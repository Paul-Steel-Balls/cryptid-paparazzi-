"""Hand-drawn WANTED posters for cryptids you haven't got on film yet (Cryptid Files).

Takes each portrait in ui/portraits/, turns it into a pencil sketch (dodge blend + cross-hatching),
and lays it on an aged paper poster with a WANTED header, a reward and where it was last seen.

    python3 tools/make_wanted.py            # all cryptids
    python3 tools/make_wanted.py the_rake   # just one
"""
import math
import random
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ui" / "wanted"
W, H = 600, 820
INK = (52, 36, 24)

# Reward and haunt per cryptid (kept in step with scripts/species.gd by hand: it's flavour text).
INFO = {
    "bigboobs": ("$500", "THE WOODS & THE LAKE"),
    "methman": ("$150", "UNDER THE CITY OVERPASS"),
    "jersey_devil": ("$225", "CITY PARKING LOTS"),
    "grey_tourist": ("$100", "EVERYWHERE. TAKING PICTURES."),
    "cornicorn": ("$150", "DEEP WOODS & LAKESIDE"),
    "crackin": ("$225", "THE CITY RIVERBANK"),
    "oh_go_pogo": ("$225", "LAKESIDE"),
    "wherewolf": ("$1,000", "NOBODY KNOWS. NOT EVEN HIM."),
    "fhairy": ("$100", "LAKESIDE"),
    "leperchaun": ("$225", "THE DEEP WOODS (NEAR HIS GOLD)"),
    "bent": ("$225", "THE DEEP WOODS"),
    "the_rake": ("$500", "THE CITY. BEHIND YOU."),
    "santa": ("$2,000", "YOUR ROOF. ONCE A YEAR."),
}
NAMES = {}


def load_names():
    src = (ROOT / "scripts" / "species.gd").read_text()
    for m in re.finditer(r'"(\w+)": \{\s*"name": "([^"]+)"', src):
        NAMES[m.group(1)] = m.group(2)


def paper(rng):
    base = np.zeros((H, W, 3), np.float32)
    base[:] = (226, 211, 172)
    noise = np.array(Image.effect_noise((W, H), 28).filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None]
    base += (noise - 128.0) * 0.1
    blot = np.array(Image.effect_noise((W // 8, H // 8), 60).resize((W, H), Image.BICUBIC), np.float32)[..., None]
    base -= np.clip(blot - 128.0, 0, None) * 0.1
    yy, xx = np.mgrid[0:H, 0:W]
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy)).astype(np.float32)
    base *= (0.72 + 0.28 * np.clip(edge / 70.0, 0, 1))[..., None]          # browned edges
    for _ in range(3):                                                    # coffee rings / water stains
        cx, cy, r = rng.randint(40, W - 40), rng.randint(60, H - 60), rng.randint(30, 80)
        d = np.hypot(xx - cx, yy - cy)
        ring = np.exp(-((d - r) ** 2) / 30.0) * 18 + np.clip(1 - d / r, 0, 1) * 6
        base -= ring[..., None] * np.array([0.6, 0.8, 1.0])
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    # ragged edges
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    pts = []
    for i in range(80):
        t = i / 80
        pts.append((t * W, rng.uniform(2, 9)))
    for i in range(100):
        t = i / 100
        pts.append((W - rng.uniform(2, 9), t * H))
    for i in range(80):
        t = 1 - i / 80
        pts.append((t * W, H - rng.uniform(2, 9)))
    for i in range(100):
        t = 1 - i / 100
        pts.append((rng.uniform(2, 9), t * H))
    md.polygon(pts, fill=255)
    img.putalpha(mask)
    return img


def sketch(portrait, size):
    """Pencil sketch of an RGBA portrait: dodge-blend line art plus hatching in the shadows."""
    p = portrait.convert("RGBA")
    bg = Image.new("RGBA", p.size, (255, 255, 255, 255))
    bg.alpha_composite(p)
    g = ImageOps.grayscale(bg.convert("RGB"))
    g = ImageOps.autocontrast(g, cutoff=1)
    arr = np.array(g, np.float32)
    lifted = arr * 0.7 + 75.0          # so big dark areas become hatching, not solid black
    inv = 255.0 - lifted
    blur = np.array(Image.fromarray(inv.astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), np.float32)
    dodge = np.clip(lifted * 255.0 / np.maximum(1.0, 255.0 - blur), 0, 255)
    edges = np.array(g.filter(ImageFilter.FIND_EDGES), np.float32)
    lines = np.clip(dodge - edges * 0.9, 0, 255)
    # hatching where the original is dark
    hh, ww = arr.shape
    yy, xx = np.mgrid[0:hh, 0:ww]
    hatch1 = (np.sin((xx + yy) * 0.6) > 0.55)
    hatch2 = (np.sin((xx - yy) * 0.6) > 0.6)
    hatch3 = (np.sin(xx * 0.85) > 0.75)
    dark = arr < 140
    darker = arr < 80
    darkest = arr < 35
    out = lines.copy()
    out[dark & hatch1] *= 0.5
    out[darker & hatch2] *= 0.45
    out[darkest & hatch3] *= 0.5
    # a little graphite grain
    grain = np.array(Image.effect_noise((ww, hh), 40), np.float32)
    out = np.clip(out - np.clip(128 - grain, 0, None) * 0.15 * (out < 230), 0, 255)
    alpha = Image.fromarray((255 - out).astype(np.uint8))
    alpha = alpha.resize(size, Image.LANCZOS)
    ink = Image.new("RGBA", size, INK + (0,))
    ink.putalpha(alpha.point(lambda v: min(255, int(v * 1.15))))
    return ink


def wobbly_rect(d, box, rng, width=3):
    x0, y0, x1, y1 = box
    for (a, b) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        for k in range(2):
            j = lambda: rng.uniform(-2.5, 2.5)
            d.line([(a[0] + j(), a[1] + j()), (b[0] + j(), b[1] + j())], fill=INK + (200,), width=width - k)


def centered(d, y, text, font, fill=INK + (235,)):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=fill)


def poster(cid):
    rng = random.Random(hash(cid) & 0xFFFF)
    img = paper(rng)
    d = ImageDraw.Draw(img)
    rye = lambda s: ImageFont.truetype(str(ROOT / "fonts" / "Rye-Regular.ttf"), s)
    typ = lambda s: ImageFont.truetype(str(ROOT / "fonts" / "SpecialElite-Regular.ttf"), s)
    centered(d, 26, "WANTED", rye(96))
    centered(d, 140, "FOR PHOTOGRAPHS", typ(30))
    box = (70, 190, W - 70, 600)
    src = ROOT / "ui" / "portraits" / f"{cid}.png"
    if src.exists():
        sk = sketch(Image.open(src), (box[2] - box[0] - 20, box[3] - box[1] - 20))
        img.alpha_composite(sk, (box[0] + 10, box[1] + 10))
    wobbly_rect(d, box, rng)
    name = NAMES.get(cid, cid.replace("_", " ")).upper()
    f = rye(48 if len(name) < 13 else 38)
    centered(d, 616, name, f)
    reward, seen = INFO.get(cid, ("$???", "UNKNOWN"))
    centered(d, 680, f"REWARD  {reward}", typ(34))
    centered(d, 726, f"LAST SEEN: {seen}", typ(20))
    centered(d, 760, "DO NOT APPROACH  ·  DO NOT FEED  ·  NO FLASH", typ(16), INK + (180,))
    # a thumbtack at the top
    d.ellipse((W / 2 - 13, 8, W / 2 + 13, 34), fill=(170, 30, 25, 255), outline=(90, 15, 10, 255), width=2)
    d.ellipse((W / 2 - 5, 13, W / 2 + 3, 21), fill=(235, 120, 110, 255))
    # slight tilt, as if pinned up by hand
    img = img.rotate(rng.uniform(-1.6, 1.6), resample=Image.BICUBIC, expand=True)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{cid}.png")
    print("wanted", cid)


if __name__ == "__main__":
    load_names()
    ids = sys.argv[1:] or list(INFO)
    for cid in ids:
        poster(cid)
