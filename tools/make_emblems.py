"""Draws the charges for clan emblems into assets/emblems (white silhouettes on transparent,
256 px): raven, wolf, longship, crossed axes, world tree, serpent, valknut, sun wheel, Thor's
hammer and boar. shaders/include/emblem.gdshaderinc paints them onto banners and shields in
the clan's colours (scripts/game/emblem.gd).

    python tools/make_emblems.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "emblems")
S = 1024
W = (255, 255, 255, 255)


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def P(pts):
    return [(x * S, y * S) for x, y in pts]


def ell(d, cx, cy, rx, ry, fill=W):
    d.ellipse(((cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S), fill=fill)


def thick_line(d, pts, w):
    d.line(P(pts), fill=W, width=int(w * S), joint="curve")
    for x, y in pts[:1] + pts[-1:]:
        ell(d, x, y, w / 2, w / 2)


def raven():
    im, d = canvas()
    # Wings spread, body, head turned, beak, fanned tail.
    d.polygon(P([(0.5, 0.42), (0.08, 0.2), (0.14, 0.32), (0.06, 0.36), (0.16, 0.44), (0.1, 0.5), (0.24, 0.54), (0.42, 0.56)]), fill=W)
    d.polygon(P([(0.5, 0.42), (0.92, 0.2), (0.86, 0.32), (0.94, 0.36), (0.84, 0.44), (0.9, 0.5), (0.76, 0.54), (0.58, 0.56)]), fill=W)
    ell(d, 0.5, 0.52, 0.11, 0.18)
    ell(d, 0.5, 0.3, 0.08, 0.08)
    d.polygon(P([(0.44, 0.28), (0.3, 0.33), (0.45, 0.34)]), fill=W)
    d.polygon(P([(0.44, 0.66), (0.56, 0.66), (0.64, 0.88), (0.5, 0.82), (0.36, 0.88)]), fill=W)
    d.polygon(P([(0.44, 0.7), (0.4, 0.78), (0.47, 0.75)]), fill=W)
    return im


def wolf():
    im, d = canvas()
    # A wolf's head in profile, snarling, ears up, a ruff of fur.
    d.polygon(P([(0.2, 0.86), (0.26, 0.6), (0.32, 0.42), (0.36, 0.2), (0.44, 0.34), (0.5, 0.16), (0.56, 0.36), (0.7, 0.42),
                 (0.86, 0.5), (0.9, 0.56), (0.84, 0.6), (0.7, 0.6), (0.82, 0.64), (0.74, 0.7), (0.6, 0.68), (0.62, 0.8), (0.52, 0.88),
                 (0.44, 0.84), (0.36, 0.9), (0.3, 0.84)]), fill=W)
    ell(d, 0.56, 0.46, 0.025, 0.02, fill=(0, 0, 0, 0))
    return im


def longship():
    im, d = canvas()
    # The hull: a curved crescent, dragon prow, curled stern, shields, mast and a striped sail.
    hull = []
    for i in range(41):
        t = i / 40
        x = 0.12 + 0.76 * t
        y = 0.66 + 0.12 * math.sin(t * math.pi)
        hull.append((x, y))
    top = [(0.88, 0.6), (0.9, 0.42), (0.86, 0.34), (0.94, 0.3), (0.95, 0.36), (0.92, 0.44), (0.93, 0.58)]
    d.polygon(P([(0.1, 0.56), (0.12, 0.66)] + hull + [(0.88, 0.66)] + list(reversed(top)) + [(0.86, 0.58), (0.14, 0.58), (0.08, 0.44), (0.06, 0.48)]), fill=W)
    thick_line(d, [(0.09, 0.47), (0.05, 0.38), (0.1, 0.34)], 0.035)
    d.rectangle(P([(0.485, 0.12), (0.515, 0.6)]), fill=W)
    d.polygon(P([(0.28, 0.16), (0.72, 0.16), (0.76, 0.5), (0.24, 0.5)]), fill=W)
    for i in range(3):
        d.rectangle(P([(0.3 + i * 0.15, 0.18), (0.36 + i * 0.15, 0.48)]), fill=(0, 0, 0, 0))
    return im


def axes():
    im, d = canvas()
    for s in (-1, 1):
        # A handle across and a bearded blade at its top.
        x0, x1 = (0.5 - s * 0.36, 0.5 + s * 0.3)
        thick_line(d, [(x0, 0.88), (x1, 0.14)], 0.055)
        bx, by = 0.5 + s * 0.26, 0.24
        d.polygon(P([(bx, by - 0.08), (bx + s * 0.2, by - 0.16), (bx + s * 0.22, by + 0.1), (bx + s * 0.04, by + 0.16), (bx - s * 0.02, by + 0.04)]), fill=W)
    return im


def tree():
    im, d = canvas()
    # The world tree: a trunk, spreading branches in a round crown, roots below.
    d.polygon(P([(0.45, 0.78), (0.47, 0.45), (0.53, 0.45), (0.55, 0.78)]), fill=W)
    for cx, cy, r in [(0.5, 0.3, 0.2), (0.32, 0.38, 0.14), (0.68, 0.38, 0.14), (0.38, 0.22, 0.13), (0.62, 0.22, 0.13), (0.5, 0.14, 0.11)]:
        ell(d, cx, cy, r, r * 0.9)
    for s in (-1, 1):
        thick_line(d, [(0.5, 0.74), (0.5 + s * 0.14, 0.82), (0.5 + s * 0.3, 0.86)], 0.04)
        thick_line(d, [(0.5, 0.76), (0.5 + s * 0.08, 0.9)], 0.035)
    thick_line(d, [(0.2, 0.88), (0.8, 0.88)], 0.03)
    return im


def serpent():
    im, d = canvas()
    # The world serpent in a ring, biting its tail.
    pts = []
    for i in range(80):
        a = math.pi * 0.62 + i / 79 * math.pi * 1.85
        pts.append((0.5 + 0.32 * math.cos(a), 0.52 + 0.32 * math.sin(a)))
    for i in range(len(pts) - 1):
        w = 0.03 + 0.07 * (i / len(pts))
        d.line(P([pts[i], pts[i + 1]]), fill=W, width=int(w * S))
        ell(d, pts[i][0], pts[i][1], w / 2, w / 2)
    hx, hy = pts[-1]
    d.polygon(P([(hx - 0.06, hy - 0.06), (hx + 0.08, hy - 0.08), (hx + 0.14, hy - 0.01), (hx + 0.06, hy + 0.06), (hx - 0.05, hy + 0.05)]), fill=W)
    return im


def valknut():
    im, d = canvas()
    # Three interlocked triangles, outlined.
    for k in range(3):
        cx = 0.5 + 0.12 * math.cos(math.pi / 2 + k * 2 * math.pi / 3)
        cy = 0.55 - 0.12 * math.sin(math.pi / 2 + k * 2 * math.pi / 3)
        tri = [(cx + 0.3 * math.cos(-math.pi / 2 + j * 2 * math.pi / 3), cy + 0.3 * math.sin(-math.pi / 2 + j * 2 * math.pi / 3)) for j in range(3)]
        d.line(P(tri + [tri[0]]), fill=W, width=int(0.05 * S), joint="curve")
    return im


def sun_wheel():
    im, d = canvas()
    # A sun wheel: ring, four arms, a hub.
    d.ellipse(P([(0.14, 0.14), (0.86, 0.86)]), outline=W, width=int(0.07 * S))
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        thick_line(d, [(0.5, 0.5), (0.5 + 0.34 * math.cos(ang), 0.5 + 0.34 * math.sin(ang))], 0.07)
    ell(d, 0.5, 0.5, 0.1, 0.1)
    for a in range(8):
        ang = a * math.pi / 4
        x, y = 0.5 + 0.44 * math.cos(ang), 0.5 + 0.44 * math.sin(ang)
        ell(d, x, y, 0.035, 0.035)
    return im


def hammer():
    im, d = canvas()
    # Mjolnir: a broad flared head, a short handle, a ring at its end.
    d.polygon(P([(0.18, 0.2), (0.82, 0.2), (0.78, 0.3), (0.86, 0.42), (0.6, 0.44), (0.56, 0.4), (0.44, 0.4), (0.4, 0.44), (0.14, 0.42), (0.22, 0.3)]), fill=W)
    d.rectangle(P([(0.45, 0.4), (0.55, 0.76)]), fill=W)
    d.ellipse(P([(0.4, 0.74), (0.6, 0.9)]), outline=W, width=int(0.04 * S))
    for x in (0.3, 0.5, 0.7):
        ell(d, x, 0.31, 0.025, 0.025, fill=(0, 0, 0, 0))
    return im


def boar():
    im, d = canvas()
    # A boar standing: humped back with bristles, snout, tusk, legs.
    d.polygon(P([(0.14, 0.52), (0.2, 0.4), (0.34, 0.3), (0.52, 0.26), (0.7, 0.32), (0.82, 0.44), (0.92, 0.5), (0.9, 0.56), (0.8, 0.6),
                 (0.72, 0.62), (0.3, 0.64), (0.18, 0.6)]), fill=W)
    for i in range(7):
        x = 0.3 + i * 0.06
        d.polygon(P([(x, 0.3 - 0.01 * abs(i - 3)), (x + 0.03, 0.2 + 0.01 * abs(i - 3)), (x + 0.06, 0.3 - 0.01 * abs(i - 3))]), fill=W)
    for x in (0.24, 0.36, 0.64, 0.74):
        d.rectangle(P([(x, 0.6), (x + 0.06, 0.8)]), fill=W)
    d.polygon(P([(0.86, 0.56), (0.9, 0.46), (0.84, 0.5)]), fill=(0, 0, 0, 0))
    d.polygon(P([(0.84, 0.58), (0.8, 0.46), (0.86, 0.5)]), fill=W)
    thick_line(d, [(0.14, 0.5), (0.08, 0.44), (0.1, 0.38)], 0.025)
    return im


CHARGES = {"raven": raven, "wolf": wolf, "longship": longship, "axes": axes, "tree": tree, "serpent": serpent,
           "valknut": valknut, "sun_wheel": sun_wheel, "hammer": hammer, "boar": boar}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in CHARGES.items():
        im = fn().filter(ImageFilter.GaussianBlur(1.2))
        im.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print(len(CHARGES), "charges in", OUT)


if __name__ == "__main__":
    main()
