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


## A nine-patch from assets/ui (tools/make_ui_textures.py): `margin` texture pixels kept at
## each edge, `pad` content padding.
static func box(name: String, margin := 16, pad := Vector4(10, 6, 10, 6), tint := Color.WHITE) -> StyleBoxTexture:
	var key := "%s_%d_%s_%s" % [name, margin, pad, tint.to_html()]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/%s.png" % name)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	sb.modulate_color = tint
	_boxes[key] = sb
	return sb


static var _boxes := {}


## The great framed panel: smoked oak, a double gold border, knotwork in the corners.
static func panel() -> StyleBoxTexture:
	return box("panel", 44, Vector4(20, 18, 20, 18))


## A gilded ornamental rule (for under headings).
static func rule() -> TextureRect:
	var r := TextureRect.new()
	r.texture = load("res://assets/ui/rule.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(0, 14)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A section heading: gilded capitals over a rule.
static func heading(text: String, size := 17) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(900))
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", GOLD)
	v.add_child(l)
	gild(l)
	v.add_child(rule())
	return v


## Theme for HUD controls: Cinzel text with a soft shadow; oak-and-gold panels, bronze buttons
## that glow on hover and sink when pressed, tabs, parchment tooltips, gilded bars and
## scrollbars (all nine-patches from assets/ui).
static func hud_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(700)
	t.default_font_size = 15
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_outline_size", "Label", 3)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	var pad := Vector4(14, 7, 14, 7)
	t.set_stylebox("normal", "Button", box("button", 14, pad))
	t.set_stylebox("hover", "Button", box("button_hover", 14, pad))
	t.set_stylebox("pressed", "Button", box("button_pressed", 14, pad))
	t.set_stylebox("hover_pressed", "Button", box("button_pressed", 14, pad))
	t.set_stylebox("disabled", "Button", box("button_disabled", 14, pad))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.78))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.94, 0.75))
	t.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.94, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.45))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", 3)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	# Tabs.
	var tp := Vector4(16, 8, 16, 6)
	t.set_stylebox("tab_selected", "TabContainer", box("tab_active", 14, tp))
	t.set_stylebox("tab_unselected", "TabContainer", box("tab", 14, tp))
	t.set_stylebox("tab_hovered", "TabContainer", box("tab", 14, tp, Color(1.35, 1.25, 1.1)))
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", Color(0.75, 0.68, 0.55))
	t.set_color("font_hovered_color", "TabContainer", PARCHMENT)
	t.set_font_size("font_size", "TabContainer", 15)
	# Tooltips: parchment with dark ink.
	t.set_stylebox("panel", "TooltipPanel", box("tooltip", 16, Vector4(14, 10, 14, 10)))
	t.set_color("font_color", "TooltipLabel", Color(0.16, 0.1, 0.05))
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "TooltipLabel", 14)
	# Bars and scrollbars.
	t.set_stylebox("background", "ProgressBar", box("bar_bg", 6, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box("bar_fill", 6, Vector4.ZERO, GOLD))
	t.set_stylebox("scroll", "VScrollBar", box("bar_bg", 6, Vector4(3, 3, 3, 3)))
	t.set_stylebox("grabber", "VScrollBar", box("bar_fill", 6, Vector4.ZERO, Color(0.75, 0.58, 0.3)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box("bar_fill", 6, Vector4.ZERO, GOLD))
	t.set_stylebox("grabber_pressed", "VScrollBar", box("bar_fill", 6, Vector4.ZERO, Color(1, 0.95, 0.7)))
	t.set_stylebox("scroll", "HScrollBar", box("bar_bg", 6, Vector4(3, 3, 3, 3)))
	t.set_stylebox("grabber", "HScrollBar", box("bar_fill", 6, Vector4.ZERO, Color(0.75, 0.58, 0.3)))
	t.set_stylebox("grabber_highlight", "HScrollBar", box("bar_fill", 6, Vector4.ZERO, GOLD))
	t.set_stylebox("grabber_pressed", "HScrollBar", box("bar_fill", 6, Vector4.ZERO, Color(1, 0.95, 0.7)))
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.08, 0.06, 0.04, 0.9)
	le.border_color = Color(0.5, 0.4, 0.22)
	le.set_border_width_all(1)
	le.set_corner_radius_all(4)
	le.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", le)
	var lf := le.duplicate() as StyleBoxFlat
	lf.border_color = GOLD
	t.set_stylebox("focus", "LineEdit", lf)
	return t
