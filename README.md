# Pulse HYROX (Connect IQ watch app)

Records a HYROX race or training session as a Cardio activity with one named lap per run / station.

- START: begin. LAP (BACK): end the segment, start the next (buzz). START: pause / resume. While paused, LAP opens Resume / Save / Discard.
- Race mode: the 16-segment HYROX order (Run 1, SkiErg, Run 2, Sled push, … , Wall balls). After the 16th LAP the session finishes; START saves.
- Training mode (UP/DOWN on the start screen, then START): a pick screen lists the exercises — UP/DOWN to navigate, START begins the highlighted one, START or LAP ends it and returns to the list (recording keeps running; rest time shown). On the pick screen LAP opens Resume / Save / Discard. Run is just an entry, skip it if you like.
- Each lap carries a "station" developer field, shown in Garmin Connect's lap table and read by Pulse's HYROX tab.

## Build
Needs the Connect IQ SDK and the device definition for `epix2pro47mm` (downloaded once with Garmin's SDK Manager, which requires a Garmin login).

    monkeyc -o PulseHyrox.prg -f monkey.jungle -d epix2pro47mm -y developer_key.der -w

## Install
Connect the watch by USB and copy `PulseHyrox.prg` into `GARMIN/APPS/`. It appears in the activity list as "Pulse HYROX".
