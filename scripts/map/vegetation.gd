class_name Vegetation
extends RefCounted
## Scatters trees, bushes and rocks (Blender models in assets/models/vegetation) over a level.
##
## Forest hexes get dense conifer/broadleaf woods (more conifers higher up), grassland gets
## the odd tree and bushes, rocky hexes and steep slopes get boulders. Placement follows the
## terrain surface and keeps out of rivers and the sea. Each model is drawn with MultiMeshes,
## split into chunks so off-screen parts are culled.

const MODEL_DIR := "res://assets/models/vegetation"
const CONIFERS := ["conifer_a", "conifer_b", "conifer_c"]
const BROADLEAF := ["broadleaf_a", "broadleaf_b"]
const BUSHES := ["bush_a", "bush_b"]
const ROCKS := ["rock_a", "rock_b", "rock_c", "rock_d", "rock_e"]
const CHUNK_METRES := 256.0
const T := HexMapGenerator.Terrain

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


## Mesh for a model, with the game's shaders on its Bark / Leaves / Rock surfaces.
static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var result: ArrayMesh = null
	var path := "%s/%s.glb" % [MODEL_DIR, model]
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var inst := scene.instantiate()
			var found := _find_mesh(inst)
			if found != null:
				result = found.duplicate() as ArrayMesh
			inst.free()
	if result == null:
		push_warning("Vegetation: missing model %s" % path)
		_meshes[model] = null
		return null
	for s in result.get_surface_count():
		var m := result.surface_get_material(s)
		result.surface_set_material(s, _material(m.resource_name if m != null else "Leaves"))
	_meshes[model] = result
	return result


static func build(level: HexLevel, surface: TerrainSurface, settings: HexMapSettings, parent: Node3D) -> void:
	var s := level.hex_size
	var area := 2.598 * s * s
	var size_mult := 1.0 + 0.3 * level.level_index
	var per_forest := clampi(roundi(area / (settings.tree_spacing * settings.tree_spacing)), 1, settings.max_trees_per_hex)
	var land_top := maxf(level.max_top_y() - surface.sea_y, 1.0)
	var rng := RandomNumberGenerator.new()
	## model -> {chunk Vector2i -> [transforms, customs]}
	var items: Dictionary = {}

	for i in level.cell_count():
		var t := level.terrain[i]
		if HexMapGenerator.is_water(t):
			continue
		rng.seed = hash(Vector3i(level.coords[i].x, level.coords[i].y, 7919 + level.level_index))
		var c := level.cell_center(i)
		var rel_h := clampf((level.top_y(i) - surface.sea_y) / land_top, 0.0, 1.0)
		match t:
			T.FOREST:
				if settings.trees_enabled:
					var conifer_share := clampf(0.3 + rel_h * 0.9, 0.2, 0.95)
					for k in per_forest:
						var model: String = CONIFERS[rng.randi() % CONIFERS.size()] if rng.randf() < conifer_share else BROADLEAF[rng.randi() % BROADLEAF.size()]
						_place_tree(items, model, surface, settings, c, s, rng, size_mult)
					for k in maxi(1, per_forest / 6):
						_place_bush(items, surface, c, s, rng, size_mult)
			T.GRASS, T.DIRT:
				if settings.trees_enabled:
					if rng.randf() < 0.35 * area / 1000.0 or rng.randf() < 0.25:
						_place_tree(items, BROADLEAF[rng.randi() % BROADLEAF.size()], surface, settings, c, s, rng, size_mult)
					for k in rng.randi_range(1, 3):
						_place_bush(items, surface, c, s, rng, size_mult)
			T.ROCK, T.SNOW:
				if settings.rocks_enabled:
					for k in rng.randi_range(2, 5) if t == T.ROCK else rng.randi_range(0, 2):
						_place_rock(items, surface, c, s, rng, size_mult * rng.randf_range(1.5, 5.0))
			T.SAND:
				if settings.rocks_enabled and rng.randf() < 0.15:
					_place_rock(items, surface, c, s, rng, size_mult * rng.randf_range(0.8, 2.0))
		# Boulders on steep ground anywhere.
		if settings.rocks_enabled and t != T.ROCK and surface.weight_at(c, T.ROCK) > 0.4 and rng.randf() < 0.6:
			_place_rock(items, surface, c, s, rng, size_mult * rng.randf_range(1.5, 4.0))

	for model: String in items:
		var m := mesh(model)
		if m == null:
			continue
		var chunks: Dictionary = items[model]
		for key: Vector2i in chunks:
			var data: Array = chunks[key]
			var xforms: Array = data[0]
			var customs: Array = data[1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = m
			mm.instance_count = xforms.size()
			for j in xforms.size():
				mm.set_instance_transform(j, xforms[j])
				mm.set_instance_custom_data(j, customs[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [model, key.x, key.y]
			mmi.multimesh = mm
			parent.add_child(mmi)


static func _random_point(c: Vector2, s: float, rng: RandomNumberGenerator) -> Vector2:
	for attempt in 8:
		var p := Vector2(rng.randf_range(-s, s), rng.randf_range(-s, s))
		if HexCoords.contains(p, s * 0.92):
			return c + p
	return c


static func _ok_ground(surface: TerrainSurface, p: Vector2) -> bool:
	return not surface.keep_clear(p) and surface.sample(p) > surface.sea_y + 0.6 and surface.volcanic_at(p) < 0.5


static func _place_tree(items: Dictionary, model: String, surface: TerrainSurface, settings: HexMapSettings, c: Vector2, s: float, rng: RandomNumberGenerator, mult: float) -> void:
	var p := _random_point(c, s, rng)
	if not _ok_ground(surface, p) or surface.weight_at(p, T.ROCK) > 0.55:
		return
	var h := rng.randf_range(settings.tree_height.x, settings.tree_height.y) * mult
	if model.begins_with("broadleaf"):
		h *= 0.75
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * rng.randf_range(0.85, 1.15), h, h * rng.randf_range(0.85, 1.15)))
	var y := surface.sample(p) - 0.3
	var tint := Color.from_hsv(rng.randf_range(0.2, 0.3), rng.randf_range(0.0, 0.25), rng.randf_range(0.8, 1.15))
	if model.begins_with("conifer"):
		tint = Color(0.62, 0.78, 0.68) * rng.randf_range(0.8, 1.1)
	else:
		tint = Color(0.92, 1.0, 0.72) * tint
	_add(items, model, Transform3D(basis, Vector3(p.x, y, p.y)), tint)


static func _place_bush(items: Dictionary, surface: TerrainSurface, c: Vector2, s: float, rng: RandomNumberGenerator, mult: float) -> void:
	var p := _random_point(c, s, rng)
	if not _ok_ground(surface, p) or surface.weight_at(p, T.ROCK) > 0.5:
		return
	var size := rng.randf_range(1.2, 2.4) * mult
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.7, 1.1), size))
	var tint := Color(0.85, 0.95, 0.65) * rng.randf_range(0.8, 1.1)
	_add(items, BUSHES[rng.randi() % BUSHES.size()], Transform3D(basis, Vector3(p.x, surface.sample(p) - 0.15, p.y)), tint)


static func _place_rock(items: Dictionary, surface: TerrainSurface, c: Vector2, s: float, rng: RandomNumberGenerator, size: float) -> void:
	var p := _random_point(c, s, rng)
	if surface.river_at(p) > 0.3 or surface.sample(p) < surface.sea_y - 0.5:
		return
	var up := surface.normal_at(p).lerp(Vector3.UP, 0.4).normalized()
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var tilt := Quaternion(Vector3.UP, up)
	basis = Basis(tilt) * basis
	basis = basis.scaled(Vector3(size * rng.randf_range(0.8, 1.3), size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.8, 1.3)))
	var y := surface.sample(p) - size * 0.12
	# Alpha = basalt: boulders on and around the volcano are dark basalt.
	_add(items, ROCKS[rng.randi() % ROCKS.size()], Transform3D(basis, Vector3(p.x, y, p.y)), Color(1, 1, 1, surface.volcanic_at(p)))


static func _add(items: Dictionary, model: String, xform: Transform3D, custom: Color) -> void:
	var key := Vector2i(floori(xform.origin.x / CHUNK_METRES), floori(xform.origin.z / CHUNK_METRES))
	if not items.has(model):
		items[model] = {}
	var chunks: Dictionary = items[model]
	if not chunks.has(key):
		chunks[key] = [[], []]
	chunks[key][0].append(xform)
	chunks[key][1].append(custom)


static func _find_mesh(node: Node) -> ArrayMesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _find_mesh(child)
		if m != null:
			return m
	return null


static func _material(kind: String) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	var mat := ShaderMaterial.new()
	match kind:
		"Rock":
			mat.shader = load("res://shaders/rock.gdshader")
			mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
			mat.set_shader_parameter("normal_array", TerrainMaterial.normal_array())
		"Bark":
			mat.shader = load("res://shaders/tree_wind.gdshader")
			mat.set_shader_parameter("albedo", Color(0.3, 0.22, 0.16))
			mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
			mat.set_shader_parameter("is_leaves", false)
			mat.set_shader_parameter("roughness", 0.95)
		_:
			mat.shader = load("res://shaders/tree_wind.gdshader")
			mat.set_shader_parameter("albedo", Color(0.27, 0.4, 0.15))
			mat.set_shader_parameter("is_leaves", true)
			mat.set_shader_parameter("roughness", 0.8)
	_materials[kind] = mat
	return mat
