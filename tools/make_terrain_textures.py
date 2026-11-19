#!/usr/bin/env python3
"""Generate seamless (tileable) placeholder terrain textures: albedo + OpenGL-style normal maps.

Writes assets/textures/terrain/<name>_albedo.jpg and <name>_normal.png for:
    sand, grass, forest_floor, rock, snow, dirt

They are procedural stand-ins. For better results drop in real PBR textures with the
same file names (e.g. CC0 sets from ambientCG or Poly Haven; use the *NormalGL* map).

Usage:  python3 tools/make_terrain_textures.py
Requires: numpy, pillow
"""
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
OUT = Path(__file__).resolve().parents[1] / "assets" / "textures" / "terrain"


def fbm(beta, rng, stretch=(1.0, 1.0)):
    """Periodic fractal noise via FFT filtering -> tiles perfectly. stretch makes it anisotropic."""
    spectrum = np.fft.fft2(rng.standard_normal((SIZE, SIZE)))
    fy = np.fft.fftfreq(SIZE)[:, None] * stretch[1]
    fx = np.fft.fftfreq(SIZE)[None, :] * stretch[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum /= f ** (beta / 2.0)
    spectrum[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.min()) / (out.max() - out.min())


def ramp(t, stops):
    """Map 0..1 values through a list of (position, (r, g, b)) colour stops."""
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float32) / 255.0
    return np.stack([np.interp(t, pos, cols[:, c]) for c in range(3)], axis=-1)


def cells(rng, count, radius):
    """Periodic pebble/blob field: max of soft discs at random wrapped positions."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    out = np.zeros((SIZE, SIZE), np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, SIZE, 2)
        r = radius * rng.uniform(0.5, 1.3)
        dx = np.abs(xx - cx)
        dy = np.abs(yy - cy)
        dx = np.minimum(dx, SIZE - dx)
        dy = np.minimum(dy, SIZE - dy)
        out = np.maximum(out, np.clip(1.0 - (dx * dx + dy * dy) / (r * r), 0, 1))
    return out


def normal_map(height, strength):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)  # +Y up (OpenGL convention)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, albedo, height, strength):
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT / f"{name}_albedo.jpg", quality=92)
    Image.fromarray(normal_map(height, strength), "RGB").save(OUT / f"{name}_normal.png", optimize=True)
    print("wrote", name)


def main():
    rng = np.random.default_rng(42)

    # Grass: patchy greens with fine blade streaks.
    patches = fbm(2.2, rng)
    blades = fbm(0.9, rng, stretch=(3.0, 0.6))
    t = np.clip(0.55 * patches + 0.45 * blades, 0, 1)
    albedo = ramp(t, [(0.0, (38, 62, 22)), (0.45, (72, 104, 36)), (0.75, (104, 128, 50)), (1.0, (140, 146, 72))])
    save("grass", albedo, 0.4 * patches + 0.6 * blades, 6.0)

    # Forest floor: dark soil, needles and moss.
    soil = fbm(2.0, rng)
    needles = fbm(0.7, rng, stretch=(2.5, 1.0))
    moss = fbm(2.6, rng)
    t = np.clip(0.4 * soil + 0.6 * needles, 0, 1)
    albedo = ramp(t, [(0.0, (34, 26, 18)), (0.5, (66, 50, 30)), (1.0, (104, 82, 52))])
    moss_mask = np.clip((moss - 0.55) * 4.0, 0, 1)[..., None]
    albedo = albedo * (1 - moss_mask) + ramp(needles, [(0, (40, 62, 26)), (1, (78, 98, 40))]) * moss_mask
    save("forest_floor", albedo, 0.5 * soil + 0.5 * needles, 7.0)

    # Rock: ridged layers plus cracks.
    big = fbm(2.3, rng)
    ridges = 1.0 - np.abs(fbm(1.9, rng, stretch=(0.5, 2.0)) * 2 - 1)
    fine = fbm(1.2, rng)
    h = 0.45 * big + 0.35 * ridges + 0.2 * fine
    cracks = np.clip((ridges - 0.92) * 12.0, 0, 1)
    albedo = ramp(h, [(0.0, (62, 58, 54)), (0.5, (104, 98, 90)), (0.8, (136, 130, 120)), (1.0, (160, 154, 144))])
    albedo *= (1.0 - 0.5 * cracks)[..., None]
    save("rock", albedo, h - 0.3 * cracks, 10.0)

    # Sand: wind ripples (integer frequency -> tiles) warped by noise.
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
    warp = fbm(2.6, rng)
    ripples = 0.5 + 0.5 * np.sin(2 * np.pi * (14 * yy + 3 * xx) + warp * 6.0)
    grain = fbm(0.4, rng)
    h = 0.6 * ripples + 0.25 * fbm(2.2, rng) + 0.15 * grain
    albedo = ramp(0.5 * fbm(2.4, rng) + 0.3 * ripples + 0.2 * grain,
                  [(0.0, (168, 146, 106)), (0.5, (198, 178, 134)), (1.0, (222, 206, 166))])
    save("sand", albedo, h, 4.0)

    # Snow: soft drifts, slight blue in hollows, sparkle.
    drifts = fbm(2.6, rng)
    sparkle = (rng.random((SIZE, SIZE)) > 0.996).astype(np.float32) * 0.15
    albedo = ramp(drifts, [(0.0, (196, 210, 228)), (0.6, (230, 236, 244)), (1.0, (248, 250, 252))]) + sparkle[..., None]
    save("snow", albedo, drifts + 0.1 * fbm(1.4, rng), 3.0)

    # Dirt: earth with pebbles (used for cliff sides under grass).
    earth = fbm(2.1, rng)
    pebbles = cells(rng, 140, 7.0)
    h = 0.6 * earth + 0.4 * pebbles + 0.1 * fbm(1.0, rng)
    albedo = ramp(earth, [(0.0, (62, 44, 30)), (0.6, (96, 72, 48)), (1.0, (122, 96, 66))])
    peb_col = ramp(fbm(1.5, rng), [(0, (96, 92, 86)), (1, (140, 134, 124))])
    pm = np.clip(pebbles * 2.0, 0, 1)[..., None]
    albedo = albedo * (1 - pm) + peb_col * pm
    save("dirt", albedo, h, 8.0)


if __name__ == "__main__":
    main()
