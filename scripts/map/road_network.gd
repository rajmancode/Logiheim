class_name RoadNetwork
extends RefCounted
## Trails across the land, for units to travel faster.
##
## plan() (finest level): picks natural settlement spots (flat, dry, open ground, best near the
## coast, rivers and lakes), spaced about `road_spacing` apart, links them with a minimum
## spanning tree plus a few extra links for loops, and routes every link over the hexes with
## A*: steep ground, rock, snow, wetland and volcanic ground cost more, the sea and lakes are
## impassable, rivers are crossed on bridges, and following an existing trail is cheap, so
## trails merge into a network. The hex path is jittered and smoothed into a winding trail.
## apply() (every level): cuts the trail into the ground (gentle cut and fill), keeps trees off
## it and marks its hexes (`level.road`, lower movement cost). build_meshes(): the trail ribbon
## (packed earth and gravel with wheel ruts, soft edges) and wooden bridges.

## Each: {pts: PackedVector2Array (about 4 m apart), bridge: PackedByteArray (1 = on a bridge)}.
var roads: Array = []
var width := 3.5

static var _trail_mat: ShaderMaterial

const STEP := 4.0


static func plan(level: HexLevel, surface: TerrainSurface, settings: HexMapSettings, destinations: Array = []) -> RoadNetwork:
	var rn := RoadNetwork.new()
	rn.width = settings.road_width
	if not settings.roads_enabled:
		return rn
	var n := level.cell_count()
	var hh := PackedFloat32Array()
	hh.resize(n)
	var blocked := PackedByteArray()
	blocked.resize(n)
	var T := HexMapGenerator.Terrain
	for i in n:
		var c := level.cell_center(i)
		hh[i] = surface.sample(c)
		if HexMapGenerator.is_water(level.terrain[i]) or level.lake[i] == 1 or hh[i] < surface.sea_y + 0.5:
			blocked[i] = 1
	# Settlement spots.
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(5150)
	var cands: Array = []
	for i in n:
		var t := level.terrain[i]
		if blocked[i] == 1 or level.river[i] == 1 or t == T.ROCK or t == T.SNOW:
			continue
		var c := level.cell_center(i)
		if surface.normal_at(c).y < 0.88 or surface.wetland_at(c) > 0.4 or surface.volcanic_at(c) > 0.2:
			continue
		var score := surface.normal_at(c).y + rng.randf() * 0.4
		for k in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[i], k))
			if j < 0:
				continue
			if HexMapGenerator.is_water(level.terrain[j]):
				score += 0.35
			if level.river[j] == 1 or level.lake[j] == 1:
				score += 0.25
		cands.append([score, i])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var nodes: Array[int] = []
	# Destinations first (cave entrances): every one gets a trail.
	for d: Vector2 in destinations:
		var cell := level.cell_at(d)
		if cell >= 0 and blocked[cell] == 0 and not nodes.has(cell):
			nodes.append(cell)
	for cand in cands:
		var c := level.cell_center(cand[1])
		var ok := true
		for o in nodes:
			if level.cell_center(o).distance_to(c) < settings.road_spacing:
				ok = false
				break
		if ok:
			nodes.append(cand[1])
		if nodes.size() >= 90:
			break
	if nodes.size() < 2:
		return rn
	# Links: minimum spanning tree (Prim) plus a few short extra links for loops.
	var links: Array = []
	var in_tree := {nodes[0]: true}
	while in_tree.size() < nodes.size():
		var best := INF
		var pair := [-1, -1]
		for a in in_tree:
			for b in nodes:
				if in_tree.has(b):
					continue
				var d := level.cell_center(a).distance_to(level.cell_center(b))
				if d < best:
					best = d
					pair = [a, b]
		in_tree[pair[1]] = true
		links.append([pair[0], pair[1], best])
	for a in nodes:
		var best := INF
		var bb := -1
		for b in nodes:
			if b == a:
				continue
			var d := level.cell_center(a).distance_to(level.cell_center(b))
			var known := false
			for l in links:
				if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
					known = true
			if not known and d < best:
				best = d
				bb = b
		if bb >= 0 and best < settings.road_spacing * 2.4 and rng.randf() < 0.85:
			links.append([a, bb, best])
		# Now and then a second, longer link for more loops and crossroads.
		var second := -1
		var second_d := INF
		for b in nodes:
			if b == a or b == bb:
				continue
			var d := level.cell_center(a).distance_to(level.cell_center(b))
			if d < second_d:
				second_d = d
				second = b
		if second >= 0 and second_d < settings.road_spacing * 2.6 and rng.randf() < 0.4:
			links.append([a, second, second_d])
	links.sort_custom(func(a, b): return a[2] < b[2])
	# Route.
	var on_road := PackedByteArray()
	on_road.resize(n)
	var wet := PackedFloat32Array()
	wet.resize(n)
	var volc := PackedFloat32Array()
	volc.resize(n)
	for i in n:
		var c := level.cell_center(i)
		wet[i] = surface.wetland_at(c)
		volc[i] = surface.volcanic_at(c)
	var hex_w := HexCoords.SQRT3 * level.hex_size
	for l in links:
		var cells := _route(level, l[0], l[1], hh, blocked, on_road, wet, volc, hex_w)
		if cells.size() < 2:
			continue
		for c in cells:
			on_road[c] = 1
		rn.roads.append(rn._shape(level, surface, cells))
	print("RoadNetwork: %d spots, %d trails" % [nodes.size(), rn.roads.size()])
	return rn


## A* over the hexes from a to b.
static func _route(level: HexLevel, a: int, b: int, hh: PackedFloat32Array, blocked: PackedByteArray,
		on_road: PackedByteArray, wet: PackedFloat32Array, volc: PackedFloat32Array, hex_w: float) -> PackedInt32Array:
	var T := HexMapGenerator.Terrain
	var n := level.cell_count()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap: Array = []   # [f, cell], binary min-heap
	g[a] = 0.0
	_push(heap, [0.0, a])
	var goal := level.coords[b]
	while not heap.is_empty():
		var cur: Array = _pop(heap)
		var i: int = cur[1]
		if closed[i] == 1:
			continue
		closed[i] = 1
		if i == b:
			break
		for k in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[i], k))
			if j < 0 or blocked[j] == 1 or closed[j] == 1:
				continue
			var grade := absf(hh[j] - hh[i]) / hex_w
			var cost := 1.0 + 25.0 * grade * grade + (40.0 if grade > 0.6 else 0.0)
			if level.river[j] == 1:
				cost += 4.0
			match level.terrain[j]:
				T.ROCK:
					cost += 1.5
				T.SNOW:
					cost += 4.0
				T.FOREST:
					cost += 0.4
			cost += wet[j] * 4.0 + volc[j] * 4.0
			if on_road[j] == 1:
				cost *= 0.35
			var ng := g[i] + cost
			if ng < g[j]:
				g[j] = ng
				came[j] = i
				_push(heap, [ng + HexCoords.distance(level.coords[j], goal) * 0.35, j])
	if came[b] < 0:
		return PackedInt32Array()
	var out := PackedInt32Array([b])
	var c := b
	while c != a:
		c = came[c]
		out.append(c)
	out.reverse()
	return out


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if heap[p][0] <= heap[i][0]:
			break
		var t = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < heap.size() and heap[l][0] < heap[m][0]:
			m = l
		if r < heap.size() and heap[r][0] < heap[m][0]:
			m = r
		if m == i:
			break
		var t = heap[m]
		heap[m] = heap[i]
		heap[i] = t
		i = m
	return top


## Hex path -> a winding trail: centres jittered sideways, corners rounded (Chaikin), then
## resampled every STEP metres; bridge where it crosses a river.
func _shape(level: HexLevel, surface: TerrainSurface, cells: PackedInt32Array) -> Dictionary:
	var pts := PackedVector2Array()
	for k in cells.size():
		var c := level.cell_center(cells[k])
		if k > 0 and k < cells.size() - 1:
			var d := (level.cell_center(cells[k + 1]) - level.cell_center(cells[k - 1])).normalized()
			var side := Vector2(-d.y, d.x)
			c += side * (BorderNoise.snoise(c * 0.05) - 0.5) * level.hex_size * 0.7
		pts.append(c)
	for it in 4:
		if pts.size() < 3:
			break
		var np := PackedVector2Array([pts[0]])
		for k in pts.size() - 1:
			np.append(pts[k].lerp(pts[k + 1], 0.25))
			np.append(pts[k].lerp(pts[k + 1], 0.75))
		np.append(pts[pts.size() - 1])
		pts = np
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		var t := STEP - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += STEP
		carry = seg - (t - STEP)
	out.append(pts[pts.size() - 1])
	var bridge := PackedByteArray()
	bridge.resize(out.size())
	for k in out.size():
		if surface.river_at(out[k]) > 0.45:
			bridge[k] = 1
	# Grow bridges a little so they reach dry banks.
	var grown := bridge.duplicate()
	for k in out.size():
		if bridge[k] == 1:
			for q in range(maxi(0, k - 2), mini(out.size(), k + 3)):
				grown[q] = 1
	return {"pts": out, "bridge": grown}


## Cuts the trails into a level's surface and marks its hexes.
func apply(level: HexLevel, surface: TerrainSurface) -> void:
	if level.road.size() != level.cell_count():
		level.road.resize(level.cell_count())
	level.road.fill(0)
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var bridge: PackedByteArray = r.bridge
		var n := pts.size()
		# Target grade: the ground along the trail, smoothed, so it climbs evenly.
		var ys := PackedFloat32Array()
		ys.resize(n)
		for k in n:
			ys[k] = surface.sample(pts[k])
		var sm := ys.duplicate()
		for k in n:
			var acc := 0.0
			var cnt := 0
			for q in range(maxi(0, k - 5), mini(n, k + 6)):
				acc += ys[q]
				cnt += 1
			sm[k] = acc / cnt
		var half := width * 0.5
		var reach := half + 3.0
		for k in n:
			var p := pts[k]
			var cell := level.cell_at(p)
			if cell >= 0:
				level.road[cell] = 1
			if bridge[k] == 1:
				continue
			var x0 := maxi(0, floori((p.x - reach) / surface.spacing))
			var x1 := mini(surface.nx - 1, ceili((p.x + reach) / surface.spacing))
			var z0 := maxi(0, floori((p.y - reach) / surface.spacing))
			var z1 := mini(surface.nz - 1, ceili((p.y + reach) / surface.spacing))
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var i := z * surface.nx + x
					var d := Vector2(x * surface.spacing, z * surface.spacing).distance_to(p)
					if d > reach or surface.river_mask[i] > 0.5:
						continue
					var t := 1.0 - smoothstep(half, reach, d)
					surface.heights[i] = lerpf(surface.heights[i], sm[k], t * 0.85)
					surface.path_mask[i] = maxf(surface.path_mask[i], 1.0 - smoothstep(half * 0.6, half + 1.0, d))
					if d < half + 2.0:
						surface.clear_mask[i] = 1


## The trail ribbons and bridges.
func build_meshes(surface: TerrainSurface, parent: Node3D) -> void:
	if roads.is_empty():
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var bridges := MeshData.new()
	var wood := Color(0.36, 0.24, 0.14)
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var bridge: PackedByteArray = r.bridge
		var n := pts.size()
		var along := 0.0
		var prev := -1
		for k in n:
			if k > 0:
				along += pts[k].distance_to(pts[k - 1])
			if bridge[k] == 1:
				prev = -1
				continue
			var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var side := Vector2(-d.y, d.x) * width * 0.5
			var l := pts[k] - side
			var rr := pts[k] + side
			var base := verts.size()
			verts.append(Vector3(l.x, surface.sample(l) + 0.1, l.y))
			verts.append(Vector3(rr.x, surface.sample(rr) + 0.1, rr.y))
			uvs.append(Vector2(0.0, along))
			uvs.append(Vector2(1.0, along))
			normals.append(surface.normal_at(l))
			normals.append(surface.normal_at(rr))
			if prev >= 0:
				var cross_up := (verts[base + 1] - verts[prev]).cross(verts[base] - verts[prev]).y > 0.0
				if cross_up:
					indices.append_array([prev, base, prev + 1, prev + 1, base, base + 1])
				else:
					indices.append_array([prev, prev + 1, base, prev + 1, base + 1, base])
			prev = base
		# Bridges: one straight deck per run of bridge points.
		var k := 0
		while k < n:
			if bridge[k] == 0:
				k += 1
				continue
			var k0 := k
			while k < n and bridge[k] == 1:
				k += 1
			var k1 := k - 1
			var a := pts[maxi(k0 - 1, 0)]
			var b := pts[mini(k1 + 1, n - 1)]
			var y := maxf(surface.sample(a), surface.sample(b)) + 0.35
			_add_bridge(bridges, a, b, y, width * 0.9, wood)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if not verts.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Trails"
		mi.mesh = mesh
		mi.material_override = _trail_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	if not bridges.verts.is_empty():
		var bm := MeshInstance3D.new()
		bm.name = "Bridges"
		bm.mesh = bridges.to_mesh()
		bm.material_override = ResourceProps._material("body")
		parent.add_child(bm)


## A plank deck with posts and rails from a to b.
static func _add_bridge(data: MeshData, a: Vector2, b: Vector2, y: float, w: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var mid := (a + b) * 0.5
	_box(data, Vector3(mid.x, y, mid.y), dir, side, length + 1.0, w, 0.35, col)
	for s: float in [-1.0, 1.0]:
		var rail: Vector2 = mid + side * s * w * 0.5
		_box(data, Vector3(rail.x, y + 0.75, rail.y), dir, side, length + 0.6, 0.15, 0.12, col * 0.9)
		var posts := maxi(2, int(length / 3.0) + 1)
		for q in posts:
			var t := float(q) / (posts - 1) - 0.5
			var pp: Vector2 = rail + dir * t * length
			_box(data, Vector3(pp.x, y + 0.35, pp.y), dir, side, 0.2, 0.2, 0.9, col * 0.8)


static func _box(data: MeshData, c: Vector3, dir: Vector2, side: Vector2, l: float, w: float, h: float, col: Color) -> void:
	var ex := Vector3(dir.x, 0, dir.y) * l * 0.5
	var ez := Vector3(side.x, 0, side.y) * w * 0.5
	var ey := Vector3(0, h * 0.5, 0)
	var corners := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(c + ex * sx + ey * sy + ez * sz)
	# Faces: (indices into corners, outward normal)
	var faces := [
		[[0, 1, 3, 2], -ex.normalized()], [[4, 6, 7, 5], ex.normalized()],
		[[0, 4, 5, 1], -Vector3.UP], [[2, 3, 7, 6], Vector3.UP],
		[[0, 2, 6, 4], -ez.normalized()], [[1, 5, 7, 3], ez.normalized()],
	]
	for f in faces:
		var q: Array = f[0]
		var nrm: Vector3 = f[1]
		data.tri(corners[q[0]], corners[q[1]], corners[q[2]], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, Vector2.ZERO, col)
		data.tri(corners[q[0]], corners[q[2]], corners[q[3]], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, Vector2.ZERO, col)


static func _trail_material() -> ShaderMaterial:
	if _trail_mat == null:
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = load("res://shaders/trail.gdshader")
		_trail_mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
		_trail_mat.set_shader_parameter("normal_array", TerrainMaterial.normal_array())
	return _trail_mat
