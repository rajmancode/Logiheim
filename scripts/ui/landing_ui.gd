class_name LandingUI
extends CanvasLayer
## "Choose your landing": before play, each player picks where on the coast to come ashore.
##
## The map's landing sites (LandingSites) stand on the map as banners and are listed here with
## their stars and what they offer. Set how many players there are (1-6) and their names, then
## for each player pick a site - click its banner on the map or its entry in the list - and
## claim it. Sites already claimed are taken. "Random landings" fills in the rest; "Set sail"
## starts once everyone has a landing. Reopen with L. Each player's shield shows their clan's
## emblem; "Banner" opens the EmblemEditor to choose colours, pattern and charge.

signal site_focused(index: int)
## Emitted with [{name, color, site (index)}] once every player has a landing.
signal finished(players: Array)

const COLORS := [Color(0.85, 0.2, 0.18), Color(0.2, 0.45, 0.9), Color(0.25, 0.7, 0.3),
	Color(0.95, 0.75, 0.2), Color(0.6, 0.3, 0.8), Color(0.92, 0.92, 0.9)]
const DEFAULT_NAMES := ["Ragnhild", "Sigurd", "Astrid", "Bjorn", "Freydis", "Leif"]

var sites: Array = []
var players: Array = []          # {name, color, site}
var current := 0                 # player choosing now
var focused := -1                # site shown in the card

var _panel: PanelContainer
var _players_box: VBoxContainer
var _sites_box: VBoxContainer
var _card: Label
var _claim: Button
var _start: Button
var _count_label: Label
var _map_name: Label
var _editor: EmblemEditor


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.theme = UiStyle.hud_theme()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -440
	_panel.offset_right = -12
	_panel.offset_top = 12
	_panel.offset_bottom = -12
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Choose your landing"
	title.add_theme_font_override("font", UiStyle.font(900))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	title.add_theme_color_override("font_outline_color", UiStyle.INK)
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	_map_name = Label.new()
	_map_name.add_theme_font_size_override("font_size", 13)
	_map_name.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_map_name)

	# Players: how many, their names, and where each has landed.
	var head := HBoxContainer.new()
	box.add_child(head)
	var pl := _heading("Players")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(pl)
	head.add_child(_small_button("−", func() -> void: _set_count(players.size() - 1)))
	_count_label = Label.new()
	_count_label.custom_minimum_size = Vector2(26, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_count_label)
	head.add_child(_small_button("+", func() -> void: _set_count(players.size() + 1)))
	_players_box = VBoxContainer.new()
	box.add_child(_players_box)

	box.add_child(HSeparator.new())
	box.add_child(_heading("Landing sites"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(10, 0)
	box.add_child(scroll)
	_sites_box = VBoxContainer.new()
	_sites_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sites_box)

	box.add_child(HSeparator.new())
	_card = Label.new()
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.custom_minimum_size = Vector2(10, 96)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_theme_font_size_override("font_size", 14)
	box.add_child(_card)
	_claim = Button.new()
	_claim.clip_text = true
	_claim.pressed.connect(_on_claim)
	box.add_child(_claim)
	var row := HBoxContainer.new()
	box.add_child(row)
	var rnd := Button.new()
	rnd.text = "Random landings"
	rnd.clip_text = true
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rnd.pressed.connect(_random_landings)
	row.add_child(rnd)
	_start = Button.new()
	_start.text = "Set sail"
	_start.clip_text = true
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.pressed.connect(_on_start)
	row.add_child(_start)
	for b in [_claim, rnd, _start]:
		(b as Button).focus_mode = Control.FOCUS_NONE
	_editor = EmblemEditor.new()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_editor.offset_right = -460
	_editor.offset_left = -860
	_editor.offset_top = -340
	_editor.offset_bottom = 340
	_editor.changed.connect(func() -> void: _refresh_players())
	add_child(_editor)
	visible = false


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiStyle.font(900))
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UiStyle.GOLD)
	return l


func _small_button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(30, 0)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Opens the chooser for a freshly built map. Keeps the players (names, count) from before, but
## their landings are cleared: the sites are new.
func open(p_sites: Array, map_name: String) -> void:
	sites = p_sites
	_map_name.text = "%s - %d landing sites" % [map_name, sites.size()]
	if players.is_empty():
		_set_count(2, false)
	for p: Dictionary in players:
		p.site = -1
	current = 0
	focused = -1
	visible = true
	_refresh()
	if not sites.is_empty():
		focus(0)


## Reopens the chooser on the current map, landings kept.
func reopen() -> void:
	visible = true
	_refresh()


func is_open() -> bool:
	return visible


func focus(index: int) -> void:
	if index < 0 or index >= sites.size():
		return
	focused = index
	site_focused.emit(index)
	_refresh()


func owner_of(site: int) -> int:
	for k in players.size():
		if players[k].site == site:
			return k
	return -1


func _set_count(n: int, refresh := true) -> void:
	n = clampi(n, 1, mini(COLORS.size(), maxi(sites.size(), 1)))
	while players.size() < n:
		var k := players.size()
		players.append({"name": DEFAULT_NAMES[k], "color": COLORS[k], "site": -1, "emblem": Emblem.default_for(k)})
	while players.size() > n:
		players.pop_back()
	current = clampi(current, 0, players.size() - 1)
	if refresh:
		_refresh()


func _on_claim() -> void:
	if focused < 0:
		return
	var who := owner_of(focused)
	if who == current:
		players[current].site = -1      # release it
	elif who < 0:
		players[current].site = focused
		# On to the next player still without a landing.
		for k in players.size():
			var c := (current + 1 + k) % players.size()
			if players[c].site < 0:
				current = c
				break
	_refresh()


func _random_landings() -> void:
	var free: Array = []
	for i in sites.size():
		if owner_of(i) < 0:
			free.append(i)
	free.shuffle()
	for p: Dictionary in players:
		if p.site < 0 and not free.is_empty():
			p.site = free.pop_back()
	_refresh()


func _on_start() -> void:
	for p: Dictionary in players:
		if p.site < 0:
			return
	visible = false
	finished.emit(players)


func _refresh() -> void:
	_refresh_players()
	_refresh_sites()


func _refresh_players() -> void:
	_count_label.text = str(players.size())
	for c in _players_box.get_children():
		c.queue_free()
	for k in players.size():
		var p: Dictionary = players[k]
		var row := HBoxContainer.new()
		# The clan's shield: click to choose for this player.
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(40, 44)
		sw.focus_mode = Control.FOCUS_NONE
		sw.flat = true
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.set_corner_radius_all(6)
		st.set_border_width_all(2 if k == current else 0)
		st.border_color = UiStyle.GOLD
		for state in ["normal", "hover", "pressed"]:
			sw.add_theme_stylebox_override(state, st)
		var sh := Emblem.shield(p.color, p.get("emblem", Emblem.default_for(k)), 40.0)
		sh.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		sh.offset_left = -17
		sh.offset_right = 17
		sh.offset_top = -20
		sh.offset_bottom = 20
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(sh)
		sw.tooltip_text = "Choose for this player"
		sw.pressed.connect(func() -> void:
			current = k
			if p.site >= 0:
				focus(p.site)
			_refresh())
		row.add_child(sw)
		var name_edit := LineEdit.new()
		name_edit.text = p.name
		name_edit.custom_minimum_size = Vector2(120, 0)
		name_edit.text_changed.connect(func(t: String) -> void: p.name = t)
		name_edit.text_submitted.connect(func(_t: String) -> void:
			name_edit.release_focus()
			_refresh())
		row.add_child(name_edit)
		var where := Label.new()
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		where.clip_text = true
		where.custom_minimum_size = Vector2(10, 0)
		where.text = ("→ " + sites[p.site].name) if p.site >= 0 else ("choosing…" if k == current else "—")
		where.modulate = Color(1, 1, 1, 1.0 if p.site >= 0 or k == current else 0.6)
		row.add_child(where)
		var ban := Button.new()
		ban.text = "Banner"
		ban.focus_mode = Control.FOCUS_NONE
		ban.tooltip_text = "Choose this clan's colours, pattern and charge"
		ban.add_theme_font_size_override("font_size", 12)
		ban.pressed.connect(func() -> void: _editor.edit(p))
		row.add_child(ban)
		_players_box.add_child(row)


func _refresh_sites() -> void:
	for c in _sites_box.get_children():
		c.queue_free()
	for i in sites.size():
		var s: Dictionary = sites[i]
		var who := owner_of(i)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Long entries are cut short rather than widening the panel.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(10, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = i == focused
		var stars := "★".repeat(s.stars) + "☆".repeat(5 - s.stars)
		var tags: PackedStringArray = s.tags
		b.text = "%s   %s\n%s" % [s.name, stars, ", ".join(tags.slice(0, 6))]
		if who >= 0:
			b.text += "\nLanding of %s" % players[who].name
			b.add_theme_color_override("font_color", players[who].color.lightened(0.3))
		b.pressed.connect(func() -> void: focus(i))
		_sites_box.add_child(b)

	if focused >= 0:
		var s: Dictionary = sites[focused]
		var lines := PackedStringArray()
		lines.append("%s   %s" % [s.name, "★".repeat(s.stars) + "☆".repeat(5 - s.stars)])
		var feats := PackedStringArray()
		feats.append("a beach to draw the ships up" if s.beach else "a rocky landing")
		feats.append("fresh water close by" if s.water else "no river or lake close by")
		feats.append("a sheltered bay" if s.shelter > 0.6 else "an open shore")
		var ft := ", ".join(feats)
		lines.append(ft.substr(0, 1).to_upper() + ft.substr(1) + ".")
		var res: Dictionary = s.resources
		if res.is_empty():
			lines.append("No resources nearby.")
		else:
			var kinds := res.keys()
			kinds.sort_custom(func(x, y): return res[x] > res[y])
			var names := PackedStringArray()
			for k in kinds.slice(0, 7):
				names.append(NaturalResources.display_name(k))
			lines.append("Nearby: " + ", ".join(names) + ".")
		_card.text = "\n".join(lines)
		var who := owner_of(focused)
		if who == current:
			_claim.text = "Give up this landing"
			_claim.disabled = false
		elif who >= 0:
			_claim.text = "Taken by %s" % players[who].name
			_claim.disabled = true
		else:
			_claim.text = "Land here - %s" % players[current].name
			_claim.disabled = false
	else:
		_card.text = "Pick a landing site: click a banner on the map, or one in the list."
		_claim.text = "Land here"
		_claim.disabled = true
	var ready := true
	for p: Dictionary in players:
		if p.site < 0:
			ready = false
	_start.disabled = not ready
	_start.text = "Set sail" if ready else "Set sail (%d left)" % players.filter(func(p): return p.site < 0).size()
