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
## River water by 10 m cell: [centre, half-width] of every river point (bridges only over water).
var _water_grid := {}

const STEP := 2.0
## Steepest a trail may climb (rise/run), and how deep it may cut or fill to manage that.
const MAX_GRADE := 0.15
const MAX_CUT := 2.5
## Columns across the trail ribbon, so it follows the ground across as well as along.
const ACROSS := 4


static func plan(level: HexLevel, surface: TerrainSurface, settings: HexMapSettings, destinations: Array = [], rivers: Array = []) -> RoadNetwork:
	var rn := RoadNetwork.new()
	for path: RiverPath in rivers:
		for k in path.points.size():
			var q := Vector2(path.points[k].x, path.points[k].z)
			var key := Vector2i(floori(q.x / 10.0), floori(q.y / 10.0))
			if not rn._water_grid.has(key):
				rn._water_grid[key] = []
			var qa := path.points[maxi(k - 1, 0)]
			var qb := path.points[mini(k + 1, path.points.size() - 1)]
			rn._water_grid[key].append([q, path.widths[k] * 0.5, Vector2(qb.x - qa.x, qb.z - qa.z).normalized()])
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
	# River hexes within two hexes of an existing crossing, and hexes beside a trail.
	var bridge_near := PackedByteArray()
	bridge_near.resize(n)
	var beside := PackedByteArray()
	beside.resize(n)
	# How steep the ground under each hex is (cross-slope matters too, not just the grade).
	var steep := PackedFloat32Array()
	steep.resize(n)
	for i in n:
		var ny := surface.normal_at(level.cell_center(i)).y
		var tan_s := sqrt(maxf(1.0 / (ny * ny) - 1.0, 0.0))
		# Steep ground is all but off-limits: trails go round it.
		steep[i] = 25.0 * smoothstep(0.08, 0.3, tan_s) + (400.0 if tan_s > 0.45 else 0.0)
	for l in links:
		var cells := _route(level, l[0], l[1], hh, blocked, on_road, wet, volc, hex_w, steep, bridge_near, beside)
		if cells.size() < 2:
			continue
		for c in cells:
			on_road[c] = 1
		_mark_near(level, cells, bridge_near, beside)
		rn.roads.append(rn._merge(rn._shape(level, surface, cells)))
	# Spurs: every land deposit gets a trail to its door, joining the nearest trail.
	var spurs := 0
	for d: Dictionary in level.deposits:
		var kind: int = d.kind
		if kind == NaturalResources.Kind.FISH or kind == NaturalResources.Kind.WHALES:
			continue
		var c: int = d.center
		if c < 0 or blocked[c] == 1:
			continue
		var near := on_road[c] == 1
		for kk in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[c], kk))
			if j >= 0 and on_road[j] == 1:
				near = true
		if near:
			continue
		var cells := _route(level, c, -1, hh, blocked, on_road, wet, volc, hex_w, steep, bridge_near, beside)
		if cells.size() < 2:
			continue
		for cc in cells:
			on_road[cc] = 1
		_mark_near(level, cells, bridge_near, beside)
		rn.roads.append(rn._merge(rn._shape(level, surface, cells)))
		spurs += 1
	print("RoadNetwork: %d spots, %d trails, %d spurs to deposits" % [nodes.size(), rn.roads.size() - spurs, spurs])
	return rn


## After a trail is laid: river hexes near its crossings, and the hexes beside it.
static func _mark_near(level: HexLevel, cells: PackedInt32Array, bridge_near: PackedByteArray, beside: PackedByteArray) -> void:
	for c in cells:
		for k in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[c], k))
			if j >= 0:
				beside[j] = 1
		if level.river[c] != 1:
			continue
		for j in level.cell_count():
			if level.river[j] == 1 and HexCoords.distance(level.coords[j], level.coords[c]) <= 3:
				bridge_near[j] = 1


## A* over the hexes from a to b; with b = -1, to the nearest hex already on a trail.
static func _route(level: HexLevel, a: int, b: int, hh: PackedFloat32Array, blocked: PackedByteArray,
		on_road: PackedByteArray, wet: PackedFloat32Array, volc: PackedFloat32Array, hex_w: float, steep: PackedFloat32Array,
		bridge_near: PackedByteArray, beside: PackedByteArray) -> PackedInt32Array:
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
	var goal := level.coords[b] if b >= 0 else Vector2i.ZERO
	var found := -1
	while not heap.is_empty():
		var cur: Array = _pop(heap)
		var i: int = cur[1]
		if closed[i] == 1:
			continue
		closed[i] = 1
		if i == b or (b < 0 and i != a and on_road[i] == 1):
			found = i
			break
		if b < 0 and g[i] > 5000.0:
			break
		for k in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[i], k))
			if j < 0 or blocked[j] == 1 or closed[j] == 1:
				continue
			var grade := absf(hh[j] - hh[i]) / hex_w
			# Trails keep to flat ground: steep grades and steep ground underfoot cost a lot.
			var cost := 1.0 + 70.0 * grade * grade + (60.0 if grade > 0.15 else 0.0) + (200.0 if grade > 0.3 else 0.0) + steep[j]
			if level.river[j] == 1:
				cost += 25.0   # cross rivers, don't follow them
				# One crossing per stretch of river: with a bridge already close by, use it.
				if on_road[j] == 0 and bridge_near[j] == 1:
					cost += 400.0
			elif on_road[j] == 0 and beside[j] == 1:
				cost += 3.0    # don't run alongside a trail: join it or keep away
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
				_push(heap, [ng + (HexCoords.distance(level.coords[j], goal) * 0.35 if b >= 0 else 0.0), j])
	if found < 0 or came[found] < 0:
		return PackedInt32Array()
	var out := PackedInt32Array([found])
	var c := found
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
			# The same sideways wobble whichever way a trail runs, so trails sharing hexes
			# share one line (and one bridge) instead of running side by side.
			if d.x < 0.0 or (is_zero_approx(d.x) and d.y < 0.0):
				d = -d
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
		if _over_water(out[k]):
			bridge[k] = 1
	# Spans of one trail only a few metres apart are one crossing (a confluence, a braided
	# channel): bridge the gap.
	var gap := -1
	for q in out.size():
		if bridge[q] == 1:
			if gap >= 0 and q - gap <= 4:
				for g in range(gap, q):
					bridge[g] = 1
			gap = -1
		elif q > 0 and bridge[q - 1] == 1:
			gap = q
	# A bridge only where the trail really crosses (from one bank to the other). A trail that
	# just brushes the water while running along a river is pushed back onto its bank.
	var kk := 0
	while kk < out.size():
		if bridge[kk] == 0:
			kk += 1
			continue
		var k0 := kk
		while kk < out.size() and bridge[kk] == 1:
			kk += 1
		var a := out[maxi(k0 - 1, 0)]
		var b := out[mini(kk, out.size() - 1)]
		var e := _nearest_water((a + b) * 0.5)
		if e.is_empty():
			continue
		var nrm := Vector2(-(e[2] as Vector2).y, (e[2] as Vector2).x)
		var sa: float = (a - e[0]).dot(nrm)
		var sb: float = (b - e[0]).dot(nrm)
		# Crossing: opposite banks, across the flow, and not much longer than the river is wide.
		var along_flow := absf((b - a).normalized().dot(e[2] as Vector2)) > 0.7
		var too_long := a.distance_to(b) > float(e[1]) * 5.0 + 14.0
		if sa * sb < 0.0 and not along_flow and not too_long:
			continue
		var side := 1.0 if sa + sb >= 0.0 else -1.0
		for q in range(k0, kk):
			var eq := _nearest_water(out[q])
			if eq.is_empty():
				continue
			var nq := Vector2(-(eq[2] as Vector2).y, (eq[2] as Vector2).x) * side
			var need := float(eq[1]) + width * 0.5 + 3.0
			var off: float = (out[q] - eq[0]).dot(nq)
			if off < need:
				out[q] += nq * (need - off)
			bridge[q] = 0
	# Grow each bridge just until both ends stand on dry bank (a metre or two clear of the
	# water), no further: a short crossing stays a short bridge.
	var grown := bridge.duplicate()
	for k in out.size():
		if bridge[k] != 1:
			continue
		for dirn: int in [-1, 1]:
			var q := k + dirn
			var steps := 0
			while q >= 0 and q < out.size() and bridge[q] == 0 and steps < 4:
				grown[q] = 1
				steps += 1
				if _river_gap(out[q]) > 1.5:
					break
				q += dirn
	return {"pts": out, "bridge": grown}


## Where a new trail runs alongside one already laid (within ~12 m), it is drawn onto the old
## line, easing over, so shared stretches are one trail with one bridge, not two side by side.
## Bridges are then taken from the old trail.
func _merge(r: Dictionary) -> Dictionary:
	var pts: PackedVector2Array = r.pts
	var bridge: PackedByteArray = r.bridge
	var shared := PackedByteArray()
	shared.resize(pts.size())
	if roads.is_empty():
		r["shared"] = shared
		return r
	var grid := {}
	for o: Dictionary in roads:
		var op: PackedVector2Array = o.pts
		var ob: PackedByteArray = o.bridge
		for k in op.size():
			var key := Vector2i(floori(op[k].x / 12.0), floori(op[k].y / 12.0))
			if not grid.has(key):
				grid[key] = []
			grid[key].append([op[k], ob[k]])
	var w := PackedFloat32Array()
	w.resize(pts.size())
	var near := PackedVector2Array()
	near.resize(pts.size())
	var nb := PackedByteArray()
	nb.resize(pts.size())
	for k in pts.size():
		var key := Vector2i(floori(pts[k].x / 12.0), floori(pts[k].y / 12.0))
		var best := INF
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for e: Array in grid.get(key + Vector2i(dx, dz), []):
					var d := pts[k].distance_to(e[0])
					if d < best:
						best = d
						near[k] = e[0]
						nb[k] = e[1]
		w[k] = 1.0 - smoothstep(8.0, 26.0, best)
	# Ease the pull in and out along the trail (no kinks where it starts and stops).
	var ws := w.duplicate()
	for k in pts.size():
		var acc := 0.0
		var cnt := 0
		for q in range(maxi(0, k - 3), mini(pts.size(), k + 4)):
			acc += w[q]
			cnt += 1
		ws[k] = minf(w[k], acc / cnt) if w[k] < 0.99 else w[k]
	for k in pts.size():
		pts[k] = pts[k].lerp(near[k], ws[k])
		if ws[k] > 0.9:
			bridge[k] = 0   # the old trail's bridge carries it here
			shared[k] = 1   # and the old trail's ribbon and bed
	return {"pts": pts, "bridge": bridge, "shared": shared}


## Distance from p to the nearest river's edge (negative on the water), up to ~20 m.
func _river_gap(p: Vector2) -> float:
	var key := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
	var best := 20.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for e: Array in _water_grid.get(key + Vector2i(dx, dz), []):
				best = minf(best, p.distance_to(e[0]) - float(e[1]))
	return best


## The nearest river point to p ([position, half width, flow direction]), or [].
func _nearest_water(p: Vector2) -> Array:
	var key := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
	var best := INF
	var out: Array = []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for e: Array in _water_grid.get(key + Vector2i(dx, dz), []):
				var d := p.distance_to(e[0])
				if d < best:
					best = d
					out = e
	return out


## True if p is on a river's water (within its half-width).
func _over_water(p: Vector2) -> bool:
	var key := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for e: Array in _water_grid.get(key + Vector2i(dx, dz), []):
				if p.distance_to(e[0]) < float(e[1]) + 0.5:
					return true
	return false


## Cuts the trails into a level's surface and marks its hexes.
func apply(level: HexLevel, surface: TerrainSurface) -> void:
	if level.road.size() != level.cell_count():
		level.road.resize(level.cell_count())
	level.road.fill(0)
	# Every trail first records, per terrain vertex, the bed height it wants and how strongly
	# (1 on the bed, easing to 0 across a bank whose width grows with the depth of the cut or
	# fill, so embankments slope gently instead of dropping as walls). The strongest wins and
	# the ground is blended once, then the bank band is smoothed so it melds into the land.
	var nv := surface.heights.size()
	var want_t := PackedFloat32Array()
	want_t.resize(nv)
	var want_y := PackedFloat32Array()
	want_y.resize(nv)
	var want_w := PackedFloat32Array()
	want_w.resize(nv)
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
			for q in range(maxi(0, k - 10), mini(n, k + 11)):
				acc += ys[q]
				cnt += 1
			sm[k] = acc / cnt
		# A trail never climbs steeper than MAX_GRADE: the profile is limited both ways along
		# the trail, cutting into rises and building up over dips (by at most MAX_CUT metres;
		# beyond that the trail follows the ground).
		for it in 2:
			for k in range(1, n):
				var ds := pts[k].distance_to(pts[k - 1])
				sm[k] = clampf(sm[k], sm[k - 1] - MAX_GRADE * ds, sm[k - 1] + MAX_GRADE * ds)
			for k in range(n - 2, -1, -1):
				var ds := pts[k].distance_to(pts[k + 1])
				sm[k] = clampf(sm[k], sm[k + 1] - MAX_GRADE * ds, sm[k + 1] + MAX_GRADE * ds)
		for k in n:
			sm[k] = clampf(sm[k], ys[k] - MAX_CUT, ys[k] + MAX_CUT)
		# Ease the profile where the cap kicks in and out (no kinks, no lumps).
		var sm2 := sm.duplicate()
		for k in n:
			var acc := 0.0
			var cnt := 0
			for q in range(maxi(0, k - 4), mini(n, k + 5)):
				acc += sm[q]
				cnt += 1
			sm2[k] = clampf(acc / cnt, ys[k] - MAX_CUT, ys[k] + MAX_CUT)
		sm = sm2
		# Fords: off the bridges, a trail never rises above the ground near a river (no
		# embankment damming a stream); it eases down to the water's edge instead.
		for k in n:
			if bridge[k] == 1:
				continue
			var gap := _river_gap(pts[k])
			if gap < 14.0:
				sm[k] = minf(sm[k], lerpf(ys[k] + 0.2, sm[k], smoothstep(4.0, 14.0, gap)))
		# Cut (-) or fill (+) at each point, kept for debugging and tests.
		var cut := PackedFloat32Array()
		cut.resize(n)
		for k in n:
			cut[k] = sm[k] - ys[k]
		r["cut"] = cut
		var half := width * 0.5
		# The levelled bed must reach the nearest terrain grid vertices, or the 5 m grid would
		# leave the trail on the old slope between them.
		var flat_r := half + surface.spacing * 0.75
		for k in n:
			var p := pts[k]
			var cell := level.cell_at(p)
			if cell >= 0:
				level.road[cell] = 1
			if bridge[k] == 1 or (r.has("shared") and (r.shared as PackedByteArray)[k] == 1):
				continue
			# Bank width: at least 7 m, and about 1 in 3 for deep cuts and fills.
			var bank := 7.0 + absf(sm[k] - ys[k]) * 3.0
			var reach := flat_r + bank
			var x0 := maxi(0, floori((p.x - reach) / surface.spacing))
			var x1 := mini(surface.nx - 1, ceili((p.x + reach) / surface.spacing))
			var z0 := maxi(0, floori((p.y - reach) / surface.spacing))
			var z1 := mini(surface.nz - 1, ceili((p.y + reach) / surface.spacing))
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var i := z * surface.nx + x
					var d := Vector2(x * surface.spacing, z * surface.spacing).distance_to(p)
					if d > reach or surface.river_mask[i] > 0.3:
						continue
					# Level across the whole width (t = 1), easing back into the ground beyond
					# (smootherstep: no crease where the bank meets the bed or the land).
					var u := clampf((d - flat_r) / bank, 0.0, 1.0)
					var t := (1.0 - u * u * u * (u * (u * 6.0 - 15.0) + 10.0)) * (1.0 - surface.river_mask[i] / 0.3)
					# Where trails meet or run close, their beds are averaged (weighted to the
					# nearer one) instead of one overriding the other, so no steps at junctions.
					want_t[i] = maxf(want_t[i], t)
					want_y[i] += sm[k] * t * t * t
					want_w[i] += t * t * t
					surface.path_mask[i] = maxf(surface.path_mask[i], 1.0 - smoothstep(half * 0.6, half + 1.0, d))
					if d < half + 2.0:
						surface.clear_mask[i] = 1
	for i in nv:
		if want_t[i] > 0.0 and want_w[i] > 0.0:
			surface.heights[i] = lerpf(surface.heights[i], want_y[i] / want_w[i], want_t[i])
	# Smooth the banks (not the bed, not river channels): two passes of a 3x3 average, weighted
	# towards the middle of the bank where creases would show.
	for it in 2:
		var src := surface.heights.duplicate()
		for z in range(1, surface.nz - 1):
			for x in range(1, surface.nx - 1):
				var i := z * surface.nx + x
				var t := want_t[i]
				if t <= 0.0 or t >= 0.98 or surface.river_mask[i] > 0.5:
					continue
				var acc := 0.0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						acc += src[i + dz * surface.nx + dx]
				var w := 4.0 * t * (1.0 - t) + 0.25
				surface.heights[i] = lerpf(src[i], acc / 9.0, minf(w, 1.0))


## The trail ribbons and bridges.
func build_meshes(surface: TerrainSurface, parent: Node3D, rivers: Array = []) -> void:
	if roads.is_empty():
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var bridges := MeshData.new()
	var wood := Color(0.36, 0.24, 0.14)
	var built: Array[Vector2] = []
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r.pts
		var bridge: PackedByteArray = r.bridge
		var shared: PackedByteArray = r.get("shared", PackedByteArray())
		var n := pts.size()
		var ground := _ground_kinds(pts, surface)
		var along := 0.0
		var prev := -1
		for k in n:
			if k > 0:
				along += pts[k].distance_to(pts[k - 1])
			if bridge[k] == 1 or (shared.size() == n and shared[k] == 1):
				prev = -1
				continue
			var d := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var side := Vector2(-d.y, d.x) * width * 0.5
			var base := verts.size()
			for c in ACROSS + 1:
				var u := float(c) / ACROSS
				var q := pts[k] + side * (u * 2.0 - 1.0)
				# Exactly on the terrain mesh's triangles, so the trail never dips into the ground.
				verts.append(Vector3(q.x, surface.sample_mesh(q) + 0.1, q.y))
				uvs.append(Vector2(u, along))
				# The ground the trail runs over (picks its surface in trail.gdshader).
				var gk: Array = ground[k]
				colors.append(gk[0])
				uv2s.append(gk[1])
				normals.append(surface.normal_at(q))
			if prev >= 0:
				for c in ACROSS:
					var a0 := prev + c
					var a1 := prev + c + 1
					var b0 := base + c
					var b1 := base + c + 1
					for tri in [[a0, b0, a1], [a1, b0, b1]]:
						var cross_y := (verts[tri[1]] - verts[tri[0]]).cross(verts[tri[2]] - verts[tri[0]]).y
						# Clockwise from above = facing up in Godot.
						if cross_y < 0.0:
							indices.append_array([tri[0], tri[1], tri[2]])
						else:
							indices.append_array([tri[0], tri[2], tri[1]])
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
			# One bridge per crossing: another trail's bridge here already carries this one.
			var mid := (a + b) * 0.5
			var dup := false
			for q in built:
				if q.distance_to(mid) < 18.0:
					dup = true
					break
			if dup:
				continue
			built.append(mid)
			# Each end sits on its own bank; the middle clears the river's water.
			var ya := surface.sample(a) + 0.15
			var yb := surface.sample(b) + 0.15
			var info := _river_under((a + b) * 0.5, rivers)
			var water: float = info[0]
			var river_w: float = info[1]
			var span := a.distance_to(b)
			var rocky := (surface.weight_at(a, HexMapGenerator.Terrain.ROCK) + surface.weight_at(b, HexMapGenerator.Terrain.ROCK)) * 0.5
			# The bridge suits its crossing: a couple of logs over a brook, a stone arch where
			# the banks are rock, a braced trestle over a long span, planks on piers otherwise.
			if river_w < 4.5 and span < 10.0:
				var ym := maxf((ya + yb) * 0.5, water + 0.5)
				_add_log_bridge(bridges, a, b, ya, ym, yb, wood, surface)
			elif rocky > 0.35 and span < 26.0:
				var ym := maxf((ya + yb) * 0.5 + span * 0.06, water + 1.6)
				_add_stone_bridge(bridges, a, b, ya, ym, yb, width * 0.95, water, surface)
			else:
				var ym := maxf((ya + yb) * 0.5, water + 1.0)
				_add_bridge(bridges, a, b, ya, ym, yb, width * 0.9, wood, surface, span > 16.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if not verts.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Trails"
		mi.mesh = mesh
		mi.material_override = _trail_material()
		_trail_material().set_shader_parameter("trail_width", width)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	if not bridges.verts.is_empty():
		var bm := MeshInstance3D.new()
		bm.name = "Bridges"
		bm.mesh = bridges.to_mesh()
		bm.material_override = ResourceProps._material("body")
		parent.add_child(bm)


## What each trail point runs over, smoothed along the trail (~20 m) so its surface changes
## gradually: [Color(sand, rock, bog, forest), Vector2(snow, moisture)].
static func _ground_kinds(pts: PackedVector2Array, surface: TerrainSurface) -> Array:
	const T := HexMapGenerator.Terrain
	var raw: Array = []
	for p in pts:
		var acc := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for o in [Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			var q: Vector2 = p + o
			acc[0] += surface.weight_at(q, T.SAND)
			acc[1] += surface.weight_at(q, T.ROCK)
			acc[2] += surface.wetland_at(q)
			acc[3] += surface.weight_at(q, T.FOREST)
			acc[4] += surface.weight_at(q, T.SNOW)
			acc[5] += surface.moisture_at(q)
		raw.append(acc)
	var out: Array = []
	var n := pts.size()
	for k in n:
		var s := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var cnt := 0
		for j in range(maxi(k - 5, 0), mini(k + 6, n)):
			for c in 6:
				s[c] += raw[j][c] / 5.0
			cnt += 1
		for c in 6:
			s[c] /= cnt
		out.append([Color(s[0], s[1], s[2], s[3]), Vector2(s[4], s[5])])
	return out


## [water level, width] of the river nearest p ([-INF, 0] if none is close).
static func _river_under(p: Vector2, rivers: Array) -> Array:
	var best := 900.0
	var out := [-INF, 0.0]
	for path: RiverPath in rivers:
		for k in path.points.size():
			var q := path.points[k]
			var d := Vector2(q.x, q.z).distance_squared_to(p)
			if d < best:
				best = d
				out = [q.y, path.widths[k]]
	return out


## Water level of the river nearest p (or -INF if none is close).
static func _water_under(p: Vector2, rivers: Array) -> float:
	var best := 900.0
	var y := -INF
	for path: RiverPath in rivers:
		for q in path.points:
			var d := Vector2(q.x, q.z).distance_squared_to(p)
			if d < best:
				best = d
				y = q.y
	return y


## A plank bridge from a to b: deck height runs a -> middle -> b (each end on its bank, the
## middle clear of the water), planks across, rails on posts, and piers down to the ground or
## river bed wherever the deck stands above it.
static func _add_bridge(data: MeshData, a: Vector2, b: Vector2, ya: float, ym: float, yb: float, w: float, col: Color, surface: TerrainSurface, trestle := false) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var deck := func(t: float) -> float:
		return lerpf(ya, ym, smoothstep(0.0, 0.5, t) if t < 0.5 else 1.0) if t < 0.5 else lerpf(ym, yb, smoothstep(0.5, 1.0, t))
	# Planks.
	var planks := maxi(2, int(length / 0.5))
	for q in planks:
		var t := (q + 0.5) / planks
		var c := a + dir * t * length
		var shade := 0.85 + 0.3 * float(q % 3) / 2.0
		_box(data, Vector3(c.x, deck.call(t), c.y), dir, side, length / planks * 0.9, w, 0.14, col * shade)
	# Posts, rails and piers.
	var posts := maxi(2, int(length / 2.5) + 1)
	for s: float in [-1.0, 1.0]:
		for q in posts:
			var t := float(q) / (posts - 1)
			var pp: Vector2 = a + dir * t * length + side * s * w * 0.5
			var y := float(deck.call(t))
			_box(data, Vector3(pp.x, y + 0.45, pp.y), dir, side, 0.18, 0.18, 0.9, col * 0.8)
			var ground := surface.sample(pp)
			if y - ground > 0.3:
				_box(data, Vector3(pp.x, (y + ground) * 0.5 - 0.3, pp.y), dir, side, 0.3, 0.3, y - ground + 0.6, col * 0.7)
				# A trestle: every other pier tied to its partner across the deck by a
				# cross-beam under the deck and two diagonal braces down to the bed.
				if trestle and s > 0.0 and q % 2 == 0 and y - ground > 1.0:
					var other: Vector2 = pp - side * w
					var g2 := surface.sample(other)
					var low := maxf(ground, g2) + 0.4
					var top := y - 0.35
					_log(data, Vector3(pp.x, top, pp.y), Vector3(other.x, top, other.y), 0.12, col * 0.65)
					_log(data, Vector3(pp.x, top, pp.y), Vector3(other.x, low, other.y), 0.09, col * 0.6)
					_log(data, Vector3(other.x, top, other.y), Vector3(pp.x, low, pp.y), 0.09, col * 0.6)
			if q < posts - 1:
				var t2 := float(q + 1) / (posts - 1)
				var mid: Vector2 = a + dir * (t + t2) * 0.5 * length + side * s * w * 0.5
				var ry := (float(deck.call(t)) + float(deck.call(t2))) * 0.5 + 0.85
				_box(data, Vector3(mid.x, ry, mid.y), dir, side, length / (posts - 1) + 0.1, 0.12, 0.12, col * 0.9)


## A footbridge over a brook: three logs laid side by side from bank to bank (round in
## section), with one rail on posts along one side.
static func _add_log_bridge(data: MeshData, a: Vector2, b: Vector2, ya: float, ym: float, yb: float, col: Color, surface: TerrainSurface) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	# The logs run a little onto each bank.
	var a2 := a - dir * 0.6
	var b2 := b + dir * 0.6
	var m := (a + b) * 0.5
	for i in 3:
		var o := side * (float(i) - 1.0) * 0.42
		var r := 0.2 + 0.03 * float((i * 7) % 3)
		var shade := 0.8 + 0.12 * i
		_log(data, Vector3(a2.x + o.x, ya + r - 0.1, a2.y + o.y), Vector3(m.x + o.x, ym + r - 0.1, m.y + o.y), r, col * shade)
		_log(data, Vector3(m.x + o.x, ym + r - 0.1, m.y + o.y), Vector3(b2.x + o.x, yb + r - 0.1, b2.y + o.y), r, col * shade)
	# A hand rail on one side.
	var rs := side * 0.75
	var posts := maxi(2, int(length / 2.5) + 1)
	for q in posts:
		var t := float(q) / (posts - 1)
		var pp := a + dir * t * length + rs
		var y := lerpf(ya, ym, t * 2.0) if t < 0.5 else lerpf(ym, yb, t * 2.0 - 1.0)
		_box(data, Vector3(pp.x, y + 0.75, pp.y), dir, side, 0.14, 0.14, 1.0, col * 0.75)
	var ra := a + rs
	var rb := b + rs
	var rm := m + rs
	_log(data, Vector3(ra.x, ya + 1.2, ra.y), Vector3(rm.x, ym + 1.2, rm.y), 0.07, col * 0.85)
	_log(data, Vector3(rm.x, ym + 1.2, rm.y), Vector3(rb.x, yb + 1.2, rb.y), 0.07, col * 0.85)


## A stone arch bridge (where the banks are rock): a smooth humped deck on a single arch
## springing from each bank - spandrel walls down to the curve of the arch, its underside
## (the soffit) across, a parapet along each side, and a footing on each bank.
static func _add_stone_bridge(data: MeshData, a: Vector2, b: Vector2, ya: float, ym: float, yb: float, w: float, water: float, surface: TerrainSurface) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var stone := Color(0.52, 0.5, 0.47)
	var segs := maxi(12, int(length / 0.5))
	var spring := maxf(water - 0.2, minf(ya, yb) - 2.0)
	var hw := w * 0.5
	var pw := 0.32   # parapet thickness
	var ph := 0.7    # parapet height
	var prev: Array = []
	for q in segs + 1:
		var t := float(q) / segs
		var c := a + dir * t * length
		var deck := lerpf(ya, yb, t) + (ym - lerpf(ya, yb, 0.5)) * sin(PI * t)
		var soffit := spring + (deck - 0.7 - spring) * pow(sin(PI * t), 0.6)
		# Over the banks the walls run down into the ground.
		var ground := minf(surface.sample(c + side * hw), surface.sample(c - side * hw))
		if ground > soffit - 0.3:
			soffit = ground - 0.4
		var l := c + side * (hw + pw)
		var li := c + side * hw
		var ri := c - side * hw
		var rr := c - side * (hw + pw)
		var row := [
			Vector3(l.x, soffit, l.y), Vector3(l.x, deck + ph, l.y), Vector3(li.x, deck + ph, li.y), Vector3(li.x, deck, li.y),
			Vector3(ri.x, deck, ri.y), Vector3(ri.x, deck + ph, ri.y), Vector3(rr.x, deck + ph, rr.y), Vector3(rr.x, soffit, rr.y),
		]
		if not prev.is_empty():
			# Courses of stone: each band a slightly different shade.
			var shade := 0.86 + 0.2 * fposmod(float(q) * 0.618, 1.0)
			var col := stone * shade
			var up := Vector3.UP
			var out_l := Vector3(side.x, 0, side.y)
			var fwd := Vector3(dir.x, 0, dir.y)
			_quad(data, prev[0], row[0], row[1], prev[1], out_l, col)            # outer wall, left
			_quad(data, prev[1], row[1], row[2], prev[2], up, col * 1.05)        # parapet top
			_quad(data, prev[2], row[2], row[3], prev[3], -out_l, col * 0.9)     # parapet inner face
			_quad(data, prev[3], row[3], row[4], prev[4], up, col * 0.95)        # deck
			_quad(data, prev[4], row[4], row[5], prev[5], out_l, col * 0.9)      # parapet inner face
			_quad(data, prev[5], row[5], row[6], prev[6], up, col * 1.05)        # parapet top
			_quad(data, prev[6], row[6], row[7], prev[7], -out_l, col)           # outer wall, right
			_quad(data, prev[7], row[7], row[0], prev[0], -up, col * 0.7)        # arch underside
		else:
			_quad(data, row[0], row[1], row[6], row[7], -Vector3(dir.x, 0, dir.y), stone * 0.9)
		prev = row
	_quad(data, prev[0], prev[1], prev[6], prev[7], Vector3(dir.x, 0, dir.y), stone * 0.9)
	# Footings on the banks.
	for e: Vector2 in [a, b]:
		var y := ya if e == a else yb
		_box(data, Vector3(e.x, y - 0.7, e.y), dir, side, 1.6, w + 1.2, 1.6, stone * 0.8)


## Two triangles p0-p1-p2-p3, wound to face along n (Godot: clockwise from the front).
static func _quad(data: MeshData, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col: Color) -> void:
	_tri(data, p0, p1, p2, n, col)
	_tri(data, p0, p2, p3, n, col)


static func _tri(data: MeshData, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).dot(n) < 0.0:
		data.tri(p0, p1, p2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, n, Vector2.ZERO, col)
	else:
		data.tri(p0, p2, p1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, n, Vector2.ZERO, col)


## A round log from p to q (an eight-sided prism) of radius r.
static func _log(data: MeshData, p: Vector3, q: Vector3, r: float, col: Color) -> void:
	var ax := q - p
	var length := ax.length()
	if length < 0.01:
		return
	var f := ax / length
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	var u := f.cross(up).normalized()
	var v := u.cross(f).normalized()
	const SIDES := 8
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var o0 := (u * cos(a0) + v * sin(a0)) * r
		var o1 := (u * cos(a1) + v * sin(a1)) * r
		var nrm := (u * cos((a0 + a1) * 0.5) + v * sin((a0 + a1) * 0.5)).normalized()
		var shade := 0.85 + 0.15 * nrm.y
		_tri(data, p + o0, q + o0, q + o1, nrm, col * shade)
		_tri(data, p + o0, q + o1, p + o1, nrm, col * shade)
		# End grain, paler.
		_tri(data, p, p + o1, p + o0, -f, col * 1.35)
		_tri(data, q, q + o0, q + o1, f, col * 1.35)


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
