"""Frames the renders from tools/render_game_icons.gd into the game's icons.

    godot --path . -s tools/render_game_icons.gd -- <renders>
    python tools/make_game_icons.py <renders>

Writes
  assets/icons/buildings/<id>.png - a rounded tile framed in the build-menu category's colour
      (harvest green, crafts violet, people blue, military red) with the building's own model
      on it, and a small coin in the corner with the good it gives, so look-alike huts still
      tell apart at a glance;
  assets/icons/goods/<id>.png - a round coin in the good's colour with the good's model on it
      (the stock bar, costs, what a building uses and makes, and the +N pops over buildings).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128
SS = 4  # supersampling for smooth edges

CATEGORY = {
    "harvest": (88, 150, 70),
    "crafts": (128, 92, 168),
    "people": (70, 112, 170),
    "military": (170, 62, 52),
}


def hexcol(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fit(render, box):
    """The render cropped to what is drawn and scaled to fit in a box (w, h)."""
    bb = render.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = render.crop(bb) if bb else render
    s = min(box[0] / im.width, box[1] / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def shadowed(canvas, im, pos, blur):
    """Paste with a soft drop shadow under it."""
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sh.putalpha(im.getchannel("A").point(lambda v: int(v * 0.55)))
    pad = blur * 3
    big = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    big.alpha_composite(sh, (pad, pad))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(big, (pos[0] - pad + blur // 2, pos[1] - pad + blur))
    canvas.alpha_composite(im, pos)


def radial(size, inner, outer):
    """A disc-shaped gradient fill, lighter towards the upper left."""
    g = Image.new("RGBA", (size, size))
    px = g.load()
    cx, cy = size * 0.38, size * 0.32
    for y in range(size):
        for x in range(size):
            d = min(1.0, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / (size * 0.85))
            px[x, y] = mix(inner, outer, d) + (255,)
    return g


def coin(size, col, render=None):
    """A round coin: dark rim, a lighter ring, a face in the good's colour, the model on it."""
    S = size * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = int(S * 0.03)
    rim = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rim).ellipse((m, m, S - m, S - m), fill=255)
    dark = mix(col, (20, 18, 16), 0.72)
    out.paste(Image.new("RGBA", (S, S), dark + (255,)), (0, 0), rim)
    ring = int(S * 0.075)
    face_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(face_mask).ellipse((m + ring, m + ring, S - m - ring, S - m - ring), fill=255)
    face = radial(S, mix(col, (255, 255, 255), 0.35), mix(col, (30, 28, 26), 0.45))
    out.paste(face, (0, 0), face_mask)
    # A thin bright edge on the ring, catching the light at the top.
    d = ImageDraw.Draw(out)
    lw = max(2, S // 64)
    d.arc((m + lw, m + lw, S - m - lw, S - m - lw), 200, 340, fill=mix(col, (255, 255, 255), 0.6) + (255,), width=lw)
    d.ellipse((m + ring, m + ring, S - m - ring, S - m - ring), outline=mix(col, (0, 0, 0), 0.55) + (255,), width=lw)
    out = out.resize((size, size), Image.LANCZOS)
    if render is not None:
        inner = int(size * 0.70)
        im = fit(render, (inner, inner))
        shadowed(out, im, ((size - im.width) // 2, (size - im.height) // 2 + int(size * 0.02)), max(1, size // 40))
    return out


def tile(size, col, render):
    """A rounded square framed in the category colour, the building on a sky-to-ground field."""
    S = size * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    r = int(S * 0.2)
    m = int(S * 0.02)
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((m, m, S - m, S - m), r, fill=mix(col, (16, 14, 12), 0.55) + (255,))
    fw = int(S * 0.06)
    d.rounded_rectangle((m + fw * 0.4, m + fw * 0.4, S - m - fw * 0.4, S - m - fw * 0.4), r - fw * 0.4, fill=col + (255,))
    inner = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inner).rounded_rectangle((m + fw, m + fw, S - m - fw, S - m - fw), r - fw, fill=255)
    field = Image.new("RGBA", (S, S))
    fp = ImageDraw.Draw(field)
    top, bot = (206, 218, 226), (104, 112, 92)
    for y in range(S):
        fp.line((0, y, S, y), fill=mix(top, bot, (y / S) ** 1.3) + (255,))
    out.paste(field, (0, 0), inner)
    d.rounded_rectangle((m + fw, m + fw, S - m - fw, S - m - fw), r - fw, outline=mix(col, (0, 0, 0), 0.5) + (255,), width=max(2, S // 96))
    out = out.resize((size, size), Image.LANCZOS)
    im = fit(render, (int(size * 0.8), int(size * 0.76)))
    shadowed(out, im, ((size - im.width) // 2, int(size * 0.53 - im.height / 2)), max(1, size // 48))
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "icon_renders")
    man = json.load(open(os.path.join(src, "manifest.json"), encoding="utf-8"))
    gdir = os.path.join(ROOT, "assets", "icons", "goods")
    bdir = os.path.join(ROOT, "assets", "icons", "buildings")
    os.makedirs(gdir, exist_ok=True)
    os.makedirs(bdir, exist_ok=True)
    goods = {}
    for gid, info in man["goods"].items():
        render = Image.open(os.path.join(src, "goods", gid + ".png")).convert("RGBA")
        c = coin(SIZE, hexcol(info["color"]), render)
        c.save(os.path.join(gdir, gid + ".png"))
        goods[gid] = c
    for bid, info in man["buildings"].items():
        render = Image.open(os.path.join(src, "buildings", bid + ".png")).convert("RGBA")
        t = tile(SIZE, CATEGORY.get(info["category"], (120, 120, 120)), render)
        p = info.get("product", "")
        if p in goods:
            b = int(SIZE * 0.42)
            small = goods[p].resize((b, b), Image.LANCZOS)
            t.alpha_composite(small, (SIZE - b - 1, SIZE - b - 1))
        t.save(os.path.join(bdir, bid + ".png"))
    print("icons:", len(goods), "goods,", len(man["buildings"]), "buildings")


if __name__ == "__main__":
    main()
