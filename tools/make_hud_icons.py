"""The top bar's badges: bold, flat glyphs that read on the dark bar at a glance.

    python tools/make_hud_icons.py

Writes assets/icons/hud/<id>.png: a glossy disc in a vivid colour of its own (no two alike in
the bar), ringed white then near-black so it stands off dark and light backgrounds alike, with
a plain white symbol on it (a dark shadow under it) - a person, a smile, a crown, a storehouse,
a fork and knife, logs, a stone block, a hammer - and for silver, a struck silver coin.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 96
SS = 8
S = SIZE * SS
W = (255, 255, 255, 255)

COLOURS = {
    "people": (52, 112, 214),
    "content": (222, 74, 128),
    "influence": (146, 72, 218),
    "store": (28, 150, 160),
    "food": (232, 118, 26),
    "wood": (60, 150, 62),
    "stone": (104, 110, 128),
    "tools": (200, 52, 48),
    "silver": (36, 70, 140),
}


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def P(x, y):
    """Glyph coordinates (-1..1 across the face) to pixels."""
    return (S / 2 + x * S * 0.30, S / 2 + y * S * 0.30)


def poly(d, pts, fill=W):
    d.polygon([P(x, y) for x, y in pts], fill=fill)


def rect(d, x0, y0, x1, y1, r=0.0, fill=W):
    a, b = P(x0, y0), P(x1, y1)
    d.rounded_rectangle((a[0], a[1], b[0], b[1]), r * S * 0.30, fill=fill)


def circle(d, x, y, r, fill=W):
    c = P(x, y)
    rr = r * S * 0.30
    d.ellipse((c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr), fill=fill)


def line(d, pts, w, fill=W):
    d.line([P(x, y) for x, y in pts], fill=fill, width=int(w * S * 0.30), joint="curve")
    for x, y in (pts[0], pts[-1]):
        circle(d, x, y, w / 2, fill)


def glyph(name, d):
    if name == "people":
        circle(d, 0, -0.52, 0.34)
        d.pieslice((*P(-0.72, -0.1), *P(0.72, 1.35)), 180, 360, fill=W)
        rect(d, -0.72, 0.6, 0.72, 0.78, 0.0)
    elif name == "content":
        circle(d, 0, 0, 0.92)
        k = (0, 0, 0, 0)
        circle(d, -0.32, -0.25, 0.13, k)
        circle(d, 0.32, -0.25, 0.13, k)
        d.arc((*P(-0.55, -0.45), *P(0.55, 0.55)), 25, 155, fill=k, width=int(0.15 * S * 0.3))
    elif name == "influence":
        poly(d, [(-0.85, 0.45), (-0.95, -0.55), (-0.45, -0.05), (0, -0.8), (0.45, -0.05), (0.95, -0.55), (0.85, 0.45)])
        rect(d, -0.85, 0.55, 0.85, 0.78, 0.05)
        for x, y in [(-0.95, -0.55), (0, -0.8), (0.95, -0.55)]:
            circle(d, x, y, 0.14)
    elif name == "store":
        poly(d, [(-0.95, -0.15), (0, -0.9), (0.95, -0.15)])
        rect(d, -0.75, -0.2, 0.75, 0.8)
        k = (0, 0, 0, 0)
        rect(d, -0.3, 0.15, 0.3, 0.8, 0.0, k)
        line(d, [(-0.3, 0.15), (0.3, 0.8)], 0.08)
        line(d, [(0.3, 0.15), (-0.3, 0.8)], 0.08)
    elif name == "food":
        # A fork on the left, a knife on the right.
        for x in (-0.68, -0.5, -0.32):
            line(d, [(x, -0.9), (x, -0.35)], 0.1)
        d.pieslice((*P(-0.74, -0.65), *P(-0.26, -0.05)), 0, 180, fill=W)
        line(d, [(-0.5, -0.2), (-0.5, 0.85)], 0.2)
        poly(d, [(0.32, -0.9), (0.6, -0.55), (0.62, 0.1), (0.32, 0.1)])
        d.pieslice((*P(0.02, -0.9), *P(0.62, -0.3)), 270, 360, fill=W)
        line(d, [(0.47, 0.05), (0.47, 0.85)], 0.2)
    elif name == "wood":
        for cx, cy in [(-0.45, 0.35), (0.45, 0.35), (0, -0.4)]:
            circle(d, cx, cy, 0.42)
            circle(d, cx, cy, 0.25, (0, 0, 0, 0))
            circle(d, cx, cy, 0.1)
    elif name == "stone":
        poly(d, [(-0.85, -0.1), (-0.35, -0.55), (0.85, -0.55), (0.35, -0.1)])
        poly(d, [(0.4, -0.02), (0.88, -0.47), (0.88, 0.45), (0.4, 0.85)], (236, 236, 236, 255))
        rect(d, -0.85, -0.02, 0.32, 0.85)
    elif name == "tools":
        # A hammer: a heavy head across the top, the haft down and to the left.
        a = math.radians(-35)
        def rot(x, y):
            return (x * math.cos(a) - y * math.sin(a) + 0.05, x * math.sin(a) + y * math.cos(a) + 0.05)
        poly(d, [rot(x, y) for x, y in [(-0.75, -0.95), (0.75, -0.95), (0.75, -0.45), (-0.75, -0.45)]])
        poly(d, [rot(x, y) for x, y in [(0.75, -0.85), (1.0, -0.8), (1.0, -0.6), (0.75, -0.55)]])
        poly(d, [rot(x, y) for x, y in [(-0.14, -0.5), (0.14, -0.5), (0.17, 0.95), (-0.17, 0.95)]])
        circle(d, *rot(0, 0.95), 0.17)


def silver_coin():
    """A struck silver coin, face on: bright rim, a raised cross between pellets."""
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    r0 = S * 0.37
    cx = cy = S / 2
    # Shading: light top-left to grey bottom-right.
    for i in range(80, 0, -1):
        t = i / 80
        r = r0 * t
        col = mix((250, 252, 255), (150, 158, 172), (1 - t) * 0.2 + 0.0)
        col = mix(col, (130, 138, 152), max(0.0, t - 0.6))
        d.ellipse((cx - r - (1 - t) * r0 * 0.12, cy - r - (1 - t) * r0 * 0.12, cx + r - (1 - t) * r0 * 0.12, cy + r - (1 - t) * r0 * 0.12), fill=col + (255,))
    d.ellipse((cx - r0, cy - r0, cx + r0, cy + r0), outline=(90, 96, 110, 255), width=int(S * 0.018))
    ri = r0 * 0.8
    d.ellipse((cx - ri, cy - ri, cx + ri, cy + ri), outline=(120, 128, 142, 255), width=int(S * 0.012))
    # Beads round the rim.
    for k in range(24):
        a = k / 24 * math.tau
        x, y = cx + math.cos(a) * r0 * 0.9, cy + math.sin(a) * r0 * 0.9
        rb = S * 0.008
        d.ellipse((x - rb, y - rb, x + rb, y + rb), fill=(120, 128, 142, 255))
    # A long cross with pellets in its angles.
    w = S * 0.045
    d.rectangle((cx - w, cy - ri * 0.8, cx + w, cy + ri * 0.8), fill=(118, 126, 140, 255))
    d.rectangle((cx - ri * 0.8, cy - w, cx + ri * 0.8, cy + w), fill=(118, 126, 140, 255))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = cx + sx * ri * 0.42, cy + sy * ri * 0.42
            rb = S * 0.028
            d.ellipse((x - rb, y - rb, x + rb, y + rb), fill=(118, 126, 140, 255))
    # A glint.
    d.arc((cx - r0 * 0.85, cy - r0 * 0.85, cx + r0 * 0.85, cy + r0 * 0.85), 200, 250, fill=(255, 255, 255, 255), width=int(S * 0.02))
    return c


def badge(name, col):
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    m = int(S * 0.02)
    d.ellipse((m, m, S - m, S - m), fill=(16, 10, 6, 255))
    wr = int(S * 0.055)
    d.ellipse((m + wr * 0.6, m + wr * 0.6, S - m - wr * 0.6, S - m - wr * 0.6), fill=(255, 246, 222, 255))
    face = Image.new("RGBA", (S, S))
    fp = ImageDraw.Draw(face)
    top, bot = mix(col, (255, 255, 255), 0.25), mix(col, (0, 0, 0), 0.35)
    for y in range(S):
        fp.line((0, y, S, y), fill=mix(top, bot, y / S) + (255,))
    mask = Image.new("L", (S, S), 0)
    fm = m + wr * 1.6
    ImageDraw.Draw(mask).ellipse((fm, fm, S - fm, S - fm), fill=255)
    out.paste(face, (0, 0), mask)
    gl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gl).ellipse((S * 0.2, fm + S * 0.02, S * 0.8, S * 0.44), fill=60)
    gl = gl.filter(ImageFilter.GaussianBlur(S * 0.03))
    out.paste(Image.new("RGBA", (S, S), W), (0, 0), Image.composite(gl, Image.new("L", (S, S), 0), mask))
    if name == "silver":
        sym = silver_coin()
    else:
        sym = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        glyph(name, ImageDraw.Draw(sym))
    # A dark drop shadow under the symbol so it stands off the face.
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(sym.getchannel("A").point(lambda v: int(v * 0.6)))
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.012))
    out.alpha_composite(sh, (int(S * 0.012), int(S * 0.02)))
    out.alpha_composite(sym)
    return out.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    dst = os.path.join(ROOT, "assets", "icons", "hud")
    os.makedirs(dst, exist_ok=True)
    for name, col in COLOURS.items():
        badge(name, col).save(os.path.join(dst, name + ".png"))
    print("wrote", len(COLOURS), "badges to", dst)


if __name__ == "__main__":
    main()
