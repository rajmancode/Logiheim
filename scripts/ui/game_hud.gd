class_name GameHUD
extends CanvasLayer
## The settlement's interface once the players have landed.
##   - Top bar: whose turn at the controls (click or Tab to pass them on), people (and how
##     many are idle), contentment, influence (and its rate) with "Expand land", the key goods
##     and food, the Ledger button and the game speed (pause, 1x, 2x, 4x).
##   - Build menu (bottom): tabs for Gather, Food, Industry, Crafts, Sea & Trade, People and
##     Military; a card per building with its icon and cost (greyed out when you can't afford
##     it; hover for what it makes from what). The wheel scrolls the cards. Click a card, then
##     a hex.
##   - The selected building (left): what it is, what it's doing, its people, every recipe it
##     can work (the one in use marked), a bar for its work or construction, and "Pull down".
##   - The ledger (right, L): tabs for Stores (every good by kind, how much, made and used per
##     minute), Buildings (every kind you have, how many are working, waiting or idle, and why;
##     click to select one) and People (homes, food, each want and how well it is met,
##     contentment and what it does, where influence comes from).
##   - Short messages ("Longhouse finished.") under the top bar.
##   - Armies: "Muster army" in the Military tab gathers the clan's warriors into an army
##     group; its panel (where the building panel goes) sets its formation, shows where it is
##     going and disbands it. Click the army to select it, click the map to march it there.
##   - Options (the Options button, F10): the interface's scale, where the resource bar, build
##     menu, building panel and ledger sit, and the production pops (UiSettings, saved).
##   All of it hangs under one root control drawn at UiSettings.scale; _layout() places the
##   parts for the window size and the chosen placements.

var world: GameWorld

var _player_btn: Button
var _people: Label
var _content: Label
var _influence: Label
var _expand: Button
var _goods_box: HBoxContainer
var _speed_btns: Array[Button] = []
var _tab := "harvest"
var _tabs: Array[Button] = []
var _cards: HBoxContainer
var _card_scroll: ScrollContainer
var _info: PanelContainer
var _info_title: Label
var _info_icon: TextureRect
var _info_text: RichTextLabel
var _info_bar: ProgressBar
var _demolish: Button
var _toast: Label
var _toast_box: PanelContainer
var _team_style := {}
var _toast_t := 0.0
var _hint: Label
var _refresh_t := 0.0
var _ledger: PanelContainer
var _ledger_btn: Button
var _ledger_tabs: TabContainer
var _store_rows := {}          # good -> [row, amount label, rate label]
var _buildings_box: VBoxContainer
var _people_text: RichTextLabel
var _needs_box: VBoxContainer
var _root: Control
var _top: PanelContainer
var _bottom: PanelContainer
var _crest_box: CenterContainer
var _crest_for := -1
var _options: PanelContainer
var _army_panel: PanelContainer
var _army_title: Label
var _army_text: RichTextLabel
var _army_buttons: Dictionary = {}
var _army_shield: CenterContainer
var _scale_label: Label
var _narrow := false            # little room across: fewer icons, one speed button
var _bar_icons: Array[Control] = []
const BAR_H := 60.0
const BUILD_H := 168.0


func _ready() -> void:
	layer = 15
	var theme := UiStyle.hud_theme()
	UiSettings.ensure_loaded()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)
	get_viewport().size_changed.connect(_layout)
	# --- Top bar -----------------------------------------------------------------------------
	var top := PanelContainer.new()
	_top = top
	top.theme = theme
	top.add_theme_stylebox_override("panel", UiStyle.box("topbar", 24, Vector4(14, 6, 14, 12)))
	_root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	top.add_child(row)
	_crest_box = CenterContainer.new()
	_crest_box.custom_minimum_size = Vector2(36, 40)
	row.add_child(_crest_box)
	_player_btn = Button.new()
	_player_btn.focus_mode = Control.FOCUS_NONE
	_player_btn.tooltip_text = "Pass the controls to the next player (Tab)"
	_player_btn.pressed.connect(func() -> void: world.set_active(world.active + 1))
	row.add_child(_player_btn)
	_bar_icons.append(_icon_rect(load("res://assets/icons/buildings/longhouse.png"), 28, "People"))
	row.add_child(_bar_icons[-1])
	_people = Label.new()
	_people.tooltip_text = "People: how many / room in your homes (idle hands)"
	_people.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_people)
	_bar_icons.append(_icon_rect(Goods.icon("jewellery"), 26, "Contentment"))
	row.add_child(_bar_icons[-1])
	_content = Label.new()
	_content.tooltip_text = "Contentment: how well your people's wants are met (see the ledger's People tab)"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_content)
	row.add_child(_icon_rect(Goods.icon("influence"), 28, "Influence"))
	_influence = Label.new()
	row.add_child(_influence)
	_expand = Button.new()
	_expand.focus_mode = Control.FOCUS_NONE
	_expand.tooltip_text = "Spend influence to push your land a step further out from the town hall"
	_expand.pressed.connect(func() -> void: world.expand())
	row.add_child(_expand)
	_goods_box = HBoxContainer.new()
	_goods_box.add_theme_constant_override("separation", 5)
	_goods_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_goods_box)
	_ledger_btn = Button.new()
	_ledger_btn.text = "Ledger"
	_ledger_btn.toggle_mode = true
	_ledger_btn.focus_mode = Control.FOCUS_NONE
	_ledger_btn.tooltip_text = "Stores, buildings and people (L)"
	_ledger_btn.toggled.connect(_slide_ledger)
	row.add_child(_ledger_btn)
	for sp in [[0.0, "❚❚"], [1.0, "1x"], [2.0, "2x"], [4.0, "4x"]]:
		var b := Button.new()
		b.text = sp[1]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(40, 0)
		b.focus_mode = Control.FOCUS_NONE
		var v: float = sp[0]
		b.pressed.connect(func() -> void:
			if v == 0.0:
				world.paused = not world.paused
			elif _narrow:
				# One button cycles 1x, 2x, 4x.
				world.speed = 1.0 if world.paused else {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(world.speed, 1.0)
				world.paused = false
			else:
				world.paused = false
				world.speed = v)
		row.add_child(b)
		_speed_btns.append(b)
	var opt := Button.new()
	opt.text = "Options"
	opt.focus_mode = Control.FOCUS_NONE
	opt.tooltip_text = "Interface size and layout (F10)"
	opt.add_theme_font_size_override("font_size", 13)
	opt.pressed.connect(func() -> void: _options.visible = not _options.visible)
	row.add_child(opt)

	# --- Build menu ----------------------------------------------------------------------------
	var bottom := PanelContainer.new()
	_bottom = bottom
	bottom.theme = theme
	bottom.add_theme_stylebox_override("panel", UiStyle.box("panel", 44, Vector4(18, 12, 18, 14)))
	_root.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	bv.add_child(tabs)
	var title := Label.new()
	title.text = "Build "
	title.add_theme_font_override("font", UiStyle.font(900))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	tabs.add_child(title)
	for cat in BuildingDefs.CATEGORIES:
		var b := Button.new()
		b.text = BuildingDefs.CATEGORY_NAMES[cat]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var tp := Vector4(14, 6, 14, 6)
		b.add_theme_stylebox_override("normal", UiStyle.box("tab", 14, tp))
		b.add_theme_stylebox_override("hover", UiStyle.box("tab", 14, tp, Color(1.4, 1.3, 1.1)))
		b.add_theme_stylebox_override("pressed", UiStyle.box("tab_active", 14, tp))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box("tab_active", 14, tp))
		b.add_theme_color_override("font_pressed_color", UiStyle.GOLD)
		b.add_theme_color_override("font_hover_pressed_color", UiStyle.GOLD)
		b.pressed.connect(func() -> void:
			_tab = cat
			_build_cards())
		tabs.add_child(b)
		_tabs.append(b)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.clip_text = true
	tabs.add_child(_hint)
	_card_scroll = ScrollContainer.new()
	_card_scroll.custom_minimum_size = Vector2(0, 104)
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.gui_input.connect(_on_cards_wheel)
	bv.add_child(_card_scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	_card_scroll.add_child(_cards)

	# --- Selected building ---------------------------------------------------------------------
	_info = PanelContainer.new()
	_info.theme = theme
	_info.add_theme_stylebox_override("panel", UiStyle.panel())
	_info.custom_minimum_size = Vector2(360, 0)
	_root.add_child(_info)
	var iv := VBoxContainer.new()
	_info.add_child(iv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	iv.add_child(head)
	_info_icon = _icon_rect(null, 64, "")
	head.add_child(_info_icon)
	_info_title = Label.new()
	_info_title.add_theme_font_override("font", UiStyle.font(900))
	_info_title.add_theme_font_size_override("font_size", 20)
	_info_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_info_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_info_title)
	UiStyle.gild(_info_title)
	iv.add_child(UiStyle.rule())
	_info_text = _rich(14, 340)
	iv.add_child(_info_text)
	_info_bar = _bar(Color(0.78, 0.58, 0.24))
	iv.add_child(_info_bar)
	_demolish = Button.new()
	_demolish.text = "Pull down"
	_demolish.focus_mode = Control.FOCUS_NONE
	_demolish.pressed.connect(func() -> void: world.demolish(world.selected))
	iv.add_child(_demolish)
	_info.visible = false

	# --- Ledger --------------------------------------------------------------------------------
	_ledger = PanelContainer.new()
	_ledger.theme = theme
	_ledger.add_theme_stylebox_override("panel", UiStyle.panel())
	_root.add_child(_ledger)
	_ledger_tabs = TabContainer.new()
	_ledger.add_child(_ledger_tabs)
	_build_stores_tab()
	_build_buildings_tab()
	_build_people_tab()
	_ledger.visible = false

	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UiStyle.box("banner", 34, Vector4(56, 12, 56, 14)))
	_toast_box.custom_minimum_size = Vector2(600, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	_root.add_child(_toast_box)
	_toast = Label.new()
	_toast.theme = theme
	_toast.add_theme_font_override("font", UiStyle.font(800))
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_toast.add_theme_color_override("font_outline_color", UiStyle.INK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast)
	_build_army_panel(theme)
	_build_options(theme)
	visible = false
	_layout.call_deferred()


# ------------------------------------------------------------------------------- helpers

## A good's icon and amount in a small dark chip (the top bar).
func _chip(tex: Texture2D, text: String, tip: String) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UiStyle.box("chip", 16, Vector4(6, 2, 12, 2)))
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	if tex != null:
		h.add_child(_icon_rect(tex, 24, ""))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return c


## The ledger slides in from its side and out again.
func _slide_ledger(on: bool) -> void:
	var home := _ledger_x()
	var away := home + (440.0 if UiSettings.ledger_right else -440.0)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if on:
		_ledger.visible = true
		_ledger.position.x = away
		_ledger.modulate.a = 0.0
		tw.tween_property(_ledger, "position:x", home, 0.28)
		tw.tween_property(_ledger, "modulate:a", 1.0, 0.2)
		_refresh_t = 0.0
	else:
		tw.tween_property(_ledger, "position:x", away, 0.22)
		tw.tween_property(_ledger, "modulate:a", 0.0, 0.2)
		tw.chain().tween_callback(func() -> void: _ledger.visible = false)


## The interface's size in its own (unscaled) units.
func _area() -> Vector2:
	return get_viewport().get_visible_rect().size / UiSettings.scale


## Where everything goes, for this window and the chosen placements.
func _layout() -> void:
	if _root == null:
		return
	var s := UiSettings.scale
	var size := _area()
	_root.scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = size
	# The resource bar along the top or the bottom.
	_top.position = Vector2(0, 0 if UiSettings.bar_top else size.y - BAR_H)
	_top.size = Vector2(size.x, BAR_H)
	_narrow = size.x < 1500.0
	for ic in _bar_icons:
		ic.visible = not _narrow
	_speed_btns[2].visible = not _narrow
	_speed_btns[3].visible = not _narrow
	# The build menu at the bottom or the top, clear of the resource bar.
	var y_top := BAR_H if UiSettings.bar_top else 0.0
	var y_bot := size.y - (0.0 if UiSettings.bar_top else BAR_H)
	var bw := minf(size.x - 40.0, 1400.0)
	if UiSettings.build_bottom:
		_bottom.position = Vector2((size.x - bw) * 0.5, y_bot - BUILD_H)
		y_bot -= BUILD_H
	else:
		_bottom.position = Vector2((size.x - bw) * 0.5, y_top)
		y_top += BUILD_H
	_bottom.size = Vector2(bw, BUILD_H)
	# The side panels in the band between.
	_ledger.size = Vector2(410, maxf(y_bot - y_top - 20.0, 200.0))
	_ledger.position = Vector2(_ledger_x(), y_top + 10.0)
	_info.position = Vector2(_info_x(), y_top + 10.0)
	_army_panel.position = _info.position
	_toast_box.position = Vector2((size.x - 600.0) * 0.5, y_top + 10.0)
	_options.position = (size - _options.size) * 0.5
	if _scale_label != null:
		_scale_label.text = "%d%%" % int(round(s * 100.0))


func _ledger_x() -> float:
	return _area().x - 420.0 if UiSettings.ledger_right else 10.0


func _info_x() -> float:
	var x := 12.0 if UiSettings.panel_left else _area().x - 384.0
	# Beside the ledger if both are on the same side.
	if UiSettings.panel_left != UiSettings.ledger_right and _ledger.visible:
		x += 420.0 if UiSettings.panel_left else -420.0
	return x


## The options panel: interface scale and where its parts sit.
func _build_options(theme: Theme) -> void:
	_options = PanelContainer.new()
	_options.theme = theme
	_options.add_theme_stylebox_override("panel", UiStyle.panel())
	_options.custom_minimum_size = Vector2(460, 0)
	_root.add_child(_options)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_options.add_child(v)
	v.add_child(UiStyle.heading("Options", 22))
	var srow := HBoxContainer.new()
	v.add_child(srow)
	var sl := Label.new()
	sl.text = "Interface size"
	sl.custom_minimum_size = Vector2(170, 0)
	srow.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 75
	slider.max_value = 150
	slider.step = 5
	slider.value = UiSettings.scale * 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	srow.add_child(slider)
	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(56, 0)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	srow.add_child(_scale_label)
	slider.drag_ended.connect(func(_c: bool) -> void:
		UiSettings.scale = slider.value / 100.0
		_changed_settings())
	slider.value_changed.connect(func(x: float) -> void: _scale_label.text = "%d%%" % int(x))
	v.add_child(_choice("Resource bar", ["Top", "Bottom"], 0 if UiSettings.bar_top else 1, func(i: int) -> void: UiSettings.bar_top = i == 0))
	v.add_child(_choice("Build menu", ["Bottom", "Top"], 0 if UiSettings.build_bottom else 1, func(i: int) -> void: UiSettings.build_bottom = i == 0))
	v.add_child(_choice("Building panel", ["Left", "Right"], 0 if UiSettings.panel_left else 1, func(i: int) -> void: UiSettings.panel_left = i == 0))
	v.add_child(_choice("Ledger", ["Right", "Left"], 0 if UiSettings.ledger_right else 1, func(i: int) -> void: UiSettings.ledger_right = i == 0))
	v.add_child(_choice("Production pops", ["Shown", "Hidden"], 0 if UiSettings.pops else 1, func(i: int) -> void: UiSettings.pops = i == 0))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	var reset := Button.new()
	reset.text = "Defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		UiSettings.reset()
		_options.queue_free()
		_build_options(theme)
		_options.visible = true
		_changed_settings())
	brow.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: _options.visible = false)
	brow.add_child(close)
	_options.visible = false


## A labelled row of toggle buttons, one chosen.
func _choice(label: String, items: Array, chosen: int, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var group := ButtonGroup.new()
	for i in items.size():
		var b := Button.new()
		b.text = items[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == chosen
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			cb.call(i)
			_changed_settings())
		row.add_child(b)
	return row


func _changed_settings() -> void:
	UiSettings.save()
	_layout()


func _icon_rect(tex: Texture2D, size: int, tip: String) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(size, size)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tooltip_text = tip
	ic.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	return ic


func _rich(size: int, width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r


func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 14)
	b.show_percentage = false
	b.add_theme_stylebox_override("fill", UiStyle.box("bar_fill", 6, Vector4.ZERO, col))
	b.add_theme_stylebox_override("background", UiStyle.box("bar_bg", 6, Vector4.ZERO))
	return b


func _header(text: String) -> Control:
	return UiStyle.heading(text, 16)


## A recipe as BBCode: what it uses -> what it makes.
static func _recipe_bb(r: Dictionary, size := 20) -> String:
	var uses: Dictionary = r.get("uses", {})
	var makes: Dictionary = r.get("makes", {})
	var left := Goods.bbcode(uses, size) if not uses.is_empty() else ""
	var right := Goods.bbcode(makes, size, "+")
	return (left + "  [color=#c8a050]→[/color]  " + right) if left != "" else right


# ------------------------------------------------------------------------------- ledger tabs

func _scroll_page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ledger_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v


func _build_stores_tab() -> void:
	var v := _scroll_page("Stores")
	for group: String in Goods.GROUPS:
		v.add_child(_header(group))
		for id: String in Goods.GROUPS[group]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.tooltip_text = Goods.display_name(id)
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(_icon_rect(Goods.icon(id), 26, ""))
			var gname := Label.new()
			gname.text = Goods.display_name(id)
			gname.custom_minimum_size = Vector2(120, 0)
			gname.add_theme_font_size_override("font_size", 14)
			row.add_child(gname)
			var amt := Label.new()
			amt.custom_minimum_size = Vector2(52, 0)
			amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amt.add_theme_font_size_override("font_size", 14)
			row.add_child(amt)
			var rate := RichTextLabel.new()
			rate.bbcode_enabled = true
			rate.fit_content = true
			rate.scroll_active = false
			rate.autowrap_mode = TextServer.AUTOWRAP_OFF
			rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rate.add_theme_font_size_override("normal_font_size", 13)
			row.add_child(rate)
			v.add_child(row)
			_store_rows[id] = [row, amt, rate]


func _build_buildings_tab() -> void:
	_buildings_box = _scroll_page("Buildings")


func _build_people_tab() -> void:
	var v := _scroll_page("People")
	_people_text = _rich(14, 360)
	v.add_child(_people_text)
	v.add_child(_header("Wants"))
	_needs_box = VBoxContainer.new()
	v.add_child(_needs_box)
	for n: Array in Goods.NEEDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon_rect(Goods.icon(n[0]), 26, Goods.display_name(n[0])))
		var l := Label.new()
		l.text = String(n[2])
		l.custom_minimum_size = Vector2(120, 0)
		l.add_theme_font_size_override("font_size", 14)
		row.add_child(l)
		var b := _bar(Color(0.45, 0.7, 0.4))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.name = "Bar"
		row.add_child(b)
		row.name = String(n[0])
		_needs_box.add_child(row)


func _update_ledger(s: Settlement) -> void:
	if not _ledger.visible:
		return
	match _ledger_tabs.current_tab:
		0:
			for id: String in _store_rows:
				var r: Array = _store_rows[id]
				var n := float(s.stock.get(id, 0))
				var made := float(s.made_rate.get(id, 0.0))
				var used := float(s.used_rate.get(id, 0.0))
				(r[1] as Label).text = "%d" % int(n)
				var parts := PackedStringArray()
				if made > 0.05:
					parts.append("[color=#8fd07a]+%.1f[/color]" % made)
				if used > 0.05:
					parts.append("[color=#e08a70]-%.1f[/color]" % used)
				(r[2] as RichTextLabel).text = (" ".join(parts) + " [color=#a09070]/min[/color]") if not parts.is_empty() else ""
				(r[0] as Control).modulate.a = 1.0 if n >= 0.5 or made > 0.05 or used > 0.05 else 0.35
		1:
			_fill_buildings(s)
		2:
			_fill_people(s)


func _fill_buildings(s: Settlement) -> void:
	for c in _buildings_box.get_children():
		c.queue_free()
	var by_id := {}
	for b: Dictionary in s.buildings:
		if not by_id.has(b.id):
			by_id[b.id] = []
		(by_id[b.id] as Array).append(b)
	for cat in BuildingDefs.CATEGORIES:
		var any := false
		for id in BuildingDefs.DEFS:
			if BuildingDefs.DEFS[id].category != cat or not by_id.has(id):
				continue
			if not any:
				_buildings_box.add_child(_header(BuildingDefs.CATEGORY_NAMES[cat]))
				any = true
			var list: Array = by_id[id]
			var working := 0
			var rising := 0
			var why := ""
			for b: Dictionary in list:
				if not s.is_built(b):
					rising += 1
				elif bool(b.working):
					working += 1
				elif why == "":
					why = String(b.status)
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 46)
			btn.icon = BuildingDefs.icon(id)
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 40)
			btn.add_theme_font_size_override("font_size", 13)
			var line := "%s  x%d" % [String(BuildingDefs.DEFS[id].name), list.size()]
			var state := PackedStringArray()
			if working > 0:
				state.append("%d working" % working)
			if rising > 0:
				state.append("%d going up" % rising)
			if why != "":
				state.append(why)
			btn.text = line + "\n" + ", ".join(state)
			btn.tooltip_text = "Select (click again for the next)"
			var first: Dictionary = list[0]
			btn.pressed.connect(func() -> void:
				var i := list.find(world.selected)
				world.select(list[(i + 1) % list.size()] if i >= 0 else first))
			_buildings_box.add_child(btn)


func _fill_people(s: Settlement) -> void:
	var lines := PackedStringArray()
	lines.append("[b]People[/b]  %d of %d homes   [color=#a09070](%d idle, %d jobs)[/color]" % [s.population, s.housing(), s.idle(), s.workers_needed()])
	var eat := ceilf(s.population / 4.0) * 60.0 / Settlement.EAT_TIME
	lines.append("[b]Food[/b]  %d in store, eating %.0f a minute" % [int(s.food()), eat])
	for f in Goods.FOOD:
		var n := int(s.stock.get(f, 0))
		if n > 0:
			lines.append("    [img=18x18]%s[/img] %s %d" % [Goods.icon_path(f), Goods.display_name(f), n])
	lines.append("")
	lines.append("[b]Contentment[/b]  %d%%" % int(s.contentment * 100.0))
	lines.append("[color=#a09070]Growth x%.2f, work x%.2f, +%.2f influence/s[/color]" % [0.6 + 0.8 * s.contentment, 0.85 + 0.3 * s.contentment, s.contentment * 0.03 * s.population])
	lines.append("")
	lines.append("[b]Influence[/b]  %d  (+%.2f/s)" % [int(s.influence), s.influence_rate()])
	var parts := s.influence_parts()
	for k in parts:
		if float(parts[k]) > 0.001:
			lines.append("    %s  +%.2f/s" % [k, float(parts[k])])
	lines.append("    [color=#a09070]Expanding the land costs %d[/color]" % s.expand_cost())
	_people_text.text = "\n".join(lines)
	for row in _needs_box.get_children():
		var good := String(row.name)
		(row.get_node("Bar") as ProgressBar).value = float(s.needs.get(good, 0.0)) * 100.0
		(row as Control).tooltip_text = "%s: %d in store. One for every %d people a minute." % [Goods.display_name(good), int(s.stock.get(good, 0)), int(_need_rate(good))]


static func _need_rate(good: String) -> float:
	for n: Array in Goods.NEEDS:
		if n[0] == good:
			return float(n[1])
	return 0.0


# ------------------------------------------------------------------------------- the rest

func open(p_world: GameWorld) -> void:
	world = p_world
	if not world.message.is_connected(show_message):
		world.message.connect(show_message)
		world.army_selected.connect(func(_a: Dictionary) -> void: _update_army())
		world.selection_changed.connect(func(_r: Dictionary) -> void: _update_info())
	visible = true
	_build_cards()


func show_message(text: String) -> void:
	_toast.text = text
	_toast_t = 3.5
	_toast_box.modulate.a = 1.0
	_toast_box.scale = Vector2(0.9, 0.9)
	_toast_box.pivot_offset = _toast_box.size * 0.5
	create_tween().tween_property(_toast_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_L:
		_ledger_btn.button_pressed = not _ledger_btn.button_pressed
		get_viewport().set_input_as_handled()
	elif k != null and k.pressed and not k.echo and k.keycode == KEY_F10:
		_options.visible = not _options.visible
		get_viewport().set_input_as_handled()


## The wheel over the cards scrolls them sideways.
func _on_cards_wheel(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
		_card_scroll.scroll_horizontal -= 120
		_card_scroll.accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		_card_scroll.scroll_horizontal += 120
		_card_scroll.accept_event()


func _build_cards() -> void:
	for i in _tabs.size():
		_tabs[i].button_pressed = BuildingDefs.CATEGORIES[i] == _tab
	for c in _cards.get_children():
		c.queue_free()
	var s := world.me() if world != null else null
	for id in BuildingDefs.in_category(_tab):
		var d: Dictionary = BuildingDefs.DEFS[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(222, 96)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		var cp := Vector4(8, 6, 8, 6)
		b.add_theme_stylebox_override("normal", UiStyle.box("card", 22, cp))
		b.add_theme_stylebox_override("hover", UiStyle.box("card_hover", 22, cp))
		b.add_theme_stylebox_override("pressed", UiStyle.box("card_active", 22, cp))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box("card_active", 22, cp))
		b.mouse_entered.connect(func() -> void:
			b.pivot_offset = b.size * 0.5
			create_tween().tween_property(b, "scale", Vector2(1.05, 1.05), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		b.mouse_exited.connect(func() -> void:
			create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
		b.button_pressed = world != null and world.placing == id
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var pic := _icon_rect(BuildingDefs.icon(id), 72, "")
		row.add_child(pic)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var nm := Label.new()
		nm.text = String(d.name)
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", UiStyle.GOLD)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		var cost := RichTextLabel.new()
		cost.bbcode_enabled = true
		cost.fit_content = true
		cost.scroll_active = false
		cost.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.add_theme_font_size_override("normal_font_size", 13)
		cost.text = Goods.bbcode(d.cost, 20) if not d.cost.is_empty() else "Free"
		col.add_child(cost)
		b.tooltip_text = _card_tip(id)
		if s != null and not s.can_afford(d.cost):
			b.modulate = Color(1, 1, 1, 0.45)
		b.pressed.connect(func() -> void:
			if world.placing == id:
				world.cancel_placement()
			else:
				world.begin_placement(id)
			_build_cards())
		_cards.add_child(b)
	if _tab == "military":
		var m := Button.new()
		m.custom_minimum_size = Vector2(222, 96)
		m.focus_mode = Control.FOCUS_NONE
		var cp := Vector4(8, 6, 8, 6)
		m.add_theme_stylebox_override("normal", UiStyle.box("card", 22, cp))
		m.add_theme_stylebox_override("hover", UiStyle.box("card_hover", 22, cp))
		m.add_theme_stylebox_override("pressed", UiStyle.box("card_active", 22, cp))
		var mrow := HBoxContainer.new()
		mrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mrow.offset_left = 6
		mrow.offset_right = -6
		mrow.add_theme_constant_override("separation", 8)
		mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(mrow)
		mrow.add_child(_icon_rect(Goods.icon("warriors"), 64, ""))
		var ml := Label.new()
		ml.text = "Muster army\nfrom your warriors"
		ml.add_theme_font_size_override("font_size", 14)
		ml.add_theme_color_override("font_color", UiStyle.GOLD)
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mrow.add_child(ml)
		m.tooltip_text = "Gather up to 24 warriors from the barracks' training into an army group. Select it on the map, set its formation, and click where it should march."
		m.pressed.connect(func() -> void: world.muster())
		_cards.add_child(m)
	_card_scroll.scroll_horizontal = 0


func _card_tip(id: String) -> String:
	var d: Dictionary = BuildingDefs.DEFS[id]
	var tip := String(d.desc)
	if int(d.get("workers", 0)) > 0:
		tip += "\nPeople: %d" % int(d.workers)
	for r: Dictionary in BuildingDefs.recipes(id):
		var uses: Dictionary = r.get("uses", {})
		var line := Goods.describe(r.makes).replace("influence", "Influence")
		if not uses.is_empty():
			line = "%s -> %s" % [Goods.describe(uses), line]
		tip += "\n  " + line
	if d.has("cycle") and not BuildingDefs.recipes(id).is_empty():
		tip += "\nEvery %ds" % int(d.cycle)
	if d.get("tools", false):
		tip += "\nWears out tools (slow without them)"
	tip += "\nBuild time: %ds" % int(d.build_time)
	return tip


func _process(delta: float) -> void:
	if not visible or world == null or world.me() == null:
		return
	var s := world.me()
	if _crest_for != s.index:
		_crest_for = s.index
		for c in _crest_box.get_children():
			c.queue_free()
		_crest_box.add_child(Emblem.shield(s.color, s.emblem, 40.0))
	_player_btn.text = "  %s  " % s.player_name
	if not _team_style.has(s.index):
		_team_style[s.index] = UiStyle.box("button_pressed", 14, Vector4(14, 7, 14, 7), Color(s.color.r * 1.7, s.color.g * 1.7, s.color.b * 1.7))
	if _player_btn.get_theme_stylebox("normal") != _team_style[s.index]:
		_player_btn.add_theme_stylebox_override("normal", _team_style[s.index])
		_player_btn.add_theme_stylebox_override("hover", _team_style[s.index])
	_people.text = "%d/%d (%d idle)" % [s.population, s.housing(), s.idle()]
	_content.text = "%d%%" % int(s.contentment * 100.0)
	_content.modulate = Color(1, 0.65, 0.55) if s.contentment < 0.3 else (Color(0.75, 1, 0.7) if s.contentment > 0.7 else Color.WHITE)
	_influence.text = "%d (+%.1f/s)" % [int(s.influence), s.influence_rate()]
	_expand.text = "Expand (%d)" % s.expand_cost()
	_expand.disabled = s.influence < s.expand_cost()
	_speed_btns[0].button_pressed = world.paused
	for i in range(1, 4):
		_speed_btns[i].button_pressed = not world.paused and is_equal_approx(world.speed, [0.0, 1.0, 2.0, 4.0][i])
	if _narrow:
		_speed_btns[1].text = "%dx" % int(world.speed)
		_speed_btns[1].button_pressed = not world.paused
	else:
		_speed_btns[1].text = "1x"
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_update_goods(s)
		_build_cards_affordable(s)
		_update_info()
		_update_army()
		_update_ledger(s)
	if world.placing != "":
		_hint.text = "Placing %s: click a hex on your land (Shift: more). Right-click or Esc to stop." % String(BuildingDefs.DEFS[world.placing].name)
	else:
		_hint.text = "Click a building to see what it's doing. L: ledger."
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast_box.modulate.a = clampf(_toast_t, 0.0, 1.0)


## The top bar's goods: the stores' fill, food, and the few goods everything is built from.
func _update_goods(s: Settlement) -> void:
	for c in _goods_box.get_children():
		_goods_box.remove_child(c)
		c.queue_free()
	var store := _chip(load("res://assets/icons/buildings/warehouse.png"), "%d/%d" % [int(s.stored()), s.storage()], "Goods in store / room in your stores")
	if s.stored() >= s.storage():
		store.modulate = Color(1, 0.7, 0.6)
	_goods_box.add_child(store)
	_goods_box.add_child(_chip(Goods.icon("bread"), "%d" % int(s.food()), "Food: fish, meat, bread and salt fish"))
	# As many of the key goods as there is room for (the ledger has them all).
	var room := clampi(int((_area().x - (1250.0 if _narrow else 1330.0)) / 88.0), 0, Goods.TOP.size())
	for id in Goods.TOP.slice(0, room):
		_goods_box.add_child(_chip(Goods.icon(id), "%d" % int(s.stock.get(id, 0)), Goods.display_name(id)))
	# A container grows to fit and never shrinks back by itself: hold the bar to the window.
	_top.size = Vector2(_area().x, BAR_H)


func _build_cards_affordable(s: Settlement) -> void:
	var ids := BuildingDefs.in_category(_tab)
	for i in mini(ids.size(), _cards.get_child_count()):
		var b := _cards.get_child(i) as Button
		b.modulate = Color(1, 1, 1, 1.0 if s.can_afford(BuildingDefs.DEFS[ids[i]].cost) else 0.45)
		b.button_pressed = world.placing == ids[i]


func _build_army_panel(theme: Theme) -> void:
	_army_panel = PanelContainer.new()
	_army_panel.theme = theme
	_army_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_army_panel.custom_minimum_size = Vector2(360, 0)
	_root.add_child(_army_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_army_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_army_shield = CenterContainer.new()
	_army_shield.custom_minimum_size = Vector2(56, 64)
	head.add_child(_army_shield)
	_army_title = Label.new()
	_army_title.add_theme_font_override("font", UiStyle.font(900))
	_army_title.add_theme_font_size_override("font_size", 20)
	_army_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_army_title)
	UiStyle.gild(_army_title)
	v.add_child(UiStyle.rule())
	_army_text = _rich(14, 340)
	v.add_child(_army_text)
	v.add_child(UiStyle.heading("Formation", 15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for f: String in ArmyView.FORMATIONS:
		var b := Button.new()
		b.text = ArmyView.FORMATION_NAMES[f]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			if not world.selected_army.is_empty():
				world.set_formation(world.selected_army, f)
				_update_army())
		grid.add_child(b)
		_army_buttons[f] = b
	var dis := Button.new()
	dis.text = "Disband (back to the hall)"
	dis.focus_mode = Control.FOCUS_NONE
	dis.pressed.connect(func() -> void:
		if not world.selected_army.is_empty():
			world.disband(world.selected_army))
	v.add_child(dis)
	_army_panel.visible = false


func _update_army() -> void:
	var a: Dictionary = world.selected_army if world != null else {}
	var was := _army_panel.visible
	_army_panel.visible = not a.is_empty()
	if a.is_empty():
		return
	if not was:
		_info.visible = false
		var home := _info_x()
		_army_panel.position.x = home + (-400.0 if UiSettings.panel_left else 400.0)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_army_panel, "position:x", home, 0.25)
		var s := world.me()
		for c in _army_shield.get_children():
			c.queue_free()
		_army_shield.add_child(Emblem.shield(s.color, s.emblem, 60.0))
	_army_title.text = String(a.name)
	var moving := not (a.path as Array).is_empty()
	var lines := PackedStringArray()
	lines.append("[b]%d warriors[/b] and the clan's standard" % int(a.size))
	lines.append(("[color=#8fd07a]Marching[/color] - %d hexes to go" % (a.path as Array).size()) if moving else "Standing in %s" % String(ArmyView.FORMATION_NAMES[a.formation]).to_lower())
	lines.append("[color=#a09070]Click the map to march. Right-click to let go.[/color]")
	_army_text.text = "\n".join(lines)
	for f in _army_buttons:
		(_army_buttons[f] as Button).button_pressed = f == String(a.formation)
	_army_panel.reset_size()


func _update_info() -> void:
	var rec := world.selected if world != null else {}
	var was := _info.visible
	_info.visible = not rec.is_empty()
	if rec.is_empty():
		return
	if not was:
		var home := _info_x()
		_info.position.x = home + (-400.0 if UiSettings.panel_left else 400.0)
		_info.modulate.a = 0.0
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_info, "position:x", home, 0.25)
		tw.tween_property(_info, "modulate:a", 1.0, 0.2)
	var d: Dictionary = BuildingDefs.DEFS[rec.id]
	var s: Settlement = world.settlements[world._settlement_of(rec)]
	_info_title.text = String(d.name)
	_info_icon.texture = BuildingDefs.icon(String(rec.id))
	var lines := PackedStringArray()
	lines.append(String(rec.status) if String(rec.status) != "" else "Standing")
	if s != world.me():
		lines.append("Belongs to %s" % s.player_name)
	if int(d.get("workers", 0)) > 0:
		lines.append("People: %d of %d" % [int(rec.staff), int(d.workers)])
	var recs := BuildingDefs.recipes(String(rec.id), int(rec.kind))
	if not recs.is_empty():
		lines.append("[color=#c8a050]Works%s every %ds:[/color]" % [" (the first it can)" if recs.size() > 1 else "", int(d.get("cycle", 10))])
		var picked := s._pick_recipe(recs)
		for r: Dictionary in recs:
			var mark := "[color=#8fd07a]●[/color] " if r == picked else "[color=#5a5040]○[/color] "
			lines.append(mark + _recipe_bb(r, 20))
	if d.get("tools", false):
		lines.append("[color=#a09070]Wears out tools.[/color]")
	if d.has("housing"):
		lines.append("Homes for %d" % int(d.housing))
	if d.has("storage"):
		lines.append("Stores %d goods" % int(d.storage))
	if d.has("influence"):
		lines.append("+%.1f influence/s" % float(d.influence))
	if d.has("territory"):
		lines.append("Claims land %d hexes round it" % (int(d.territory) + (s.expansions if rec.id == "town_hall" else 0)))
	if int(rec.kind) != 0:
		lines.append("On %s" % NaturalResources.display_name(int(rec.kind)))
	_info_text.text = "\n".join(lines)
	if not s.is_built(rec):
		_info_bar.value = float(rec.progress) * 100.0
	else:
		_info_bar.value = float(rec.timer) / maxf(float(d.get("cycle", 10.0)), 0.1) * 100.0 if d.has("cycle") else 100.0
	_demolish.visible = rec.id != "town_hall" and s == world.me()
	_info.reset_size()
