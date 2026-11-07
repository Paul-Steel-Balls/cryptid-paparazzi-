#!/usr/bin/env python3
"""Synthesize every sound and music track for Cryptid Paparazzi from scratch.
Usage: python3 tools/make_audio.py <out_dir>
All audio is original (procedural), so there are no licensing questions."""
import os, subprocess, sys, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)
OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ helpers
def t_(dur): return np.arange(int(dur * SR)) / SR
def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.1):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    sus = max(0, n - a - d - r)
    e = np.concatenate([np.linspace(0, 1, a, False), np.linspace(1, s, d, False), np.full(sus, s), np.linspace(s, 0, r)])
    return np.pad(e, (0, max(0, n - len(e))))[:n]
def exp_dec(n, tau): return np.exp(-np.arange(n) / (tau * SR))
def noise(n): return rng.standard_normal(n)
def bp(x, lo, hi, order=2): return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)
def lp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, "lowpass", fs=SR, output="sos"), x)
def hp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x)
def osc(freq, kind="sine", phase0=0.0):
    """freq: array of instantaneous Hz."""
    ph = phase0 + 2 * np.pi * np.cumsum(freq) / SR
    if kind == "sine": return np.sin(ph)
    if kind == "saw": return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if kind == "square": return np.sign(np.sin(ph))
    if kind == "tri": return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
def note(name):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + (octave - 4) * 12) / 12)
def mix_at(buf, x, start):
    i = int(start * SR)
    end = min(len(buf), i + len(x))
    if i < len(buf): buf[i:end] += x[: end - i]
def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak
def fade(x, fin=0.002, fout=0.01):
    n = len(x); a, b = int(fin * SR), int(fout * SR)
    x = x.copy()
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x
def save_wav(name, x, peak=0.8):
    x = norm(x, peak) if name.endswith("_hum") else fade(norm(x, peak))   # loops: no fades at the seam
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
def save_ogg(name, x, peak=0.85, stereo=None):
    x = norm(x, peak)
    data = x if stereo is None else np.stack([x * (1 - stereo) + stereo * np.roll(x, 331), x * (1 - stereo) + stereo * np.roll(x, 517)], axis=1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (data * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f.name, "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(f.name)
def formant(x, formants, q=6.0):
    y = np.zeros_like(x)
    for f, g in formants:
        y += g * bp(x, f * (1 - 1 / q), f * (1 + 1 / q))
    return y
def reverb(x, wet=0.25, length=1.6, seed=1):
    r = np.random.default_rng(seed)
    n = int(length * SR)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / (length * SR / 6))
    ir = lp(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    y = signal.fftconvolve(x, ir)
    out = np.pad(x, (0, len(y) - len(x))) + wet * y
    return out
def loopify(x, loop_len):
    """Fold the tail past loop_len back onto the start: seamless loop with reverb tails."""
    n = int(loop_len * SR)
    out = x[:n].copy()
    tail = x[n:]
    out[: len(tail)] += tail[:n]
    return out

# ------------------------------------------------------------------ SFX v2
# Building blocks: granular crackle, resonators, formant voice, modal metal.

def grains(dur, rate_env, lo, hi, seed, amp_env=None, decay=(0.0003, 0.0015), loud=1.6):
    """Granular crackle: many tiny damped sinusoid 'ticks'. rate_env(t)->grains/sec."""
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    out = np.zeros(n + int(0.01 * SR))
    # Non-homogeneous Poisson process via thinning (no stray late grains).
    rmax = max(max(rate_env(x) for x in np.linspace(0, dur, 200)), 1e-3)
    tt = 0.0
    while True:
        tt += r.exponential(1.0 / rmax)
        if tt >= dur:
            break
        if r.random() > rate_env(tt) / rmax:
            continue
        f = r.uniform(lo, hi)
        d = r.uniform(*decay)
        m = int(d * 6 * SR) + 2
        k = np.arange(m) / SR
        a = r.pareto(3.0) * 0.4 + 0.2
        a = min(a, loud)
        if amp_env is not None:
            a *= amp_env(tt)
        g = np.sin(2 * np.pi * f * k + r.uniform(0, 6.28)) * np.exp(-k / d) * a
        i = int(tt * SR)
        out[i:i + m] += g[: len(out) - i]
    return out[:n]

def env_exp(n, attack, tau):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / tau)

def thump(dur, f0, f1, tau, noise_lp=300, mix=0.5, seed=0):
    t = t_(dur)
    tone = osc(f1 + (f0 - f1) * np.exp(-t * 30)) * np.exp(-t / tau)
    nz = lp(np.random.default_rng(seed).standard_normal(len(t)), noise_lp) * np.exp(-t / (tau * 0.6))
    return tone + mix * nz / (np.max(np.abs(nz)) + 1e-9)

def resonator(x, f, bw):
    """Two-pole resonant bandpass (constant peak gain ~1)."""
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    a = [1, -2 * r * np.cos(th), r * r]
    b = [(1 - r * r) * 0.5, 0, -(1 - r * r) * 0.5]
    return signal.lfilter(b, a, x)

VOWELS = {"a": (730, 1090, 2440), "o": (570, 840, 2410), "u": (320, 870, 2240), "i": (290, 2290, 3010),
          "e": (530, 1840, 2480), "ae": (660, 1720, 2410), "uh": (520, 1190, 2390), "er": (490, 1350, 1690)}

def voice(dur, f0, vowels, breath=0.15, rough=0.0, jitter=0.01, shimmer=0.05, scale=1.0, seed=0, bw=(90, 110, 160)):
    """Formant synthesis. f0: callable(u in 0..1)->Hz. vowels: list of (u, vowel) keyframes.
    scale: formant scale (<1 bigger creature, >1 smaller)."""
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    u = np.arange(n) / n
    jit = 1 + jitter * lp(r.standard_normal(n), 40) * 6
    f = np.array([f0(x) for x in u[:: 64]])
    f = np.interp(np.arange(n), np.arange(0, n, 64)[: len(f)], f) * jit
    if rough > 0:  # subharmonic growl
        f = f * (1 + rough * 0.15 * np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR))
    ph = np.cumsum(f) / SR
    saw = 2 * (ph % 1.0) - 1
    glottal = lp(saw, 4000, 1) + 0.3 * lp(saw, 1200, 1)
    sh = 1 + shimmer * lp(r.standard_normal(n), 30) * 6
    src = glottal * sh + breath * hp(r.standard_normal(n), 800) * (0.5 + 0.5 * np.abs(np.sin(np.pi * ph)))
    if rough > 0:
        src = src + rough * 0.6 * bp(r.standard_normal(n), 100, 1800) * (0.5 + 0.5 * saw)
    # formant trajectory, processed in short blocks with filter state carried over
    keys_u = [k[0] for k in vowels]
    F = np.array([[np.interp(x, keys_u, [VOWELS[k[1]][i] for k in vowels]) for i in range(3)] for x in np.linspace(0, 1, n // 256 + 2)]) * scale
    out = np.zeros(n)
    for i, (fi, b) in enumerate(zip(range(3), bw)):
        y = np.zeros(n); zi = np.zeros(2)
        for blk in range(0, n, 256):
            seg = src[blk:blk + 256]
            ff = F[blk // 256, fi]
            rr = np.exp(-np.pi * b * scale / SR); th = 2 * np.pi * ff / SR
            a = [1, -2 * rr * np.cos(th), rr * rr]; bb = [(1 - rr * rr) * 0.5, 0, -(1 - rr * rr) * 0.5]
            y[blk:blk + 256], zi = signal.lfilter(bb, a, seg, zi=zi)
        out += y * (1.0, 0.7, 0.35)[i]
    return out

def vshape(n, a=0.03, r=0.12):
    return env_adsr(n, a, 0.05, 0.85, r)

# ---- footsteps (forest floor: heel thump + crunch + toe roll + grass swish)
def step_forest(seed, weight=1.0, swish=0.25):
    r = np.random.default_rng(seed)
    dur = 0.32
    n = int(dur * SR)
    out = np.zeros(n)
    th = thump(0.09, 160, 70, 0.025, 260, 0.6, seed) * 0.55 * weight
    out[: len(th)] += th
    heel = lambda t: 3200 * np.exp(-t / 0.016)
    out += grains(dur, heel, 900, 4200, seed, decay=(0.0002, 0.0012), loud=1.0) * 0.45 * weight
    toe_t = r.uniform(0.07, 0.1)
    toe = lambda t: 1800 * np.exp(-max(t - toe_t, 0) / 0.015) * (t > toe_t) + 1e-3
    out += grains(dur, toe, 1500, 6000, seed + 50, decay=(0.0002, 0.0009), loud=0.9) * 0.3
    leaves = lambda t: 700 * np.exp(-t / 0.035)
    out += grains(dur, leaves, 2500, 8000, seed + 99, decay=(0.0001, 0.0005), loud=0.8) * 0.25
    sw = bp(r.standard_normal(n), 1800, 7000) * env_exp(n, 0.012, 0.07) * swish
    out += sw * 0.6
    return lp(out, 9000)

def step_run(seed):
    """Running footfall: a hard, low heel slam, a forward dirt scuff/skid as the foot pushes off,
    dense twig crackle, and a jacket/pack rustle. Shorter and punchier than a walking step."""
    r = np.random.default_rng(seed)
    dur = 0.26
    n = int(dur * SR)
    out = np.zeros(n)
    th = thump(0.11, 120, 48, 0.035, 220, 0.9, seed) * 1.0
    out[: len(th)] += th
    slam = lambda t: 5200 * np.exp(-t / 0.01)
    out += grains(dur, slam, 600, 3200, seed, decay=(0.0003, 0.0016), loud=1.2) * 0.55
    # push-off scuff: a short noisy drag that rises then cuts
    sk0 = int(r.uniform(0.035, 0.05) * SR); skn = int(0.07 * SR)
    sk = bp(r.standard_normal(skn), 700, 3200) * np.sin(np.linspace(0, np.pi, skn)) ** 1.5
    out[sk0:sk0 + skn] += sk[: max(0, min(skn, n - sk0))] * 0.5
    crack = lambda t: 2600 * np.exp(-max(t - 0.03, 0) / 0.03) * (t > 0.02) + 1e-3
    out += grains(dur, crack, 2000, 7500, seed + 50, decay=(0.0001, 0.0006), loud=1.0) * 0.35
    rus = bp(r.standard_normal(n), 400, 2200) * env_exp(n, 0.02, 0.06) * 0.22   # pack/jacket bounce
    out += rus
    return lp(out, 8000)

def step_sneak(seed):
    r = np.random.default_rng(seed)
    n = int(0.38 * SR)
    out = bp(r.standard_normal(n), 1200, 4500) * env_exp(n, 0.05, 0.08) * 0.28
    out += grains(0.38, lambda t: 400 * np.exp(-((t - 0.08) / 0.05) ** 2) + 10, 1800, 6000, seed, decay=(0.0001, 0.0006)) * 0.25
    th = thump(0.06, 120, 60, 0.02, 200, 0.6, seed) * 0.12
    out[: len(th)] += th
    return out

def step_land():
    out = step_forest(77, weight=1.8, swish=0.4)
    th = thump(0.25, 120, 45, 0.07, 200, 0.8, 5)
    out[: len(th)] += th * 0.9
    return np.tanh(out * 1.2)

def wade(seed):
    r = np.random.default_rng(seed)
    n = int(0.45 * SR)
    slosh = bp(r.standard_normal(n), 300, 2500) * env_exp(n, 0.03, 0.12)
    out = slosh * 0.6
    for k in range(r.integers(4, 9)):  # bubbles
        d = r.uniform(0.01, 0.04); m = int(d * SR)
        f0 = r.uniform(350, 1100)
        b = np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f0 * 1.6, m)) / SR) * np.exp(-np.arange(m) / (d * SR / 3))
        mix_at(out, b * r.uniform(0.15, 0.4), r.uniform(0.02, 0.25))
    return out

def big_step(seed=3):
    r = np.random.default_rng(seed)
    n = int(0.55 * SR)
    out = np.zeros(n)
    th = thump(0.45, 90, 38, 0.11, 160, 1.0, seed)
    out[: len(th)] += th
    out += grains(0.55, lambda t: 1800 * np.exp(-t / 0.05), 500, 3500, seed, decay=(0.0004, 0.002), loud=1.0) * 0.55
    if r.random() < 0.7:  # a twig snaps under the weight
        tw = grains(0.03, lambda t: 9000, 1500, 5000, seed + 1, decay=(0.0002, 0.0008), loud=2.5)
        mix_at(out, tw * 0.9, r.uniform(0.03, 0.08))
    return np.tanh(out * 1.4)

def mid_step(seed=4):
    return step_forest(seed + 200, weight=1.2, swish=0.3)

def hoof(seed):
    r = np.random.default_rng(seed)
    n = int(0.3 * SR)
    out = np.zeros(n)
    for st, a in ((0.0, 1.0), (r.uniform(0.035, 0.05), 0.6)):
        k = t_(0.2)
        knock = np.sin(2 * np.pi * r.uniform(420, 520) * k) * np.exp(-k / 0.012) + 0.6 * np.sin(2 * np.pi * r.uniform(150, 190) * k) * np.exp(-k / 0.025)
        mix_at(out, knock * a, st)
    out = lp(out, 2500) + grains(0.3, lambda t: 1200 * np.exp(-t / 0.03), 1200, 5000, seed, decay=(0.0002, 0.0008)) * 0.3
    return out

def boing():
    t = t_(0.7)
    f = 170 + 110 * (1 - np.exp(-t * 18)) + 40 * np.sin(2 * np.pi * 17 * t) * np.exp(-t * 4)
    twang = (osc(f) + 0.35 * osc(f * 2.01) + 0.15 * osc(f * 3.03)) * np.exp(-t / 0.18)
    coil = bp(noise(len(t)), 2000, 6000) * np.exp(-t / 0.05) * 0.2
    th = np.zeros(len(t)); tk = thump(0.12, 140, 60, 0.03, 250, 0.6, 9); th[: len(tk)] = tk
    return twang * 0.7 + coil + th * 0.6

# ---- camera
def sfx_shutter():
    out = np.zeros(int(0.62 * SR))
    slap = thump(0.05, 220, 110, 0.012, 1200, 0.8, 1) * 0.6
    mix_at(out, slap, 0.0)
    for st, f in ((0.004, 3200), (0.012, 4200), (0.058, 2600)):
        m = int(0.005 * SR)
        c = bp(noise(m), f, f * 2.0) * np.exp(-np.arange(m) / (0.0012 * SR))
        mix_at(out, c * 1.1, st)
    k = t_(0.035)
    pop = np.sin(2 * np.pi * 6200 * k) * np.exp(-k / 0.004) * 0.25  # flash discharge tick
    mix_at(out, pop, 0.006)
    wt = t_(0.32)
    gear = osc(np.full(len(wt), 118), "saw") * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * wt))
    gear = bp(gear, 500, 3200) * env_adsr(len(wt), 0.02, 0.03, 0.9, 0.06) * 0.22
    mix_at(out, gear + grains(0.32, lambda t: 260, 2000, 5000, 7, decay=(0.0002, 0.0005)) * 0.12, 0.13)
    return out

def sfx_flash_charge():
    t = t_(1.5)
    f = 2400 + 6200 * (1 - np.exp(-t / 0.45))
    whine = (osc(f) + 0.25 * osc(f * 2)) * np.clip(t / 0.08, 0, 1) * np.exp(-np.maximum(t - 1.1, 0) / 0.12)
    return whine * (0.6 + 0.4 * np.exp(-t / 0.5))

def sfx_dry_click():
    out = np.zeros(int(0.18 * SR))
    for st, a in ((0.0, 1.0), (0.05, 0.55)):
        m = int(0.004 * SR)
        mix_at(out, bp(noise(m), 2000, 5000) * np.exp(-np.arange(m) / (0.001 * SR)) * a, st)
    return out

def sfx_reload():
    out = np.zeros(int(1.0 * SR))
    mix_at(out, thump(0.04, 900, 500, 0.008, 3000, 0.5, 2) * 0.5, 0.0)   # back door pops
    for k in range(3):  # thumb lever ratchet
        st = 0.25 + k * 0.17
        mix_at(out, grains(0.07, lambda t: 900 * np.exp(-t / 0.01), 2000, 6000, 10 + k, decay=(0.0002, 0.0007)) * 0.8, st)
        mix_at(out, bp(noise(int(0.06 * SR)), 800, 3000) * env_exp(int(0.06 * SR), 0.01, 0.02) * 0.25, st)
    mix_at(out, thump(0.05, 700, 400, 0.01, 2500, 0.6, 4) * 0.7, 0.85)  # door snaps shut
    return out

# ---- ui / economy
def sfx_ui_click():
    k = t_(0.06)
    return np.sin(2 * np.pi * 1900 * k) * np.exp(-k / 0.006) * 0.8 + bp(noise(len(k)), 3000, 8000) * np.exp(-k / 0.002) * 0.3

def bell(f, dur, decay=1.0):
    t = t_(dur)
    return sum(np.sin(2 * np.pi * f * m * t) * np.exp(-t * d / decay) * g for m, d, g in ((1, 2.2, 0.6), (2.76, 3.0, 0.35), (5.4, 5.0, 0.2), (8.9, 8.0, 0.1)))

def sfx_cash():
    out = np.zeros(int(1.6 * SR))
    for k in range(4):
        mix_at(out, grains(0.03, lambda t: 2000, 1500, 4000, 30 + k, decay=(0.0003, 0.001)) * 0.7, k * 0.045)
    m = int(0.25 * SR)
    mix_at(out, bp(noise(m), 300, 1500) * env_exp(m, 0.03, 0.08) * 0.35, 0.2)  # drawer
    mix_at(out, bell(2093, 1.3) * 0.8, 0.22)
    return out

def sfx_whoosh():
    n = int(0.4 * SR)
    x = noise(n); out = np.zeros(n)
    for i, seg in enumerate(np.array_split(np.arange(n), 20)):
        f = 350 + 2500 * np.sin(np.pi * i / 20)
        out[seg] = bp(x, f * 0.6, f * 1.5)[seg]
    return out * np.sin(np.pi * np.linspace(0, 1, n)) ** 2

def sfx_escaped():
    out = np.zeros(int(1.6 * SR))
    mix_at(out, bell(note("E5"), 1.2, 1.4) * 0.6, 0.0)
    mix_at(out, bell(note("A5"), 1.3, 1.4) * 0.6, 0.16)
    return reverb(out, 0.3, 1.2)

# ---- traps & bait
def modal(freqs, decays, gains, dur):
    t = t_(dur)
    return sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) * g for f, d, g in zip(freqs, decays, gains))

def sfx_trap_snap():
    out = np.zeros(int(1.2 * SR))
    mix_at(out, hp(noise(int(0.003 * SR)), 2500) * 2.0, 0.0)
    clang = modal([410, 1131, 2214, 3660, 5480], [0.35, 0.22, 0.14, 0.08, 0.05], [0.7, 0.5, 0.35, 0.25, 0.15], 1.1)
    mix_at(out, clang, 0.002)
    mix_at(out, thump(0.2, 140, 50, 0.05, 300, 0.7, 6) * 0.9, 0.0)
    mix_at(out, grains(0.35, lambda t: 300 * np.exp(-t / 0.12), 2500, 7000, 12, decay=(0.0005, 0.002)) * 0.4, 0.04)  # chain rattle
    return np.tanh(out * 1.3)

def sfx_trap_set():
    out = np.zeros(int(0.9 * SR))
    t = t_(0.35)  # spring creak: stick-slip metallic squeal
    creak = bp(osc(260 + 60 * np.sin(2 * np.pi * 3 * t), "saw") * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 31 * t))), 600, 3000)
    mix_at(out, creak * env_adsr(len(t), 0.05, 0.05, 0.7, 0.1) * 0.25, 0.0)
    st = 0.3
    for k in range(5):
        mix_at(out, modal([2400, 3900], [0.01, 0.007], [0.6, 0.3], 0.04) + hp(noise(int(0.04 * SR)), 2000) * np.exp(-np.arange(int(0.04 * SR)) / 60) * 0.4, st)
        st += 0.07 - k * 0.006
    mix_at(out, modal([900, 1700, 3100], [0.05, 0.03, 0.02], [0.6, 0.4, 0.2], 0.15), st + 0.06)  # latch
    return out

def sfx_bait_drop():
    n = int(0.45 * SR)
    out = thump(0.12, 180, 70, 0.03, 600, 1.0, 13)
    out = np.pad(out, (0, n - len(out)))
    sq = voice(0.3, lambda u: 140 - 60 * u, [(0, "u"), (1, "o")], breath=0.6, scale=1.4, seed=2) * env_exp(int(0.3 * SR), 0.01, 0.08)
    mix_at(out, sq * 0.7, 0.01)
    out += grains(0.45, lambda t: 800 * np.exp(-t / 0.04), 600, 3000, 14, decay=(0.0005, 0.002)) * 0.3
    return out

def sfx_munch():
    out = np.zeros(int(1.5 * SR))
    for k, st in enumerate((0.0, 0.33, 0.66, 1.0)):
        mix_at(out, grains(0.12, lambda t: 2500 * np.exp(-t / 0.03), 700, 3500, 40 + k, decay=(0.0004, 0.0015)) * 0.8, st)
        m = int(0.18 * SR)
        wet = voice(0.18, lambda u: 90, [(0, "o"), (1, "u")], breath=1.0, scale=0.9, seed=k) * env_exp(m, 0.01, 0.05)
        mix_at(out, wet * 0.5, st + 0.02)
    return out

def sfx_ouch():
    out = np.zeros(int(1.0 * SR))
    ow = voice(0.45, lambda u: 290 - 110 * u, [(0, "a"), (0.4, "a"), (1, "u")], breath=0.2, scale=1.05, seed=5) * vshape(int(0.45 * SR), 0.015, 0.12)
    mix_at(out, ow, 0.0)
    t = t_(0.5)
    bo = osc(220 * (1 + 0.2 * np.sin(2 * np.pi * 13 * t) * np.exp(-t * 4))) * np.exp(-t / 0.15) * 0.3
    mix_at(out, bo, 0.35)
    return out

# ---- wildlife
def sfx_owl():
    out = np.zeros(int(2.4 * SR))
    for st, d, a in ((0.0, 0.16, 0.7), (0.26, 0.12, 0.6), (0.42, 0.42, 1.0), (1.0, 0.22, 0.75), (1.32, 0.22, 0.7)):
        m = int(d * SR); k = np.arange(m) / SR
        f = 300 * (1 + 0.03 * np.sin(np.pi * k / d))
        h = osc(f) + 0.1 * osc(2 * f) + 0.05 * hp(noise(m), 600)
        mix_at(out, h * np.sin(np.pi * np.linspace(0, 1, m)) ** 0.8 * a, st)
    return reverb(lp(out, 1800), 0.5, 1.8)

def sfx_loon():
    v = voice(2.4, lambda u: 620 + 380 * np.sin(np.pi * min(u * 1.6, 1)) - 150 * u, [(0, "u"), (0.3, "o"), (1, "u")], breath=0.05, scale=1.7, seed=8, jitter=0.002)
    return reverb(v * vshape(len(v), 0.2, 0.6), 0.6, 2.5)

def frog_bull(seed):
    r = np.random.default_rng(seed)
    out = np.zeros(int(1.4 * SR))
    for k in range(r.integers(2, 4)):
        d = r.uniform(0.25, 0.4)
        v = voice(d, lambda u: 95 + 25 * np.sin(np.pi * u), [(0, "o"), (0.5, "u"), (1, "uh")], breath=0.1, rough=0.4, scale=0.55, seed=seed + k)
        mix_at(out, v * vshape(len(v), 0.03, 0.08), k * (d + 0.12))
    return out

def frog_green(seed):
    t = t_(0.25)
    f = 300 + 40 * np.random.default_rng(seed).random()
    return (osc(np.full(len(t), f)) + 0.6 * osc(np.full(len(t), f * 2.02)) + 0.3 * osc(np.full(len(t), f * 3.1))) * np.exp(-t / 0.05)

# ---- cryptid voices
def v_bigfoot_roar():
    v = voice(1.7, lambda u: 85 + 45 * np.sin(np.pi * min(u * 1.4, 1)), [(0, "uh"), (0.25, "a"), (0.8, "o"), (1, "u")],
              breath=0.6, rough=0.9, scale=0.62, seed=11)
    v = np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 2.2) * vshape(len(v), 0.08, 0.4)
    return reverb(v, 0.3, 1.4)

def v_bigfoot_grunt():
    v = voice(0.5, lambda u: 95 + 50 * u ** 2, [(0, "u"), (1, "uh")], breath=0.35, rough=0.4, scale=0.65, seed=12)
    return reverb(np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 1.6) * vshape(len(v), 0.04, 0.15), 0.2, 0.9)

def v_methman_alert():
    out = np.zeros(int(1.3 * SR))
    for k in range(5):
        v = voice(0.14, lambda u: 700 + 500 * u, [(0, "i"), (1, "e")], breath=0.4, scale=1.25, seed=20 + k, jitter=0.04)
        mix_at(out, v * vshape(len(v), 0.005, 0.03), k * 0.11)
    flutter = bp(noise(len(out)), 200, 1500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * np.arange(len(out)) / SR))) * 0.25
    return reverb(out + flutter * np.linspace(1, 0, len(out)), 0.2, 1.0)

def v_methman_grunt():
    out = np.zeros(int(0.9 * SR))
    for k in range(4):
        v = voice(0.09, lambda u: 260 - 40 * u, [(0, "e"), (1, "uh")], breath=0.7, scale=1.1, seed=30 + k, jitter=0.05)
        mix_at(out, v * vshape(len(v), 0.004, 0.03), k * 0.13 + np.random.default_rng(k).uniform(0, 0.03))
    return out

def v_grey_alert():
    out = np.zeros(int(1.1 * SR))
    notes_ = [(0.0, 0.12, 900, 1400), (0.15, 0.12, 1400, 700), (0.3, 0.25, 800, 1800)]
    for st, d, a, b in notes_:
        t = t_(d)
        f = a + (b - a) * (t / d) ** 0.6
        mix_at(out, (osc(f) + 0.3 * osc(f * 2, "tri")) * np.sin(np.pi * t / d) ** 0.5 * 0.6, st)
    return reverb(out, 0.25, 0.9)

def v_grey_grunt():
    t = t_(0.6)
    f = 500 + 300 * (t / 0.6) ** 2 + 30 * np.sin(2 * np.pi * 7 * t)
    return reverb(osc(f) * np.sin(np.pi * t / 0.6) * 0.6, 0.3, 0.9)

def v_corn_alert():  # whinny
    v = voice(1.3, lambda u: 900 - 500 * u + 120 * np.sin(2 * np.pi * 9 * u * 1.3), [(0, "i"), (0.5, "e"), (1, "ae")],
              breath=0.3, scale=1.35, seed=40, jitter=0.02)
    return reverb(v * vshape(len(v), 0.03, 0.4), 0.3, 1.2)

def v_corn_grunt():  # snort
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    return lp(noise(n), 1600) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 42 * t))) * env_exp(n, 0.01, 0.12)

def v_jersey_alert():  # shriek
    v = voice(1.1, lambda u: 650 + 700 * np.sin(np.pi * u) , [(0, "i"), (0.6, "ae"), (1, "i")], breath=0.5, rough=0.5, scale=1.3, seed=50, jitter=0.03)
    v = np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 2.0) * vshape(len(v), 0.05, 0.3)
    return reverb(v, 0.4, 1.6)

def v_jersey_grunt():  # "WOOO!" sports fan
    v = voice(0.8, lambda u: 210 + 160 * np.sin(np.pi * min(u * 1.5, 1)), [(0, "u"), (1, "u")], breath=0.25, scale=1.0, seed=51)
    return reverb(v * vshape(len(v), 0.04, 0.25), 0.25, 1.0)

def v_crackin_grunt():  # long beer burp
    r = np.random.default_rng(60)
    v = voice(1.0, lambda u: 75 + 25 * np.sin(np.pi * u) + 10 * r.standard_normal(), [(0, "o"), (0.5, "a"), (1, "uh")],
              breath=0.5, rough=1.0, scale=0.75, seed=60, jitter=0.08, shimmer=0.25)
    gurgle = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 23 * np.arange(len(v)) / SR + 3 * np.sin(2 * np.pi * 3 * np.arange(len(v)) / SR)))
    return v * gurgle * vshape(len(v), 0.02, 0.2)

def v_crackin_alert():  # "HEY!"
    out = np.zeros(int(1.6 * SR))
    v = voice(0.4, lambda u: 190 + 60 * np.sin(np.pi * u), [(0, "e"), (0.6, "e"), (1, "i")], breath=0.35, scale=0.95, seed=61)
    mix_at(out, v * vshape(len(v), 0.01, 0.1), 0.0)
    mix_at(out, v_crackin_grunt()[: int(0.9 * SR)] * 0.7, 0.45)
    return out

def v_pogo_alert():  # gargling lake roar
    v = voice(1.4, lambda u: 120 + 40 * np.sin(np.pi * u), [(0, "o"), (0.5, "a"), (1, "o")], breath=0.4, rough=0.6, scale=0.7, seed=70)
    bub = 0.5 + 0.5 * (np.random.default_rng(1).random(len(v) // 400 + 1).repeat(400)[: len(v)] > 0.4)
    return reverb(v * lp(bub, 60) * vshape(len(v), 0.05, 0.3), 0.35, 1.4)

def v_pogo_grunt():
    out = boing() * 0.6
    g = voice(0.4, lambda u: 130, [(0, "u"), (1, "o")], breath=0.5, rough=0.5, scale=0.8, seed=71)
    mix_at(out, g * vshape(len(g)) * 0.6, 0.2)
    return out

def v_wolf_alert():  # awooo
    v = voice(2.2, lambda u: 360 + 220 * np.sin(np.pi * min(u * 1.3, 1)) - 60 * u, [(0, "a"), (0.3, "o"), (1, "u")],
              breath=0.2, scale=1.1, seed=80, jitter=0.004)
    return reverb(v * vshape(len(v), 0.15, 0.6), 0.5, 2.2)

def v_wolf_grunt():  # "where?" whimper
    v = voice(0.6, lambda u: 480 + 260 * u ** 1.5, [(0, "u"), (0.4, "e"), (1, "er")], breath=0.25, scale=1.15, seed=81)
    return v * vshape(len(v), 0.03, 0.15)

def v_toe_talk(seed):
    r = np.random.default_rng(seed)
    out = np.zeros(int(1.4 * SR))
    st = 0.0
    vs = ["a", "e", "o", "u", "uh", "ae", "i"]
    while st < 1.15:
        d = r.uniform(0.08, 0.16)
        a, b = vs[r.integers(len(vs))], vs[r.integers(len(vs))]
        base = 135 * (1 + 0.15 * np.sin(st * 4))
        v = voice(d, lambda u, base=base: base + 25 * np.sin(np.pi * u), [(0, a), (1, b)], breath=0.15, scale=0.95, seed=int(st * 100) + seed)
        mix_at(out, v * vshape(len(v), 0.01, 0.03), st)
        st += d + r.uniform(0.0, 0.05)
    return out

def v_toe_whoa():
    v = voice(0.9, lambda u: 190 - 70 * u, [(0, "u"), (0.3, "o"), (1, "a")], breath=0.2, scale=0.95, seed=90)
    return v * vshape(len(v), 0.03, 0.3)

# ------------------------------------------------------------------ instruments
def pluck(f, dur, bright=3000):
    tt = t_(dur)
    x = osc(np.full(len(tt), f), "tri") * 0.7 + osc(np.full(len(tt), f * 2)) * 0.2
    return lp(x * exp_dec(len(tt), 0.22), bright)
def pad(freqs, dur):
    tt = t_(dur)
    x = np.zeros(len(tt))
    for f in freqs:
        for det in (-0.4, 0.0, 0.45):
            x += osc(np.full(len(tt), f * 2 ** (det / 100 * 12 / 12 * 0.1)), "saw", rng.uniform(0, 6))
    x = lp(x, 900, 2)
    return x * env_adsr(len(tt), 0.6, 0.4, 0.8, 0.8) / (len(freqs) * 3)
def theremin(notes, bpm, total):
    """notes: list of (beat_start, beats, name or None). Continuous glide between notes."""
    beat = 60 / bpm
    n = int(total * SR)
    f = np.zeros(n); amp = np.zeros(n)
    cur = None
    for b0, bl, nm in notes:
        i0, i1 = int(b0 * beat * SR), int((b0 + bl) * beat * SR)
        if nm is None: continue
        target = note(nm)
        start = cur if cur else target
        glide = min(int(0.09 * SR), i1 - i0)
        seg = np.full(i1 - i0, target)
        seg[:glide] = np.linspace(start, target, glide)
        f[i0:i1] = seg
        e = np.ones(i1 - i0)
        a = min(int(0.05 * SR), len(e)); r = min(int(0.12 * SR), len(e))
        e[:a] = np.linspace(0, 1, a); e[-r:] *= np.linspace(1, 0, r)
        amp[i0:i1] = np.maximum(amp[i0:i1], e)
        cur = target
    f[f == 0] = 440
    tt = np.arange(n) / SR
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.6 * tt) * np.clip(tt % 2, 0, 1)
    x = osc(f * vib) + 0.15 * osc(2 * f * vib)
    return x * lp(amp, 20)
def kick(dur=0.35):
    tt = t_(dur)
    return np.tanh(osc(50 + 110 * np.exp(-tt * 28)) * exp_dec(len(tt), 0.11) * 2.5)
def snare(dur=0.2):
    tt = t_(dur)
    return bp(noise(len(tt)), 1200, 7000) * exp_dec(len(tt), 0.05) + osc(np.full(len(tt), 190)) * exp_dec(len(tt), 0.03) * 0.5
def hat(dur=0.05, open_=False):
    n = int((0.2 if open_ else dur) * SR)
    return hp(noise(n), 7000) * exp_dec(n, 0.06 if open_ else 0.012)
def snap():
    n = int(0.08 * SR)
    return bp(noise(n), 1500, 4500) * exp_dec(n, 0.012)

# ------------------------------------------------------------------ music
def music_explore():
    bpm = 92; beat = 60 / bpm; bars = 16; total = bars * 4 * beat
    buf = np.zeros(int((total + 3) * SR))
    prog = [("A", ["A3", "C4", "E4"]), ("F", ["F3", "A3", "C4"]), ("D", ["D3", "F3", "A3"]), ("E", ["E3", "G#3", "B3"])]
    for i in range(8):
        root, ch = prog[i % 4]
        mix_at(buf, pad([note(n) for n in ch], 2 * 4 * beat + 0.8) * 0.55, i * 8 * beat)
    bass_pat = [(0, 0), (1.5, 0), (2, 7), (3, 5)]  # beat, semitone offset
    bass_roots = {"A": "A2", "F": "F2", "D": "D2", "E": "E2"}
    for bar in range(bars):
        root = prog[(bar // 2) % 4][0]
        f0 = note(bass_roots[root])
        for b, st in bass_pat:
            mix_at(buf, pluck(f0 * 2 ** (st / 12), 0.45, 1200) * 0.55, (bar * 4 + b) * beat)
        mix_at(buf, snap() * 0.35, (bar * 4 + 1) * beat)
        mix_at(buf, snap() * 0.35, (bar * 4 + 3) * beat)
        for e in range(8):
            mix_at(buf, hat() * (0.08 if e % 2 else 0.04), (bar * 4 + e * 0.5) * beat)
    mel = [
        (0, 3, "E5"), (3, 1, "F5"), (4, 2, "E5"), (6, 2, "C5"),
        (8, 3, "A4"), (11, 1, "C5"), (12, 4, "D5"),
        (16, 3, "F5"), (19, 1, "E5"), (20, 2, "D5"), (22, 2, "A4"),
        (24, 2, "B4"), (26, 2, "G#4"), (28, 4, "E5"),
        (36, 2, "A5"), (38, 1, "G5"), (39, 1, "F5"), (40, 4, "E5"),
        (44, 2, "C5"), (46, 2, "D5"), (48, 3, "F5"), (51, 1, "E5"), (52, 4, "D5"),
        (56, 2, "B4"), (58, 2, "D5"), (60, 4, "E5"),
    ]
    mix_at(buf, theremin(mel, bpm, total) * 0.32, 0)
    return loopify(reverb(buf, 0.35, 2.2), total), total
def music_chase():
    bpm = 150; beat = 60 / bpm; bars = 8; total = bars * 4 * beat
    buf = np.zeros(int((total + 2) * SR))
    riff = [0, 0, 12, 0, 3, 0, 5, 3, 0, 0, 12, 0, 7, 6, 5, 3]
    roots = ["D2", "D2", "A#1", "C2", "D2", "D2", "A#1", "A1"]
    for bar in range(bars):
        f0 = note(roots[bar])
        for e in range(8):
            st = riff[(bar % 2) * 8 + e]
            tt = t_(beat * 0.48)
            b = lp(osc(np.full(len(tt), f0 * 2 ** (st / 12)), "saw"), 900) * exp_dec(len(tt), 0.12)
            mix_at(buf, b * 0.6, (bar * 4 + e * 0.5) * beat)
        for b in [0, 1.5, 2, 3.5] if bar % 2 else [0, 1, 2, 2.75, 3]:
            mix_at(buf, kick() * 0.9, (bar * 4 + b) * beat)
        mix_at(buf, snare() * 0.55, (bar * 4 + 1) * beat)
        mix_at(buf, snare() * 0.55, (bar * 4 + 3) * beat)
        for e in range(8):
            mix_at(buf, hat(open_=(e == 7)) * 0.12, (bar * 4 + e * 0.5) * beat)
        stab_ch = [note("D4"), note("F4"), note("A4")] if roots[bar] in ("D2",) else [note("A#3"), note("D4"), note("F4")] if roots[bar] == "A#1" else [note("C4"), note("E4"), note("G4")] if roots[bar] == "C2" else [note("A3"), note("C#4"), note("E4")]
        for b in [0.5, 2.5]:
            tt = t_(beat * 0.4)
            s = sum(osc(np.full(len(tt), f), "saw") for f in stab_ch)
            mix_at(buf, lp(s, 2500) * exp_dec(len(tt), 0.08) * 0.12, (bar * 4 + b) * beat)
    wail = [(4, 3.5, "A5"), (8, 1, "C6"), (9, 1, "A#5"), (10, 2, "A5"), (12, 4, "F5"),
            (20, 3.5, "D6"), (24, 2, "C6"), (26, 2, "A#5"), (28, 4, "A5")]
    mix_at(buf, theremin(wail, bpm, total) * 0.18, 0)
    return loopify(reverb(buf, 0.18, 1.0), total), total
def xfade_loop(x, loop_len, xf=1.0):
    """Seamless loop for continuous sounds: crossfade the overhang into the start."""
    n, m = int(loop_len * SR), int(xf * SR)
    out = x[:n].copy()
    ramp = np.linspace(0, 1, m)
    out[:m] = x[:m] * np.sqrt(ramp) + x[n:n + m] * np.sqrt(1 - ramp)
    return out
# ------------------------------------------------------------------ ambience v2 (true stereo)
def pan(x, p):
    """p in -1..1 -> (L, R) equal-power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)

def cricket_voice(dur, seed, carrier, gain, dist):
    """One field cricket: chirps of 3-4 pulses (~15 ms each), ~2.5 chirps/sec, distance-filtered."""
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    out = np.zeros(n)
    period = r.uniform(0.32, 0.5)
    st = r.uniform(0, period)
    pulses = r.integers(3, 5)
    while st < dur - 0.2:
        for k in range(pulses):
            m = int(0.016 * SR)
            t = np.arange(m) / SR
            f = carrier * (1.02 - 0.03 * t / 0.016)
            e = np.minimum(t / 0.002, 1) * np.exp(-t / 0.008)
            p = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.12 * np.sin(4 * np.pi * np.cumsum(f) / SR)) * e
            mix_at(out, p * (0.85 + 0.15 * r.random()), st + k * 0.034)
        st += period * r.uniform(0.92, 1.08)
        if r.random() < 0.04:  # crickets pause now and then
            st += r.uniform(1.0, 3.0)
    cutoff = 9000 - 5500 * dist
    return lp(out, cutoff, 2) * gain

def katydid(dur, seed, gain):
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    out = np.zeros(n)
    st = r.uniform(0, 1)
    while st < dur - 0.5:
        for k in range(3):  # "ka-ty-did"
            m = int(0.06 * SR)
            b = bp(r.standard_normal(m), 5500, 11000) * np.sin(np.pi * np.linspace(0, 1, m)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 160 * np.arange(m) / SR)))
            mix_at(out, b, st + k * 0.13)
        st += r.uniform(1.2, 2.2)
    return out * gain

def tree_cricket(dur, seed, gain):
    """Continuous soft trill far away (snowy tree cricket style)."""
    t = np.arange(int(dur * SR)) / SR
    r = np.random.default_rng(seed)
    f = 2850 + 30 * np.sin(2 * np.pi * 0.07 * t + r.uniform(0, 6))
    trill = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * np.sin(2 * np.pi * 52 * t)) ** 3
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * 0.4 * t + r.uniform(0, 6)) ** 2
    return lp(trill * swell, 4000) * gain

def amb_woods():
    dur = 40.0
    n = int((dur + 1.5) * SR)
    L = np.zeros(n); R = np.zeros(n)
    t = np.arange(n) / SR
    wind = lp(noise(n), 350, 4) * (0.55 + 0.45 * np.sin(2 * np.pi * t / 13.0 + 1.0)) * 0.5
    leaves = bp(noise(n), 1500, 5000) * np.clip(np.sin(2 * np.pi * t / 13.0 + 1.0), 0, 1) ** 3 * 0.025
    rs = np.random.default_rng(21)
    for i in range(12):
        dist = rs.uniform(0.0, 1.0)
        c = cricket_voice(dur + 1.5, 100 + i, rs.uniform(4200, 4900), (1.0 - 0.75 * dist) * 0.09, dist)
        st = pan(c, rs.uniform(-0.9, 0.9))
        L += st[:, 0]; R += st[:, 1]
    for i in range(2):
        k = pan(katydid(dur + 1.5, 300 + i, 0.03), rs.uniform(-1, 1)); L += k[:, 0]; R += k[:, 1]
    tc = tree_cricket(dur + 1.5, 7, 0.025)
    L += tc; R += np.roll(tc, 600)
    L += wind + leaves; R += np.roll(wind, 1500) + np.roll(leaves, 900)
    st = np.stack([L, R], axis=1)
    return np.stack([xfade_loop(st[:, 0], dur), xfade_loop(st[:, 1], dur)], axis=1), dur

def amb_lake():
    dur = 40.0
    n = int((dur + 1.5) * SR)
    t = np.arange(n) / SR
    rs = np.random.default_rng(33)
    # lapping: slow swells of filtered noise with little splashes on the shore
    swell = (0.5 + 0.5 * np.sin(2 * np.pi * t / 4.3)) ** 2 * 0.7 + 0.3
    water = lp(noise(n), 900, 4) * swell * 0.45 + bp(noise(n), 1500, 4000) * swell ** 3 * 0.06
    L = water.copy(); R = np.roll(water, 2200)
    for i in range(int(dur / 1.3)):
        sp = wade(500 + i) * rs.uniform(0.05, 0.14)
        p = pan(sp, rs.uniform(-0.8, 0.8)); s0 = int(rs.uniform(0, dur) * SR)
        e = min(n, s0 + len(sp)); L[s0:e] += p[: e - s0, 0]; R[s0:e] += p[: e - s0, 1]
    for i in range(6):  # bullfrogs and green frogs around the shore
        st0 = rs.uniform(0, dur - 2)
        f = frog_bull(600 + i) * rs.uniform(0.15, 0.3) if i % 2 == 0 else frog_green(700 + i) * rs.uniform(0.1, 0.2)
        p = pan(f, rs.uniform(-1, 1)); s0 = int(st0 * SR); e = min(n, s0 + len(f))
        L[s0:e] += p[: e - s0, 0]; R[s0:e] += p[: e - s0, 1]
    for i in range(5):
        dist = rs.uniform(0.5, 1.0)
        c = pan(cricket_voice(dur + 1.5, 900 + i, rs.uniform(4300, 4800), (1.0 - 0.75 * dist) * 0.06, dist), rs.uniform(-0.9, 0.9))
        L += c[:, 0]; R += c[:, 1]
    return np.stack([xfade_loop(L, dur), xfade_loop(R, dur)], axis=1), dur

def save_ogg_stereo(name, st, peak=0.85):
    st = st / (np.max(np.abs(st)) + 1e-9) * peak
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (st * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f.name, "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(f.name)

def jingle_win():
    bpm = 160; beat = 60 / bpm
    buf = np.zeros(int(3.5 * SR))
    seq = [(0, 0.5, "C5"), (0.5, 0.5, "E5"), (1, 0.5, "G5"), (1.5, 2.5, "C6")]
    for b0, bl, n_ in seq:
        tt = t_(bl * beat + 0.3)
        f = note(n_)
        x = lp(osc(np.full(len(tt), f), "saw") + 0.5 * osc(np.full(len(tt), f * 1.5), "saw"), 3500)
        mix_at(buf, x * env_adsr(len(tt), 0.01, 0.1, 0.7, 0.25) * 0.4, b0 * beat)
    for f in ["C4", "E4", "G4"]:
        tt = t_(1.8)
        mix_at(buf, lp(osc(np.full(len(tt), note(f)), "saw"), 1800) * env_adsr(len(tt), 0.02, 0.2, 0.6, 0.8) * 0.2, 1.5 * beat)
    cym = hp(noise(int(1.8 * SR)), 5000) * exp_dec(int(1.8 * SR), 0.5) * 0.25
    mix_at(buf, cym, 1.5 * beat)
    return reverb(buf, 0.3, 1.5)
def sting_lose():
    buf = np.zeros(int(4.5 * SR))
    seq = [(0.0, 0.42, "G3"), (0.5, 0.42, "F#3"), (1.0, 0.42, "F3"), (1.5, 1.8, "E3")]
    for st, d, n_ in seq:
        tt = t_(d)
        f = np.full(len(tt), note(n_)) * (1 + (0.03 * np.sin(2 * np.pi * 6 * tt) * np.clip((tt - 0.3) * 2, 0, 1) if d > 1 else 0))
        src = osc(f, "saw")
        wah = np.zeros(len(tt))
        segs = np.array_split(np.arange(len(tt)), 24)
        filt = np.zeros(len(tt))
        for i, s in enumerate(segs):
            cutoff = 400 + 1600 * np.sin(np.pi * min(1.0, i / (len(segs) * (0.5 if d < 1 else 0.25)))) ** 2
            filt[s] = lp(src, cutoff)[s]
        mix_at(buf, filt * env_adsr(len(tt), 0.02, 0.05, 0.9, 0.1) * 0.6, st)
    return reverb(buf, 0.25, 1.2)



# ------------------------------------------------------------------ v0.8: RV, shop, Toe's camera swap, alien flash
def sfx_stun_ring():
    """Blinded by a flash: high tinnitus whine that wobbles and fades, with a muffled thump."""
    tt = t_(2.4)
    f = 3900 + 60 * np.sin(2 * np.pi * 5.2 * tt)
    ring = osc(f) * 0.6 + osc(f * 1.502) * 0.18
    ring *= np.exp(-tt / 1.0) * (1 - np.exp(-tt / 0.02))
    thud = thump(0.5, 90, 40, 0.12, seed=11)
    out = np.zeros(len(tt)); mix_at(out, ring, 0.0); mix_at(out, thud * 0.8, 0.0)
    return out

def sfx_engine():
    """Old RV turning over, catching, revving, then pulling away."""
    dur = 4.2; tt = t_(dur); n = len(tt)
    rpm = np.interp(tt, [0, 0.9, 1.1, 1.6, 2.2, 3.0, 4.2], [4, 5, 14, 22, 15, 26, 30])
    ph = np.cumsum(rpm) / SR
    firing = (np.sin(2 * np.pi * ph) > 0.55).astype(float)
    pulses = lp(firing - firing.mean(), 900) + 0.6 * lp(noise(n), 400) * firing
    body = resonator(pulses, 110, 80) + 0.5 * resonator(pulses, 240, 140)
    starter = np.zeros(n)
    st = osc(np.full(int(1.0 * SR), 18.0), "saw") * (0.5 + 0.5 * osc(np.full(int(1.0 * SR), 6.0)))
    mix_at(starter, bp(st + 0.2 * noise(len(st)), 200, 1500) * 0.7, 0.0)
    eng = body * np.clip((tt - 0.9) * 4, 0, 1)
    out = starter + eng * 1.4
    return reverb(out * np.minimum(1, (dur - tt) / 0.6), 0.15, 0.8)

def sfx_snore():
    """Two snores: rattly inhale, whistly exhale."""
    out = np.zeros(int(4.0 * SR))
    for k, st in enumerate((0.1, 2.1)):
        inh = voice(1.0, lambda u: 70 + 15 * u, [(0, "o"), (1, "a")], breath=0.6, rough=1.0, scale=0.9, seed=200 + k)
        inh = inh * vshape(len(inh), 0.25, 0.25) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 28 * t_(1.0)[:len(inh)])))
        exh = hp(noise(int(0.8 * SR)), 1200) * 0.15 + osc(np.linspace(900, 700, int(0.8 * SR))) * 0.05
        exh *= env_adsr(len(exh), 0.1, 0.2, 0.6, 0.3)
        mix_at(out, inh, st); mix_at(out, exh, st + 1.05)
    return out

def sfx_camera_crash():
    """The old camera hits the dirt: plastic clatter, a lens tinkle, a bounce."""
    out = np.zeros(int(1.2 * SR))
    for i, (st, g) in enumerate(((0.0, 1.0), (0.18, 0.5), (0.31, 0.3))):
        hit = modal([620, 1340, 2210, 3480], [0.05, 0.04, 0.03, 0.02], [1, 0.6, 0.4, 0.3], 0.3) * g
        mix_at(out, hit + 0.4 * g * hp(noise(len(hit)), 2000) * exp_dec(len(hit), 0.02), st)
    for i in range(6):
        mix_at(out, bell(3000 + i * 700 + rng.uniform(-200, 200), 0.25, 0.25) * 0.12, 0.05 + i * 0.04)
    mix_at(out, thump(0.3, 120, 60, 0.05, seed=5) * 0.6, 0.0)
    return out

def sfx_door():
    """RV screen door: latch click, creak, slap shut."""
    out = np.zeros(int(1.0 * SR))
    mix_at(out, modal([1800, 2600], [0.015, 0.01], [1, 0.5], 0.06) * 0.6, 0.0)
    cr = t_(0.45)
    f = 380 + 140 * np.sin(np.pi * cr / 0.45) + 30 * noise(len(cr)) * 0.2
    creak = resonator((np.sin(2 * np.pi * np.cumsum(f) / SR) > 0.9).astype(float), 1100, 300) * 0.6
    mix_at(out, creak * env_adsr(len(cr), 0.05, 0.1, 0.8, 0.1), 0.08)
    mix_at(out, modal([180, 420, 900], [0.08, 0.05, 0.03], [1, 0.5, 0.3], 0.3) * 0.8 + thump(0.3, 140, 70, 0.05, seed=3) * 0.5, 0.6)
    return out

def sfx_develop():
    """Darkroom: paper slipping into the tray, a slosh, drips."""
    out = np.zeros(int(1.6 * SR))
    slide = bp(noise(int(0.35 * SR)), 1500, 6000) * env_adsr(int(0.35 * SR), 0.05, 0.1, 0.6, 0.15) * 0.4
    mix_at(out, slide, 0.0)
    slosh = lp(noise(int(0.6 * SR)), 900) * env_adsr(int(0.6 * SR), 0.05, 0.2, 0.4, 0.3)
    slosh *= 0.5 + 0.5 * np.sin(2 * np.pi * 3.5 * t_(0.6)[:len(slosh)])
    mix_at(out, slosh * 0.8, 0.3)
    for i, st in enumerate((0.95, 1.2, 1.38)):
        d = t_(0.08); mix_at(out, np.sin(2 * np.pi * np.cumsum(np.linspace(900 + i * 150, 1900, len(d))) / SR) * exp_dec(len(d), 0.015) * 0.4, st)
    return out

def sfx_cash_tick():
    return bell(2600, 0.12, 0.05) * 0.5 + bell(3900, 0.12, 0.03) * 0.2

def v_shop_talk(seed):
    """Nasal, self-satisfied mumble: 'well actually...'"""
    r = np.random.default_rng(seed)
    out = np.zeros(int(1.3 * SR)); st = 0.0
    vs = ["e", "ae", "i", "uh", "a"]
    while st < 1.05:
        d = r.uniform(0.07, 0.14)
        a, b = vs[r.integers(len(vs))], vs[r.integers(len(vs))]
        base = 175 * (1 + 0.2 * np.sin(st * 6))
        v = voice(d, lambda u, base=base: base + 35 * np.sin(np.pi * u), [(0, a), (1, b)], breath=0.08, scale=1.08, seed=int(st * 100) + seed)
        mix_at(out, v * vshape(len(v), 0.01, 0.03), st)
        st += d + r.uniform(0.0, 0.04)
    return bp(out, 300, 2800, 1)

def v_shop_laugh():
    """Snorty 'heh heh'."""
    out = np.zeros(int(1.0 * SR))
    for i in range(3):
        v = voice(0.14, lambda u: 210 - 30 * u, [(0, "e"), (1, "uh")], breath=0.5, scale=1.08, seed=300 + i)
        mix_at(out, v * vshape(len(v), 0.01, 0.05), 0.05 + i * 0.2)
    return out

# ---- v0.11 voices and sounds
def v_fhairy_alert():  # big hairy man shrieking in falsetto: "EEEEE!"
    v = voice(0.9, lambda u: 620 + 260 * np.sin(np.pi * min(u * 1.6, 1)), [(0, "i"), (0.7, "i"), (1, "e")],
              breath=0.35, rough=0.15, scale=0.9, seed=90, jitter=0.03)
    return reverb(np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 1.6) * vshape(len(v), 0.03, 0.25), 0.25, 1.0)

def v_fhairy_grunt():  # a breathy giggle: "tee-hee-hee" in a baritone
    out = np.zeros(int(1.0 * SR))
    for k in range(4):
        v = voice(0.13, lambda u: 210 - 30 * u + k * 12, [(0, "i"), (1, "e")], breath=0.6, scale=0.92, seed=91 + k)
        mix_at(out, v * vshape(len(v), 0.008, 0.05), 0.05 + k * 0.17)
    return out

def v_leper_alert():  # "OI! ME GOLD!" squeaky and furious
    out = np.zeros(int(1.3 * SR))
    syl = [(0.0, 0.22, [(0, "o"), (1, "i")], 380), (0.35, 0.16, [(0, "e"), (1, "i")], 450), (0.56, 0.4, [(0, "o"), (0.5, "o"), (1, "u")], 420)]
    for k, (st, d, vw, f0) in enumerate(syl):
        v = voice(d, lambda u, f0=f0: f0 + 140 * np.sin(np.pi * u), vw, breath=0.3, scale=1.25, seed=95 + k, jitter=0.03)
        mix_at(out, v * vshape(len(v), 0.01, 0.06), st)
    return reverb(out, 0.2, 0.8)

def v_leper_grunt():  # a little diddly-dee hum (a jig)
    out = np.zeros(int(1.2 * SR))
    seq = [520, 620, 700, 620, 520, 470]
    for k, f in enumerate(seq):
        v = voice(0.16, lambda u, f=f: f, [(0, "i"), (1, "i")], breath=0.2, scale=1.3, seed=99 + k)
        mix_at(out, v * vshape(len(v), 0.01, 0.04), k * 0.17)
    return reverb(out * 0.8, 0.2, 0.8)

def v_rake_alert():  # the Rake's scream: a ragged, inhuman screech
    v = voice(1.6, lambda u: 900 + 500 * np.sin(np.pi * u * 1.2) + 200 * np.sin(2 * np.pi * 13 * u), [(0, "ae"), (0.5, "i"), (1, "ae")],
              breath=0.9, rough=1.0, scale=1.4, seed=110, jitter=0.06, shimmer=0.3)
    v = np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 3.0)
    return reverb(v * vshape(len(v), 0.02, 0.5), 0.5, 2.0)

def v_rake_grunt():  # plastic tines dragged over concrete
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    ticks = grains(1.1, lambda tt: 90 + 60 * np.sin(np.pi * tt / 1.1), 1500, 4500, 111, loud=1.2)
    scrape = bp(noise(n), 900, 3500) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 5.5 * t))) * 0.35
    return reverb((ticks[:n] + scrape) * env_adsr(n, 0.05, 0.1, 0.8, 0.3), 0.3, 1.2)

def v_bent_alert():  # a slow, huge "duuuuude..."
    v = voice(1.8, lambda u: 70 + 18 * np.sin(np.pi * u), [(0, "u"), (0.2, "u"), (0.8, "u"), (1, "uh")],
              breath=0.45, rough=0.4, scale=0.55, seed=120, jitter=0.02)
    return reverb(v * vshape(len(v), 0.1, 0.5), 0.35, 1.6)

def v_bent_grunt():  # cough then a long slurp
    out = np.zeros(int(1.3 * SR))
    for k in range(2):
        c = hp(noise(int(0.16 * SR)), 300) * env_exp(int(0.16 * SR), 0.005, 0.05)
        mix_at(out, lp(c, 2500) * 0.6, 0.05 + k * 0.22)
    n = int(0.6 * SR)
    sl = bp(noise(n), 400, 1800) * np.linspace(0.2, 1.0, n) * env_adsr(n, 0.05, 0.1, 0.8, 0.1) * 0.4
    mix_at(out, sl, 0.6)
    return out

def v_santa_ho():  # HO HO HO
    out = np.zeros(int(1.8 * SR))
    for k in range(3):
        v = voice(0.32, lambda u: 140 - 25 * u, [(0, "o"), (1, "o")], breath=0.5, scale=0.75, seed=130 + k)
        h = hp(noise(int(0.05 * SR)), 1000) * 0.3
        mix_at(out, h, 0.05 + k * 0.45)
        mix_at(out, v * vshape(len(v), 0.02, 0.1), 0.08 + k * 0.45)
    return reverb(out, 0.3, 1.2)

def sfx_sleigh_bells():
    out = np.zeros(int(2.5 * SR))
    r = np.random.default_rng(140)
    for k in range(26):
        f = r.choice([2400, 2900, 3300, 3800])
        b = bell(f, 0.35, 0.12) * r.uniform(0.2, 0.5)
        mix_at(out, b, k * 0.085 + r.uniform(0, 0.02))
    return out * np.linspace(1, 0.3, len(out))

def sfx_ufo_hum():  # loopable 2 s throb
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    base = osc(np.full(n, 55.0)) + 0.6 * osc(np.full(n, 110.5)) + 0.3 * osc(np.full(n, 221.0), "tri")
    wob = 0.75 + 0.25 * np.sin(2 * np.pi * 2.0 * t)
    whine = osc(np.full(n, 880.0) + 30 * np.sin(2 * np.pi * 1.0 * t)) * 0.08
    return (base * wob * 0.4 + whine)

def sfx_ufo_zip():  # pew: shoots off into the sky
    t = t_(1.2)
    f = 300 + 2600 * (t / 1.2) ** 2
    return reverb((osc(f) + 0.4 * osc(f * 1.5, "tri")) * np.exp(-t / 0.5) * 0.6, 0.4, 1.5)

def sfx_horn():  # two-tone car horn, a short impatient double toot
    out = np.zeros(int(0.62 * SR))
    for start, dur in [(0.0, 0.18), (0.26, 0.34)]:
        n = int(dur * SR)
        tt = np.arange(n) / SR
        x = np.zeros(n)
        for f in (415.0, 523.0):  # the classic minor-third horn pair
            ph = 2 * np.pi * f * tt
            x += signal.square(ph, 0.5) * 0.5 + np.sin(ph) * 0.3
        x = bp(x, 300, 3200)
        x *= env_adsr(n, 0.008, 0.04, 0.85, 0.04)
        mix_at(out, x, int(start * SR))
    return fade(out)


def sfx_tractor():  # the beam locks on
    t = t_(1.6)
    f = 140 + 60 * np.sin(2 * np.pi * 6 * t)
    x = (osc(f) + 0.5 * osc(f * 2.01) + 0.3 * osc(f * 3.02, "tri")) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t))
    x += bp(noise(len(t)), 2000, 6000) * 0.08
    return reverb(x * env_adsr(len(t), 0.15, 0.2, 0.8, 0.4), 0.4, 1.6)

def sfx_coins():
    out = np.zeros(int(1.2 * SR))
    r = np.random.default_rng(150)
    for k in range(14):
        b = bell(r.uniform(3200, 5200), 0.25, 0.08) * r.uniform(0.3, 0.7)
        mix_at(out, b, k * 0.06 + r.uniform(0, 0.03))
    mix_at(out, sfx_cash() * 0.6, 0.6)
    return out

def sfx_rooster():  # cock-a-doodle-doo, from across the way
    out = np.zeros(int(2.0 * SR))
    parts = [(0.0, 0.18, 620, 700), (0.22, 0.16, 760, 820), (0.42, 0.18, 820, 860), (0.64, 0.75, 900, 560)]
    for k, (st, d, f0, f1) in enumerate(parts):
        v = voice(d, lambda u, f0=f0, f1=f1: f0 + (f1 - f0) * u, [(0, "o"), (0.5, "u"), (1, "o")], breath=0.4, rough=0.5, scale=1.6, seed=170 + k, jitter=0.05)
        mix_at(out, v * vshape(len(v), 0.01, 0.08), st)
    return reverb(lp(out, 3500) * 0.7, 0.5, 1.6)

def amb_city():
    dur = 40.0
    n = int((dur + 1.5) * SR)
    t = np.arange(n) / SR
    rs = np.random.default_rng(160)
    rumble = lp(noise(n), 180, 4) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 9.0)) * 0.7
    hiss = bp(noise(n), 400, 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 6.3 + 1)) ** 2 * 0.05
    L = rumble + hiss; R = np.roll(rumble, 3000) + np.roll(hiss, 1700)
    for i in range(7):  # cars passing on far streets
        st0 = rs.uniform(0, dur - 4); d = rs.uniform(2.5, 4.0); m = int(d * SR)
        car = lp(noise(m), rs.uniform(500, 900), 2) * np.sin(np.pi * np.arange(m) / m) ** 2 * rs.uniform(0.2, 0.4)
        p = pan(car, rs.uniform(-1, 1)); s0 = int(st0 * SR); e = min(n, s0 + m)
        L[s0:e] += p[: e - s0, 0]; R[s0:e] += p[: e - s0, 1]
    for i in range(3):  # distant horns
        st0 = rs.uniform(0, dur - 1); m = int(0.4 * SR); tt = np.arange(m) / SR
        h = (osc(np.full(m, 420.0), "saw") + osc(np.full(m, 525.0), "saw")) * env_adsr(m, 0.01, 0.05, 0.8, 0.05)
        h = reverb(lp(h, 1500) * 0.05, 0.5, 1.5)[:m]
        p = pan(h, rs.uniform(-1, 1)); s0 = int(st0 * SR); e = min(n, s0 + m)
        L[s0:e] += p[: e - s0, 0]; R[s0:e] += p[: e - s0, 1]
    # one far-off siren
    m = int(9.0 * SR); tt = np.arange(m) / SR
    sir = osc(700 + 250 * np.sin(2 * np.pi * 0.35 * tt)) * np.sin(np.pi * tt / 9.0) ** 2 * 0.04
    sir = lp(sir, 1800)
    s0 = int(14 * SR); L[s0:s0 + m] += sir * 0.7; R[s0:s0 + m] += sir
    return np.stack([xfade_loop(L, dur), xfade_loop(R, dur)], axis=1), dur

# ------------------------------------------------------------------ render
SFX = {
    "shutter": sfx_shutter, "dry_click": sfx_dry_click, "flash_charge": sfx_flash_charge, "reload": sfx_reload,
    "ui_click": sfx_ui_click, "cash": sfx_cash, "whoosh": sfx_whoosh, "escaped": sfx_escaped,
    "trap_snap": sfx_trap_snap, "trap_set": sfx_trap_set, "bait_drop": sfx_bait_drop, "ouch": sfx_ouch,
    "bigfoot_munch": sfx_munch, "owl": sfx_owl, "loon": sfx_loon, "land": step_land, "boing": boing,
    "win": jingle_win, "lose": sting_lose,
    "bigfoot_roar": v_bigfoot_roar, "bigfoot_grunt": v_bigfoot_grunt,
    "methman_alert": v_methman_alert, "methman_grunt": v_methman_grunt,
    "grey_alert": v_grey_alert, "grey_grunt": v_grey_grunt,
    "corn_alert": v_corn_alert, "corn_grunt": v_corn_grunt,
    "jersey_alert": v_jersey_alert, "jersey_grunt": v_jersey_grunt,
    "crackin_alert": v_crackin_alert, "crackin_grunt": v_crackin_grunt,
    "pogo_alert": v_pogo_alert, "pogo_grunt": v_pogo_grunt,
    "wolf_alert": v_wolf_alert, "wolf_grunt": v_wolf_grunt,
    "toe_whoa": v_toe_whoa,
    "stun_ring": sfx_stun_ring, "engine": sfx_engine, "snore": sfx_snore, "camera_crash": sfx_camera_crash,
    "door": sfx_door, "develop": sfx_develop, "cash_tick": sfx_cash_tick, "shop_laugh": v_shop_laugh,
    "fhairy_alert": v_fhairy_alert, "fhairy_grunt": v_fhairy_grunt, "leper_alert": v_leper_alert, "leper_grunt": v_leper_grunt,
    "rake_alert": v_rake_alert, "rake_grunt": v_rake_grunt, "bent_alert": v_bent_alert, "bent_grunt": v_bent_grunt,
    "santa_ho": v_santa_ho, "sleigh_bells": sfx_sleigh_bells, "ufo_hum": sfx_ufo_hum, "ufo_zip": sfx_ufo_zip,
    "tractor": sfx_tractor, "coins": sfx_coins, "rooster": sfx_rooster, "horn": sfx_horn,
}
for i in range(6):
    SFX[f"step_{i+1}"] = (lambda i=i: step_forest(1000 + i * 7))
    SFX[f"run_{i+1}"] = (lambda i=i: step_run(2000 + i * 7))
for i in range(4):
    SFX[f"sneak_{i+1}"] = (lambda i=i: step_sneak(3000 + i * 7))
    SFX[f"wade_{i+1}"] = (lambda i=i: wade(4000 + i * 7))
    SFX[f"bigstep_{i+1}"] = (lambda i=i: big_step(5000 + i * 7))
    SFX[f"midstep_{i+1}"] = (lambda i=i: mid_step(6000 + i * 7))
    SFX[f"hoof_{i+1}"] = (lambda i=i: hoof(7000 + i * 7))
for i in range(3):
    SFX[f"shop_talk_{i+1}"] = (lambda i=i: v_shop_talk(9000 + i))
for i in range(3):
    SFX[f"toe_talk_{i+1}"] = (lambda i=i: v_toe_talk(8000 + i))

only = set(sys.argv[2:])
for name, fn in SFX.items():
    if only and name not in only and name.rsplit("_", 1)[0] not in only:
        continue
    save_wav(name, fn())
    print("sfx", name)
for name, fn in {"music_explore": music_explore, "music_chase": music_chase}.items():
    if only and name not in only:
        continue
    x, length = fn()
    save_ogg(name, x, stereo=0.35)
    print("loop", name, f"{length:.2f}s")
for name, fn in {"amb_woods": amb_woods, "amb_lake": amb_lake, "amb_city": amb_city}.items():
    if only and name not in only:
        continue
    st, length = fn()
    save_ogg_stereo(name, st)
    print("loop", name, f"{length:.2f}s")
