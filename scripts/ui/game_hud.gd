class_name GameHUD
extends CanvasLayer
## The settlement's interface once the players have landed.
##   - Top bar: whose turn at the controls (click to pass to the next player), people (and how
##     many are idle), influence (and its rate) with "Expand land", every good in stock with its
##     icon, and the game speed (pause, 1x, 2x, 4x).
##   - Build menu (bottom): tabs for Gather, Crafts, People and Military; a card per building
##     with its cost (greyed out when you can't afford it). Click a card, then a hex.
##   - The selected building (left): what it is, what it's doing, its people, what it makes and
##     uses, a bar for its work (or its construction), and "Pull down".
##   - Short messages ("Longhouse finished.") under the top bar.

var world: GameWorld

var _player_btn: Button
var _people: Label
var _influence: Label
var _expand: Button
var _goods_box: HBoxContainer
var _speed_btns: Array[Button] = []
var _tab := "harvest"
var _tabs: Array[Button] = []
var _cards: HBoxContainer
var _info: PanelContainer
var _info_title: Label
var _info_icon: TextureRect
var _info_text: RichTextLabel
var _info_bar: ProgressBar
var _demolish: Button
var _toast: Label
var _toast_t := 0.0
var _hint: Label
var _refresh_t := 0.0


func _ready() -> void:
	layer = 15
	var theme := UiStyle.hud_theme()
	# Top bar.
	var top := PanelContainer.new()
	top.theme = theme
	top.add_theme_stylebox_override("panel", _panel_style(0.9))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 54
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	_player_btn = Button.new()
	_player_btn.focus_mode = Control.FOCUS_NONE
	_player_btn.tooltip_text = "Pass the controls to the next player (Tab)"
	_player_btn.pressed.connect(func() -> void: world.set_active(world.active + 1))
	row.add_child(_player_btn)
	_people = Label.new()
	row.add_child(_people)
	var inf_icon := TextureRect.new()
	inf_icon.texture = Goods.icon("influence")
	inf_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inf_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inf_icon.custom_minimum_size = Vector2(30, 30)
	inf_icon.tooltip_text = "Influence"
	row.add_child(inf_icon)
	_influence = Label.new()
	row.add_child(_influence)
	_expand = Button.new()
	_expand.focus_mode = Control.FOCUS_NONE
	_expand.tooltip_text = "Spend influence to push your land a step further out from the town hall"
	_expand.pressed.connect(func() -> void: world.expand())
	row.add_child(_expand)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_goods_box = HBoxContainer.new()
	_goods_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_goods_box)
	for sp in [[0.0, "❚❚"], [1.0, "1x"], [2.0, "2x"], [4.0, "4x"]]:
		var b := Button.new()
		b.text = sp[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var v: float = sp[0]
		b.pressed.connect(func() -> void:
			if v == 0.0:
				world.paused = not world.paused
			else:
				world.paused = false
				world.speed = v)
		row.add_child(b)
		_speed_btns.append(b)

	# Build menu.
	var bottom := PanelContainer.new()
	bottom.theme = theme
	bottom.add_theme_stylebox_override("panel", _panel_style(0.9))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -150
	bottom.offset_left = 220
	bottom.offset_right = -220
	add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	var tabs := HBoxContainer.new()
	bv.add_child(tabs)
	var title := Label.new()
	title.text = "Build"
	title.add_theme_font_override("font", UiStyle.font(900))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	tabs.add_child(title)
	for cat in BuildingDefs.CATEGORIES:
		var b := Button.new()
		b.text = BuildingDefs.CATEGORY_NAMES[cat]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_tab = cat
			_build_cards())
		tabs.add_child(b)
		_tabs.append(b)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	tabs.add_child(_hint)
	var cs := ScrollContainer.new()
	cs.custom_minimum_size = Vector2(0, 96)
	cs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(cs)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	cs.add_child(_cards)

	# Selected building.
	_info = PanelContainer.new()
	_info.theme = theme
	_info.add_theme_stylebox_override("panel", _panel_style(0.9))
	_info.position = Vector2(12, 66)
	_info.custom_minimum_size = Vector2(330, 0)
	add_child(_info)
	var iv := VBoxContainer.new()
	_info.add_child(iv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	iv.add_child(head)
	_info_icon = TextureRect.new()
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_icon.custom_minimum_size = Vector2(64, 64)
	head.add_child(_info_icon)
	_info_title = Label.new()
	_info_title.add_theme_font_override("font", UiStyle.font(900))
	_info_title.add_theme_font_size_override("font_size", 20)
	_info_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_info_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_info_title)
	_info_text = RichTextLabel.new()
	_info_text.bbcode_enabled = true
	_info_text.fit_content = true
	_info_text.scroll_active = false
	_info_text.custom_minimum_size = Vector2(310, 0)
	_info_text.add_theme_font_size_override("normal_font_size", 14)
	iv.add_child(_info_text)
	_info_bar = ProgressBar.new()
	_info_bar.custom_minimum_size = Vector2(0, 14)
	_info_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.58, 0.24)
	fill.set_corner_radius_all(3)
	_info_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.04)
	bg.set_corner_radius_all(3)
	_info_bar.add_theme_stylebox_override("background", bg)
	iv.add_child(_info_bar)
	_demolish = Button.new()
	_demolish.text = "Pull down"
	_demolish.focus_mode = Control.FOCUS_NONE
	_demolish.pressed.connect(func() -> void: world.demolish(world.selected))
	iv.add_child(_demolish)
	_info.visible = false

	_toast = Label.new()
	_toast.theme = theme
	_toast.add_theme_font_override("font", UiStyle.font(800))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	_toast.add_theme_color_override("font_outline_color", UiStyle.INK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 64
	_toast.offset_left = -400
	_toast.offset_right = 400
	add_child(_toast)
	visible = false


func _panel_style(alpha: float) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.05, 0.04, alpha)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(8)
	st.border_color = Color(0.85, 0.68, 0.32, 0.9)
	st.set_border_width_all(2)
	return st


func open(p_world: GameWorld) -> void:
	world = p_world
	if not world.message.is_connected(show_message):
		world.message.connect(show_message)
		world.selection_changed.connect(func(_r: Dictionary) -> void: _update_info())
	visible = true
	_build_cards()


func show_message(text: String) -> void:
	_toast.text = text
	_toast_t = 3.5
	_toast.modulate.a = 1.0


func _build_cards() -> void:
	for i in _tabs.size():
		_tabs[i].button_pressed = BuildingDefs.CATEGORIES[i] == _tab
	for c in _cards.get_children():
		c.queue_free()
	var s := world.me() if world != null else null
	for id in BuildingDefs.in_category(_tab):
		var d: Dictionary = BuildingDefs.DEFS[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(212, 88)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = world != null and world.placing == id
		# The building's tile, its name, and what it costs as coins and numbers.
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var pic := TextureRect.new()
		pic.texture = BuildingDefs.icon(id)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(72, 72)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var nm := Label.new()
		nm.text = String(d.name)
		nm.add_theme_font_size_override("font_size", 14)
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
		var tip := String(d.desc)
		if d.has("workers") and int(d.workers) > 0:
			tip += "\nPeople: %d" % int(d.workers)
		if d.has("makes"):
			tip += "\nMakes: %s every %ds" % [Goods.describe(d.makes).replace("influence", "Influence"), int(d.get("cycle", 10))]
		if d.has("uses"):
			tip += "\nUses: %s" % Goods.describe(d.uses)
		tip += "\nBuild time: %ds" % int(d.build_time)
		b.tooltip_text = tip
		if s != null and not s.can_afford(d.cost):
			b.modulate = Color(1, 1, 1, 0.45)
		b.pressed.connect(func() -> void:
			if world.placing == id:
				world.cancel_placement()
			else:
				world.begin_placement(id)
			_build_cards())
		_cards.add_child(b)


func _process(delta: float) -> void:
	if not visible or world == null or world.me() == null:
		return
	var s := world.me()
	_player_btn.text = "  %s  " % s.player_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = s.color.darkened(0.25)
	sb.set_corner_radius_all(5)
	sb.border_color = UiStyle.GOLD
	sb.set_border_width_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	_player_btn.add_theme_stylebox_override("normal", sb)
	_people.text = "People %d/%d  (%d idle)" % [s.population, s.housing(), s.idle()]
	_influence.text = "%d  (+%.1f/s)" % [int(s.influence), s.influence_rate()]
	_expand.text = "Expand land (%d)" % s.expand_cost()
	_expand.disabled = s.influence < s.expand_cost()
	_speed_btns[0].button_pressed = world.paused
	for i in range(1, 4):
		_speed_btns[i].button_pressed = not world.paused and is_equal_approx(world.speed, [0.0, 1.0, 2.0, 4.0][i])
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.4
		_update_goods(s)
		_build_cards_affordable(s)
		_update_info()
	if world.placing != "":
		_hint.text = "Placing %s: click a hex on your land (Shift: place more).  Right-click or Esc to stop." % String(BuildingDefs.DEFS[world.placing].name)
	else:
		_hint.text = "Click a building to see what it's doing."
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


func _update_goods(s: Settlement) -> void:
	for c in _goods_box.get_children():
		c.queue_free()
	var store := Label.new()
	store.text = "Stores %d/%d" % [int(s.stored()), s.storage()]
	store.modulate = Color(1, 0.7, 0.6) if s.stored() >= s.storage() else Color.WHITE
	_goods_box.add_child(store)
	for id in Goods.ORDER:
		var n := float(s.stock.get(id, 0))
		if n < 0.5 and not id in ["wood", "stone", "grain", "fish"]:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		item.tooltip_text = Goods.display_name(id)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		var tex := Goods.icon(id)
		if tex != null:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(28, 28)
			item.add_child(ic)
		else:
			var chip := ColorRect.new()
			chip.color = Goods.color(id)
			chip.custom_minimum_size = Vector2(12, 12)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item.add_child(chip)
		var l := Label.new()
		l.text = "%s %d" % [Goods.display_name(id) if tex == null else "", int(n)]
		item.add_child(l)
		_goods_box.add_child(item)


func _build_cards_affordable(s: Settlement) -> void:
	var ids := BuildingDefs.in_category(_tab)
	for i in mini(ids.size(), _cards.get_child_count()):
		var b := _cards.get_child(i) as Button
		b.modulate = Color(1, 1, 1, 1.0 if s.can_afford(BuildingDefs.DEFS[ids[i]].cost) else 0.45)
		b.button_pressed = world.placing == ids[i]


func _update_info() -> void:
	var rec := world.selected if world != null else {}
	_info.visible = not rec.is_empty()
	if rec.is_empty():
		return
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
	var gains: Dictionary = d.yields.get(int(rec.kind), {}) if d.has("yields") else d.get("makes", {})
	if not gains.is_empty():
		lines.append("Makes  %s  every %ds" % [Goods.bbcode(gains, 22, "+"), int(d.get("cycle", 10))])
	if d.has("uses"):
		lines.append("Uses  %s" % Goods.bbcode(d.uses, 22, "-"))
	if d.has("housing"):
		lines.append("Homes for %d" % int(d.housing))
	if d.has("storage"):
		lines.append("Stores %d goods" % int(d.storage))
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
