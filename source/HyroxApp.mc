// Pulse HYROX — one named lap per run / station. START begins, LAP (BACK) ends the current segment and starts the next,
// START again pauses/resumes, long-hold BACK while paused saves. Race mode follows the 16-segment HYROX format; Training mode
// lets you pick the next station with UP/DOWN before each LAP. Each lap carries a "station" developer field for Garmin Connect
// and Pulse. Records as Cardio (training load counts, running VO2max is untouched).
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

const RACE = ["Run 1", "SkiErg", "Run 2", "Sled push", "Run 3", "Sled pull", "Run 4", "Burpee BJ", "Run 5", "Row", "Run 6", "Farmers", "Run 7", "Lunges", "Run 8", "Wall balls"] as Array<String>;
const STATIONS = ["Run", "SkiErg", "Sled push", "Sled pull", "Burpee BJ", "Row", "Farmers", "Lunges", "Wall balls", "Rest"] as Array<String>;

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
    var mode as Number = 0;              // 0 = race, 1 = training
    var started as Boolean = false;
    var paused as Boolean = false;
    var finished as Boolean = false;
    var seg as Number = 0;               // index into RACE, or lap count in training
    var pick as Number = 0;              // training: index into STATIONS for the segment in progress
    var segStartMs as Number = 0;
    var pausedAtMs as Number = 0;
    var pausedTotalMs as Number = 0;

    function current() as String {
        if (mode == 0) { return seg < RACE.size() ? RACE[seg] : "Finish"; }
        return STATIONS[pick];
    }
    function start() as Void {
        session = ActivityRecording.createSession({ :name => "HYROX", :sport => Activity.SPORT_TRAINING, :subSport => Activity.SUB_SPORT_CARDIO_TRAINING });
        stationField = session.createField("station", 0, FitContributor.DATA_TYPE_STRING, { :mesgType => FitContributor.MESG_TYPE_LAP, :count => 12 });
        session.start(); started = true; segStartMs = System.getTimer(); pausedTotalMs = 0;
        stationField.setData(current());
        buzz(1);
    }
    function lap() as Void {
        if (!started || paused || finished) { return; }
        session.addLap();
        if (mode == 0) {
            seg += 1;
            if (seg >= RACE.size()) { finished = true; buzz(3); session.stop(); return; }
        } else { seg += 1; }
        segStartMs = System.getTimer(); pausedTotalMs = 0;
        stationField.setData(current());
        buzz(1);
    }
    function togglePause() as Void {
        if (!started || finished) { return; }
        if (paused) { session.start(); pausedTotalMs += System.getTimer() - pausedAtMs; paused = false; }
        else { session.stop(); pausedAtMs = System.getTimer(); paused = true; }
        buzz(1);
    }
    function save() as Void { if (session != null) { session.save(); session = null; } }
    function discard() as Void { if (session != null) { session.discard(); session = null; } }
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
    var m as HyroxModel;
    var timer as Timer.Timer;
    function initialize(model as HyroxModel) { View.initialize(); m = model; timer = new Timer.Timer(); }
    function onShow() as Void { timer.start(method(:tick), 250, true); }
    function onHide() as Void { timer.stop(); }
    function tick() as Void { WatchUi.requestUpdate(); }
    function fmt(ms as Number) as String {
        var s = ms / 1000; var h = s / 3600; var mm = (s % 3600) / 60; var ss = s % 60;
        return h > 0 ? h.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d") : mm.format("%d") + ":" + ss.format("%02d");
    }
    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK); dc.clear();
        if (!m.started) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.22, Graphics.FONT_SMALL, "PULSE HYROX", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.40, Graphics.FONT_LARGE, m.mode == 0 ? "Race" : "Training", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.58, Graphics.FONT_TINY, "UP/DOWN: mode", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.68, Graphics.FONT_TINY, "START: go  ·  LAP: next", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        // in session: segment name, segment time (big), total time, HR, lap number
        dc.setColor(m.paused ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        var title = m.finished ? "FINISHED" : (m.paused ? "PAUSED · " + m.current() : m.current().toUpper());
        dc.drawText(cx, h * 0.16, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.30, Graphics.FONT_NUMBER_THAI_HOT, fmt(m.segMs()), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.60, Graphics.FONT_SMALL, "total " + fmt(m.totalMs()), Graphics.TEXT_JUSTIFY_CENTER);
        var hr = m.hr();
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 0.18, h * 0.72, Graphics.FONT_MEDIUM, hr != null ? hr.format("%d") : "--", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var lapTxt = m.mode == 0 ? (m.seg + 1).format("%d") + "/16" : "lap " + (m.seg + 1).format("%d");
        dc.drawText(cx + w * 0.18, h * 0.72, Graphics.FONT_MEDIUM, lapTxt, Graphics.TEXT_JUSTIFY_CENTER);
        if (m.mode == 0 && !m.finished && m.seg + 1 < RACE.size()) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.85, Graphics.FONT_TINY, "next: " + RACE[m.seg + 1], Graphics.TEXT_JUSTIFY_CENTER);
        } else if (m.mode == 1 && !m.finished) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.85, Graphics.FONT_TINY, "UP/DOWN: station", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (m.finished || m.paused) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.85, Graphics.FONT_TINY, m.finished ? "START: save" : "START: resume · LAP: save/discard", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class HyroxDelegate extends WatchUi.BehaviorDelegate {
    var m as HyroxModel;
    function initialize(model as HyroxModel) { BehaviorDelegate.initialize(); m = model; }
    function onSelect() as Boolean {                       // START / ENTER
        if (!m.started) { m.start(); }
        else if (m.finished) { m.save(); System.exit(); }
        else { m.togglePause(); }
        WatchUi.requestUpdate(); return true;
    }
    function onBack() as Boolean {                         // LAP / BACK
        if (!m.started) { System.exit(); return true; }
        if (m.paused) {                                    // paused: LAP opens Resume / Save / Discard
            var menu = new WatchUi.Menu2({ :title => "HYROX" });
            menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
            menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
            menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
            WatchUi.pushView(menu, new PauseMenuDelegate(m), WatchUi.SLIDE_UP); return true;
        }
        m.lap(); WatchUi.requestUpdate(); return true;
    }
    function onPreviousPage() as Boolean {                 // UP
        if (!m.started) { m.mode = m.mode == 0 ? 1 : 0; }
        else if (m.mode == 1 && !m.finished) { m.pick = (m.pick + STATIONS.size() - 1) % STATIONS.size(); m.stationField.setData(m.current()); }
        WatchUi.requestUpdate(); return true;
    }
    function onNextPage() as Boolean {                     // DOWN
        if (!m.started) { m.mode = m.mode == 0 ? 1 : 0; }
        else if (m.mode == 1 && !m.finished) { m.pick = (m.pick + 1) % STATIONS.size(); m.stationField.setData(m.current()); }
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
        else { WatchUi.popView(WatchUi.SLIDE_DOWN); m.togglePause(); }
    }
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_DOWN); }
}
