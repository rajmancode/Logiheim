class_name HexMap
extends Node3D
## Loads a Gaea export, builds every hex level (LOD) and shows one at a time.

signal generated
signal level_changed(level_index: int)

@export var settings: HexMapSettings

var source: TerrainSource
var levels: Array[HexLevel] = []
var active_level := -1
var auto_lod := true

var _level_roots: Array[Node3D] = []
var _material: ShaderMaterial


## Loads map.json from map_dir and builds the map. Returns false if loading failed.
func load_map(map_dir: String) -> bool:
	var src := TerrainSource.load_from_dir(map_dir)
	if src == null:
		return false
	source = src
	rebuild()
	return true


## Rebuilds all levels from the current source and settings (e.g. after changing hex size).
func rebuild() -> void:
	if source == null:
		return
	if settings == null:
		settings = HexMapSettings.new()
	if _material == null:
		_material = TerrainMaterial.create()
	_clear()

	var t0 := Time.get_ticks_msec()
	levels = HexMapGenerator.new(source, settings).build_levels()
	for level in levels:
		var root := Node3D.new()
		root.name = "Level%d" % level.level_index
		root.visible = false
		add_child(root)
		HexMeshBuilder.build(level, settings, _material, root)
		if settings.trees_enabled:
			TreeScatter.build(level, settings, root)
		_level_roots.append(root)
	print("HexMap: built %d levels for '%s' in %d ms" % [levels.size(), source.name, Time.get_ticks_msec() - t0])

	active_level = -1
	set_level(0)
	generated.emit()


func _clear() -> void:
	for root in _level_roots:
		root.queue_free()
	_level_roots.clear()
	levels.clear()
	set_highlight("hover", -1)
	set_highlight("select", -1)


func current_level() -> HexLevel:
	return levels[active_level] if active_level >= 0 and active_level < levels.size() else null


func set_level(i: int) -> void:
	i = clampi(i, 0, levels.size() - 1)
	if i == active_level:
		return
	active_level = i
	for k in _level_roots.size():
		_level_roots[k].visible = k == i
	set_highlight("hover", -1)
	set_highlight("select", -1)
	level_changed.emit(i)


## Picks the coarsest level whose hexes are still big enough on screen, with a little hysteresis.
func update_lod(camera_distance: float) -> void:
	if not auto_lod or levels.is_empty():
		return
	var want := 0
	for i in range(1, levels.size()):
		var threshold := levels[i].hex_size * settings.lod_distance_factor
		if i <= active_level:
			threshold *= 0.9
		if camera_distance > threshold:
			want = i
	set_level(want)


## kind is "hover" or "select"; cell -1 clears it.
func set_highlight(kind: String, cell: int) -> void:
	if _material == null:
		return
	var level := current_level()
	if level == null or cell < 0:
		_material.set_shader_parameter(kind + "_cell", Vector3(0, 0, -1))
		return
	var c := level.cell_center(cell)
	_material.set_shader_parameter(kind + "_cell", Vector3(c.x, c.y, level.hex_size))
	_material.set_shader_parameter(kind + "_y", level.top_y(cell))


func set_grid_visible(on: bool) -> void:
	if _material != null:
		_material.set_shader_parameter("show_grid", on)


## Ray-marches the active level's stepped surface. Returns a cell index or -1.
func pick(origin: Vector3, dir: Vector3) -> int:
	var level := current_level()
	if level == null or dir.y > -1e-4:
		return -1
	var top := level.max_top_y()
	var t := maxf(0.0, (origin.y - top) / -dir.y)
	var t_end := (origin.y - level.base_y()) / -dir.y
	var step := level.hex_size * 0.2
	var iterations := 0
	while t <= t_end and iterations < 6000:
		var p := origin + dir * t
		var ci := level.cell_at(Vector2(p.x, p.z))
		if ci >= 0 and p.y <= level.top_y(ci):
			return ci
		t += step
		iterations += 1
	return -1


## Height of the surface under a world point on the active level (for the camera pivot).
func surface_height(p: Vector2) -> float:
	var level := current_level()
	if level == null:
		return 0.0
	var ci := level.nearest_cell(p)
	return level.top_y(ci) if ci >= 0 else 0.0
