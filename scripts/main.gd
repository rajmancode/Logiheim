extends Node3D
## Demo scene: loads Gaea maps from res://data/gaea, sets up lighting, the camera and a HUD,
## and handles hex hover/selection plus runtime controls.

const MAPS_ROOT := "res://data/gaea"

var hex_map: HexMap
var cam: StrategyCamera
var sun: DirectionalLight3D
var hud: Label
var hud_panel: PanelContainer

var map_dirs: PackedStringArray = []
var map_index := 0
var hovered := -1
var selected := -1
var show_grid := true


func _ready() -> void:
	_setup_environment()
	hex_map = HexMap.new()
	hex_map.name = "HexMap"
	hex_map.settings = HexMapSettings.new()
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
	sun.directional_shadow_max_distance = maxf(size.x, size.y) * 2.0


func _rebuild() -> void:
	hovered = -1
	selected = -1
	hex_map.rebuild()


func _process(_delta: float) -> void:
	if hex_map.current_level() == null:
		return
	hex_map.update_lod(cam.distance)
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
		KEY_BRACKETLEFT:
			s.base_hex_size = maxf(4.0, s.base_hex_size / 1.25)
			_rebuild()
		KEY_BRACKETRIGHT:
			s.base_hex_size = minf(200.0, s.base_hex_size * 1.25)
			_rebuild()
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


func _on_level_changed(_i: int) -> void:
	hovered = -1
	selected = -1


func _update_hud() -> void:
	var level := hex_map.current_level()
	var src := hex_map.source
	var s := hex_map.settings
	var lines := PackedStringArray()
	lines.append("%s   %d x %d m   (map %d/%d, M = next)" % [src.name, src.world_size.x, src.world_size.y, map_index + 1, map_dirs.size()])
	lines.append("Level %d/%d   hex %.1f m   %d x %d = %d cells   %s" % [
		level.level_index + 1, hex_map.levels.size(), level.hex_size, level.cols, level.rows,
		level.cell_count(), "auto LOD" if hex_map.auto_lod else "manual LOD"])
	lines.append("Step %.1f m   height x%.2f   view %.0f m" % [s.step_height, s.height_scale, cam.distance])
	lines.append(_describe("Hover", level, hovered))
	lines.append(_describe("Selected", level, selected))
	lines.append("")
	lines.append("WASD / arrows / middle-drag: pan    wheel: zoom    Q E / right-drag: rotate    click: select")
	lines.append("[ ]: hex size    - =: height scale    1-5: force level    0: auto LOD    G: grid    T: trees    H: hide")
	hud.text = "\n".join(lines)


func _describe(label: String, level: HexLevel, i: int) -> String:
	if i < 0:
		return "%s: -" % label
	var a := level.coords[i]
	var text := "%s: (%d, %d) %s, elevation %d (%.0f m), slope %.2f" % [
		label, a.x, a.y, HexMapGenerator.TERRAIN_NAMES[level.terrain[i]],
		level.elevation[i], level.top_y(i), level.slope[i]]
	var up := level.parent[i]
	if up >= 0:
		var pa := hex_map.levels[level.level_index + 1].coords[up]
		text += ", parent (%d, %d)" % [pa.x, pa.y]
	if not level.children[i].is_empty():
		text += ", %d children" % level.children[i].size()
	return text


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.7, 0.76, 0.82)
	sky_mat.ground_horizon_color = Color(0.7, 0.76, 0.82)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.82)
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 4000.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


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
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 14)
	hud_panel.add_child(hud)
