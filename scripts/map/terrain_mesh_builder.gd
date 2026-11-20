class_name TerrainMeshBuilder
extends RefCounted
## Turns a TerrainSurface into chunked, indexed meshes for frustum culling.
##
## Vertex data used by shaders/hex_terrain.gdshader: the 8 terrain blend weights are packed
## into COLOR (layers 0-3), UV (4-5) and UV2 (6-7); CUSTOM0 = (floodplain strength, river
## level the floodplain floods from, 0, 0).

## Quads per chunk edge.
const CHUNK := 64


static func build(surface: TerrainSurface, material: Material, parent: Node3D) -> void:
	var cx := ceili(float(surface.nx - 1) / CHUNK)
	var cz := ceili(float(surface.nz - 1) / CHUNK)
	for bz in cz:
		for bx in cx:
			var mesh := _chunk(surface, bx * CHUNK, bz * CHUNK,
				mini(bx * CHUNK + CHUNK, surface.nx - 1), mini(bz * CHUNK + CHUNK, surface.nz - 1))
			var mi := MeshInstance3D.new()
			mi.name = "Terrain_%d_%d" % [bx, bz]
			mi.mesh = mesh
			mi.material_override = material
			parent.add_child(mi)


static func _chunk(s: TerrainSurface, x0: int, z0: int, x1: int, z1: int) -> ArrayMesh:
	var w := x1 - x0 + 1
	var d := z1 - z0 + 1
	var n := w * d
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var custom := PackedFloat32Array()
	custom.resize(n * 4)
	verts.resize(n)
	normals.resize(n)
	colors.resize(n)
	uv.resize(n)
	uv2.resize(n)
	var sp := s.spacing
	var k := 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * s.nx + x
			verts[k] = Vector3(x * sp, s.heights[i], z * sp)
			var xa := maxi(x - 1, 0)
			var xb := mini(x + 1, s.nx - 1)
			var za := maxi(z - 1, 0)
			var zb := mini(z + 1, s.nz - 1)
			var hx := (s.heights[z * s.nx + xb] - s.heights[z * s.nx + xa]) / float(xb - xa)
			var hz := (s.heights[zb * s.nx + x] - s.heights[za * s.nx + x]) / float(zb - za)
			normals[k] = Vector3(-hx, sp, -hz).normalized()
			var b := i * TerrainSurface.LAYERS
			colors[k] = Color(s.weights[b], s.weights[b + 1], s.weights[b + 2], s.weights[b + 3])
			uv[k] = Vector2(s.weights[b + 4], s.weights[b + 5])
			uv2[k] = Vector2(s.weights[b + 6], s.weights[b + 7])
			custom[k * 4] = s.flood_mask[i]
			custom[k * 4 + 1] = s.flood_y[i]
			k += 1

	var indices := PackedInt32Array()
	indices.resize((w - 1) * (d - 1) * 6)
	var t := 0
	for z in d - 1:
		for x in w - 1:
			var a := z * w + x
			var b := a + 1
			var c := a + w
			var e := c + 1
			# Clockwise when seen from above (Godot's front face).
			indices[t] = a
			indices[t + 1] = b
			indices[t + 2] = c
			indices[t + 3] = b
			indices[t + 4] = e
			indices[t + 5] = c
			t += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh := ArrayMesh.new()
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh
