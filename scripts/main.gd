extends Node3D
## Demo scene: loads Gaea maps from res://data/gaea, sets up lighting, the camera and a HUD,
## and handles hex hover/selection plus runtime controls.

const MAPS_ROOT := "res://data/gaea"

var hex_map: HexMap
var cam: StrategyCamera
var atmosphere: Atmosphere
var hud: Label
var hud_panel: PanelContainer

var map_dirs: PackedStringArray = []
var map_index := 0
var hovered := -1
var selected := -1
var show_grid := true
var seed_edit: LineEdit
var cave_env: Environment
var _surface_cam := {}
var loading: LoadingScreen
var landing_ui: LandingUI
var landing_markers: LandingMarkers
var landing_sites: LandingSites
## The players and where they came ashore, once landings are chosen ([] before).
var landings: Array = []
var game_world: GameWorld
var game_hud: GameHUD


func _ready() -> void:
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	hex_map = HexMap.new()
	hex_map.name = "HexMap"
	hex_map.settings = HexMapSettings.new()
	# --seed=N on the command line (after --) picks the map seed.
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--seed="):
			hex_map.settings.seed = int(arg.trim_prefix("--seed="))
	hex_map.level_changed.connect(_on_level_changed)
	add_child(hex_map)

	cam = StrategyCamera.new()
	cam.name = "StrategyCamera"
	add_child(cam)
	_setup_hud()
	loading = LoadingScreen.new()
	loading.name = "LoadingScreen"
	add_child(loading)
	hex_map.progress.connect(loading.set_progress)
	hex_map.chart_layer.connect(loading.add_layer)
	hex_map.chart_layers = not OS.has_environment("LOGIHEIM_SYNC_BUILD")
	landing_markers = LandingMarkers.new()
	landing_markers.name = "LandingMarkers"
	add_child(landing_markers)
	landing_ui = LandingUI.new()
	landing_ui.name = "LandingUI"
	add_child(landing_ui)
	landing_ui.site_focused.connect(_on_site_focused)
	landing_ui.finished.connect(_on_landings_chosen)
	game_world = GameWorld.new()
	game_world.name = "GameWorld"
	add_child(game_world)
	game_hud = GameHUD.new()
	game_hud.name = "GameHUD"
	add_child(game_hud)

	map_dirs = _find_maps()
	if map_dirs.is_empty():
		hud.text = "No maps found. Put a Gaea export with a map.json under %s/<map_name>/" % MAPS_ROOT
		return
	_load_map(0)


func _find_maps() -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(MAPS_ROOT):
		var dir := MAPS_ROOT.path_join(d)
		if FileAccess.file_exists(dir.path_join("map.json")):
			out.append(dir)
	# Maps list by their "order" in map.json (then by name): the island made for settling first.
	var order := func(d: String) -> int:
		var meta = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("map.json")))
		return int(meta.get("order", 100)) if meta is Dictionary else 100
	var arr := Array(out)
	arr.sort_custom(func(a, b): return order.call(a) < order.call(b) or (order.call(a) == order.call(b) and a < b))
	return PackedStringArray(arr)


func _load_map(i: int) -> void:
	if hex_map.building:
		return
	map_index = posmod(i, map_dirs.size())
	hovered = -1
	selected = -1
	_before_build(TerrainSource.load_from_dir(map_dirs[map_index]))
	if not await hex_map.load_map(map_dirs[map_index]):
		loading.visible = false
		hud_panel.visible = true
		hud.text = "Failed to load %s (see the Output panel)" % map_dirs[map_index]
		return
	var size := hex_map.source.world_size
	cam.ground_height = hex_map.surface_height(size * 0.5)
	cam.frame_rect(Rect2(Vector2.ZERO, size))
	atmosphere.configure(size, hex_map.levels[0].max_top_y())
	_after_build()


func _rebuild() -> void:
	if hex_map.building:
		return
	hovered = -1
	selected = -1
	_before_build(hex_map.source)
	await hex_map.rebuild()
	_after_build()


## The loading screen over everything while the map builds.
func _before_build(src: TerrainSource) -> void:
	landing_ui.visible = false
	game_world.clear()
	game_hud.visible = false
	if OS.has_environment("LOGIHEIM_SYNC_BUILD"):
		return
	hud_panel.visible = false
	loading.begin(src)


## Map ready: fade the loading screen and open the landing chooser on its coast.
func _after_build() -> void:
	hud_panel.visible = true
	landings = []
	landing_sites = hex_map.landing if hex_map.landing != null else LandingSites.find(hex_map, 10)
	landing_markers.build(landing_sites.sites)
	# (Tools and tests that build in one go skip the screens.)
	if OS.has_environment("LOGIHEIM_SYNC_BUILD"):
		landing_markers.visible = OS.has_environment("LOGIHEIM_LANDINGS")
		if OS.has_environment("LOGIHEIM_LANDINGS"):
			landing_ui.open(landing_sites.sites, hex_map.source.name)
		return
	loading.finish()
	landing_markers.visible = true
	landing_markers.show_all()
	landing_ui.open(landing_sites.sites, hex_map.source.name)
	landing_markers.update_state(landing_ui.players, landing_ui.focused)


func _on_site_focused(index: int) -> void:
	var s: Dictionary = landing_sites.sites[index]
	var p: Vector2 = s.p
	cam.set("_target", Vector3(p.x, float(s.y), p.y))
	cam.set("_target_distance", 260.0)
	landing_markers.update_state(landing_ui.players, index)


## Everyone has a landing: their town halls go up there and the game begins, the view on the
## first player's.
func _on_landings_chosen(players: Array) -> void:
	landings = players.duplicate(true)
	landing_markers.visible = false
	if not players.is_empty():
		_on_site_focused(players[0].site)
	game_world.start(hex_map, players, landing_sites.sites)
	game_hud.open(game_world)
	hud_panel.visible = false


func _process(_delta: float) -> void:
	if hex_map.current_level() == null or hex_map.building:
		return
	if landing_ui.is_open():
		landing_markers.update_state(landing_ui.players, landing_ui.focused)
	if hex_map.underground >= 0:
		var cp := cam.position
		cam.ground_height = hex_map.cave_floor(Vector2(cp.x, cp.z))
		_update_hud()
		return
	hex_map.update_lod(cam.distance)
	atmosphere.update_view(cam.position, cam.distance)
	var p := cam.position
	cam.ground_height = hex_map.surface_height(Vector2(p.x, p.z))

	var mouse := get_viewport().get_mouse_position()
	var cell := hex_map.pick(cam.camera.project_ray_origin(mouse), cam.camera.project_ray_normal(mouse))
	if cell != hovered:
		hovered = cell
		hex_map.set_highlight("hover", hovered)
	if game_world.running:
		var over_ui := get_viewport().gui_get_hovered_control() != null
		game_world.hover(-1 if cell < 0 or over_ui else hex_map.finest_cell_at(Vector2(hex_map.last_pick.x, hex_map.last_pick.z)))
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and game_world.running and game_world.right_click():
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and game_world.running and hovered >= 0:
			if game_world.click(hex_map.finest_cell_at(Vector2(hex_map.last_pick.x, hex_map.last_pick.z))):
				return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# While choosing landings, a click on (or near) a banner picks that site.
			if landing_ui.is_open() and hovered >= 0:
				var lv := hex_map.current_level()
				var near := landing_markers.site_near(lv.cell_center(hovered), maxf(45.0, lv.hex_size * 2.5))
				if near >= 0:
					landing_ui.focus(near)
					return
			selected = hovered
			hex_map.set_highlight("select", selected)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or hex_map.building:
		return
	var s := hex_map.settings
	if game_world.running:
		match key.keycode:
			KEY_ESCAPE:
				if game_world.placing != "":
					game_world.cancel_placement()
					return
				if not game_world.selected.is_empty() or game_world.selected_resource >= 0:
					game_world.select({})
					return
				if not game_world.selected_army.is_empty():
					game_world.select_army({})
					return
			KEY_TAB:
				game_world.set_active(game_world.active + 1)
				return
			KEY_SPACE:
				game_world.paused = not game_world.paused
				return
	match key.keycode:
		KEY_C:
			_toggle_cave()
		KEY_ESCAPE:
			if hex_map.underground >= 0:
				_toggle_cave()
		KEY_F5:
			# A new random world from the same terrain.
			_set_seed(randi() % 1000000)
		KEY_MINUS:
			s.height_scale = maxf(0.25, s.height_scale - 0.25)
			_rebuild()
		KEY_EQUAL:
			s.height_scale = minf(5.0, s.height_scale + 0.25)
			_rebuild()
		KEY_0:
			hex_map.auto_lod = true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			hex_map.auto_lod = false
			hex_map.set_level(key.keycode - KEY_1)
		KEY_G:
			show_grid = not show_grid
			hex_map.set_grid_visible(show_grid)
		KEY_T:
			s.trees_enabled = not s.trees_enabled
			_rebuild()
		KEY_M:
			if not map_dirs.is_empty():
				_load_map(map_index + 1)
		KEY_H:
			hud_panel.visible = not hud_panel.visible
		KEY_N:
			atmosphere.cycle_running = not atmosphere.cycle_running
		KEY_COMMA:
			atmosphere.shift_time(-1.0)
		KEY_PERIOD:
			atmosphere.shift_time(1.0)
		KEY_R:
			atmosphere.cycle_weather()
		KEY_I:
			hex_map.set_resource_icons_visible(not hex_map.resource_icons_visible())
		KEY_L:
			# Back to the landing chooser (landings kept).
			if landing_sites != null and not hex_map.building and not game_world.running:
				landing_markers.show_all()
				landing_ui.reopen()
				landing_markers.update_state(landing_ui.players, landing_ui.focused)


## Into the cave nearest the view (or the hovered cave entrance), or back out.
func _toggle_cave() -> void:
	if hex_map.underground >= 0:
		hex_map.exit_cave()
		atmosphere.underground = false
		cam.camera.environment = null
		for k in _surface_cam:
			cam.set(k, _surface_cam[k])
		cam.set("_target_distance", 260.0)
		return
	var si := hex_map.nearest_cave(Vector2(cam.position.x, cam.position.z), 2000.0)
	var info := hex_map.enter_cave(si)
	if info.is_empty():
		return
	for k in ["min_distance", "max_distance", "near_pitch_deg", "far_pitch_deg", "bounds", "position", "_target"]:
		_surface_cam[k] = cam.get(k)
	var view: Vector3 = info.view
	var box: AABB = info.bounds
	cam.min_distance = 6.0
	cam.max_distance = 90.0
	cam.near_pitch_deg = 30.0
	cam.far_pitch_deg = 62.0
	cam.bounds = Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	cam.set("_target", view)
	cam.position = view
	cam.set("_target_distance", 40.0)
	cam.distance = 40.0
	atmosphere.underground = true
	if cave_env == null:
		cave_env = Environment.new()
		cave_env.background_mode = Environment.BG_COLOR
		cave_env.background_color = Color(0.01, 0.01, 0.012)
		cave_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		cave_env.ambient_light_color = Color(0.32, 0.3, 0.28)
		cave_env.ambient_light_energy = 0.35
		cave_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		cave_env.glow_enabled = true
		cave_env.glow_intensity = 0.6
		cave_env.ssao_enabled = true
	cam.camera.environment = cave_env


func _on_level_changed(_i: int) -> void:
	hovered = -1
	selected = -1


func _update_hud() -> void:
	var level := hex_map.current_level()
	var src := hex_map.source
	var s := hex_map.settings
	var lines := PackedStringArray()
	if hex_map.underground >= 0:
		var sy: Dictionary = hex_map.cave_plan.systems[hex_map.underground]
		var names := PackedStringArray()
		for k: int in sy.kinds:
			names.append(NaturalResources.display_name(k))
		lines.append("Cave %d%s: %s   (%d entrances)" % [hex_map.underground + 1, " (lava tube)" if sy.lava else "", ", ".join(names), sy.entrances.size()])
		lines.append("WASD / drag: move    wheel: zoom    Q E: rotate    C or Esc: back to the surface")
		hud.text = "\n".join(lines)
		return
	lines.append("%s   %d x %d m   (map %d/%d, M = next)   seed %d" % [src.name, src.world_size.x, src.world_size.y, map_index + 1, map_dirs.size(), s.seed])
	lines.append("Level %d/%d   hex %.1f m   %d x %d = %d cells   %s" % [
		level.level_index + 1, hex_map.levels.size(), level.hex_size, level.cols, level.rows,
		level.cell_count(), "auto LOD" if hex_map.auto_lod else "manual LOD"])
	lines.append("Step %.1f m   height x%.2f   view %.0f m" % [s.step_height, s.height_scale, cam.distance])
	lines.append(atmosphere.describe())
	if not landings.is_empty():
		var who := PackedStringArray()
		for p: Dictionary in landings:
			who.append("%s at %s" % [p.name, landing_sites.sites[p.site].name])
		lines.append("Landings: " + ", ".join(who) + "   (L: choose again)")
	lines.append(_describe("Hover", level, hovered))
	lines.append(_describe("Selected", level, selected))
	lines.append("")
	lines.append("WASD / arrows / middle-drag: pan    wheel: zoom    Q E / right-drag: rotate    click: select")
	lines.append("- =: height scale    1-5: force level    0: auto LOD    G: grid    T: trees    H: hide    F5: new seed")
	lines.append("N: pause/run day cycle    , .: time -/+ 1 h    R: weather (clear / cloudy / rain)    I: resource icons    C: explore nearest cave    L: landings")
	hud.text = "\n".join(lines)


func _describe(label: String, level: HexLevel, i: int) -> String:
	if i < 0:
		return "%s: -" % label
	var a := level.coords[i]
	var text := "%s: (%d, %d) %s, elevation %d (%.0f m), slope %.2f" % [
		label, a.x, a.y, HexMapGenerator.TERRAIN_NAMES[level.terrain[i]],
		level.elevation[i], level.top_y(i), level.slope[i]]
	if level.river[i] == 1:
		text += ", river %.0f m wide" % level.river_width[i]
	if level.lake[i] == 1:
		text += ", lake"
	if level.road.size() > i and level.road[i] == 1:
		text += ", trail"
	if level.cave.size() > i and level.cave[i] >= 0:
		text += ", cave entrance"
	text += ", move cost %.1f" % level.move_cost(i)
	if level.floodplain[i] == 1:
		text += ", floodplain" + (" (flooded)" if atmosphere.flood > 0.5 else "")
	if level.resource[i] != 0:
		text += ", %s (%s)" % [NaturalResources.display_name(level.resource[i]), ["", "small", "good", "rich"][level.resource_amount[i]]]
		if level.resource2.size() > i and level.resource2[i] != 0:
			text += " with %s" % NaturalResources.display_name(level.resource2[i])
		var dep := level.deposit[i]
		if dep >= 0 and dep < level.deposits.size():
			text += " in a %d-hex deposit" % level.deposits[dep].size
	var up := level.parent[i]
	if up >= 0:
		var pa := hex_map.levels[level.level_index + 1].coords[up]
		text += ", parent (%d, %d)" % [pa.x, pa.y]
	if not level.children[i].is_empty():
		text += ", %d children" % level.children[i].size()
	return text


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	style.border_color = Color(0.85, 0.68, 0.32, 0.85)
	style.set_border_width_all(2)
	hud_panel.add_theme_stylebox_override("panel", style)
	hud_panel.theme = UiStyle.hud_theme()
	layer.add_child(hud_panel)
	var box := VBoxContainer.new()
	hud_panel.add_child(box)
	var title := Label.new()
	title.text = "Logiheim"
	title.add_theme_font_override("font", UiStyle.font(900))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	title.add_theme_color_override("font_outline_color", UiStyle.INK)
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	UiStyle.gild(title)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 14)
	box.add_child(hud)
	# Seed: type a number and press Enter (or F5 for a random one).
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = "Seed:"
	row.add_child(label)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(120, 0)
	seed_edit.text = str(hex_map.settings.seed)
	seed_edit.text_submitted.connect(func(t: String) -> void:
		seed_edit.release_focus()
		if t.strip_edges().is_valid_int():
			_set_seed(int(t.strip_edges())))
	row.add_child(seed_edit)
	var btn := Button.new()
	btn.text = "Random"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: _set_seed(randi() % 1000000))
	row.add_child(btn)


func _set_seed(s: int) -> void:
	hex_map.settings.seed = s
	if seed_edit != null:
		seed_edit.text = str(s)
	_rebuild()
