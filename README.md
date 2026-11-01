# Pulse HYROX

A Connect IQ activity app for Garmin watches that records a **HYROX** race or training session as one Cardio activity with **one named lap per run / station** — so Garmin Connect, Strava and anything that reads the FIT file get per-station times, heart rate and distance.

![Pulse HYROX](store/cover_1440x720.png)

- **Race mode** — the official 16 segments in order (Run 1, SkiErg, Run 2, Sled push, Run 3, Sled pull, Run 4, Burpee broad jumps, Run 5, Row, Run 6, Farmers carry, Run 7, Sandbag lunges, Run 8, Wall balls). START to begin, LAP at each transition, START to save after the last one.
- **Training mode** — build the session as you go: pick each exercise from a list (SkiErg, Sled push, Sled pull, Burpee BJ, Row, Farmers, Lunges, Wall balls, Run, Rest), START to begin it, START or LAP to finish it and return to the list. Rest between exercises is timed; pick **Rest** to record it as its own lap.
- Heart rate coloured by your Garmin HR zones; step-based distance estimate on screen for farmers carry, lunges and runs.
- Records as **Cardio** (training load counts; running VO2 max and race predictions are untouched). Strava shows it as a Workout.
- Every lap carries FIT developer fields: `station` (name), `station_idx`, `steps`, `est_m` — visible per lap in Garmin Connect when installed from the store.
- No settings, no account, no network: nothing leaves the watch. [Privacy policy](docs/privacy.html).

Currently built for the **epix Pro (Gen 2) 47 mm**. Other 416 × 416 round watches (fenix 7 Pro / 8 47 mm, epix 2, Forerunner 965…) should work by adding their product ids to `manifest.xml` and downloading their device definitions.

## Controls
| Screen | START | LAP (BACK) | UP / DOWN |
|---|---|---|---|
| Start | go (race) / pick (training) | exit | race ↔ training |
| Race segment | pause / resume | next segment (16th → finish) | — |
| Training list | begin highlighted exercise | Resume / Save / Discard menu | choose |
| Training exercise | done → list | done → list | — |
| Paused | resume | menu | — |

Button help is drawn as coloured arcs beside the physical buttons (green = START action, orange = LAP menu, grey = UP/DOWN), which keeps the round screen's bottom edge clear.

## Install
- **Connect IQ Store**: search "Pulse HYROX" in the Connect IQ app on your phone (listing pending review).
- **Sideload**: build or download `PulseHyrox.prg`, connect the watch by USB and copy it into `GARMIN/Apps/`. On Linux the epix mounts over MTP: wait for `mtp:host=091e_…` under `/run/user/<uid>/gvfs/`, then `gio copy PulseHyrox.prg "mtp://<host>/Internal Storage/GARMIN/Apps/PulseHyrox.prg"` (plain `cp` fails on MTP). If `lsusb` shows `091e:0003` with nothing mountable, the watch is still in Garmin mode — it switches to MTP on its own after a few seconds; repeated `error -71` in `dmesg` means the cable or the contacts.

## Build
Needs the Connect IQ SDK (any 7+; built with 9.3), the device definition(s) from Garmin's SDK Manager (or [connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli) on a headless machine: `connect-iq-sdk-manager login --username …` then `device download --device epix2pro47mm`), and a developer key (`openssl genrsa -out dev.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in dev.pem -out dev.der -nocrypt`).

With Visual Studio Code + the Monkey C extension: open the folder, *Monkey C: Build for Device* / *Export Project*.

Without the SDK on the host, `build.sh` runs the compiler in a stock Java container:

```sh
SDK=~/connectiq-sdk-lin-9.3.0 KEY=~/dev.der ./build.sh epix2pro47mm   # sideload build → bin/PulseHyrox.prg
SDK=~/connectiq-sdk-lin-9.3.0 KEY=~/dev.der ./build.sh                # store package  → bin/PulseHyrox.iq
```

## FIT fields
| Field | id | type | meaning |
|---|---|---|---|
| `station` | 0 | string(12) | exercise name ("SkiErg", "Run 3", "Rest" …) |
| `station_idx` | 1 | uint8 | race: 0–15 segment index; training: 100 + list index (109 = Rest) |
| `steps` | 2 | uint16 | watch pedometer delta during the lap |
| `est_m` | 3 | uint16 | steps × stride (farmers 0.65 m, lunges 0.75 m, run 1.1 m); 0 when not estimated |

Implementation note: `Field.setData()` only stages the value for the *next* lap write, so the app re-applies all four fields on every 250 ms tick; a lap written with stale fields was the first bug on hardware. `resources/fitcontributions/fitcontributions.xml` declares the fields so Garmin Connect displays them (store builds only).

## Store listing
`store/` holds the cover, icons, the four 416 × 416 screen images and `listing.md` with the description (English + Arabic) and the answers to the upload form.

## Licence
MIT. Built for [Pulse](https://github.com/ammarhussein5481-hash/pulse), a personal training dashboard, but the app has no dependency on it.
