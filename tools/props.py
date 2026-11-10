#!/usr/bin/env python3
"""Higher-detail props for the style previews (and, if a style is picked, the game).
Usage: python3 tools/props.py <out_dir> [name ...]
Material groups: body = car paint, metal = chrome / rims, shiny = glass, cloth = rubber & plastic."""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from charkit import *

OUT = sys.argv[1] if len(sys.argv) > 1 else "models"
ONLY = set(sys.argv[2:])
os.makedirs(OUT, exist_ok=True)


def car_sedan():
    """A four-door sedan, ~4.5 m long, front at +z. Real wheel arches, a slanted windshield and
    rear window, inset glass, bumpers, grille, lights, mirrors, door seams and handles."""
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("car_sedan", s, voxel=0.02)
    ch.group_voxel = {"body": 0.022, "metal": 0.018, "shiny": 0.022, "cloth": 0.024}
    paint = (0.85, 0.85, 0.85)   # tinted per car in the game
    def body_col(p):
        out = np.tile(np.array(paint), (len(p), 1))
        seam = ((np.abs(p[:, 2] - 0.18) < 0.008) | (np.abs(p[:, 2] + 0.95) < 0.008) | (np.abs(p[:, 2] - 1.28) < 0.008)) \
            & (p[:, 1] > 0.35) & (p[:, 1] < 0.95) & (np.abs(p[:, 0]) > 0.82)
        out[seam] = (0.25, 0.25, 0.25)
        return out
    # Lower body: long rounded box with a gently sloping hood and boot, wheel arches cut out.
    ch.add(box((0, 0.62, 0.0), (0.88, 0.3, 2.22), "root", body_col, r=0.16, k=0.02))
    ch.add(box((0, 0.42, 0.0), (0.86, 0.12, 2.2), "root", body_col, r=0.08, k=0.06))
    ch.add(box((0, 1.05, 1.55), (1.2, 0.2, 0.8), "root", body_col, rot=(-0.12, 0, 0), sub=True, k=0.06))
    ch.add(box((0, 1.05, -1.6), (1.2, 0.2, 0.7), "root", body_col, rot=(0.1, 0, 0), sub=True, k=0.06))
    for z in (1.38, -1.38):
        ch.add(cylinder((-1.2, 0.36, z), (1.2, 0.36, z), 0.43, "root", body_col, rounding=0.02, sub=True, k=0.03))
    # The glasshouse: one dark-glass shape (windscreen, side windows, rear window) with the
    # roof, pillars and window frames in paint over it. Slopes come from flat planes.
    def plane_fn(planes):
        planes = [(np.asarray(n, float) / np.linalg.norm(n), d / np.linalg.norm(n)) for n, d in planes]
        return lambda p: np.max(np.stack([p @ n - d for n, d in planes], 1), 1)
    def slanted(y0, y1, half_x, top_in, zf0, zf1, zr0, zr1, inset=0.0):
        # front plane through (y0, zf0)-(y1, zf1); rear through (y0, zr0)-(y1, zr1); sides lean in
        fn_ = np.array([0.0, zf0 - zf1, y1 - y0]); df = fn_ @ np.array([0, y0, zf0])
        rn_ = np.array([0.0, zr1 - zr0, -(y1 - y0)]); dr = rn_ @ np.array([0, y0, zr0])
        side = []
        for sx in (-1, 1):
            n = np.array([sx * (y1 - y0), top_in, 0.0]); side.append((n, n @ np.array([sx * half_x, y0, 0]) / 1.0))
        planes = [((0, -1, 0), -y0), ((0, 1, 0), y1), (tuple(fn_), df), (tuple(rn_), dr)] + [(tuple(n), d) for n, d in side]
        fn = plane_fn([(n, d) for n, d in planes])
        return lambda p: fn(p) + inset
    glass_fn = slanted(0.9, 1.38, 0.8, 0.12, 0.98, 0.18, -1.22, -0.72)
    ch.add(Part(glass_fn, "root", (0.08, 0.1, 0.13), k=0.0, mat="shiny", bounds=((-1, 0.8, -1.4), (1, 1.5, 1.2))))
    roof_fn = slanted(1.33, 1.42, 0.7, 0.02, 0.24, 0.14, -0.74, -0.66)
    ch.add(Part(roof_fn, "root", body_col, k=0.02, bounds=((-1, 1.2, -1.0), (1, 1.6, 0.5))))
    # pillars: A (windscreen edges), B (middle), C (rear) and the window sills
    for x in (-1, 1):
        ch.add(capsule((x * 0.79, 0.92, 0.96), (x * 0.69, 1.38, 0.2), 0.035, "root", body_col, k=0.02))
        ch.add(capsule((x * 0.79, 0.92, -1.2), (x * 0.69, 1.38, -0.7), 0.05, "root", body_col, k=0.02))
        ch.add(capsule((x * 0.8, 0.92, -0.3), (x * 0.71, 1.38, -0.3), 0.04, "root", body_col, k=0.02))
        ch.add(capsule((x * 0.82, 0.91, 1.0), (x * 0.82, 0.91, -1.25), 0.03, "root", body_col, k=0.02))
    # Glass trim strip round the windows.
    for x in (-1, 1):
        ch.add(box((x * 0.8, 0.94, -0.12), (0.006, 0.012, 1.05), "root", (0.75, 0.75, 0.78), r=0.004, mat="metal", k=0.0))
        # mirror, door handles, side trim
        ch.add(box((x * 0.92, 0.98, 0.78), (0.1, 0.05, 0.06), "root", paint, r=0.02, k=0.01))
        for z in (0.1, -0.75):
            ch.add(box((x * 0.885, 0.82, z), (0.01, 0.015, 0.07), "root", (0.75, 0.75, 0.78), r=0.004, mat="metal", k=0.0))
        ch.add(box((x * 0.885, 0.5, 0.0), (0.01, 0.02, 1.1), "root", (0.12, 0.12, 0.12), r=0.004, mat="cloth", k=0.0))
    # Bumpers, grille, lights, plate.
    for z, sgn in ((2.2, 1), (-2.2, -1)):
        ch.add(box((0, 0.42, z), (0.86, 0.11, 0.06), "root", (0.12, 0.12, 0.13), r=0.04, mat="cloth", k=0.0))
        ch.add(box((0, 0.5, z + sgn * 0.02), (0.18, 0.08, 0.01), "root", (0.92, 0.92, 0.88), r=0.005, mat="cloth", k=0.0))
    ch.add(box((0, 0.66, 2.21), (0.42, 0.08, 0.02), "root", (0.08, 0.08, 0.09), r=0.02, mat="cloth", k=0.0))
    ch.add(box((0, 0.66, 2.225), (0.44, 0.095, 0.006), "root", (0.75, 0.75, 0.78), r=0.01, mat="metal", k=0.0))
    for x in (-1, 1):
        ch.add(ellipsoid((x * 0.66, 0.7, 2.18), (0.16, 0.06, 0.05), "root", (0.95, 0.95, 0.9), mat="shiny", k=0.0))
        ch.add(ellipsoid((x * 0.66, 0.74, -2.19), (0.17, 0.06, 0.04), "root", (0.8, 0.05, 0.05), mat="shiny", k=0.0))
    # Wheels: tyres with sidewall bulge, five-spoke alloys, brake discs behind.
    for x in (-1, 1):
        for z in (1.38, -1.38):
            c = np.array([x * 0.78, 0.35, z])
            ch.add(torus(c, 0.25, 0.1, "root", (0.07, 0.07, 0.07), rot=(0, 0, math.pi / 2), mat="cloth", k=0.0))
            ch.add(cylinder(c - [0.1, 0, 0], c + [0.1, 0, 0], 0.28, "root", (0.07, 0.07, 0.07), rounding=0.04, mat="cloth", k=0.0))
            rim = c + np.array([x * 0.06, 0, 0])
            ch.add(cylinder(rim - [0.02, 0, 0], rim + [0.02, 0, 0], 0.2, "root", (0.75, 0.76, 0.78), rounding=0.01, mat="metal", k=0.0))
            for k in range(5):
                a = k / 5 * 2 * math.pi
                d = np.array([0, math.cos(a), math.sin(a)])
                ch.add(capsule(rim + np.array([x * 0.025, 0, 0]), rim + np.array([x * 0.025, 0, 0]) + d * 0.18, 0.022, "root",
                               (0.82, 0.83, 0.85), mat="metal", k=0.0))
            ch.add(cylinder(rim + [x * 0.02, 0, 0], rim + [x * 0.05, 0, 0], 0.045, "root", (0.6, 0.6, 0.62), mat="metal"))
    return ch


def car_toon():
    """A chunky cartoon car for the stylized looks: short and tall, a bubble cabin, fat tyres,
    big round headlights and bumpers. Front at +z, ~3.5 m long."""
    s = Skeleton(); s.add("root", None, (0, 0, 0))
    ch = Character("car_toon", s, voxel=0.025)
    ch.group_voxel = {"body": 0.025, "metal": 0.02, "shiny": 0.022, "cloth": 0.025}
    paint = (0.85, 0.85, 0.85)
    dark = (0.08, 0.08, 0.09)
    # Fat tub of a body, a hood that dips to the front, wheel arches cut out.
    ch.add(box((0, 0.78, 0.0), (0.86, 0.38, 1.68), "root", paint, r=0.34, k=0.05))
    ch.add(box((0, 1.25, 1.35), (1.2, 0.25, 0.5), "root", paint, rot=(-0.25, 0, 0), sub=True, k=0.15))
    for z in (1.02, -1.02):
        ch.add(cylinder((-1.2, 0.46, z), (1.2, 0.46, z), 0.56, "root", paint, rounding=0.02, sub=True, k=0.05))
    # Bubble cabin: glass all round, a fat roof cap and chunky pillars over it.
    ch.add(ellipsoid((0, 1.32, -0.25), (0.74, 0.5, 1.0), "root", (0.1, 0.13, 0.18), mat="shiny", k=0.0))
    ch.add(ellipsoid((0, 1.62, -0.28), (0.72, 0.2, 0.84), "root", paint, k=0.06))
    for x in (-1, 1):
        for (zb, zt) in ((0.62, 0.32), (-1.15, -0.95)):
            ch.add(capsule((x * 0.7, 1.08, zb), (x * 0.6, 1.62, zt), 0.05, "root", paint, k=0.03))
        ch.add(capsule((x * 0.8, 1.08, 0.66), (x * 0.8, 1.08, -1.18), 0.06, "root", paint, k=0.05))
    # Big round headlights with chrome rings, little tail lights, grin of a grille.
    for x in (-1, 1):
        c = np.array([x * 0.5, 0.86, 1.62])
        ch.add(cylinder(c - [0, 0, 0.12], c + [0, 0, 0.06], 0.2, "root", (0.8, 0.8, 0.82), rounding=0.05, mat="metal", k=0.02))
        ch.add(sphere(c + [0, 0, 0.04], 0.16, "root", (1.0, 0.95, 0.75), mat="shiny", k=0.0))
        ch.add(ellipsoid((x * 0.58, 0.95, -1.66), (0.14, 0.1, 0.05), "root", (0.8, 0.1, 0.08), mat="shiny", k=0.0))
    ch.add(box((0, 0.6, 1.68), (0.34, 0.1, 0.06), "root", dark, r=0.08, mat="cloth", k=0.0))
    for k in range(5):
        ch.add(box((-0.26 + k * 0.13, 0.6, 1.73), (0.025, 0.08, 0.02), "root", (0.75, 0.75, 0.78), r=0.01, mat="metal", k=0.0))
    # Chunky chrome bumpers.
    for z, sgn in ((1.74, 1), (-1.72, -1)):
        ch.add(capsule((-0.82, 0.42, z), (0.82, 0.42, z), 0.12, "root", (0.82, 0.83, 0.86), mat="metal", k=0.0))
    # Fat tyres with deep hubcaps.
    for z in (1.02, -1.02):
        for x in (-1, 1):
            c = np.array([x * 0.74, 0.46, z])
            ch.add(torus(c, 0.3, 0.17, "root", dark, rot=(0, 0, math.pi / 2), mat="cloth", k=0.0))
            ch.add(cylinder(c - [0.14, 0, 0], c + [0.14, 0, 0], 0.32, "root", dark, rounding=0.08, mat="cloth", k=0.0))
            ch.add(ellipsoid(c + [x * 0.13, 0, 0], (0.06, 0.22, 0.22), "root", (0.88, 0.88, 0.9), mat="metal", k=0.0))
    # Side mirrors.
    for x in (-1, 1):
        ch.add(ellipsoid((x * 0.95, 1.12, 0.55), (0.12, 0.08, 0.06), "root", paint, k=0.02))
    return ch


BUILDERS = {"car_sedan": car_sedan, "car_toon": car_toon}

if __name__ == "__main__":
    for name, fn in BUILDERS.items():
        if ONLY and name not in ONLY:
            continue
        fn().build(os.path.join(OUT, name + ".glb"))
