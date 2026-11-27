class_name LakeMaker
extends RefCounted
## Adds lakes the terrain doesn't make on its own, then reshapes the ground so they hold water.
##
## Planned once on the finest level's Hydrology grid:
##   - lakes painted with a Gaea "lake" mask (water covers most of the painted area);
##   - procedural lakes: a river valley floor dammed by a natural moraine (lowland lakes),
##     plus a high basin (tarn). The dam height is raised step by step until the lake reaches
##     `lake_target_area`.
## apply() then deepens each basin towards the middle and raises a low dam wherever water
## would spill, on any level's TerrainSurface. The normal lake detection in Hydrology then finds
## them, so rivers flow in and out of them like natural lakes.

const NONE := -1.0e9

var spacing := 10.0
var nx := 0
var nz := 0
## Planned water level per grid cell, NONE outside lakes.
var water := PackedFloat32Array()
## Ground is raised to at least this per cell (dams), NONE elsewhere.
var dam := PackedFloat32Array()
## Distance from the shore inside lakes, metres (for the basin shape).
var shore_dist := PackedFloat32Array()
var lake_count := 0


static func plan(hydro: Hydrology, source: TerrainSource, settings: HexMapSettings) -> LakeMaker:
	var lm := LakeMaker.new()
	lm.spacing = hydro.spacing
	lm.nx = hydro.nx
	lm.nz = hydro.nz
	var n := hydro.nx * hydro.nz
	lm.water.resize(n)
	lm.water.fill(NONE)
	lm.dam.resize(n)
	lm.dam.fill(NONE)
	lm.shore_dist.resize(n)
	if source.masks.has("lake"):
		lm._mask_lakes(hydro, source)
	if settings.lake_count > 0:
		lm._procedural_lakes(hydro, settings)
	lm._shore_distances()
	print("LakeMaker: %d lakes planned" % lm.lake_count)
	return lm


## Deepens lake basins and raises dams on a surface (any level).
func apply(surface: TerrainSurface) -> void:
	if lake_count == 0:
		return
	# The plan grid is coarse (10 m), so its cells would make a stepped, square shoreline.
	# Instead the lake mask is blurred on the plan grid and the shore is where the blurred mask
	# crosses one half: a smooth curve with rounded bays. A gentle noise warp keeps it from
	# looking machine-made.
	var n := nx * nz
	var soft := PackedFloat32Array()
	soft.resize(n)
	var lvl := water.duplicate()
	var sd := shore_dist.duplicate()
	for c in n:
		soft[c] = 1.0 if water[c] > NONE else 0.0
	for it in 4:
		soft = _blur(soft)
		# Water level and shore distance spread outwards so the blurred shore can use them.
		var nl := lvl.duplicate()
		for c in n:
			if lvl[c] > NONE:
				continue
			for m in _neighbors8(c):
				if lvl[m] > NONE and lvl[m] > nl[c]:
					nl[c] = lvl[m]
					sd[c] = 0.0
		lvl = nl
	# Dams become moraines: the crest falls away on both sides at a natural slope instead of
	# ending in a wall (a cone field spread out from every dam cell, two chamfer sweeps).
	var top := _dam_cones(0.55)
	# Only vertices near a planned lake or dam need any work.
	var near := PackedByteArray()
	near.resize(n)
	for c in n:
		if water[c] > NONE or dam[c] > NONE:
			var cx := c % nx
			var cz := c / nx
			for dz in range(-7, 8):
				for dx in range(-7, 8):
					var xx := cx + dx
					var zz := cz + dz
					if xx >= 0 and zz >= 0 and xx < nx and zz < nz:
						near[zz * nx + xx] = 1
	for z in surface.nz:
		for x in surface.nx:
			var p := Vector2(x * surface.spacing, z * surface.spacing)
			var i := z * surface.nx + x
			if near[clampi(roundi(p.y / spacing), 0, nz - 1) * nx + clampi(roundi(p.x / spacing), 0, nx - 1)] == 0:
				continue
			var h := surface.heights[i]
			var warp := Vector2(BorderNoise.snoise(p * 0.012 + Vector2(4.2, 1.1)) - 0.5,
				BorderNoise.snoise(p * 0.012 + Vector2(9.7, 6.3)) - 0.5) * spacing * 1.6
			var q := p + warp
			var lake_w := smoothstep(0.3, 0.7, _bilinear(soft, q))
			var level := _nearest(lvl, q)
			if lake_w > 0.0 and level > NONE:
				var dist := maxf(_bilinear(sd, q), 0.0)
				var bed := level - minf(1.0 + dist * 0.09, 30.0)
				h = minf(h, lerpf(h, bed, lake_w))
			# The dam slope fades out across the shore band (no step where the lake begins).
			h = maxf(h, _bilinear(top, p + warp * 0.3) - smoothstep(0.0, 0.5, lake_w) * 25.0)
			surface.heights[i] = h


## One pass of a 3x3 binomial blur on the plan grid.
func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := src.duplicate()
	for z in range(1, nz - 1):
		for x in range(1, nx - 1):
			var c := z * nx + x
			out[c] = (src[c] * 4.0 + (src[c - 1] + src[c + 1] + src[c - nx] + src[c + nx]) * 2.0
				+ src[c - nx - 1] + src[c - nx + 1] + src[c + nx - 1] + src[c + nx + 1]) / 16.0
	return out


func _nearest(arr: PackedFloat32Array, p: Vector2) -> float:
	return arr[clampi(roundi(p.y / spacing), 0, nz - 1) * nx + clampi(roundi(p.x / spacing), 0, nx - 1)]


## Bilinear plan sample at p: (lake weight, highest water level, shore distance, dam weight).
func _sample(p: Vector2) -> Vector4:
	var fx := clampf(p.x / spacing, 0.0, nx - 1.001)
	var fz := clampf(p.y / spacing, 0.0, nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var lake_w := 0.0
	var level := NONE
	var dist := 0.0
	var dam_w := 0.0
	for k in 4:
		var c := (z0 + (k / 2)) * nx + x0 + (k % 2)
		var w := (tx if k % 2 == 1 else 1.0 - tx) * (tz if k / 2 == 1 else 1.0 - tz)
		if water[c] > NONE:
			lake_w += w
			level = maxf(level, water[c])
			dist += shore_dist[c] * w
		if dam[c] > NONE:
			dam_w += w
	if lake_w > 0.0:
		dist /= lake_w
	return Vector4(lake_w, level, dist, dam_w)


## Height every plan cell would be raised to by the nearest dam: the dam's crest minus
## `slope` per metre of distance from it (NONE far from any dam).
func _dam_cones(slope: float) -> PackedFloat32Array:
	var top := dam.duplicate()
	var d1 := spacing * slope
	var d2 := spacing * 1.4142 * slope
	for it in 2:
		var fwd := it == 0
		var zr := range(nz) if fwd else range(nz - 1, -1, -1)
		var xr := range(nx) if fwd else range(nx - 1, -1, -1)
		var s := -1 if fwd else 1
		for z: int in zr:
			for x: int in xr:
				var c := z * nx + x
				var best := top[c]
				# Neighbours already visited in this sweep.
				if x + s >= 0 and x + s < nx:
					best = maxf(best, top[c + s] - d1)
				if z + s >= 0 and z + s < nz:
					best = maxf(best, top[c + s * nx] - d1)
					if x + s >= 0 and x + s < nx:
						best = maxf(best, top[c + s * nx + s] - d2)
					if x - s >= 0 and x - s < nx:
						best = maxf(best, top[c + s * nx - s] - d2)
				top[c] = best
	return top


func _bilinear(arr: PackedFloat32Array, p: Vector2) -> float:
	var fx := clampf(p.x / spacing, 0.0, nx - 1.001)
	var fz := clampf(p.y / spacing, 0.0, nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * nx + x0
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + nx], arr[i + nx + 1], tx), tz)


# --------------------------------------------------------------------------- mask lakes

func _mask_lakes(hydro: Hydrology, source: TerrainSource) -> void:
	var n := nx * nz
	var seen := PackedByteArray()
	seen.resize(n)
	for start in n:
		if seen[start] == 1 or not hydro.land(start) or source.sample_mask("lake", hydro.cell_pos(start)) < 0.5:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < comp.size():
			var c := comp[head]
			head += 1
			for m in _neighbors4(c):
				if seen[m] == 0 and hydro.land(m) and source.sample_mask("lake", hydro.cell_pos(m)) >= 0.5:
					seen[m] = 1
					comp.append(m)
		if comp.size() < 6:
			continue
		# Water covers ~85% of the painted area; anything higher stays as islands.
		var hs := PackedFloat32Array()
		for c in comp:
			hs.append(hydro.height[c])
		hs.sort()
		var level := hs[int(hs.size() * 0.85)] + 0.5
		_commit(hydro, comp, level)


# --------------------------------------------------------------------------- procedural lakes

func _procedural_lakes(hydro: Hydrology, settings: HexMapSettings) -> void:
	var n := nx * nz
	var cell_area := spacing * spacing
	var land_area := 0.0
	var max_h := hydro.sea_y
	for c in n:
		if hydro.land(c):
			land_area += cell_area
			max_h = maxf(max_h, hydro.height[c])
	var river_area := maxf(settings.river_catchment * land_area, cell_area * 6.0)
	var sea_dist := _distance_from_sea(hydro)

	# Upstream lists (children of each cell in the drainage tree).
	var child_start := PackedInt32Array()
	child_start.resize(n + 1)
	for c in n:
		if hydro.parent[c] >= 0:
			child_start[hydro.parent[c] + 1] += 1
	for c in n:
		child_start[c + 1] += child_start[c]
	var fill := child_start.duplicate()
	var children := PackedInt32Array()
	children.resize(child_start[n])
	for c in n:
		var p := hydro.parent[c]
		if p >= 0:
			children[fill[p]] = c
			fill[p] += 1

	# Candidate dam sites: flat stretches of river valley, away from the sea.
	var lowland: Array = []
	var highland: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(1234)
	for c in n:
		if not hydro.land(c) or hydro.area[c] < river_area * 0.3 or sea_dist[c] < 100.0:
			continue
		if hydro.height[c] < hydro.sea_y + 6.0 or hydro.lake_id[c] >= 0:
			continue
		# Not near the map's border (a lake there would be cut off by the edge of the map).
		if TerrainSource.cut_edge_dist(hydro.cell_pos(c)) < TerrainSurface.EDGE_MARGIN + 80.0:
			continue
		# The flattest river stretches this map has (steep maps get deep mountain lakes).
		var slope := _local_slope(hydro, c, 3)
		if slope > 0.25:
			continue
		var score := 1.0 - slope / 0.25 + rng.randf() * 0.3
		var rel := (hydro.height[c] - hydro.sea_y) / maxf(max_h - hydro.sea_y, 1.0)
		if rel > 0.55:
			highland.append([score, c])
		else:
			lowland.append([score, c])
	lowland.sort_custom(func(a, b): return a[0] > b[0])
	highland.sort_custom(func(a, b): return a[0] > b[0])

	var sites: Array[Vector2] = []
	var want_high := 1 if settings.lake_count >= 2 else 0
	var made_high := _try_sites(hydro, highland, want_high, settings.lake_target_area * 0.5, sites, children, child_start)
	_try_sites(hydro, lowland, settings.lake_count - made_high, settings.lake_target_area, sites, children, child_start)


func _try_sites(hydro: Hydrology, candidates: Array, wanted: int, target: float, sites: Array[Vector2], children: PackedInt32Array, child_start: PackedInt32Array) -> int:
	var made := 0
	var min_gap := maxf(sqrt(target) * 1.6, 250.0)
	var tried := 0
	for cand in candidates:
		if made >= wanted or tried > 60:
			break
		var c: int = cand[1]
		var pos := hydro.cell_pos(c)
		var close := false
		for s in sites:
			if s.distance_to(pos) < min_gap:
				close = true
				break
		if close or water[c] > NONE:
			continue
		tried += 1
		var region := _dam_region(hydro, c, target, children, child_start)
		if region.is_empty():
			continue
		_commit(hydro, region[0], region[1])
		sites.append(pos)
		made += 1
	return made


## Raises an imaginary dam at `site` until the water held behind it reaches `target` m^2.
## Returns [cells, level] or [] if the valley can't hold a lake that big.
func _dam_region(hydro: Hydrology, site: int, target: float, children: PackedInt32Array, child_start: PackedInt32Array) -> Array:
	var cell_area := spacing * spacing
	var radius := sqrt(target) * 1.6 + 150.0
	var origin := hydro.cell_pos(site)
	var best: PackedInt32Array = PackedInt32Array()
	var best_level := 0.0
	# Tall dams come out as broad moraine hills (see apply()), not walls.
	for dam_h in [2.5, 4.0, 6.0, 8.0, 11.0, 15.0, 20.0, 26.0, 32.0]:
		var level: float = hydro.filled[site] + dam_h
		var cells := PackedInt32Array([site])
		var head := 0
		var ok := true
		while head < cells.size():
			var c := cells[head]
			head += 1
			for k in range(child_start[c], child_start[c + 1]):
				var m := children[k]
				if hydro.height[m] >= level:
					continue
				if hydro.cell_pos(m).distance_to(origin) > radius or water[m] > NONE:
					ok = false
					continue
				cells.append(m)
		if not ok and cells.size() * cell_area < target * 0.25:
			break
		best = cells
		best_level = level
		if cells.size() * cell_area >= target:
			break
	if best.size() * cell_area < target * 0.25:
		return []
	return [best, best_level]


# --------------------------------------------------------------------------- helpers

## Marks cells under `level` as lake and puts a dam on every neighbour that would let it spill.
func _commit(hydro: Hydrology, cells: PackedInt32Array, level: float) -> void:
	var inside := {}
	for c in cells:
		if hydro.height[c] < level:
			water[c] = level
			inside[c] = true
	# Two cells thick, so the dam holds at every level's terrain resolution.
	var ring1 := {}
	for c in inside:
		for m in _neighbors8(c):
			if inside.has(m) or not hydro.land(m):
				continue
			ring1[m] = true
			if hydro.height[m] < level + 0.6:
				dam[m] = maxf(dam[m], level + 0.6)
	for c in ring1:
		for m in _neighbors8(c):
			if inside.has(m) or ring1.has(m) or not hydro.land(m):
				continue
			if hydro.height[m] < level + 0.3 and dam[c] > NONE:
				dam[m] = maxf(dam[m], level + 0.3)
	lake_count += 1


func _shore_distances() -> void:
	var n := nx * nz
	shore_dist.fill(0.0)
	var queue := PackedInt32Array()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	for c in n:
		if water[c] <= NONE:
			continue
		for m in _neighbors4(c):
			if water[m] <= NONE:
				dist[c] = 1
				queue.append(c)
				break
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for m in _neighbors4(c):
			if water[m] > NONE and dist[m] < 0:
				dist[m] = dist[c] + 1
				queue.append(m)
	for c in n:
		shore_dist[c] = maxf(dist[c], 0) * spacing


func _distance_from_sea(hydro: Hydrology) -> PackedFloat32Array:
	var n := nx * nz
	var d := PackedFloat32Array()
	d.resize(n)
	d.fill(INF)
	var queue := PackedInt32Array()
	for c in n:
		if not hydro.land(c):
			d[c] = 0.0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for m in _neighbors4(c):
			if d[m] == INF:
				d[m] = d[c] + spacing
				queue.append(m)
	return d


func _local_slope(hydro: Hydrology, c: int, r: int) -> float:
	var x := c % nx
	var z := c / nx
	var xa := maxi(x - r, 0)
	var xb := mini(x + r, nx - 1)
	var za := maxi(z - r, 0)
	var zb := mini(z + r, nz - 1)
	var gx := (hydro.filled[z * nx + xb] - hydro.filled[z * nx + xa]) / (maxi(xb - xa, 1) * spacing)
	var gz := (hydro.filled[zb * nx + x] - hydro.filled[za * nx + x]) / (maxi(zb - za, 1) * spacing)
	return sqrt(gx * gx + gz * gz)


func _neighbors4(c: int) -> PackedInt32Array:
	var x := c % nx
	var z := c / nx
	var out := PackedInt32Array()
	if x > 0:
		out.append(c - 1)
	if x < nx - 1:
		out.append(c + 1)
	if z > 0:
		out.append(c - nx)
	if z < nz - 1:
		out.append(c + nx)
	return out


func _neighbors8(c: int) -> PackedInt32Array:
	var x := c % nx
	var z := c / nx
	var out := PackedInt32Array()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var xx := x + dx
			var zz := z + dz
			if xx >= 0 and zz >= 0 and xx < nx and zz < nz:
				out.append(zz * nx + xx)
	return out
