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

const HIGHLIGHT_COLORS := {"hover": Color(1.0, 0.85, 0.35), "select": Color(0.35, 0.8, 1.0)}

var _level_roots: Array[Node3D] = []
## Outline noise for each level, shared by meshes, rivers, highlights and picking.
var _noises: Array[BorderNoise] = []
var _material: ShaderMaterial
var _highlights: Dictionary = {}


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
		var noise := BorderNoise.new(level.hex_size, settings.border_noise, settings.border_segments)
		_noises.append(noise)
		HexMeshBuilder.build(level, settings, noise, _material, root)
		if settings.rivers_enabled:
			RiverMeshBuilder.build(level, noise, root)
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
	_noises.clear()
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


## kind is "hover" or "select"; cell -1 clears it. Draws an overlay that follows the hex's
## noisy outline.
func set_highlight(kind: String, cell: int) -> void:
	var mi: MeshInstance3D = _highlights.get(kind)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Highlight_" + kind
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/highlight.gdshader")
		mat.set_shader_parameter("color", HIGHLIGHT_COLORS.get(kind, Color.WHITE))
		mat.render_priority = 1 if kind == "select" else 2
		mi.material_override = mat
		add_child(mi)
		_highlights[kind] = mi
	var level := current_level()
	if level == null or cell < 0 or active_level >= _noises.size():
		mi.visible = false
		return
	var c := level.cell_center(cell)
	var y := level.top_y(cell) + 0.15
	var center := Vector3(c.x, y, c.y)
	var rim := Vector2(1.0, 0.0)
	var data := HexMeshBuilder.MeshData.new()
	var outline := _outline(level, cell)
	for k in outline.size():
		var a := outline[k]
		var b := outline[(k + 1) % outline.size()]
		data.tri(center, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector2.ZERO, rim, rim, Vector3.UP, Vector2.ZERO)
	mi.mesh = data.to_mesh()
	mi.visible = true


## The hex's noisy outline as a closed polygon (world x, z).
func _outline(level: HexLevel, cell: int) -> PackedVector2Array:
	var noise: BorderNoise = _noises[level.level_index]
	var c := level.cell_center(cell)
	var poly := PackedVector2Array()
	for k in 6:
		var pts := noise.hex_edge(c, level.hex_size, k)
		for s in pts.size() - 1:
			poly.append(pts[s])
	return poly


## Exact cell under p using the noisy outlines: the plain hex or one of its neighbours.
func _cell_at_noisy(level: HexLevel, p: Vector2) -> int:
	var ci := level.cell_at(p)
	if ci < 0 or level.level_index >= _noises.size() or _noises[level.level_index].amplitude <= 0.0:
		return ci
	if Geometry2D.is_point_in_polygon(p, _outline(level, ci)):
		return ci
	for k in 6:
		var j := level.index_of(HexCoords.neighbor(level.coords[ci], k))
		if j >= 0 and Geometry2D.is_point_in_polygon(p, _outline(level, j)):
			return j
	return ci


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
			ci = _cell_at_noisy(level, Vector2(p.x, p.z))
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
