class_name UiStyle
extends RefCounted
## Shared lettering: Cinzel (SIL OFL, assets/fonts) for map labels and the HUD. Map labels are
## gold on a thick dark outline with a soft drop shadow so they read over any terrain.

const FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(1.0, 0.86, 0.45)
const PARCHMENT := Color(0.98, 0.93, 0.8)
const INK := Color(0.08, 0.05, 0.03, 1.0)

static var _fonts: Dictionary = {}


## Cinzel at a weight (400 regular .. 900 black), with a little extra letter spacing.
static func font(weight: int = 800) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base: FontFile = load(FONT_PATH)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = 1
	_fonts[weight] = fv
	return fv


## A world label that pops: heavy Cinzel, coloured fill, dark outline and a drop shadow.
## `offset` is in screen pixels (fixed size), like Label3D.offset.
static func map_label(text: String, size: int, color: Color, offset: Vector2, priority: int, pixel_size := 0.0003) -> Label3D:
	var lb := _label(text, size, color, offset, priority, pixel_size)
	lb.outline_size = int(size * 0.42)
	lb.outline_modulate = INK
	var sh := _label(text, size, Color(0, 0, 0, 0.55), offset + Vector2(size * 0.09, -size * 0.11), priority - 1, pixel_size)
	sh.outline_size = int(size * 0.5)
	sh.outline_modulate = Color(0, 0, 0, 0.35)
	sh.name = "Shadow"
	lb.add_child(sh)
	return lb


static func _label(text: String, size: int, color: Color, offset: Vector2, priority: int, pixel_size: float) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = font(900)
	lb.font_size = size
	lb.modulate = color
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.fixed_size = true
	lb.pixel_size = pixel_size
	lb.no_depth_test = true
	lb.render_priority = priority
	lb.outline_render_priority = priority - 1
	lb.offset = offset
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return lb


## Theme for HUD controls: Cinzel body text with a light shadow.
static func hud_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(700)
	t.default_font_size = 15
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_outline_size", "Label", 2)
	return t
