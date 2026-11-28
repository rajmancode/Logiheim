"""The top bar's badges: bold, high-contrast icons that read on the dark bar at a glance.

    python tools/make_hud_icons.py <renders>      (renders from tools/render_game_icons.gd)

Writes assets/icons/hud/<id>.png: a glossy disc in a vivid colour of its own (no two alike in
the bar), ringed white then near-black so it stands off both dark and light backgrounds, with
the model on it cut out like a sticker - a white outline and a dark hairline round it.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 96
SS = 4

# id: (render folder, render name, colour). The bar's own stats first, then the goods.
BADGES = {
    "people": ("buildings", "longhouse", (52, 112, 214)),
    "content": ("goods", "jewellery", (222, 74, 128)),
    "influence": ("goods", "influence", (146, 72, 218)),
    "store": ("buildings", "warehouse", (28, 160, 166)),
    "food": ("goods", "bread", (236, 126, 30)),
    "wood": ("goods", "wood", (58, 158, 62)),
    "stone": ("goods", "stone", (96, 104, 196)),
    "tools": ("goods", "tools", (200, 56, 52)),
    "silver": ("goods", "silver", (30, 92, 168)),
}


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fit(render, box):
    bb = render.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = render.crop(bb) if bb else render
    s = min(box / im.width, box / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def sticker(im, white, dark):
    """The model with a white outline and a dark hairline round that."""
    pad = white + dark + 2
    a = Image.new("L", (im.width + pad * 2, im.height + pad * 2), 0)
    a.paste(im.getchannel("A").point(lambda v: 255 if v > 60 else 0), (pad, pad))
    w = a.filter(ImageFilter.MaxFilter(white * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    d = w.filter(ImageFilter.MaxFilter(dark * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.new("RGBA", a.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", a.size, (24, 16, 10, 255)), (0, 0), d)
    out.paste(Image.new("RGBA", a.size, (255, 252, 244, 255)), (0, 0), w)
    out.alpha_composite(im, (pad, pad))
    return out


def badge(col, render):
    S = SIZE * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    m = int(S * 0.02)
    d.ellipse((m, m, S - m, S - m), fill=(16, 10, 6, 255))
    wr = int(S * 0.055)
    d.ellipse((m + wr * 0.6, m + wr * 0.6, S - m - wr * 0.6, S - m - wr * 0.6), fill=(255, 246, 222, 255))
    # The face: the colour, light at the top and deep at the bottom.
    face = Image.new("RGBA", (S, S))
    fp = ImageDraw.Draw(face)
    top, bot = mix(col, (255, 255, 255), 0.28), mix(col, (0, 0, 0), 0.38)
    for y in range(S):
        fp.line((0, y, S, y), fill=mix(top, bot, y / S) + (255,))
    mask = Image.new("L", (S, S), 0)
    fm = m + wr * 1.6
    ImageDraw.Draw(mask).ellipse((fm, fm, S - fm, S - fm), fill=255)
    out.paste(face, (0, 0), mask)
    # A gloss across the top half.
    gl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gl).ellipse((S * 0.2, fm + S * 0.02, S * 0.8, S * 0.46), fill=70)
    gl = gl.filter(ImageFilter.GaussianBlur(S * 0.03))
    out.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), Image.composite(gl, Image.new("L", (S, S), 0), mask))
    out = out.resize((SIZE, SIZE), Image.LANCZOS)
    im = sticker(fit(render, int(SIZE * 0.7)), 3, 1)
    out.alpha_composite(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2 + 1))
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "icon_renders")
    dst = os.path.join(ROOT, "assets", "icons", "hud")
    os.makedirs(dst, exist_ok=True)
    for bid, (folder, name, col) in BADGES.items():
        render = Image.open(os.path.join(src, folder, name + ".png")).convert("RGBA")
        badge(col, render).save(os.path.join(dst, bid + ".png"))
    print("wrote", len(BADGES), "badges to", dst)


if __name__ == "__main__":
    main()
