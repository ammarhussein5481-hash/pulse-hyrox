# Pulse HYROX — Connect IQ watch app

Records a HYROX race or training session on a Garmin epix Pro (Gen 2) as one **Cardio** activity with **one named lap per run / station**, so Garmin Connect, Strava and the Pulse dashboard (HYROX tab) get per-station times, heart rate and distance. Built for pulse.ammarhussein.cloud; source in `source/HyroxApp.mc`.

## Using it on the watch
START → activity list → **Pulse HYROX**. The start screen shows the mode; UP/DOWN toggles **Race / Training**.

| Screen | Buttons |
|---|---|
| Start | START = go (race) / pick (training) · UP/DOWN = mode · LAP = exit |
| Race segment | LAP = next segment · START = pause/resume · after the 16th LAP: START = save |
| Training pick list | UP/DOWN = choose · START = begin the highlighted exercise · LAP = menu (Resume / Save / Discard) |
| Training exercise | START or LAP = done → back to the list (rest timer runs) |
| Paused | START = resume · LAP = menu |

Button help is drawn as coloured arcs beside the physical buttons (green = START action, orange/grey = LAP, grey = UP/DOWN) because text at the bottom of the round 416 px screen gets clipped.

- **Race mode**: the official 16 segments — Run 1, SkiErg, Run 2, Sled push, Run 3, Sled pull, Run 4, Burpee BJ, Run 5, Row, Run 6, Farmers, Run 7, Lunges, Run 8, Wall balls. Three buzzes at the finish.
- **Training mode**: list = SkiErg, Sled push, Sled pull, Burpee BJ, Row, Farmers, Lunges, Wall balls, Run, Rest. After each exercise the list comes back pre-selected on the next entry. The time on the list is rest and is folded into the start of the next lap; pick **Rest** and START it to record rest as its own lap. Ammar's runs between stations are 1.11 km.
- HR number is coloured by the user's Garmin HR zones (grey < Z1, blue, green, orange, red). Farmers / lunges / run show "~190 m · 290 steps" from the watch pedometer (stride 0.65 / 0.75 / 1.1 m per step).
- Sport = `SPORT_TRAINING` / `SUB_SPORT_CARDIO_TRAINING`: training load counts, running VO2 max and race predictions are untouched; Strava shows "Workout".

## Data written to the FIT file (developer fields, per lap)
| Field | id | type | meaning |
|---|---|---|---|
| `station` | 0 | string(12) | exercise name ("SkiErg", "Run 3", "Rest" …) |
| `station_idx` | 1 | uint8 | race: index into the 16 segments; training: 100 + list index (109 = Rest) |
| `steps` | 2 | uint16 | pedometer delta during the lap |
| `est_m` | 3 | uint16 | steps × stride, metres (0 when no stride) |

`setData()` only stages a value for the *next* lap write, so the app re-applies the fields on every 250 ms tick (a lap written with stale fields was the first bug). `resources/fitcontributions/fitcontributions.xml` declares the fields so store builds display them in Garmin Connect's lap table; sideloaded builds record them but Connect does not show them.

The dashboard reads them with `hyrox_watch.py` → `site/hyrox_watch.json` → HYROX tab ("From your watch"). Without names, a 16-lap session is read as a race in the standard order.

## Build (done on the VPS, no SDK install on the host)
1. Connect IQ SDK 9.3 (Linux zip) unpacked at `/tmp/ciq/sdk`; developer key `/tmp/ciq/keys/dev.der` (`openssl genrsa 4096` → pkcs8 DER).
2. Device definition `epix2pro47mm` — the SDK Manager needs a Garmin login, so it was downloaded on Ammar's Ubuntu laptop with [lindell/connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli) (`login --username`, then `device download --device epix2pro47mm`), zipped from `~/.Garmin/ConnectIQ/Devices/`, and unpacked to `/tmp/ciq/devices/epix2pro47mm`. Each extra device for the store is one more `device download`.
3. Compile in a stock JRE container (the SDK's simulator needs GTK/WebKit libraries the VPS doesn't have; the compiler doesn't):

```sh
cd ~/whoop-dash/watch/hyrox
docker run --rm -v /tmp/ciq:/ciq -v $PWD:/src -w /src -v /tmp/ciq/devices:/root/.Garmin/ConnectIQ/Devices eclipse-temurin:17-jre \
  java -jar /ciq/sdk/bin/monkeybrains.jar -o /ciq/PulseHyrox.prg -f monkey.jungle -d epix2pro47mm -y /ciq/keys/dev.der -w       # sideload build
docker run --rm -v /tmp/ciq:/ciq -v $PWD:/src -w /src -v /tmp/ciq/devices:/root/.Garmin/ConnectIQ/Devices eclipse-temurin:17-jre \
  java -jar /ciq/sdk/bin/monkeybrains.jar -e -r -o /ciq/PulseHyrox.iq -f monkey.jungle -y /ciq/keys/dev.der -w                  # store package (release, all products in the manifest)
```
Both are served from `site/share/PulseHyrox-<random>.prg|.iq` (the share folder is public but unlisted; not in git).

## Sideload (Linux, MTP)
The epix 2 series has no USB mass-storage mode. It enumerates first as `091e:0003` ("Garmin" mode, vendor class 255, nothing mountable) and switches to MTP by itself after a while; a worn cable makes that hand-over fail (`dmesg`: `device descriptor read/64, error -71`, "Cannot enable. Maybe the USB cable is bad?") — clean the four contacts, reseat the clip, use the USB‑C port. Once `ls /run/user/1000/gvfs/` shows `mtp:host=091e_…`:

```sh
gio copy ~/Downloads/PulseHyrox.prg "mtp://091e_50d9_0000cd8a10e1/Internal Storage/GARMIN/Apps/PulseHyrox.prg"   # cp fails with "Operation not supported" on MTP; gio works. Folder is "Apps", case-sensitive
gio mount -u "mtp://091e_50d9_0000cd8a10e1/"
```
Unplug; the app appears in the activity list (START → list → Add if not). The watch moves the file out of `Apps` after installing it; copy a new build the same way to update. Delete the sideload once the store version is installed (different app id).

## Connect IQ Store
Developer account on apps.garmin.com (free), upload the `.iq` at apps.garmin.com/developer/upload, then the listing: see `store/listing.md` for every field (description EN/AR, what's new, answers to the ANT+/BLE/companion/monetisation questions) and `store/` for the cover (1440×720), icons and the four 416×416 screen images. Privacy policy page: `site/hyrox/privacy.html`, public via the nginx `/hyrox/` location. Garmin reviews public apps in a few working days; "beta" uploads stay unlisted.

## History
Built 31 Oct – 1 Nov 2026 in the Pulse project: v1 (race order only) → training pick list → START ends the exercise → fields re-staged every tick (first FIT had no `station`) → round-screen layout with button arcs → steps / distance estimate → store package. Compiled only; no simulator — tested on the watch itself.
