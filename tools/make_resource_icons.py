"""Writes the resource icons (SVG) used by the map overlay.

Usage:
    python tools/make_resource_icons.py

Each icon is a badge with a simple white glyph, written to assets/icons/resources/<key>.svg.
Keys match NaturalResources.INFO. Every group has its own shape and colour, so groups tell
apart at a glance: core = green circle, precious = gold diamond, industry = violet rounded
square, wildlife = orange hexagon, norse = blue shield. Badges have a dark outline, a light rim
and a drop shadow so they stand out on any ground. cave.svg marks cave entrances.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "icons" / "resources"

GROUP_COLORS = {
    "core": "#2f9e44",
    "precious": "#e0a100",
    "industry": "#7048e8",
    "wildlife": "#e8590c",
    "norse": "#1971c2",
    "cave": "#2b2522",
}

# Badge outline per group (SVG element without fill/stroke attributes).
SHAPES = {
    "core": '<circle cx="64" cy="64" r="54"/>',
    "precious": '<polygon points="64,4 124,64 64,124 4,64"/>',
    "industry": '<rect x="10" y="10" width="108" height="108" rx="20"/>',
    "wildlife": '<polygon points="64,4 118,34 118,94 64,124 10,94 10,34"/>',
    "norse": '<path d="M12 12 H116 V58 C116 94 92 114 64 125 C36 114 12 94 12 58 Z"/>',
    "cave": '<polygon points="40,6 88,6 122,40 122,88 88,122 40,122 6,88 6,40"/>',
}
# Glyphs are drawn a little smaller on the pointier shapes so they stay inside.
GLYPH_SCALE = {"core": 0.92, "precious": 0.72, "industry": 0.9, "wildlife": 0.85, "norse": 0.82, "cave": 0.9}

W = 'fill="#ffffff"'
WS = 'fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"'

GLYPHS = {
    "timber": ("core", f'<polygon {W} points="40,30 24,68 56,68"/><polygon {W} points="64,22 46,72 82,72"/>'
                       f'<polygon {W} points="88,30 72,68 104,68"/><rect {W} x="60" y="72" width="8" height="18"/>'
                       f'<rect {W} x="36" y="68" width="7" height="14"/><rect {W} x="85" y="68" width="7" height="14"/>'),
    "oak": ("norse", f'<circle {W} cx="64" cy="48" r="26"/><circle {W} cx="44" cy="58" r="16"/><circle {W} cx="84" cy="58" r="16"/>'
                     f'<rect {W} x="58" y="64" width="12" height="30"/><path {WS} d="M30 98 Q64 112 98 98"/>'),
    "tar": ("norse", f'<rect {W} x="40" y="30" width="48" height="66" rx="10"/>'
                     '<rect fill="#2d5b8c" x="40" y="44" width="48" height="5"/><rect fill="#2d5b8c" x="40" y="77" width="48" height="5"/>'),
    "stone": ("core", f'<rect {W} x="26" y="70" width="34" height="22"/><rect {W} x="66" y="70" width="36" height="22"/>'
                      f'<rect {W} x="44" y="44" width="40" height="22"/>'),
    "soapstone": ("norse", f'<path {W} d="M30 48 H98 Q96 92 64 94 Q32 92 30 48 Z"/><rect {W} x="26" y="40" width="76" height="8" rx="3"/>'),
    "iron": ("core", f'<polygon {W} points="36,84 46,52 82,52 92,84"/><polygon {W} points="44,48 52,30 76,30 84,48"/>'),
    "bog_iron": ("norse", f'<polygon {W} points="38,66 46,40 82,40 90,66"/><path {WS} d="M26 82 q9 -8 18 0 t18 0 t18 0 t18 0"/>'
                          f'<path {WS} d="M34 98 q9 -8 18 0 t18 0 t18 0"/>'),
    "coal": ("industry", '<polygon fill="#1b1b1b" stroke="#ffffff" stroke-width="5" points="32,72 44,42 70,32 94,50 92,80 62,94"/>'),
    "gold": ("precious", f'<circle {W} cx="52" cy="70" r="22"/><circle fill="#f2c94c" stroke="#ffffff" stroke-width="5" cx="74" cy="56" r="22"/>'),
    "silver": ("precious", '<circle fill="#e7ecef" stroke="#ffffff" stroke-width="5" cx="64" cy="64" r="28"/>'
                           '<circle fill="none" stroke="#9aa5ab" stroke-width="4" cx="64" cy="64" r="18"/>'),
    "gems": ("precious", f'<polygon {W} points="40,50 52,34 76,34 88,50 64,96"/>'
                         '<polyline fill="none" stroke="#b58410" stroke-width="3" points="40,50 88,50"/>'
                         '<polyline fill="none" stroke="#b58410" stroke-width="3" points="52,34 58,50 64,96 70,50 76,34"/>'),
    "fish": ("core", f'<ellipse {W} cx="58" cy="64" rx="28" ry="15"/><polygon {W} points="80,64 102,46 102,82"/>'
                     '<circle fill="#3d7a3a" cx="42" cy="60" r="4"/>'),
    "whales": ("norse", f'<path {W} d="M64 96 C60 70 62 58 64 52 C66 58 68 70 64 96 Z"/>'
                        f'<path {W} d="M64 54 C52 34 34 34 22 40 C38 46 52 52 64 60 C76 52 90 46 106 40 C94 34 76 34 64 54 Z"/>'
                        f'<path {WS} d="M30 100 q8 -6 16 0 t16 0 t16 0 t16 0"/>'),
    "seals": ("norse", f'<ellipse {W} cx="60" cy="74" rx="34" ry="14"/><circle {W} cx="90" cy="56" r="13"/>'
                       '<circle fill="#2d5b8c" cx="94" cy="53" r="3"/><polygon fill="#ffffff" points="26,74 14,64 14,86"/>'),
    "farmland": ("core", f'<path {WS} d="M64 100 V34"/>'
                         + "".join(f'<ellipse {W} cx="{64 + dx}" cy="{y}" rx="6" ry="10" transform="rotate({ang} {64 + dx} {y})"/>'
                                   for y in (42, 58, 74) for dx, ang in ((-10, -30), (10, 30)))
                         + f'<ellipse {W} cx="64" cy="30" rx="6" ry="10"/>'),
    "wool": ("norse", f'<circle {W} cx="50" cy="58" r="16"/><circle {W} cx="70" cy="52" r="18"/><circle {W} cx="86" cy="64" r="14"/>'
                      f'<circle {W} cx="62" cy="70" r="16"/><circle fill="#1d1d1d" stroke="#ffffff" stroke-width="3" cx="32" cy="58" r="10"/>'
                      f'<rect {W} x="48" y="80" width="6" height="16"/><rect {W} x="76" y="78" width="6" height="16"/>'),
    "horses": ("wildlife", '<path fill="none" stroke="#ffffff" stroke-width="12" stroke-linecap="round" d="M42 92 V62 A22 22 0 0 1 86 62 V92"/>'
                           + "".join(f'<circle fill="#7a5230" cx="{x}" cy="{y}" r="3"/>' for x, y in ((42, 70), (42, 84), (86, 70), (86, 84), (50, 46), (78, 46)))),
    "game": ("wildlife", f'<path {WS} d="M64 96 V60"/><path {WS} d="M64 62 C50 56 40 44 38 26"/><path {WS} d="M64 62 C78 56 88 44 90 26"/>'
                         f'<path {WS} d="M44 44 L30 38"/><path {WS} d="M84 44 L98 38"/><path {WS} d="M40 32 L48 22"/><path {WS} d="M88 32 L80 22"/>'),
    "furs": ("wildlife", f'<path {W} d="M48 26 Q64 36 80 26 L90 44 Q82 64 92 86 L74 92 Q64 104 54 92 L36 86 Q46 64 38 44 Z"/>'),
    "clay": ("industry", f'<rect {W} x="24" y="72" width="38" height="18" rx="2"/><rect {W} x="66" y="72" width="38" height="18" rx="2"/>'
                         f'<rect {W} x="45" y="50" width="38" height="18" rx="2"/>'),
    "salt": ("industry", f'<polygon {W} points="22,92 64,38 106,92"/>'
                         '<polygon fill="#566170" points="56,70 64,58 72,70 64,82"/>'),
    "peat": ("norse", f'<path {W} d="M64 26 C76 44 90 56 88 74 C86 92 74 100 64 100 C54 100 42 92 40 76 C38 62 48 54 52 44 C56 54 60 58 64 60 C66 48 64 38 64 26 Z"/>'),
    "reeds": ("norse", f'<path {WS} d="M44 100 C44 74 40 56 34 40"/><path {WS} d="M64 100 V34"/><path {WS} d="M84 100 C84 74 88 58 96 44"/>'
                       f'<rect {W} x="58" y="30" width="12" height="26" rx="6"/><rect {W} x="28" y="38" width="10" height="22" rx="5" transform="rotate(-15 33 49)"/>'
                       f'<path {WS} d="M24 104 H104"/>'),
    "lake_ore": ("norse", f'<polygon {W} points="40,58 48,34 80,34 88,58"/><path {WS} d="M24 74 q10 -8 20 0 t20 0 t20 0 t20 0"/>'
                          f'<path {WS} d="M32 92 q10 -8 20 0 t20 0 t20 0"/>'),
    "amber": ("precious", '<path fill="#f39c12" stroke="#ffffff" stroke-width="5" d="M64 26 C78 50 90 64 90 78 A26 22 0 0 1 38 78 C38 64 50 50 64 26 Z"/>'
                          '<ellipse fill="#ffd27a" cx="54" cy="74" rx="5" ry="9"/>'),
}


def badge(group: str, glyph: str) -> str:
    color = GROUP_COLORS[group]
    shape = SHAPES[group]
    sc = GLYPH_SCALE[group]
    rim = "#ffa94d" if group == "cave" else "#f8f4ea"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        # Drop shadow, dark outline, coloured face with a light rim.
        f'<g transform="translate(64 64) scale(0.94) translate(-64 -64)">'
        f'<g transform="translate(3 4)" fill="#000000" opacity="0.45">{shape}</g>'
        f'<g fill="none" stroke="#0d1013" stroke-width="12" stroke-linejoin="round">{shape}</g>'
        f'<g fill="{color}" stroke="{rim}" stroke-width="5" stroke-linejoin="round">{shape}</g>'
        f'<g transform="translate(64 64) scale({sc}) translate(-64 -64)">{glyph}</g>'
        '</g></svg>'
    )


CAVE_GLYPH = (
    '<path fill="#e9dfd0" d="M22 104 V70 A42 42 0 0 1 106 70 V104 Z"/>'
    '<path fill="#0b0908" d="M40 104 V74 A24 24 0 0 1 88 74 V104 Z"/>'
    '<polygon fill="#e9dfd0" points="50,62 54,76 58,62"/><polygon fill="#e9dfd0" points="68,58 72,74 76,58"/>'
    '<polygon fill="#ffa94d" points="60,104 64,92 68,104"/>'
)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for key, (group, glyph) in GLYPHS.items():
        (OUT / f"{key}.svg").write_text(badge(group, glyph), encoding="utf-8")
    (OUT / "cave.svg").write_text(badge("cave", CAVE_GLYPH), encoding="utf-8")
    print(f"wrote {len(GLYPHS)} icons to {OUT}")


if __name__ == "__main__":
    main()
