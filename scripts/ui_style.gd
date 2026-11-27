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


## Gilds a title label: shaded, hammered, sheened gold instead of one flat colour
## (shaders/gold_text.gdshader). The gradient follows the capitals' height for this font size.
static func gild(label: Label) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/gold_text.gdshader")
	label.material = mat
	var update := func() -> void:
		var f: Font = label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var asc := f.get_ascent(size)
		var line_h := asc + f.get_descent(size)
		# Where the text sits in the label (vertically centred or at the top).
		var y0 := (label.size.y - line_h) * 0.5 if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER else 0.0
		mat.set_shader_parameter("text_top", y0 + asc - size * 0.72)
		mat.set_shader_parameter("text_bottom", y0 + asc)
		var tw := f.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			tw = maxf(tw, label.size.x)
		mat.set_shader_parameter("text_width", maxf(tw, 50.0))
	label.resized.connect(update)
	update.call()


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
	# Buttons: dark wood with a gold rim; lighter on hover, gold when pressed or toggled on.
	var make := func(bg: Color, border: Color, width: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		return sb
	t.set_stylebox("normal", "Button", make.call(Color(0.16, 0.11, 0.07, 0.95), Color(0.75, 0.58, 0.28), 1))
	t.set_stylebox("hover", "Button", make.call(Color(0.27, 0.19, 0.11, 0.98), GOLD, 2))
	t.set_stylebox("pressed", "Button", make.call(Color(0.45, 0.32, 0.14, 1.0), GOLD, 2))
	t.set_stylebox("hover_pressed", "Button", make.call(Color(0.5, 0.36, 0.16, 1.0), GOLD, 2))
	t.set_stylebox("disabled", "Button", make.call(Color(0.1, 0.08, 0.06, 0.7), Color(0.4, 0.33, 0.22), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.8))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.92, 0.7))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.45))
	t.set_stylebox("normal", "LineEdit", make.call(Color(0.08, 0.06, 0.04, 0.9), Color(0.5, 0.4, 0.22), 1))
	t.set_stylebox("focus", "LineEdit", make.call(Color(0.1, 0.08, 0.05, 0.95), GOLD, 1))
	return t
