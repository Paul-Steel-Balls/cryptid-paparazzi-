#!/usr/bin/env python3
"""All Cryptid Paparazzi characters, sculpted with charkit.
Usage: python3 tools/characters.py <out_dir> [name ...]"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from charkit import *

OUT = sys.argv[1] if len(sys.argv) > 1 else "models"
ONLY = set(sys.argv[2:])
os.makedirs(OUT, exist_ok=True)
PI = math.pi

SKIN = (0.93, 0.72, 0.56)
BLACK = (0.05, 0.05, 0.06)
WHITE = (0.95, 0.95, 0.93)

def cartoon_eyes(ch, bone, cy, cz, spacing, r, pupil_col=BLACK, white=WHITE, look=(0, 0, 1), y_tilt=0.0, pupil_scale=0.5):
    for s in (-1, 1):
        c = np.array([s * spacing, cy + s * y_tilt, cz])
        ch.add(sphere(c, r, bone, white, mat="shiny", k=0.0, sharp=0.004))
        pc = c + np.array(look) * r * 0.75
        ch.add(sphere(pc, r * pupil_scale, bone, pupil_col, mat="shiny", k=0.0, sharp=0.003))

def hand(ch, bone, c, r, color, fingers_dir=(0, -1, 0), side=1):
    c = np.asarray(c, float)
    ch.add(ellipsoid(c, (r * 0.9, r * 1.1, r * 0.6), bone, color, k=0.02))
    d = np.asarray(fingers_dir, float); d /= np.linalg.norm(d)
    ch.add(capsule(c + np.array([side * r * 0.7, r * 0.1, r * 0.3]), c + np.array([side * r * 1.2, -r * 0.2, r * 0.7]), r * 0.3, bone, color, k=0.015))

def boot(ch, bone, x, color, sole=(0.12, 0.08, 0.06), length=0.13, h=0.07):
    ch.add(ellipsoid((x, h, 0.04), (0.06, h, length), bone, color, k=0.02))
    ch.add(box((x, 0.015, 0.04), (0.062, 0.015, length * 0.95), bone, sole, r=0.012, k=0.01))

# =============================================================================== PHOTOGRAPHER
def photographer(skin="default"):
    """The player. skin picks an outfit from SKINS (tools/skins.py): same skeleton and
    animations, so every outfit walks, aims and holds the camera exactly the same."""
    s = humanoid(Skeleton(), hips_y=0.95, shoulder_w=0.2, shoulder_y=1.40, neck_y=1.48, hip_w=0.1,
                 knee_y=0.52, ankle_y=0.1, head_y=1.58, elbow_drop=0.26, wrist_drop=0.23, arm_out=0.1)
    # Outfits are sculpted a touch coarser: they're bigger and smoother, and there are a lot of them.
    ch = Character("photographer" if skin == "default" else "photographer_" + skin, s, voxel=0.014 if skin == "default" else 0.018)
    if skin != "default":
        ch.group_voxel = {"cloth": 0.017, "shiny": 0.011, "metal": 0.013}
    shirt = (0.15, 0.55, 0.6); vest = (0.62, 0.55, 0.36); vest_d = (0.5, 0.43, 0.27)
    jeans = speckle((0.2, 0.3, 0.55), 0.08, 40); boots = (0.38, 0.24, 0.12); red = (0.85, 0.12, 0.1)
    def torso_col(p):
        out = np.tile(np.array(vest, float), (len(p), 1))
        front = (np.abs(p[:, 0]) < 0.045 + (1.42 - p[:, 1]) * 0.05) & (p[:, 2] > 0)
        out[front] = shirt
        return out
    L = dict(face=SKIN, hair=(0.35, 0.22, 0.12), cap=red, torso=torso_col, pockets=vest_d, hips=jeans, belt=(0.3, 0.2, 0.1),
             backpack=True, upper_arm=shirt, cuff=shirt, forearm=SKIN, hands=SKIN, thigh=jeans, shin=jeans, boots=boots,
             eyes=True, extra=None)
    if skin != "default":
        import skins as _skins
        L.update(_skins.SKINS[skin](s))
    face = L["face"]
    # head
    ch.add(ellipsoid((0, 1.66, 0.01), (0.135, 0.155, 0.14), "head", face, k=0.02))
    ch.add(ellipsoid((0, 1.6, 0.06), (0.11, 0.08, 0.1), "head", face, k=0.04))  # cheeks/jaw
    ch.add(sphere((0, 1.645, 0.155), 0.034, "head", L.get("nose", (0.95, 0.62, 0.5)), k=0.02))   # nose
    ch.add(mirror(lambda x: ellipsoid((x * 0.135, 1.65, 0.0), (0.025, 0.045, 0.032), "head", face, k=0.015)))
    if L["eyes"]:
        cartoon_eyes(ch, "head", 1.685, 0.118, 0.052, 0.027)
        ch.add(mirror(lambda x: capsule((x * 0.025, 1.725, 0.135), (x * 0.08, 1.735, 0.12), 0.011, "head", (0.3, 0.2, 0.12), k=0.004)))
    ch.add(capsule((-0.04, 1.595, 0.135), (0.04, 1.6, 0.135), 0.009, "head", L.get("mouth", (0.55, 0.2, 0.2)), k=0.006))
    if L["hair"] is not None:
        ch.add(ellipsoid((0, 1.67, -0.06), (0.14, 0.12, 0.1), "head", L["hair"], k=0.02, noise=(0.006, 30)))  # hair
    # cap
    if L["cap"] is not None:
        ch.add(ellipsoid((0, 1.745, 0.0), (0.15, 0.085, 0.155), "head", L["cap"], k=0.008))
        dark = (0.75, 0.08, 0.08) if skin == "default" else tuple(np.array(L["cap"]) * 0.88)
        ch.add(ellipsoid((0, 1.735, 0.15), (0.11, 0.012, 0.1), "head", dark, k=0.004))
        ch.add(sphere((0, 1.83, 0.0), 0.018, "head", dark, k=0.006))
    # neck + torso
    ch.add(capsule((0, 1.44, 0), (0, 1.56, 0.01), 0.055, "neck", L.get("neck", face), k=0.02))
    ch.add(ellipsoid((0, 1.24, 0), (0.2, 0.23, 0.125), "chest", L["torso"], k=0.03))
    ch.add(ellipsoid((0, 1.06, 0.0), (0.18, 0.14, 0.12), "spine", L["torso"], k=0.05))
    if L["pockets"] is not None:
        for x in (-0.1, 0.1):
            ch.add(box((x, 1.1, 0.12), (0.045, 0.04, 0.015), "spine", L["pockets"], r=0.01, k=0.005))
            ch.add(box((x, 1.28, 0.12), (0.04, 0.035, 0.013), "chest", L["pockets"], r=0.01, k=0.005))
    ch.add(ellipsoid((0, 0.93, 0), (0.17, 0.11, 0.115), "hips", L["hips"], k=0.04))
    if L["belt"] is not None:
        ch.add(box((0, 0.99, 0.0), (0.172, 0.018, 0.118), "hips", L["belt"], r=0.015, k=0.006))  # belt
    # backpack
    if L["backpack"]:
        ch.add(box((0, 1.22, -0.17), (0.14, 0.19, 0.07), "chest", (0.75, 0.4, 0.12), r=0.04, k=0.02))
        ch.add(box((0, 1.12, -0.24), (0.1, 0.07, 0.03), "chest", (0.62, 0.32, 0.1), r=0.02, k=0.01))
    # (the camera itself is models/camera.glb, hung on the chest bone in the game at about (0, 1.23, 0.19))
    # arms (sleeves rolled to the elbow)
    for side, x in (("l", -1), ("r", 1)):
        sh = np.array(s.heads[s.idx(f"shoulder_{side}")]); el = np.array(s.heads[s.idx(f"elbow_{side}")]); hd = np.array(s.heads[s.idx(f"hand_{side}")])
        # (Outfits with their own baggy sleeves leave the arms underneath out, so no shirt pokes through.)
        if not L.get("arms_hidden", False):
            ch.add(capsule(sh, el, 0.058, f"shoulder_{side}", L["upper_arm"], rb=0.05, k=0.03))
            if L["cuff"] is not None:
                ch.add(torus(el + np.array([0, 0.01, 0]), 0.048, 0.016, f"elbow_{side}", L["cuff"], k=0.01))
            ch.add(capsule(el, hd, 0.045, f"elbow_{side}", L["forearm"], rb=0.038, k=0.02))
        hand(ch, f"hand_{side}", hd + np.array([0, -0.05, 0.0]), 0.045, L["hands"], side=-x)
        # legs
        hp = np.array(s.heads[s.idx(f"hip_{side}")]); kn = np.array(s.heads[s.idx(f"knee_{side}")]); ft = np.array(s.heads[s.idx(f"foot_{side}")])
        ch.add(capsule(hp, kn, 0.08, f"hip_{side}", L["thigh"], rb=0.066, k=0.03))
        ch.add(capsule(kn, ft + np.array([0, 0.04, 0]), 0.066, f"knee_{side}", L["shin"], rb=0.055, k=0.02))
        if L["boots"] is not None:
            boot(ch, f"foot_{side}", x * 0.1, L["boots"])
    if L["extra"] is not None:
        L["extra"](ch, s)
    hl, el_ = solve_arm(s, "l", (-0.1, 1.2, 0.17)); hr, er_ = solve_arm(s, "r", (0.1, 1.2, 0.17))
    print(f"  camera grip IK error: {el_:.3f} / {er_:.3f} m")
    hold_pose = {**hl, **hr}
    hold = lambda t: hold_pose
    ch.anim("idle", 3.0, override(idle_cycle(), hold))
    ch.anim("walk", 1.0, override(walk_cycle(stride=0.45, arm=0.0, bob=0.03), hold))
    ch.anim("jog", 0.72, override(walk_cycle(stride=0.62, arm=0.0, bob=0.055, lean=0.12, knee=1.0, twist=0.1, sway=0.03, speed=1.0 / 0.72), hold))
    ch.anim("run", 0.62, override(walk_cycle(stride=0.8, arm=0.0, bob=0.07, lean=0.22, knee=1.25, twist=0.12, sway=0.03, speed=1.0 / 0.62), hold))
    # Jump: knees tucked, camera clutched, a little lean back.
    ch.anim("jump", 1.0, override(lambda t: {"hip_l": (-0.9, 0, -0.05), "hip_r": (-0.5, 0, 0.05), "knee_l": (1.4, 0, 0), "knee_r": (1.0, 0, 0),
                                            "foot_l": (0.35, 0, 0), "foot_r": (0.25, 0, 0), "spine": (-0.08, 0, 0), "head": (0.1, 0, 0),
                                            "_hips_offset": (0, 0.06, 0)}, hold))
    # Raised camera (aiming): both hands bring it up to the eye.
    ch.anim("aim", 2.0, lambda t: {"shoulder_l": (-1.25, 0, 0.35), "shoulder_r": (-1.25, 0, -0.35), "elbow_l": (-1.45, 0.4, 0),
                                   "elbow_r": (-1.45, -0.4, 0), "head": (0.06, 0, 0), "chest": (0.02 * math.sin(2 * PI * t / 2.0), 0, 0)})
    def crouch_pose(t, breathe=True):
        b = 0.02 * math.sin(2 * PI * t / 2.0) if breathe else 0.0
        return {"hip_l": (-1.3, 0, -0.08), "hip_r": (-1.3, 0, 0.08), "knee_l": (2.0, 0, 0), "knee_r": (2.0, 0, 0),
                "foot_l": (-0.6, 0, 0), "foot_r": (-0.6, 0, 0), "spine": (0.35 + b, 0, 0), "head": (-0.3, 0.1 * math.sin(2 * PI * t / 4.0), 0),
                "_hips_offset": (0, -0.4, 0)}
    ch.anim("crouch", 4.0, override(crouch_pose, hold))
    def crouch_walk(t, dur=1.2):
        ph = 2 * PI * t / dur
        out = crouch_pose(t, breathe=False)
        for side, off in (("l", 0.0), ("r", PI)):
            sn, cs = math.sin(ph + off), math.cos(ph + off)
            lift = max(0.0, cs)
            out[f"hip_{side}"] = (-1.25 - 0.32 * sn - 0.12 * lift, 0, -0.08 if side == "l" else 0.08)
            out[f"knee_{side}"] = (1.95 + 0.35 * lift - 0.15 * sn, 0, 0)
            out[f"foot_{side}"] = (-0.62 + 0.28 * sn, 0, 0)
        out["hips"] = (0, 0.1 * math.sin(ph), 0.05 * math.cos(ph))
        out["spine"] = (0.42, -0.06 * math.sin(ph), -0.04 * math.cos(ph))
        out["head"] = (-0.38, 0.05 * math.sin(ph), 0)  # eyes up, scanning
        out["_hips_offset"] = (0, -0.42 + 0.025 * (abs(math.cos(ph)) - 0.5), 0)
        return out
    ch.anim("crouch_walk", 1.2, override(crouch_walk, hold))
    ch.anim("snap", 0.5, lambda t: {"shoulder_l": (-1.3, 0, 0.3), "shoulder_r": (-1.3, 0, -0.3), "elbow_l": (-1.3, 0.4, 0),
                                    "elbow_r": (-1.3, -0.4, 0), "chest": (-0.1, 0, 0)})
    # Behind the wheel: seated, hands at ten and two, steering a little, nodding along to the road.
    def drive(t, dur=4.0):
        ph = 2 * PI * t / dur
        steer = 0.12 * math.sin(ph) + 0.05 * math.sin(ph * 3.0)
        return {"hip_l": (-1.5, 0, -0.06), "hip_r": (-1.5, 0, 0.06), "knee_l": (1.45, 0, 0), "knee_r": (1.45, 0, 0),
                "foot_l": (0.1, 0, 0), "foot_r": (0.1, 0, 0), "spine": (-0.08, 0, 0), "chest": (0.04, 0, 0),
                "shoulder_l": (-1.3, 0.1, 0.32 + steer), "shoulder_r": (-1.3, -0.1, -0.32 + steer),
                "elbow_l": (-0.45, 0.3, 0), "elbow_r": (-0.45, -0.3, 0),
                "head": (0.05 + 0.04 * math.sin(ph * 2.0), 0.15 * math.sin(ph * 0.5), 0),
                "_hips_offset": (0, -0.43 + 0.006 * math.sin(ph * 8.0), -0.05)}
    ch.anim("drive", 4.0, drive)
    _emotes(ch)
    return ch


def _emotes(ch):
    """Emote wheel animations (emote_<id>). The camera stays slung on the chest strap; arms are free.
    Convention here: shoulder x<0 swings the arm forward, right arm z>0 / left arm z<0 lifts it out
    to the side; elbow x<0 bends the forearm up/forward."""
    S = math.sin; C = math.cos
    rest = {"shoulder_l": (0.05, 0, -0.12), "shoulder_r": (0.05, 0, 0.12), "elbow_l": (-0.15, 0, 0), "elbow_r": (-0.15, 0, 0)}
    def with_rest(fn):
        return lambda t: {**rest, **fn(t)}
    # Wave: right arm up high, hand waving side to side, head tilted, friendly.
    ch.anim("emote_wave", 2.4, with_rest(lambda t: {
        "shoulder_r": (-0.2, 0, 2.5), "elbow_r": (0, 0, 0.35 + 0.45 * S(2 * PI * t / 0.5)),
        "head": (0, 0.1, -0.12), "chest": (0, 0.05, -0.04 * S(2 * PI * t / 0.5))}))
    # Thumbs up: arm out front, forearm up, a couple of nods.
    ch.anim("emote_thumbs", 2.0, with_rest(lambda t: {
        "shoulder_r": (-1.2, 0, -0.15), "elbow_r": (-1.1, 0, 0), "head": (0.12 * max(0.0, S(2 * PI * t / 0.7)), 0, 0),
        "chest": (-0.05, 0, 0)}))
    # Point and laugh: right arm pointing, left hand on the belly, doubled over cackling.
    ch.anim("emote_laugh", 2.8, with_rest(lambda t: {
        "shoulder_r": (-1.45, 0, 0.05), "elbow_r": (-0.1, 0, 0),
        "shoulder_l": (-0.5, 0, 0.35), "elbow_l": (-1.7, 0, 0),
        "spine": (0.12 + 0.12 * abs(S(2 * PI * t / 0.36)), 0, 0), "head": (-0.35 + 0.1 * S(2 * PI * t / 0.36), 0, 0),
        "_hips_offset": (0, -0.02 * abs(S(2 * PI * t / 0.36)), 0)}))
    # Facepalm: hand to the face, head down, slow shake.
    ch.anim("emote_facepalm", 2.6, with_rest(lambda t: {
        "shoulder_r": (-1.35, 0, -0.55), "elbow_r": (-2.25, 0.25, 0), "head": (0.4, 0.15 * S(2 * PI * t / 1.3), 0),
        "neck": (0.15, 0, 0), "chest": (0.1, 0, 0), "spine": (0.08, 0, 0)}))
    # Flex: double biceps, puffing up and pulsing.
    def flex(t):
        p = 0.12 * S(2 * PI * t / 0.6)
        return {"shoulder_l": (0, 0, -1.45), "shoulder_r": (0, 0, 1.45), "elbow_l": (0, 0, -1.5 - p), "elbow_r": (0, 0, 1.5 + p),
                "chest": (-0.12, 0, 0), "head": (-0.12, 0.2 * S(2 * PI * t / 2.4), 0), "_hips_offset": (0, 0.01 * S(2 * PI * t / 0.6), 0)}
    ch.anim("emote_flex", 2.4, flex)
    # Chicken dance: flapping elbows, pecking head, bouncing knees.
    def chicken(t):
        f = 0.5 + 0.5 * S(2 * PI * t / 0.5)
        k = abs(S(2 * PI * t / 1.0))
        return {"shoulder_l": (-0.2, 0, -0.35 - 0.7 * f), "shoulder_r": (-0.2, 0, 0.35 + 0.7 * f),
                "elbow_l": (-2.3, 0, 0), "elbow_r": (-2.3, 0, 0),
                "head": (0.35 * max(0.0, S(2 * PI * t / 0.5)), 0, 0), "neck": (0.1, 0, 0),
                "hip_l": (-0.35 * k, 0, -0.05), "hip_r": (-0.35 * k, 0, 0.05), "knee_l": (0.7 * k, 0, 0), "knee_r": (0.7 * k, 0, 0),
                "foot_l": (-0.35 * k, 0, 0), "foot_r": (-0.35 * k, 0, 0), "spine": (0.15, 0, 0),
                "_hips_offset": (0, -0.08 * k, 0)}
    ch.anim("emote_chicken", 2.0, chicken)
    # Disco: point up to one corner, then down across; hips swaying, knees alternating.
    def disco(t):
        ph = 2 * PI * t / 1.0
        up = 0.5 + 0.5 * S(ph)
        sway = S(ph)
        return {"shoulder_r": (-0.4 * (1 - up), 0, 2.6 * up - 0.5 * (1 - up)), "elbow_r": (-0.1, 0, 0),
                "shoulder_l": (-0.2, 0, -0.25), "elbow_l": (-1.6, 0, 0), "hips": (0, 0.2 * sway, 0.08 * sway),
                "spine": (0, -0.15 * sway, -0.06 * sway), "head": (0, 0.2 * sway, 0.1 * up),
                "hip_l": (-0.3 * max(0.0, sway), 0, -0.05), "hip_r": (-0.3 * max(0.0, -sway), 0, 0.05),
                "knee_l": (0.6 * max(0.0, sway), 0, 0), "knee_r": (0.6 * max(0.0, -sway), 0, 0),
                "_hips_offset": (0.04 * sway, -0.03 * abs(sway), 0)}
    ch.anim("emote_disco", 2.0, disco)
    # Dizzy: arms out for balance, head lolling round, swaying and stumbling on the spot.
    def dizzy(t):
        ph = 2 * PI * t / 1.6
        return {"shoulder_l": (0, 0, -1.0 - 0.3 * S(ph)), "shoulder_r": (0, 0, 1.0 - 0.3 * S(ph)),
                "elbow_l": (-0.3, 0, -0.3 * S(ph * 2)), "elbow_r": (-0.3, 0, 0.3 * S(ph * 2)),
                "head": (0.2 * S(ph), 0.3 * C(ph), 0.25 * S(ph)), "spine": (0.08, 0, 0.18 * S(ph)),
                "hip_l": (-0.2 * max(0.0, S(ph)), 0, -0.1), "hip_r": (-0.2 * max(0.0, -S(ph)), 0, 0.1),
                "knee_l": (0.35, 0, 0), "knee_r": (0.35, 0, 0), "_hips_offset": (0.07 * S(ph), -0.04, 0)}
    ch.anim("emote_dizzy", 3.2, dizzy)

# =============================================================================== shared biped helpers
def H(s, name): return np.array(s.heads[s.idx(name)], float)

def biped_limbs(ch, s, arm_cols, leg_cols, r_arm=(0.06, 0.05, 0.042), r_leg=(0.085, 0.068, 0.055), k=0.03, noise=None):
    """Arm/leg capsules along the skeleton. arm_cols/leg_cols: (upper, lower) colours."""
    for side in ("l", "r"):
        sh, el, hd = H(s, f"shoulder_{side}"), H(s, f"elbow_{side}"), H(s, f"hand_{side}")
        ch.add(capsule(sh, el, r_arm[0], f"shoulder_{side}", arm_cols[0], rb=r_arm[1], k=k, noise=noise))
        ch.add(capsule(el, hd, r_arm[1], f"elbow_{side}", arm_cols[1], rb=r_arm[2], k=k * 0.7, noise=noise))
        hp, kn, ft = H(s, f"hip_{side}"), H(s, f"knee_{side}"), H(s, f"foot_{side}")
        ch.add(capsule(hp, kn, r_leg[0], f"hip_{side}", leg_cols[0], rb=r_leg[1], k=k, noise=noise))
        ch.add(capsule(kn, ft + np.array([0, 0.03, 0]), r_leg[1], f"knee_{side}", leg_cols[1], rb=r_leg[2], k=k * 0.7, noise=noise))

def claw_hand(ch, s, side, color, r, claw_col=None, fingers=4, length=1.4, noise=None):
    hd = H(s, f"hand_{side}"); sx = -1 if side == "l" else 1
    c = hd + np.array([sx * 0.01, -r * 0.9, 0.01])
    ch.add(ellipsoid(c, (r * 0.85, r * 1.05, r * 0.55), f"hand_{side}", color, k=0.02, noise=noise))
    for i in range(fingers):
        z = (i - (fingers - 1) / 2) * r * 0.45
        a = c + np.array([0, -r * 0.8, z]); b = a + np.array([sx * r * 0.15, -r * length * 0.6, z * 0.3])
        ch.add(capsule(a, b, r * 0.2, f"hand_{side}", color, rb=r * 0.16, k=0.012))
        if claw_col is not None:
            ch.add(capsule(b, b + np.array([0, -r * 0.35, r * 0.12]), r * 0.1, f"hand_{side}", claw_col, rb=r * 0.02, k=0.004, mat="shiny"))
    ch.add(capsule(c + np.array([0, -r * 0.2, r * 0.45]), c + np.array([sx * r * 0.2, -r * 0.9, r * 0.95]), r * 0.2, f"hand_{side}", color, k=0.012))

def big_foot(ch, s, side, color, length=0.2, width=0.09, height=0.07, toes=True, toe_col=None):
    ft = H(s, f"foot_{side}")
    c = np.array([ft[0], height, ft[2] + length * 0.35])
    ch.add(ellipsoid(c, (width, height, length), f"foot_{side}", color, k=0.03))
    if toes:
        for i in range(4):
            x = ft[0] + (i - 1.5) * width * 0.45
            ch.add(sphere((x, height * 0.6, c[2] + length * 0.9), width * 0.22, f"foot_{side}", toe_col or color, k=0.015))

def roar_anim(t):
    a = min(1.0, t * 4)
    return {"shoulder_l": (-0.4 * a, 0, -1.0 * a), "shoulder_r": (-0.4 * a, 0, 1.0 * a), "elbow_l": (-0.6 * a, 0, 0),
            "elbow_r": (-0.6 * a, 0, 0), "chest": (-0.25 * a, 0, 0), "head": (-0.35 * a + 0.05 * math.sin(t * 40), 0, 0),
            "spine": (-0.1 * a, 0, 0)}

def trapped_anim(t):
    ph = t * 2 * PI * 3
    return {"shoulder_l": (-2.6 + 0.5 * math.sin(ph), 0, -0.4), "shoulder_r": (-2.6 - 0.5 * math.sin(ph), 0, 0.4),
            "elbow_l": (-0.5, 0, 0), "elbow_r": (-0.5, 0, 0), "head": (-0.2, 0.4 * math.sin(ph * 0.5), 0),
            "hip_l": (-0.6 - 0.3 * math.sin(ph), 0, 0), "knee_l": (1.1, 0, 0), "hip_r": (0.1, 0, 0),
            "spine": (0, 0, 0.12 * math.sin(ph)), "_hips_offset": (0, 0.06 * abs(math.sin(ph)), 0)}

def eat_anim(t):
    ph = t * 2 * PI * 1.5
    l = max(0.0, math.sin(ph)); r = max(0.0, -math.sin(ph))
    return {"spine": (0.45, 0, 0), "chest": (0.2, 0, 0), "head": (0.1 + 0.1 * math.sin(ph * 2), 0, 0),
            "shoulder_l": (-1.2 - 0.9 * l, 0.2, 0.3), "elbow_l": (-1.4 * l - 0.3, 0, 0),
            "shoulder_r": (-1.2 - 0.9 * r, -0.2, -0.3), "elbow_r": (-1.4 * r - 0.3, 0, 0),
            "hip_l": (-1.0, 0, 0), "hip_r": (-1.0, 0, 0), "knee_l": (1.9, 0, 0), "knee_r": (1.9, 0, 0),
            "foot_l": (-0.7, 0, 0), "foot_r": (-0.7, 0, 0), "_hips_offset": (0, -0.38, 0.0)}

def std_anims(ch, walk_kw=None, run_kw=None, idle_kw=None, extra=None):
    walk_kw = walk_kw or {}; run_kw = run_kw or {}; idle_kw = idle_kw or {}
    ch.anim("idle", 3.0, merge(idle_cycle(**idle_kw), extra or (lambda t: {})))
    ch.anim("walk", 1.1, walk_cycle(**walk_kw))
    rk = dict(stride=0.8, arm=0.8, bob=0.07, lean=0.25, knee=1.2, speed=1 / 0.7); rk.update(run_kw)
    ch.anim("run", 0.7, walk_cycle(**rk))

# =============================================================================== BIGBOOBS (Bigfoot)
def bigboobs():
    s = humanoid(Skeleton(), hips_y=1.1, shoulder_w=0.36, shoulder_y=1.85, neck_y=1.95, hip_w=0.17,
                 knee_y=0.6, ankle_y=0.13, head_y=2.05, elbow_drop=0.42, wrist_drop=0.4, arm_out=0.16)
    ch = Character("bigboobs", s, voxel=0.022)
    furc = fur((0.45, 0.29, 0.15), 0.18, 18, 1.0); furl = fur((0.55, 0.37, 0.2), 0.14, 18, 2.0)
    skin = speckle((0.32, 0.22, 0.17), 0.08, 30)
    nz = (0.014, 22, 3.0)
    eyes = ch.glow("eyes_glow", (1.0, 0.78, 0.25))
    ch.add(ellipsoid((0, 1.6, -0.02), (0.44, 0.4, 0.3), "chest", furc, k=0.08, noise=nz))
    ch.add(ellipsoid((0, 1.28, 0.03), (0.38, 0.32, 0.3), "spine", furc, k=0.08, noise=nz))
    ch.add(ellipsoid((0, 1.06, -0.01), (0.33, 0.2, 0.26), "hips", furc, k=0.06, noise=nz))
    ch.add(ellipsoid((0, 1.02, -0.14), (0.3, 0.2, 0.16), "hips", furc, k=0.14, noise=nz))  # rump
    # the boobs: bare skin (no fur), cartoonishly huge, in a hot-pink tube top
    bare = speckle((0.36, 0.25, 0.2), 0.05, 30)
    boob_c = [np.array([x * 0.18, 1.48, 0.27]) for x in (-1, 1)]
    boob_r = np.array([0.18, 0.2, 0.17])
    boob_R = [rot_euler(0.25, 0, x * 0.2) for x in (-1, 1)]
    ch.add(mirror(lambda x: ellipsoid((x * 0.18, 1.48, 0.27), (0.18, 0.2, 0.17), "chest", bare, rot=(0.25, 0, x * 0.2), k=0.06)))
    top_lo, top_hi = 1.31, 1.61
    def tube_sdf(p):
        d = np.minimum(sd_ellipsoid(p, boob_c[0], boob_r, boob_R[0]), sd_ellipsoid(p, boob_c[1], boob_r, boob_R[1])) - 0.018
        band = sd_ellipsoid(p, np.array([0, 1.46, 0.0]), np.array([0.47, 0.3, 0.33]))
        d = smin(d, band, 0.07)
        slab = np.maximum(top_lo - p[:, 1], p[:, 1] - top_hi)
        return smax(d, slab, 0.012)
    def tube_col(p):
        pink, trim = np.array([0.98, 0.28, 0.6]), np.array([1.0, 0.72, 0.86])
        out = np.tile(pink, (len(p), 1)) * (1 + 0.05 * vnoise(p, 40, 5.0))[:, None]
        edge = (p[:, 1] > top_hi - 0.025) | (p[:, 1] < top_lo + 0.025)
        out[edge] = trim
        return np.clip(out, 0, 1)
    ch.add(Part(tube_sdf, "chest", tube_col, k=0.0, mat="cloth", bounds=(np.array([-0.62, 1.2, -0.45]), np.array([0.62, 1.72, 0.56]))))
    # pearl necklace
    for i in range(15):
        a = -PI * 0.42 + i / 14 * PI * 0.84
        y = 1.86 - 0.13 * (1 - abs(a) / (PI * 0.42)) ** 0.7
        ch.add(sphere((math.sin(a) * 0.27, y, math.cos(a) * 0.26 + 0.05), 0.03, "chest", (0.97, 0.95, 0.9), mat="shiny", k=0.0))
    # head
    ch.add(capsule((0, 1.86, 0.0), (0, 2.02, 0.03), 0.17, "neck", furc, k=0.07, noise=nz))
    ch.add(ellipsoid((0, 2.13, 0.03), (0.21, 0.24, 0.21), "head", furc, k=0.05, noise=nz))
    ch.add(ellipsoid((0, 2.32, -0.04), (0.11, 0.12, 0.15), "head", furc, k=0.07, noise=nz))  # crest
    ch.add(ellipsoid((0, 2.09, 0.17), (0.17, 0.17, 0.09), "head", skin, k=0.04))  # face
    ch.add(capsule((-0.13, 2.18, 0.21), (0.13, 2.18, 0.21), 0.045, "head", furc, k=0.03, noise=(0.006, 30)))  # brow
    ch.add(ellipsoid((0, 2.07, 0.25), (0.065, 0.045, 0.05), "head", (0.18, 0.12, 0.1), k=0.025))  # nose
    ch.add(mirror(lambda x: sphere((x * 0.025, 2.055, 0.29), 0.012, "head", BLACK, k=0.004)))
    ch.add(capsule((-0.07, 1.985, 0.215), (0.07, 1.985, 0.215), 0.022, "head", (0.85, 0.12, 0.2), k=0.01))  # red lips
    ch.add(mirror(lambda x: sphere((x * 0.08, 2.13, 0.225), 0.048, "head", (1.0, 0.8, 0.3), mat=eyes, k=0.0)))
    ch.add(mirror(lambda x: sphere((x * 0.08, 2.13, 0.268), 0.017, "head", BLACK, mat="shiny", k=0.0)))
    for x in (-1, 1):  # eyelashes
        for j in range(3):
            a = np.array([x * (0.05 + j * 0.025), 2.17, 0.25]); b = a + np.array([x * (0.012 + j * 0.016), 0.05, 0.02])
            ch.add(capsule(a, b, 0.008, "head", BLACK, k=0.0, mat="shiny"))
    ch.add(mirror(lambda x: ellipsoid((x * 0.2, 2.14, -0.0), (0.04, 0.06, 0.04), "head", furc, k=0.03)))
    biped_limbs(ch, s, (furc, furc), (furc, furc), r_arm=(0.13, 0.11, 0.09), r_leg=(0.17, 0.13, 0.1), k=0.06, noise=nz)
    for side in ("l", "r"):
        claw_hand(ch, s, side, skin, 0.11, fingers=4)
        big_foot(ch, s, side, skin, length=0.26, width=0.12, height=0.08)
    std_anims(ch, walk_kw=dict(stride=0.45, arm=0.55, bob=0.05, twist=0.12), run_kw=dict(stride=0.7, arm=0.9))
    ch.anim("eat", 1.4, eat_anim)
    ch.anim("trapped", 1.0, trapped_anim)
    ch.anim("roar", 1.2, roar_anim)
    return ch

# =============================================================================== pose helpers
def blend_pose(a, b, w):
    out = {}
    for k in set(a) | set(b):
        va = a.get(k, (0, 0, 0)); vb = b.get(k, (0, 0, 0))
        out[k] = tuple(x + (y - x) * w for x, y in zip(va, vb))
    return out
def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
def jitter(t, dur, amp=1.0):
    ph = 2 * PI * t / dur
    return amp * (0.5 * math.sin(23 * ph) + 0.3 * math.sin(37 * ph + 1.0) + 0.2 * math.sin(51 * ph + 2.0))

def dirty(base, stain=(0.55, 0.45, 0.28), amount=0.55, freq=5.0, seed=9.0):
    base, stain = np.asarray(base), np.asarray(stain)
    def f(p):
        n = np.clip(fbm(p, freq, 3, seed) * 1.6 - 0.15, 0, 1)[:, None] * amount
        return base * (1 - n) + stain * n
    return f
def seven_seg(digits, cx, cy, h, w_digit, thick, axis_x=0, facing=-1):
    """Mask function for big jersey numbers. Points with z*facing > 0 are on that side."""
    SEG = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}
    def mask(p):
        x = p[:, 0] * facing; y = p[:, 1]
        m = np.zeros(len(p), bool)
        n = len(digits)
        for i, d in enumerate(digits):
            ox = cx + (i - (n - 1) / 2) * w_digit * 1.35
            hw = w_digit / 2; hh = h / 2
            segs = {"a": (ox - hw, cy + hh - thick, ox + hw, cy + hh), "d": (ox - hw, cy - hh, ox + hw, cy - hh + thick),
                    "g": (ox - hw, cy - thick / 2, ox + hw, cy + thick / 2),
                    "f": (ox - hw, cy, ox - hw + thick, cy + hh), "b": (ox + hw - thick, cy, ox + hw, cy + hh),
                    "e": (ox - hw, cy - hh, ox - hw + thick, cy), "c": (ox + hw - thick, cy - hh, ox + hw, cy)}
            for sname in SEG[d]:
                x0, y0, x1, y1 = segs[sname]
                m |= (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)
        return m & (p[:, 2] * facing > 0)
    return mask

# =============================================================================== METHMAN (+ his camp)
def methman():
    s = humanoid(Skeleton(), hips_y=0.98, shoulder_w=0.19, shoulder_y=1.55, neck_y=1.63, hip_w=0.09,
                 knee_y=0.52, ankle_y=0.08, head_y=1.72, elbow_drop=0.3, wrist_drop=0.28, arm_out=0.08)
    s.add("wing_l", "chest", (-0.1, 1.48, -0.14)); s.add("wing_r", "chest", (0.1, 1.48, -0.14))
    ch = Character("methman", s, voxel=0.015)
    fz = fur((0.44, 0.41, 0.37), 0.16, 24, 5.0); nz = (0.007, 26, 6.0)
    red = ch.glow("eyes_red", (1.0, 0.08, 0.05)); lamp = ch.glow("lantern", (1.0, 0.82, 0.45))
    tank = dirty((0.92, 0.9, 0.84), (0.6, 0.5, 0.3), 0.6)
    shorts = speckle((0.55, 0.5, 0.3), 0.08, 30)
    # hunched torso
    ch.add(ellipsoid((0, 1.38, -0.01), (0.16, 0.19, 0.11), "chest", tank, rot=(0.25, 0, 0), k=0.03))
    ch.add(ellipsoid((0, 1.16, 0.0), (0.13, 0.15, 0.1), "spine", tank, k=0.04))
    ch.add(ellipsoid((0, 0.97, 0.0), (0.14, 0.1, 0.11), "hips", shorts, k=0.03))
    for x in (-1, 1):  # cargo pockets
        ch.add(box((x * 0.13, 0.86, 0.02), (0.035, 0.05, 0.045), f"hip_{'l' if x < 0 else 'r'}", (0.47, 0.42, 0.24), r=0.01, k=0.006))
    # neck + head (pushed forward: bad posture)
    ch.add(capsule((0, 1.52, -0.02), (0, 1.68, 0.07), 0.045, "neck", fz, k=0.03, noise=nz))
    ch.add(ellipsoid((0, 1.79, 0.07), (0.12, 0.135, 0.12), "head", fz, k=0.03, noise=nz))
    ch.add(ellipsoid((0, 1.72, 0.11), (0.075, 0.07, 0.08), "head", fz, k=0.03))
    ch.add(mirror(lambda x: ellipsoid((x * 0.07, 1.81, 0.155), (0.06, 0.072, 0.045), "head", (1.0, 0.15, 0.1), mat=red, rot=(0, x * 0.3, x * 0.35), k=0.0)))
    ch.add(capsule((-0.045, 1.7, 0.175), (0.045, 1.705, 0.17), 0.014, "head", (0.15, 0.05, 0.05), k=0.006))
    ch.add(box((-0.016, 1.688, 0.183), (0.011, 0.016, 0.006), "head", (0.92, 0.85, 0.4), r=0.003, k=0.0, mat="shiny"))
    ch.add(box((0.022, 1.69, 0.18), (0.01, 0.012, 0.006), "head", (0.8, 0.7, 0.3), r=0.003, k=0.0, mat="shiny", rot=(0, 0, 0.3)))
    # feathery antennae
    for x in (-1, 1):
        pts = [np.array([x * 0.04, 1.89, 0.11]), np.array([x * 0.11, 2.06, 0.17]), np.array([x * 0.2, 2.13, 0.12])]
        for a, b in zip(pts[:-1], pts[1:]):
            ch.add(capsule(a, b, 0.009, "head", (0.3, 0.27, 0.22), k=0.004))
            for i in range(5):
                c = a + (b - a) * (i + 0.5) / 5
                ch.add(capsule(c, c + np.array([x * 0.01, 0.035, -0.03]), 0.005, "head", (0.55, 0.5, 0.4), k=0.003))
                ch.add(capsule(c, c + np.array([x * 0.02, -0.01, 0.04]), 0.005, "head", (0.55, 0.5, 0.4), k=0.003))
    # wings: tattered moth wings with eyespots
    for x, side in ((-1, "l"), (1, "r")):
        spot = np.array([x * 0.42, 1.5, -0.25])
        def wing_col(p, spot=spot):
            d = np.linalg.norm(p - spot, axis=1)
            base = np.array([0.5, 0.42, 0.33]) * (1 + 0.25 * fbm(p, 9, 2, 3.0))[:, None]
            out = base.copy()
            out[d < 0.11] = (0.85, 0.5, 0.15); out[d < 0.075] = (0.1, 0.08, 0.06); out[d < 0.03] = (0.95, 0.9, 0.8)
            vein = np.abs(np.sin(np.arctan2(p[:, 1] - 1.45, (p[:, 0] - x * 0.1) * x) * 9)) < 0.08
            out[vein] *= 0.6
            return out
        ch.add(ellipsoid((x * 0.42, 1.48, -0.22), (0.4, 0.28, 0.024), f"wing_{side}", wing_col, rot=(0.1, x * 0.35, x * 0.35), k=0.01, mat="wing", noise=(0.01, 6, 2.0 + x)))
        ch.add(ellipsoid((x * 0.3, 1.15, -0.18), (0.25, 0.2, 0.024), f"wing_{side}", wing_col, rot=(0, x * 0.3, -x * 0.3), k=0.01, mat="wing", noise=(0.01, 7, 4.0 + x)))
    biped_limbs(ch, s, (fz, fz), (shorts, fz), r_arm=(0.04, 0.034, 0.03), r_leg=(0.07, 0.042, 0.036), k=0.02, noise=nz)
    for side, x in (("l", -1), ("r", 1)):
        ch.add(sphere(H(s, f"knee_{side}") + np.array([0, 0, 0.02]), 0.048, f"knee_{side}", fz, k=0.02))
        claw_hand(ch, s, side, fz, 0.045, claw_col=(0.2, 0.18, 0.15), fingers=3, length=1.8)
        ft = H(s, f"foot_{side}")
        ch.add(ellipsoid((ft[0], 0.035, 0.05), (0.045, 0.032, 0.1), f"foot_{side}", fz, k=0.02))
        ch.add(box((ft[0], 0.008, 0.05), (0.055, 0.008, 0.12), f"foot_{side}", (0.15, 0.45, 0.85), r=0.006, k=0.004))
        ch.add(capsule((ft[0] - 0.04, 0.02, 0.06), (ft[0] + 0.04, 0.02, 0.06), 0.008, f"foot_{side}", (0.15, 0.45, 0.85), k=0.004))
    # lantern held up at face height in the right hand (he's drawn to the light)
    hold_r, err = solve_arm(s, "r", (0.2, 1.42, 0.3), hand_offset=(0, -0.04, 0))
    lt = np.array([0.2, 1.42, 0.3])
    ch.add(attach([
        torus(lt + np.array([0, 0.0, 0]), 0.04, 0.006, "hand_r", (0.25, 0.25, 0.25), rot=(PI / 2, 0, 0), k=0.0, mat="metal"),
        cylinder(lt - np.array([0, 0.06, 0]), lt - np.array([0, 0.09, 0]), 0.055, "hand_r", (0.15, 0.4, 0.2), k=0.0),
        cylinder(lt - np.array([0, 0.09, 0]), lt - np.array([0, 0.21, 0]), 0.045, "hand_r", (1.0, 0.85, 0.5), mat=lamp, k=0.0),
        cylinder(lt - np.array([0, 0.21, 0]), lt - np.array([0, 0.26, 0]), 0.058, "hand_r", (0.15, 0.4, 0.2), k=0.0)], s, hold_r, "hand_r"))
    print(f"  lantern IK error {err:.3f}")
    def twitch(t, dur=3.0):
        return {"head": (0.12 * jitter(t, dur), 0.3 * jitter(t + 0.4, dur), 0.15 * jitter(t + 0.9, dur)),
                "neck": (0.05 * jitter(t + 1.3, dur), 0, 0), "wing_l": (0, 0.15 * jitter(t, dur), 0), "wing_r": (0, -0.15 * jitter(t, dur), 0)}
    def scratch(t, dur=3.0):
        w = smoothstep(0.4, 0.7, t) * (1 - smoothstep(1.9, 2.2, t))
        sc = {"shoulder_l": (-2.6, 0.2, -0.3), "elbow_l": (-1.8 + 0.35 * math.sin(2 * PI * t / dur * 30), 0.2, 0)}
        return blend_pose({}, sc, w)
    ch.anim("idle", 3.0, merge(override(idle_cycle(speed=2, sway=0.05), lambda t: {**hold_r, **scratch(t)}), twitch))
    ch.anim("walk", 0.9, merge(override(walk_cycle(stride=0.45, arm=0.5, bob=0.04, lean=0.15, speed=1 / 0.9), lambda t: hold_r), lambda t: twitch(t, 0.9)))
    ch.anim("run", 0.6, merge(walk_cycle(stride=0.75, arm=0.9, bob=0.07, lean=0.3, knee=1.2, speed=1 / 0.6),
                              lambda t: {"wing_l": (0, 0.5 * math.sin(2 * PI * t / 0.3), 0), "wing_r": (0, -0.5 * math.sin(2 * PI * t / 0.3), 0)}))
    ch.anim("flap", 0.4, lambda t: {"wing_l": (0, 0.9 * math.sin(2 * PI * t / 0.4), 0.3), "wing_r": (0, -0.9 * math.sin(2 * PI * t / 0.4), -0.3)})
    return ch

def methman_camp():
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("methman_camp", s, voxel=0.045)
    tent = speckle((0.2, 0.36, 0.72), 0.08, 12)
    ch.add(ellipsoid((0, -0.1, 0), (1.1, 1.05, 1.3), "root", tent, k=0.02, noise=(0.02, 3, 1.0)))
    ch.add(ellipsoid((0, 0.35, 1.1), (0.35, 0.42, 0.25), "root", (0.05, 0.06, 0.1), k=0.02))  # door hole
    for (x, y, z, r) in ((0.6, 0.6, 0.6, (0.2, 0.15, 0.02)), (-0.7, 0.4, -0.3, (0.18, 0.18, 0.02)), (0.2, 0.85, -0.5, (0.15, 0.2, 0.02))):
        ch.add(box((x, y, z), r, "root", (0.62, 0.62, 0.6), r=0.01, k=0.01, rot=(0.4, x, 0.3)))  # duct tape patches
    for a in (-0.6, 0.6):
        ch.add(torus((0, -0.1, 0), 1.12, 0.018, "root", (0.55, 0.55, 0.58), rot=(PI / 2, a, 0), k=0.0, mat="metal"))
    ch.add(capsule((0.9, 0.12, 1.4), (1.6, 0.12, 1.1), 0.13, "root", (0.25, 0.4, 0.2), k=0.03))  # sleeping bag
    # lawn chair
    c = np.array([-1.5, 0, 1.3])
    for dx in (-0.25, 0.25):
        ch.add(capsule(c + (dx, 0.02, -0.25), c + (dx, 0.45, 0.25), 0.015, "root", (0.8, 0.8, 0.82), mat="metal", k=0.0))
        ch.add(capsule(c + (dx, 0.02, 0.25), c + (dx, 0.75, -0.25), 0.015, "root", (0.8, 0.8, 0.82), mat="metal", k=0.0))
    ch.add(box(c + (0, 0.42, 0.0), (0.24, 0.015, 0.22), "root", stripes((0.2, 0.7, 0.4), (0.95, 0.95, 0.9), axis=0, period=0.06), r=0.01, k=0.0))
    ch.add(box(c + (0, 0.62, -0.2), (0.24, 0.18, 0.015), "root", stripes((0.2, 0.7, 0.4), (0.95, 0.95, 0.9), axis=0, period=0.06), r=0.01, k=0.0, rot=(-0.35, 0, 0)))
    rng = np.random.default_rng(3)
    for i in range(9):  # empty cans
        p = np.array([rng.uniform(-2, 2), 0.035, rng.uniform(0.8, 2.4)])
        d = np.array([math.cos(i), 0, math.sin(i)]) * 0.06
        ch.add(cylinder(p - d, p + d, 0.033, "root", [(0.8, 0.1, 0.1), (0.75, 0.75, 0.8), (0.1, 0.3, 0.8)][i % 3], mat="metal", k=0.0))
    ch.add(torus((1.7, 0.12, -0.6), 0.32, 0.12, "root", (0.08, 0.08, 0.08), rot=(0.3, 0, 0.2), k=0.0))  # old tyre
    ch.add(box((-1.3, 0.12, -0.9), (0.22, 0.12, 0.14), "root", (0.1, 0.1, 0.1), r=0.02, k=0.0))  # car battery
    return ch

# =============================================================================== WHERE-WOLF (lost, with a map)
def wherewolf():
    s = humanoid(Skeleton(), hips_y=1.0, shoulder_w=0.3, shoulder_y=1.63, neck_y=1.71, hip_w=0.14,
                 knee_y=0.55, ankle_y=0.12, head_y=1.8, elbow_drop=0.36, wrist_drop=0.33, arm_out=0.1)
    s.add("tail", "hips", (0, 0.98, -0.2)); s.add("map", "chest", (0, 1.36, 0.44))
    ch = Character("wherewolf", s, voxel=0.018)
    fz = fur((0.47, 0.47, 0.5), 0.2, 20, 7.0); light = fur((0.75, 0.72, 0.68), 0.12, 20, 8.0); nz = (0.012, 22, 7.0)
    plaid_c = plaid((0.7, 0.12, 0.1), (0.35, 0.07, 0.06), (0.1, 0.05, 0.05), period=0.06)
    def shirt(p):
        out = plaid_c(p)
        front = (np.abs(p[:, 0]) < 0.06 + (1.62 - p[:, 1]) * 0.12) & (p[:, 2] > 0.05)
        out[front] = light(p[front]); return out
    jorts = lambda p: np.clip(np.array([0.45, 0.55, 0.75]) * (1 + 0.12 * vnoise(p, 40, 2)[:, None]), 0, 1)
    ch.add(ellipsoid((0, 1.42, 0.03), (0.3, 0.28, 0.21), "chest", shirt, rot=(0.2, 0, 0), k=0.05))
    ch.add(ellipsoid((0, 1.17, 0.02), (0.25, 0.22, 0.19), "spine", shirt, k=0.05))
    ch.add(ellipsoid((0, 0.98, 0), (0.24, 0.14, 0.19), "hips", jorts, k=0.04))
    ch.add(capsule((0, 1.62, 0.02), (0, 1.76, 0.1), 0.12, "neck", fz, k=0.05, noise=nz))
    ch.add(ellipsoid((0, 1.88, 0.06), (0.15, 0.15, 0.16), "head", fz, k=0.04, noise=nz))
    ch.add(capsule((0, 1.85, 0.15), (0, 1.81, 0.36), 0.085, "head", fz, rb=0.058, k=0.04, noise=(0.006, 30)))  # snout
    ch.add(capsule((0, 1.77, 0.14), (0, 1.77, 0.32), 0.06, "head", light, rb=0.04, k=0.03))  # jaw
    ch.add(sphere((0, 1.835, 0.39), 0.034, "head", BLACK, k=0.01, mat="shiny"))
    ch.add(mirror(lambda x: capsule((x * 0.09, 1.98, 0.03), (x * 0.16, 2.17, 0.0), 0.055, "head", fz, rb=0.008, k=0.02)))
    ch.add(mirror(lambda x: capsule((x * 0.095, 1.99, 0.06), (x * 0.155, 2.13, 0.04), 0.03, "head", (0.85, 0.6, 0.6), rb=0.006, k=0.0)))
    ch.add(mirror(lambda x: ellipsoid((x * 0.14, 1.83, 0.08), (0.06, 0.08, 0.07), "head", light, k=0.04, noise=(0.01, 25))))  # cheek tufts
    # derpy confused eyes: looking different ways, one brow raised
    for x, look, by in ((-1, (-0.4, 0.3, 1), 0.035), (1, (0.5, -0.2, 1), 0.0)):
        c = np.array([x * 0.07, 1.92, 0.17])
        ch.add(sphere(c, 0.038, "head", WHITE, mat="shiny", k=0.0))
        lk = np.array(look, float); lk /= np.linalg.norm(lk)
        ch.add(sphere(c + lk * 0.03, 0.016, "head", BLACK, mat="shiny", k=0.0))
        ch.add(capsule(c + np.array([-0.03, 0.05 + by, 0.01]), c + np.array([0.03, 0.05 + by * 0.4, 0.01]), 0.012, "head", (0.25, 0.25, 0.27), k=0.005))
    ch.add(capsule(H(s, "tail"), H(s, "tail") + np.array([0, -0.3, -0.35]), 0.09, "tail", fz, rb=0.06, k=0.05, noise=(0.02, 15, 9.0)))
    biped_limbs(ch, s, (plaid_c, fz), (jorts, fz), r_arm=(0.1, 0.085, 0.07), r_leg=(0.13, 0.1, 0.08), k=0.05, noise=None)
    for side in ("l", "r"):
        claw_hand(ch, s, side, fz, 0.07, claw_col=(0.9, 0.88, 0.8), fingers=4)
        big_foot(ch, s, side, fz, length=0.2, width=0.09, height=0.07, toe_col=(0.85, 0.85, 0.8))
    # the map he can't read
    def map_col(p):
        out = np.tile(np.array([0.93, 0.88, 0.7]), (len(p), 1))
        n = fbm(p * np.array([1, 1, 0.0]) + np.array([0, 0, 1]), 9, 3, 4.0)
        out[n > 0.25] = (0.45, 0.7, 0.4); out[n < -0.3] = (0.4, 0.6, 0.9)
        route = np.abs(np.sin(p[:, 0] * 25) * 0.04 - (p[:, 1] - 1.36)) < 0.008
        out[route & (np.sin(p[:, 0] * 120) > 0)] = (0.85, 0.1, 0.1)
        out[(np.abs(p[:, 0]) < 0.004) | (np.abs(p[:, 0] - 0.12) < 0.004) | (np.abs(p[:, 0] + 0.12) < 0.004)] *= 0.8
        return out
    ch.add(box((0, 1.36, 0.44), (0.24, 0.17, 0.008), "map", map_col, r=0.004, rot=(-0.55, 0, 0), k=0.0, mat="paper"))
    hl, e1 = solve_arm(s, "l", (-0.2, 1.33, 0.44), hand_offset=(0, -0.06, 0)); hr, e2 = solve_arm(s, "r", (0.2, 1.33, 0.44), hand_offset=(0, -0.06, 0))
    print(f"  map grip IK error {e1:.3f} / {e2:.3f}")
    grip = {**hl, **hr}
    def confused(t, dur=4.0):
        ph = 2 * PI * t / dur
        return {"head": (0.15, 0, 0.35 * math.sin(ph)), "map": (0, 0, -0.5 * math.sin(ph) + 0.4 * math.sin(2 * ph)),
                "tail": (0, 0.4 * math.sin(3 * ph), 0)}
    ch.anim("idle", 4.0, override(merge(idle_cycle(), confused), lambda t: grip))
    ch.anim("walk", 1.1, merge(override(walk_cycle(stride=0.45, arm=0.0, bob=0.04, lean=0.2), lambda t: grip),
                               lambda t: {"head": (0, 0.5 * math.sin(2 * PI * t / 1.1), 0), "tail": (0, 0.3 * math.sin(4 * PI * t / 1.1), 0)}))
    ch.anim("run", 0.65, override(walk_cycle(stride=0.8, arm=0.0, bob=0.07, lean=0.35, knee=1.2, speed=1 / 0.65), lambda t: grip))
    return ch

# =============================================================================== GREY ALIEN TOURIST
def grey_tourist():
    s = humanoid(Skeleton(), hips_y=0.58, shoulder_w=0.13, shoulder_y=0.86, neck_y=0.9, hip_w=0.065,
                 knee_y=0.32, ankle_y=0.06, head_y=0.97, elbow_drop=0.17, wrist_drop=0.16, arm_out=0.06)
    ch = Character("grey_tourist", s, voxel=0.011)
    grey = speckle((0.62, 0.66, 0.66), 0.05, 25)
    shirt = hawaiian((0.08, 0.55, 0.75), (0.97, 0.38, 0.58), (1.0, 0.85, 0.2), (0.15, 0.6, 0.25), scale=0.055, seed=3.0)
    khaki = (0.78, 0.7, 0.5)
    # big head: round cranium tapering to a pointy chin
    ch.add(sphere((0, 1.14, -0.01), 0.21, "head", grey, k=0.04))
    ch.add(capsule((0, 1.1, 0.02), (0, 0.95, 0.07), 0.16, "head", grey, rb=0.045, k=0.05))
    ch.add(mirror(lambda x: ellipsoid((x * 0.095, 1.07, 0.165), (0.085, 0.045, 0.04), "head", (0.03, 0.03, 0.04), rot=(0, x * 0.35, -x * 0.45), mat="shiny", k=0.0)))
    ch.add(mirror(lambda x: sphere((x * 0.08, 1.085, 0.2), 0.012, "head", WHITE, mat="shiny", k=0.0)))
    ch.add(capsule((-0.02, 0.965, 0.115), (0.02, 0.965, 0.115), 0.005, "head", (0.25, 0.25, 0.27), k=0.003))
    # bucket hat, perched (too small for the head)
    hat = (0.86, 0.8, 0.6)
    ch.add(ellipsoid((0, 1.355, -0.02), (0.14, 0.075, 0.14), "head", hat, k=0.01))
    ch.add(ellipsoid((0, 1.31, -0.02), (0.21, 0.016, 0.21), "head", hat, rot=(0.08, 0, 0), k=0.01))
    ch.add(torus((0, 1.325, -0.02), 0.135, 0.012, "head", (0.3, 0.25, 0.2), k=0.0))
    # body
    ch.add(capsule((0, 0.86, 0), (0, 0.93, 0.02), 0.032, "neck", grey, k=0.02))
    ch.add(ellipsoid((0, 0.75, 0.0), (0.13, 0.15, 0.095), "chest", shirt, k=0.03))
    ch.add(ellipsoid((0, 0.65, 0.025), (0.12, 0.1, 0.1), "spine", shirt, k=0.03))  # tourist tummy
    ch.add(mirror(lambda x: box((x * 0.05, 0.87, 0.06), (0.05, 0.012, 0.035), "chest", shirt, r=0.01, rot=(0.5, 0, x * 0.4), k=0.005)))  # collar
    ch.add(ellipsoid((0, 0.57, 0), (0.115, 0.075, 0.09), "hips", khaki, k=0.03))
    ch.add(torus((0, 0.6, 0.0), 0.12, 0.008, "hips", BLACK, k=0.0))
    ch.add(box((0, 0.6, 0.11), (0.075, 0.035, 0.03), "hips", (0.95, 0.2, 0.8), r=0.02, k=0.005))  # fanny pack
    ch.add(torus((0, 0.865, 0.03), 0.075, 0.006, "chest", BLACK, rot=(0.45, 0, 0), k=0.0))  # camera strap
    ch.add(box((0, 0.76, 0.115), (0.045, 0.03, 0.02), "chest", BLACK, r=0.008, k=0.004))
    ch.add(cylinder((0, 0.758, 0.13), (0, 0.758, 0.16), 0.018, "chest", (0.12, 0.12, 0.13), k=0.0))
    biped_limbs(ch, s, (shirt, grey), (khaki, grey), r_arm=(0.038, 0.026, 0.022), r_leg=(0.05, 0.026, 0.022), k=0.02)
    for side, x in (("l", -1), ("r", 1)):
        hd = H(s, f"hand_{side}")
        ch.add(sphere(hd + np.array([0, -0.02, 0]), 0.028, f"hand_{side}", grey, k=0.01))
        for i in range(3):
            a = hd + np.array([0, -0.035, (i - 1) * 0.015])
            ch.add(capsule(a, a + np.array([x * 0.005, -0.06, (i - 1) * 0.01]), 0.007, f"hand_{side}", grey, k=0.006))
        ft = H(s, f"foot_{side}")
        ch.add(capsule(ft + np.array([0, 0.0, 0]), ft + np.array([0, 0.11, 0]), 0.03, f"knee_{side}", WHITE, k=0.01))  # socks
        ch.add(ellipsoid((ft[0], 0.028, 0.045), (0.035, 0.025, 0.08), f"foot_{side}", WHITE, k=0.01))
        ch.add(box((ft[0], 0.008, 0.045), (0.042, 0.008, 0.095), f"foot_{side}", (0.45, 0.28, 0.15), r=0.005, k=0.0))
        ch.add(torus((ft[0], 0.035, 0.08), 0.03, 0.007, f"foot_{side}", (0.35, 0.2, 0.1), rot=(0, 0, PI / 2), k=0.0))
    hl, _ = solve_arm(s, "l", (-0.06, 0.78, 0.15), hand_offset=(0, -0.03, 0)); hr, _ = solve_arm(s, "r", (0.06, 0.78, 0.15), hand_offset=(0, -0.03, 0))
    photo_pose = {**hl, **hr, "chest": (-0.05, 0, 0)}
    def sightsee(t, dur=4.0):
        ph = 2 * PI * t / dur
        w = smoothstep(2.0, 2.3, t) * (1 - smoothstep(3.4, 3.7, t))
        base = {"head": (-0.1, 0.6 * math.sin(ph), 0.1 * math.sin(2 * ph))}
        return blend_pose(base, {**photo_pose, "head": (-0.05, 0, 0)}, w)
    ch.anim("idle", 4.0, override(idle_cycle(), sightsee))
    ch.anim("walk", 0.8, merge(walk_cycle(stride=0.35, arm=0.35, bob=0.025, twist=0.15, speed=1 / 0.8),
                               lambda t: {"spine": (0, 0, 0.1 * math.sin(2 * PI * t / 0.8))}))
    ch.anim("run", 0.5, walk_cycle(stride=0.7, arm=0.9, bob=0.05, lean=0.2, knee=1.2, speed=2.0))
    ch.anim("snap", 0.6, lambda t: photo_pose)
    return ch

# =============================================================================== CORNICORN
def cornicorn():
    s = Skeleton()
    s.add("root", None, (0, 0, 0)); s.add("hips", "root", (0, 1.05, -0.42)); s.add("spine", "hips", (0, 1.07, 0.0))
    s.add("chest", "spine", (0, 1.08, 0.38)); s.add("neck", "chest", (0, 1.28, 0.55)); s.add("head", "neck", (0, 1.6, 0.76))
    s.add("tail", "hips", (0, 1.16, -0.72))
    for nm, par, z in (("f", "chest", 0.42), ("b", "hips", -0.45)):
        for side, x in (("l", -0.17), ("r", 0.17)):
            s.add(f"leg_{nm}{side}", par, (x, 0.98, z)); s.add(f"knee_{nm}{side}", f"leg_{nm}{side}", (x, 0.55, z + (0.03 if nm == "f" else -0.04)))
            s.add(f"hoof_{nm}{side}", f"knee_{nm}{side}", (x, 0.13, z))
    ch = Character("cornicorn", s, voxel=0.016)
    white = lambda p: np.clip(np.array([0.97, 0.95, 0.98]) - 0.04 * np.abs(vnoise(p, 6, 2))[:, None] * np.array([0.3, 0.5, 0.0]), 0, 1)
    ch.add(ellipsoid((0, 1.05, -0.02), (0.29, 0.29, 0.6), "spine", white, k=0.08))
    ch.add(ellipsoid((0, 1.06, 0.36), (0.26, 0.3, 0.28), "chest", white, k=0.08))
    ch.add(ellipsoid((0, 1.09, -0.42), (0.28, 0.29, 0.28), "hips", white, k=0.08))
    ch.add(capsule((0, 1.15, 0.45), (0, 1.55, 0.72), 0.19, "neck", white, rb=0.12, k=0.07))
    ch.add(ellipsoid((0, 1.64, 0.8), (0.12, 0.14, 0.17), "head", white, rot=(-0.6, 0, 0), k=0.05))
    ch.add(ellipsoid((0, 1.5, 0.95), (0.09, 0.085, 0.12), "head", (0.98, 0.84, 0.88), rot=(-0.3, 0, 0), k=0.05))
    ch.add(mirror(lambda x: sphere((x * 0.035, 1.5, 1.065), 0.016, "head", (0.35, 0.15, 0.2), k=0.01)))
    ch.add(capsule((-0.05, 1.445, 1.02), (0.05, 1.445, 1.02), 0.008, "head", (0.4, 0.15, 0.2), k=0.004))
    cartoon_eyes(ch, "head", 1.67, 0.875, 0.085, 0.042, look=(0.3, 0, 1))
    for x in (-1, 1):
        for j in range(3):
            a = np.array([x * (0.075 + j * 0.02), 1.705, 0.9]); ch.add(capsule(a, a + np.array([x * 0.02, 0.035, 0.0]), 0.006, "head", BLACK, k=0.0, mat="shiny"))
        ch.add(capsule((x * 0.06, 1.74, 0.72), (x * 0.085, 1.86, 0.69), 0.035, "head", white, rb=0.008, k=0.02))
        ch.add(capsule((x * 0.062, 1.75, 0.735), (x * 0.082, 1.83, 0.71), 0.018, "head", (0.98, 0.7, 0.8), rb=0.004, k=0.0))
    # rainbow mane + tail
    rainbow = [(0.95, 0.25, 0.3), (1.0, 0.6, 0.2), (1.0, 0.9, 0.3), (0.4, 0.85, 0.4), (0.3, 0.6, 1.0), (0.65, 0.4, 0.95)]
    for i in range(12):
        u = i / 11
        p = np.array([0.04 * (1 if i % 2 else -1), 1.76 - 0.5 * u, 0.7 - 0.36 * u - 0.07]) + np.array([0, 0, -0.03])
        ch.add(ellipsoid(p, (0.05, 0.09, 0.07), "neck" if u > 0.25 else "head", rainbow[i % 6], rot=(-0.5, 0, 0), k=0.02, noise=(0.008, 30, i)))
    ch.add(ellipsoid((0, 1.78, 0.86), (0.05, 0.05, 0.06), "head", rainbow[0], k=0.02))
    for i in range(8):
        u = i / 7
        p = np.array([0.03 * math.sin(i * 1.7), 1.16 - 0.55 * u, -0.72 - 0.22 * math.sin(u * 2.2)])
        ch.add(ellipsoid(p, (0.06, 0.1, 0.06), "tail", rainbow[i % 6], k=0.025, noise=(0.008, 30, i + 20)))
    # legs + golden hooves
    for nm in ("fl", "fr", "bl", "br"):
        a, b, c = H(s, f"leg_{nm}"), H(s, f"knee_{nm}"), H(s, f"hoof_{nm}")
        ch.add(capsule(a, b, 0.085, f"leg_{nm}", white, rb=0.06, k=0.05))
        ch.add(capsule(b, c, 0.055, f"knee_{nm}", white, rb=0.05, k=0.03))
        ch.add(ellipsoid(c + np.array([0, 0.03, 0]), (0.075, 0.04, 0.075), f"hoof_{nm}", white, k=0.03, noise=(0.01, 30)))  # fluff
        ch.add(cylinder(c - np.array([0, 0.13, 0]), c - np.array([0, 0.02, 0]), 0.06, f"hoof_{nm}", (0.95, 0.75, 0.2), mat="shiny", k=0.0))
    # The horn is just an ear of corn: fat cob, real kernels, husk peeled back, silk on top.
    A = np.array([0, 1.76, 0.85]); ax = np.array([0, 0.78, 0.62]); ax /= np.linalg.norm(ax)
    u_ax = np.cross(ax, [1, 0, 0]); u_ax /= np.linalg.norm(u_ax); w_ax = np.cross(ax, u_ax)
    c0 = A + ax * 0.06; c1 = A + ax * 0.34
    ROWS, SP = 14, 0.021
    def kernel_coords(p):
        t = (p - A) @ ax; q = p - A - np.outer(t, ax)
        ang = np.arctan2(q @ w_ax, q @ u_ax)
        rowf = (ang + PI) / (2 * PI) * ROWS
        row = np.floor(rowf)
        v = 2 * (rowf - row) - 1
        tt = t / SP + 0.5 * (row % 2)  # staggered rows
        u = 2 * (tt - np.floor(tt)) - 1
        return t, u, v
    def corn_sdf(p):
        d = sd_capsule(p, c0, c1, 0.07, 0.056)
        t, u, v = kernel_coords(p)
        bump = np.sqrt(np.clip(1 - (u ** 4 + v ** 4), 0, 1))
        return d - 0.008 * bump + 0.002
    def corn_col(p):
        t, u, v = kernel_coords(p)
        bump = np.sqrt(np.clip(1 - (u ** 4 + v ** 4), 0, 1))
        top, groove = np.array([1.0, 0.86, 0.3]), np.array([0.78, 0.52, 0.07])
        out = groove[None, :] + (top - groove)[None, :] * (bump ** 0.6)[:, None]
        out *= (1 + 0.06 * vnoise(p, 60, 8.0))[:, None]
        return np.clip(out, 0, 1)
    lo = np.minimum(c0, c1) - 0.1; hi = np.maximum(c0, c1) + 0.1
    ch.add(Part(corn_sdf, "head", corn_col, k=0.0, mat="corn", bounds=(lo, hi)))
    # silk tuft at the tip
    tip = c1 + ax * 0.05
    for i in range(6):
        a = i / 6 * 2 * PI
        out = (math.cos(a) * u_ax + math.sin(a) * w_ax)
        p1 = tip + out * 0.025 + ax * 0.04; p2 = p1 + out * 0.035 + ax * 0.03 - np.array([0, 0.02, 0])
        ch.add(capsule(tip - ax * 0.02, p1, 0.006, "head", (0.86, 0.72, 0.42), rb=0.005, k=0.004, mat="corn"))
        ch.add(capsule(p1, p2, 0.005, "head", (0.7, 0.5, 0.28), rb=0.004, k=0.004, mat="corn"))
    # husk leaves peeled back down over the forehead
    def leaf_col(p):
        return np.clip(np.array([0.42, 0.7, 0.26])[None, :] * (1 + 0.12 * vnoise(p * np.array([60, 6, 60]), 1, 3.0))[:, None], 0, 1)
    for i in range(5):
        a = (i / 5) * 2 * PI + 0.3
        radial = math.cos(a) * u_ax + math.sin(a) * w_ax
        down = -ax * 0.75 + radial * 0.65; down /= np.linalg.norm(down)
        thin = radial - down * (radial @ down); thin /= np.linalg.norm(thin)
        side = np.cross(down, thin)
        R = np.column_stack([side, down, thin])
        centre = A + ax * 0.07 + radial * 0.075 + down * 0.08
        ch.add(Part(lambda p, c=centre, R=R: sd_ellipsoid(p, c, np.array([0.045, 0.11, 0.009]), R), "head", leaf_col, k=0.01, mat="leaf",
                    bounds=(centre - 0.16, centre + 0.16)))
    def quad_walk(stride, knee, bob, speed, gallop=False):
        def f(t):
            ph = 2 * PI * t * speed
            out = {}
            offs = {"fl": 0.0, "br": 0.0, "fr": PI, "bl": PI} if not gallop else {"fl": 0.0, "fr": 0.4, "bl": PI, "br": PI + 0.4}
            for nm, o in offs.items():
                sgn = math.sin(ph + o)
                out[f"leg_{nm}"] = (stride * sgn, 0, 0)
                kb = knee * max(0.0, math.cos(ph + o))
                out[f"knee_{nm}"] = ((-kb if nm[0] == "f" else kb), 0, 0)
            out["_hips_offset"] = (0, bob * abs(math.sin(ph)), 0)
            out["neck"] = (0.08 * math.sin(2 * ph), 0, 0); out["tail"] = (0.2, 0.3 * math.sin(ph), 0)
            if gallop: out["spine"] = (0.08 * math.sin(ph), 0, 0)
            return out
        return f
    ch.anim("idle", 3.0, lambda t: {"neck": (0.06 * math.sin(2 * PI * t / 3), 0.15 * math.sin(2 * PI * t / 1.5), 0),
                                    "head": (0.08 * math.sin(2 * PI * t / 3 + 1), 0, 0), "tail": (0.1, 0.5 * math.sin(2 * PI * t), 0),
                                    "leg_fr": (-0.25 * max(0, math.sin(2 * PI * t / 3)) ** 4, 0, 0)})
    ch.anim("walk", 1.0, quad_walk(0.35, 0.6, 0.03, 1.0))
    ch.anim("run", 0.5, quad_walk(0.6, 1.0, 0.08, 2.0, gallop=True))
    return ch

# =============================================================================== JERSEY DEVIL
def jersey_devil():
    s = humanoid(Skeleton(), hips_y=0.95, shoulder_w=0.21, shoulder_y=1.45, neck_y=1.53, hip_w=0.1,
                 knee_y=0.5, ankle_y=0.1, head_y=1.62, elbow_drop=0.28, wrist_drop=0.26, arm_out=0.1)
    s.add("tail", "hips", (0, 0.93, -0.14))
    ch = Character("jersey_devil", s, voxel=0.014)
    deer = fur((0.55, 0.38, 0.24), 0.12, 25, 11.0); cream = (0.92, 0.86, 0.75)
    red = ch.glow("devil_eyes", (1.0, 0.15, 0.05))
    jred, jwhite = np.array([0.78, 0.08, 0.13]), np.array([0.96, 0.96, 0.94])
    num_back = seven_seg("13", 0.0, 1.25, 0.2, 0.09, 0.028, facing=-1)
    num_front = seven_seg("13", 0.0, 1.3, 0.09, 0.04, 0.014, facing=1)
    def jersey(p):
        out = np.tile(jred, (len(p), 1))
        out[(p[:, 1] > 1.46) | (p[:, 1] < 0.99)] = jwhite
        out[num_back(p) | num_front(p)] = jwhite
        return out
    def sleeve(p):
        out = np.tile(jred, (len(p), 1)); band = np.abs(((p[:, 1] - 1.2) % 0.1) - 0.05) < 0.012
        out[band] = jwhite; return out
    jeans = speckle((0.22, 0.32, 0.58), 0.08, 40)
    ch.add(ellipsoid((0, 1.3, 0), (0.2, 0.21, 0.13), "chest", jersey, k=0.03))
    ch.add(ellipsoid((0, 1.1, 0.0), (0.17, 0.15, 0.12), "spine", jersey, k=0.04))
    ch.add(ellipsoid((0, 0.93, 0), (0.17, 0.11, 0.12), "hips", jeans, k=0.03))
    ch.add(capsule((0, 1.48, 0), (0, 1.62, 0.04), 0.05, "neck", deer, k=0.02))
    ch.add(ellipsoid((0, 1.72, 0.03), (0.11, 0.12, 0.13), "head", deer, k=0.03))
    ch.add(capsule((0, 1.7, 0.1), (0, 1.66, 0.27), 0.08, "head", deer, rb=0.05, k=0.04))
    ch.add(capsule((0, 1.64, 0.12), (0, 1.63, 0.26), 0.05, "head", cream, rb=0.035, k=0.02))
    ch.add(sphere((0, 1.665, 0.305), 0.032, "head", BLACK, mat="shiny", k=0.01))
    ch.add(mirror(lambda x: ellipsoid((x * 0.14, 1.78, -0.01), (0.04, 0.095, 0.025), "head", deer, rot=(0, 0, x * 1.15), k=0.015)))
    ch.add(mirror(lambda x: ellipsoid((x * 0.07, 1.75, 0.115), (0.03, 0.022, 0.02), "head", (1.0, 0.2, 0.1), mat=red, rot=(0, x * 0.4, x * 0.3), k=0.0)))
    bone = (0.88, 0.83, 0.7)
    for x in (-1, 1):  # antlers poking out from under the helmet
        p0, p1, p2 = np.array([x * 0.1, 1.84, -0.01]), np.array([x * 0.24, 2.0, 0.0]), np.array([x * 0.33, 2.2, 0.07])
        ch.add(capsule(p0, p1, 0.02, "head", bone, rb=0.016, k=0.01)); ch.add(capsule(p1, p2, 0.016, "head", bone, rb=0.008, k=0.008))
        for u, ln in ((0.3, 0.13), (0.65, 0.12)):
            b = p0 + (p1 - p0) * u if u < 0.5 else p1 + (p2 - p1) * (u - 0.4)
            ch.add(capsule(b, b + np.array([x * 0.02, ln, 0.03]), 0.012, "head", bone, rb=0.005, k=0.006))
    # the beer-drinking ("sippy cup") helmet with straws to his mouth
    ch.add(ellipsoid((0, 1.82, 0.02), (0.135, 0.075, 0.15), "head", stripes(jred, jwhite, axis=0, period=0.045), k=0.006))
    ch.add(ellipsoid((0, 1.775, 0.02), (0.16, 0.012, 0.17), "head", jred, k=0.004))
    for x in (-1, 1):
        cp = np.array([x * 0.17, 1.82, 0.02])
        ch.add(box(cp - np.array([x * 0.02, 0, 0]), (0.02, 0.02, 0.025), "head", (0.2, 0.2, 0.2), r=0.005, k=0.004))
        ch.add(cylinder(cp - np.array([0, 0.065, 0]), cp + np.array([0, 0.065, 0]), 0.036, "head", stripes((0.95, 0.85, 0.2), (0.85, 0.1, 0.1), axis=1, period=0.03), mat="metal", k=0.0))
        pts = [cp + np.array([x * 0.015, -0.06, 0.02]), np.array([x * 0.19, 1.66, 0.12]), np.array([x * 0.1, 1.62, 0.22]), np.array([x * 0.02, 1.645, 0.27])]
        for a, b in zip(pts[:-1], pts[1:]):
            ch.add(capsule(a, b, 0.007, "head", (0.95, 0.95, 0.95), k=0.0, mat="shiny"))
    # devil tail (no wings, per Ian & Alex)
    tp = [H(s, "tail"), np.array([0, 0.75, -0.35]), np.array([0, 0.62, -0.42])]
    for a, b in zip(tp[:-1], tp[1:]):
        ch.add(capsule(a, b, 0.018, "tail", (0.55, 0.1, 0.1), rb=0.014, k=0.01))
    ch.add(ellipsoid(tp[-1] + np.array([0, -0.04, -0.01]), (0.012, 0.05, 0.04), "tail", (0.75, 0.05, 0.05), rot=(0.6, 0, 0), k=0.005))
    biped_limbs(ch, s, (sleeve, deer), (jeans, jeans), r_arm=(0.055, 0.045, 0.038), r_leg=(0.08, 0.068, 0.058), k=0.025)
    for side, x in (("l", -1), ("r", 1)):
        claw_hand(ch, s, side, deer, 0.045, fingers=3)
        ft = H(s, f"foot_{side}")
        for dz in (-0.022, 0.022):  # cloven hooves
            ch.add(ellipsoid((ft[0] + dz, 0.045, 0.05), (0.028, 0.045, 0.06), f"foot_{side}", (0.08, 0.06, 0.06), mat="shiny", k=0.008))
    def sip(t, dur=3.0):
        return {"head": (0.12 * max(0, math.sin(2 * PI * t / dur * 2)) ** 2, 0.1 * math.sin(2 * PI * t / dur), 0)}
    std_anims(ch, walk_kw=dict(stride=0.5, arm=0.5, bob=0.04, twist=0.15), extra=sip)
    ch.anim("cheer", 1.0, lambda t: {"shoulder_l": (-0.2, 0, -2.4 + 0.2 * math.sin(4 * PI * t)), "shoulder_r": (-0.2, 0, 2.4 - 0.2 * math.sin(4 * PI * t)),
                                     "elbow_l": (-0.3, 0, 0), "elbow_r": (-0.3, 0, 0), "_hips_offset": (0, 0.12 * abs(math.sin(2 * PI * t)), 0)})
    return ch

# =============================================================================== CRACKIN' (octopus guy, plumber's crack, beer at a right angle)
def crackin():
    s = humanoid(Skeleton(), hips_y=0.95, shoulder_w=0.25, shoulder_y=1.45, neck_y=1.52, hip_w=0.12,
                 knee_y=0.5, ankle_y=0.1, head_y=1.6, elbow_drop=0.28, wrist_drop=0.27, arm_out=0.12)
    ch = Character("crackin", s, voxel=0.015)
    def octo(p):
        base = np.array([0.66, 0.26, 0.5]); spot = np.array([0.85, 0.5, 0.65])
        n = vnoise(p, 18, 3.0)
        out = np.tile(base, (len(p), 1)); out[n > 0.45] = spot
        return out * (1 + 0.06 * vnoise(p, 40, 1)[:, None])
    tank = dirty((0.95, 0.94, 0.9), (0.75, 0.6, 0.3), 0.5, 6, 2.0)
    jeans = speckle((0.22, 0.3, 0.55), 0.08, 40)
    def body_col(p):
        # tank top rides up over the gut; jeans sag at the back
        out = tank(p)
        belly = (p[:, 1] < 1.04) & (p[:, 2] > 0.05)
        out[belly] = octo(p[belly])
        back_skin = (p[:, 1] < 1.0) & (p[:, 2] < -0.05)
        out[back_skin] = octo(p[back_skin])
        return out
    def hips_col(p):
        out = jeans(p)
        top = np.where(p[:, 2] < -0.04, 0.86, 0.95)
        skin = p[:, 1] > top
        out[skin] = octo(p[skin])
        crack = (np.abs(p[:, 0]) < 0.012) & (p[:, 2] < -0.1) & (p[:, 1] > 0.84)
        out[crack] = (0.25, 0.08, 0.18)
        return out
    # mantle head, tilted back
    ch.add(ellipsoid((0, 1.86, -0.12), (0.2, 0.28, 0.23), "head", octo, rot=(0.45, 0, 0), k=0.06))
    ch.add(ellipsoid((0, 1.66, 0.05), (0.16, 0.13, 0.14), "head", octo, k=0.06))
    for x in (-1, 1):  # lazy half-lidded eyes with goat pupils
        c = np.array([x * 0.095, 1.72, 0.13])
        ch.add(sphere(c, 0.048, "head", (0.96, 0.9, 0.6), mat="shiny", k=0.0))
        ch.add(box(c + np.array([0, -0.008, 0.045]), (0.026, 0.008, 0.006), "head", BLACK, mat="shiny", k=0.0, r=0.004))
        ch.add(ellipsoid(c + np.array([0, 0.022, 0.006]), (0.055, 0.032, 0.054), "head", octo, k=0.004))
    for i in range(6):  # tentacle beard
        a = (i - 2.5) / 2.5
        p0 = np.array([a * 0.11, 1.62, 0.13 - abs(a) * 0.03])
        pts = [p0, p0 + np.array([a * 0.02, -0.1, 0.03]), p0 + np.array([a * 0.05, -0.2, 0.02]), p0 + np.array([a * 0.04 + 0.03 * a, -0.26, 0.06])]
        r = [0.026, 0.02, 0.014, 0.008]
        for j in range(3):
            ch.add(capsule(pts[j], pts[j + 1], r[j], "head", octo, rb=r[j + 1], k=0.012))
    # trucker cap
    def cap_col(p):
        out = np.tile(np.array([0.12, 0.15, 0.35]), (len(p), 1))
        front = p[:, 2] > 0.0
        out[front] = (0.96, 0.96, 0.94)
        logo = front & (np.hypot(p[:, 0], p[:, 1] - 2.06) < 0.04)
        out[logo] = (0.85, 0.12, 0.12)
        mesh = (~front) & ((np.sin(p[:, 0] * 160) * np.sin(p[:, 1] * 160)) > 0.3)
        out[mesh] *= 0.5
        return out
    ch.add(ellipsoid((0, 2.04, -0.05), (0.2, 0.12, 0.21), "head", cap_col, rot=(0.15, 0, 0), k=0.008))
    ch.add(ellipsoid((0, 1.985, 0.17), (0.13, 0.016, 0.11), "head", (0.12, 0.15, 0.35), rot=(-0.15, 0, 0), k=0.004))
    ch.add(capsule((0, 1.46, -0.02), (0, 1.58, 0.02), 0.09, "neck", octo, k=0.04))
    ch.add(ellipsoid((0, 1.33, 0), (0.24, 0.19, 0.15), "chest", body_col, k=0.05))
    ch.add(ellipsoid((0, 1.1, 0.09), (0.27, 0.25, 0.25), "spine", body_col, k=0.06))  # beer gut
    ch.add(sphere((0, 1.0, 0.33), 0.015, "spine", (0.4, 0.12, 0.3), sub=True, k=0.01))  # belly button
    ch.add(ellipsoid((0, 0.92, -0.02), (0.24, 0.13, 0.19), "hips", hips_col, k=0.05))
    ch.add(mirror(lambda x: ellipsoid((x * 0.085, 0.86, -0.1), (0.12, 0.11, 0.1), "hips", hips_col, k=0.03)))
    ch.add(capsule((0, 0.82, -0.2), (0, 0.97, -0.19), 0.011, "hips", (0.25, 0.08, 0.18), sub=True, k=0.008))  # the crack
    biped_limbs(ch, s, (octo, octo), (jeans, jeans), r_arm=(0.075, 0.062, 0.05), r_leg=(0.1, 0.09, 0.08), k=0.04)
    for side, x in (("l", -1), ("r", 1)):
        claw_hand(ch, s, side, octo, 0.055, fingers=3)
        boot(ch, f"foot_{side}", x * 0.12, (0.6, 0.45, 0.25), length=0.15, h=0.075)
    # right hand: beer can held out at a right angle
    target = np.array([0.32, 1.12, 0.3])
    hold_r, err = solve_arm(s, "r", target, hand_offset=(0, -0.05, 0))
    print(f"  beer IK error {err:.3f}")
    can = stripes((0.85, 0.1, 0.12), (0.9, 0.9, 0.92), axis=1, period=0.025)
    cc = target + np.array([0, -0.05, 0.0])
    ch.add(attach([cylinder(cc + np.array([0, -0.065, 0]), cc + np.array([0, 0.065, 0]), 0.034, "hand_r", can, mat="metal", k=0.0),
                   cylinder(cc + np.array([0, 0.065, 0]), cc + np.array([0, 0.075, 0]), 0.026, "hand_r", (0.75, 0.75, 0.78), mat="metal", k=0.0)],
                  s, hold_r, "hand_r"))
    sip_l, _ = solve_arm(s, "r", np.array([0.06, 1.48, 0.28]), hand_offset=(0, -0.05, 0))
    scratch_l, _ = solve_arm(s, "l", np.array([-0.04, 0.95, -0.24]), hand_offset=(0, -0.05, 0))
    def life(t, dur=5.0):
        w_sip = smoothstep(1.2, 1.6, t) * (1 - smoothstep(2.3, 2.7, t))
        w_scr = smoothstep(3.2, 3.5, t) * (1 - smoothstep(4.4, 4.7, t))
        pose = blend_pose(hold_r, sip_l, w_sip)
        sc = dict(scratch_l); sc["elbow_l"] = (sc["elbow_l"][0] + 0.25 * math.sin(2 * PI * t * 6), sc["elbow_l"][1], 0)
        pose.update(blend_pose({}, sc, w_scr))
        pose["head"] = (-0.25 * w_sip, 0, 0)
        return pose
    ch.anim("idle", 5.0, override(idle_cycle(speed=0.6, sway=0.04), life))
    ch.anim("walk", 1.2, override(walk_cycle(stride=0.4, arm=0.4, bob=0.03, twist=0.2, speed=1 / 1.2), lambda t: hold_r))
    ch.anim("run", 0.75, override(walk_cycle(stride=0.65, arm=0.7, bob=0.06, lean=0.15, knee=1.0, speed=1 / 0.75), lambda t: hold_r))
    return ch

# =============================================================================== OH-GO-POGO (Ogopogo on a pogo stick)
def oh_go_pogo():
    s = Skeleton()
    s.add("root", None, (0, 0, 0)); s.add("hips", "root", (0, 0.1, 0))
    s.add("tail", "hips", (0, 0.36, 0.0)); s.add("coil1", "hips", (0, 0.5, 0)); s.add("coil2", "coil1", (0, 0.8, 0)); s.add("coil3", "coil2", (0, 1.08, 0))
    s.add("neck1", "coil3", (0, 1.28, 0.06)); s.add("neck2", "neck1", (0, 1.5, 0.12)); s.add("head", "neck2", (0, 1.7, 0.2))
    ch = Character("oh_go_pogo", s, voxel=0.013)
    def scales(p):
        d = np.hypot(p[:, 0], p[:, 2])
        base = np.tile(np.array([0.2, 0.55, 0.32]), (len(p), 1))
        belly = d < 0.135
        base[belly] = (0.75, 0.82, 0.45)
        sc = (np.sin(p[:, 1] * 90 + np.arctan2(p[:, 0], p[:, 2]) * 8) > 0.6) & ~belly
        base[sc] *= 0.82
        return base
    metal = (0.78, 0.8, 0.84)
    # pogo stick
    ch.add(cylinder((0, 0.04, 0), (0, 1.42, 0), 0.022, "hips", metal, mat="metal", k=0.0))
    ch.add(sphere((0, 0.035, 0), 0.035, "hips", BLACK, k=0.0))
    for i in range(7):
        ch.add(torus((0, 0.1 + i * 0.03, 0), 0.042, 0.009, "hips", (0.6, 0.6, 0.65), mat="metal", k=0.0))
    ch.add(cylinder((-0.17, 0.33, 0), (0.17, 0.33, 0), 0.02, "hips", (0.1, 0.1, 0.1), k=0.0))
    ch.add(cylinder((-0.25, 1.36, 0), (0.25, 1.36, 0), 0.02, "hips", metal, mat="metal", k=0.0))
    for x in (-1, 1):
        ch.add(cylinder((x * 0.16, 1.36, 0), (x * 0.27, 1.36, 0), 0.03, "hips", (0.85, 0.12, 0.12), k=0.0))
    # serpent body coiled round the shaft
    def P(u):
        a = u * 2.6 * 2 * PI
        return np.array([0.14 * math.sin(a), 0.42 + 0.8 * u, 0.14 * math.cos(a)])
    N = 34
    for i in range(N):
        u0, u1 = i / N, (i + 1) / N
        r0 = 0.05 + 0.03 * math.sin(PI * u0); r1 = 0.05 + 0.03 * math.sin(PI * u1)
        bone = "coil1" if u0 < 0.33 else ("coil2" if u0 < 0.66 else "coil3")
        ch.add(capsule(P(u0), P(u1), r0, bone, scales, rb=r1, k=0.02))
        if i % 3 == 0 and i > 2:  # dorsal fins on the outside of the coil
            c = P(u0); outw = np.array([c[0], 0, c[2]]); outw /= np.linalg.norm(outw)
            ch.add(ellipsoid(c + outw * (r0 + 0.01) + np.array([0, 0.02, 0]), (0.012, 0.035, 0.03), bone, (0.9, 0.82, 0.3), k=0.01))
    tail_pts = [P(0), np.array([0.1, 0.36, 0.06]), np.array([0.15, 0.33, -0.02])]
    for a, b in zip(tail_pts[:-1], tail_pts[1:]):
        ch.add(capsule(a, b, 0.045, "tail", scales, rb=0.025, k=0.02))
    ch.add(ellipsoid(tail_pts[-1] + np.array([0.04, 0, -0.02]), (0.05, 0.04, 0.01), "tail", (0.9, 0.82, 0.3), k=0.01))
    neck_pts = [P(1.0), np.array([0, 1.3, 0.07]), np.array([0, 1.5, 0.12]), np.array([0, 1.68, 0.2])]
    for j, (a, b) in enumerate(zip(neck_pts[:-1], neck_pts[1:])):
        ch.add(capsule(a, b, 0.075 - j * 0.004, ["coil3", "neck1", "neck2"][j], scales, rb=0.07 - j * 0.004, k=0.03))
    for j in range(5):
        c = np.array([0, 1.32 + j * 0.08, 0.06 + j * 0.03 - 0.075])
        ch.add(ellipsoid(c, (0.012, 0.04, 0.035), "neck1" if j < 2 else "neck2", (0.9, 0.82, 0.3), k=0.01))
    # head: goofy horse/dragon with a big grin and a Canadian toque
    ch.add(ellipsoid((0, 1.76, 0.27), (0.1, 0.1, 0.15), "head", scales, rot=(-0.2, 0, 0), k=0.04))
    ch.add(ellipsoid((0, 1.72, 0.41), (0.078, 0.065, 0.1), "head", (0.25, 0.6, 0.35), k=0.04))
    ch.add(mirror(lambda x: sphere((x * 0.03, 1.745, 0.505), 0.013, "head", BLACK, k=0.005)))
    ch.add(capsule((-0.075, 1.705, 0.38), (0.075, 1.705, 0.38), 0.012, "head", (0.3, 0.06, 0.08), k=0.005))
    ch.add(mirror(lambda x: capsule((x * 0.075, 1.705, 0.38), (x * 0.085, 1.72, 0.32), 0.011, "head", (0.3, 0.06, 0.08), k=0.005)))
    ch.add(mirror(lambda x: box((x * 0.03, 1.69, 0.47), (0.009, 0.012, 0.004), "head", WHITE, r=0.003, mat="shiny", k=0.0)))
    cartoon_eyes(ch, "head", 1.83, 0.3, 0.055, 0.036, look=(0, 0.1, 1))
    ch.add(mirror(lambda x: ellipsoid((x * 0.1, 1.76, 0.2), (0.01, 0.06, 0.06), "head", (0.9, 0.82, 0.3), rot=(0, x * 0.5, 0), k=0.01)))  # cheek frills
    ch.add(ellipsoid((0, 1.86, 0.21), (0.085, 0.07, 0.085), "head", stripes((0.85, 0.1, 0.1), (0.96, 0.96, 0.94), axis=1, period=0.025), k=0.01, noise=(0.004, 50)))
    ch.add(torus((0, 1.83, 0.21), 0.085, 0.016, "head", (0.96, 0.96, 0.94), k=0.0, noise=(0.003, 60)))
    ch.add(sphere((0, 1.95, 0.21), 0.035, "head", (0.85, 0.1, 0.1), k=0.0, noise=(0.006, 40)))
    def bounce(period, height, lean=0.0):
        def f(t):
            ph = (t % period) / period
            h = height * math.sin(PI * ph)
            squash = math.cos(2 * PI * ph)
            return {"_hips_offset": (0, h, 0), "hips": (lean, 0, 0),
                    "coil1": (0, 0, 0.05 * squash), "coil2": (0, 0, -0.05 * squash),
                    "neck1": (-0.15 * squash, 0, 0), "neck2": (0.1 * squash, 0.15 * math.sin(2 * PI * t / (period * 4)), 0),
                    "head": (0.15 * squash, 0, 0.1 * math.sin(2 * PI * t / (period * 2))), "tail": (0, 0, 0.2 * squash)}
        return f
    ch.anim("idle", 2.0, bounce(0.5, 0.18))
    ch.anim("walk", 1.6, bounce(0.4, 0.3, lean=0.12))
    ch.anim("run", 1.2, bounce(0.3, 0.42, lean=0.22))
    return ch

# =============================================================================== TOE ROGAN (campfire host; unlocks maps)
def toe_rogan():
    s = humanoid(Skeleton(), hips_y=0.66, shoulder_w=0.27, shoulder_y=1.06, neck_y=1.12, hip_w=0.11,
                 knee_y=0.36, ankle_y=0.08, head_y=1.17, elbow_drop=0.2, wrist_drop=0.19, arm_out=0.12)
    ch = Character("toe_rogan", s, voxel=0.013)
    jeans = speckle((0.18, 0.24, 0.4), 0.08, 40)
    toe_skin = (0.95, 0.74, 0.62)
    # Black V-neck tee with a white "big toe" print.
    tee_red = np.array([0.075, 0.075, 0.085])
    def tee(p):
        out = np.tile(tee_red, (len(p), 1))
        logo = ((p[:, 0] / 0.065) ** 2 + ((p[:, 1] - 0.86) / 0.075) ** 2 < 1.0) & (p[:, 2] > 0.1)
        nail = ((p[:, 0] / 0.036) ** 2 + ((p[:, 1] - 0.893) / 0.032) ** 2 < 1.0) & (p[:, 2] > 0.1)
        out[logo] = (0.97, 0.95, 0.9)
        out[nail] = (0.95, 0.6, 0.6)
        # the V: skin shows through at the front, with a slightly darker trim along its edge
        vy = 1.0 + 1.25 * np.abs(p[:, 0])
        front = p[:, 2] > 0.02
        out[front & (p[:, 1] > vy)] = toe_skin
        out[front & (p[:, 1] > vy - 0.018) & (p[:, 1] <= vy)] = (0.22, 0.22, 0.24)   # ribbed collar
        out[(p[:, 1] < 0.715) & (p[:, 1] > 0.69)] = (0.2, 0.2, 0.22)              # hem stitching
        return out
    # THE HEAD IS THE TOE (Thumb-Thumb style): one tall, straight, smooth column of skin rising
    # out of the V-neck, domed on top, a big oval nail on the upper front, two knuckle creases
    # across the middle. No face at all.
    def toe_col(p):
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        out = np.tile(np.array(toe_skin), (len(p), 1))
        tip = np.clip((y - 1.42) / 0.2, 0, 1)[:, None]
        out = out * (1 - 0.12 * tip) + np.array([0.98, 0.62, 0.56]) * 0.12 * tip   # a little rosier up top
        for cy in (1.324, 1.362):   # knuckle creases, curving down at the sides
            crease = (np.abs(y - cy + 0.9 * x * x) < 0.006) & (z > 0.06) & (np.abs(x) < 0.125)
            out[crease] = (0.8, 0.58, 0.5)
        # cuticle: a soft darker ring just outside the nail
        nx, ny = x / 0.116, (y - 1.505) / 0.138
        rim = (nx * nx + ny * ny < 1.0) & (z > 0.05)
        out[rim] = out[rim] * 0.45 + np.array([0.7, 0.4, 0.36]) * 0.55     # the groove round the nail
        return np.clip(out * (1 + 0.025 * vnoise(p, 30, 2.0))[:, None], 0, 1)
    ch.add(capsule((0, 1.04, -0.005), (0, 1.22, -0.005), 0.16, "neck", toe_col, k=0.01))
    ch.add(capsule((0, 1.2, -0.005), (0, 1.465, -0.005), 0.155, "head", toe_col, rb=0.16, k=0.05))
    # knuckle folds: soft bulges between the creases
    for cy, sx in ((1.305, 0.11), (1.343, 0.115)):
        ch.add(ellipsoid((0, cy, 0.118), (sx, 0.016, 0.042), "head", toe_col, k=0.016))
    def nail_col(p):
        x, y = p[:, 0], p[:, 1]
        out = np.tile(np.array([0.9, 0.55, 0.6]), (len(p), 1))            # pink nail bed showing through
        moon = ((x / 0.06) ** 2 + ((y - 1.405) / 0.05) ** 2) < 1.0
        out[moon] = (0.99, 0.88, 0.86)                                      # lunula
        out[y > 1.598] = (0.99, 0.97, 0.92)                                 # white free edge
        out[(y > 1.588) & (y <= 1.598)] = (0.86, 0.6, 0.6)                  # the line where it lifts off
        ridge = np.abs(np.sin(x * 95)) < 0.1
        out[ridge] = out[ridge] * 0.95                                      # lengthwise ridges
        shine = (np.abs(x + 0.035) < 0.012) & (y > 1.44) & (y < 1.58)
        out[shine] = out[shine] * 0.55 + 0.4                                # glossy highlight
        return np.clip(out, 0, 1)
    # the nail: a broad oval plate following the front curve and tipping back over the dome
    ch.add(ellipsoid((0, 1.505, 0.104), (0.1, 0.13, 0.052), "head", nail_col, rot=(-0.32, 0, 0), k=0.006))
    # huge traps, chest, lats in the tee
    ch.add(mirror(lambda x: capsule((x * 0.06, 1.1, -0.02), (x * 0.25, 1.06, -0.01), 0.085, "chest", tee, k=0.03)))
    ch.add(ellipsoid((0, 0.94, -0.01), (0.31, 0.17, 0.17), "chest", tee, k=0.06))
    ch.add(mirror(lambda x: ellipsoid((x * 0.12, 0.96, 0.11), (0.13, 0.095, 0.075), "chest", tee, k=0.04)))  # pecs
    ch.add(ellipsoid((0, 0.8, 0.02), (0.22, 0.13, 0.15), "spine", tee, k=0.06))  # lats taper
    ch.add(ellipsoid((0, 0.66, 0.0), (0.18, 0.09, 0.13), "hips", jeans, k=0.04))
    ch.add(box((0, 0.72, 0.0), (0.185, 0.015, 0.135), "hips", (0.15, 0.1, 0.06), r=0.012, k=0.005))  # belt
    ch.add(box((0, 0.72, 0.136), (0.03, 0.02, 0.006), "hips", (0.8, 0.75, 0.6), r=0.004, k=0.0, mat="metal"))  # buckle
    # arms: shoulder caps in the tee, then big bare arms with bulging biceps
    for side, x in (("l", -1), ("r", 1)):
        sh, el, hd = H(s, f"shoulder_{side}"), H(s, f"elbow_{side}"), H(s, f"hand_{side}")
        ch.add(ellipsoid(sh + np.array([x * 0.03, -0.045, 0]), (0.115, 0.115, 0.105), f"shoulder_{side}", tee, k=0.012))   # sleeve
        ch.add(capsule(sh + (el - sh) * 0.25, el, 0.085, f"shoulder_{side}", toe_skin, rb=0.07, k=0.012))
        ch.add(ellipsoid((sh + el) * 0.5 + np.array([0, -0.01, 0.04]), (0.07, 0.085, 0.065), f"shoulder_{side}", toe_skin, k=0.03))  # bicep
        ch.add(capsule(el, hd, 0.07, f"elbow_{side}", toe_skin, rb=0.05, k=0.03))
        hand(ch, f"hand_{side}", hd + np.array([0, -0.045, 0.0]), 0.05, toe_skin, side=-x)
        hp, kn, ft = H(s, f"hip_{side}"), H(s, f"knee_{side}"), H(s, f"foot_{side}")
        ch.add(capsule(hp, kn, 0.1, f"hip_{side}", jeans, rb=0.085, k=0.03))
        ch.add(capsule(kn, ft + np.array([0, 0.04, 0]), 0.08, f"knee_{side}", jeans, rb=0.07, k=0.02))
        boot(ch, f"foot_{side}", x * 0.11, (0.1, 0.1, 0.1), length=0.12)
    def talk(t, dur=2.4):
        ph = 2 * PI * t / dur
        return {"shoulder_l": (-0.7 - 0.25 * math.sin(ph), 0.2, -0.3), "shoulder_r": (-0.7 - 0.25 * math.sin(ph + 2.0), -0.2, 0.3),
                "elbow_l": (-1.2 - 0.3 * max(0, math.sin(ph * 2)), 0, 0), "elbow_r": (-1.2 - 0.3 * max(0, math.sin(ph * 2 + 1)), 0, 0),
                "head": (0.12 * math.sin(ph * 2) ** 2, 0.15 * math.sin(ph), 0), "chest": (0.04 * math.sin(ph), 0.08 * math.sin(ph + 1), 0)}
    std_anims(ch, walk_kw=dict(stride=0.4, arm=0.35, bob=0.03, twist=0.18), idle_kw=dict(arm_hang=0.25))
    ch.anim("talk", 2.4, talk)
    ch.anim("swap", 3.6, toe_swap_anim())
    ch.anim("impressed", 1.2, lambda t: {"head": (-0.25, 0.3 * math.sin(2 * PI * t / 1.2), 0), "shoulder_l": (-0.4, 0, -0.9), "shoulder_r": (-0.4, 0, 0.9),
                                        "elbow_l": (-1.6, 0, 0), "elbow_r": (-1.6, 0, 0), "chest": (-0.12, 0, 0)})
    return ch


# =============================================================================== F'HAIRY (fat hairy man in a too-small fairy costume)
def fhairy():
    s = humanoid(Skeleton(), hips_y=0.92, shoulder_w=0.25, shoulder_y=1.44, neck_y=1.52, hip_w=0.13,
                 knee_y=0.49, ankle_y=0.09, head_y=1.62, elbow_drop=0.26, wrist_drop=0.23, arm_out=0.17)
    s.add("wing_l", "chest", (-0.08, 1.36, -0.22)); s.add("wing_r", "chest", (0.08, 1.36, -0.22))
    ch = Character("fhairy", s, voxel=0.013)
    skin = (0.94, 0.74, 0.62)
    def hairy(p, base=skin):
        # dense fine body hair: lots of tiny dark flecks over skin, thicker on chest and belly
        out = np.tile(np.array(base), (len(p), 1))
        dens = 0.1 + 0.22 * np.clip((1.0 - np.abs(p[:, 1] - 1.2) * 3.0), 0, 1)
        hair = vnoise(p, 160, 7.0) > (0.55 - dens)
        out[hair] = out[hair] * 0.35 + np.array([0.25, 0.16, 0.1]) * 0.65
        return np.clip(out, 0, 1)
    pink = (1.0, 0.55, 0.78); spark = ch.glow("wand_star", (1.0, 0.95, 0.5)); wingglow = ch.glow("fairy_wing", (0.75, 0.9, 1.0))
    # big hairy belly and chest, a tiny pink bodice that can't cover it
    ch.add(ellipsoid((0, 1.3, 0.02), (0.27, 0.18, 0.2), "chest", hairy, k=0.05))
    ch.add(ellipsoid((0, 1.05, 0.1), (0.31, 0.25, 0.28), "spine", hairy, k=0.08))   # belly
    ch.add(ellipsoid((0, 1.33, 0.06), (0.22, 0.09, 0.17), "chest", pink, k=0.02))   # bodice strip
    for x in (-1, 1):
        ch.add(capsule((x * 0.12, 1.37, 0.12), (x * 0.18, 1.48, -0.02), 0.012, "chest", pink, k=0.004))  # straps
    # tutu: layered frilly skirt riding up under the belly
    for i, r in enumerate((0.36, 0.32)):
        ch.add(ellipsoid((0, 0.88 - i * 0.03, 0.03), (r, 0.05, r * 0.95), "hips", (1.0, 0.65 - i * 0.1, 0.85), k=0.02, noise=(0.02, 12, 3.0 + i)))
    ch.add(ellipsoid((0, 0.9, 0.0), (0.22, 0.1, 0.18), "hips", hairy, k=0.04))
    # head: stubbly, bald on top, a sparkly tiara, five o'clock shadow
    ch.add(capsule((0, 1.47, 0), (0, 1.57, 0.02), 0.09, "neck", hairy, k=0.03))
    ch.add(ellipsoid((0, 1.68, 0.03), (0.15, 0.16, 0.15), "head", skin, k=0.03))
    ch.add(ellipsoid((0, 1.6, 0.07), (0.13, 0.08, 0.11), "head", lambda p: hairy(p, (0.6, 0.48, 0.42)), k=0.04))  # stubble jaw
    ch.add(sphere((0, 1.67, 0.17), 0.04, "head", (0.97, 0.62, 0.55), k=0.02))   # nose
    cartoon_eyes(ch, "head", 1.71, 0.135, 0.055, 0.024, look=(0, -0.1, 1))
    ch.add(capsule((-0.045, 1.615, 0.15), (0.045, 1.62, 0.15), 0.01, "head", (0.6, 0.25, 0.25), k=0.004))
    ch.add(mirror(lambda x: capsule((x * 0.03, 1.755, 0.15), (x * 0.09, 1.76, 0.13), 0.012, "head", (0.25, 0.17, 0.1), k=0.004)))
    ch.add(torus((0, 1.8, 0.02), 0.11, 0.012, "head", (0.9, 0.85, 0.95), rot=(0.25, 0, 0), k=0.0, mat="metal"))
    for i in range(3):
        ch.add(sphere((-0.05 + i * 0.05, 1.85 + (0.02 if i == 1 else 0), 0.07), 0.018 if i == 1 else 0.012, "head", (1.0, 0.6, 0.85), mat="shiny", k=0.0))
    # little translucent-looking wings, far too small for him
    for side, x in (("l", -1), ("r", 1)):
        ch.add(ellipsoid((x * 0.2, 1.48, -0.26), (0.18, 0.24, 0.012), f"wing_{side}", (0.8, 0.92, 1.0), mat=wingglow, rot=(0.2, x * 0.4, x * 0.5), k=0.01))
        ch.add(ellipsoid((x * 0.16, 1.22, -0.25), (0.11, 0.14, 0.012), f"wing_{side}", (0.8, 0.92, 1.0), mat=wingglow, rot=(0, x * 0.3, -x * 0.4), k=0.01))
    biped_limbs(ch, s, (hairy, hairy), (hairy, hairy), r_arm=(0.08, 0.068, 0.055), r_leg=(0.115, 0.09, 0.065), k=0.03)
    for side, x in (("l", -1), ("r", 1)):
        hand(ch, f"hand_{side}", H(s, f"hand_{side}") + np.array([0, -0.045, 0]), 0.055, skin, side=-x)
        ft = H(s, f"foot_{side}")
        ch.add(ellipsoid((ft[0], 0.04, 0.05), (0.06, 0.04, 0.11), f"foot_{side}", pink, mat="shiny", k=0.01))   # ballet slippers
        ch.add(capsule((ft[0] - 0.05, 0.11, 0.0), (ft[0] + 0.05, 0.13, 0.02), 0.008, f"foot_{side}", pink, k=0.003))
    # magic wand in the right hand
    hold_r, err = solve_arm(s, "r", (0.32, 1.12, 0.22), hand_offset=(0, -0.045, 0))
    w0 = np.array([0.32, 1.1, 0.22])
    ch.add(attach([capsule(w0, w0 + np.array([0.05, 0.32, 0.06]), 0.009, "hand_r", (0.95, 0.95, 0.95), k=0.0, mat="shiny"),
                   sphere(w0 + np.array([0.06, 0.36, 0.07]), 0.045, "hand_r", (1.0, 0.95, 0.5), mat=spark, k=0.0)], s, hold_r, "hand_r"))
    print(f"  wand IK error {err:.3f}")
    flutter = lambda t: {"wing_l": (0, 0.55 * math.sin(2 * PI * t / 0.18), 0.2), "wing_r": (0, -0.55 * math.sin(2 * PI * t / 0.18), -0.2)}
    def prance(t, dur=1.0):
        return {"_hips_offset": (0, 0.05 * abs(math.sin(2 * PI * t / dur)), 0)}
    ch.anim("idle", 3.0, merge(override(idle_cycle(sway=0.05), lambda t: hold_r), flutter))
    ch.anim("walk", 1.0, merge(override(walk_cycle(stride=0.4, arm=0.3, bob=0.05, twist=0.2, sway=0.08), lambda t: hold_r), flutter, prance))
    ch.anim("run", 0.6, merge(override(walk_cycle(stride=0.65, arm=0.6, bob=0.09, lean=0.15, knee=1.1, speed=1 / 0.6), lambda t: hold_r), flutter))
    return ch

# =============================================================================== LEPERCHAUN (a leprechaun with leprosy)
def leperchaun():
    s = humanoid(Skeleton(), hips_y=0.55, shoulder_w=0.15, shoulder_y=0.88, neck_y=0.94, hip_w=0.075,
                 knee_y=0.3, ankle_y=0.06, head_y=1.0, elbow_drop=0.17, wrist_drop=0.16, arm_out=0.07)
    ch = Character("leperchaun", s, voxel=0.01)
    def sick_skin(p):
        out = np.tile(np.array([0.9, 0.72, 0.6]), (len(p), 1))
        patch = fbm(p, 14, 3, 3.0)
        out[patch > 0.18] = (0.72, 0.74, 0.6)      # pale grey-green patches
        out[patch > 0.32] = (0.62, 0.42, 0.38)     # raw spots
        return out
    green = speckle((0.08, 0.45, 0.18), 0.08, 30); dkgreen = (0.05, 0.3, 0.12)
    ginger = fur((0.85, 0.42, 0.12), 0.18, 40, 9.0); gold = (1.0, 0.8, 0.15); bandage = dirty((0.95, 0.93, 0.85), (0.7, 0.6, 0.45), 0.4)
    # coat, waistcoat, belt with a big gold buckle
    ch.add(ellipsoid((0, 0.8, 0), (0.15, 0.15, 0.11), "chest", green, k=0.03))
    ch.add(ellipsoid((0, 0.66, 0.01), (0.15, 0.12, 0.11), "spine", green, k=0.04))
    ch.add(box((0, 0.6, 0.0), (0.155, 0.02, 0.115), "spine", BLACK, r=0.01, k=0.004))
    ch.add(box((0, 0.6, 0.115), (0.04, 0.03, 0.008), "spine", gold, mat="metal", r=0.006, k=0.0))
    ch.add(ellipsoid((0, 0.53, 0), (0.13, 0.08, 0.1), "hips", dkgreen, k=0.03))
    # head: lumpy, missing an ear (bandaged), big ginger beard
    ch.add(ellipsoid((0, 1.03, 0.01), (0.11, 0.12, 0.11), "head", sick_skin, k=0.03, noise=(0.006, 18, 2.0)))
    ch.add(ellipsoid((0, 0.96, 0.07), (0.1, 0.1, 0.07), "head", ginger, k=0.04, noise=(0.01, 20, 1.0)))   # beard
    ch.add(sphere((0, 1.02, 0.115), 0.033, "head", (0.85, 0.55, 0.5), k=0.02, noise=(0.004, 30, 5.0)))
    cartoon_eyes(ch, "head", 1.06, 0.1, 0.042, 0.02, look=(0.1, 0, 1))
    ch.add(box((0.042, 1.06, 0.105), (0.03, 0.024, 0.006), "head", BLACK, r=0.006, k=0.0, rot=(0, 0, 0.2)))   # eye patch
    ch.add(capsule((-0.1, 1.09, 0.02), (0.1, 1.09, 0.02), 0.004, "head", BLACK, k=0.0))
    ch.add(ellipsoid((-0.11, 1.04, 0.0), (0.02, 0.035, 0.025), "head", sick_skin, k=0.01))   # the ear he still has
    ch.add(ellipsoid((0.11, 1.04, 0.0), (0.03, 0.045, 0.04), "head", bandage, k=0.01))       # the one he doesn't
    # top hat with a buckle
    ch.add(cylinder((0, 1.12, 0.0), (0, 1.135, 0.0), 0.15, "head", dkgreen, k=0.0))
    ch.add(cylinder((0, 1.13, 0.0), (0, 1.32, 0.0), 0.095, "head", dkgreen, k=0.0))
    ch.add(cylinder((0, 1.15, 0.0), (0, 1.18, 0.0), 0.098, "head", BLACK, k=0.0))
    ch.add(box((0, 1.165, 0.095), (0.025, 0.02, 0.006), "head", gold, mat="metal", r=0.004, k=0.0))
    ch.add(sphere((0.06, 1.25, 0.08), 0.014, "head", (0.2, 0.85, 0.2), k=0.0))   # little shamrock
    biped_limbs(ch, s, (green, sick_skin), (dkgreen, bandage), r_arm=(0.035, 0.03, 0.026), r_leg=(0.045, 0.04, 0.034), k=0.02)
    for side, x in (("l", -1), ("r", 1)):
        hd = H(s, f"hand_{side}")
        ch.add(ellipsoid(hd + np.array([0, -0.03, 0]), (0.03, 0.035, 0.022), f"hand_{side}", sick_skin, k=0.01))
        ft = H(s, f"foot_{side}")
        ch.add(ellipsoid((ft[0], 0.03, 0.04), (0.035, 0.03, 0.08), f"foot_{side}", BLACK, mat="shiny", k=0.01))
        ch.add(box((ft[0], 0.05, 0.08), (0.02, 0.015, 0.004), f"foot_{side}", gold, mat="metal", r=0.003, k=0.0))
    # bandage wraps round one forearm
    el, hd = H(s, "elbow_l"), H(s, "hand_l")
    for i in range(4):
        c = el + (hd - el) * (0.2 + i * 0.2)
        ch.add(torus(c, 0.032, 0.008, "elbow_l", bandage, rot=(0, 0, 0.4), k=0.002))
    std_anims(ch, walk_kw=dict(stride=0.5, arm=0.5, bob=0.05, twist=0.2), run_kw=dict(stride=0.9, arm=0.9),
              extra=lambda t: {"head": (0.05 * math.sin(2 * PI * t / 1.5), 0.2 * math.sin(2 * PI * t / 3.0), 0)})
    ch.anim("jig", 0.8, lambda t: {"hip_l": (-0.6 * max(0, math.sin(2 * PI * t / 0.8)), 0, 0), "hip_r": (-0.6 * max(0, -math.sin(2 * PI * t / 0.8)), 0, 0),
                                   "knee_l": (0.9 * max(0, math.sin(2 * PI * t / 0.8)), 0, 0), "knee_r": (0.9 * max(0, -math.sin(2 * PI * t / 0.8)), 0, 0),
                                   "shoulder_l": (0, 0, -1.2), "shoulder_r": (0, 0, 1.2), "elbow_l": (-1.2, 0, 0), "elbow_r": (-1.2, 0, 0),
                                   "_hips_offset": (0, 0.05 * abs(math.sin(2 * PI * t / 0.4)), 0)})
    return ch

# =============================================================================== THE RAKE (Slenderman-sized, a big plastic rake for a head)
def the_rake():
    s = humanoid(Skeleton(), hips_y=1.32, shoulder_w=0.2, shoulder_y=2.12, neck_y=2.2, hip_w=0.09,
                 knee_y=0.7, ankle_y=0.09, head_y=2.3, elbow_drop=0.48, wrist_drop=0.46, arm_out=0.06)
    ch = Character("the_rake", s, voxel=0.014)
    suit = speckle((0.06, 0.06, 0.07), 0.05, 30); shirt = (0.92, 0.92, 0.9); tie = (0.6, 0.05, 0.05)
    pale = (0.85, 0.85, 0.82); plastic = (0.15, 0.62, 0.22); handle = (0.82, 0.62, 0.3)
    ch.add(ellipsoid((0, 1.98, 0), (0.17, 0.2, 0.1), "chest", suit, k=0.03))
    ch.add(ellipsoid((0, 1.68, 0), (0.14, 0.24, 0.09), "spine", suit, k=0.04))
    ch.add(ellipsoid((0, 1.36, 0), (0.13, 0.1, 0.09), "hips", suit, k=0.03))
    ch.add(box((0, 1.95, 0.085), (0.045, 0.17, 0.02), "chest", shirt, r=0.01, k=0.005))
    ch.add(box((0, 1.95, 0.1), (0.016, 0.15, 0.008), "chest", tie, r=0.005, k=0.0))
    # neck is the rake's handle; the head is a big green plastic leaf-rake fan, tines down
    ch.add(capsule((0, 2.12, 0), (0, 2.55, 0.02), 0.024, "neck", handle, k=0.0, mat="shiny"))
    def rake_col(p):
        out = np.tile(np.array(plastic), (len(p), 1))
        out[p[:, 1] < 2.48] = (0.12, 0.52, 0.18)
        return out
    for i in range(13):
        a = (i - 6) / 6.0 * 0.62
        base = np.array([0, 2.52, 0.03])
        tip = base + np.array([math.sin(a) * 0.42, 0.42 * math.cos(a) - 0.05, 0.04 * abs(math.sin(a))])
        ch.add(capsule(base, tip, 0.016, "head", rake_col, rb=0.012, k=0.004, mat="shiny"))
        ch.add(capsule(tip, tip + np.array([math.sin(a) * 0.02, 0.0, 0.06]), 0.012, "head", plastic, rb=0.008, k=0.003, mat="shiny"))
    for r in (0.2, 0.32):   # cross braces
        pts = [np.array([0, 2.52, 0.035]) + np.array([math.sin(a) * r, r * math.cos(a) - 0.02, 0.0]) for a in np.linspace(-0.6, 0.6, 9)]
        for a, b in zip(pts[:-1], pts[1:]):
            ch.add(capsule(a, b, 0.01, "head", plastic, k=0.003, mat="shiny"))
    ch.add(cylinder((0, 2.5, 0.0), (0, 2.56, 0.04), 0.045, "head", plastic, k=0.01, mat="shiny"))   # the collar where the handle goes in
    biped_limbs(ch, s, (suit, suit), (suit, suit), r_arm=(0.04, 0.034, 0.028), r_leg=(0.055, 0.045, 0.04), k=0.02)
    for side, x in (("l", -1), ("r", 1)):
        hd = H(s, f"hand_{side}")
        ch.add(ellipsoid(hd + np.array([0, -0.04, 0]), (0.03, 0.05, 0.02), f"hand_{side}", pale, k=0.01))
        for i in range(4):   # long pale fingers
            a = hd + np.array([0, -0.08, (i - 1.5) * 0.014]); b = a + np.array([x * 0.01, -0.13, 0.01])
            ch.add(capsule(a, b, 0.007, f"hand_{side}", pale, rb=0.005, k=0.004))
        ft = H(s, f"foot_{side}")
        ch.add(ellipsoid((ft[0], 0.04, 0.06), (0.045, 0.035, 0.12), f"foot_{side}", BLACK, mat="shiny", k=0.01))
    def creep(t, dur=4.0):
        return {"head": (0.15 * math.sin(2 * PI * t / dur), 0.35 * math.sin(2 * PI * t / dur * 0.5), 0.25 * math.sin(2 * PI * t / dur * 0.7)),
                "shoulder_l": (0.05, 0, -0.05), "shoulder_r": (0.05, 0, 0.05)}
    ch.anim("idle", 4.0, merge(idle_cycle(sway=0.02, speed=0.5), creep))
    ch.anim("walk", 1.5, merge(walk_cycle(stride=0.4, arm=0.15, bob=0.02, lean=0.12, speed=1 / 1.5), lambda t: {"head": (0.2, 0, 0.15)}))
    ch.anim("run", 0.75, walk_cycle(stride=0.8, arm=0.6, bob=0.05, lean=0.35, knee=1.2, speed=1 / 0.75))
    return ch

# =============================================================================== bENT (stoned tree-person)
def bent():
    s = humanoid(Skeleton(), hips_y=1.05, shoulder_w=0.3, shoulder_y=1.85, neck_y=1.95, hip_w=0.15,
                 knee_y=0.55, ankle_y=0.1, head_y=2.08, elbow_drop=0.4, wrist_drop=0.36, arm_out=0.14)
    ch = Character("bent", s, voxel=0.016)
    def bark(p):
        out = np.tile(np.array([0.42, 0.3, 0.18]), (len(p), 1))
        groove = np.abs(np.sin(p[:, 0] * 60 + vnoise(p, 8, 1.0) * 3)) > 0.85
        out[groove] = (0.25, 0.17, 0.1)
        moss = (fbm(p, 9, 3, 4.0) > 0.25) & (p[:, 1] > 0.6)
        out[moss] = (0.3, 0.5, 0.2)
        return out
    leaves = speckle((0.25, 0.55, 0.2), 0.15, 20); ember = ch.glow("joint_ember", (1.0, 0.45, 0.1))
    red_cup = (0.85, 0.08, 0.08); bnz = (0.012, 10, 2.0)
    ch.add(ellipsoid((0, 1.62, 0), (0.28, 0.42, 0.22), "chest", bark, k=0.06, noise=bnz))
    ch.add(ellipsoid((0, 1.2, 0), (0.24, 0.25, 0.19), "spine", bark, k=0.06, noise=bnz))
    ch.add(ellipsoid((0, 0.98, 0), (0.22, 0.13, 0.17), "hips", bark, k=0.05, noise=bnz))
    # face in the trunk: heavy-lidded, bloodshot eyes, knothole mouth
    def bloodshot(p):
        out = np.tile(np.array([0.97, 0.94, 0.9]), (len(p), 1))
        vein = np.abs(np.sin(p[:, 0] * 220 + p[:, 1] * 180)) < 0.12
        out[vein] = (0.85, 0.15, 0.15)
        return out
    for x in (-1, 1):
        c = np.array([x * 0.09, 1.92, 0.19])
        ch.add(sphere(c, 0.05, "chest", bloodshot, k=0.0, mat="shiny"))
        ch.add(sphere(c + np.array([0, -0.005, 0.042]), 0.02, "chest", (0.55, 0.12, 0.1), k=0.0, mat="shiny"))
        ch.add(ellipsoid(c + np.array([0, 0.025, 0.005]), (0.06, 0.035, 0.05), "chest", bark, k=0.01))   # droopy lids
    ch.add(ellipsoid((0, 1.74, 0.2), (0.06, 0.035, 0.03), "chest", (0.12, 0.07, 0.04), k=0.01))   # mouth
    ch.add(ellipsoid((0, 1.83, 0.23), (0.035, 0.06, 0.03), "chest", bark, k=0.02))               # knobby nose
    # crown of branches and leaves (bone: head)
    for a, l in ((-0.6, 0.5), (-0.2, 0.6), (0.25, 0.55), (0.65, 0.45), (0.0, 0.7)):
        b0 = np.array([math.sin(a) * 0.15, 2.0, 0.0]); b1 = b0 + np.array([math.sin(a) * l * 0.7, l, -0.05])
        ch.add(capsule(b0, b1, 0.05, "head", bark, rb=0.025, k=0.03))
        ch.add(ellipsoid(b1 + np.array([0, 0.08, 0]), (0.22, 0.17, 0.2), "head", leaves, k=0.06, noise=(0.03, 8, 3.0 + a)))
    biped_limbs(ch, s, (bark, bark), (bark, bark), r_arm=(0.08, 0.065, 0.05), r_leg=(0.12, 0.1, 0.09), k=0.04, noise=bnz)
    for side, x in (("l", -1), ("r", 1)):
        hd = H(s, f"hand_{side}")
        for i in range(3):   # twiggy fingers
            a = hd + np.array([0, -0.04, (i - 1) * 0.03]); b = a + np.array([x * 0.03, -0.12, 0.02])
            ch.add(capsule(a, b, 0.016, f"hand_{side}", bark, rb=0.008, k=0.01))
        ft = H(s, f"foot_{side}")
        for i in range(3):   # roots for feet
            a = np.array([ft[0], 0.1, 0.0]); b = a + np.array([(i - 1) * 0.08, -0.08, 0.15])
            ch.add(capsule(a, b, 0.05, f"foot_{side}", bark, rb=0.025, k=0.03))
    # red solo cup (right) and a joint (left), double-fisted
    hold_r, er = solve_arm(s, "r", (0.36, 1.35, 0.3), hand_offset=(0, -0.05, 0))
    hold_l, el = solve_arm(s, "l", (-0.34, 1.45, 0.32), hand_offset=(0, -0.05, 0))
    cp = np.array([0.36, 1.33, 0.3]); jp = np.array([-0.34, 1.47, 0.32])
    ch.add(attach([cylinder(cp - np.array([0, 0.07, 0]), cp + np.array([0, 0.08, 0]), 0.055, "hand_r", red_cup, k=0.0, mat="shiny"),
                   cylinder(cp + np.array([0, 0.065, 0]), cp + np.array([0, 0.08, 0]), 0.056, "hand_r", WHITE, k=0.0)], s, hold_r, "hand_r"))
    ch.add(attach([capsule(jp, jp + np.array([0.1, 0.02, 0.04]), 0.008, "hand_l", (0.96, 0.95, 0.9), rb=0.013, k=0.0),
                   sphere(jp + np.array([0.105, 0.021, 0.042]), 0.014, "hand_l", (1.0, 0.45, 0.1), mat=ember, k=0.0)], s, hold_l, "hand_l"))
    print(f"  cup/joint IK error {er:.3f} / {el:.3f}")
    hold = {**hold_r, **hold_l}
    sway = lambda t: {"spine": (0, 0, 0.06 * math.sin(2 * PI * t / 5.0)), "head": (0.1, 0.2 * math.sin(2 * PI * t / 7.0), 0)}
    ch.anim("idle", 5.0, merge(override(idle_cycle(speed=0.6, sway=0.06), lambda t: hold), sway))
    ch.anim("walk", 1.6, merge(override(walk_cycle(stride=0.35, arm=0.0, bob=0.03, lean=0.05, twist=0.12, sway=0.08, speed=1 / 1.6), lambda t: hold), sway))
    ch.anim("run", 1.0, override(walk_cycle(stride=0.55, arm=0.0, bob=0.06, lean=0.15, knee=0.9, speed=1.0), lambda t: hold))
    return ch

# =============================================================================== SANTA (legendary) in his sleigh, for the RV roof
def santa_sleigh():
    s = Skeleton(); s.add("root", None, (0, 0, 0)); s.add("santa", "root", (0, 0.65, -0.1))
    s.add("head", "santa", (0, 1.25, -0.05)); s.add("shoulder_r", "santa", (0.28, 1.05, -0.05)); s.add("elbow_r", "shoulder_r", (0.45, 0.8, 0.0))
    ch = Character("santa_sleigh", s, voxel=0.018)
    red = (0.8, 0.08, 0.08); white = (0.96, 0.95, 0.92); gold = (1.0, 0.78, 0.2); skin = (0.96, 0.78, 0.68)
    # sleigh: curvy red body on gold runners, a sack of presents in the back
    ch.add(box((0, 0.55, 0), (0.55, 0.28, 1.0), "root", red, r=0.12, k=0.05))
    ch.add(ellipsoid((0, 0.9, 0.95), (0.55, 0.32, 0.18), "root", red, k=0.08))      # curled front
    ch.add(box((0, 0.8, -0.95), (0.55, 0.35, 0.1), "root", red, r=0.1, k=0.04))       # tall back
    for x in (-0.5, 0.5):
        ch.add(capsule((x, 0.1, -1.0), (x, 0.1, 1.0), 0.04, "root", gold, k=0.0, mat="metal"))
        ch.add(torus((x, 0.32, 1.05), 0.22, 0.04, "root", gold, rot=(0, PI / 2, 0), k=0.0, mat="metal"))
        for z in (-0.6, 0.5):
            ch.add(capsule((x, 0.1, z), (x, 0.32, z), 0.03, "root", gold, k=0.0, mat="metal"))
    ch.add(box((0, 0.84, 0), (0.56, 0.02, 1.0), "root", gold, r=0.01, k=0.0, mat="metal"))   # trim
    ch.add(ellipsoid((0, 1.05, -0.65), (0.4, 0.35, 0.3), "root", (0.55, 0.38, 0.2), k=0.05, noise=(0.02, 8, 1.0)))   # sack
    for i, (x, z, c) in enumerate(((-0.25, -0.4, (0.2, 0.5, 0.9)), (0.2, -0.45, (0.2, 0.75, 0.3)), (0.0, -0.75, (0.95, 0.85, 0.2)))):
        ch.add(box((x, 1.3, z), (0.12, 0.12, 0.12), "root", c, r=0.02, k=0.0, rot=(0.2 * i, 0.4 * i, 0)))
    # Santa, seated
    ch.add(ellipsoid((0, 0.95, -0.05), (0.38, 0.35, 0.32), "santa", red, k=0.05))           # belly
    ch.add(box((0, 0.9, 0.0), (0.4, 0.04, 0.34), "santa", BLACK, r=0.02, k=0.01))          # belt
    ch.add(box((0, 0.9, 0.33), (0.07, 0.05, 0.02), "santa", gold, r=0.01, k=0.0, mat="metal"))
    ch.add(ellipsoid((0, 1.2, -0.05), (0.32, 0.18, 0.26), "santa", red, k=0.04))
    ch.add(ellipsoid((0, 1.38, 0.0), (0.16, 0.17, 0.15), "head", skin, k=0.03))
    ch.add(ellipsoid((0, 1.28, 0.08), (0.17, 0.17, 0.12), "head", white, k=0.05, noise=(0.012, 14, 2.0)))   # beard
    ch.add(mirror(lambda x: ellipsoid((x * 0.06, 1.34, 0.15), (0.06, 0.025, 0.03), "head", white, rot=(0, 0, x * 0.3), k=0.01)))   # moustache
    ch.add(sphere((0, 1.38, 0.155), 0.035, "head", (0.95, 0.55, 0.5), k=0.01))
    cartoon_eyes(ch, "head", 1.42, 0.14, 0.05, 0.02)
    ch.add(cylinder((0, 1.5, 0.0), (0, 1.53, 0.0), 0.17, "head", white, k=0.02))
    ch.add(capsule((0, 1.52, -0.02), (0.05, 1.65, -0.18), 0.12, "head", red, rb=0.04, k=0.04))
    ch.add(sphere((0.08, 1.62, -0.28), 0.05, "head", white, k=0.01))
    for x in (-1, 1):   # legs out front, black boots on the footboard
        ch.add(capsule((x * 0.15, 0.85, 0.1), (x * 0.17, 0.75, 0.5), 0.1, "santa", red, k=0.03))
        ch.add(ellipsoid((x * 0.17, 0.62, 0.58), (0.08, 0.1, 0.12), "santa", BLACK, mat="shiny", k=0.02))
    ch.add(capsule((-0.28, 1.15, -0.05), (-0.35, 0.95, 0.25), 0.07, "santa", red, k=0.03))   # left arm on the reins
    ch.add(sphere((-0.35, 0.93, 0.3), 0.055, "santa", white, k=0.01))
    sh, el = H(s, "shoulder_r"), H(s, "elbow_r")
    ch.add(capsule(sh, el, 0.07, "shoulder_r", red, k=0.03))
    ch.add(capsule(el, el + np.array([0.1, -0.18, 0.05]), 0.06, "elbow_r", red, k=0.03))
    ch.add(sphere(el + np.array([0.12, -0.23, 0.06]), 0.055, "elbow_r", white, k=0.01))
    ch.anim("idle", 3.0, lambda t: {"santa": (0, 0.05 * math.sin(2 * PI * t / 3.0), 0.02 * math.sin(2 * PI * t / 1.5)),
                                    "head": (0.06 * math.sin(2 * PI * t / 1.5), 0.2 * math.sin(2 * PI * t / 3.0), 0)})
    ch.anim("wave", 1.2, lambda t: {"shoulder_r": (-0.4, 0, 2.2), "elbow_r": (0, 0, 0.5 * math.sin(2 * PI * t / 0.6)),
                                    "santa": (0, 0, 0.05 * math.sin(2 * PI * t / 1.2)), "head": (-0.15, 0.2, 0)})
    return ch

# =============================================================================== CITY PEDESTRIANS
def _pedestrian(name, shirt, pants, hair, extra):
    s = humanoid(Skeleton(), hips_y=0.95, shoulder_w=0.2, shoulder_y=1.42, neck_y=1.5, hip_w=0.1,
                 knee_y=0.52, ankle_y=0.09, head_y=1.6, elbow_drop=0.27, wrist_drop=0.24, arm_out=0.07)
    ch = Character(name, s, voxel=0.015)
    ch.add(ellipsoid((0, 1.28, 0), (0.19, 0.2, 0.12), "chest", shirt, k=0.03))
    ch.add(ellipsoid((0, 1.07, 0), (0.16, 0.14, 0.11), "spine", shirt, k=0.04))
    ch.add(ellipsoid((0, 0.93, 0), (0.16, 0.1, 0.11), "hips", pants, k=0.03))
    ch.add(capsule((0, 1.47, 0), (0, 1.56, 0.01), 0.05, "neck", SKIN, k=0.02))
    ch.add(ellipsoid((0, 1.67, 0.01), (0.1, 0.12, 0.11), "head", SKIN, k=0.03))
    ch.add(ellipsoid((0, 1.73, -0.01), (0.105, 0.08, 0.11), "head", hair, k=0.02))
    cartoon_eyes(ch, "head", 1.68, 0.095, 0.04, 0.017)
    biped_limbs(ch, s, (shirt, shirt), (pants, pants), r_arm=(0.05, 0.042, 0.035), r_leg=(0.075, 0.062, 0.05), k=0.02)
    for side, x in (("l", -1), ("r", 1)):
        hand(ch, f"hand_{side}", H(s, f"hand_{side}") + np.array([0, -0.04, 0]), 0.04, SKIN, side=-x)
        boot(ch, f"foot_{side}", x * 0.1, (0.12, 0.1, 0.08), length=0.12)
    extra(ch, s)
    std_anims(ch, walk_kw=dict(stride=0.42, arm=0.4, bob=0.03))
    return ch

def ped_suit():
    def briefcase(ch, s):
        hd = H(s, "hand_r")
        ch.add(box(hd + np.array([0, -0.16, 0]), (0.03, 0.12, 0.16), "hand_r", (0.35, 0.22, 0.12), r=0.01, k=0.0))
        ch.add(box((0, 1.3, 0.12), (0.012, 0.12, 0.006), "chest", (0.15, 0.25, 0.6), r=0.003, k=0.0))   # tie
    return _pedestrian("ped_suit", speckle((0.3, 0.32, 0.36), 0.05, 30), (0.22, 0.23, 0.26), (0.2, 0.14, 0.1), briefcase)

def ped_hoodie():
    def phone_and_hood(ch, s):
        ch.add(ellipsoid((0, 1.62, -0.07), (0.13, 0.12, 0.09), "neck", (0.3, 0.5, 0.35), k=0.03))   # hood
        hd = H(s, "hand_l")
        ch.add(box(hd + np.array([0, -0.04, 0.05]), (0.03, 0.05, 0.006), "hand_l", (0.1, 0.1, 0.12), r=0.004, k=0.0, mat="shiny"))
    return _pedestrian("ped_hoodie", speckle((0.3, 0.5, 0.35), 0.06, 30), speckle((0.2, 0.3, 0.55), 0.08, 40), (0.1, 0.07, 0.05), phone_and_hood)

# =============================================================================== keyframed poses
def keyed(keys):
    """keys: [(t, {bone: (x,y,z)}), ...] -> smooth (smoothstep) interpolation per bone."""
    bones = set(b for _, k in keys for b in k)
    def f(t):
        out = {}
        for b in bones:
            pts = [(kt, k.get(b, (0, 0, 0))) for kt, k in keys]
            if t <= pts[0][0]:
                out[b] = pts[0][1]; continue
            for (t0, a), (t1, c) in zip(pts[:-1], pts[1:]):
                if t0 <= t <= t1:
                    u = (t - t0) / max(t1 - t0, 1e-6); u = u * u * (3 - 2 * u)
                    out[b] = tuple(x + (y - x) * u for x, y in zip(a, c)); break
            else:
                out[b] = pts[-1][1]
        return out
    return f

def toe_swap_anim():
    """Toe Rogan takes your camera, hurls it into the woods, hands you a new one. 3.6 s.
    Game timing: take at 0.55, release at 1.55, new camera appears at 2.4, handed over at 3.0."""
    rest = {"shoulder_r": (0, 0, 0.25), "elbow_r": (-0.2, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0), "spine": (0, 0, 0),
            "shoulder_l": (0, 0, -0.25), "elbow_l": (-0.2, 0, 0)}
    reach = {"shoulder_r": (-1.35, 0, 0.15), "elbow_r": (-0.25, 0, 0), "chest": (0.15, -0.15, 0), "head": (0.15, 0, 0), "spine": (0.1, 0, 0)}
    hold = {"shoulder_r": (-0.6, 0, 0.3), "elbow_r": (-1.3, 0, 0), "chest": (0, 0.1, 0), "head": (0, 0.3, 0)}
    windup = {"shoulder_r": (-2.7, 0.2, 0.5), "elbow_r": (-1.6, 0, 0), "chest": (-0.1, 0.55, 0), "spine": (-0.12, 0.3, 0), "head": (0, 0.6, 0),
              "shoulder_l": (-1.0, 0, -0.6), "elbow_l": (-0.4, 0, 0)}
    throw = {"shoulder_r": (-0.7, -0.3, 0.1), "elbow_r": (-0.05, 0, 0), "chest": (0.3, -0.55, 0), "spine": (0.25, -0.3, 0), "head": (-0.1, -0.6, 0),
             "shoulder_l": (0.3, 0, -0.4)}
    watch = {"shoulder_r": (-0.2, 0, 0.3), "elbow_r": (-0.3, 0, 0), "chest": (0, -0.3, 0), "head": (-0.15, -0.9, 0)}
    fetch = {"shoulder_r": (0.35, 0, 0.35), "elbow_r": (-0.9, 0, 0), "chest": (0.1, 0.2, 0), "head": (0.2, 0.2, 0)}
    give = {"shoulder_r": (-1.4, 0, 0.1), "elbow_r": (-0.2, 0, 0), "chest": (0.12, 0, 0), "head": (0.1, 0, 0), "spine": (0.08, 0, 0)}
    return keyed([(0.0, rest), (0.45, reach), (0.75, hold), (1.3, windup), (1.55, throw), (1.75, throw), (2.15, watch),
                  (2.45, fetch), (2.95, give), (3.25, give), (3.6, rest)])

# =============================================================================== SHOPKEEPER (bait & traps stand)
def shopkeeper():
    s = humanoid(Skeleton(), hips_y=0.9, shoulder_w=0.24, shoulder_y=1.42, neck_y=1.5, hip_w=0.13,
                 knee_y=0.48, ankle_y=0.09, head_y=1.6, elbow_drop=0.25, wrist_drop=0.22, arm_out=0.16)
    ch = Character("shopkeeper", s, voxel=0.013)
    skin = (0.95, 0.78, 0.68); beard = fur((0.32, 0.22, 0.14), 0.12, 40, 3.0)
    tee = speckle((0.22, 0.2, 0.32), 0.06, 30); shorts = speckle((0.55, 0.5, 0.36), 0.08, 30)
    def tee_col(p):
        out = tee(p)
        stain = np.linalg.norm((p - np.array([0.08, 1.3, 0.24])) * np.array([1, 1.3, 1]), axis=1) < 0.045
        out[stain] = (0.65, 0.35, 0.15)  # pizza stain
        return out
    # head: round, double chin, greasy side hair, neckbeard under the jaw (none on the chin)
    ch.add(ellipsoid((0, 1.67, 0.02), (0.15, 0.16, 0.15), "head", skin, k=0.03))
    ch.add(ellipsoid((0, 1.565, 0.06), (0.14, 0.07, 0.11), "head", skin, k=0.05))  # double chin
    ch.add(ellipsoid((0, 1.53, 0.0), (0.16, 0.08, 0.13), "neck", beard, k=0.04, noise=(0.008, 30, 2.0)))  # the neckbeard
    ch.add(mirror(lambda x: ellipsoid((x * 0.14, 1.66, -0.03), (0.04, 0.1, 0.08), "head", (0.3, 0.22, 0.15), k=0.02, noise=(0.006, 30))))
    ch.add(sphere((0, 1.655, 0.165), 0.035, "head", (0.97, 0.66, 0.6), k=0.02))  # nose
    cartoon_eyes(ch, "head", 1.69, 0.13, 0.055, 0.024, look=(0, -0.2, 1))
    for x in (-1, 1):  # glasses
        ch.add(torus((x * 0.055, 1.69, 0.15), 0.036, 0.006, "head", (0.08, 0.08, 0.08), rot=(PI / 2, 0, 0), k=0.0, mat="shiny"))
    ch.add(capsule((-0.02, 1.69, 0.152), (0.02, 1.69, 0.152), 0.005, "head", (0.08, 0.08, 0.08), k=0.0, mat="shiny"))
    ch.add(capsule((-0.04, 1.6, 0.15), (0.04, 1.6, 0.15), 0.008, "head", (0.6, 0.3, 0.3), k=0.004))  # smirk
    # fedora
    ch.add(cylinder((0, 1.77, 0.0), (0, 1.79, 0.0), 0.24, "head", (0.25, 0.18, 0.12), k=0.0))
    ch.add(ellipsoid((0, 1.86, 0.0), (0.15, 0.1, 0.16), "head", (0.28, 0.2, 0.13), k=0.01))
    ch.add(ellipsoid((0, 1.9, 0.0), (0.05, 0.03, 0.12), "head", (0.2, 0.14, 0.09), k=0.015))  # crease
    ch.add(cylinder((0, 1.79, 0.0), (0, 1.83, 0.0), 0.153, "head", (0.1, 0.08, 0.06), k=0.0))  # band
    # torso: the shirt is too small and rides up; the belly hangs out under it
    ch.add(capsule((0, 1.48, 0), (0, 1.56, 0), 0.08, "neck", skin, k=0.03))
    ch.add(ellipsoid((0, 1.33, 0.02), (0.27, 0.17, 0.2), "chest", tee_col, k=0.05))
    ch.add(ellipsoid((0, 1.22, 0.06), (0.3, 0.12, 0.24), "spine", tee_col, k=0.05))
    ch.add(ellipsoid((0, 1.0, 0.13), (0.33, 0.27, 0.3), "spine", skin, k=0.08))  # THE BELLY
    ch.add(sphere((0, 0.96, 0.425), 0.018, "spine", (0.7, 0.45, 0.4), k=0.01))  # navel
    ch.add(ellipsoid((0, 0.86, -0.01), (0.27, 0.12, 0.2), "hips", shorts, k=0.04))
    for x in (-1, 1):  # cargo pockets
        ch.add(box((x * 0.19, 0.66, 0.05), (0.06, 0.08, 0.05), "hip_" + ("l" if x < 0 else "r"), (0.5, 0.45, 0.32), r=0.015, k=0.01))
    for side, x in (("l", -1), ("r", 1)):
        sh, el, hd = H(s, f"shoulder_{side}"), H(s, f"elbow_{side}"), H(s, f"hand_{side}")
        ch.add(ellipsoid(sh + np.array([x * 0.02, -0.04, 0]), (0.1, 0.1, 0.1), f"shoulder_{side}", tee, k=0.04))
        ch.add(capsule(sh, el, 0.075, f"shoulder_{side}", skin, rb=0.065, k=0.03))
        ch.add(capsule(el, hd, 0.065, f"elbow_{side}", skin, rb=0.05, k=0.03))
        hand(ch, f"hand_{side}", hd + np.array([0, -0.045, 0.0]), 0.05, skin, side=-x)
        hp, kn, ft = H(s, f"hip_{side}"), H(s, f"knee_{side}"), H(s, f"foot_{side}")
        ch.add(capsule(hp, kn, 0.11, f"hip_{side}", shorts, rb=0.09, k=0.03))
        ch.add(capsule(kn, ft + np.array([0, 0.04, 0]), 0.085, f"knee_{side}", skin, rb=0.06, k=0.02))
        ch.add(cylinder(ft + np.array([0, 0.06, 0]), ft + np.array([0, 0.16, 0]), 0.062, f"knee_{side}", (0.95, 0.95, 0.95), k=0.01))  # socks
        boot(ch, f"foot_{side}", x * 0.13, (0.85, 0.85, 0.88), length=0.14)
    def belly_jiggle(t, dur=2.6):
        ph = 2 * PI * t / dur
        return {"spine": (0.03 * math.sin(ph * 2), 0, 0.02 * math.sin(ph)), "chest": (-0.04 + 0.02 * math.sin(ph), 0, 0),
                "head": (0.05 * math.sin(ph), 0.15 * math.sin(ph * 0.5), 0),
                "shoulder_l": (-0.5, 0.3, -0.35), "elbow_l": (-1.2, 0, 0), "shoulder_r": (-0.5, -0.3, 0.35), "elbow_r": (-1.2, 0, 0),
                "_hips_offset": (0, 0.008 * math.sin(ph * 2), 0)}
    ch.anim("idle", 2.6, belly_jiggle)
    ch.anim("talk", 2.0, lambda t: {"shoulder_r": (-0.9 - 0.3 * math.sin(2 * PI * t), 0, 0.3), "elbow_r": (-1.3, 0, 0),
                                   "shoulder_l": (-0.4, 0.3, -0.35), "elbow_l": (-1.2, 0, 0), "head": (0.08 * math.sin(4 * PI * t), 0.2 * math.sin(2 * PI * t), 0)})
    # tips his fedora
    ch.anim("tip_hat", 1.6, keyed([(0.0, {"shoulder_r": (-0.5, -0.3, 0.35), "elbow_r": (-1.2, 0, 0), "head": (0, 0, 0)}),
                                   (0.5, {"shoulder_r": (-2.4, 0, 0.55), "elbow_r": (-2.2, 0, 0), "head": (0.25, 0, 0)}),
                                   (1.1, {"shoulder_r": (-2.4, 0, 0.55), "elbow_r": (-2.2, 0, 0), "head": (0.25, 0, 0)}),
                                   (1.6, {"shoulder_r": (-0.5, -0.3, 0.35), "elbow_r": (-1.2, 0, 0), "head": (0, 0, 0)})]))
    return ch

# =============================================================================== SHOP STAND
def shop_stand():
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("shop_stand", s, voxel=0.028)
    wood = speckle((0.55, 0.38, 0.22), 0.1, 14); dark = speckle((0.38, 0.26, 0.15), 0.1, 14)
    def planks(p):
        out = wood(p); seam = np.abs(((p[:, 1] + 0.02) % 0.16) - 0.08) > 0.072
        out[seam] = (0.3, 0.2, 0.12); return out
    ch.add(box((0, 0.5, 0), (1.3, 0.5, 0.35), "root", planks, r=0.02, k=0.0))            # counter
    ch.add(box((0, 1.03, 0.0), (1.4, 0.035, 0.45), "root", dark, r=0.015, k=0.0))       # counter top
    for x in (-1.3, 1.3):
        for z in (-0.4, 0.5):
            ch.add(box((x, 1.3, z), (0.05, 1.3, 0.05), "root", dark, r=0.01, k=0.0))     # posts
    stripe = stripes((0.85, 0.15, 0.15), (0.97, 0.95, 0.9), axis=0, period=0.22)
    ch.add(box((0, 2.62, 0.05), (1.5, 0.04, 0.75), "root", stripe, r=0.02, k=0.0, rot=(0.18, 0, 0)))  # awning
    for i in range(7):  # scalloped awning edge
        ch.add(sphere((-1.29 + i * 0.43, 2.48, 0.78), 0.11, "root", stripe, k=0.0))
    ch.add(box((0, 2.95, -0.35), (1.0, 0.22, 0.03), "root", (0.92, 0.85, 0.62), r=0.02, k=0.0))  # sign board (text in game)
    ch.add(capsule((-1.2, 2.3, 0.45), (1.2, 2.3, 0.45), 0.02, "root", (0.6, 0.6, 0.62), mat="metal", k=0.0))  # hook rail
    meat = (0.62, 0.22, 0.14); bone_c = (0.95, 0.92, 0.82)
    for x in (-0.8, -0.35, 0.1):  # bait hanging on hooks
        ch.add(capsule((x, 2.3, 0.45), (x, 2.15, 0.45), 0.006, "root", (0.6, 0.6, 0.62), mat="metal", k=0.0))
        ch.add(ellipsoid((x, 1.98, 0.45), (0.12, 0.16, 0.1), "root", meat, k=0.02))
        ch.add(capsule((x, 2.12, 0.45), (x, 2.2, 0.45), 0.02, "root", bone_c, k=0.01))
    # traps on display on the counter
    steel = (0.45, 0.45, 0.48)
    for x in (0.55, 1.0):
        ch.add(torus((x, 1.08, 0.05), 0.17, 0.012, "root", steel, k=0.0, mat="metal"))
        for i in range(8):
            a = i / 8 * 2 * PI
            ch.add(capsule((x + math.cos(a) * 0.17, 1.08, 0.05 + math.sin(a) * 0.17), (x + math.cos(a) * 0.17, 1.12, 0.05 + math.sin(a) * 0.17), 0.008, "root", steel, rb=0.001, mat="metal", k=0.0))
        ch.add(box((x, 1.075, 0.05), (0.2, 0.01, 0.02), "root", steel, r=0.004, mat="metal", k=0.0))
    # cooler for fresh bait + a cash box
    ch.add(box((-0.75, 1.2, 0.05), (0.28, 0.15, 0.2), "root", (0.2, 0.45, 0.85), r=0.04, k=0.0))
    ch.add(box((-0.75, 1.36, 0.05), (0.29, 0.025, 0.21), "root", (0.95, 0.95, 0.95), r=0.02, k=0.0))
    ch.add(box((-0.2, 1.12, -0.15), (0.13, 0.06, 0.09), "root", (0.3, 0.45, 0.3), r=0.01, k=0.0, mat="metal"))
    ch.add(box((0, 0.6, -0.5), (1.1, 0.03, 0.12), "root", wood, r=0.01, k=0.0))  # back shelf
    return ch

# =============================================================================== RV EXTERIOR
def rv_exterior():
    """70s Class C motorhome: cream body with retro stripes, cab-over bunk, sloped hood, round
    headlights, chrome bumpers, ladder, roof AC, spare tire. +X = front, door side = -Z."""
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("rv_exterior", s, voxel=0.04)
    cream = speckle((0.93, 0.9, 0.8), 0.03, 6)
    teal = (0.1, 0.62, 0.62); orange = (0.98, 0.55, 0.12); brown = (0.45, 0.24, 0.12); gold = (1.0, 0.8, 0.15)
    def livery(p):
        out = cream(p)
        y = p[:, 1]
        out[(y > 1.05) & (y < 1.17)] = gold
        out[(y > 1.17) & (y < 1.31)] = orange
        out[(y > 1.31) & (y < 1.45)] = brown
        out[(y > 2.45) & (y < 2.55)] = teal          # thin pinstripe up top
        out[y < 0.75] = (0.85, 0.82, 0.72)              # dirtier skirt
        return out
    glass = (0.1, 0.14, 0.22); chrome = (0.82, 0.83, 0.86); tire = (0.07, 0.07, 0.08)
    # coach body (rear living box) and the cab-over bunk
    ch.add(box((-0.35, 1.62, 0), (1.95, 1.07, 1.12), "root", livery, r=0.16, k=0.0))
    ch.add(box((1.95, 2.25, 0), (0.55, 0.42, 1.08), "root", livery, r=0.22, k=0.0))
    # cab: box under the bunk, then the sloped hood
    ch.add(box((2.15, 1.25, 0), (0.62, 0.72, 1.0), "root", livery, r=0.12, k=0.0))
    ch.add(box((2.95, 0.95, 0), (0.42, 0.4, 0.95), "root", livery, r=0.18, k=0.0, rot=(0, 0, -0.12)))
    # windshield (sloped), cab side windows, bunk window
    ch.add(box((2.8, 1.66, 0), (0.04, 0.27, 0.86), "root", glass, r=0.04, k=0.0, rot=(0, 0, -0.12), mat="shiny"))
    ch.add(box((2.82, 1.66, 0), (0.045, 0.29, 0.025), "root", chrome, r=0.01, k=0.0, mat="metal"))  # centre pillar
    for z in (-1.0, 1.0):
        ch.add(box((2.25, 1.6, z * 1.0), (0.33, 0.28, 0.03), "root", glass, r=0.04, k=0.0, mat="shiny"))
        # coach windows with little brown shutters
        for x in (-1.55, 0.95):
            ch.add(box((x, 1.85, z * 1.12), (0.42, 0.26, 0.03), "root", glass, r=0.05, k=0.0, mat="shiny"))
            ch.add(box((x - 0.5, 1.85, z * 1.13), (0.06, 0.29, 0.025), "root", brown, r=0.02, k=0.0))
            ch.add(box((x + 0.5, 1.85, z * 1.13), (0.06, 0.29, 0.025), "root", brown, r=0.02, k=0.0))
    ch.add(box((2.5, 2.3, 0), (0.03, 0.14, 0.55), "root", glass, r=0.04, k=0.0, mat="shiny"))
    # back window
    ch.add(box((-2.3, 1.95, 0), (0.03, 0.22, 0.5), "root", glass, r=0.04, k=0.0, mat="shiny"))
    # door frame on the -Z side (the door itself is animated in the game)
    ch.add(box((0.0, 1.35, -1.125), (0.5, 0.86, 0.02), "root", brown, r=0.02, k=0.0))
    # wheel wells, tires, hubcaps
    for x in (-1.3, 2.55):
        for z in (-1.0, 1.0):
            ch.add(cylinder((x, 0.42, z * 0.98), (x, 0.42, z * 1.06), 0.5, "root", (0.15, 0.13, 0.12), k=0.0))
            ch.add(cylinder((x, 0.42, z * 0.88), (x, 0.42, z * 1.12), 0.42, "root", tire, rounding=0.06, k=0.0))
            ch.add(cylinder((x, 0.42, z * 1.08), (x, 0.42, z * 1.16), 0.24, "root", chrome, k=0.0, mat="metal"))
            ch.add(sphere((x, 0.42, z * 1.16), 0.07, "root", chrome, k=0.0, mat="metal"))
    # bumpers, grille, headlights, tail lights, mirrors
    ch.add(box((3.38, 0.62, 0), (0.06, 0.1, 1.0), "root", chrome, r=0.04, k=0.0, mat="metal"))
    ch.add(box((-2.32, 0.62, 0), (0.06, 0.09, 1.05), "root", chrome, r=0.04, k=0.0, mat="metal"))
    ch.add(box((3.33, 0.98, 0), (0.03, 0.2, 0.45), "root", chrome, r=0.03, k=0.0, mat="metal"))
    for i in range(5):
        ch.add(box((3.36, 0.86 + i * 0.06, 0), (0.02, 0.012, 0.42), "root", (0.15, 0.15, 0.17), r=0.005, k=0.0))
    head = ch.glow("headlight", (1.0, 0.95, 0.75))
    tail = ch.glow("taillight", (1.0, 0.1, 0.05))
    for z in (-0.72, 0.72):
        ch.add(cylinder((3.3, 1.0, z), (3.38, 1.0, z), 0.14, "root", chrome, k=0.0, mat="metal"))
        ch.add(cylinder((3.36, 1.0, z), (3.4, 1.0, z), 0.11, "root", (1.0, 0.95, 0.75), k=0.0, mat=head))
        ch.add(box((-2.33, 0.95, z * 1.25), (0.03, 0.14, 0.08), "root", (1.0, 0.1, 0.05), r=0.02, k=0.0, mat=tail))
        ch.add(capsule((2.6, 1.55, z * 1.38), (2.6, 1.2, z * 1.38), 0.015, "root", chrome, mat="metal", k=0.0))
        ch.add(box((2.6, 1.55, z * 1.42), (0.03, 0.14, 0.09), "root", (0.1, 0.1, 0.1), r=0.02, k=0.0))
    # roof: AC unit, vent, ladder up the back, spare tire
    ch.add(box((-0.6, 2.82, 0), (0.42, 0.13, 0.36), "root", (0.9, 0.9, 0.88), r=0.06, k=0.0))
    for i in range(4):
        ch.add(box((-0.6 + (i - 1.5) * 0.18, 2.96, 0), (0.05, 0.01, 0.3), "root", (0.6, 0.6, 0.6), r=0.005, k=0.0))
    ch.add(box((0.9, 2.74, 0.4), (0.22, 0.05, 0.22), "root", (0.85, 0.85, 0.8), r=0.03, k=0.0))
    for z in (0.35, 0.75):
        ch.add(capsule((-2.37, 0.7, z), (-2.37, 2.85, z), 0.02, "root", chrome, mat="metal", k=0.0))
    for i in range(7):
        ch.add(capsule((-2.37, 0.85 + i * 0.3, 0.35), (-2.37, 0.85 + i * 0.3, 0.75), 0.015, "root", chrome, mat="metal", k=0.0))
    ch.add(cylinder((-2.33, 1.35, -0.55), (-2.48, 1.35, -0.55), 0.36, "root", tire, rounding=0.06, k=0.0))
    ch.add(cylinder((-2.46, 1.35, -0.55), (-2.5, 1.35, -0.55), 0.2, "root", teal, k=0.0))
    # running board under the door
    ch.add(box((0.0, 0.32, -1.22), (0.5, 0.03, 0.14), "root", chrome, r=0.01, k=0.0, mat="metal"))
    return ch

# =============================================================================== RV INTERIOR PROPS
def rv_cab():
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("rv_cab", s, voxel=0.017)
    seat = speckle((0.35, 0.22, 0.15), 0.06, 25); dash = speckle((0.16, 0.16, 0.18), 0.05, 25)
    for x in (-0.45, 0.45):
        ch.add(box((x, 0.45, 0.0), (0.24, 0.07, 0.24), "root", seat, r=0.05, k=0.03))
        ch.add(box((x, 0.85, -0.22), (0.24, 0.35, 0.06), "root", seat, r=0.05, k=0.03, rot=(-0.15, 0, 0)))
        ch.add(box((x, 1.25, -0.27), (0.13, 0.08, 0.05), "root", seat, r=0.04, k=0.02))  # headrest
        ch.add(cylinder((x, 0.0, 0.0), (x, 0.38, 0.0), 0.05, "root", (0.3, 0.3, 0.32), mat="metal", k=0.0))
    ch.add(box((0, 0.85, 0.75), (1.0, 0.2, 0.25), "root", dash, r=0.06, k=0.03))
    # Driver sits on the left (authored +X ends up on the left once the cab faces forward in the RV).
    for i, x in enumerate((0.6, 0.42)):  # gauges glow faintly
        ch.add(cylinder((x, 0.98, 0.56), (x, 0.98, 0.52), 0.06, "root", (0.9, 0.7, 0.3), mat="shiny", k=0.0))
    ch.add(torus((0.45, 1.12, 0.26), 0.17, 0.018, "root", (0.1, 0.1, 0.1), rot=(1.2, 0, 0), k=0.0))  # steering wheel, clear of the dash
    ch.add(capsule((0.45, 1.09, 0.29), (0.45, 0.98, 0.55), 0.03, "root", (0.1, 0.1, 0.1), k=0.0))
    ch.add(capsule((0.0, 0.42, 0.25), (0.0, 0.65, 0.3), 0.015, "root", (0.2, 0.2, 0.2), k=0.0, mat="metal"))  # gear stick
    ch.add(sphere((0.0, 0.67, 0.31), 0.03, "root", (0.1, 0.1, 0.1), k=0.0, mat="shiny"))
    ch.add(ellipsoid((-0.25, 1.07, 0.66), (0.04, 0.05, 0.02), "root", (0.95, 0.85, 0.2), k=0.0))  # air freshener tree
    return ch

def rv_bed():
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("rv_bed", s, voxel=0.02)
    ch.add(box((0, 0.22, 0), (0.75, 0.22, 1.0), "root", speckle((0.45, 0.32, 0.2), 0.08, 14), r=0.02, k=0.0))
    ch.add(box((0, 0.5, 0), (0.72, 0.09, 0.97), "root", (0.92, 0.9, 0.85), r=0.06, k=0.0))  # mattress
    ch.add(ellipsoid((0, 0.62, -0.75), (0.4, 0.07, 0.18), "root", (0.98, 0.98, 0.95), k=0.02))  # pillow
    plaid_c = plaid((0.7, 0.15, 0.15), (0.2, 0.2, 0.25), (0.9, 0.85, 0.7), period=0.12)
    ch.add(box((0, 0.6, 0.25), (0.74, 0.04, 0.7), "root", plaid_c, r=0.03, k=0.0, noise=(0.025, 4, 7.0)))
    ch.add(ellipsoid((0.25, 0.68, 0.05), (0.3, 0.06, 0.22), "root", plaid_c, k=0.06, noise=(0.02, 5, 2.0)))  # rumpled lump
    ch.add(box((0, 0.7, -1.05), (0.75, 0.25, 0.04), "root", speckle((0.45, 0.32, 0.2), 0.08, 14), r=0.02, k=0.0))  # headboard
    return ch

def rv_darkroom():
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("rv_darkroom", s, voxel=0.016)
    ch.add(box((0, 0.45, 0), (0.9, 0.45, 0.3), "root", speckle((0.2, 0.2, 0.22), 0.05, 20), r=0.02, k=0.0))  # cabinet
    ch.add(box((0, 0.92, 0), (0.95, 0.025, 0.33), "root", (0.3, 0.3, 0.32), r=0.01, k=0.0))
    for i, x in enumerate((-0.55, -0.15, 0.25)):  # developer / stop / fix trays
        c = [(0.85, 0.85, 0.85), (0.9, 0.3, 0.3), (0.3, 0.5, 0.9)][i]
        ch.add(box((x, 0.97, 0.02), (0.17, 0.03, 0.13), "root", c, r=0.01, k=0.0, mat="shiny"))
        ch.add(box((x, 0.985, 0.02), (0.14, 0.012, 0.1), "root", (0.25, 0.22, 0.12), r=0.005, k=0.0, mat="shiny"))  # liquid
    # enlarger
    ch.add(box((0.68, 0.96, -0.05), (0.16, 0.02, 0.16), "root", (0.1, 0.1, 0.1), r=0.01, k=0.0))
    ch.add(capsule((0.68, 0.96, -0.18), (0.68, 1.55, -0.18), 0.025, "root", (0.7, 0.7, 0.72), mat="metal", k=0.0))
    ch.add(box((0.68, 1.4, -0.06), (0.09, 0.1, 0.12), "root", (0.12, 0.12, 0.13), r=0.02, k=0.0))
    ch.add(cylinder((0.68, 1.3, -0.04), (0.68, 1.22, -0.04), 0.04, "root", (0.15, 0.15, 0.15), k=0.0))
    # red safelight
    red = ch.glow("safelight", (1.0, 0.12, 0.08))
    ch.add(sphere((-0.7, 1.75, -0.2), 0.06, "root", (1.0, 0.2, 0.15), mat=red, k=0.0))
    ch.add(cylinder((-0.7, 1.8, -0.2), (-0.7, 1.95, -0.2), 0.012, "root", (0.2, 0.2, 0.2), k=0.0))
    return ch


# =============================================================================== THE CAMERA
def camera_lo():
    """Same camera, coarser (for props: Toe's hands, the camera pile, the third-person body)."""
    ch = camera(); ch.name = "camera_lo"; ch.voxel = 0.0042
    return ch

def camera():
    """The paparazzo's camera: a chunky 35mm SLR with a long lens and a flashgun on the hot shoe.
    Authored lens-forward along +Z, origin at the middle of the body. Crisp edges (k=0): it's a machine.
    The +X side is the lens-release side; the hand grip and shutter button are on -X."""
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("camera", s, voxel=0.0022)
    flash = ch.glow("flash", (1.0, 1.0, 0.92))
    leather = speckle((0.07, 0.07, 0.075), 0.025, 260)
    chrome = (0.78, 0.78, 0.8); dark = (0.12, 0.12, 0.13); grey = (0.3, 0.3, 0.32)
    # body: leatherette wrap between a chrome top plate and base plate
    ch.add(box((0, -0.002, 0), (0.072, 0.038, 0.027), "root", leather, r=0.006, k=0.0))
    ch.add(box((0, 0.04, 0), (0.073, 0.007, 0.028), "root", chrome, r=0.004, k=0.0, mat="metal"))
    ch.add(box((0, -0.043, 0), (0.073, 0.004, 0.028), "root", chrome, r=0.003, k=0.0, mat="metal"))
    # pentaprism hump
    ch.add(box((0, 0.056, -0.002), (0.026, 0.014, 0.024), "root", dark, r=0.004, k=0.0))
    ch.add(box((0, 0.066, 0.004), (0.02, 0.006, 0.018), "root", dark, r=0.003, k=0.0, rot=(0.35, 0, 0)))
    ch.add(box((0, 0.056, 0.0225), (0.016, 0.006, 0.002), "root", chrome, r=0.001, k=0.0, mat="metal"))   # name plate
    # hand grip on the -X side, shutter button on top of it
    ch.add(box((-0.056, -0.004, 0.031), (0.016, 0.036, 0.01), "root", leather, r=0.007, k=0.0))
    ch.add(cylinder((-0.052, 0.047, 0.012), (-0.052, 0.052, 0.012), 0.006, "root", chrome, k=0.0, mat="metal"))
    ch.add(cylinder((-0.052, 0.052, 0.012), (-0.052, 0.054, 0.012), 0.0035, "root", (0.85, 0.12, 0.1), k=0.0))
    # dials: shutter speed (knurled), film rewind crank, advance lever
    ch.add(cylinder((-0.034, 0.047, -0.004), (-0.034, 0.055, -0.004), 0.011, "root", chrome, k=0.0, mat="metal"))
    for i in range(16):
        a = 2 * PI * i / 16
        ch.add(box((-0.034 + 0.0112 * math.cos(a), 0.051, -0.004 + 0.0112 * math.sin(a)), (0.0012, 0.0035, 0.0012), "root", grey, r=0.0004, k=0.0))
    ch.add(cylinder((0.046, 0.047, -0.004), (0.046, 0.056, -0.004), 0.009, "root", chrome, k=0.0, mat="metal"))
    ch.add(box((0.046, 0.058, 0.002), (0.0025, 0.0015, 0.008), "root", chrome, r=0.001, k=0.0, mat="metal"))
    ch.add(box((-0.05, 0.048, -0.018), (0.016, 0.0018, 0.004), "root", chrome, r=0.0015, k=0.0, mat="metal", rot=(0, 0.5, 0)))
    # back: rubber eyepiece, film window, a PRESS sticker
    ch.add(box((0, 0.054, -0.028), (0.011, 0.009, 0.006), "root", (0.04, 0.04, 0.045), r=0.003, k=0.0))
    ch.add(box((0, 0.054, -0.0345), (0.007, 0.005, 0.0012), "root", (0.15, 0.2, 0.3), r=0.001, k=0.0, mat="shiny"))
    ch.add(box((0.04, -0.008, -0.0275), (0.018, 0.012, 0.0012), "root", (0.85, 0.75, 0.3), r=0.001, k=0.0))
    ch.add(box((-0.03, 0.005, -0.0275), (0.022, 0.014, 0.0012), "root", (0.92, 0.9, 0.85), r=0.0015, k=0.0))
    ch.add(box((-0.03, 0.005, -0.028), (0.018, 0.004, 0.0008), "root", (0.8, 0.1, 0.08), r=0.0005, k=0.0))
    # strap lugs
    for x in (-1, 1):
        ch.add(torus((x * 0.075, 0.028, 0.0), 0.005, 0.0016, "root", chrome, rot=(0, 0, PI / 2), k=0.0, mat="metal"))
    # lens: chrome mount, ribbed focus ring, aperture ring, front bezel, glass
    z0 = 0.027
    ch.add(cylinder((0, -0.004, z0), (0, -0.004, z0 + 0.008), 0.031, "root", chrome, k=0.0, mat="metal"))
    ch.add(cylinder((0, -0.004, z0 + 0.008), (0, -0.004, z0 + 0.03), 0.028, "root", dark, k=0.0))
    for i in range(24):
        a = 2 * PI * i / 24
        ch.add(box((0.0285 * math.cos(a), -0.004 + 0.0285 * math.sin(a), z0 + 0.019), (0.0018, 0.0018, 0.009), "root", (0.05, 0.05, 0.055),
                   r=0.0006, k=0.0, rot=(0, 0, a)))
    ch.add(cylinder((0, -0.004, z0 + 0.03), (0, -0.004, z0 + 0.075), 0.026, "root", dark, k=0.0))
    for i in range(7):
        a = PI * 0.25 + i * 0.12
        ch.add(box((0.0262 * math.cos(a), -0.004 + 0.0262 * math.sin(a), z0 + 0.034), (0.0006, 0.0006, 0.003), "root", (0.95, 0.95, 0.9),
                   r=0.0002, k=0.0, rot=(0, 0, a)))
    ch.add(cylinder((0, -0.004, z0 + 0.075), (0, -0.004, z0 + 0.092), 0.031, "root", dark, k=0.0))
    ch.add(torus((0, -0.004, z0 + 0.092), 0.0285, 0.0028, "root", chrome, rot=(PI / 2, 0, 0), k=0.0, mat="metal"))
    ch.add(cylinder((0, -0.004, z0 + 0.086), (0, -0.004, z0 + 0.09), 0.025, "root", (0.12, 0.2, 0.42), k=0.0, mat="shiny"))
    ch.add(sphere((0, -0.004, z0 + 0.075), 0.0175, "root", (0.25, 0.45, 0.75), k=0.0, mat="shiny"))
    # flashgun on the hot shoe
    ch.add(box((0, 0.073, -0.004), (0.012, 0.004, 0.01), "root", chrome, r=0.001, k=0.0, mat="metal"))
    ch.add(box((0, 0.093, -0.004), (0.022, 0.017, 0.014), "root", dark, r=0.004, k=0.0))
    ch.add(box((0, 0.093, -0.0185), (0.012, 0.008, 0.0012), "root", (0.9, 0.4, 0.1), r=0.001, k=0.0))   # ready lamp panel
    ch.add(box((0, 0.124, 0.0), (0.03, 0.016, 0.017), "root", dark, r=0.004, k=0.0))
    ch.add(box((0, 0.124, 0.0178), (0.026, 0.0125, 0.0015), "root", (1.0, 1.0, 0.92), r=0.002, k=0.0, mat=flash))
    return ch

# =============================================================================== FIRST-PERSON ARMS (camera space, +Z = forward)
FP_CAMERA = (-0.13, -0.2, 0.52)   # where scripts/player.gd hangs models/camera.glb (arms' own frame)

def fp_arms():
    """Just the arms and hands. The camera is its own model (camera.glb) placed at FP_CAMERA in the
    game, so hands and camera never blend into one blob. Fingers rest on its surfaces."""
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("fp_arms", s, voxel=0.0055)
    # Authored mirrored in X: Godot turns the model 180 degrees to face -Z, which swaps left/right.
    cam = np.array(FP_CAMERA)
    # right hand wraps the grip (camera's -X side): palm on the side, fingers round the front, thumb at the back
    rh = cam + np.array([-0.094, -0.004, 0.012])
    ch.add(ellipsoid(rh, (0.02, 0.05, 0.036), "root", SKIN, k=0.012))
    for i in range(4):
        y = 0.022 - i * 0.017
        a = rh + np.array([0.008, y, 0.03]); b = cam + np.array([-0.05, y - 0.004, 0.047])
        ch.add(capsule(a, b, 0.0085, "root", SKIN, k=0.004))
    ch.add(capsule(rh + (0.004, 0.032, -0.02), cam + (-0.062, 0.03, -0.034), 0.009, "root", SKIN, k=0.005))   # thumb on the back
    # left hand cradles the lens from underneath, fingers up its near side, thumb up the far side
    lh = cam + np.array([0.004, -0.058, 0.06])
    ch.add(ellipsoid(lh, (0.042, 0.017, 0.048), "root", SKIN, k=0.012))
    for i in range(4):
        z = 0.036 + i * 0.016
        a = lh + np.array([0.034, 0.004, z - 0.06]); b = cam + np.array([0.034, -0.012, z])
        ch.add(capsule(a, b, 0.0082, "root", SKIN, k=0.004))
    ch.add(capsule(lh + (-0.034, 0.006, -0.005), cam + (-0.032, -0.018, 0.07), 0.009, "root", SKIN, k=0.005))
    lel = np.array([0.22, -0.5, 0.16]); rel = np.array([-0.4, -0.5, 0.16])
    ch.add(capsule(lh + (0, -0.01, -0.03), lel, 0.032, "root", SKIN, rb=0.042, k=0.02))
    ch.add(capsule(rh + (-0.01, -0.03, -0.02), rel, 0.032, "root", SKIN, rb=0.042, k=0.02))
    for e in (lel, rel):
        ch.add(capsule(e, e + (0, -0.12, -0.08), 0.058, "root", (0.15, 0.55, 0.6), k=0.02))
        ch.add(torus(e + (0, 0.02, 0.015), 0.052, 0.016, "root", (0.12, 0.47, 0.52), rot=(0.6, 0, 0), k=0.01))
    return ch

BUILDERS = {"fhairy": fhairy, "leperchaun": leperchaun, "the_rake": the_rake, "bent": bent, "santa_sleigh": santa_sleigh,
            "ped_suit": ped_suit, "ped_hoodie": ped_hoodie, "rv_exterior": rv_exterior, "shopkeeper": shopkeeper, "shop_stand": shop_stand, "rv_cab": rv_cab, "rv_bed": rv_bed, "rv_darkroom": rv_darkroom,
            "toe_rogan": toe_rogan, "camera": camera, "camera_lo": camera_lo, "fp_arms": fp_arms, "photographer": photographer, "bigboobs": bigboobs, "methman": methman, "methman_camp": methman_camp,
            "wherewolf": wherewolf, "grey_tourist": grey_tourist, "cornicorn": cornicorn, "jersey_devil": jersey_devil,
            "crackin": crackin, "oh_go_pogo": oh_go_pogo}

def add_reaction_anims(ch):
    """Every biped cryptid can eat bait, get caught in a trap and roar, scaled to its own hip height."""
    s = ch.skel
    if "shoulder_l" not in s.names or "hip_l" not in s.names:
        return
    k = s.heads[s.idx("hips")][1] / 1.1
    def scaled(fn):
        def f(t):
            out = dict(fn(t))
            if "_hips_offset" in out:
                x, y, z = out["_hips_offset"]; out["_hips_offset"] = (x, y * k, z)
            return out
        return f
    for nm, dur, fn in (("eat", 1.4, eat_anim), ("trapped", 1.0, trapped_anim), ("roar", 1.2, roar_anim)):
        if nm not in ch.anims:
            ch.anim(nm, dur, scaled(fn))

try:
    import skins as _skins_mod
    for _sk in _skins_mod.SKINS:
        BUILDERS["photographer_" + _sk] = (lambda k=_sk: photographer(k))
except ImportError:
    pass

CRYPTIDS = {"bigboobs", "methman", "wherewolf", "grey_tourist", "jersey_devil", "crackin", "fhairy", "leperchaun", "the_rake", "bent"}

if __name__ == "__main__":
    for name, fn in BUILDERS.items():
        if ONLY and name not in ONLY: continue
        ch = fn()
        if name in CRYPTIDS:
            add_reaction_anims(ch)
        ch.build(os.path.join(OUT, name + ".glb"))
