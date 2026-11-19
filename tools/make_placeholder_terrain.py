#!/usr/bin/env python3
"""Generate placeholder "Gaea-style" exports so the game runs before real Gaea maps exist.

Each map is written to data/gaea/<map_name>/ using the same layout the game expects
from a real Gaea export (see docs/GAEA_PIPELINE.md):

    map.json        metadata (world size, height range, sea level, file list)
    heightmap.r16   16-bit little-endian unsigned heights, row-major, row 0 = north (z = 0)
    <mask>.png      8-bit grayscale masks (water, sand, rock, snow, forest)

Replace these folders with real Gaea exports whenever you are ready.

Usage:  python3 tools/make_placeholder_terrain.py
Requires: numpy, pillow
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "data" / "gaea"


def fbm(shape, beta, rng):
    """Spectral-synthesis fractal noise (power spectrum ~ 1/f^beta), normalised to 0..1."""
    h, w = shape
    spectrum = np.fft.fft2(rng.standard_normal(shape))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum /= f ** (beta / 2.0)
    spectrum[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.min()) / (out.max() - out.min())


def ridged(n):
    return 1.0 - np.abs(n * 2.0 - 1.0)


def normalise(a):
    return (a - a.min()) / (a.max() - a.min())


def blur(mask, radius):
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255.0


def slope_of(h, world_size, height_range):
    rows, cols = h.shape
    gz, gx = np.gradient(h * height_range)
    gx /= world_size[0] / cols
    gz /= world_size[1] / rows
    return np.sqrt(gx * gx + gz * gz)


def make_island(rng, res):
    h, w = res
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xx / w - 0.5) * 2.0
    dy = (yy / h - 0.5) * 2.0
    warp = fbm(res, 2.6, rng) - 0.5
    dist = np.sqrt(dx * dx + dy * dy) + warp * 0.35
    falloff = np.clip(1.0 - dist ** 2.2, 0.0, 1.0)
    base = fbm(res, 2.4, rng)
    mountains = ridged(fbm(res, 2.1, rng)) ** 2.0
    detail = fbm(res, 1.6, rng)
    height = falloff * (0.55 * base + 0.55 * mountains * falloff) + 0.04 * detail
    return normalise(height), 0.38  # height, water fraction


def make_valley(rng, res):
    h, w = res
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / h
    meander = (fbm(res, 3.2, rng) - 0.5) * 0.35
    valley = np.abs((v - 0.5) + meander)  # 0 along the river line
    ranges = np.clip(valley * 2.2, 0, 1) ** 1.4
    mountains = ridged(fbm(res, 2.0, rng)) ** 1.8
    base = fbm(res, 2.5, rng)
    height = 0.15 + 0.55 * ranges * (0.5 + 0.8 * mountains) + 0.25 * base * ranges + 0.03 * fbm(res, 1.5, rng)
    height -= np.exp(-(valley / 0.02) ** 2) * 0.12  # carve the river
    return normalise(height), 0.10


def write_map(name, title, res, world_size, height_range, maker, seed):
    rng = np.random.default_rng(seed)
    height, water_fraction = maker(rng, res)
    sea_level = float(np.quantile(height, water_fraction))
    # Gaea would derive these from erosion/flow data; here we use simple land-relative rules.
    slope = slope_of(blur(height, 6), world_size, height_range)
    moisture = fbm(res, 2.2, rng)
    land = height >= sea_level
    rock_slope = float(np.quantile(slope[land], 0.82))
    snow_line = float(np.quantile(height[land], 0.93))
    beach_top = sea_level + (snow_line - sea_level) * 0.04

    water = (~land).astype(np.float32)
    sand = (land & (height < beach_top)).astype(np.float32)
    rock = (land & (slope > rock_slope)).astype(np.float32)
    snow = (land & (height > snow_line)).astype(np.float32)
    forest = (land & (moisture > 0.5) & (height > beach_top) & (height < snow_line * 0.85) & (slope <= rock_slope)).astype(np.float32)

    out = ROOT / name
    out.mkdir(parents=True, exist_ok=True)
    (np.clip(height, 0, 1) * 65535).astype("<u2").tofile(out / "heightmap.r16")
    masks = {"water": water, "sand": sand, "rock": rock, "snow": snow, "forest": forest}
    for mask_name, mask in masks.items():
        m = blur(mask, 2)
        Image.fromarray((m * 255).astype(np.uint8), "L").save(out / f"{mask_name}.png", optimize=True)

    meta = {
        "name": title,
        "world_size": list(world_size),
        "height_range": height_range,
        "sea_level": round(sea_level, 4),
        "heightmap": {"file": "heightmap.r16", "format": "r16", "width": res[1], "height": res[0]},
        "masks": {k: f"{k}.png" for k in masks},
        "source": "placeholder (tools/make_placeholder_terrain.py)",
    }
    (out / "map.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {out}  {res[1]}x{res[0]} px, {world_size[0]}x{world_size[1]} m, sea level {sea_level:.3f}")


if __name__ == "__main__":
    write_map("placeholder_island", "Placeholder Island", (1024, 1024), (2048, 2048), 260.0, make_island, 7)
    write_map("placeholder_valley", "Placeholder Valley", (512, 1024), (3072, 1536), 320.0, make_valley, 11)
