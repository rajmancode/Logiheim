class_name HexMap
extends Node3D
## Loads a Gaea export, builds every hex level (LOD) and shows one at a time.
##
## Per level: a soft-stepped TerrainSurface, carved river channels and river water, trees,
## bushes and rocks, and (finest level only) grass. One sea surface is shared by all levels.
## Grid lines and highlights are drawn by the terrain and water shaders.

signal generated
signal level_changed(level_index: int)

@export var settings: HexMapSettings

var source: TerrainSource
var levels: Array[HexLevel] = []
var surfaces: Array[TerrainSurface] = []
var active_level := -1
var auto_lod := true
## World y of the sea surface.
var sea_y := 0.0

var _level_roots: Array[Node3D] = []
## Border noise per level, shared by shaders (grid) and picking.
var _noises: Array[BorderNoise] = []
var _materials: Array[ShaderMaterial] = []
var _base_material: ShaderMaterial
var _water: MeshInstance3D
var _water_material: ShaderMaterial
var _show_grid := true


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
	if _base_material == null:
		_base_material = TerrainMaterial.create()
	_clear()

	var t0 := Time.get_ticks_msec()
	var gen := HexMapGenerator.new(source, settings)
	levels = gen.build_levels()
	sea_y = gen.sea_y()
	for level in levels:
		var t1 := Time.get_ticks_msec()
		var root := Node3D.new()
		root.name = "Level%d" % level.level_index
		root.visible = false
		add_child(root)
		var noise := BorderNoise.new(level.hex_size, settings.border_noise)
		var surface := TerrainSurface.new(level, source, settings, gen)
		var paths: Array[RiverPath] = []
		if settings.rivers_enabled:
			paths = RiverMeshBuilder.compute_paths(level, surface)
			surface.carve(paths)
		surface.finish_weights()
		var mat := TerrainMaterial.for_level(_base_material, level, noise, sea_y)
		mat.set_shader_parameter("show_grid", _show_grid)
		TerrainMeshBuilder.build(surface, mat, root)
		RiverMeshBuilder.build(paths, root)
		Vegetation.build(level, surface, settings, root)
		if level.level_index == 0 and settings.grass_enabled:
			GrassField.build(surface, settings, root)
		_level_roots.append(root)
		_noises.append(noise)
		_materials.append(mat)
		surfaces.append(surface)
		print("HexMap: level %d (%.0f m hexes, %d x %d terrain) in %d ms" % [
			level.level_index, level.hex_size, surface.nx, surface.nz, Time.get_ticks_msec() - t1])
	_build_water()
	print("HexMap: built %d levels for '%s' in %d ms" % [levels.size(), source.name, Time.get_ticks_msec() - t0])

	active_level = -1
	set_level(0)
	generated.emit()


func _clear() -> void:
	for root in _level_roots:
		root.queue_free()
	_level_roots.clear()
	_noises.clear()
	_materials.clear()
	surfaces.clear()
	levels.clear()


func _build_water() -> void:
	if _water == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = load("res://shaders/water.gdshader")
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 512
		tex.height = 512
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 6.0
		tex.generate_mipmaps = true
		tex.noise = noise
		_water_material.set_shader_parameter("wave_normal", tex)
		_water = MeshInstance3D.new()
		_water.name = "Sea"
		_water.material_override = _water_material
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)
	var size := source.world_size
	var plane := PlaneMesh.new()
	plane.size = size * 3.0
	plane.subdivide_width = 300
	plane.subdivide_depth = 300
	_water.mesh = plane
	_water.position = Vector3(size.x * 0.5, sea_y, size.y * 0.5)
	_water_material.set_shader_parameter("show_grid", _show_grid)


func current_level() -> HexLevel:
	return levels[active_level] if active_level >= 0 and active_level < levels.size() else null


func current_surface() -> TerrainSurface:
	return surfaces[active_level] if active_level >= 0 and active_level < surfaces.size() else null


func set_level(i: int) -> void:
	i = clampi(i, 0, levels.size() - 1)
	if i == active_level:
		return
	active_level = i
	for k in _level_roots.size():
		_level_roots[k].visible = k == i
	if _water_material != null:
		TerrainMaterial.set_grid(_water_material, levels[i], _noises[i])
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


## kind is "hover" or "select"; cell -1 clears it. The shaders draw it.
func set_highlight(kind: String, cell: int) -> void:
	var level := current_level()
	var value := Vector3.ZERO
	if level != null and cell >= 0:
		var a := level.coords[cell]
		value = Vector3(a.x, a.y, 1.0)
	var param := kind + "_cell"
	if active_level >= 0 and active_level < _materials.size():
		_materials[active_level].set_shader_parameter(param, value)
	if _water_material != null:
		_water_material.set_shader_parameter(param, value)


func set_grid_visible(on: bool) -> void:
	_show_grid = on
	for m in _materials:
		m.set_shader_parameter("show_grid", on)
	if _water_material != null:
		_water_material.set_shader_parameter("show_grid", on)


## Ground (or sea surface) height at a world point on the active level.
func ground_height(p: Vector2) -> float:
	var s := current_surface()
	return maxf(s.sample(p), sea_y) if s != null else 0.0


## Finds where a ray hits the active level's terrain or sea. Returns a cell index or -1.
func pick(origin: Vector3, dir: Vector3) -> int:
	var level := current_level()
	var s := current_surface()
	if level == null or s == null or dir.y > -1e-4:
		return -1
	var top := level.max_top_y() + settings.terrain_detail * source.height_range * settings.height_scale + 20.0
	var t := maxf(0.0, (origin.y - top) / -dir.y)
	var t_end := (origin.y - (sea_y - 1.0)) / -dir.y
	var step := s.spacing * 1.5
	var prev := t
	var hit := -1.0
	while t <= t_end:
		var p := origin + dir * t
		if p.y <= ground_height(Vector2(p.x, p.z)):
			hit = t
			break
		prev = t
		t += step
	if hit < 0.0:
		return -1
	# Refine between the last miss and the hit.
	var lo := prev
	var hi := hit
	for k in 8:
		var mid := (lo + hi) * 0.5
		var p := origin + dir * mid
		if p.y <= ground_height(Vector2(p.x, p.z)):
			hi = mid
		else:
			lo = mid
	var q := origin + dir * hi
	return _noises[active_level].cell_at(level, Vector2(q.x, q.z))


## Height of the surface under a world point on the active level (for the camera pivot).
func surface_height(p: Vector2) -> float:
	return ground_height(p)
