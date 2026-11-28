"""Draws the interface's frames and buttons into assets/ui (nine-patch PNGs, used by
scripts/ui_style.gd): smoked oak panels with a double gold border and knotwork corners, bronze
buttons in four states, tabs, gilded cards, parchment tooltips, bars, ornamental rules, the top
bar's band and the banner for messages.

    python tools/make_ui_textures.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
SS = 4

GOLD = (214, 172, 86)
GOLD_HI = (250, 226, 150)
GOLD_LO = (120, 86, 36)
OAK = (30, 21, 14)
OAK_HI = (54, 39, 26)
INK = (10, 7, 4)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def wood(w, h, base, hi, alpha=255, seed=1):
    """Dark wood: long grain lines and a soft vignette."""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (w, h), base + (alpha,))
    d = ImageDraw.Draw(im)
    for _ in range(int(h * 0.9)):
        y = rnd.uniform(0, h)
        amp = rnd.uniform(0.5, 3.0) * SS
        freq = rnd.uniform(0.004, 0.012) / SS
        ph = rnd.uniform(0, 6.3)
        col = lerp(base, hi, rnd.uniform(0.0, 0.8))
        pts = [(x, y + math.sin(x * freq * 6.28 + ph) * amp) for x in range(0, w + 8, 8)]
        d.line(pts, fill=col + (alpha,), width=max(1, int(rnd.uniform(1, 3) * SS / 2)))
    im = im.filter(ImageFilter.GaussianBlur(SS * 0.6))
    # Vignette: darker towards the edges.
    v = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(v)
    for i in range(40):
        t = i / 40.0
        inset = int(min(w, h) * 0.5 * t)
        vd.rectangle((inset, inset, w - inset, h - inset), fill=int(255 * (t ** 0.5)))
    v = v.filter(ImageFilter.GaussianBlur(min(w, h) * 0.08))
    dark = Image.new("RGBA", (w, h), INK + (alpha,))
    return Image.composite(im, dark, v.point(lambda p: int(110 + p * 145 / 255)))


def bevel_rect(d, box, width, col_hi, col, col_lo):
    x0, y0, x1, y1 = box
    for i in range(width):
        t = i / max(width - 1, 1)
        c = lerp(col_hi, col_lo, t) if i < width / 2 else lerp(col, col_lo, t)
        d.rectangle((x0 + i, y0 + i, x1 - i, y1 - i), outline=c + (255,))


def gold_frame(im, inset, width, inner_line=True):
    d = ImageDraw.Draw(im)
    w, h = im.size
    # A dark keyline, the gold band with a light top-left and dark bottom-right, a fine inner line.
    d.rectangle((inset - SS, inset - SS, w - inset + SS - 1, h - inset + SS - 1), outline=INK + (255,), width=SS)
    for i in range(width):
        t = i / max(width - 1, 1)
        c = lerp(GOLD_HI, GOLD_LO, abs(t - 0.3) / 0.7)
        d.rectangle((inset + i, inset + i, w - inset - i - 1, h - inset - i - 1), outline=c + (255,))
    if inner_line:
        k = inset + width + 5 * SS
        d.rectangle((k, k, w - k - 1, h - k - 1), outline=GOLD_LO + (200,), width=SS)


def knot(d, cx, cy, r):
    """A corner ornament: a gold diamond with a ring and a dark stud."""
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    d.polygon(pts, fill=GOLD + (255,), outline=INK + (255,))
    pts2 = [(cx, cy - r * 0.6), (cx + r * 0.6, cy), (cx, cy + r * 0.6), (cx - r * 0.6, cy)]
    d.polygon(pts2, fill=GOLD_LO + (255,))
    d.ellipse((cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42), outline=GOLD_HI + (255,), width=max(1, int(r * 0.12)))
    d.ellipse((cx - r * 0.2, cy - r * 0.2, cx + r * 0.2, cy + r * 0.2), fill=(40, 24, 12, 255))
    d.ellipse((cx - r * 0.25, cy - r * 0.32, cx - r * 0.05, cy - r * 0.12), fill=GOLD_HI + (255,))


def save(im, name, size):
    im = im.resize(size, Image.LANCZOS)
    im.save(os.path.join(OUT, name))


def panel():
    S = 256 * SS
    im = wood(S, S, OAK, OAK_HI, 240, 3)
    gold_frame(im, 6 * SS, 5 * SS)
    d = ImageDraw.Draw(im)
    for cx, cy in [(14, 14), (242, 14), (14, 242), (242, 242)]:
        knot(d, cx * SS, cy * SS, 11 * SS)
    save(im, "panel.png", (256, 256))


def button(name, fill_top, fill_bot, rim, glow=0.0, inset=False, alpha=255):
    W, H = 96 * SS, 48 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = 7 * SS
    # The plate: a vertical gradient, rounded.
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    for y in range(H):
        t = y / H
        if inset:
            t = 1.0 - t
        gd.line((0, y, W, y), fill=lerp(fill_top, fill_bot, t) + (alpha,))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H - 2 * SS), r, fill=255)
    im.paste(grad, (0, 0), mask)
    if glow > 0:
        g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(g).rounded_rectangle((4 * SS, 4 * SS, W - 4 * SS, H - 4 * SS), r, outline=GOLD_HI + (int(160 * glow),), width=5 * SS)
        g = g.filter(ImageFilter.GaussianBlur(3 * SS))
        im.alpha_composite(g)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H - 2 * SS), r, outline=INK + (255,), width=SS)
    d.rounded_rectangle((3 * SS, 3 * SS, W - 3 * SS, H - 3 * SS), r, outline=rim + (255,), width=2 * SS)
    # A highlight along the top edge.
    if not inset:
        d.line((r + 3 * SS, 6 * SS, W - r - 3 * SS, 6 * SS), fill=lerp(rim, (255, 255, 255), 0.4) + (110,), width=SS)
    save(im, name, (96, 48))


def tab(name, active):
    W, H = 96 * SS, 40 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r = 8 * SS
    plate = wood(W, H, (52, 36, 20) if active else (24, 17, 11), (80, 58, 34) if active else (40, 29, 19), 250, 7)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H + r), r, fill=255)
    im.paste(plate, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H + r), r, outline=(GOLD_HI if active else GOLD_LO) + (255,), width=(2 if active else 1) * SS)
    if active:
        d.line((r, 5 * SS, W - r, 5 * SS), fill=GOLD_HI + (140,), width=SS)
    save(im, name, (96, 40))


def card(name, rim_w, glow):
    S = 128 * SS
    im = wood(S, S, (36, 26, 17), (60, 44, 28), 245, 11)
    if glow > 0:
        g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(g).rectangle((8 * SS, 8 * SS, S - 8 * SS, S - 8 * SS), outline=GOLD_HI + (int(200 * glow),), width=8 * SS)
        g = g.filter(ImageFilter.GaussianBlur(5 * SS))
        im.alpha_composite(g)
    gold_frame(im, 4 * SS, rim_w * SS, inner_line=False)
    d = ImageDraw.Draw(im)
    for cx, cy in [(9, 9), (119, 9), (9, 119), (119, 119)]:
        d.ellipse(((cx - 4) * SS, (cy - 4) * SS, (cx + 4) * SS, (cy + 4) * SS), fill=GOLD + (255,), outline=INK + (255,), width=SS)
        d.ellipse(((cx - 1.5) * SS, (cy - 2) * SS, (cx + 0.5) * SS, cy * SS), fill=GOLD_HI + (255,))
    save(im, name, (128, 128))


def tooltip():
    S = 96 * SS
    rnd = random.Random(5)
    im = Image.new("RGBA", (S, S), (236, 220, 184, 250))
    d = ImageDraw.Draw(im)
    for _ in range(900):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        c = lerp((236, 220, 184), (196, 170, 120), rnd.uniform(0, 0.6))
        d.ellipse((x, y, x + rnd.uniform(2, 9) * SS, y + rnd.uniform(2, 9) * SS), fill=c + (250,))
    im = im.filter(ImageFilter.GaussianBlur(2 * SS))
    v = Image.new("L", (S, S), 0)
    ImageDraw.Draw(v).rectangle((10 * SS, 10 * SS, S - 10 * SS, S - 10 * SS), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(9 * SS))
    burnt = Image.new("RGBA", (S, S), (150, 108, 60, 250))
    im = Image.composite(im, burnt, v)
    d = ImageDraw.Draw(im)
    d.rectangle((SS, SS, S - SS - 1, S - SS - 1), outline=(70, 44, 20, 255), width=2 * SS)
    d.rectangle((5 * SS, 5 * SS, S - 5 * SS - 1, S - 5 * SS - 1), outline=(120, 84, 40, 200), width=SS)
    save(im, "tooltip.png", (96, 96))


def bar(name, fill):
    W, H = 64 * SS, 16 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if fill:
        for y in range(H):
            t = y / H
            c = lerp((255, 255, 255), (150, 150, 150), t) if t > 0.35 else lerp((255, 255, 255), (220, 220, 220), t / 0.35)
            d.line((0, y, W, y), fill=c + (255,))
        d.line((3 * SS, 3 * SS, W - 3 * SS, 3 * SS), fill=(255, 255, 255, 200), width=SS)
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).rounded_rectangle((SS, SS, W - SS, H - SS), 5 * SS, fill=255)
        out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        out.paste(im, (0, 0), mask)
        im = out
    else:
        d.rounded_rectangle((0, 0, W - 1, H - 1), 6 * SS, fill=(12, 9, 6, 235), outline=GOLD_LO + (255,), width=SS)
        d.line((5 * SS, 3 * SS, W - 5 * SS, 3 * SS), fill=(0, 0, 0, 180), width=2 * SS)
    save(im, name, (64, 16))


def rule():
    W, H = 512 * SS, 24 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cy = H // 2
    for x in range(0, W // 2 - 20 * SS):
        t = x / (W / 2)
        a = int(255 * min(1.0, t * 3.0))
        th = 1.0 + 1.5 * t
        d.line((x, cy - th * SS / 2, x, cy + th * SS / 2), fill=GOLD + (a,))
        d.line((W - x, cy - th * SS / 2, W - x, cy + th * SS / 2), fill=GOLD + (a,))
    knot(d, W // 2, cy, 10 * SS)
    for s in (-1, 1):
        x = W // 2 + s * 22 * SS
        d.polygon([(x, cy - 4 * SS), (x + s * 6 * SS, cy), (x, cy + 4 * SS), (x - s * 6 * SS, cy)], fill=GOLD + (255,))
    save(im, "rule.png", (512, 24))


def topbar():
    W, H = 512 * SS, 64 * SS
    im = wood(W, H, (24, 17, 11), (44, 32, 21), 245, 13)
    d = ImageDraw.Draw(im)
    # A gold edge along the bottom with a dark line under it, a fine line along the top.
    d.rectangle((0, H - 5 * SS, W, H - 1), fill=GOLD + (255,))
    d.line((0, H - 5 * SS, W, H - 5 * SS), fill=GOLD_HI + (255,), width=SS)
    d.line((0, H - 1 * SS, W, H - 1 * SS), fill=INK + (255,), width=SS)
    d.line((0, 2 * SS, W, 2 * SS), fill=GOLD_LO + (200,), width=SS)
    for x in range(40, 512, 64):
        knot(d, x * SS, H - 3 * SS, 5 * SS)
    save(im, "topbar.png", (512, 64))


def chip():
    W, H = 64 * SS, 40 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((SS, SS, W - SS, H - SS), 18 * SS, fill=(14, 10, 7, 220), outline=GOLD_LO + (255,), width=SS)
    d.line((14 * SS, 4 * SS, W - 14 * SS, 4 * SS), fill=(255, 255, 255, 30), width=SS)
    save(im, "chip.png", (64, 40))


def banner():
    W, H = 640 * SS, 72 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = wood(W, H, (40, 14, 10), (72, 26, 18), 235, 17)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    notch = 28 * SS
    md.polygon([(0, 6 * SS), (W, 6 * SS), (W - notch, H // 2), (W, H - 6 * SS), (0, H - 6 * SS), (notch, H // 2)], fill=255)
    im.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(im)
    for y in (10 * SS, H - 10 * SS):
        d.line((notch, y, W - notch, y), fill=GOLD + (230,), width=2 * SS)
    save(im, "banner.png", (640, 72))


def main():
    os.makedirs(OUT, exist_ok=True)
    panel()
    button("button.png", (62, 44, 26), (30, 21, 13), GOLD_LO)
    button("button_hover.png", (92, 66, 36), (46, 32, 18), GOLD, glow=0.6)
    button("button_pressed.png", (140, 100, 44), (84, 58, 24), GOLD_HI, glow=0.3, inset=True)
    button("button_disabled.png", (38, 34, 30), (24, 22, 20), (80, 70, 56), alpha=210)
    tab("tab.png", False)
    tab("tab_active.png", True)
    card("card.png", 2, 0.0)
    card("card_hover.png", 3, 0.7)
    card("card_active.png", 4, 1.0)
    tooltip()
    bar("bar_bg.png", False)
    bar("bar_fill.png", True)
    rule()
    topbar()
    chip()
    banner()
    print("ui textures in", OUT)


if __name__ == "__main__":
    main()
