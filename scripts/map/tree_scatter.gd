class_name TreeScatter
extends RefCounted
## Scatters simple low-poly conifers on forest hexes using one MultiMesh per level.

static var _tree_mesh: ArrayMesh


static func build(level: HexLevel, settings: HexMapSettings, parent: Node3D) -> void:
	var s := level.hex_size
	var area := 2.598 * s * s
	var per_hex := clampi(roundi(area / (settings.tree_spacing * settings.tree_spacing)), 1, settings.max_trees_per_hex)
	var tree_h := clampf(s * 0.45, 5.0, 45.0)
	var rng := RandomNumberGenerator.new()

	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in level.cell_count():
		if level.terrain[i] != HexMapGenerator.Terrain.FOREST:
			continue
		rng.seed = hash(Vector3i(level.coords[i].x, level.coords[i].y, level.level_index))
		var c := level.cell_center(i)
		var y := level.top_y(i)
		var placed := 0
		var attempts := 0
		while placed < per_hex and attempts < per_hex * 4:
			attempts += 1
			var p := Vector2(rng.randf_range(-s, s), rng.randf_range(-s, s))
			if not HexCoords.contains(p, s * 0.82):
				continue
			var scale := tree_h * rng.randf_range(0.7, 1.3)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.85, 1.2), scale))
			xforms.append(Transform3D(basis, Vector3(c.x + p.x, y, c.y + p.y)))
			colors.append(Color.from_hsv(rng.randf_range(0.26, 0.36), rng.randf_range(0.45, 0.7), rng.randf_range(0.75, 1.0)))
			placed += 1

	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _get_mesh()
	mm.instance_count = xforms.size()
	for j in xforms.size():
		mm.set_instance_transform(j, xforms[j])
		mm.set_instance_color(j, colors[j])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	parent.add_child(mmi)


static func _get_mesh() -> ArrayMesh:
	if _tree_mesh != null:
		return _tree_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.14)
	trunk_mat.roughness = 0.95
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.16, 0.32, 0.15)
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 0.9

	_tree_mesh = ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.05
	trunk.bottom_radius = 0.08
	trunk.height = 0.4
	trunk.radial_segments = 6
	trunk.rings = 1
	_append(trunk, Vector3(0, 0.2, 0), trunk_mat)
	var lower := CylinderMesh.new()
	lower.top_radius = 0.0
	lower.bottom_radius = 0.42
	lower.height = 0.75
	lower.radial_segments = 8
	lower.rings = 1
	_append(lower, Vector3(0, 0.62, 0), leaf_mat)
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.3
	upper.height = 0.6
	upper.radial_segments = 8
	upper.rings = 1
	_append(upper, Vector3(0, 0.98, 0), leaf_mat)
	return _tree_mesh


static func _append(prim: PrimitiveMesh, offset: Vector3, mat: Material) -> void:
	var arrays := prim.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for j in v.size():
		v[j] += offset
	arrays[Mesh.ARRAY_VERTEX] = v
	_tree_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_tree_mesh.surface_set_material(_tree_mesh.get_surface_count() - 1, mat)
