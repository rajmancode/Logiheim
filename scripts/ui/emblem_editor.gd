class_name EmblemEditor
extends PanelContainer
## Choose a clan's banner before setting sail (opened from the landing chooser): its colour,
## the second colour, the pattern dividing them and the charge in the middle, with the shield
## and the flag shown as you choose. Changes go straight into the player's entry.

signal changed

var player: Dictionary = {}
var _preview_box: CenterContainer
var _pattern_label: Label
var _charges: GridContainer
var _fields: HFlowContainer
var _metals: HFlowContainer
var _title: Label


func _ready() -> void:
	theme = UiStyle.hud_theme()
	add_theme_stylebox_override("panel", UiStyle.panel())
	custom_minimum_size = Vector2(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_title = Label.new()
	_title.add_theme_font_override("font", UiStyle.font(900))
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	UiStyle.gild(_title)
	v.add_child(UiStyle.rule())
	_preview_box = CenterContainer.new()
	_preview_box.custom_minimum_size = Vector2(0, 170)
	v.add_child(_preview_box)
	v.add_child(UiStyle.heading("Clan colour", 15))
	_fields = HFlowContainer.new()
	v.add_child(_fields)
	v.add_child(UiStyle.heading("Second colour", 15))
	_metals = HFlowContainer.new()
	v.add_child(_metals)
	v.add_child(UiStyle.heading("Pattern", 15))
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(prow)
	prow.add_child(_button("◀", func() -> void: _step_pattern(-1)))
	_pattern_label = Label.new()
	_pattern_label.custom_minimum_size = Vector2(160, 0)
	_pattern_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prow.add_child(_pattern_label)
	prow.add_child(_button("▶", func() -> void: _step_pattern(1)))
	v.add_child(UiStyle.heading("Charge", 15))
	_charges = GridContainer.new()
	_charges.columns = 5
	_charges.add_theme_constant_override("h_separation", 6)
	_charges.add_theme_constant_override("v_separation", 6)
	v.add_child(_charges)
	var done := _button("Done", func() -> void:
		visible = false
		changed.emit())
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(done)
	visible = false


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Opens for a player's entry ({name, color, emblem, ...}).
func edit(p: Dictionary) -> void:
	player = p
	if not player.has("emblem"):
		player.emblem = Emblem.default_for(0)
	visible = true
	_refresh()


func _step_pattern(d: int) -> void:
	player.emblem.pattern = posmod(int(player.emblem.pattern) + d, Emblem.PATTERNS.size())
	_refresh()


func _swatch(col: Color, selected: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(30, 30)
	b.focus_mode = Control.FOCUS_NONE
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.set_corner_radius_all(15)
	st.set_border_width_all(3 if selected else 1)
	st.border_color = UiStyle.GOLD if selected else Color(0, 0, 0, 0.7)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, st)
	b.pressed.connect(cb)
	return b


func _refresh() -> void:
	var e: Dictionary = player.emblem
	_title.text = "The banner of %s" % String(player.get("name", ""))
	for c in _preview_box.get_children():
		c.queue_free()
	var big := Emblem.shield(player.color, e, 160.0)
	_preview_box.add_child(big)
	for c in _fields.get_children():
		c.queue_free()
	for col: Color in Emblem.FIELDS:
		_fields.add_child(_swatch(col, col.is_equal_approx(player.color), func() -> void:
			player.color = col
			_refresh()))
	for c in _metals.get_children():
		c.queue_free()
	for col: Color in Emblem.METALS:
		_metals.add_child(_swatch(col, col.is_equal_approx(e.metal), func() -> void:
			e.metal = col
			_refresh()))
	_pattern_label.text = Emblem.PATTERNS[int(e.pattern)]
	for c in _charges.get_children():
		c.queue_free()
	for ch: String in Emblem.CHARGES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = ch == String(e.charge)
		b.tooltip_text = Emblem.CHARGE_NAMES[ch]
		var ic := TextureRect.new()
		ic.texture = Emblem.charge_texture(ch)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 9
		ic.offset_top = 9
		ic.offset_right = -9
		ic.offset_bottom = -9
		ic.modulate = UiStyle.GOLD if b.button_pressed else UiStyle.PARCHMENT
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		b.pressed.connect(func() -> void:
			e.charge = ch
			_refresh())
		_charges.add_child(b)
	changed.emit()
