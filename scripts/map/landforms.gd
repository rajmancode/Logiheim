class_name Landforms
extends RefCounted
## Coastal landforms and oxbow lakes, each only where the map has room for it.
##
## Coast (planned on the finest terrain, before rivers and lakes, then applied to every level as
## a height change):
## - Beaches: gentle coasts are graded into a wide, low sand slope with a shallow sandy shelf
##   offshore (the terrain weights turn the low band into sand).
## - Cliffs: steep coasts are steepened to the waterline with deep water at their foot.
## - Sea stacks: rock pillars standing off the cliffs on a shallow rocky base.
## - Spits: sand ridges growing from a beach along the coast, out into the sea, hooking back.
## - Lagoon: a barrier bar offshore of a beach with a tidal inlet; shallow water behind it.
## - Tombolo: a sand bar tying an islet to the mainland (an islet is raised if none exists).
## - Atoll: a ring reef with low sandy islets and gaps around a shallow lagoon, in open sea.
## Rivers (planned on the finest level after the rivers are placed):
## - Oxbow lakes: crescent lakes beside slow lowland rivers - meanders the river has cut off.

const BEACH := 1
const CLIFF := 2
const OFFS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var nx := 0
var nz := 0
var spacing := 5.0
var sea_y := 0.0
## Height change on the finest grid (added to every level).
var delta := PackedFloat32Array()
## [Vector2 position, radius, top y] per sea stack.
var stacks: Array = []
## {c: Vector2, r, hw, a0, a1, ground} per oxbow lake (crescent around c, from angle a0 to a1).
var oxbows: Array = []
## [name, Vector2 position] of each spit, lagoon, tombolo and atoll (for tests and labels).
var features: Array = []
var counts := {"beach": 0, "cliff": 0, "stack": 0, "spit": 0, "lagoon": 0, "tombolo": 0, "atoll": 0, "oxbow": 0}

var _o := PackedFloat32Array()   # original heights
var _h := PackedFloat32Array()   # reshaped heights
var _rng := RandomNumberGenerator.new()
var _used: Array[Vector2] = []   # feature centres, to keep features apart
var _noff := Vector2.ZERO        # seeded noise offset


## Plans and shapes the coast on the finest surface (call before hydrology). The change is
## kept in `delta` and applied with apply() - also to this surface.
static func plan_coast(surface: TerrainSurface, settings: HexMapSettings) -> Landforms:
	var lf := Landforms.new()
	lf.nx = surface.nx
	lf.nz = surface.nz
	lf.spacing = surface.spacing
	lf.sea_y = surface.sea_y
	lf._rng.seed = MapSeed.mix(7171)
	lf._noff = Vector2(lf._rng.randf() * 500.0, lf._rng.randf() * 500.0)
	lf._o = surface.heights.duplicate()
	lf._h = surface.heights.duplicate()
	if settings.landforms_enabled:
		lf._coast()
	lf.delta.resize(lf._o.size())
	for i in lf._o.size():
		lf.delta[i] = lf._h[i] - lf._o[i]
	lf._h = PackedFloat32Array()
	print("Landforms: %s" % str(lf.counts))
	return lf


## Adds the coast change to a surface (the finest one exactly; coarser ones averaged over
## each vertex's footprint).
func apply(surface: TerrainSurface) -> void:
	if delta.is_empty():
		return
	if surface.nx == nx and surface.nz == nz:
		for i in delta.size():
			surface.heights[i] += delta[i]
		return
	var r := surface.spacing * 0.35
	for z in surface.nz:
		for x in surface.nx:
			var p := Vector2(x, z) * surface.spacing
			var acc := 0.0
			for o: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
				acc += _bilin(delta, p + o)
			surface.heights[z * surface.nx + x] += acc / 5.0


# --------------------------------------------------------------------------- coast

func _coast() -> void:
	var n := nx * nz
	var land := PackedByteArray()
	land.resize(n)
	for i in n:
		land[i] = 1 if _o[i] > sea_y else 0
	var coast := PackedInt32Array()
	for z in range(3, nz - 3):
		for x in range(3, nx - 3):
			var i := z * nx + x
			# (Not along the map's border: there the land is only cut away into the sea, and
			# beaches, cliffs, stacks, spits and lagoons would line the edge of the map.)
			if mini(mini(x, z), mini(nx - 1 - x, nz - 1 - z)) * spacing < TerrainSurface.EDGE_MARGIN + 60.0:
				continue
			if land[i] == 1 and (land[i - 1] == 0 or land[i + 1] == 0 or land[i - nx] == 0 or land[i + nx] == 0):
				coast.append(i)
	if coast.size() < 30:
		return
	var near := _nearest(coast, 320.0)
	# Each coast cell: which way is inland, how fast the land rises, and so what kind of coast.
	var normals := PackedVector2Array()
	var kind := PackedByteArray()
	var beaches: Array[int] = []
	var cliffs: Array[int] = []
	var rises := PackedFloat32Array()
	for ci in coast.size():
		var i := coast[ci]
		var x := i % nx
		var z := i / nx
		var nv := Vector2.ZERO
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var xx := clampi(x + dx, 0, nx - 1)
				var zz := clampi(z + dz, 0, nz - 1)
				nv += Vector2(dx, dz) * (1.0 if land[zz * nx + xx] == 1 else -1.0)
		nv = nv.normalized() if nv.length() > 0.001 else Vector2.RIGHT
		normals.append(nv)
		rises.append(_bilin(_o, Vector2(x, z) * spacing + nv * 30.0) - sea_y)
	# What counts as gentle or steep is relative to this map's own coast: the steepest ~20%
	# (at least 5 m rise in 30 m) can become cliffs, the lower half beaches.
	var sorted := rises.duplicate()
	sorted.sort()
	var low := clampf(sorted[int(sorted.size() * 0.5)], 3.0, 9.0)
	var steep := maxf(sorted[int(sorted.size() * 0.8)], 5.0)
	for ci in coast.size():
		var i := coast[ci]
		var p := Vector2(i % nx, i / nx) * spacing
		var rise := rises[ci]
		var nb := BorderNoise.snoise(p * 0.005 + _noff)
		var k := 0
		if (rise < low and nb > -0.35) or (rise < low * 1.6 and nb > 0.4):
			k = BEACH
			beaches.append(ci)
		elif rise > steep and nb > -0.5:
			k = CLIFF
			cliffs.append(ci)
		kind.append(k)
	counts["beach"] = int(beaches.size() * spacing)
	counts["cliff"] = int(cliffs.size() * spacing)
	# Beaches and cliffs: reshape everything near those coasts.
	for i in n:
		var ci := near[i]
		if ci < 0 or kind[ci] == 0:
			continue
		var c := coast[ci]
		var cp := Vector2(c % nx, c / nx) * spacing
		var p := Vector2(i % nx, i / nx) * spacing
		var d := p.distance_to(cp)
		var h := _h[i]
		if kind[ci] == BEACH:
			if _o[i] > sea_y:
				# A long low sand slope: 0.3 m at the water, rising ~1 in 18.
				_h[i] = lerpf(h, minf(h, sea_y + 0.3 + d * 0.055), 1.0 - smoothstep(40.0, 75.0, d))
			else:
				# A shallow sandy shelf (wide turquoise shallows, gentle surf).
				_h[i] = lerpf(h, maxf(h, sea_y - 0.25 - d * 0.065), 1.0 - smoothstep(50.0, 85.0, d))
		else:
			if _o[i] > sea_y:
				# The cliff face pushed out to the waterline.
				var top := _bilin(_o, cp + normals[ci] * 30.0)
				_h[i] = maxf(h, lerpf(h, top, 1.0 - smoothstep(6.0, 26.0, d)))
			else:
				# Deep water right at the cliff foot.
				_h[i] = lerpf(h, minf(h, sea_y - 3.5 - d * 0.25), 1.0 - smoothstep(10.0, 32.0, d))
	var shaped := _h.duplicate()   # beaches and cliffs; the features below add to this
	_shuffle(beaches)
	_shuffle(cliffs)
	_stacks(coast, normals, cliffs)
	var want_spits := clampi(int(beaches.size() * spacing / 900.0), 0, 2)
	for ci in beaches:
		if counts["spit"] >= want_spits:
			break
		_try_spit(coast[ci], normals[ci])
	for ci in beaches:
		if counts["lagoon"] >= 1 or beaches.size() * spacing < 500.0:
			break
		_try_lagoon(coast[ci], normals[ci])
	_tombolo(land, coast, normals, beaches + cliffs)
	_atoll(near, coast)
	_erode(shaped)


## Sea stacks off the cliffs: about one per 250 m of cliff, at most 7.
func _stacks(coast: PackedInt32Array, normals: PackedVector2Array, cliffs: Array[int]) -> void:
	var want := clampi(int(cliffs.size() * spacing / 250.0), 0, 7)
	var placed: Array[Vector2] = []
	for ci in cliffs:
		if stacks.size() >= want:
			break
		var c := coast[ci]
		var cp := Vector2(c % nx, c / nx) * spacing
		var nv := normals[ci]
		var q := cp - nv * _rng.randf_range(24.0, 50.0)
		if not _inside(q, 40.0) or _close(q, placed, 110.0):
			continue
		var depth := sea_y - _bilin(_h, q)
		if depth < 1.5 or depth > 16.0:
			continue
		var r := _rng.randf_range(4.0, 7.0)
		if _land_near(q, r + 8.0, _o):
			continue
		placed.append(q)
		stacks.append([q, r, sea_y + _rng.randf_range(14.0, 28.0)])
		_raise_disc(q, r + 9.0, sea_y - 1.4)
		# Often a worn stump beside it.
		if _rng.randf() < 0.55:
			var t := Vector2(-nv.y, nv.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var q2 := q + t * _rng.randf_range(14.0, 22.0) - nv * _rng.randf_range(-3.0, 6.0)
			if not _land_near(q2, 6.0, _o):
				stacks.append([q2, r * _rng.randf_range(0.45, 0.65), sea_y + _rng.randf_range(2.5, 8.0)])
				_raise_disc(q2, r * 0.6 + 7.0, sea_y - 1.6)
	counts["stack"] = stacks.size()


## A spit: from a beach along the shore and out to sea, curling landward at its tip.
func _try_spit(c: int, nv: Vector2) -> void:
	var cp := Vector2(c % nx, c / nx) * spacing
	if _close(cp, _used, 350.0):
		return
	var t := Vector2(-nv.y, nv.x)
	for sgn: float in [1.0, -1.0]:
		var dir := (t * sgn * cos(0.4) - nv * sin(0.4)).normalized()
		var hook := signf(dir.cross(nv))
		var length := _rng.randf_range(150.0, 280.0)
		var steps := int(length / 10.0)
		var p := cp
		var pts := PackedVector2Array([p])
		var ok := true
		for s in steps:
			if float(s) / steps > 0.62:
				dir = dir.rotated(hook * 0.12)
			p += dir * 10.0
			if not _inside(p, 40.0):
				ok = false
				break
			var oh := _bilin(_o, p)
			if s >= 3 and (oh > sea_y - 0.5 or sea_y - oh > 14.0):
				ok = false
				break
			if s >= 5 and _land_near(p, 18.0, _h):
				ok = false
				break
			pts.append(p)
		if not ok:
			continue
		_ridge(pts, 14.0, 9.0, sea_y + 1.0, sea_y + 0.6, 7.0, 0.0, 0.9)
		_used.append(pts[pts.size() / 2])
		features.append(["spit", pts[pts.size() / 2]])
		counts["spit"] += 1
		return


## A barrier lagoon: a sand bar bowed out ~100 m off a beach, joined to the shore at both
## ends, with one tidal inlet; the water behind it is made shallow and calm.
func _try_lagoon(c: int, nv: Vector2) -> void:
	var cp := Vector2(c % nx, c / nx) * spacing
	if _close(cp, _used, 450.0):
		return
	var t := Vector2(-nv.y, nv.x)
	var off := _rng.randf_range(90.0, 140.0)
	var length := _rng.randf_range(300.0, 440.0)
	var steps := 24
	var pts := PackedVector2Array()
	for s in steps + 1:
		var u := (float(s) / steps - 0.5) * length
		pts.append(cp + t * u - nv * off * (1.0 - pow(2.0 * u / length, 4.0)))
	# Both ends must reach the shore (walk them on a little if need be).
	for end in 2:
		var k := 0 if end == 0 else pts.size() - 1
		var k2 := 1 if end == 0 else pts.size() - 2
		var step := (pts[k] - pts[k2]).normalized() * 5.0
		var reached := false
		for w in 14:
			if _bilin(_o, pts[k]) > sea_y + 0.2:
				reached = true
				break
			pts[k] += step
		if not reached:
			return
	for s in range(3, steps - 2):
		var oh := _bilin(_o, pts[s])
		if not _inside(pts[s], 40.0) or oh > sea_y - 0.6 or sea_y - oh > 12.0:
			return
	var wet := 0
	var tot := 0
	for su in range(-4, 5):
		for sv in range(1, 5):
			var u := su * length / 10.0
			var q := cp + t * u - nv * off * (1.0 - pow(2.0 * u / length, 4.0)) * sv / 5.0
			tot += 1
			if _bilin(_o, q) < sea_y:
				wet += 1
	if wet < tot * 0.7:
		return
	# The lagoon floor: shallow, calm water behind the bar.
	var lo := cp - Vector2(length, length)
	var hi := cp + Vector2(length, length)
	for z in range(maxi(0, floori(lo.y / spacing)), mini(nz, ceili(hi.y / spacing))):
		for x in range(maxi(0, floori(lo.x / spacing)), mini(nx, ceili(hi.x / spacing))):
			var i := z * nx + x
			if _o[i] >= sea_y:
				continue
			var p := Vector2(x, z) * spacing - cp
			var u := p.dot(t)
			var v := p.dot(-nv)
			if absf(u) >= length * 0.5:
				continue
			var bow := off * (1.0 - pow(2.0 * u / length, 4.0))
			if v > bow or v < -40.0:
				continue
			var w := smoothstep(bow, bow - 14.0, v)
			var floor_y := sea_y - 0.7 - 1.6 * clampf(sin(PI * clampf(v / maxf(bow, 1.0), 0.0, 1.0)), 0.0, 1.0)
			_h[i] = lerpf(_h[i], clampf(_h[i], floor_y - 0.6, floor_y), w)
	var s_in := int(steps * _rng.randf_range(0.25, 0.4))
	if _rng.randf() < 0.5:
		s_in = steps - 2 - s_in
	_ridge(pts.slice(0, s_in + 1), 15.0, 11.0, sea_y + 1.0, sea_y + 0.6, 10.0)
	_ridge(pts.slice(s_in + 2), 11.0, 15.0, sea_y + 0.6, sea_y + 1.0, 10.0)
	_lower_disc((pts[s_in] + pts[s_in + 2]) * 0.5, 14.0, sea_y - 2.2)
	_used.append(cp - nv * off * 0.5)
	features.append(["lagoon", cp - nv * off * 0.5])
	counts["lagoon"] += 1


## Tombolo: a sand bar tying an islet to the mainland. Uses a real islet within 280 m of the
## main island if there is one; otherwise raises a small rocky islet off the coast.
func _tombolo(land: PackedByteArray, coast: PackedInt32Array, normals: PackedVector2Array, cands: Array) -> void:
	var n := nx * nz
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var sizes := PackedInt32Array()
	var edge_touch := PackedByteArray()
	var q := PackedInt32Array()
	for s in n:
		if land[s] == 0 or comp[s] >= 0:
			continue
		var id := sizes.size()
		comp[s] = id
		q.resize(0)
		q.append(s)
		var head := 0
		var touch := 0
		while head < q.size():
			var i := q[head]
			head += 1
			var x := i % nx
			var z := i / nx
			if x == 0 or z == 0 or x == nx - 1 or z == nz - 1:
				touch = 1
			for m in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if z > 0 else -1, i + nx if z < nz - 1 else -1]:
				if m >= 0 and land[m] == 1 and comp[m] < 0:
					comp[m] = id
					q.append(m)
		sizes.append(q.size())
		edge_touch.append(touch)
	if sizes.is_empty():
		return
	var main := 0
	for id in sizes.size():
		if sizes[id] > sizes[main]:
			main = id
	var main_coast := PackedInt32Array()
	for i in coast:
		if comp[i] == main:
			main_coast.append(i)
	var near_main := _nearest(main_coast, 290.0)
	var max_cells := int(75000.0 / (spacing * spacing))
	var best_d := INF
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	for i in n:
		var id := comp[i]
		if id < 0 or id == main or sizes[id] > max_cells or sizes[id] < 20 or edge_touch[id] == 1 or near_main[i] < 0:
			continue
		var a := Vector2(i % nx, i / nx) * spacing
		var mc := main_coast[near_main[i]]
		var b := Vector2(mc % nx, mc / nx) * spacing
		var d := a.distance_to(b)
		if d < 40.0 or d > 280.0 or d >= best_d or not _bar_line_ok(a, b):
			continue
		best_d = d
		best_a = a
		best_b = b
	if best_d < INF:
		_ridge(PackedVector2Array([best_a, (best_a + best_b) * 0.5 + (best_b - best_a).orthogonal().normalized() * _rng.randf_range(-18.0, 18.0), best_b]), 9.0, 9.0, sea_y + 0.7, sea_y + 0.7, 6.0, 1.3)
		_used.append((best_a + best_b) * 0.5)
		features.append(["tombolo", (best_a + best_b) * 0.5])
		counts["tombolo"] += 1
		return
	# No islet: raise one off a headland, then tie it on.
	for ci in cands:
		var c := coast[ci]
		var cp := Vector2(c % nx, c / nx) * spacing
		var nv := normals[ci]
		var isle := cp - nv * _rng.randf_range(130.0, 200.0)
		if not _inside(isle, 70.0) or _close(isle, _used, 350.0) or _land_near(isle, 60.0, _h):
			continue
		var depth := sea_y - _bilin(_o, isle)
		if depth < 2.0 or depth > 14.0 or not _bar_line_ok(isle - (isle - cp).normalized() * 40.0, cp):
			continue
		var r := _rng.randf_range(26.0, 38.0)
		var peak := sea_y + _rng.randf_range(8.0, 15.0)
		_mound(isle, r, peak)
		var mid := (isle + cp) * 0.5 + (cp - isle).orthogonal().normalized() * _rng.randf_range(-25.0, 25.0)
		_ridge(PackedVector2Array([isle, mid, cp]), 9.0, 9.0, sea_y + 0.7, sea_y + 0.7, 6.0, 1.3)
		_used.append(mid)
		features.append(["tombolo", mid])
		counts["tombolo"] += 1
		return


## A ring reef in open water: needs ~R + 150 m of sea all round.
func _atoll(near: PackedInt32Array, coast: PackedInt32Array) -> void:
	var size := minf(nx, nz) * spacing
	var radius := clampf(size * 0.045, 0.0, 110.0)
	if radius < 55.0:
		return
	var cands: Array[Vector2] = []
	var step := maxi(1, int(40.0 / spacing))
	for z in range(0, nz, step):
		for x in range(0, nx, step):
			var i := z * nx + x
			var p := Vector2(x, z) * spacing
			# Well clear of the map edge, where the sea floor shelves away into the open ocean.
			if _o[i] > sea_y - 8.0 or not _inside(p, radius * 2.1 + 260.0) or _close(p, _used, radius + 200.0):
				continue
			if near[i] >= 0:
				var c := coast[near[i]]
				if p.distance_to(Vector2(c % nx, c / nx) * spacing) < radius + 150.0:
					continue
			cands.append(p)
	if cands.is_empty():
		return
	var c := cands[_rng.randi() % cands.size()]
	var g0 := _rng.randf() * TAU
	var gaps := [g0, g0 + PI * _rng.randf_range(0.6, 1.4)]
	# Atolls are rarely round: stretched along one axis, with a lumpy outline.
	var axis := Vector2.from_angle(_rng.randf() * PI)
	var stretch := _rng.randf_range(1.15, 1.5)
	var r_out := radius * 1.35 + 90.0
	var box := r_out * stretch
	for z in range(maxi(0, floori((c.y - box) / spacing)), mini(nz, ceili((c.y + box) / spacing))):
		for x in range(maxi(0, floori((c.x - box) / spacing)), mini(nx, ceili((c.x + box) / spacing))):
			var i := z * nx + x
			var p := Vector2(x, z) * spacing
			# Distance in the atoll's own stretched frame.
			var v := p - c
			var local := Vector2(v.dot(axis) / stretch, v.dot(axis.orthogonal()))
			var d := local.length()
			if d > r_out:
				continue
			var a := local.angle()
			var ring := Vector2(cos(a), sin(a))
			var rr := radius * (0.82 + 0.36 * BorderNoise.snoise(ring * 1.3 + _noff) + 0.12 * (BorderNoise.snoise(ring * 4.7 + _noff * 0.6) - 0.5))
			var hw := 16.0 + 14.0 * BorderNoise.snoise(ring * 2.3 + _noff * 1.3)
			# A reef flat just awash, with sandy islets (motu) here and there, and passes where
			# the sea gets into the lagoon.
			var motu := smoothstep(0.58, 0.8, BorderNoise.snoise(ring * 5.3 + _noff * 0.7))
			var crest := sea_y - 0.5 + motu * (1.4 + 1.2 * BorderNoise.snoise(p * 0.05 + _noff))
			for g: float in gaps:
				crest = lerpf(sea_y - 2.0, crest, smoothstep(0.05, 0.16, absf(angle_difference(a, g))))
			var rd := d - rr
			var uu := rd / maxf(hw * (0.45 + 0.55 * (1.0 - motu * 0.5)), 4.0)
			var target := crest - 1.6 * uu * uu
			if rd > 0.0:
				# The outer reef front drops away steeply into deep water.
				target = maxf(target, sea_y - 1.2 - rd * 0.6)
			else:
				# The lagoon: a few metres deep, with patch reefs.
				var patch := smoothstep(0.7, 0.85, BorderNoise.snoise(p * 0.035 + _noff * 2.1))
				target = maxf(target, sea_y - 4.0 + 1.0 * BorderNoise.snoise(p * 0.03 + _noff) + patch * 2.6)
			_h[i] = maxf(_h[i], target)
	_used.append(c)
	features.append(["atoll", c])
	counts["atoll"] += 1


func _bar_line_ok(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := maxi(2, int(dist / 10.0))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / steps)
		var oh := _bilin(_o, p)
		if sea_y - oh > 13.0:
			return false
	return true


# --------------------------------------------------------------------------- oxbows

## Oxbow lakes: crescents beside slow, wide lowland rivers on flat ground (finest level).
func plan_oxbows(paths: Array[RiverPath], surface: TerrainSurface, hydro: Hydrology, settings: HexMapSettings) -> void:
	if not settings.landforms_enabled:
		return
	var want := clampi(int(minf(surface.nx, surface.nz) * surface.spacing / 700.0), 0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(7272)
	var cands: Array = []
	for path in paths:
		var n := path.points.size()
		if n < 30:
			continue
		for k in range(10, n - 10, 6):
			var q := path.points[k]
			if path.widths[k] < 1.0 or q.y - surface.sea_y > 45.0 or path.turbulence[k] > 0.45:
				continue
			cands.append([path, k, 1.0])
			cands.append([path, k, -1.0])
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var placed: Array[Vector2] = []
	var why := {"close": 0, "edge": 0, "river": 0, "low": 0, "volc": 0, "lake": 0, "relief": 0}
	for cand: Array in cands:
		if oxbows.size() >= want:
			break
		var path: RiverPath = cand[0]
		var k: int = cand[1]
		var q3 := path.points[k]
		var q := Vector2(q3.x, q3.z)
		var a3 := path.points[k + 3] - path.points[k - 3]
		var dir := Vector2(a3.x, a3.z).normalized()
		var np := Vector2(-dir.y, dir.x) * float(cand[2])
		# Sized to the river that cut it: a loop a few river-widths across.
		var w := path.widths[k]
		var r := clampf(w * rng.randf_range(6.0, 9.0), 30.0, 52.0)
		var hw := clampf(w * 1.8, 8.0, 12.0)
		var c := q + np * (path.widths[k] * 0.5 + 14.0 + hw + r * 0.6)
		if _close(c, placed, 260.0):
			why.close += 1
			continue
		var span := deg_to_rad(rng.randf_range(95.0, 120.0))
		var base := np.angle()
		var lo := INF
		var hi := -INF
		var ok := true
		for s in 31:
			var a := base - span + 2.0 * span * s / 30.0
			for off: float in [-hw - 3.0, 0.0, hw + 3.0]:
				var p := c + Vector2.from_angle(a) * (r + off)
				if p.x < 60.0 or p.y < 60.0 or p.x > (surface.nx - 1) * surface.spacing - 60.0 or p.y > (surface.nz - 1) * surface.spacing - 60.0:
					why.edge += 1
					ok = false
					break
				var g := surface.sample(p)
				if surface.river_at(p) > 0.3:
					why.river += 1
				elif g < surface.sea_y + 1.9:
					why.low += 1
				elif surface.volcanic_at(p) > 0.2:
					why.volc += 1
				elif hydro != null and hydro.lake_at(p) >= 0:
					why.lake += 1
				else:
					lo = minf(lo, g)
					hi = maxf(hi, g)
					continue
				ok = false
				break
			if not ok:
				break
		if ok and hi - lo > 8.0:
			why.relief += 1
		if not ok or hi - lo > 8.0:
			continue
		placed.append(c)
		# The bed stays above the sea (the sea surface runs under all the land).
		oxbows.append({"c": c, "r": r, "hw": hw, "a0": base - span, "a1": base + span, "ground": lo,
			"depth": minf(3.2, lo - surface.sea_y - 0.5)})
	counts["oxbow"] = oxbows.size()
	print("Landforms: %d oxbow lakes (%d candidates, rejected %s)" % [oxbows.size(), cands.size(), str(why)])


## Cuts the oxbow beds into a surface (finest two levels; coarser grids are too coarse).
func carve_oxbows(level: HexLevel, surface: TerrainSurface) -> void:
	if surface.spacing > 12.0:
		return
	for ob: Dictionary in oxbows:
		var c: Vector2 = ob.c
		var reach: float = ob.r + ob.hw + 16.0
		var g: float = ob.ground
		var hw: float = ob.hw
		for z in range(maxi(0, floori((c.y - reach) / surface.spacing)), mini(surface.nz, ceili((c.y + reach) / surface.spacing) + 1)):
			for x in range(maxi(0, floori((c.x - reach) / surface.spacing)), mini(surface.nx, ceili((c.x + reach) / surface.spacing) + 1)):
				var i := z * surface.nx + x
				var d := _arc_dist(ob, Vector2(x, z) * surface.spacing)
				if d < hw:
					# Flat-bottomed: deep across most of the width, shelving only at the banks.
					var u := d / hw
					surface.heights[i] = minf(surface.heights[i], g - float(ob.depth) * (1.0 - u * u * u * u))
					surface.river_mask[i] = maxf(surface.river_mask[i], 0.5)
				elif d < hw + 14.0:
					surface.heights[i] = minf(surface.heights[i], g + (d - hw) * 0.3)
				if d < hw + 2.0:
					surface.clear_mask[i] = 1


## Oxbows hold their own still water: keep the floodplain's flood painting off them.
func unflood_oxbows(surface: TerrainSurface) -> void:
	if surface.flood_mask.is_empty():
		return
	for ob: Dictionary in oxbows:
		var c: Vector2 = ob.c
		var reach: float = ob.r + ob.hw + 16.0
		for z in range(maxi(0, floori((c.y - reach) / surface.spacing)), mini(surface.nz, ceili((c.y + reach) / surface.spacing) + 1)):
			for x in range(maxi(0, floori((c.x - reach) / surface.spacing)), mini(surface.nx, ceili((c.x + reach) / surface.spacing) + 1)):
				var d := _arc_dist(ob, Vector2(x, z) * surface.spacing)
				if d < ob.hw + 14.0:
					var i := z * surface.nx + x
					surface.flood_mask[i] *= smoothstep(ob.hw + 4.0, ob.hw + 14.0, d)


## Marks every hex an oxbow runs through as lake (no trails, crops or resources there), and
## drops any pond the water model sees in the carved bed (it would fill to the bank top as a
## sheet of shallow water; the oxbow draws its own).
func mark_oxbows(level: HexLevel, hydro: Hydrology) -> void:
	if hydro != null:
		var drop := {}
		for ob: Dictionary in oxbows:
			for k in 41:
				var a: float = lerpf(ob.a0, ob.a1, k / 40.0)
				var id := hydro.lake_at((ob.c as Vector2) + Vector2.from_angle(a) * float(ob.r))
				if id >= 0:
					drop[id] = true
		if not drop.is_empty():
			for c in hydro.lake_id.size():
				if drop.has(hydro.lake_id[c]):
					hydro.lake_id[c] = -1
	for ob: Dictionary in oxbows:
		var c: Vector2 = ob.c
		var r: float = ob.r
		for k in 41:
			var a: float = lerpf(ob.a0, ob.a1, k / 40.0)
			var ci := level.cell_at(c + Vector2.from_angle(a) * r)
			if ci >= 0:
				level.lake[ci] = 1


## Distance from p to an oxbow's centre line (an arc with rounded ends).
static func _arc_dist(ob: Dictionary, p: Vector2) -> float:
	var c: Vector2 = ob.c
	var a0: float = ob.a0
	var a1: float = ob.a1
	var v := p - c
	var mid := (a0 + a1) * 0.5
	var half := (a1 - a0) * 0.5
	var da := angle_difference(mid, v.angle())
	if absf(da) <= half:
		return absf(v.length() - float(ob.r))
	return p.distance_to(c + Vector2.from_angle(mid + signf(da) * half) * float(ob.r))


# --------------------------------------------------------------------------- meshes

## Oxbow water and sea stacks (finest two levels).
func build_meshes(level_index: int, surface: TerrainSurface, lake_mat: Material, parent: Node3D) -> void:
	if level_index > 1:
		return
	if not oxbows.is_empty():
		var verts := PackedVector3Array()
		var colors := PackedColorArray()
		for ob: Dictionary in oxbows:
			var c: Vector2 = ob.c
			var r: float = ob.r
			var hw: float = ob.hw * 0.95
			var y: float = ob.ground - 0.3
			var e := hw / r
			var a_lo: float = ob.a0 - e
			var a_hi: float = ob.a1 + e
			var segs := 56
			var rows: Array = []
			for s in segs + 1:
				var a := lerpf(a_lo, a_hi, float(s) / segs)
				var over := maxf(maxf(ob.a0 - a, a - ob.a1), 0.0) * r
				var w := hw * sqrt(maxf(0.0, 1.0 - (over / hw) * (over / hw)))
				var dv := Vector2.from_angle(a)
				rows.append([c + dv * (r - w), c + dv * r, c + dv * (r + w)])
			for s in segs:
				var ra: Array = rows[s]
				var rb: Array = rows[s + 1]
				for col in 2:
					var al := 0.0 if col == 0 else 1.0
					var ar := 1.0 if col == 0 else 0.0
					var p00: Vector2 = ra[col]
					var p01: Vector2 = ra[col + 1]
					var p10: Vector2 = rb[col]
					var p11: Vector2 = rb[col + 1]
					# Wound clockwise seen from above (front face), like the lake meshes.
					for t: Array in [[p00, al], [p11, ar], [p10, al], [p00, al], [p01, ar], [p11, ar]]:
						var pp: Vector2 = t[0]
						verts.append(Vector3(pp.x, y, pp.y))
						colors.append(Color(1, 1, 1, t[1]))
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Oxbows"
		mi.mesh = mesh
		mi.material_override = lake_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	if stacks.is_empty():
		return
	# Sea stacks: a tall pillar of stretched boulder, a cap piece to break the outline, and a
	# spill of fallen blocks round the base.
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(7373)
	var items: Dictionary = {}
	for st: Array in stacks:
		var p: Vector2 = st[0]
		var r: float = st[1]
		var top: float = st[2]
		var floor_y := surface.ground_min(p, r)
		var height := top - floor_y + 1.0
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var sy := height / 0.82
		var b := yaw * Basis.from_scale(Vector3(r * 1.7, sy, r * 1.6))
		_put(items, "rock_c", Transform3D(b, Vector3(p.x, floor_y - 1.0 + 0.35 * sy, p.y)))
		if height > 8.0:
			var cb := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r * 1.5, height * 0.4 / 0.53, r * 1.5))
			_put(items, "rock_e", Transform3D(cb, Vector3(p.x + rng.randf_range(-1.5, 1.5), top - height * 0.18, p.y + rng.randf_range(-1.5, 1.5))))
		for k in rng.randi_range(3, 6):
			var a := rng.randf() * TAU
			var bp := p + Vector2.from_angle(a) * (r + rng.randf_range(0.0, 5.0))
			var s := rng.randf_range(1.5, 3.5)
			var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * 0.8, s))
			_put(items, ["rock_a", "rock_b"][k % 2], Transform3D(bb, Vector3(bp.x, surface.ground_min(bp, s * 0.6) - s * 0.1, bp.y)))
	for model: String in items:
		var m := Vegetation.mesh(model)
		if m == null:
			continue
		var list: Array = items[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
			mm.set_instance_custom_data(j, Color(1, 1, 1, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "SeaStacks_" + model
		mmi.multimesh = mm
		parent.add_child(mmi)


static func _put(items: Dictionary, model: String, xf: Transform3D) -> void:
	if not items.has(model):
		items[model] = []
	(items[model] as Array).append(xf)


# --------------------------------------------------------------------------- helpers

## For every cell, the index (into seeds) of a near seed cell within max_d metres, or -1
## (breadth-first spread of the nearest seed: close to the true nearest).
func _nearest(seeds: PackedInt32Array, max_d: float) -> PackedInt32Array:
	var n := nx * nz
	var src := PackedInt32Array()
	src.resize(n)
	src.fill(-1)
	var q := PackedInt32Array()
	for k in seeds.size():
		src[seeds[k]] = k
		q.append(seeds[k])
	var md2 := (max_d / spacing) * (max_d / spacing)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % nx
		var z := i / nx
		var s := seeds[src[i]]
		var sx := s % nx
		var sz := s / nx
		for o in OFFS8:
			var xx := x + o.x
			var zz := z + o.y
			if xx < 0 or zz < 0 or xx >= nx or zz >= nz:
				continue
			var j := zz * nx + xx
			if src[j] != -1:
				continue
			if float((xx - sx) * (xx - sx) + (zz - sz) * (zz - sz)) > md2:
				continue
			src[j] = src[i]
			q.append(j)
	return src


## A sand ridge along a polyline: crest height and half-width taper from start to end,
## rounded in section and at the ends. Natural, not drawn with a ruler: the centre line wanders
## (`wobble` metres), the width swells and pinches and the crest rises into low dunes and dips
## to wash-overs. `flare` widens both ends (a tombolo's salients), `bulb` swells the far tip (a
## spit's recurved head). Only ever raises the ground.
func _ridge(pts: PackedVector2Array, w0: float, w1: float, c0: float, c1: float, wobble := 8.0, flare := 0.0, bulb := 0.0) -> void:
	if pts.size() < 2:
		return
	pts = _wander(pts, wobble)
	var lo := pts[0]
	var hi := pts[0]
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		lo = lo.min(pts[k])
		hi = hi.max(pts[k])
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var total := maxf(cum[cum.size() - 1], 1.0)
	# Big enough that the flank has dropped below any sea floor by the box edge.
	var pad := maxf(w0, w1) * 1.4 * (1.0 + flare + bulb) * 3.8
	for z in range(maxi(0, floori((lo.y - pad) / spacing)), mini(nz, ceili((hi.y + pad) / spacing) + 1)):
		for x in range(maxi(0, floori((lo.x - pad) / spacing)), mini(nx, ceili((hi.x + pad) / spacing) + 1)):
			var p := Vector2(x, z) * spacing
			var best := INF
			var bu := 0.0
			for k in range(pts.size() - 1):
				var a := pts[k]
				var ab := pts[k + 1] - a
				var l2 := maxf(ab.length_squared(), 0.001)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var dd := p.distance_squared_to(a + ab * t)
				if dd < best:
					best = dd
					bu = (cum[k] + sqrt(l2) * t) / total
			var d := sqrt(best)
			var along := bu * total
			var w := lerpf(w0, w1, bu) * (0.6 + 0.8 * BorderNoise.snoise(Vector2(along * 0.018, 3.3) + _noff))
			w *= 1.0 + flare * (1.0 - sin(PI * bu)) + bulb * smoothstep(0.75, 1.0, bu)
			var crest := lerpf(c0, c1, bu) + 0.9 * (BorderNoise.snoise(Vector2(along * 0.025, 7.1) + _noff) - 0.5) \
				+ 0.3 * (BorderNoise.snoise(p * 0.09 + _noff) - 0.5)
			# Section: a low rounded crest with long, gently shelving flanks.
			var u := d / maxf(w, 3.0)
			# (falls below the sea floor well inside the search box, so no edge shows)
			var target := crest - 1.6 * u * u
			var i := z * nx + x
			if target > _h[i]:
				_h[i] = target


## Wear on everything the coast shaping changed, so nothing looks drawn:
## - the change is domain-warped (outlines wobble and crenulate instead of tracing curves),
## - tidal channels and wash-overs (ridged noise) cut through bars, spits, reefs and islets,
##   now and then breaking them into pieces,
## - steep sand faces slump to a natural angle (a few passes of slope erosion),
## - and a little fine roughness.
func _erode(shaped: PackedFloat32Array) -> void:
	var n := nx * nz
	var d := PackedFloat32Array()
	d.resize(n)
	var feat := PackedFloat32Array()
	feat.resize(n)
	var lo := Vector2i(nx, nz)
	var hi := Vector2i(-1, -1)
	for i in n:
		d[i] = _h[i] - _o[i]
		feat[i] = _h[i] - shaped[i]
		if absf(d[i]) > 0.01:
			lo = Vector2i(mini(lo.x, i % nx), mini(lo.y, i / nx))
			hi = Vector2i(maxi(hi.x, i % nx), maxi(hi.y, i / nx))
	if hi.x < 0:
		return
	lo = Vector2i(maxi(lo.x - 4, 1), maxi(lo.y - 4, 1))
	hi = Vector2i(mini(hi.x + 4, nx - 2), mini(hi.y + 4, nz - 2))
	var o1 := _noff + Vector2(13.7, 2.9)
	var o2 := _noff + Vector2(5.3, 17.1)
	# Warp: read the change from a point pushed about by smooth noise (two scales).
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var i := z * nx + x
			var p := Vector2(x, z) * spacing
			var w := Vector2(BorderNoise.snoise(p * 0.012 + o1) - 0.5, BorderNoise.snoise(p * 0.012 + o2) - 0.5) * 22.0 				+ Vector2(BorderNoise.snoise(p * 0.05 + o2) - 0.5, BorderNoise.snoise(p * 0.05 + o1) - 0.5) * 7.0
			var dw := _bilin(d, p + w)
			var fw := _bilin(feat, p + w)
			# Beach and cliff edits are warped gently (they follow the real coast), the built
			# features fully.
			var base := dw - fw
			var keep := d[i] - feat[i]
			_h[i] = _o[i] + lerpf(keep, base, 0.5) + fw
			# Channels and wash-overs, only on what the features raised.
			if fw > 0.3:
				var ch := 1.0 - absf(BorderNoise.snoise(p * 0.022 + o1) * 2.0 - 1.0)
				var ch2 := 1.0 - absf(BorderNoise.snoise(p * 0.06 + o2) * 2.0 - 1.0)
				var cut := pow(ch, 8.0) * 2.6 + pow(ch2, 10.0) * 1.0
				_h[i] -= minf(cut, fw)
			if absf(_h[i] - _o[i]) > 0.05:
				_h[i] += (BorderNoise.snoise(p * 0.18 + o1) - 0.5) * 0.35
	# Slumping: sand and loose rock settle where a face is steeper than ~35 degrees.
	var talus := spacing * 0.7
	for it in 8:
		var src := _h.duplicate()
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := z * nx + x
				# Built sand features only: cliffs stay steep.
				if feat[i] < 0.2:
					continue
				for j: int in [i - 1, i + 1, i - nx, i + nx]:
					var diff := src[i] - src[j]
					if diff > talus:
						var mv := (diff - talus) * 0.2
						_h[i] -= mv
						_h[j] += mv


## The polyline resampled every 5 m with its points pushed sideways by smooth noise (none at
## the ends, so it still meets the shore where it should).
func _wander(pts: PackedVector2Array, amp: float) -> PackedVector2Array:
	if amp <= 0.0 or pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var steps := maxi(1, int(a.distance_to(b) / 5.0))
		for q in range(1, steps + 1):
			out.append(a.lerp(b, float(q) / steps))
	var total := 0.0
	for k in range(1, out.size()):
		total += out[k].distance_to(out[k - 1])
	var res := out.duplicate()
	var along := 0.0
	var salt := Vector2(_rng.randf() * 50.0, _rng.randf() * 50.0)
	for k in range(1, out.size() - 1):
		along += out[k].distance_to(out[k - 1])
		var t := (out[k + 1] - out[k - 1]).normalized()
		var n := Vector2(-t.y, t.x)
		var taper := sin(PI * clampf(along / maxf(total, 1.0), 0.0, 1.0))
		var off := (BorderNoise.snoise(Vector2(along * 0.011, 1.7) + salt) - 0.5) * 2.0 + 0.4 * (BorderNoise.snoise(Vector2(along * 0.04, 5.2) + salt) - 0.5)
		res[k] = out[k] + n * off * amp * taper
	return res


## A rocky islet with a ragged outline: lobes and coves (radius varies with direction), an
## off-centre knoll and uneven slopes, falling to the sea floor.
func _mound(c: Vector2, r: float, peak: float) -> void:
	var reach := r * 3.2
	var top := c + Vector2.from_angle(_rng.randf() * TAU) * r * 0.3
	for z in range(maxi(0, floori((c.y - reach) / spacing)), mini(nz, ceili((c.y + reach) / spacing) + 1)):
		for x in range(maxi(0, floori((c.x - reach) / spacing)), mini(nx, ceili((c.x + reach) / spacing) + 1)):
			var p := Vector2(x, z) * spacing
			var dir := (p - c).normalized() if p != c else Vector2.RIGHT
			var rr := r * 1.6 * (0.7 + 0.55 * BorderNoise.snoise(dir * 1.4 + _noff) + 0.25 * (BorderNoise.snoise(dir * 4.3 + _noff * 1.7) - 0.5))
			var u := p.distance_to(top.lerp(c, clampf(p.distance_to(c) / r, 0.0, 1.0))) / maxf(rr, 4.0)
			var bump := 1.0 + 0.35 * (BorderNoise.snoise(p * 0.06 + _noff) - 0.5)
			var target := sea_y - 2.5 + (peak - sea_y + 2.5) * pow(maxf(1.0 - u, 0.0), 1.25) * bump
			# Beyond its foot the islet's apron keeps falling away, below any sea floor.
			target -= maxf(u - 1.0, 0.0) * 25.0
			var i := z * nx + x
			_h[i] = maxf(_h[i], target)


## Raises the sea floor towards `y` inside radius r (smooth edge), never lowers it.
func _raise_disc(c: Vector2, r: float, y: float) -> void:
	for z in range(maxi(0, floori((c.y - r) / spacing)), mini(nz, ceili((c.y + r) / spacing) + 1)):
		for x in range(maxi(0, floori((c.x - r) / spacing)), mini(nx, ceili((c.x + r) / spacing) + 1)):
			var i := z * nx + x
			var w := 1.0 - smoothstep(r * 0.5, r, (Vector2(x, z) * spacing).distance_to(c))
			_h[i] = maxf(_h[i], lerpf(_h[i], y, w))


## Lowers the ground towards `y` inside radius r (smooth edge), never raises it.
func _lower_disc(c: Vector2, r: float, y: float) -> void:
	for z in range(maxi(0, floori((c.y - r) / spacing)), mini(nz, ceili((c.y + r) / spacing) + 1)):
		for x in range(maxi(0, floori((c.x - r) / spacing)), mini(nx, ceili((c.x + r) / spacing) + 1)):
			var i := z * nx + x
			var w := 1.0 - smoothstep(r * 0.5, r, (Vector2(x, z) * spacing).distance_to(c))
			_h[i] = minf(_h[i], lerpf(_h[i], y, w))


func _land_near(p: Vector2, r: float, arr: PackedFloat32Array) -> bool:
	if _bilin(arr, p) > sea_y - 0.3:
		return true
	for k in 12:
		var a := TAU * k / 12.0
		for f: float in [0.5, 1.0]:
			if _bilin(arr, p + Vector2.from_angle(a) * r * f) > sea_y - 0.3:
				return true
	return false


func _inside(p: Vector2, margin: float) -> bool:
	return p.x > margin and p.y > margin and p.x < (nx - 1) * spacing - margin and p.y < (nz - 1) * spacing - margin


static func _close(p: Vector2, list: Array[Vector2], d: float) -> bool:
	for q in list:
		if q.distance_squared_to(p) < d * d:
			return true
	return false


func _shuffle(a: Array[int]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


func _bilin(arr: PackedFloat32Array, p: Vector2) -> float:
	var fx := clampf(p.x / spacing, 0.0, nx - 1.001)
	var fz := clampf(p.y / spacing, 0.0, nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * nx + x0
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + nx], arr[i + nx + 1], tx), tz)
