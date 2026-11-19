// Pulse HYROX — one named lap per run / station.
// Race mode: fixed 16-segment HYROX order. START begins, LAP ends the segment and starts the next.
// Training mode: pick the exercise from the list (UP/DOWN), START begins it, LAP ends it and brings the list back
// so you can pick the next one (Run is just an entry — skip it if you like). Recording keeps running between
// exercises; the transition time is shown on the pick screen. On the pick screen LAP opens Resume / Save / Discard.
// Plan mode: the week's session from your own server (setting "Plan URL"; Pulse writes it every Sunday). The app fetches it
// through the phone each time it opens and keeps the last copy, so it also works with the phone away. Steps run in order:
// LAP ends a step and starts the next, START pauses, UP/DOWN mid-step relabel the lap (skip / go back). Rest steps buzz at 0.
// Each lap carries a "station" developer field for Garmin Connect and Pulse. Records as Cardio (training load counts,
// running VO2max is untouched).
// Runs on round fēnix / epix / Enduro / MARQ / Descent, Forerunner, Instinct (1-bit screen + sub-screen) and
// Venu / vívoactive (2 buttons + touch): see HyroxView for how the layout adapts.
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
import Toybox.ActivityMonitor;
import Toybox.Communications;

const RACE = ["Run 1", "SkiErg", "Run 2", "Sled push", "Run 3", "Sled pull", "Run 4", "Burpee BJ", "Run 5", "Row", "Run 6", "Farmers", "Run 7", "Lunges", "Run 8", "Wall balls"] as Array<String>;
const STATIONS = ["SkiErg", "Sled push", "Sled pull", "Burpee BJ", "Row", "Farmers", "Lunges", "Wall balls", "Run", "Rest"] as Array<String>;
// metres per step for the step-based distance estimate in training (0 = no estimate): farmers carry, lunges, run
const STRIDE = [0.0, 0.0, 0.0, 0.0, 0.0, 0.65, 0.75, 0.0, 1.1, 0.0] as Array<Float>;

class HyroxApp extends Application.AppBase {
    var model as HyroxModel or Null = null;
    function initialize() { AppBase.initialize(); }
    function onStart(state as Dictionary or Null) as Void { fetchPlan(); }
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var m = new HyroxModel(); model = m;
        return [new HyroxView(m), new HyroxDelegate(m)];
    }
    // GET the plan JSON through the phone (Garmin Connect app); silently keeps the cached copy when there is no phone or no URL
    function fetchPlan() as Void {
        var url = Application.Properties.getValue("planUrl");
        if (!(url instanceof String) || (url as String).length() < 12) { return; }
        Communications.makeWebRequest(url as String, null, { :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON }, method(:onPlan));
    }
    function onPlan(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary) || !((data as Dictionary).get("s") instanceof Array)) { return; }
        Application.Storage.setValue("plan", data as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
        if (model != null) { (model as HyroxModel).loadPlan(); WatchUi.requestUpdate(); }
    }
}

class HyroxModel {
    var session as ActivityRecording.Session or Null = null;
    var stationField as FitContributor.Field or Null = null;
    var stationIdx as FitContributor.Field or Null = null;   // numeric twin: index into RACE (race) / STATIONS (training), +100 in training
    var stepsField as FitContributor.Field or Null = null;   // training: steps taken during the lap (watch pedometer delta)
    var estField as FitContributor.Field or Null = null;     // training: steps × stride for farmers / lunges / run, metres
    var stepsAt as Number = 0;           // pedometer reading when the current lap began
    var mode as Number = 0;              // 0 = race, 1 = training, 2 = plan (only when a plan has been downloaded)
    var plan as Dictionary or Null = null;   // {"d": date, "dl": "Sun 22 Nov", "t": title, "m": minutes, "s": [[station index, label, target, rest s], …]}
    var pos as Number = 0;               // plan: current step
    var restBuzzed as Boolean = false;
    var started as Boolean = false;      // session exists and has been started at least once
    var picking as Boolean = false;      // training: on the pick screen (before first START or after a LAP)
    var paused as Boolean = false;
    var finished as Boolean = false;
    var seg as Number = 0;               // race: index into RACE; training: exercises completed
    var pick as Number = 0;              // training: index into STATIONS
    var segStartMs as Number = 0;
    var pausedAtMs as Number = 0;
    var pausedTotalMs as Number = 0;

    function initialize() { loadPlan(); }
    function loadPlan() as Void {
        var p = Application.Storage.getValue("plan");
        plan = (p instanceof Dictionary && (p as Dictionary).get("s") instanceof Array && ((p as Dictionary).get("s") as Array).size() > 0) ? p as Dictionary : null;
        if (plan == null && mode == 2 && !started) { mode = 0; }
    }
    function nSteps() as Number { return plan == null ? 0 : ((plan as Dictionary).get("s") as Array).size(); }
    function stepAt(i as Number) as Array { return ((plan as Dictionary).get("s") as Array)[i] as Array; }
    function stepK(i as Number) as Number { var k = stepAt(i)[0]; return (k instanceof Number && k >= 0 && k < STATIONS.size()) ? k as Number : 9; }
    function stepLabel(i as Number) as String { var s = stepAt(i)[1]; return s instanceof String ? s as String : STATIONS[stepK(i)]; }
    function stepTarget(i as Number) as String { var s = stepAt(i)[2]; return s instanceof String ? s as String : ""; }
    function stepSec(i as Number) as Number { var s = stepAt(i)[3]; return s instanceof Number ? s as Number : 0; }
    function planText(k as String) as String { if (plan == null) { return ""; } var v = (plan as Dictionary).get(k); return v instanceof String ? v as String : ""; }
    function cycleMode(dir as Number) as Void { var n = plan != null ? 3 : 2; mode = (mode + dir + n) % n; }
    // plan, mid-step: UP/DOWN say "this lap is really the previous / next step" (skip a step, or go back)
    function relabel(dir as Number) as Void {
        if (mode != 2 || !started || picking || finished || paused) { return; }
        var p = pos + dir; if (p < 0 || p >= nSteps()) { return; }
        pos = p; pick = stepK(pos); restBuzzed = false; syncField();
    }
    // rest steps: two buzzes when the rest is over (the lap keeps running until LAP)
    function check() as Void {
        if (mode != 2 || !started || paused || finished || restBuzzed) { return; }
        var sec = stepSec(pos); if (sec > 0 && segMs() >= sec * 1000) { restBuzzed = true; buzz(2); }
    }
    function current() as String {
        if (mode == 0) { return seg < RACE.size() ? RACE[seg] : "Finish"; }
        return STATIONS[pick];
    }
    function ensureSession() as Void {
        if (session != null) { return; }
        // activity title in Garmin Connect / Strava (the header still shows the type, "Cardio": Connect IQ has no HYROX sport)
        session = ActivityRecording.createSession({ :name => mode == 0 ? "HYROX Race" : "HYROX Training", :sport => Activity.SPORT_TRAINING, :subSport => Activity.SUB_SPORT_CARDIO_TRAINING });
        stationField = session.createField("station", 0, FitContributor.DATA_TYPE_STRING, { :mesgType => FitContributor.MESG_TYPE_LAP, :count => 12 });
        stationIdx = session.createField("station_idx", 1, FitContributor.DATA_TYPE_UINT8, { :mesgType => FitContributor.MESG_TYPE_LAP });
        stepsField = session.createField("steps", 2, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "steps" });
        estField = session.createField("est_m", 3, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "m" });
    }
    function pedometer() as Number { var i = ActivityMonitor.getInfo(); return (i != null && i.steps != null) ? i.steps : 0; }
    function lapSteps() as Number { var d = pedometer() - stepsAt; return d < 0 ? 0 : d; }
    function stride() as Float { return (mode >= 1 && !picking) ? STRIDE[pick] : 0.0; }
    function estM() as Number { return (lapSteps() * stride()).toNumber(); }
    // setData only stages the value for the next lap write, so it is re-applied on every tick while a segment runs
    function syncField() as Void {
        if (stationField == null || finished) { return; }
        stationField.setData(picking ? "Rest" : current());
        stationIdx.setData(mode == 0 ? seg : (picking ? 109 : 100 + pick));
        stepsField.setData(lapSteps()); estField.setData(estM());
    }
    // Race: START on the start screen. Training: START on the pick screen (first exercise or a later one).
    function begin() as Void {
        var first = !started;
        ensureSession();
        if (first) { session.start(); started = true; if (mode == 2) { pos = 0; pick = stepK(0); restBuzzed = false; } }
        picking = false;
        segStartMs = System.getTimer(); pausedTotalMs = 0; stepsAt = pedometer();
        syncField();
        buzz(1);
    }
    function lap() as Void {
        if (!started || paused || finished || picking) { return; }
        session.addLap();
        seg += 1;
        if (mode == 0) {
            if (seg >= RACE.size()) { finished = true; buzz(3); session.stop(); return; }
            segStartMs = System.getTimer(); pausedTotalMs = 0; stepsAt = pedometer();
            syncField();
            buzz(1);
        } else if (mode == 2) {                             // plan: straight into the next step
            pos += 1;
            if (pos >= nSteps()) { finished = true; buzz(3); session.stop(); return; }
            pick = stepK(pos); restBuzzed = false;
            segStartMs = System.getTimer(); pausedTotalMs = 0; stepsAt = pedometer();
            syncField();
            buzz(1);
        } else {
            picking = true;                                 // back to the list; transition time runs from here
            segStartMs = System.getTimer(); pausedTotalMs = 0; stepsAt = pedometer();
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


// Font ladders, largest first: each text row uses the first font that fits the round screen at that height.
const F_TITLE = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;
const F_MED = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;
const F_SMALL = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;
const F_TINY = [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;
const F_NUM = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE] as Array<Graphics.FontDefinition>;

// true on 5-button watches (fēnix, epix, Forerunner, Instinct…); false on Venu / vívoactive, which have only START and
// BACK — there UP/DOWN come from vertical swipes and a tap acts as START on the start and pick screens.
function hasUpDown() as Boolean {
    var s = System.getDeviceSettings();
    if (s has :inputButtons) {
        var need = System.BUTTON_INPUT_UP | System.BUTTON_INPUT_DOWN;
        return (s.inputButtons & need) == need;
    }
    return true;
}

class HyroxView extends WatchUi.View {
    // Works on any round screen (218–454 px). Rows are placed as fractions of the height; each row picks the largest font
    // whose text fits the circle's chord at that height (and stays left of the Instinct sub-screen). Button help is a
    // coloured arc at each physical button (START 30°, LAP −30°, UP 150°, DOWN 210°) with a one-word label beside it.
    var m as HyroxModel;
    var timer as Timer.Timer;
    var zones as Array<Number> or Null = null;
    var upDown as Boolean;
    var w as Number = 0; var h as Number = 0; var cx as Number = 0; var cy as Number = 0; var pen as Number = 5;
    var sub as Graphics.BoundingBox or Null = null;        // Instinct sub-screen (the small round window), if any
    var labels as Boolean = true;                          // button-hint words (screens under 200 px get the arcs only)
    var ri as Number = 0; var lblH as Number = 0;          // hint-label radius and height
    var res as Array<Number> = [0, 0, 0, 0] as Array<Number>; // width of the hint word on this screen at START, LAP, UP, DOWN (0 = none)

    function initialize(model as HyroxModel) {
        View.initialize(); m = model; timer = new Timer.Timer(); upDown = hasUpDown();
        try { zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC); } catch (e) { zones = null; }
    }
    function onLayout(dc as Graphics.Dc) as Void {
        w = dc.getWidth(); h = dc.getHeight(); cx = w / 2; cy = h / 2;
        pen = w / 80; if (pen < 3) { pen = 3; }
        if (WatchUi has :getSubscreen) { sub = WatchUi.getSubscreen(); }
        labels = w >= 200;
        ri = cx - pen / 2 - 1 - pen - 6;
        lblH = dc.getFontHeight(Graphics.FONT_XTINY);
    }
    function onShow() as Void { timer.start(method(:tick), 250, true); }
    function onHide() as Void { timer.stop(); }
    function tick() as Void { m.syncField(); m.check(); WatchUi.requestUpdate(); }
    function fmt(ms as Number) as String {
        var s = ms / 1000; var hh = s / 3600; var mm = (s % 3600) / 60; var ss = s % 60;
        return hh > 0 ? hh.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d") : mm.format("%d") + ":" + ss.format("%02d");
    }
    function hrColor(hr as Number or Null) as Number {
        if (hr == null || zones == null || zones.size() < 6) { return Graphics.COLOR_LT_GRAY; }
        if (hr >= zones[4]) { return Graphics.COLOR_RED; }
        if (hr >= zones[3]) { return Graphics.COLOR_ORANGE; }
        if (hr >= zones[2]) { return Graphics.COLOR_GREEN; }
        if (hr >= zones[1]) { return Graphics.COLOR_BLUE; }
        return Graphics.COLOR_LT_GRAY;
    }
    // colour on colour screens; on 1-bit screens (Instinct) everything that is not black is drawn white
    (:color) function setC(dc as Graphics.Dc, c as Number) as Void { dc.setColor(c, Graphics.COLOR_TRANSPARENT); }
    (:mono) function setC(dc as Graphics.Dc, c as Number) as Void { dc.setColor(c == Graphics.COLOR_BLACK ? c : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT); }

    // horizontal span [left, right] usable for text whose cell starts at y0 and is fh tall
    function spanAt(y0 as Number, fh as Number) as Array<Number> {
        var top = y0 + fh * 0.18, bot = y0 + fh * 0.82;     // font cells carry padding above / below the glyphs
        var d = (top - cy).abs(); var d2 = (bot - cy).abs(); if (d2 > d) { d = d2; }
        var r = cx.toFloat(), half = 0.0;
        if (d < r) { half = Math.sqrt(r * r - d * d) * 0.92; }
        var l = cx - half, rt = cx + half;
        if (labels) {                                     // keep clear of this screen's hint words (upper row: START / UP, lower: LAP / DOWN)
            var ly = ri / 2, ex = ri * 0.866;
            for (var k = 0; k < 2; k++) {
                var yc = k == 0 ? cy - ly : cy + ly;
                if (top < yc + lblH / 2 && bot > yc - lblH / 2) {
                    var wr = res[k], wl = res[k + 2];
                    if (wr > 0 && rt > cx + ex - wr - 4) { rt = cx + ex - wr - 4; }
                    if (wl > 0 && l < cx - ex + wl + 4) { l = cx - ex + wl + 4; }
                }
            }
        }
        if (sub != null && top < sub.y + sub.height && bot > sub.y && rt > sub.x - 3) { rt = (sub.x - 3).toFloat(); }
        return [l.toNumber(), rt.toNumber()] as Array<Number>;
    }
    // draws text centred in that span with the first font from `fonts` that fits (the last one is used regardless)
    function row(dc as Graphics.Dc, yf as Float, text as String, fonts as Array<Graphics.FontDefinition>, color as Number, maxHf as Float) as Void {
        rowAlt(dc, yf, [text] as Array<String>, fonts, color, maxHf);
    }
    // same with shorter wordings: each one is tried in every font before falling back to the next
    function rowAlt(dc as Graphics.Dc, yf as Float, texts as Array<String>, fonts as Array<Graphics.FontDefinition>, color as Number, maxHf as Float) as Void {
        var y0 = (h * yf).toNumber(), maxH = h * maxHf, n = fonts.size();
        for (var t = 0; t < texts.size(); t++) {
            for (var i = 0; i < n; i++) {
                var f = fonts[i], fh = dc.getFontHeight(f);
                var last = i == n - 1 && t == texts.size() - 1;
                if (fh > maxH && !last) { continue; }
                var sp = spanAt(y0, fh);
                if (dc.getTextWidthInPixels(texts[t], f) <= sp[1] - sp[0] || last) {
                    setC(dc, color);
                    dc.drawText((sp[0] + sp[1]) / 2, y0, f, texts[t], Graphics.TEXT_JUSTIFY_CENTER);
                    return;
                }
            }
        }
    }
    // same, but for a cell centred at x with a fixed width (the HR / lap pair)
    function cell(dc as Graphics.Dc, x as Number, yf as Float, maxW as Number, text as String, color as Number) as Void {
        var f = Graphics.FONT_XTINY;
        for (var i = 0; i < F_MED.size(); i++) { if (dc.getTextWidthInPixels(text, F_MED[i]) <= maxW) { f = F_MED[i]; break; } }
        setC(dc, color);
        dc.drawText(x, (h * yf).toNumber(), f, text, Graphics.TEXT_JUSTIFY_CENTER);
    }
    // Button hints for the screen: [START word, START colour, LAP word, LAP colour, UP word, DOWN word] ("" = none).
    // Reserves the words' widths first so the text rows keep clear of them, then hints() draws them last.
    function plan(dc as Graphics.Dc, start as String, lap as String, up as String, down as String) as Void {
        var words = [start, lap, up, down] as Array<String>;
        for (var i = 0; i < 4; i++) {
            var on = labels && words[i].length() > 0 && (i < 2 || upDown);
            res[i] = on ? dc.getTextWidthInPixels(words[i], Graphics.FONT_XTINY) : 0;
        }
    }
    function hints(dc as Graphics.Dc, start as String, sc as Number, lap as String, lc as Number, up as String, down as String) as Void {
        if (start.length() > 0) { hint(dc, 30, start, sc); }
        if (lap.length() > 0) { hint(dc, -30, lap, lc); }
        if (up.length() > 0) { hint(dc, 150, up, Graphics.COLOR_DK_GRAY); }
        if (down.length() > 0) { hint(dc, 210, down, Graphics.COLOR_DK_GRAY); }
    }
    // arc + label at a button. deg: 30 START, -30 LAP, 150 UP, 210 DOWN (0° = 3 o'clock, counter-clockwise).
    // UP / DOWN hints are skipped on watches without those buttons.
    function hint(dc as Graphics.Dc, deg as Number, label as String, color as Number) as Void {
        if ((deg == 150 || deg == 210) && !upDown) { return; }
        var r = cx - pen / 2 - 1;
        setC(dc, color);
        dc.setPenWidth(color == Graphics.COLOR_DK_GRAY ? (pen + 1) / 2 : pen);   // thinner when dim (mono shows no grey)
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, deg - 9, deg + 9);
        if (!labels) { return; }
        var rad = deg * Math.PI / 180.0;
        var tx = cx + ri * Math.cos(rad), ty = cy - ri * Math.sin(rad);
        var just = (deg > 90 && deg < 270) ? Graphics.TEXT_JUSTIFY_LEFT : Graphics.TEXT_JUSTIFY_RIGHT;
        dc.drawText(tx, ty, Graphics.FONT_XTINY, label, just | Graphics.TEXT_JUSTIFY_VCENTER);
    }
    // Instinct: live HR in the sub-screen once recording
    function drawSub(dc as Graphics.Dc) as Void {
        if (sub == null || !m.started) { return; }
        var s = sub as Graphics.BoundingBox;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK); dc.fillRectangle(s.x, s.y, s.width, s.height);
        var hr = m.hr();
        var t = hr != null ? hr.format("%d") : "--";
        var f = dc.getTextWidthInPixels(t, Graphics.FONT_NUMBER_MILD) <= s.width - 8 ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_SMALL;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s.x + s.width / 2, s.y + s.height / 2, f, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
    function onUpdate(dc as Graphics.Dc) as Void {
        var G = Graphics.COLOR_GREEN, O = Graphics.COLOR_ORANGE, D = Graphics.COLOR_DK_GRAY, L = Graphics.COLOR_LT_GRAY, W = Graphics.COLOR_WHITE;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK); dc.clear();
        if (!m.started && !m.picking) {                       // start screen: choose mode
            var go = m.mode == 1 ? "pick" : "go";
            plan(dc, go, "exit", "mode", "mode");
            rowAlt(dc, 0.11, ["PULSE HYROX", "HYROX"] as Array<String>, F_TINY, O, 0.13);
            row(dc, 0.24, m.mode == 0 ? "Race" : m.mode == 1 ? "Training" : "Plan", F_TITLE, W, 0.22);
            if (m.mode == 2) {
                var dl = m.planText("dl"), n = m.nSteps().format("%d");
                rowAlt(dc, 0.47, [m.planText("t"), "this week's plan"] as Array<String>, F_TINY, W, 0.09);
                rowAlt(dc, 0.56, [dl + " · " + n + " steps", n + " steps"] as Array<String>, F_TINY, L, 0.09);
            } else {
                row(dc, 0.47, m.mode == 0 ? "16 segments, fixed order" : "pick each exercise", F_TINY, L, 0.09);
                row(dc, 0.56, m.mode == 0 ? "LAP ends each one" : "START or LAP ends it", F_TINY, L, 0.09);
            }
            if (!upDown) { rowAlt(dc, 0.66, ["swipe to change mode", "swipe for mode"] as Array<String>, F_TINY, L, 0.10); }
            hints(dc, go, G, "exit", D, "mode", "mode");
            return;
        }
        if (m.picking) {                                      // training: pick the next exercise
            var n = STATIONS.size();
            var back = m.started ? "menu" : "back";
            plan(dc, "go", back, "up", "down");
            row(dc, 0.13, m.started ? "NEXT · " + (m.seg + 1).format("%d") : "FIRST", F_SMALL, O, 0.15);
            row(dc, 0.27, STATIONS[(m.pick + n - 1) % n], F_SMALL, D, 0.13);
            row(dc, 0.38, STATIONS[m.pick], F_TITLE, W, 0.19);
            row(dc, 0.54, STATIONS[(m.pick + 1) % n], F_SMALL, D, 0.13);
            if (m.started) {
                row(dc, 0.66, "rest " + fmt(m.segMs()), F_TINY, L, 0.085);
                row(dc, 0.74, "total " + fmt(m.totalMs()), F_TINY, L, 0.085);
            } else if (!upDown) {
                row(dc, 0.68, "swipe to choose", F_TINY, L, 0.10);
            }
            hints(dc, "go", G, back, m.started ? O : D, "up", "down");
            drawSub(dc);
            return;
        }
        // in an exercise / race segment: name, segment time (big), total time, HR (zone colour), lap number
        var hs = "done", hsc = G, hl = "done", hlc = G;
        if (m.finished) { hs = "save"; hl = ""; }
        else if (m.paused) { hs = "resume"; hl = "menu"; hlc = O; }
        else if (m.mode != 1) { hs = "pause"; hsc = D; hl = "next"; }
        var pu = "", pd = "";
        if (m.mode == 2 && !m.finished && !m.paused) { pu = m.pos > 0 ? "prev" : ""; pd = m.pos + 1 < m.nSteps() ? "skip" : ""; }
        plan(dc, hs, hl, pu, pd);
        if (m.finished || m.paused || m.mode != 2) {
            row(dc, 0.15, m.finished ? "FINISHED" : (m.paused ? "PAUSED" : m.current().toUpper()), F_MED, m.paused ? Graphics.COLOR_YELLOW : O, 0.14);
        } else {
            rowAlt(dc, 0.15, [m.stepLabel(m.pos).toUpper(), m.current().toUpper()] as Array<String>, F_MED, O, 0.14);
        }
        row(dc, 0.27, fmt(m.segMs()), F_NUM, W, 0.32);
        row(dc, 0.56, "total " + fmt(m.totalMs()), F_SMALL, L, 0.12);
        var hr = m.hr();
        var lapTxt = m.mode == 0 ? (m.seg + 1).format("%d") + "/16" : m.mode == 2 ? (m.pos + 1).format("%d") + "/" + m.nSteps().format("%d") : "#" + (m.seg + 1).format("%d");
        var sp = spanAt((h * 0.67).toNumber(), dc.getFontHeight(Graphics.FONT_MEDIUM)), cw = (sp[1] - sp[0]) / 2 - 6;
        cell(dc, (sp[0] + cx) / 2 + 2, 0.67, cw, hr != null ? hr.format("%d") : "--", hrColor(hr));
        cell(dc, (cx + sp[1]) / 2 - 2, 0.67, cw, lapTxt, L);
        if (m.mode == 2 && !m.finished && !m.paused) {
            var sec = m.stepSec(m.pos), tg = m.stepTarget(m.pos);
            if (sec > 0) {
                var left = sec * 1000 - m.segMs();
                row(dc, 0.79, left > 0 ? "rest " + fmt(left + 999) : "go: " + (m.pos + 1 < m.nSteps() ? m.stepLabel(m.pos + 1) : "last"), F_TINY, left > 0 ? L : G, 0.10);
            } else if (tg.length() > 0) {
                row(dc, 0.79, tg, F_TINY, L, 0.10);
            } else if (m.pos + 1 < m.nSteps()) {
                row(dc, 0.79, "next " + m.stepLabel(m.pos + 1), F_TINY, D, 0.10);
            }
        } else if (m.mode == 0 && !m.finished && !m.paused && m.seg + 1 < RACE.size()) {
            row(dc, 0.79, "next " + RACE[m.seg + 1], F_TINY, D, 0.10);
        } else if (m.mode == 1 && !m.finished && m.stride() > 0) {
            var em = "~" + m.estM().format("%d") + " m", st = m.lapSteps().format("%d");
            rowAlt(dc, 0.79, [em + " · " + st + " steps", em + " · " + st, em] as Array<String>, F_TINY, L, 0.10);
        }
        hints(dc, hs, hsc, hl, hlc, pu, pd);
        drawSub(dc);
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
            if (m.mode == 1) { m.picking = true; } else { m.begin(); }
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
    function onPreviousPage() as Boolean {                 // UP (or swipe down)
        if (m.picking) { m.pick = (m.pick + STATIONS.size() - 1) % STATIONS.size(); }
        else if (!m.started) { m.cycleMode(-1); }
        else { m.relabel(-1); }
        WatchUi.requestUpdate(); return true;
    }
    function onNextPage() as Boolean {                     // DOWN (or swipe up)
        if (m.picking) { m.pick = (m.pick + 1) % STATIONS.size(); }
        else if (!m.started) { m.cycleMode(1); }
        else { m.relabel(1); }
        WatchUi.requestUpdate(); return true;
    }
    // Touchscreens: vertical swipes scroll; sideways swipes are swallowed so a sweaty wrist can't end a lap (the default
    // maps swipe-right to BACK = LAP). A tap acts as START only on the start and pick screens, never mid-exercise.
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { return onNextPage(); }
        if (d == WatchUi.SWIPE_DOWN) { return onPreviousPage(); }
        return true;
    }
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (!hasUpDown() && (!m.started || m.picking)) { return onSelect(); }
        return true;
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
