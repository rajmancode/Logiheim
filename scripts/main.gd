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
	out.sort()
	return out


func _load_map(i: int) -> void:
	map_index = posmod(i, map_dirs.size())
	hovered = -1
	selected = -1
	if not hex_map.load_map(map_dirs[map_index]):
		hud.text = "Failed to load %s (see the Output panel)" % map_dirs[map_index]
		return
	var size := hex_map.source.world_size
	cam.ground_height = hex_map.surface_height(size * 0.5)
	cam.frame_rect(Rect2(Vector2.ZERO, size))
	atmosphere.configure(size, hex_map.levels[0].max_top_y())


func _rebuild() -> void:
	hovered = -1
	selected = -1
	hex_map.rebuild()


func _process(_delta: float) -> void:
	if hex_map.current_level() == null:
		return
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
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			selected = hovered
			hex_map.set_highlight("select", selected)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var s := hex_map.settings
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
	lines.append(_describe("Hover", level, hovered))
	lines.append(_describe("Selected", level, selected))
	lines.append("")
	lines.append("WASD / arrows / middle-drag: pan    wheel: zoom    Q E / right-drag: rotate    click: select")
	lines.append("- =: height scale    1-5: force level    0: auto LOD    G: grid    T: trees    H: hide    F5: new seed")
	lines.append("N: pause/run day cycle    , .: time -/+ 1 h    R: weather (clear / cloudy / rain)    I: resource icons    C: explore nearest cave")
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
	hud_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(hud_panel)
	var box := VBoxContainer.new()
	hud_panel.add_child(box)
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
