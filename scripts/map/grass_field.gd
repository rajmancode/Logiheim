class_name GrassField
extends RefCounted
## Dense grass on the finest level: clumps of curved blades on grassy ground (and thinner under
## forest), placed on the terrain surface, in chunks that only draw near the camera.

const CHUNK_METRES := 48.0
const T := HexMapGenerator.Terrain

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


static func build(surface: TerrainSurface, settings: HexMapSettings, parent: Node3D) -> void:
	if settings.grass_density <= 0.0:
		return
	var size := Vector2((surface.nx - 1) * surface.spacing, (surface.nz - 1) * surface.spacing)
	var cx := ceili(size.x / CHUNK_METRES)
	var cz := ceili(size.y / CHUNK_METRES)
	var per_chunk := roundi(CHUNK_METRES * CHUNK_METRES * settings.grass_density)
	var rng := RandomNumberGenerator.new()
	var total := 0
	for bz in cz:
		for bx in cx:
			var o := Vector2(bx, bz) * CHUNK_METRES
			if not _has_grass(surface, o):
				continue
			rng.seed = hash(Vector2i(bx, bz))
			var xforms: Array[Transform3D] = []
			for k in per_chunk:
				var p := o + Vector2(rng.randf(), rng.randf()) * CHUNK_METRES
				var g := surface.weight_at(p, T.GRASS) + 0.45 * surface.weight_at(p, T.FOREST) + 0.3 * surface.weight_at(p, T.DIRT)
				if rng.randf() > g * 1.3:
					continue
				if surface.river_at(p) > 0.25 or surface.path_at(p) > 0.4:
					continue
				var y := surface.sample(p)
				if y < surface.sea_y + 0.8:
					continue
				var up := surface.normal_at(p)
				if up.y < 0.8:
					continue
				var basis := Basis(Quaternion(Vector3.UP, up.lerp(Vector3.UP, 0.5).normalized())) * Basis(Vector3.UP, rng.randf() * TAU)
				var sc := rng.randf_range(0.7, 1.35)
				basis = basis.scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.25), sc))
				xforms.append(Transform3D(basis, Vector3(p.x, y - 0.05, p.y)))
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _clump_mesh()
			mm.instance_count = xforms.size()
			for j in xforms.size():
				mm.set_instance_transform(j, xforms[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Grass_%d_%d" % [bx, bz]
			mmi.multimesh = mm
			mmi.material_override = _get_material()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = settings.grass_view_distance
			mmi.visibility_range_end_margin = settings.grass_view_distance * 0.2
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mmi)
			total += xforms.size()
	print("GrassField: %d clumps" % total)


static func _has_grass(surface: TerrainSurface, o: Vector2) -> bool:
	for k in 9:
		var p := o + Vector2(k % 3, k / 3) * (CHUNK_METRES * 0.5)
		if surface.sample(p) > surface.sea_y + 0.8 and surface.weight_at(p, T.GRASS) + surface.weight_at(p, T.FOREST) > 0.05:
			return true
	return false


## A clump of 9 curved, tapering blades. UV.y runs 0 (root) to 1 (tip).
static func _clump_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 3
	for b in 9:
		var root := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
		var yaw := rng.randf() * TAU
		var across := Vector3(cos(yaw), 0.0, sin(yaw))
		var lean := Vector3(-across.z, 0.0, across.x) * rng.randf_range(0.1, 0.35)
		var height := rng.randf_range(0.35, 0.75)
		var width := rng.randf_range(0.035, 0.06)
		var start := verts.size()
		for sgm in SEGMENTS + 1:
			var t := float(sgm) / SEGMENTS
			var c := root + Vector3(0.0, height * t, 0.0) + lean * height * t * t
			var hw := width * (1.0 - t * 0.85) * 0.5
			var n := lean.normalized().cross(across) if lean.length() > 0.0 else Vector3.BACK
			verts.append(c - across * hw)
			verts.append(c + across * hw)
			normals.append(n)
			normals.append(n)
			uvs.append(Vector2(0.0, t))
			uvs.append(Vector2(1.0, t))
		for sgm in SEGMENTS:
			var a := start + sgm * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/grass.gdshader")
	return _material
