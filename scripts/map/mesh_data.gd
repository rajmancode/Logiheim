class_name MeshData
extends RefCounted
## Small triangle-soup builder used for river ribbons and grass clumps.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var colors := PackedColorArray()


## Adds a triangle, ordering it so it faces along n (Godot front faces are clockwise).
func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n: Vector3, uv2: Vector2, color := Color.WHITE) -> void:
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
		colors.append(color)


func to_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
