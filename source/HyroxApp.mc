// Pulse HYROX — one named lap per run / station.
// Race mode: fixed 16-segment HYROX order. START begins, LAP ends the segment and starts the next.
// Training mode: pick the exercise from the list (UP/DOWN), START begins it, LAP ends it and brings the list back
// so you can pick the next one (Run is just an entry — skip it if you like). Recording keeps running between
// exercises; the transition time is shown on the pick screen. On the pick screen LAP opens Resume / Save / Discard.
// Each lap carries a "station" developer field for Garmin Connect and Pulse. Records as Cardio (training load counts,
// running VO2max is untouched).
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Timer;
import Toybox.Attention;
import Toybox.System;
import Toybox.Graphics;
import Toybox.Math;
import Toybox.UserProfile;

const RACE = ["Run 1", "SkiErg", "Run 2", "Sled push", "Run 3", "Sled pull", "Run 4", "Burpee BJ", "Run 5", "Row", "Run 6", "Farmers", "Run 7", "Lunges", "Run 8", "Wall balls"] as Array<String>;
const STATIONS = ["SkiErg", "Sled push", "Sled pull", "Burpee BJ", "Row", "Farmers", "Lunges", "Wall balls", "Run", "Rest"] as Array<String>;

class HyroxApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var m = new HyroxModel();
        return [new HyroxView(m), new HyroxDelegate(m)];
    }
}

class HyroxModel {
    var session as ActivityRecording.Session or Null = null;
    var stationField as FitContributor.Field or Null = null;
    var stationIdx as FitContributor.Field or Null = null;   // numeric twin: index into RACE (race) / STATIONS (training), +100 in training
    var mode as Number = 0;              // 0 = race, 1 = training
    var started as Boolean = false;      // session exists and has been started at least once
    var picking as Boolean = false;      // training: on the pick screen (before first START or after a LAP)
    var paused as Boolean = false;
    var finished as Boolean = false;
    var seg as Number = 0;               // race: index into RACE; training: exercises completed
    var pick as Number = 0;              // training: index into STATIONS
    var segStartMs as Number = 0;
    var pausedAtMs as Number = 0;
    var pausedTotalMs as Number = 0;

    function current() as String {
        if (mode == 0) { return seg < RACE.size() ? RACE[seg] : "Finish"; }
        return STATIONS[pick];
    }
    function ensureSession() as Void {
        if (session != null) { return; }
        session = ActivityRecording.createSession({ :name => "HYROX", :sport => Activity.SPORT_TRAINING, :subSport => Activity.SUB_SPORT_CARDIO_TRAINING });
        stationField = session.createField("station", 0, FitContributor.DATA_TYPE_STRING, { :mesgType => FitContributor.MESG_TYPE_LAP, :count => 12 });
        stationIdx = session.createField("station_idx", 1, FitContributor.DATA_TYPE_UINT8, { :mesgType => FitContributor.MESG_TYPE_LAP });
    }
    // setData only stages the value for the next lap write, so it is re-applied on every tick while a segment runs
    function syncField() as Void {
        if (stationField == null || finished) { return; }
        stationField.setData(picking ? "Rest" : current());
        stationIdx.setData(mode == 0 ? seg : (picking ? 109 : 100 + pick));
    }
    // Race: START on the start screen. Training: START on the pick screen (first exercise or a later one).
    function begin() as Void {
        var first = !started;
        ensureSession();
        if (first) { session.start(); started = true; }
        picking = false;
        segStartMs = System.getTimer(); pausedTotalMs = 0;
        syncField();
        buzz(1);
    }
    function lap() as Void {
        if (!started || paused || finished || picking) { return; }
        session.addLap();
        seg += 1;
        if (mode == 0) {
            if (seg >= RACE.size()) { finished = true; buzz(3); session.stop(); return; }
            segStartMs = System.getTimer(); pausedTotalMs = 0;
            syncField();
            buzz(1);
        } else {
            picking = true;                                 // back to the list; transition time runs from here
            segStartMs = System.getTimer(); pausedTotalMs = 0;
            pick = (pick + 1) % STATIONS.size();            // suggest the next entry in the list
            syncField();
            buzz(1);
        }
    }
    function togglePause() as Void {
        if (!started || finished) { return; }
        if (paused) { session.start(); pausedTotalMs += System.getTimer() - pausedAtMs; paused = false; }
        else { session.stop(); pausedAtMs = System.getTimer(); paused = true; }
        buzz(1);
    }
    function save() as Void { if (session != null) { if (session.isRecording()) { session.stop(); } session.save(); session = null; } }
    function discard() as Void { if (session != null) { if (session.isRecording()) { session.stop(); } session.discard(); session = null; } }
    function segMs() as Number {
        if (!started) { return 0; }
        var now = paused ? pausedAtMs : System.getTimer();
        return now - segStartMs - pausedTotalMs;
    }
    function totalMs() as Number {
        var info = Activity.getActivityInfo();
        return (info != null && info.timerTime != null) ? info.timerTime : 0;
    }
    function hr() as Number or Null { var info = Activity.getActivityInfo(); return info != null ? info.currentHeartRate : null; }
    function buzz(n as Number) as Void {
        if (Attention has :vibrate) {
            var v = [] as Array<Attention.VibeProfile>;
            for (var i = 0; i < n; i++) { v.add(new Attention.VibeProfile(80, 180)); if (i < n - 1) { v.add(new Attention.VibeProfile(0, 120)); } }
            Attention.vibrate(v);
        }
    }
}

class HyroxView extends WatchUi.View {
    // Round 416 px display: everything is placed on chords that fit the circle, and button help is drawn as a coloured
    // arc at each physical button (START 30°, LAP −30°, UP 150°, DOWN 210°) with a one-word label beside it.
    var m as HyroxModel;
    var timer as Timer.Timer;
    var zones as Array<Number> or Null = null;
    function initialize(model as HyroxModel) {
        View.initialize(); m = model; timer = new Timer.Timer();
        try { zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC); } catch (e) { zones = null; }
    }
    function onShow() as Void { timer.start(method(:tick), 250, true); }
    function onHide() as Void { timer.stop(); }
    function tick() as Void { m.syncField(); WatchUi.requestUpdate(); }
    function fmt(ms as Number) as String {
        var s = ms / 1000; var h = s / 3600; var mm = (s % 3600) / 60; var ss = s % 60;
        return h > 0 ? h.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d") : mm.format("%d") + ":" + ss.format("%02d");
    }
    function hrColor(hr as Number or Null) as Number {
        if (hr == null || zones == null || zones.size() < 6) { return Graphics.COLOR_LT_GRAY; }
        if (hr >= zones[4]) { return Graphics.COLOR_RED; }
        if (hr >= zones[3]) { return Graphics.COLOR_ORANGE; }
        if (hr >= zones[2]) { return Graphics.COLOR_GREEN; }
        if (hr >= zones[1]) { return Graphics.COLOR_BLUE; }
        return Graphics.COLOR_LT_GRAY;
    }
    // arc + label at a button. deg: 30 START, -30 LAP, 150 UP, 210 DOWN (0° = 3 o'clock, counter-clockwise)
    function hint(dc as Graphics.Dc, deg as Number, label as String, color as Number) as Void {
        var w = dc.getWidth(), cx = w / 2, cy = dc.getHeight() / 2, r = cx - 3;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT); dc.setPenWidth(5);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, deg - 9, deg + 9);
        var rad = deg * Math.PI / 180.0, tx = cx + (r - 14) * Math.cos(rad), ty = cy - (r - 14) * Math.sin(rad);
        var just = (deg > 90 && deg < 270) ? Graphics.TEXT_JUSTIFY_LEFT : Graphics.TEXT_JUSTIFY_RIGHT;
        dc.drawText(tx, ty, Graphics.FONT_XTINY, label, just | Graphics.TEXT_JUSTIFY_VCENTER);
    }
    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var G = Graphics.COLOR_GREEN, O = Graphics.COLOR_ORANGE, D = Graphics.COLOR_DK_GRAY, L = Graphics.COLOR_LT_GRAY;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK); dc.clear();
        if (!m.started && !m.picking) {                       // start screen: choose mode (rows 0.27 / 0.73 hold the button labels)
            dc.setColor(O, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.11, Graphics.FONT_TINY, "PULSE HYROX", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.24, Graphics.FONT_LARGE, m.mode == 0 ? "Race" : "Training", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(L, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.47, Graphics.FONT_TINY, m.mode == 0 ? "16 segments, fixed order" : "pick each exercise", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.56, Graphics.FONT_TINY, m.mode == 0 ? "LAP ends each one" : "START or LAP ends it", Graphics.TEXT_JUSTIFY_CENTER);
            hint(dc, 30, m.mode == 0 ? "go" : "pick", G); hint(dc, 150, "mode", D); hint(dc, 210, "mode", D); hint(dc, -30, "exit", D);
            return;
        }
        if (m.picking) {                                      // training: pick the next exercise
            var n = STATIONS.size();
            dc.setColor(O, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.13, Graphics.FONT_SMALL, m.started ? "NEXT · " + (m.seg + 1).format("%d") : "FIRST", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(D, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.27, Graphics.FONT_SMALL, STATIONS[(m.pick + n - 1) % n], Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.38, Graphics.FONT_LARGE, STATIONS[m.pick], Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(D, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.54, Graphics.FONT_SMALL, STATIONS[(m.pick + 1) % n], Graphics.TEXT_JUSTIFY_CENTER);
            if (m.started) {
                dc.setColor(L, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.66, Graphics.FONT_TINY, "rest " + fmt(m.segMs()), Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, h * 0.74, Graphics.FONT_TINY, "total " + fmt(m.totalMs()), Graphics.TEXT_JUSTIFY_CENTER);
            }
            hint(dc, 30, "go", G); hint(dc, 150, "up", D); hint(dc, 210, "down", D); hint(dc, -30, m.started ? "menu" : "back", m.started ? O : D);
            return;
        }
        // in an exercise / race segment: name, segment time (big), total time, HR (zone colour), lap number
        dc.setColor(m.paused ? Graphics.COLOR_YELLOW : O, Graphics.COLOR_TRANSPARENT);
        var title = m.finished ? "FINISHED" : (m.paused ? "PAUSED" : m.current().toUpper());
        dc.drawText(cx, h * 0.15, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.27, Graphics.FONT_NUMBER_THAI_HOT, fmt(m.segMs()), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(L, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.56, Graphics.FONT_SMALL, "total " + fmt(m.totalMs()), Graphics.TEXT_JUSTIFY_CENTER);
        var hr = m.hr();
        dc.setColor(hrColor(hr), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 0.14, h * 0.67, Graphics.FONT_MEDIUM, hr != null ? hr.format("%d") : "--", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(L, Graphics.COLOR_TRANSPARENT);
        var lapTxt = m.mode == 0 ? (m.seg + 1).format("%d") + "/16" : "#" + (m.seg + 1).format("%d");
        dc.drawText(cx + w * 0.16, h * 0.67, Graphics.FONT_MEDIUM, lapTxt, Graphics.TEXT_JUSTIFY_CENTER);
        if (m.mode == 0 && !m.finished && !m.paused && m.seg + 1 < RACE.size()) {
            dc.setColor(D, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.79, Graphics.FONT_TINY, "next " + RACE[m.seg + 1], Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (m.finished) { hint(dc, 30, "save", G); }
        else if (m.paused) { hint(dc, 30, "resume", G); hint(dc, -30, "menu", O); }
        else if (m.mode == 0) { hint(dc, 30, "pause", D); hint(dc, -30, "next", G); }
        else { hint(dc, 30, "done", G); hint(dc, -30, "done", G); }
    }
}

class HyroxDelegate extends WatchUi.BehaviorDelegate {
    var m as HyroxModel;
    function initialize(model as HyroxModel) { BehaviorDelegate.initialize(); m = model; }
    function pauseMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "HYROX" });
        menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
        menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(m), WatchUi.SLIDE_UP);
    }
    function onSelect() as Boolean {                       // START / ENTER
        if (!m.started && !m.picking) {                    // start screen
            if (m.mode == 0) { m.begin(); } else { m.picking = true; }
        }
        else if (m.picking) { m.begin(); }                 // chosen exercise starts
        else if (m.finished) { m.save(); System.exit(); }
        else if (m.mode == 1 && !m.paused) { m.lap(); }     // training: START also ends the exercise → list
        else { m.togglePause(); }
        WatchUi.requestUpdate(); return true;
    }
    function onBack() as Boolean {                         // LAP / BACK
        if (!m.started) {                                  // pre-start pick screen → start screen; start screen → exit
            if (m.picking) { m.picking = false; WatchUi.requestUpdate(); return true; }
            System.exit();
        }
        if (m.paused || m.picking) { pauseMenu(); return true; }   // Resume / Save / Discard
        m.lap(); WatchUi.requestUpdate(); return true;
    }
    function onPreviousPage() as Boolean {                 // UP
        if (m.picking) { m.pick = (m.pick + STATIONS.size() - 1) % STATIONS.size(); }
        else if (!m.started) { m.mode = m.mode == 0 ? 1 : 0; }
        WatchUi.requestUpdate(); return true;
    }
    function onNextPage() as Boolean {                     // DOWN
        if (m.picking) { m.pick = (m.pick + 1) % STATIONS.size(); }
        else if (!m.started) { m.mode = m.mode == 0 ? 1 : 0; }
        WatchUi.requestUpdate(); return true;
    }
}

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {
    var m as HyroxModel;
    function initialize(model as HyroxModel) { Menu2InputDelegate.initialize(); m = model; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :save) { m.save(); System.exit(); }
        else if (id == :discard) { m.discard(); System.exit(); }
        else { WatchUi.popView(WatchUi.SLIDE_DOWN); if (m.paused) { m.togglePause(); } }
    }
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_DOWN); }
}
