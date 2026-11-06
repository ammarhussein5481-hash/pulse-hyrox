"""Approximate preview of the Pulse HYROX screens on a device, mirroring HyroxView's row()/spanAt()/hint() logic.
Font cell height = the size in the device's font filename (ROBOTO_26B -> 26 px), glyphs drawn with Inter / DejaVu Condensed.
usage: python3 tools/preview.py DEVICES_DIR outdir   (reads manifest.xml products; needs Pillow)
Only a sanity check for clipped / overlapping text — the real fonts differ slightly; confirm in the SDK simulator."""
import json, math, re, sys, os
from PIL import Image, ImageDraw, ImageFont

import glob
def _font(*pats):
    for pat in pats:
        hits = sorted(glob.glob(pat))
        if hits: return hits[0]
    raise SystemExit("no font found for " + str(pats))
TXT = _font("/usr/share/fonts/opentype/inter/Inter-Bold.otf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
NUM = _font("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
ORDER_T = ["large", "medium", "small", "tiny", "xtiny"]
F_TITLE = ["large", "medium", "small", "tiny", "xtiny"]
F_MED = ["medium", "small", "tiny", "xtiny"]
F_SMALL = ["small", "tiny", "xtiny"]
F_TINY = ["tiny", "xtiny"]
F_NUM = ["numberThaiHot", "numberHot", "numberMedium", "numberMild", "large"]
COL = dict(G=(60, 200, 80), O=(255, 140, 0), D=(85, 85, 85), L=(170, 170, 170), W=(255, 255, 255), Y=(255, 220, 0), R=(230, 50, 50))

class Dev:
    def __init__(s, spec):
        s.id = spec["id"]; s.w = spec["w"]; s.h = spec["h"]; s.cx = s.w // 2; s.cy = s.h // 2
        s.sizes = spec["fonts"]; s.mono = spec["mono"]; s.updown = spec["updown"]; s.sub = spec.get("sub")
        s.pen = max(3, s.w // 80); s._f = {}
        s.labels = s.w >= 200; s.ri = s.cx - s.pen // 2 - 1 - s.pen - 6
        s.lblH = s.fh("xtiny"); s.res = [0, 0, 0, 0]
    def font(s, name):
        if name not in s._f:
            px = s.sizes[name]
            isnum = name.startswith("number")
            path = NUM if isnum else TXT
            s._f[name] = (ImageFont.truetype(path, int(px * (0.95 if isnum else 0.78))), px)
        return s._f[name]
    def tw(s, text, name): return s.font(name)[0].getlength(text)
    def fh(s, name): return s.font(name)[1]
    def col(s, c):
        return (255, 255, 255) if s.mono and c != (0, 0, 0) else c
    def span(s, y0, fh):
        top, bot = y0 + fh * .18, y0 + fh * .82
        d = max(abs(top - s.cy), abs(bot - s.cy)); r = s.cx
        half = math.sqrt(r * r - d * d) * .92 if d < r else 0
        l, rt = s.cx - half, s.cx + half
        if s.labels:
            ly = s.ri / 2; ex = s.ri * .866
            for k in (0, 1):
                yc = s.cy - ly if k == 0 else s.cy + ly
                if top < yc + s.lblH / 2 and bot > yc - s.lblH / 2:
                    wr, wl = s.res[k], s.res[k + 2]
                    if wr and rt > s.cx + ex - wr - 4: rt = s.cx + ex - wr - 4
                    if wl and l < s.cx - ex + wl + 4: l = s.cx - ex + wl + 4
        if s.sub:
            x, y, w, h = s.sub
            if top < y + h and bot > y and rt > x - 3: rt = x - 3
        return l, rt
    def row(s, dr, yf, text, fonts, c, maxhf, issues):
        texts = text if isinstance(text, list) else [text]
        y0 = int(s.h * yf); maxh = s.h * maxhf
        for t, tx in enumerate(texts):
            for i, f in enumerate(fonts):
                last = i == len(fonts) - 1 and t == len(texts) - 1
                fh = s.fh(f)
                if fh > maxh and not last: continue
                l, rt = s.span(y0, fh)
                if s.tw(tx, f) <= rt - l or last:
                    if last and (s.tw(tx, f) > rt - l or fh > maxh): issues.append("%r overflows (font %s)" % (tx, f))
                    dr.text(((l + rt) / 2, y0 + fh / 2), tx, font=s.font(f)[0], fill=s.col(c), anchor="mm")
                    return (y0, y0 + fh, f)
    def plan(s, start, lap, up, down):
        s.res = [s.tw(t, "xtiny") if s.labels and t and (i < 2 or s.updown) else 0 for i, t in enumerate((start, lap, up, down))]
    def hint(s, dr, deg, label, c):
        if deg in (150, 210) and not s.updown: return
        r = s.cx - s.pen // 2 - 1
        pw = (s.pen + 1) // 2 if c == COL["D"] else s.pen
        bbox = [s.cx - r, s.cy - r, s.cx + r, s.cy + r]
        dr.arc(bbox, -(deg + 9), -(deg - 9), fill=s.col(c), width=pw)
        if not s.labels: return
        ri = s.ri; rad = math.radians(deg)
        tx, ty = s.cx + ri * math.cos(rad), s.cy - ri * math.sin(rad)
        anchor = "lm" if 90 < deg < 270 else "rm"
        dr.text((tx, ty), label, font=s.font("xtiny")[0], fill=s.col(c), anchor=anchor)

def screen(d, kind):
    img = Image.new("RGB", (d.w, d.h), (0, 0, 0)); dr = ImageDraw.Draw(img); iss = []; rows = []
    G, O, D, L, W = (COL[k] for k in "GODLW")
    R = lambda *a: rows.append(d.row(dr, *a, iss))
    if kind == "start":
        d.plan("pick", "exit", "mode", "mode")
        R(.11, ["PULSE HYROX", "HYROX"], F_TINY, O, .13); R(.24, "Training", F_TITLE, W, .22)
        R(.47, "pick each exercise", F_TINY, L, .10); R(.56, "START or LAP ends it", F_TINY, L, .10)
        if not d.updown: R(.66, ["swipe: race / training", "swipe for mode"], F_TINY, L, .10)
        d.hint(dr, 30, "pick", G); d.hint(dr, 150, "mode", D); d.hint(dr, 210, "mode", D); d.hint(dr, -30, "exit", D)
    elif kind == "pick":
        d.plan("go", "menu", "up", "down")
        R(.13, "NEXT · 5", F_SMALL, O, .15); R(.27, "Sled push", F_SMALL, D, .13); R(.38, "Wall balls", F_TITLE, W, .19)
        R(.54, "Burpee BJ", F_SMALL, D, .13); R(.66, "rest 1:23", F_TINY, L, .10); R(.74, "total 24:05", F_TINY, L, .10)
        d.hint(dr, 30, "go", G); d.hint(dr, 150, "up", D); d.hint(dr, 210, "down", D); d.hint(dr, -30, "menu", O)
    else:
        hs, hl = ("done", "done") if kind == "ex" else ("pause", "next")
        d.plan(hs, hl, "", "")
        R(.15, "WALL BALLS" if kind == "ex" else "SLED PUSH", F_MED, O, .14); R(.27, "12:34", F_NUM, W, .32)
        R(.56, "total 1:02:45", F_SMALL, L, .12)
        fh = d.fh("medium"); l, rt = d.span(int(d.h * .67), fh); cw = (rt - l) / 2 - 6
        for x, t, c in (((l + d.cx) / 2 + 2, "164", COL["R"]), ((d.cx + rt) / 2 - 2, "#12" if kind == "ex" else "4/16", L)):
            f = next((f for f in F_MED if d.tw(t, f) <= cw), "xtiny")
            if d.tw(t, f) > cw: iss.append("%r cell overflows" % t)
            dr.text((x, int(d.h * .67) + d.fh(f) / 2), t, font=d.font(f)[0], fill=d.col(c), anchor="mm")
            rows.append((int(d.h * .67), int(d.h * .67) + d.fh(f), f))
        R(.79, ["~212 m · 326 steps", "~212 m · 326", "~212 m"] if kind == "ex" else "next Run 3", F_TINY, L, .10)
        d.hint(dr, 30, hs, G if kind == "ex" else D); d.hint(dr, -30, hl, G)
    if d.sub and kind != "start":
        x, y, w, h = d.sub; dr.ellipse([x, y, x + w, y + h], outline=(120, 120, 120))
        dr.text((x + w / 2, y + h / 2), "164", font=d.font("numberMild")[0], fill=(255, 255, 255), anchor="mm")
    # glyph-overlap check between consecutive rows (using the 18–82 % glyph band of each cell)
    rows = sorted(r for r in rows if r)
    for a, b in zip(rows, rows[1:]):
        if a[0] == b[0]: continue
        ga = a[1] - (a[1] - a[0]) * .18; gb = b[0] + (b[1] - b[0]) * .18
        if ga > gb + 1: iss.append("rows at %d and %d overlap by %dpx" % (a[0], b[0], ga - gb))
    mask = Image.new("L", (d.w, d.h), 0); ImageDraw.Draw(mask).ellipse([0, 0, d.w - 1, d.h - 1], fill=255)
    out = Image.new("RGB", (d.w, d.h), (40, 40, 40)); out.paste(img, (0, 0), mask)
    return out, iss

def specs(devdir):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ids = re.findall(r'<iq:product id="([^"]+)"', open(os.path.join(root, "manifest.xml")).read())
    keep = ["xtiny", "tiny", "small", "medium", "large", "numberMild", "numberMedium", "numberHot", "numberThaiHot"]
    out, ref = [], None
    for d in ids:
        c = json.load(open(os.path.join(devdir, d, "compiler.json"))); s = json.load(open(os.path.join(devdir, d, "simulator.json")))
        ppi = s.get("ppi") or 300; f = {}
        for x in s["fonts"][0]["fonts"]:
            if x.get("type") == "ttf" and x.get("size"): f[x["name"]] = round(x["size"] * ppi / 72 * 1.17)
            else:
                m = re.search(r"_(\d+)[A-Z]?$", x["filename"])
                if m: f[x["name"]] = int(m.group(1))
        keys = [k.get("behavior") for k in s.get("keys", [])]
        sub = None
        if isinstance(s.get("subscreen"), dict):
            L = s["subscreen"]["location"]; D = s["display"]["location"]; sub = [L["x"] - D["x"], L["y"] - D["y"], L["width"], L["height"]]
        sp = dict(id=d, w=c["resolution"]["width"], h=c["resolution"]["height"], mono=c["bitsPerPixel"] == 1,
                  updown="previousPage" in keys and "nextPage" in keys, fonts={k: f[k] for k in keep if k in f}, sub=sub)
        out.append(sp)
        if d == "epix2pro47mm": ref = sp["fonts"]
    for sp in out:
        f = sp["fonts"]
        if "tiny" not in f and ref:            # named bitmap fonts without a size: scale the epix set
            sp["fonts"] = f = {k: round(ref[k] * sp["w"] / 416 * 1.1) for k in keep}; sp["approx"] = True
        top = f.get("numberThaiHot", f.get("large", 40))
        for k, r in (("numberHot", .87), ("numberMedium", .65), ("numberMild", .55)): f.setdefault(k, round(top * r))
    return out

if __name__ == "__main__":
    specs = specs(sys.argv[1]); outdir = sys.argv[2]; os.makedirs(outdir, exist_ok=True)
    for sp in specs:
        d = Dev(sp); shots = []; allis = []
        for k in ("start", "pick", "ex", "race"):
            im, iss = screen(d, k); shots.append(im); allis += ["%s: %s" % (k, i) for i in iss]
        sheet = Image.new("RGB", (d.w * 4 + 30, d.h + 10), (20, 20, 20))
        for i, im in enumerate(shots): sheet.paste(im, (5 + i * (d.w + 7), 5))
        sheet.save(os.path.join(outdir, sp["id"] + ".png"))
        print(sp["id"], "%dx%d" % (d.w, d.h), "mono" if d.mono else "", "touch" if not d.updown else "", "OK" if not allis else "; ".join(allis))
