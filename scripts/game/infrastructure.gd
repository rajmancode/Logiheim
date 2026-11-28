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
var _lamps: MeshInstance3D       # posts, lanterns and kerb stones along the roads
var _glass: MeshInstance3D       # the lanterns' panes, glowing at night
var _pools: MeshInstance3D       # warm light on the road under each lantern at night
var _glass_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
const LAMP_STEP := 18.0          # metres between lanterns along a road


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
	_road_mat.set_shader_parameter("made", 1.0)
	_walls = MeshInstance3D.new()
	_walls.name = "Walls"
	add_child(_walls)
	_lamps = MeshInstance3D.new()
	_lamps.name = "Lamps"
	add_child(_lamps)
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.35, 0.25, 0.12)
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(1.0, 0.68, 0.3)
	_glass = MeshInstance3D.new()
	_glass.name = "LampGlass"
	_glass.material_override = _glass_mat
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_pool_mat.vertex_color_use_as_albedo = true
	_pool_mat.albedo_texture = _pool_texture()
	_pools = MeshInstance3D.new()
	_pools.name = "LampLight"
	_pools.material_override = _pool_mat
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pools)


## The lanterns brighten as night falls.
func _process(_delta: float) -> void:
	if _glass_mat == null:
		return
	var night := Atmosphere.night
	var t := Time.get_ticks_msec() * 0.001
	var flick := 0.92 + 0.08 * sin(t * 9.0) * sin(t * 5.3)
	_glass_mat.emission_energy_multiplier = (0.25 + 3.5 * night) * flick
	_pool_mat.albedo_color = Color(1, 1, 1, clampf(night * 1.3, 0.0, 1.0) * flick)
	_pools.visible = night > 0.05


## A soft round spot of light, bright in the middle.
static func _pool_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func clear() -> void:
	if _roads != null:
		_roads.mesh = null
		_bridges.mesh = null
		_walls.mesh = null
		_lamps.mesh = null
		_glass.mesh = null
		_pools.mesh = null


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
	var lamps := BuildingModels.Kit.new()
	var glass := BuildingModels.Kit.new()
	var pools := MeshData.new()
	for s in world.settlements:
		# Plain roads run as smooth curves through their hexes (see _road_chains); hill roads
		# and bridges are built hex by hex below and the curves meet them at the hex edge.
		for pts: PackedVector2Array in _road_chains(s, l):
			road.add(pts, surface, sea)
			_add_furniture(lamps, glass, pools, pts, surface, sea)
		for cell: int in s.roads:
			var kind := String(s.roads[cell])
			if kind == "road":
				continue
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
	_lamps.mesh = lamps.commit()
	_lamps.material_override = BuildingView.building_material(Color.WHITE)
	_glass.mesh = glass.commit()
	_pools.mesh = pools.to_mesh() if not pools.verts.is_empty() else null
	_walls.material_override = BuildingView.building_material(Color.WHITE)


## Where a plain road hex leads: [neighbouring road hexes it runs on through (plain roads),
## end points (the shared edge with a hill road or bridge, a building's door)].
func _road_links(s: Settlement, l: HexLevel, cell: int) -> Array:
	var occ: Dictionary = world.get("_occupied")
	var views: Dictionary = world.get("_views")
	var cells: Array = []
	var ends: Array = []
	var c := l.cell_center(cell)
	for k in 6:
		var j := l.index_of(HexCoords.neighbor(l.coords[cell], k))
		if j < 0:
			continue
		if s.roads.has(j):
			if String(s.roads[j]) == "road":
				cells.append(j)
			else:
				ends.append((c + l.cell_center(j)) * 0.5)
		elif occ.has(j) and s.buildings.has(occ[j]):
			var v: BuildingView = views.get((occ[j] as Dictionary).uid)
			if v != null:
				var door := v.to_global((v.info.door as Vector3) + Vector3(0, 0, -2.5))
				ends.append(Vector2(door.x, door.z))
	return [cells, ends]


## The clan's plain roads as curves: each run between forks and ends traced through its hex
## middles and rounded off (Chaikin), so a road bends gently from hex to hex instead of
## kinking at every middle; a lone hex runs from door to door, or is a short paved stretch.
func _road_chains(s: Settlement, l: HexLevel) -> Array:
	var links := {}
	for cell: int in s.roads:
		if String(s.roads[cell]) == "road":
			links[cell] = _road_links(s, l, cell)
	var degree := func(c: int) -> int:
		return (links[c][0] as Array).size() + (links[c][1] as Array).size()
	var used := {}
	var out: Array = []
	var walk := func(start: int, first: int) -> PackedVector2Array:
		var pts := PackedVector2Array([l.cell_center(start)])
		var prev := start
		var cur := first
		while true:
			used[Vector2i(mini(prev, cur), maxi(prev, cur))] = true
			pts.append(l.cell_center(cur))
			if degree.call(cur) != 2 or cur == start:
				break
			var nxt := -1
			for j: int in links[cur][0]:
				if j != prev:
					nxt = j
			if nxt < 0:
				# On through to its one end point (a door, a bridge, a hill road).
				pts.append(links[cur][1][0])
				break
			if used.has(Vector2i(mini(cur, nxt), maxi(cur, nxt))):
				break
			prev = cur
			cur = nxt
		return pts
	# Runs start at forks and ends; then whatever is left is a loop.
	for pass_no in 2:
		for c: int in links:
			if pass_no == 0 and degree.call(c) == 2:
				continue
			for j: int in links[c][0]:
				if not used.has(Vector2i(mini(c, j), maxi(c, j))):
					var pts: PackedVector2Array = walk.call(c, j)
					# A run that starts at a hex with a single end point begins there.
					if (links[c][0] as Array).size() == 1 and (links[c][1] as Array).size() == 1:
						pts.insert(0, links[c][1][0])
					out.append(pts)
	for c: int in links:
		var cells: Array = links[c][0]
		var ends: Array = links[c][1]
		var cc := l.cell_center(c)
		# Spurs to every end point, except the one a run already starts or ends on.
		if cells.size() != 1 or ends.size() != 1:
			if cells.is_empty() and ends.size() == 2:
				out.append(PackedVector2Array([ends[0], cc, ends[1]]))
			else:
				for e: Vector2 in ends:
					if not (cells.size() == 1 and ends.size() == 1):
						out.append(PackedVector2Array([cc, e]))
		if cells.is_empty() and ends.is_empty():
			var d := Vector2(l.hex_size * 0.35, 0)
			out.append(PackedVector2Array([cc - d, cc + d]))
	var smooth: Array = []
	for pts: PackedVector2Array in out:
		smooth.append(_densify(_chaikin(pts, 3), 1.6))
	return smooth


## What lines a made road: low kerb stones along both edges, and every LAMP_STEP metres a
## lantern on a post (on alternate sides) whose panes glow at night and throw a warm pool of
## light on the road - so a clan's roads stand out by day and shine by night.
func _add_furniture(k: BuildingModels.Kit, glass: BuildingModels.Kit, pools: MeshData, pts: PackedVector2Array, surface: TerrainSurface, sea: float) -> void:
	var occ: Dictionary = world.get("_occupied")
	var l := world.lv()
	var along := 0.0
	var next_kerb := 0.8
	var next_lamp := LAMP_STEP * 0.5
	var side := 1.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var d := (b - a) / seg
		var n := Vector2(-d.y, d.x)
		while next_kerb <= along + seg:
			var p := a + d * (next_kerb - along)
			for sd: float in [-1.0, 1.0]:
				var q := p + n * sd * (WIDTH * 0.5 + 0.25)
				var y := maxf(surface.sample_mesh(q), sea)
				var sh := 0.85 + 0.15 * sin(q.x * 3.1 + q.y * 1.7)
				k.box(Vector3(q.x, y + 0.06, q.y), Vector3(0.45, 0.26, 0.75), BuildingModels.STONE * sh, Vector3(0, atan2(d.x, d.y), 0))
			next_kerb += 1.7
		while next_lamp <= along + seg:
			var p := a + d * (next_lamp - along)
			var sd0 := side
			var q := p + n * sd0 * (WIDTH * 0.5 + 0.75)
			next_lamp += LAMP_STEP
			# Not in a building's yard.
			var cell := l.nearest_cell(q)
			if occ.has(cell) or surface.sample_mesh(q) < sea + 0.2:
				continue
			side = -side
			var y := surface.sample_mesh(q)
			var base := Vector3(q.x, y - 0.2, q.y)
			k.post(base, 3.1, 0.09, BuildingModels.DARK_WOOD)
			# An arm out over the road with the lantern hanging from it.
			var out := Vector3(-n.x * sd0, 0, -n.y * sd0)
			var arm_end := base + Vector3(0, 3.1, 0) + out * 0.9
			k.log(base + Vector3(0, 3.05, 0) + out * 0.45, 0.05, 1.0, BuildingModels.DARK_WOOD, out)
			var lc := arm_end + Vector3(0, -0.45, 0)
			k.box(lc + Vector3(0, 0.3, 0), Vector3(0.42, 0.08, 0.42), Color(0.16, 0.15, 0.15))
			k.box(lc - Vector3(0, 0.3, 0), Vector3(0.36, 0.06, 0.36), Color(0.16, 0.15, 0.15))
			k.cone(lc + Vector3(0, 0.34, 0), 0.3, 0.22, Color(0.16, 0.15, 0.15), 4)
			glass.box(lc, Vector3(0.3, 0.52, 0.3), Color.WHITE)
			# The pool of light on the ground beneath.
			var r := 4.5
			var g := maxf(surface.sample_mesh(Vector2(lc.x, lc.z)), sea) + 0.35
			var c3 := Vector3(lc.x, g, lc.z)
			var col := Color(1.0, 0.62, 0.28, 0.55)
			var v := [c3 + Vector3(-r, 0, -r), c3 + Vector3(r, 0, -r), c3 + Vector3(r, 0, r), c3 + Vector3(-r, 0, r)]
			pools.tri(v[0], v[1], v[2], Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector3.UP, Vector2.ZERO, col)
			pools.tri(v[0], v[2], v[3], Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), Vector3.UP, Vector2.ZERO, col)
		along += seg


## Rounds a polyline's corners off, keeping its two ends.
static func _chaikin(pts: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var p := pts
	for r in rounds:
		if p.size() < 3:
			return p
		var q := PackedVector2Array([p[0]])
		for i in p.size() - 1:
			q.append(p[i].lerp(p[i + 1], 0.25))
			q.append(p[i].lerp(p[i + 1], 0.75))
		q.append(p[p.size() - 1])
		p = q
	return p


## Points along a polyline no further apart than `step`, so the strip follows the ground.
static func _densify(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var n := maxi(1, int(ceil(pts[i].distance_to(pts[i + 1]) / step)))
		for k in n:
			out.append(pts[i].lerp(pts[i + 1], float(k) / n))
	if not pts.is_empty():
		out.append(pts[pts.size() - 1])
	return out


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
