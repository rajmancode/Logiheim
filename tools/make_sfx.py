"""Synthesises the game's sound effects (no recordings): writes assets/sfx/<name>.wav.

    python tools/make_sfx.py

Mono, 22.05 kHz, 16-bit. One-shots for the interface (hover, click, tab, panel open and close,
error, message chime), for building (placing, hammering, the bell when a building is done,
demolishing, a road's gravel), for the clan (coins, a horn to expand or muster, war drums,
the dawn bell) and seamless loops for the world around (sea, wind, birdsong, crickets, rain).
"""
import os
import wave

import numpy as np
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 22050
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a, d, curve=4.0):
    """Attack a seconds, then exponential decay over the rest (d sets its speed)."""
    x = np.arange(n) / SR
    e = np.minimum(x / max(a, 1e-4), 1.0) * np.exp(-np.maximum(x - a, 0) * curve / max(d, 1e-4))
    return e


def noise(d):
    return rng.standard_normal(int(SR * d))


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def sine(f, d, phase=0.0):
    return np.sin(2 * np.pi * f * t(d) + phase)


def sweep(f0, f1, d):
    x = t(d)
    f = f0 * (f1 / f0) ** (x / d)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pad(x, d):
    out = np.zeros(int(SR * d))
    out[:min(len(x), len(out))] += x[:len(out)]
    return out


def mixat(base, x, at):
    i = int(at * SR)
    n = min(len(x), len(base) - i)
    if n > 0:
        base[i:i + n] += x[:n]
    return base


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, peak=0.8):
    x = norm(x, peak)
    # A few ms fade at each end: no clicks.
    f = min(len(x) // 4, int(0.004 * SR))
    if f > 0:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def loop(x, fade=1.0):
    """Makes a loop seamless: the tail crossfaded into the head."""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:].copy()
    k = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * k + tail * (1 - k)
    return x


def tok(f, d=0.06, bright=0.5):
    """A wooden knock: a short pitched body and a click of noise."""
    body = sine(f, d) * env(int(SR * d), 0.001, d * 0.5, 5)
    body += 0.5 * sine(f * 2.3, d) * env(int(SR * d), 0.001, d * 0.25, 5)
    click = bp(noise(d), 1500, 6000) * env(int(SR * d), 0.0005, 0.012, 5) * bright
    return body + click


def bell(f, d, partials=((1, 1), (2.0, 0.5), (2.76, 0.4), (5.4, 0.2), (8.9, 0.08))):
    out = np.zeros(int(SR * d))
    for r, a in partials:
        out += a * sine(f * r, d, rng.uniform(0, 6)) * env(int(SR * d), 0.002, d / (0.6 + r * 0.3), 4)
    return out


def ui():
    save("ui_hover", tok(2400, 0.03, 0.2), 0.25)
    save("ui_click", tok(900, 0.07, 0.6), 0.6)
    x = bp(noise(0.12), 1800, 7000) * env(int(SR * 0.12), 0.004, 0.05, 4)
    save("ui_tab", x + 0.3 * tok(1300, 0.12, 0.2), 0.45)
    x = bp(noise(0.3), 400, 3000) * np.sin(np.linspace(0, np.pi, int(SR * 0.3))) ** 2
    save("ui_open", x * (0.4 + 0.6 * np.linspace(0, 1, len(x))), 0.35)
    save("ui_close", x[::-1] * 0.8, 0.3)
    e = np.zeros(int(SR * 0.3))
    for at in (0.0, 0.12):
        b = signal.sawtooth(2 * np.pi * 160 * t(0.1)) * env(int(SR * 0.1), 0.003, 0.06, 3)
        mixat(e, lp(b, 900), at)
    save("error", e, 0.5)
    c = bell(880, 0.9, ((1, 1), (2.0, 0.3), (3.0, 0.15)))
    c = mixat(pad(c, 1.1), bell(1320, 0.9, ((1, 0.7), (2.0, 0.2))), 0.09)
    save("message", c, 0.45)
    save("select", tok(620, 0.09, 0.4), 0.55)
    x = np.zeros(int(SR * 0.6))
    # A plucked string (Karplus-Strong) for picking a resource.
    p = int(SR / 330)
    buf = rng.uniform(-1, 1, p)
    for i in range(len(x)):
        x[i] = buf[i % p]
        buf[i % p] = 0.5 * (buf[i % p] + buf[(i + 1) % p]) * 0.996
    save("pluck", x, 0.45)
    save("pause", sweep(700, 420, 0.12) * env(int(SR * 0.12), 0.003, 0.08, 3), 0.4)
    save("resume", sweep(420, 700, 0.12) * env(int(SR * 0.12), 0.003, 0.08, 3), 0.4)


def building():
    # Placing: a deep thud as the first post goes in, and a knock.
    th = sweep(110, 50, 0.3) * env(int(SR * 0.3), 0.002, 0.15, 4)
    th += lp(noise(0.3), 300) * env(int(SR * 0.3), 0.001, 0.06, 5) * 0.6
    save("place", mixat(pad(th, 0.4), tok(380, 0.1, 0.8) * 0.7, 0.02), 0.8)
    # Hammering, three variations.
    for i, f in enumerate((520, 600, 470)):
        h = tok(f, 0.12, 1.0) + 0.4 * bp(noise(0.12), 2500, 8000) * env(int(SR * 0.12), 0.0005, 0.02, 5)
        save("hammer%d" % i, h, 0.6)
    # Done: a warm bell, twice.
    b = mixat(pad(bell(523, 2.2), 2.8), bell(784, 2.0) * 0.6, 0.35)
    save("build_done", b, 0.55)
    # Demolish: timber cracking and falling.
    d = np.zeros(int(SR * 1.3))
    for k in range(9):
        cr = bp(noise(0.05), 800, 5000) * env(int(SR * 0.05), 0.0005, 0.02, 5)
        mixat(d, cr * rng.uniform(0.4, 1.0), rng.uniform(0.0, 0.35))
    fall = lp(noise(1.0), 400) * env(int(SR * 1.0), 0.05, 0.5, 3)
    mixat(d, fall * 1.5, 0.25)
    mixat(d, sweep(90, 40, 0.5) * env(int(SR * 0.5), 0.002, 0.3, 4) * 1.2, 0.3)
    save("demolish", d, 0.8)
    # A road: shovelled gravel.
    g = np.zeros(int(SR * 0.45))
    for k in range(40):
        gr = bp(noise(0.012), 1500, 7000) * env(int(SR * 0.012), 0.0005, 0.006, 5)
        mixat(g, gr * rng.uniform(0.2, 1.0), rng.uniform(0.0, 0.38) * rng.uniform(0.6, 1.0))
    g += lp(noise(0.45), 500) * env(int(SR * 0.45), 0.02, 0.2, 4) * 0.4
    save("road", g, 0.6)


def clan():
    c = np.zeros(int(SR * 0.5))
    for at, f in ((0.0, 2300), (0.07, 3100), (0.13, 2700)):
        mixat(c, bell(f, 0.35, ((1, 1), (1.5, 0.3), (2.4, 0.2))), at)
    save("coins", c, 0.45)
    # A horn: a brassy sawtooth with a little vibrato, swelling and fading.
    d = 1.6
    x = t(d)
    f = 147 * (1 + 0.006 * np.sin(2 * np.pi * 5 * x) * np.minimum(x / 0.5, 1))
    saw = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) + 0.5 * signal.sawtooth(2 * np.pi * np.cumsum(f * 1.5) / SR)
    amp = np.minimum(x / 0.25, 1) * np.exp(-np.maximum(x - 1.1, 0) * 6)
    save("horn", lp(saw, 1400) * amp, 0.55)
    dr = np.zeros(int(SR * 1.2))
    for at, a in ((0.0, 1), (0.3, 0.7), (0.45, 0.8), (0.75, 1)):
        hit = sweep(120, 60, 0.35) * env(int(SR * 0.35), 0.001, 0.2, 4) + 0.3 * lp(noise(0.35), 900) * env(int(SR * 0.35), 0.001, 0.04, 5)
        mixat(dr, hit * a, at)
    save("drums", dr, 0.7)
    save("dawn", mixat(pad(bell(392, 2.6), 3.2), bell(392 * 1.5, 2.2) * 0.5, 0.5), 0.4)
    save("march", mixat(pad(tok(200, 0.1, 0.6), 0.5), tok(180, 0.1, 0.6) * 0.8, 0.25), 0.5)


def ambient():
    d = 10.0
    x = t(d)
    # Sea: rolling surf, waves breaking every few seconds.
    sea = lp(rng.standard_normal(len(x)), 700)
    swell = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 5.0)) ** 2.5
    swell += 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 2.5 + 1.0)) ** 4
    hiss = hp(rng.standard_normal(len(x)), 2500) * 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 5.0 - 0.6)) ** 3
    save("amb_sea", loop(sea * swell + hiss), 0.5)
    # Wind: soft gusting noise.
    w = bp(rng.standard_normal(len(x)), 200, 1200)
    gust = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 10.0)) * (0.7 + 0.3 * np.sin(2 * np.pi * x / 3.3))
    save("amb_wind", loop(w * gust), 0.5)
    # Birdsong: little chirps now and then.
    b = np.zeros(len(x))
    for k in range(26):
        f0 = rng.uniform(2500, 4200)
        dd = rng.uniform(0.05, 0.14)
        ch = sweep(f0, f0 * rng.uniform(0.7, 1.4), dd) * np.sin(np.linspace(0, np.pi, int(SR * dd)))
        at = rng.uniform(0, d - 0.3)
        for r in range(rng.integers(1, 4)):
            mixat(b, ch * rng.uniform(0.3, 1.0), at + r * dd * 1.3)
    save("amb_birds", loop(b, 0.3), 0.35)
    # Crickets: pulsed trills.
    cr = np.zeros(len(x))
    for f, per, ph in ((4400, 0.9, 0.0), (4700, 1.3, 0.4), (4100, 1.1, 0.7)):
        tr = np.sin(2 * np.pi * f * x) * (np.sin(2 * np.pi * 30 * x) > 0.2)
        on = ((x + ph) % per) < per * 0.45
        cr += tr * on * 0.4
    save("amb_crickets", loop(lp(cr, 6000)), 0.25)
    # Rain: a steady patter.
    rn = hp(rng.standard_normal(len(x)), 1500) * 0.5
    for k in range(600):
        mixat(rn, bp(noise(0.01), 2000, 8000) * env(int(SR * 0.01), 0.0005, 0.004, 5) * rng.uniform(0.5, 2.0), rng.uniform(0, d - 0.02))
    save("amb_rain", loop(rn), 0.45)


OUT = os.path.join(ROOT, "assets", "sfx")

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ui()
    building()
    clan()
    ambient()
    print("wrote", len(os.listdir(OUT)), "sounds to", OUT)
