#!/usr/bin/env python3
"""Sync manifest.xml products and monkey.jungle with the device definitions you have installed.

    python3 tools/devices.py ~/.Garmin/ConnectIQ/Devices

Takes every id in devices.txt that has a definition in that folder, keeps the ones with a round (or Instinct semi-octagon) screen and
Connect IQ >= 3.2 (manifest minSdkVersion), writes them into manifest.xml, and lists 1-bit (mono) screens in
monkey.jungle so they compile the (:mono) drawing helpers. Prints what was skipped and why.
"""
import json, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
devdir = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.Garmin/ConnectIQ/Devices")
wanted = [l.strip() for l in open(os.path.join(root, "devices.txt")) if l.strip() and not l.startswith("#")]

def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])

ok, mono, skipped = [], [], []
for d in wanted:
    p = os.path.join(devdir, d, "compiler.json")
    if not os.path.exists(p):
        skipped.append((d, "no definition")); continue
    c = json.load(open(p))
    fam = c.get("deviceFamily", "")
    if not fam.startswith(("round", "semioctagon")):   # semioctagon = Instinct (round with the sub-screen notch)
        skipped.append((d, "screen " + fam)); continue
    if max(ver(pn.get("connectIQVersion", "0")) for pn in c.get("partNumbers", [{}])) < (3, 2, 0):
        skipped.append((d, "Connect IQ < 3.2")); continue
    ok.append(d)
    if c.get("bitsPerPixel", 16) == 1:
        mono.append(d)

man = os.path.join(root, "manifest.xml")
s = open(man).read()
prods = "\n".join('      <iq:product id="%s"/>' % d for d in ok)
s = re.sub(r"<iq:products>.*?</iq:products>", "<iq:products>\n" + prods + "\n    </iq:products>", s, flags=re.S)
open(man, "w").write(s)

jun = os.path.join(root, "monkey.jungle")
lines = [l for l in open(jun).read().splitlines() if not re.match(r"^\w+\.excludeAnnotations = color$", l)]
lines += ["%s.excludeAnnotations = color" % d for d in mono]
open(jun, "w").write("\n".join(lines) + "\n")

print("%d products (%d mono: %s)" % (len(ok), len(mono), " ".join(mono)))
for d, why in skipped:
    print("  skipped %-24s %s" % (d, why))
