class_name Infrastructure
extends Node3D
## The roads a clan lays (GameWorld, the Road tool), drawn over the land:
##   - a road: a made track from the hex's middle to each neighbouring road and to the door of
##     each of the clan's buildings beside it, its surface suiting the ground (shaders/trail);
##   - a hill road, on a hex too steep to walk: the track climbs in switchbacks, held up on the
##     downhill side by dry-stone walls;
##   - a bridge, on a river hex: a deck of planks on piers (a stone arch where the banks are rock,
##     a braced trestle over a wide river) from bank to bank, high enough above the water.
## Roads are what let a clan reach land across a river or up a hill (GameWorld reachability).

const WIDTH := 3.2

var world: GameWorld
var _road_mat: ShaderMaterial
var _roads: MeshInstance3D
var _bridges: MeshInstance3D
var _walls: MeshInstance3D


func setup(p_world: GameWorld) -> void:
	world = p_world
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://shaders/trail.gdshader")
	_road_mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
	_road_mat.set_shader_parameter("normal_array", TerrainMaterial.normal_array())
	_road_mat.set_shader_parameter("trail_width", WIDTH)
	_roads = MeshInstance3D.new()
	_roads.name = "Roads"
	_roads.material_override = _road_mat
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roads)
	_bridges = MeshInstance3D.new()
	_bridges.name = "Bridges"
	add_child(_bridges)
	_walls = MeshInstance3D.new()
	_walls.name = "Walls"
	add_child(_walls)


func clear() -> void:
	if _roads != null:
		_roads.mesh = null
		_bridges.mesh = null
		_walls.mesh = null


## What kind of road a hex needs: "bridge" over a river, "hill" up a steep slope, else "road".
static func kind_for(l: HexLevel, cell: int) -> String:
	if l.river[cell] == 1:
		return "bridge"
	if l.slope[cell] > GameWorld.WALK_SLOPE:
		return "hill"
	return "road"


## What laying it costs.
static func cost_for(kind: String) -> Dictionary:
	match kind:
		"bridge":
			return {"wood": 12, "stone": 6}
		"hill":
			return {"stone": 4, "wood": 2}
	return {"wood": 1, "stone": 1}


func rebuild() -> void:
	var surface := world.hex_map.current_surface()
	if surface == null:
		return
	var l := world.lv()
	var sea := world.hex_map.sea_y
	var rivers: Array = world.hex_map.river_paths[0] if not world.hex_map.river_paths.is_empty() else []
	var road := _Strip.new()
	var bridges := MeshData.new()
	var walls := BuildingModels.Kit.new()
	var any_wall := false
	for s in world.settlements:
		for cell: int in s.roads:
			var kind := String(s.roads[cell])
			var c := l.cell_center(cell)
			# Where this hex's road goes: to neighbouring roads (to the shared edge) and to the
			# doors of the clan's buildings beside it.
			var ends: Array = []
			for k in 6:
				var j := l.index_of(HexCoords.neighbor(l.coords[cell], k))
				if j < 0:
					continue
				var edge := (c + l.cell_center(j)) * 0.5
				if s.roads.has(j):
					ends.append(edge)
				elif world.get("_occupied").has(j) and s.buildings.has(world.get("_occupied")[j]):
					var rec: Dictionary = world.get("_occupied")[j]
					var v: BuildingView = world.get("_views").get(rec.uid)
					if v != null:
						var door := v.to_global((v.info.door as Vector3) + Vector3(0, 0, -2.5))
						ends.append(Vector2(door.x, door.z))
			if kind == "bridge":
				_add_bridge(bridges, road, c, ends, l, surface, rivers, sea)
				continue
			if ends.is_empty():
				# A little paved standing by itself.
				road.add(PackedVector2Array([c - Vector2(2.5, 0), c + Vector2(2.5, 0)]), surface, sea)
				continue
			for e: Vector2 in ends:
				if kind == "hill":
					var pts := _switchbacks(c, e, l.hex_size)
					road.add(pts, surface, sea)
					any_wall = _add_walls(walls, pts, surface) or any_wall
				else:
					road.add(PackedVector2Array([c, c.lerp(e, 0.5), e]), surface, sea)
	_roads.mesh = road.commit()
	_bridges.mesh = bridges.to_mesh() if not bridges.verts.is_empty() else null
	_bridges.material_override = ResourceProps._material("body")
	_walls.mesh = walls.commit() if any_wall else null
	_walls.material_override = BuildingView.building_material(Color.WHITE)


## A climbing track from c to e that zig-zags across the slope.
static func _switchbacks(c: Vector2, e: Vector2, hs: float) -> PackedVector2Array:
	var d := e - c
	var side := Vector2(-d.y, d.x).normalized() * hs * 0.3
	var raw := [c, c + d * 0.25 + side, c + d * 0.5 - side, c + d * 0.75 + side, e]
	var out := PackedVector2Array()
	for i in raw.size() - 1:
		var a: Vector2 = raw[i]
		var b: Vector2 = raw[i + 1]
		var n := maxi(2, int(a.distance_to(b) / 2.0))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(e)
	return out


## Dry-stone retaining walls along the downhill edge of each leg of a hill road.
static func _add_walls(k: BuildingModels.Kit, pts: PackedVector2Array, surface: TerrainSurface) -> bool:
	var added := false
	var i := 0
	while i + 3 < pts.size():
		var a := pts[i]
		var b := pts[i + 3]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		# The downhill side.
		var mid := (a + b) * 0.5
		if surface.sample(mid + n * 3.0) > surface.sample(mid - n * 3.0):
			n = -n
		var off := n * (WIDTH * 0.5 + 0.35)
		var pa := a + off
		var pb := b + off
		var ya := surface.sample_mesh(pa) - 0.35
		k.stones(Vector3(pa.x, ya, pa.y), Vector3(pb.x, surface.sample_mesh(pb) - 0.35, pb.y), 0.9, 0.5, 2, BuildingModels.STONE)
		added = true
		i += 3
	return added


## A bridge across the river hex: from the bank where the road comes in to the far one.
func _add_bridge(data: MeshData, road: _Strip, c: Vector2, ends: Array, l: HexLevel, surface: TerrainSurface, rivers: Array, sea: float) -> void:
	var a: Vector2
	var b: Vector2
	if ends.size() >= 2:
		var best := -1.0
		for i in ends.size():
			for j in range(i + 1, ends.size()):
				var dd := (ends[i] as Vector2).distance_to(ends[j])
				if dd > best:
					best = dd
					a = ends[i]
					b = ends[j]
	elif ends.size() == 1:
		a = ends[0]
		b = c + (c - a)
	else:
		# Straight across, through the middle.
		a = c + Vector2(-l.hex_size * 0.8, 0)
		b = c + Vector2(l.hex_size * 0.8, 0)
	var ya := surface.sample(a) + 0.2
	var yb := surface.sample(b) + 0.2
	var info2 := RoadNetwork._river_under(c, rivers)
	var water: float = info2[0] if float(info2[0]) > -1e6 else maxf(surface.sample(c), sea)
	var span := a.distance_to(b)
	var rocky := (surface.weight_at(a, HexMapGenerator.Terrain.ROCK) + surface.weight_at(b, HexMapGenerator.Terrain.ROCK)) * 0.5
	if rocky > 0.35 and span < 30.0:
		var ym := maxf((ya + yb) * 0.5 + span * 0.06, water + 1.8)
		RoadNetwork._add_stone_bridge(data, a, b, ya, ym, yb, WIDTH, water, surface)
	else:
		var ym := maxf((ya + yb) * 0.5, water + 1.3)
		RoadNetwork._add_bridge(data, a, b, ya, ym, yb, WIDTH, Color(0.4, 0.27, 0.15), surface, span > 16.0)
	# Any other roads leaving the hex join the deck's middle.
	for e: Vector2 in ends:
		if e != a and e != b:
			road.add(PackedVector2Array([(a + b) * 0.5, e]), surface, sea)


## Road strips, draped like the map's trails.
class _Strip:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(pts: PackedVector2Array, surface: TerrainSurface, sea: float) -> void:
		var n := pts.size()
		if n < 2:
			return
		var kinds := RoadNetwork._ground_kinds(pts, surface)
		var along := 0.0
		var prev := -1
		for k in n:
			if k > 0:
				along += pts[k].distance_to(pts[k - 1])
			var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var side := Vector2(-d.y, d.x) * WIDTH * 0.5
			var base := verts.size()
			for c in 5:
				var u := float(c) / 4.0
				var q := pts[k] + side * (u * 2.0 - 1.0)
				verts.append(Vector3(q.x, maxf(surface.sample_mesh(q), sea) + 0.14, q.y))
				normals.append(surface.normal_at(q))
				uvs.append(Vector2(u, along))
				var gk: Array = kinds[k]
				colors.append(gk[0])
				uv2s.append(gk[1])
			if prev >= 0:
				for c in 4:
					_tri(prev + c, base + c, prev + c + 1)
					_tri(prev + c + 1, base + c, base + c + 1)
			prev = base

	func _tri(a: int, b: int, c: int) -> void:
		if (verts[b] - verts[a]).cross(verts[c] - verts[a]).y < 0.0:
			indices.append_array([a, b, c])
		else:
			indices.append_array([a, c, b])

	func commit() -> ArrayMesh:
		if indices.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
