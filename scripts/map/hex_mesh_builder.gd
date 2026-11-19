class_name HexMeshBuilder
extends RefCounted
## Builds stepped hex-prism meshes for a HexLevel, split into chunks.
##
## Vertex data used by shaders/hex_terrain.gdshader:
##   UV.x  top faces: 0 at the hex centre, 1 on the rim (grid lines)
##   UV.y  walls: depth below the top edge, in metres
##   UV2.x terrain id, UV2.y 0 = top face, 1 = wall


class MeshData:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()

	## Adds a triangle, ordering it so it faces along n (Godot front faces are clockwise).
	func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n: Vector3, uv2: Vector2) -> void:
		verts.append(a)
		uvs.append(ua)
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts.append(c)
			uvs.append(uc)
			verts.append(b)
			uvs.append(ub)
		else:
			verts.append(b)
			uvs.append(ub)
			verts.append(c)
			uvs.append(uc)
		for k in 3:
			normals.append(n)
			uv2s.append(uv2)

	func to_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		var mesh := ArrayMesh.new()
		if not verts.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func build(level: HexLevel, settings: HexMapSettings, noise: BorderNoise, material: Material, parent: Node3D) -> void:
	var cs := maxi(4, settings.chunk_size)
	var chunks: Dictionary = {}
	for i in level.cell_count():
		var off := HexCoords.axial_to_offset(level.coords[i])
		var key := Vector2i(off.x / cs, off.y / cs)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(i)

	var base_y := level.base_y()
	for key: Vector2i in chunks:
		var data := MeshData.new()
		for i: int in chunks[key]:
			_add_cell(data, level, i, noise, base_y)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [key.x, key.y]
		mi.mesh = data.to_mesh()
		mi.material_override = material
		parent.add_child(mi)


## One hex: a fan over its (noisy) outline, plus cliff walls along edges whose neighbour is lower.
static func _add_cell(data: MeshData, level: HexLevel, i: int, noise: BorderNoise, base_y: float) -> void:
	var c := level.cell_center(i)
	var y := level.top_y(i)
	var t := level.terrain[i]
	var top_id := Vector2(t, 0.0)
	var wall_id := Vector2(HexMapGenerator.wall_terrain(t), 1.0)
	var center := Vector3(c.x, y, c.y)
	var rim := Vector2(1.0, 0.0)

	for k in 6:
		var pts := noise.hex_edge(c, level.hex_size, k)
		for s in pts.size() - 1:
			var a := Vector3(pts[s].x, y, pts[s].y)
			var b := Vector3(pts[s + 1].x, y, pts[s + 1].y)
			data.tri(center, a, b, Vector2.ZERO, rim, rim, Vector3.UP, top_id)

		var ni := level.index_of(HexCoords.neighbor(level.coords[i], k))
		var ny := base_y if ni < 0 else level.top_y(ni)
		if ny >= y - 0.001:
			continue
		var depth := y - ny
		var u_top := Vector2(0.0, 0.0)
		var u_bot := Vector2(0.0, depth)
		for s in pts.size() - 1:
			var pa := pts[s]
			var pb := pts[s + 1]
			var d := pb - pa
			var n := Vector3(d.y, 0.0, -d.x).normalized()
			var out := (pa + pb) * 0.5 - c
			if n.x * out.x + n.z * out.y < 0.0:
				n = -n
			var a_top := Vector3(pa.x, y, pa.y)
			var b_top := Vector3(pb.x, y, pb.y)
			var a_bot := Vector3(pa.x, ny, pa.y)
			var b_bot := Vector3(pb.x, ny, pb.y)
			data.tri(a_top, b_top, b_bot, u_top, u_top, u_bot, n, wall_id)
			data.tri(a_top, b_bot, a_bot, u_top, u_bot, u_bot, n, wall_id)
