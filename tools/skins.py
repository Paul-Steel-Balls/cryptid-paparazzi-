"""Outfits for the photographer, sold at the City's costume shop (DRIP CITY).
Each entry takes the skeleton and returns overrides for the base body in characters.photographer
(colours, what to leave off) plus an "extra" function that sculpts the costume on top.

Costume shells go in the "cloth" (or "shiny"/"metal") material group: groups are meshed
separately, so a face hole cut out of a costume (sub=True) never cuts into the face under it.
Build: python3 tools/characters.py models photographer_banana  (or any photographer_<id>)"""
import math
import numpy as np
from charkit import *

SKIN = (0.93, 0.72, 0.56)
BLACK = (0.05, 0.05, 0.06)
WHITE = (0.95, 0.95, 0.93)


def J(s, name):
    return np.array(s.heads[s.idx(name)], float)


def face_hole(color, z=0.17, rx=0.112, ry=0.135, cy=1.645, mat="cloth", bone="head"):
    """Cut the face opening out of a hood/costume head (only in that costume's mesh group)."""
    return ellipsoid((0, cy, z), (rx, ry, 0.16), bone, color, mat=mat, sub=True, k=0.02)


def googly(ch, bone, c, r, mat="shiny", look=(0, 0, 1)):
    c = np.asarray(c, float)
    ch.add(sphere(c, r, bone, WHITE, mat=mat, k=0.0))
    ch.add(sphere(c + np.asarray(look) * r * 0.7 + np.array([0, -r * 0.15, 0]), r * 0.45, bone, BLACK, mat=mat, k=0.0))


def limb_shells(ch, s, arm_col, leg_col, arm_r=0.075, leg_r=0.1, mat="cloth", noise=None, hands=False, feet=None):
    """Baggy sleeves and legs over the body's own (each on its bone so they bend)."""
    for side in ("l", "r"):
        sh, el, hd = J(s, f"shoulder_{side}"), J(s, f"elbow_{side}"), J(s, f"hand_{side}")
        hp, kn, ft = J(s, f"hip_{side}"), J(s, f"knee_{side}"), J(s, f"foot_{side}")
        kw = dict(mat=mat, k=0.02)
        if noise:
            kw["noise"] = noise
        if arm_col is not None:
            ch.add(capsule(sh, el, arm_r, f"shoulder_{side}", arm_col, rb=arm_r * 0.9, **kw))
            ch.add(capsule(el, hd + (hd - el) * -0.12, arm_r * 0.88, f"elbow_{side}", arm_col, rb=arm_r * 0.75, **kw))
        if leg_col is not None:
            ch.add(capsule(hp, kn, leg_r, f"hip_{side}", leg_col, rb=leg_r * 0.9, **kw))
            ch.add(capsule(kn, ft + np.array([0, 0.09, 0]), leg_r * 0.88, f"knee_{side}", leg_col, rb=leg_r * 0.8, **kw))


def dots(base, cols, scale=0.07, r=0.28):
    base = np.asarray(base, float); cols = [np.asarray(c, float) for c in cols]
    def f(p):
        q = p / scale
        cell = np.floor(q)
        local = q - cell - 0.5
        d = np.linalg.norm(local, axis=1)
        out = np.tile(base, (len(p), 1))
        pick = ((cell[:, 0] * 7 + cell[:, 1] * 13 + cell[:, 2] * 5) % len(cols)).astype(int)
        for i, c in enumerate(cols):
            m = (d < r) & (pick == i)
            out[m] = c
        return out
    return f


def sparkle(base, var=0.35, freq=70.0):
    base = np.asarray(base, float)
    def f(p):
        n = vnoise(p, freq, 3.0)[:, None]
        return np.clip(base * (1.0 - var * 0.5 + var * n) + (n > 0.8) * 0.35, 0, 1)
    return f


# ------------------------------------------------------------------------------------- outfits

def hawaiian_dad(s):
    shirt = hawaiian((0.95, 0.42, 0.18), (1.0, 0.92, 0.35), (0.9, 0.25, 0.1), (0.1, 0.5, 0.25), scale=0.09)
    khaki = (0.74, 0.64, 0.44)
    def extra(ch, s):
        # Bucket hat, zinc on the nose, fanny pack, socks and sandals.
        ch.add(cylinder((0, 1.73, -0.01), (0, 1.735, -0.01), 0.21, "head", (0.55, 0.62, 0.4), mat="cloth"))
        ch.add(ellipsoid((0, 1.79, -0.01), (0.15, 0.08, 0.15), "head", (0.55, 0.62, 0.4), mat="cloth", k=0.02))
        ch.add(torus((0, 1.75, -0.01), 0.15, 0.012, "head", (0.85, 0.3, 0.2), mat="cloth"))
        ch.add(ellipsoid((0, 1.662, 0.18), (0.022, 0.012, 0.012), "head", WHITE, mat="shiny", k=0.0))
        ch.add(box((0, 0.98, 0.15), (0.11, 0.05, 0.04), "hips", (1.0, 0.25, 0.65), r=0.03, mat="cloth", k=0.01))
        ch.add(box((0, 0.98, 0.0), (0.18, 0.012, 0.13), "hips", (0.1, 0.1, 0.1), r=0.01, mat="cloth", k=0.0))
        for side, x in (("l", -1), ("r", 1)):
            kn, ft = J(s, f"knee_{side}"), J(s, f"foot_{side}")
            ch.add(capsule(ft + np.array([0, 0.04, 0]), ft + np.array([0, 0.3, 0.01]), 0.062, f"knee_{side}", WHITE, mat="cloth", k=0.01))
            ch.add(torus(ft + np.array([0, 0.27, 0.01]), 0.06, 0.008, f"knee_{side}", (0.2, 0.4, 0.85), mat="cloth"))
            ch.add(box((x * 0.1, 0.012, 0.05), (0.06, 0.012, 0.13), f"foot_{side}", (0.45, 0.28, 0.15), r=0.01, mat="cloth"))
            ch.add(ellipsoid((x * 0.1, 0.05, 0.05), (0.058, 0.05, 0.12), f"foot_{side}", WHITE, mat="cloth", k=0.02))
    return dict(torso=shirt, pockets=None, upper_arm=shirt, cuff=None, hips=khaki, belt=None, thigh=khaki, shin=SKIN,
                boots=None, cap=None, hair=(0.45, 0.3, 0.15), backpack=False, face=(0.96, 0.66, 0.55), nose=(0.98, 0.45, 0.4),
                extra=extra, name="Hawaiian Dad")


def ghillie(s):
    greens = fur((0.24, 0.34, 0.14), var=0.35, freq=14.0, seed=2.0)
    def extra(ch, s):
        shag = (0.022, 16.0, 5.0)
        ch.add(ellipsoid((0, 1.15, -0.01), (0.27, 0.42, 0.2), "chest", greens, mat="cloth", noise=shag, k=0.04))
        ch.add(ellipsoid((0, 0.88, 0.0), (0.24, 0.16, 0.18), "hips", greens, mat="cloth", noise=shag, k=0.04))
        ch.add(ellipsoid((0, 1.7, -0.03), (0.2, 0.22, 0.2), "head", greens, mat="cloth", noise=(0.028, 14.0, 7.0), k=0.03))
        ch.add(face_hole(greens, z=0.19, rx=0.1, ry=0.12))
        limb_shells(ch, s, greens, greens, arm_r=0.085, leg_r=0.11, noise=shag)
        # Leafy tufts sticking out all over.
        rng = np.random.default_rng(4)
        for _ in range(26):
            a = rng.uniform(0, 2 * math.pi); y = rng.uniform(0.8, 1.9)
            r = 0.26 if y < 1.5 else 0.2
            c = np.array([math.cos(a) * r, y, math.sin(a) * r - 0.02])
            if c[2] > 0.08 and y > 1.5:
                continue   # keep the face clear
            bone = "head" if y > 1.5 else ("chest" if y > 1.05 else "hips")
            ch.add(ellipsoid(c, (0.07, 0.03, 0.05), bone, (0.3 + rng.uniform(-0.08, 0.1), 0.42, 0.16), mat="cloth",
                             rot=(rng.uniform(-1, 1), a, rng.uniform(-1, 1)), noise=(0.012, 30.0), k=0.03))
    return dict(cap=None, backpack=False, extra=extra, name="Ghillie Suit")


def bigfoot_onesie(s):
    brown = fur((0.42, 0.27, 0.15), var=0.2, freq=24.0, seed=1.0)
    def belly(p):
        out = brown(p)
        m = (p[:, 2] > 0.08) & (np.abs(p[:, 0]) < 0.13) & (p[:, 1] < 1.38) & (p[:, 1] > 0.85)
        out[m] = (0.78, 0.62, 0.45)
        return out
    def extra(ch, s):
        fuzz = (0.008, 40.0)
        ch.add(ellipsoid((0, 1.15, 0.0), (0.25, 0.4, 0.18), "chest", belly, mat="cloth", noise=fuzz, k=0.04))
        ch.add(ellipsoid((0, 0.9, 0.0), (0.22, 0.15, 0.17), "hips", belly, mat="cloth", noise=fuzz, k=0.04))
        ch.add(ellipsoid((0, 1.71, -0.02), (0.18, 0.2, 0.18), "head", brown, mat="cloth", noise=fuzz, k=0.03))
        ch.add(face_hole(brown))
        for x in (-1, 1):
            ch.add(sphere((x * 0.12, 1.87, -0.02), 0.055, "head", brown, mat="cloth", noise=fuzz, k=0.02))
        googly(ch, "head", (-0.055, 1.855, 0.12), 0.04)
        googly(ch, "head", (0.055, 1.855, 0.12), 0.04)
        limb_shells(ch, s, brown, brown, arm_r=0.075, leg_r=0.105, noise=fuzz)
        # Huge fuzzy feet, three big toes each.
        for side, x in (("l", -1), ("r", 1)):
            ch.add(ellipsoid((x * 0.1, 0.07, 0.07), (0.1, 0.08, 0.19), f"foot_{side}", brown, mat="cloth", noise=fuzz, k=0.03))
            for t in (-1, 0, 1):
                ch.add(sphere((x * 0.1 + t * 0.055, 0.06, 0.25), 0.042, f"foot_{side}", (0.3, 0.2, 0.12), mat="cloth", k=0.02))
    return dict(cap=None, backpack=False, hands=(0.3, 0.2, 0.12), boots=None, extra=extra, name="Bigfoot Onesie")


def banana(s):
    yel = (0.98, 0.86, 0.2)
    def peel(p):
        out = np.tile(np.array(yel), (len(p), 1))
        ang = np.arctan2(p[:, 0], p[:, 2])
        ridge = np.abs(np.sin(ang * 2.5)) < 0.08
        out[ridge] = (0.86, 0.72, 0.12)
        spot = vnoise(p, 22.0, 9.0) > 0.86
        out[spot] = (0.45, 0.32, 0.1)
        return out
    def extra(ch, s):
        ch.add(capsule((0, 0.72, 0.03), (0, 1.4, 0.0), 0.28, "spine", peel, rb=0.27, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 1.73, -0.08), (0.24, 0.42, 0.21), "chest", peel, mat="cloth", k=0.08))
        ch.add(face_hole(peel, z=0.12, rx=0.118, ry=0.145, bone="chest"))
        ch.add(capsule((0, 2.08, -0.15), (0, 2.3, -0.27), 0.05, "chest", (0.45, 0.33, 0.12), rb=0.035, mat="cloth", k=0.03))
        ch.add(sphere((0, 2.33, -0.29), 0.04, "chest", (0.2, 0.15, 0.08), mat="cloth", k=0.02))
        ch.add(ellipsoid((0, 0.5, 0.05), (0.07, 0.07, 0.07), "spine", (0.3, 0.22, 0.1), mat="cloth", k=0.06))
    return dict(cap=None, backpack=False, hair=None, torso=yel, pockets=None, upper_arm=yel, cuff=None,
                hips=BLACK, belt=None, thigh=BLACK, shin=BLACK, boots=(0.1, 0.1, 0.1), extra=extra, name="Banana")


def hot_dog(s):
    sausage = (0.72, 0.28, 0.16); bun = (0.9, 0.66, 0.36); mustard = (0.98, 0.8, 0.08); ketchup = (0.85, 0.08, 0.06)
    def bun_col(p):
        out = np.tile(np.array(bun), (len(p), 1))
        top = vnoise(p, 9.0, 2.0)[:, None] * 0.12
        return np.clip(out - top, 0, 1)
    def extra(ch, s):
        ch.add(capsule((0, 0.68, 0.03), (0, 2.02, -0.04), 0.2, "spine", sausage, mat="cloth", k=0.03))
        ch.add(face_hole(sausage, z=0.15, rx=0.115, ry=0.14, bone="spine"))
        for x in (-1, 1):
            ch.add(ellipsoid((x * 0.21, 1.3, -0.04), (0.13, 0.66, 0.24), "spine", bun_col, mat="cloth", k=0.03))
        # Mustard and ketchup zig-zags down the front.
        pts = [(-0.11, 1.42), (0.11, 1.32), (-0.12, 1.2), (0.12, 1.08), (-0.12, 0.96), (0.11, 0.84)]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            ch.add(capsule((x0, y0, 0.205), (x1, y1, 0.205), 0.022, "spine", mustard, mat="shiny", k=0.01))
            ch.add(capsule((x0 * 0.6, y0 - 0.05, 0.2), (x1 * 0.6, y1 - 0.05, 0.2), 0.016, "spine", ketchup, mat="shiny", k=0.01))
        ch.add(capsule((-0.12, 1.92, 0.12), (0.12, 1.98, 0.08), 0.02, "spine", mustard, mat="shiny", k=0.01))
    return dict(cap=None, backpack=False, hair=None, torso=sausage, pockets=None, upper_arm=bun, cuff=None, forearm=bun,
                hips=bun, belt=None, thigh=bun, shin=bun, boots=(0.85, 0.15, 0.1), extra=extra, name="Hot Dog")


def t_rex(s):
    green = speckle((0.36, 0.62, 0.25), 0.05, 20)
    def body(p):
        out = green(p)
        m = (p[:, 2] > 0.1) & (np.abs(p[:, 0]) < 0.2)
        out[m] = (0.8, 0.84, 0.5)
        return out
    def extra(ch, s):
        ch.add(ellipsoid((0, 1.12, -0.02), (0.34, 0.46, 0.31), "spine", body, mat="cloth", k=0.05))
        ch.add(capsule((0, 1.42, 0.0), (0, 1.92, 0.06), 0.21, "chest", body, mat="cloth", k=0.06))
        ch.add(face_hole(body, z=0.14, rx=0.105, ry=0.12, bone="chest"))
        # The big dino head on top, mouth open, plenty of teeth.
        ch.add(ellipsoid((0, 2.14, 0.12), (0.2, 0.17, 0.28), "chest", green, mat="cloth", k=0.04))
        ch.add(ellipsoid((0, 2.12, 0.36), (0.15, 0.11, 0.17), "chest", green, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 1.98, 0.3), (0.13, 0.045, 0.21), "chest", green, mat="cloth", rot=(0.25, 0, 0), k=0.03))
        ch.add(ellipsoid((0, 2.04, 0.34), (0.12, 0.03, 0.16), "chest", (0.75, 0.2, 0.25), mat="shiny", k=0.0))
        for i in range(7):
            x = -0.11 + i * 0.037
            ch.add(ellipsoid((x, 2.03, 0.46 - abs(x) * 0.6), (0.012, 0.03, 0.012), "chest", WHITE, mat="shiny", k=0.0))
            ch.add(ellipsoid((x, 2.0, 0.42 - abs(x) * 0.6), (0.011, 0.026, 0.011), "chest", WHITE, mat="shiny", k=0.0))
        googly(ch, "chest", (-0.12, 2.24, 0.25), 0.045, look=(-0.4, 0, 1))
        googly(ch, "chest", (0.12, 2.24, 0.25), 0.045, look=(0.4, 0, 1))
        for x in (-1, 1):
            ch.add(sphere((x * 0.05, 2.17, 0.52), 0.015, "chest", (0.15, 0.25, 0.1), mat="cloth", k=0.0))
            # Tiny useless arms.
            ch.add(capsule((x * 0.2, 1.32, 0.24), (x * 0.22, 1.2, 0.36), 0.045, "chest", green, mat="cloth", k=0.02))
            for t in (-1, 1):
                ch.add(capsule((x * 0.22 + t * 0.015, 1.2, 0.36), (x * 0.22 + t * 0.02, 1.15, 0.4), 0.01, "chest", WHITE, mat="shiny", k=0.0))
        # Spines down the back, and a big tail.
        for i in range(6):
            ch.add(ellipsoid((0, 2.18 - i * 0.2, -0.17 - (0.12 if i > 1 else 0.0)), (0.015, 0.05, 0.04), "chest" if i < 3 else "spine",
                             (0.25, 0.45, 0.18), mat="cloth", k=0.02))
        ch.add(capsule((0, 0.98, -0.24), (0, 0.42, -0.95), 0.2, "hips", green, rb=0.04, mat="cloth", k=0.05))
        limb_shells(ch, s, green, green, arm_r=0.075, leg_r=0.14)
        for side, x in (("l", -1), ("r", 1)):
            ch.add(ellipsoid((x * 0.1, 0.07, 0.07), (0.11, 0.08, 0.17), f"foot_{side}", green, mat="cloth", k=0.03))
            for t in (-1, 0, 1):
                ch.add(ellipsoid((x * 0.1 + t * 0.05, 0.04, 0.24), (0.015, 0.02, 0.035), f"foot_{side}", WHITE, mat="shiny", k=0.0))
    return dict(cap=None, backpack=False, hair=None, boots=None, extra=extra, name="Inflatable T-Rex")


def astronaut(s):
    white = (0.92, 0.92, 0.9); grey = (0.6, 0.62, 0.65)
    def extra(ch, s):
        ch.add(ellipsoid((0, 1.17, 0.0), (0.27, 0.38, 0.2), "chest", white, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 0.9, 0.0), (0.23, 0.15, 0.18), "hips", white, mat="cloth", k=0.04))
        ch.add(box((0, 1.25, -0.25), (0.19, 0.26, 0.1), "chest", white, r=0.05, mat="cloth", k=0.02))
        ch.add(cylinder((0.12, 1.45, -0.25), (0.12, 1.55, -0.25), 0.04, "chest", grey, mat="metal"))
        # Chest control box (off to one side so the camera can hang in front).
        ch.add(box((0.12, 1.05, 0.19), (0.07, 0.05, 0.03), "chest", grey, r=0.01, mat="cloth", k=0.01))
        for i, c in enumerate([(0.9, 0.15, 0.1), (0.1, 0.4, 0.9), (0.2, 0.8, 0.3)]):
            ch.add(sphere((0.08 + i * 0.035, 1.06, 0.225), 0.011, "chest", c, mat="shiny", k=0.0))
        # Helmet ring and bubble with a gold visor.
        ch.add(torus((0, 1.48, 0.0), 0.15, 0.035, "chest", grey, mat="metal"))
        ch.add(sphere((0, 1.68, 0.01), 0.22, "head", white, mat="cloth", k=0.02))
        ch.add(ellipsoid((0, 1.67, 0.17), (0.17, 0.13, 0.12), "head", white, mat="cloth", sub=True, k=0.01))
        ch.add(ellipsoid((0, 1.67, 0.12), (0.168, 0.128, 0.12), "head", (1.0, 0.72, 0.25), mat="metal", k=0.0))
        limb_shells(ch, s, white, white, arm_r=0.08, leg_r=0.11)
        for side, x in (("l", -1), ("r", 1)):
            el, kn = J(s, f"elbow_{side}"), J(s, f"knee_{side}")
            ch.add(torus(el, 0.08, 0.016, f"elbow_{side}", grey, mat="metal"))
            ch.add(torus(kn, 0.1, 0.018, f"knee_{side}", grey, mat="metal"))
            ch.add(ellipsoid((x * 0.1, 0.08, 0.05), (0.08, 0.09, 0.16), f"foot_{side}", white, mat="cloth", k=0.03))
            ch.add(box((x * 0.1, 0.02, 0.05), (0.082, 0.02, 0.16), f"foot_{side}", grey, r=0.01, mat="cloth"))
        # Stars-and-stripes patch on the right shoulder.
        sh = J(s, "shoulder_r")
        ch.add(box(sh + np.array([0.05, -0.07, 0.0]), (0.012, 0.035, 0.05), "shoulder_r",
                   stripes((0.85, 0.1, 0.1), WHITE, axis=1, period=0.012), r=0.003, mat="cloth", k=0.0))
    return dict(cap=None, backpack=False, hands=white, boots=None, extra=extra, name="Astronaut")


def disco(s):
    gold = sparkle((0.95, 0.72, 0.2))
    def extra(ch, s):
        ch.add(sphere((0, 1.75, -0.04), 0.27, "head", (0.18, 0.1, 0.06), mat="cloth", noise=(0.02, 22.0), k=0.03))
        ch.add(face_hole((0.18, 0.1, 0.06), z=0.19, rx=0.12, ry=0.15))
        # Sunglasses, giant collar, medallion, bell bottoms, platform shoes.
        for x in (-1, 1):
            ch.add(ellipsoid((x * 0.052, 1.685, 0.142), (0.042, 0.03, 0.012), "head", (0.08, 0.05, 0.12), mat="shiny", k=0.0))
            ch.add(ellipsoid((x * 0.12, 1.43, 0.1), (0.1, 0.012, 0.07), "chest", WHITE, mat="cloth", rot=(0.4, x * 0.5, x * 0.3), k=0.0))
        ch.add(capsule((-0.05, 1.685, 0.15), (0.05, 1.685, 0.15), 0.006, "head", (0.8, 0.7, 0.3), mat="metal", k=0.0))
        ch.add(cylinder((0, 1.24, 0.13), (0, 1.24, 0.14), 0.045, "chest", (1.0, 0.85, 0.3), mat="metal"))
        for side, x in (("l", -1), ("r", 1)):
            kn, ft = J(s, f"knee_{side}"), J(s, f"foot_{side}")
            ch.add(capsule(kn, ft + np.array([0, 0.06, 0]), 0.075, f"knee_{side}", gold, rb=0.14, mat="shiny", k=0.02))
            ch.add(box((x * 0.1, 0.06, 0.05), (0.07, 0.06, 0.13), f"foot_{side}", (0.95, 0.95, 0.95), r=0.02, mat="shiny"))
    return dict(cap=None, hair=None, backpack=False, torso=gold, pockets=None, upper_arm=gold, cuff=None, forearm=gold,
                hips=gold, belt=(0.95, 0.95, 0.95), thigh=gold, shin=gold, boots=None, extra=extra, name="Disco King")


def pirate(s):
    coat = (0.6, 0.08, 0.1); gold = (0.95, 0.75, 0.25); cream = (0.92, 0.88, 0.76)
    def coat_col(p):
        out = np.tile(np.array(coat), (len(p), 1))
        front = (np.abs(p[:, 0]) < 0.06) & (p[:, 2] > 0)
        out[front] = cream
        return out
    def extra(ch, s):
        # Coat tails, gold buttons, tall black boots.
        ch.add(ellipsoid((0, 0.72, -0.05), (0.23, 0.3, 0.15), "hips", coat, mat="cloth", k=0.04))
        for y in (1.32, 1.2, 1.08, 0.96):
            for x in (-0.075, 0.075):
                ch.add(sphere((x, y, 0.125), 0.014, "chest" if y > 1.15 else "spine", gold, mat="metal", k=0.0))
        for side, x in (("l", -1), ("r", 1)):
            kn, ft = J(s, f"knee_{side}"), J(s, f"foot_{side}")
            ch.add(capsule(ft + np.array([0, 0.03, 0]), kn + np.array([0, 0.06, 0]), 0.075, f"knee_{side}", BLACK, mat="shiny", k=0.02))
            ch.add(ellipsoid(kn + np.array([0, 0.08, 0.02]), (0.09, 0.06, 0.09), f"knee_{side}", BLACK, mat="shiny", k=0.01))
            ch.add(ellipsoid((x * 0.1, 0.06, 0.06), (0.065, 0.06, 0.15), f"foot_{side}", BLACK, mat="shiny", k=0.02))
            el = J(s, f"elbow_{side}")
            ch.add(torus(el + np.array([0, -0.18, 0.01]), 0.05, 0.022, f"elbow_{side}", WHITE, mat="cloth", noise=(0.006, 50.0)))
        # Tricorn hat with a skull, eye patch and a magnificent ginger beard.
        ch.add(ellipsoid((0, 1.8, 0.0), (0.27, 0.045, 0.25), "head", BLACK, mat="cloth", k=0.02))
        for a in (0.0, 2.1, 4.2):
            ch.add(ellipsoid((math.sin(a) * 0.17, 1.84, math.cos(a) * 0.17), (0.13, 0.06, 0.035), "head", BLACK, mat="cloth",
                             rot=(0.0, a, 0.0), k=0.02))
        ch.add(ellipsoid((0, 1.87, 0.0), (0.15, 0.08, 0.15), "head", BLACK, mat="cloth", k=0.03))
        ch.add(torus((0, 1.82, 0.0), 0.22, 0.008, "head", gold, mat="metal"))
        ch.add(sphere((0, 1.86, 0.17), 0.024, "head", WHITE, mat="shiny", k=0.0))
        ch.add(ellipsoid((0.052, 1.688, 0.135), (0.034, 0.03, 0.012), "head", BLACK, mat="cloth", k=0.0))
        ch.add(torus((0, 1.7, 0.0), 0.142, 0.005, "head", BLACK, mat="cloth", rot=(0.3, 0, 0.25)))
        ch.add(ellipsoid((0, 1.53, 0.1), (0.12, 0.11, 0.07), "head", (0.75, 0.35, 0.1), mat="cloth", noise=(0.012, 35.0), k=0.03))
        ch.add(capsule((-0.06, 1.6, 0.14), (0.06, 1.6, 0.14), 0.015, "head", (0.75, 0.35, 0.1), mat="cloth", k=0.01))
        # A parrot on the shoulder (sits on the chest so it doesn't fly off when the arm moves).
        px, py, pz = -0.21, 1.52, -0.02
        ch.add(ellipsoid((px, py, pz), (0.05, 0.08, 0.06), "chest", (0.85, 0.12, 0.1), mat="shiny", k=0.02))
        ch.add(sphere((px, py + 0.1, pz + 0.02), 0.045, "chest", (0.85, 0.12, 0.1), mat="shiny", k=0.02))
        ch.add(ellipsoid((px, py + 0.09, pz + 0.07), (0.018, 0.024, 0.03), "chest", (0.95, 0.85, 0.2), mat="shiny", rot=(0.6, 0, 0), k=0.0))
        googly(ch, "chest", (px - 0.03, py + 0.115, pz + 0.045), 0.014, look=(-0.6, 0, 0.8))
        googly(ch, "chest", (px + 0.03, py + 0.115, pz + 0.045), 0.014, look=(0.6, 0, 0.8))
        for x in (-1, 1):
            ch.add(ellipsoid((px + x * 0.045, py - 0.01, pz - 0.01), (0.015, 0.065, 0.045), "chest", (0.15, 0.4, 0.85), mat="shiny", k=0.01))
        ch.add(capsule((px, py - 0.06, pz - 0.04), (px, py - 0.2, pz - 0.1), 0.02, "chest", (0.95, 0.8, 0.15), rb=0.008, mat="shiny", k=0.01))
    return dict(cap=None, hair=(0.75, 0.35, 0.1), backpack=False, torso=coat_col, pockets=None, upper_arm=coat, cuff=coat, forearm=coat,
                hips=cream, belt=(0.25, 0.15, 0.08), thigh=cream, shin=cream, boots=None, extra=extra, name="Pirate Captain")


def clown(s):
    suit = dots((0.55, 0.25, 0.8), [(1, 0.85, 0.1), (0.2, 0.8, 0.3), (1, 0.3, 0.3), (0.3, 0.7, 1)], scale=0.07)
    rainbow = lambda p: np.stack([0.5 + 0.5 * np.sin(p[:, 1] * 25), 0.5 + 0.5 * np.sin(p[:, 1] * 25 + 2.1),
                                  0.5 + 0.5 * np.sin(p[:, 1] * 25 + 4.2)], 1)
    def extra(ch, s):
        for x in (-1, 1):
            ch.add(sphere((x * 0.17, 1.7, -0.03), 0.12, "head", rainbow, mat="cloth", noise=(0.02, 25.0), k=0.03))
        ch.add(sphere((0, 1.84, -0.04), 0.1, "head", rainbow, mat="cloth", noise=(0.02, 25.0), k=0.03))
        ch.add(sphere((0, 1.645, 0.17), 0.05, "head", (0.95, 0.08, 0.08), mat="shiny", k=0.0))
        ch.add(capsule((-0.06, 1.592, 0.135), (0.06, 1.592, 0.135), 0.02, "head", (0.85, 0.1, 0.12), mat="shiny", k=0.0))
        # Ruffle collar, pom-pom buttons, enormous shoes.
        for i in range(14):
            a = i / 14 * 2 * math.pi
            ch.add(ellipsoid((math.sin(a) * 0.14, 1.46, math.cos(a) * 0.13), (0.06, 0.035, 0.06), "chest", WHITE, mat="cloth",
                             rot=(0.0, a, 0.0), k=0.02))
        for y in (1.3, 1.15, 1.0):
            ch.add(sphere((0, y, 0.13), 0.028, "chest" if y > 1.15 else "spine", WHITE, mat="cloth", noise=(0.006, 60.0), k=0.0))
        for side, x in (("l", -1), ("r", 1)):
            ch.add(ellipsoid((x * 0.11, 0.07, 0.12), (0.09, 0.07, 0.26), f"foot_{side}", (0.9, 0.1, 0.1), mat="shiny", k=0.03))
        limb_shells(ch, s, suit, suit, arm_r=0.08, leg_r=0.11)
    return dict(cap=None, hair=None, backpack=False, face=(0.98, 0.97, 0.95), torso=suit, pockets=None, upper_arm=suit, cuff=None,
                forearm=suit, hips=suit, belt=None, thigh=suit, shin=suit, boots=None, hands=WHITE, extra=extra, name="Clown")


def tinfoil_tux(s):
    def jacket(p):
        out = np.tile(np.array(BLACK, float), (len(p), 1))
        v = (np.abs(p[:, 0]) < 0.03 + (1.42 - p[:, 1]) * 0.12) & (p[:, 2] > 0) & (p[:, 1] > 1.1)
        out[v] = WHITE
        return out
    def extra(ch, s):
        ch.add(capsule((0, 1.76, 0.0), (0, 2.18, -0.02), 0.165, "head", (0.82, 0.83, 0.86), rb=0.01, mat="metal", noise=(0.006, 45.0), k=0.01))
        ch.add(cylinder((0, 1.76, 0.0), (0, 1.775, 0.0), 0.17, "head", (0.82, 0.83, 0.86), mat="metal"))
        ch.add(cylinder((0, 2.17, -0.02), (0, 2.3, -0.02), 0.005, "head", (0.7, 0.7, 0.72), mat="metal"))
        ch.add(sphere((0, 2.31, -0.02), 0.015, "head", (0.9, 0.2, 0.2), mat="shiny", k=0.0))
        for x in (-1, 1):
            ch.add(ellipsoid((x * 0.035, 1.43, 0.11), (0.035, 0.022, 0.012), "chest", BLACK, mat="shiny", rot=(0, 0, x * 0.3), k=0.005))
            ch.add(ellipsoid((x * 0.09, 1.3, 0.115), (0.06, 0.13, 0.012), "chest", (0.12, 0.12, 0.14), mat="shiny", rot=(0, 0, x * 0.35), k=0.0))
        ch.add(sphere((0, 1.43, 0.115), 0.012, "chest", BLACK, mat="shiny", k=0.0))
        ch.add(torus((0.052, 1.685, 0.142), 0.032, 0.004, "head", (0.95, 0.78, 0.3), mat="metal", rot=(1.5708, 0, 0)))
        ch.add(ellipsoid((0.06, 1.33, 0.13), (0.025, 0.015, 0.005), "chest", (0.9, 0.15, 0.2), mat="cloth", k=0.0))
    return dict(cap=None, backpack=False, torso=jacket, pockets=None, upper_arm=BLACK, cuff=WHITE, forearm=BLACK,
                hips=BLACK, belt=None, thigh=BLACK, shin=BLACK, boots=(0.03, 0.03, 0.04), extra=extra, name="Tinfoil Tux")


def superfan(s):
    pink = (0.95, 0.68, 0.66)
    def tee(p):
        out = np.tile(np.array((0.075, 0.075, 0.085)), (len(p), 1))
        d = np.hypot(p[:, 0], p[:, 1] - 1.26)
        logo = (d < 0.055) & (p[:, 2] > 0)
        out[logo] = WHITE
        inner = (d < 0.035) & (p[:, 2] > 0) & (p[:, 1] > 1.255)
        out[inner] = pink
        return out
    def extra(ch, s):
        # A giant foam toe hat, nail facing forward (like a cheesehead, but a toe). "TOE'S #1."
        ch.add(ellipsoid((0, 1.79, -0.01), (0.16, 0.08, 0.16), "head", pink, mat="cloth", k=0.03))
        ch.add(capsule((0, 1.82, -0.02), (0, 2.18, 0.0), 0.12, "head", pink, rb=0.105, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 2.14, 0.085), (0.075, 0.085, 0.03), "head", (0.99, 0.86, 0.86), mat="shiny", rot=(-0.2, 0, 0), k=0.0))
        ch.add(ellipsoid((0, 2.21, 0.1), (0.07, 0.018, 0.02), "head", WHITE, mat="shiny", rot=(-0.2, 0, 0), k=0.0))
        for y in (1.95, 1.99):
            ch.add(torus((0, y, 0.0), 0.118, 0.005, "head", (0.85, 0.55, 0.55), mat="cloth"))
        # Toe-pink wristbands.
        for side in ("l", "r"):
            el, h = J(s, f"elbow_{side}"), J(s, f"hand_{side}")
            ch.add(torus(h + (el - h) * 0.15, 0.045, 0.016, f"elbow_{side}", pink, mat="cloth", rot=(0, 0, 0)))
    return dict(cap=None, backpack=False, torso=tee, pockets=None, upper_arm=(0.075, 0.075, 0.085), cuff=None, extra=extra,
                name="Toe Superfan")


def shark(s):
    grey = (0.46, 0.53, 0.62)
    def hide(p):
        out = np.tile(np.array(grey), (len(p), 1))
        m = (p[:, 2] > 0.1) & (np.abs(p[:, 0]) < 0.17)
        out[m] = (0.93, 0.93, 0.92)
        return out
    def extra(ch, s):
        ch.add(capsule((0, 0.78, 0.0), (0, 1.45, 0.0), 0.27, "spine", hide, rb=0.27, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 1.78, 0.0), (0.25, 0.32, 0.27), "chest", hide, mat="cloth", k=0.06))
        ch.add(face_hole(hide, z=0.18, rx=0.125, ry=0.15, bone="chest"))
        # Teeth all round the mouth (your face), eyes high on the sides, fins.
        for i in range(18):
            a = i / 18 * 2 * math.pi
            c = (math.cos(a) * 0.13, 1.645 + math.sin(a) * 0.155, 0.2)
            ch.add(ellipsoid(c, (0.014, 0.028, 0.012), "chest", WHITE, mat="shiny", rot=(0, 0, a + math.pi / 2), k=0.0))
        for x in (-1, 1):
            ch.add(sphere((x * 0.2, 1.9, 0.12), 0.03, "chest", BLACK, mat="shiny", k=0.0))
            ch.add(ellipsoid((x * 0.28, 1.12, 0.02), (0.14, 0.025, 0.08), "spine", grey, mat="cloth", rot=(0, 0, x * -0.5), k=0.03))
        ch.add(ellipsoid((0, 2.12, -0.12), (0.025, 0.17, 0.14), "chest", grey, mat="cloth", rot=(-0.6, 0, 0), k=0.04))
        ch.add(capsule((0, 0.9, -0.22), (0, 0.55, -0.72), 0.16, "hips", grey, rb=0.05, mat="cloth", k=0.05))
        ch.add(ellipsoid((0, 0.62, -0.78), (0.025, 0.2, 0.08), "hips", grey, mat="cloth", rot=(0.4, 0, 0), k=0.03))
    return dict(cap=None, backpack=False, hair=None, torso=grey, pockets=None, upper_arm=grey, cuff=None, forearm=grey,
                hips=grey, belt=None, thigh=grey, shin=grey, boots=(0.3, 0.33, 0.38), extra=extra, name="Shark Attack")


SKINS = {
    "hawaiian": hawaiian_dad, "ghillie": ghillie, "bigfoot": bigfoot_onesie, "banana": banana, "hotdog": hot_dog,
    "trex": t_rex, "astronaut": astronaut, "disco": disco, "pirate": pirate, "clown": clown, "tux": tinfoil_tux,
    "superfan": superfan, "shark": shark,
}
