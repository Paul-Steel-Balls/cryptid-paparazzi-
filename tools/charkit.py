"""charkit: sculpt cartoon characters from blended SDF "clay", rig them, animate them,
and write skinned, animated glTF (.glb) files for Godot.

Model in metres, Y up, character faces +Z (glTF convention), feet at y = 0.
Every Part belongs to a bone; skin weights come from how close each surface point is
to each part, so a sculpt is rigged the moment it exists.
"""
import json, math, struct
import numpy as np
from skimage.measure import marching_cubes

# ------------------------------------------------------------------ math helpers
def v3(*a): return np.array(a if len(a) == 3 else a[0], dtype=np.float64)
def rot_euler(x=0.0, y=0.0, z=0.0):
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rz @ ry @ rx
def quat_from_euler(x, y, z):
    m = rot_euler(x, y, z)
    t = m.trace()
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return np.array([(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s])
    i = int(np.argmax([m[0, 0], m[1, 1], m[2, 2]]))
    if i == 0:
        s = math.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return np.array([0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s])
    if i == 1:
        s = math.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return np.array([(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s])
    s = math.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return np.array([(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s])

# ------------------------------------------------------------------ noise
def _hash(ix, iy, iz, seed):
    h = np.sin(ix * 127.1 + iy * 311.7 + iz * 74.7 + seed * 19.19) * 43758.5453
    return (h - np.floor(h)) * 2.0 - 1.0
def vnoise(p, freq=10.0, seed=0.0):
    q = p * freq
    i = np.floor(q); f = q - i
    u = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out
def fbm(p, freq=8.0, octaves=3, seed=0.0):
    a, s, tot = 1.0, 0.0, 0.0
    for o in range(octaves):
        s = s + a * vnoise(p, freq * 2 ** o, seed + o * 7.3); tot += a; a *= 0.5
    return s / tot

# ------------------------------------------------------------------ SDF primitives (points: (N,3))
def sd_sphere(p, c, r): return np.linalg.norm(p - c, axis=1) - r
def sd_ellipsoid(p, c, radii, R=None):
    q = p - c
    if R is not None: q = q @ R  # into local frame
    k0 = np.linalg.norm(q / radii, axis=1)
    k1 = np.linalg.norm(q / (radii * radii), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
def sd_capsule(p, a, b, ra, rb=None):
    """Round cone between a (radius ra) and b (radius rb)."""
    rb = ra if rb is None else rb
    ba = b - a; l2 = ba @ ba
    pa = p - a
    if abs(ra - rb) < 1e-6:
        h = np.clip((pa @ ba) / l2, 0, 1)
        return np.linalg.norm(pa - np.outer(h, ba), axis=1) - ra
    # exact round cone (iq)
    rr = ra - rb; a2 = l2 - rr * rr; il2 = 1.0 / l2
    y = pa @ ba; z = y - l2
    xv = pa * l2 - np.outer(y, ba)
    x2 = np.einsum('ij,ij->i', xv, xv)
    y2 = y * y * l2; z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - rb,
        np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - ra,
                 (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - ra))
    return d
def sd_box(p, c, half, r=0.0, R=None):
    q = p - c
    if R is not None: q = q @ R
    q = np.abs(q) - (half - r)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(np.max(q, axis=1), 0) - r
def sd_torus(p, c, R_major, r_minor, R=None):
    q = p - c
    if R is not None: q = q @ R
    qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - R_major
    return np.sqrt(qx ** 2 + q[:, 1] ** 2) - r_minor
def sd_cylinder(p, a, b, r, rounding=0.0):
    ba = b - a; pa = p - a
    baba = ba @ ba; paba = pa @ ba
    x = np.linalg.norm(pa * baba - np.outer(paba, ba), axis=1) - r * baba
    y = np.abs(paba - baba * 0.5) - baba * 0.5
    x2, y2 = x * x, y * y * baba
    d = np.where(np.maximum(x, y) < 0, -np.minimum(x2, y2), (np.where(x > 0, x2, 0) + np.where(y > 0, y2, 0)))
    return np.sign(d) * np.sqrt(np.abs(d)) / baba - rounding

def smin(a, b, k):
    if k <= 0: return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)
def smax(a, b, k):
    return -smin(-a, -b, k)

# ------------------------------------------------------------------ parts
class Part:
    def __init__(self, fn, bone, color, k=0.03, mat="body", sub=False, noise=None, sharp=0.004, bounds=None):
        self.fn = fn; self.bone = bone; self.color = color; self.k = k; self.mat = mat
        self.sub = sub; self.noise = noise; self.sharp = sharp; self.bounds = bounds
    def dist(self, p):
        d = self.fn(p)
        if self.noise:
            amp, freq = self.noise[:2]
            d = d + amp * fbm(p, freq, 2, self.noise[2] if len(self.noise) > 2 else 1.0)
        return d
    def col(self, p):
        c = self.color
        if callable(c): return np.asarray(c(p), dtype=np.float64)
        return np.tile(np.asarray(c, dtype=np.float64), (len(p), 1))

def _pad(bounds, m=0.08):
    lo, hi = bounds
    return np.asarray(lo) - m, np.asarray(hi) + m

def sphere(c, r, bone, color, **kw):
    c = v3(c); return Part(lambda p: sd_sphere(p, c, r), bone, color, bounds=_pad((c - r, c + r)), **kw)
def ellipsoid(c, radii, bone, color, rot=(0, 0, 0), **kw):
    c = v3(c); radii = v3(radii); R = rot_euler(*rot) if any(rot) else None
    m = radii.max()
    return Part(lambda p: sd_ellipsoid(p, c, radii, R), bone, color, bounds=_pad((c - m, c + m)), **kw)
def capsule(a, b, ra, bone, color, rb=None, **kw):
    a = v3(a); b = v3(b); rr = max(ra, rb or ra)
    return Part(lambda p: sd_capsule(p, a, b, ra, rb), bone, color, bounds=_pad((np.minimum(a, b) - rr, np.maximum(a, b) + rr)), **kw)
def box(c, half, bone, color, r=0.01, rot=(0, 0, 0), **kw):
    c = v3(c); half = v3(half); R = rot_euler(*rot) if any(rot) else None
    m = np.linalg.norm(half)
    return Part(lambda p: sd_box(p, c, half, r, R), bone, color, bounds=_pad((c - m, c + m)), **kw)
def torus(c, R_major, r_minor, bone, color, rot=(0, 0, 0), **kw):
    c = v3(c); R = rot_euler(*rot) if any(rot) else None
    m = R_major + r_minor
    return Part(lambda p: sd_torus(p, c, R_major, r_minor, R), bone, color, bounds=_pad((c - m, c + m)), **kw)
def cylinder(a, b, r, bone, color, rounding=0.004, **kw):
    a = v3(a); b = v3(b)
    return Part(lambda p: sd_cylinder(p, a, b, r - rounding, rounding), bone, color,
                bounds=_pad((np.minimum(a, b) - r, np.maximum(a, b) + r)), **kw)
def mirror(fn_builder):
    """Call fn_builder(side) for side in (-1, +1) (x = left/right) and return both parts."""
    return [fn_builder(s) for s in (-1.0, 1.0)]

# ------------------------------------------------------------------ colour helpers
def fur(base, var=0.12, freq=22.0, seed=0.0):
    base = np.asarray(base)
    def f(p):
        n = fbm(p, freq, 3, seed)[:, None]
        streak = vnoise(p * np.array([3.0, 0.6, 3.0]), freq * 1.5, seed + 3)[:, None]
        return np.clip(base * (1.0 + var * n + var * 0.6 * streak), 0, 1)
    return f
def speckle(base, var=0.06, freq=30.0, seed=0.0):
    base = np.asarray(base)
    return lambda p: np.clip(base * (1.0 + var * vnoise(p, freq, seed)[:, None]), 0, 1)
def stripes(c1, c2, axis=1, period=0.08, phase=0.0):
    c1, c2 = np.asarray(c1), np.asarray(c2)
    def f(p):
        s = (np.sin((p[:, axis] + phase) / period * math.pi) > 0)[:, None]
        return np.where(s, c1, c2)
    return f
def plaid(c1, c2, c3, period=0.09):
    c1, c2, c3 = map(np.asarray, (c1, c2, c3))
    def f(p):
        a = (np.sin(p[:, 0] / period * math.pi) > 0.3)
        b = (np.sin(p[:, 1] / period * math.pi) > 0.3)
        out = np.where((a & b)[:, None], c3, np.where((a | b)[:, None], c2, c1))
        return out
    return f
def hawaiian(bg, flower, centre, leaf, scale=0.11, seed=0.0):
    bg, flower, centre, leaf = map(np.asarray, (bg, flower, centre, leaf))
    def f(p):
        q = p / scale
        cell = np.floor(q)
        jitter = np.stack([_hash(cell[:, 0], cell[:, 1], cell[:, 2], seed + k) * 0.3 for k in range(3)], 1)
        local = q - cell - 0.5 - jitter
        r = np.linalg.norm(local, axis=1)
        ang = np.arctan2(local[:, 1], local[:, 0] + local[:, 2] * 0.5)
        petal = 0.32 + 0.1 * np.cos(5 * ang)
        out = np.tile(bg, (len(p), 1)).astype(float)
        leafmask = (np.abs(local[:, 0] - local[:, 1]) < 0.12) & (r > 0.25) & (r < 0.48)
        out[leafmask] = leaf
        out[r < petal] = flower
        out[r < 0.09] = centre
        return out
    return f

# ------------------------------------------------------------------ skeleton + animation
class Skeleton:
    def __init__(self):
        self.names, self.parents, self.heads = [], [], []
    def add(self, name, parent, head):
        self.names.append(name); self.parents.append(None if parent is None else self.names.index(parent))
        self.heads.append(v3(head)); return name
    def idx(self, name): return self.names.index(name)

def humanoid(s, hips_y, shoulder_w, shoulder_y, neck_y, hip_w, knee_y, ankle_y, elbow_drop=0.28, wrist_drop=0.26,
             arm_out=0.0, head_y=None):
    """Standard biped bones. Arms hang down slightly outwards."""
    s.add("root", None, (0, 0, 0))
    s.add("hips", "root", (0, hips_y, 0))
    s.add("spine", "hips", (0, (hips_y + shoulder_y) * 0.5, 0))
    s.add("chest", "spine", (0, shoulder_y - 0.08, 0))
    s.add("neck", "chest", (0, neck_y, 0))
    s.add("head", "neck", (0, head_y if head_y else neck_y + 0.08, 0))
    for side, sx in (("l", -1), ("r", 1)):
        sh = v3(sx * shoulder_w, shoulder_y, 0)
        s.add(f"shoulder_{side}", "chest", sh)
        el = sh + v3(sx * (0.04 + arm_out), -elbow_drop, 0)
        s.add(f"elbow_{side}", f"shoulder_{side}", el)
        s.add(f"hand_{side}", f"elbow_{side}", el + v3(sx * arm_out * 0.5, -wrist_drop, 0.02))
        s.add(f"hip_{side}", "hips", (sx * hip_w, hips_y - 0.04, 0))
        s.add(f"knee_{side}", f"hip_{side}", (sx * hip_w, knee_y, 0.02))
        s.add(f"foot_{side}", f"knee_{side}", (sx * hip_w, ankle_y, 0))
    return s

def walk_cycle(stride=0.5, arm=0.45, bob=0.03, speed=1.0, lean=0.05, knee=0.7, twist=0.08, sway=0.04, lag=0.35):
    """Biped walk. Conventions (model faces +Z): negative X rotation swings a limb forward;
    positive knee X rotation bends the shin back. Each leg: forward swing (knee folds, foot
    clears the ground) -> heel strike (toes up, knee nearly straight) -> stance (small knee
    absorb, body passes over) -> toe-off (heel up). Pelvis dips at contact, rises at passing,
    rolls toward the planted leg; chest counter-rotates; arms swing opposite with lag."""
    def leg(ph):
        s, c = math.sin(ph), math.cos(ph)
        hip = -stride * s                                # +: back, -: forward
        swing = max(0.0, c)                              # leg travelling forward
        absorb = max(0.0, s) * max(0.0, -c)              # just after heel strike
        kn = knee * swing ** 1.3 + 0.22 * knee * absorb + 0.05
        ft = -0.55 * stride * s * (1.0 - swing) - 0.25 * swing * knee * 0.6
        return hip, kn, ft
    def f(t):
        ph = t * 2 * math.pi * speed
        hl, kl, fl = leg(ph)
        hr, kr, fr = leg(ph + math.pi)
        s = math.sin(ph)
        sa = math.sin(ph - lag)                          # arms trail the legs a touch
        return {
            "hip_l": (hl, 0, 0), "hip_r": (hr, 0, 0),
            "knee_l": (kl, 0, 0), "knee_r": (kr, 0, 0),
            "foot_l": (fl, 0, 0), "foot_r": (fr, 0, 0),
            "shoulder_l": (arm * sa, 0, -0.04), "shoulder_r": (-arm * sa, 0, 0.04),
            "elbow_l": (-0.2 - 0.45 * arm * max(0.0, -sa), 0, 0), "elbow_r": (-0.2 - 0.45 * arm * max(0.0, sa), 0, 0),
            "hips": (0, twist * s, sway * math.cos(ph)),
            "spine": (lean, -twist * s * 0.5, -sway * 0.6 * math.cos(ph)),
            "chest": (0, -twist * s * 0.7, 0),
            "head": (-lean * 0.6, twist * s * 0.3, sway * 0.3 * math.cos(ph)),
            "_hips_offset": (0, bob * (abs(math.cos(ph)) - 0.5), 0),
        }
    return f
def idle_cycle(breathe=0.03, sway=0.03, speed=1.0, arm_hang=0.05):
    def f(t):
        ph = t * 2 * math.pi * speed
        return {"chest": (breathe * math.sin(ph), 0, 0), "spine": (0, 0, sway * math.sin(ph * 0.5)),
                "head": (0.03 * math.sin(ph * 0.5 + 1.0), 0.08 * math.sin(ph * 0.25), 0),
                "shoulder_l": (0, 0, -arm_hang - 0.03 * math.sin(ph)), "shoulder_r": (0, 0, arm_hang + 0.03 * math.sin(ph)),
                "_hips_offset": (0, 0.006 * math.sin(ph), 0)}
    return f

def merge(*fs):
    def f(t):
        out = {}
        for g in fs:
            for k, v in g(t).items():
                if k in out:
                    out[k] = tuple(a + b for a, b in zip(out[k], v))
                else:
                    out[k] = v
        return out
    return f
def override(base, extra):
    def f(t):
        out = dict(base(t)); out.update(extra(t)); return out
    return f

# ------------------------------------------------------------------ mesh building
MATERIALS = {
    "body": dict(rough=0.85, metal=0.0, emissive=None),
    "shiny": dict(rough=0.25, metal=0.0, emissive=None),
    "metal": dict(rough=0.3, metal=0.8, emissive=None),
    "wing": dict(rough=0.9, metal=0.0, emissive=None),
    "paper": dict(rough=0.9, metal=0.0, emissive=None),
    "cloth": dict(rough=0.95, metal=0.0, emissive=None),
    "corn": dict(rough=0.35, metal=0.0, emissive=None),
    "leaf": dict(rough=0.8, metal=0.0, emissive=None),
}
GROUP_VOXEL = {"wing": 0.0105, "paper": 0.006, "corn": 0.0045, "leaf": 0.006}
def glow_mat(rgb): return dict(rough=0.4, metal=0.0, emissive=list(rgb))

def build_group(parts, voxel):
    adds = [p for p in parts if not p.sub]
    subs = [p for p in parts if p.sub]
    lo = np.min([p.bounds[0] for p in adds], axis=0); hi = np.max([p.bounds[1] for p in adds], axis=0)
    dims = np.ceil((hi - lo) / voxel).astype(int) + 1
    xs = [lo[i] + np.arange(dims[i]) * voxel for i in range(3)]
    grid = np.stack(np.meshgrid(*xs, indexing="ij"), -1).reshape(-1, 3)
    field = np.full(len(grid), 1e3)
    # Only evaluate each part near its own bounds (big speed-up).
    for prt in adds:
        m = np.all((grid >= prt.bounds[0]) & (grid <= prt.bounds[1]), axis=1)
        if not m.any(): continue
        field[m] = smin(field[m], prt.dist(grid[m]), prt.k)
    for prt in subs:
        m = np.all((grid >= prt.bounds[0]) & (grid <= prt.bounds[1]), axis=1)
        if not m.any(): continue
        field[m] = smax(field[m], -prt.dist(grid[m]), prt.k)
    vol = field.reshape(dims)
    if vol.min() > 0: return None
    verts, faces, normals, _ = marching_cubes(vol, 0.0, spacing=(voxel, voxel, voxel))
    verts = verts + lo
    # skimage's normals point towards lower field values: for an SDF that's inward.
    normals = -normals
    # Wind faces CCW seen from outside (glTF front faces) to agree with the normals.
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    if np.mean(np.einsum("ij,ij->i", fn, normals[faces[:, 0]])) < 0:
        faces = faces[:, ::-1]
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    return verts, faces.astype(np.uint32), normals, adds

def colours_and_weights(verts, adds, skel, skin_soft=0.012):
    d = np.stack([p.dist(verts) for p in adds], 1)  # (N, P)
    dmin = d.min(1, keepdims=True)
    sharp = np.array([p.sharp for p in adds])[None, :]
    wc = np.exp(-(d - dmin) / sharp); wc /= wc.sum(1, keepdims=True)
    col = np.zeros((len(verts), 3))
    for i, p in enumerate(adds):
        sel = wc[:, i] > 1e-4
        if sel.any():
            col[sel] += wc[sel, i:i + 1] * p.col(verts[sel])
    # skin weights per bone
    ws = np.exp(-(d - dmin) / skin_soft)
    nb = len(skel.names)
    bw = np.zeros((len(verts), nb))
    for i, p in enumerate(adds):
        bw[:, skel.idx(p.bone)] += ws[:, i]
    if nb < 4:  # glTF needs exactly 4 joints per vertex
        bw = np.hstack([bw, np.zeros((len(verts), 4 - nb))])
    order = np.argsort(-bw, axis=1)[:, :4]
    order = np.minimum(order, nb - 1)
    top = np.take_along_axis(bw, order, 1)
    top = np.where(top < top[:, :1] * 0.08, 0, top)
    top /= top.sum(1, keepdims=True)
    return np.clip(col, 0, 1), order.astype(np.uint16), top.astype(np.float32)

# ------------------------------------------------------------------ glTF writer
class GLB:
    def __init__(self):
        self.bin = bytearray(); self.j = {"asset": {"version": "2.0", "generator": "charkit"}, "buffers": [],
                                           "bufferViews": [], "accessors": [], "meshes": [], "nodes": [],
                                           "materials": [], "skins": [], "animations": [], "scenes": [], "scene": 0}
    def _view(self, data, target=None):
        while len(self.bin) % 4: self.bin.append(0)
        off = len(self.bin); self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target: v["target"] = target
        self.j["bufferViews"].append(v); return len(self.j["bufferViews"]) - 1
    def acc(self, arr, ctype, atype, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        view = self._view(arr.tobytes(), target)
        a = {"bufferView": view, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if normalized: a["normalized"] = True
        if minmax:
            a["min"] = arr.min(0).tolist() if arr.ndim > 1 else [float(arr.min())]
            a["max"] = arr.max(0).tolist() if arr.ndim > 1 else [float(arr.max())]
        self.j["accessors"].append(a); return len(self.j["accessors"]) - 1
    def save(self, path):
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4: js += b" "
        while len(self.bin) % 4: self.bin.append(0)
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942)); f.write(self.bin)

F32, U16, U32 = 5126, 5123, 5125

class Character:
    def __init__(self, name, skel, voxel=0.018):
        self.name = name; self.skel = skel; self.voxel = voxel
        self.parts = []; self.anims = {}; self.mats = dict(MATERIALS)
    def add(self, *parts):
        for p in parts:
            if isinstance(p, (list, tuple)): self.add(*p)
            else: self.parts.append(p)
    def glow(self, name, rgb):
        self.mats[name] = glow_mat(rgb); return name
    def anim(self, name, duration, fn, fps=30): self.anims[name] = (duration, fn, fps)

    def ground_speeds(self):
        """For each animation, how fast the planted foot slides backward at playback speed 1.
        The game plays locomotion at (actual speed / this) so feet stick to the ground."""
        skel = self.skel
        feet = [i for i, n in enumerate(skel.names) if n.startswith("foot_") or n.startswith("hoof_")]
        out = {}
        if not feet:
            return out
        for aname, (dur, fn, fps) in self.anims.items():
            n = max(8, int(dur * 60))
            ts = np.linspace(0, dur, n, endpoint=False)
            prev = None; speeds = []
            for t in ts:
                pose = fn(float(t))
                _, Pw = fk(skel, pose)
                off = np.array(pose.get("_hips_offset", (0, 0, 0)))
                pts = np.array([Pw[i] + off for i in feet])
                low = int(np.argmin(pts[:, 1]))
                if prev is not None and prev[0] == low:
                    speeds.append(-(pts[low, 2] - prev[1]) / (dur / n))
                prev = (low, pts[low, 2])
            sp = np.array(speeds)
            sp = sp[sp > 0.05]
            out[aname] = round(float(np.median(sp)), 3) if len(sp) > n // 6 else 0.0
        return out

    def build(self, path, verbose=True):
        g = GLB(); skel = self.skel
        # materials
        mat_ids = {}
        groups = {}
        for p in self.parts: groups.setdefault(p.mat, []).append(p)
        prims = []
        tri_total = 0
        for mname, parts in groups.items():
            vox = getattr(self, "group_voxel", {}).get(mname, GROUP_VOXEL.get(mname, self.voxel if mname in ("body",) else min(self.voxel, 0.012)))
            res = build_group(parts, vox)
            if res is None: continue
            verts, faces, normals, adds = res
            col, joints, weights = colours_and_weights(verts, adds, skel)
            m = self.mats[mname]
            if mname not in mat_ids:
                md = {"name": mname, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": m["metal"],
                                                               "roughnessFactor": m["rough"]}}
                if m["emissive"]: md["emissiveFactor"] = m["emissive"]
                g.j["materials"].append(md); mat_ids[mname] = len(g.j["materials"]) - 1
            colors = np.hstack([col, np.ones((len(col), 1))]).astype(np.float32)
            prims.append({"attributes": {
                "POSITION": g.acc(verts.astype(np.float32), F32, "VEC3", 34962, minmax=True),
                "NORMAL": g.acc(normals.astype(np.float32), F32, "VEC3", 34962),
                "COLOR_0": g.acc(colors, F32, "VEC4", 34962),
                "JOINTS_0": g.acc(joints, U16, "VEC4", 34962),
                "WEIGHTS_0": g.acc(weights, F32, "VEC4", 34962)},
                "indices": g.acc(faces.reshape(-1), U32, "SCALAR", 34963), "material": mat_ids[mname]})
            tri_total += len(faces)
        g.j["meshes"].append({"name": self.name, "primitives": prims})
        # joint nodes (bind rotation identity; translation relative to parent)
        joint_nodes = []
        for i, nm in enumerate(skel.names):
            par = skel.parents[i]
            t = skel.heads[i] - (skel.heads[par] if par is not None else 0)
            g.j["nodes"].append({"name": nm, "translation": t.tolist()}); joint_nodes.append(len(g.j["nodes"]) - 1)
        for i, par in enumerate(skel.parents):
            if par is not None:
                g.j["nodes"][joint_nodes[par]].setdefault("children", []).append(joint_nodes[i])
        ibm = np.zeros((len(skel.names), 16), np.float32)
        for i, h in enumerate(skel.heads):
            m = np.eye(4); m[:3, 3] = -h
            ibm[i] = m.T.reshape(-1)  # column-major
        skin = {"joints": joint_nodes, "inverseBindMatrices": g.acc(ibm, F32, "MAT4"), "skeleton": joint_nodes[0]}
        g.j["skins"].append(skin)
        g.j["nodes"].append({"name": self.name + "_mesh", "mesh": 0, "skin": 0}); mesh_node = len(g.j["nodes"]) - 1
        g.j["nodes"].append({"name": self.name, "children": [joint_nodes[0], mesh_node]}); top = len(g.j["nodes"]) - 1
        g.j["scenes"].append({"nodes": [top]})
        # animations
        for aname, (dur, fn, fps) in self.anims.items():
            n = max(2, int(round(dur * fps)) + 1)
            times = np.linspace(0, dur, n).astype(np.float32)
            frames = [fn(float(t) % dur if t < dur else 0.0) for t in times]  # last == first: seamless loop
            tacc = g.acc(times, F32, "SCALAR", minmax=True)
            samplers, channels = [], []
            used = set(k for fr in frames for k in fr.keys())
            for jn in skel.names:
                if jn not in used and not (jn == "hips" and "_hips_offset" in used): continue
                if jn in used:
                    q = np.array([quat_from_euler(*fr.get(jn, (0, 0, 0))) for fr in frames], np.float32)
                    # keep quaternion signs continuous
                    for i in range(1, len(q)):
                        if np.dot(q[i], q[i - 1]) < 0: q[i] = -q[i]
                    samplers.append({"input": tacc, "output": g.acc(q, F32, "VEC4"), "interpolation": "LINEAR"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": joint_nodes[skel.idx(jn)], "path": "rotation"}})
            if "_hips_offset" in used:
                hi = skel.idx("hips"); base = skel.heads[hi] - skel.heads[skel.parents[hi]]
                tr = np.array([base + np.array(fr.get("_hips_offset", (0, 0, 0))) for fr in frames], np.float32)
                samplers.append({"input": tacc, "output": g.acc(tr, F32, "VEC3"), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": joint_nodes[hi], "path": "translation"}})
            g.j["animations"].append({"name": aname, "samplers": samplers, "channels": channels})
        if not g.j["animations"]: del g.j["animations"]
        g.save(path)
        gs = self.ground_speeds()
        with open(path.replace(".glb", ".anim.json"), "w") as jf:
            json.dump({"ground_speed": gs}, jf, indent=1)
        if verbose: print(f"{self.name}: {tri_total} tris, {len(skel.names)} bones, anims {list(self.anims)}, ground speeds {gs} -> {path}")
        return tri_total

# ------------------------------------------------------------------ arm IK (for prop-holding poses)
def solve_arm(skel, side, target, hand_offset=(0, -0.05, 0), elbow_y_range=1.2):
    """Shoulder (x,y,z) + elbow (x,y) euler angles that put the hand centre on target."""
    from scipy.optimize import minimize
    S = skel.heads[skel.idx(f"shoulder_{side}")]; E = skel.heads[skel.idx(f"elbow_{side}")]; H = skel.heads[skel.idx(f"hand_{side}")]
    off = np.asarray(hand_offset, float); target = np.asarray(target, float)
    def hand_pos(x):
        Rs = rot_euler(x[0], x[1], x[2]); Re = rot_euler(x[3], x[4], 0)
        return S + Rs @ (E - S) + Rs @ Re @ (H - E + off)
    def cost(x):
        return np.sum((hand_pos(x) - target) ** 2) + 0.002 * np.sum(x ** 2) + 0.05 * max(0, x[3]) ** 2
    best = None
    for x0 in ([-0.6, 0, 0, -1.0, 0], [-1.0, 0.3, 0.3, -1.4, 0.5], [-0.3, -0.3, -0.3, -0.8, -0.5], [-1.4, 0, 0, -0.3, 0]):
        r = minimize(cost, np.array(x0, float), method="Nelder-Mead", options={"maxiter": 4000, "xatol": 1e-4, "fatol": 1e-8})
        if best is None or r.fun < best.fun: best = r
    x = best.x
    err = np.linalg.norm(hand_pos(x) - target)
    return {f"shoulder_{side}": (x[0], x[1], x[2]), f"elbow_{side}": (x[3], x[4], 0.0)}, err

# ------------------------------------------------------------------ posed props
def fk(skel, pose):
    """World rotation and position of every bone for a pose (dict bone -> euler)."""
    n = len(skel.names); Rw = [None] * n; Pw = [None] * n
    for i in range(n):
        R = rot_euler(*pose.get(skel.names[i], (0, 0, 0)))
        par = skel.parents[i]
        if par is None:
            Rw[i] = R; Pw[i] = skel.heads[i].copy()
        else:
            Pw[i] = Pw[par] + Rw[par] @ (skel.heads[i] - skel.heads[par]); Rw[i] = Rw[par] @ R
    return Rw, Pw

def attach(parts, skel, pose, bone):
    """Parts modelled where they should appear in `pose` are moved into bind space
    so that skinning to `bone` puts them back exactly there."""
    Rw, Pw = fk(skel, pose); b = skel.idx(bone)
    R, P, h = Rw[b], Pw[b], skel.heads[b]
    to_posed = lambda p: (p - h) @ R.T + P
    out = []
    for prt in parts:
        fn, col = prt.fn, prt.color
        prt.fn = (lambda f: (lambda p: f(to_posed(p))))(fn)
        if callable(col): prt.color = (lambda c: (lambda p: c(to_posed(p))))(col)
        lo, hi = prt.bounds
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        cb = (corners - P) @ R + h
        prt.bounds = (cb.min(0), cb.max(0)); prt.bone = bone
        out.append(prt)
    return out
