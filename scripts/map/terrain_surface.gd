class_name TerrainSurface
extends RefCounted
## Continuous "soft-stepped" terrain for one hex level, stored as a regular height grid.
##
## Height at a point = smooth blend of the plateaus of nearby hexes (each hex keeps a flat-ish
## top at its stepped elevation, then slopes into its neighbours), plus the real Gaea relief
## inside the hex. Water hexes become a sea floor that deepens offshore. Rivers are carved in.
##
## Also stores 8 terrain blend weights per vertex (one per HexMapGenerator.Terrain layer) that
## the terrain shader mixes with height-based blending.

const LAYERS := 8
const T := HexMapGenerator.Terrain

var level: HexLevel
var spacing := 5.0
var nx := 0
var nz := 0
var sea_y := 0.0
## Grid heights (world y), row-major, vertex (x, z) at world (x * spacing, z * spacing).
var heights := PackedFloat32Array()
## LAYERS weights per vertex.
var weights := PackedFloat32Array()
## 0..1, how close each vertex is to a river or lake (river bed and banks).
var river_mask := PackedFloat32Array()
## 1 where trees would hang over a river or lake (a few metres wider than the water).
var clear_mask := PackedByteArray()
## 0..1 how much each vertex belongs to a floodplain, and the river level it floods from.
var flood_mask := PackedFloat32Array()
var flood_y := PackedFloat32Array()
## 0..1 how good the ground is for farming (flat, low, fertile); drawn as fields and rich soil.
var arable := PackedFloat32Array()
## 0..1 volcanic ground (basalt and ash): the cone of a volcano and its old lava flows.
var volcanic := PackedFloat32Array()
## Plateau height of each hex.
var plateau := PackedFloat32Array()

var _source: TerrainSource
var _settings: HexMapSettings
var _gen: HexMapGenerator
var _meters := 1.0
var _centers := PackedVector2Array()
var _neighbors := PackedInt32Array()


func _init(p_level: HexLevel, source: TerrainSource, settings: HexMapSettings, generator: HexMapGenerator) -> void:
	level = p_level
	_source = source
	_settings = settings
	_gen = generator
	sea_y = generator.sea_y()
	_meters = source.height_range * settings.height_scale
	spacing = level.hex_size / maxf(settings.terrain_resolution, 0.5)
	nx = int(ceil(source.world_size.x / spacing)) + 1
	nz = int(ceil(source.world_size.y / spacing)) + 1
	_cache_cells()
	_compute_plateaus()
	_compute_heights()
	_smooth_heights(_settings.terrain_smoothing)


func index(x: int, z: int) -> int:
	return z * nx + x


## Bilinear height at world (x, z).
func sample(p: Vector2) -> float:
	var fx := clampf(p.x / spacing, 0.0, nx - 1.001)
	var fz := clampf(p.y / spacing, 0.0, nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * nx + x0
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + nx], heights[i + nx + 1], tx)
	return lerpf(a, b, tz)


## Surface normal at world (x, z).
func normal_at(p: Vector2) -> Vector3:
	var e := spacing
	var hx := sample(p + Vector2(e, 0.0)) - sample(p - Vector2(e, 0.0))
	var hz := sample(p + Vector2(0.0, e)) - sample(p - Vector2(0.0, e))
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Blend weight of one terrain layer at the nearest vertex.
func weight_at(p: Vector2, layer: int) -> float:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return weights[(z * nx + x) * LAYERS + layer]


## True where trees and bushes should stay away (near rivers and lakes).
func keep_clear(p: Vector2) -> bool:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return clear_mask[z * nx + x] == 1


func volcanic_at(p: Vector2) -> float:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return volcanic[z * nx + x]


func river_at(p: Vector2) -> float:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return river_mask[z * nx + x]


# --------------------------------------------------------------------------- build

func _cache_cells() -> void:
	var n := level.cell_count()
	_centers.resize(n)
	_neighbors.resize(n * 6)
	for i in n:
		_centers[i] = level.cell_center(i)
		for k in 6:
			_neighbors[i * 6 + k] = level.index_of(HexCoords.neighbor(level.coords[i], k))


func _compute_plateaus() -> void:
	var n := level.cell_count()
	plateau.resize(n)
	# Distance (in hexes) from the nearest land, for water hexes.
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	for i in n:
		if not HexMapGenerator.is_water(level.terrain[i]):
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for k in 6:
			var j := _neighbors[i * 6 + k]
			if j >= 0 and dist[j] < 0:
				dist[j] = dist[i] + 1
				queue.append(j)
	var cell_w := HexCoords.SQRT3 * level.hex_size
	for i in n:
		var t := level.terrain[i]
		if HexMapGenerator.is_water(t):
			var d := float(dist[i] if dist[i] >= 0 else 40) * cell_w
			var depth := minf(_settings.seabed_depth + d * _settings.seabed_slope, 80.0)
			if t == T.DEEP_WATER:
				depth += 6.0
			plateau[i] = sea_y - depth
		else:
			plateau[i] = level.top_y(i)
			# Land hexes almost surrounded by sea become low sand bars and skerries rather
			# than thin, steep ridges sticking out of the water.
			var wet := 0
			for k in 6:
				var j := _neighbors[i * 6 + k]
				if j >= 0 and HexMapGenerator.is_water(level.terrain[j]):
					wet += 1
			if wet >= 4:
				plateau[i] = minf(plateau[i], sea_y + 1.0)
			elif wet == 3:
				plateau[i] = minf(plateau[i], sea_y + 2.5)


func _compute_heights() -> void:
	heights.resize(nx * nz)
	weights.resize(nx * nz * LAYERS)
	weights.fill(0.0)
	river_mask.resize(nx * nz)
	river_mask.fill(0.0)
	clear_mask.resize(nx * nz)
	clear_mask.fill(0)
	flood_mask.resize(nx * nz)
	flood_mask.fill(0.0)
	flood_y.resize(nx * nz)
	flood_y.fill(0.0)
	volcanic.resize(nx * nz)
	volcanic.fill(0.0)
	var radius := _settings.step_softness * level.hex_size
	var inv_r2 := 1.0 / (radius * radius)
	var detail := _settings.terrain_detail * _meters
	var cells := PackedInt32Array()
	cells.resize(7)
	var w := PackedFloat32Array()
	w.resize(7)

	for z in nz:
		for x in nx:
			var p := Vector2(x * spacing, z * spacing)
			var vi := z * nx + x
			var ci := level.nearest_cell(p)
			if ci < 0:
				heights[vi] = sea_y - 30.0
				weights[vi * LAYERS] = 1.0
				continue
			cells[0] = ci
			for k in 6:
				cells[k + 1] = _neighbors[ci * 6 + k]
			var sw := 0.0
			var sh := 0.0
			var sm := 0.0
			var land := 0.0
			for k in 7:
				var j := cells[k]
				w[k] = 0.0
				if j < 0:
					continue
				var d2 := _centers[j].distance_squared_to(p) * inv_r2
				if d2 >= 1.0:
					continue
				var t := 1.0 - d2
				var wk := t * t
				w[k] = wk
				sw += wk
				sh += wk * plateau[j]
				sm += wk * level.height[j]
				if not HexMapGenerator.is_water(level.terrain[j]):
					land += wk
			if sw <= 0.0:
				heights[vi] = plateau[ci]
				weights[vi * LAYERS + level.terrain[ci]] = 1.0
				continue
			var h := sh / sw
			var land_share := land / sw
			# Real relief inside the hex, relative to the hexes' own mean height.
			h += (_smooth_height(p) - sm / sw) * detail * land_share
			if land_share > 0.55:
				h = maxf(h, sea_y + 0.6)
			elif land_share <= 0.0:
				h = minf(h, sea_y - 0.8)
			heights[vi] = h
			var natural := _settings.natural_texturing if land_share > 0.5 else 0.0
			for k in 7:
				if w[k] > 0.0:
					weights[vi * LAYERS + level.terrain[cells[k]]] += w[k] / sw * (1.0 - natural)
			if natural > 0.0:
				weights[vi * LAYERS + _natural_terrain(p)] += natural

	# Let the map edge fall away under the sea instead of ending in a wall.
	for x in nx:
		_sink_edge(x, 0)
		_sink_edge(x, nz - 1)
	for z in nz:
		_sink_edge(0, z)
		_sink_edge(nx - 1, z)


## Rounds off the hex terraces: a few passes of a 3x3 blur over the whole grid. The coastline
## stays put (land never sinks below the sea, sea floor never rises out of it).
func _smooth_heights(passes: int) -> void:
	for it in passes:
		var src := heights.duplicate()
		for z in range(1, nz - 1):
			for x in range(1, nx - 1):
				var i := z * nx + x
				var s := src[i] * 4.0 + (src[i - 1] + src[i + 1] + src[i - nx] + src[i + nx]) * 2.0 \
					+ src[i - nx - 1] + src[i - nx + 1] + src[i + nx - 1] + src[i + nx + 1]
				var h := s / 16.0
				if src[i] > sea_y + 0.6:
					h = maxf(h, sea_y + 0.6)
				elif src[i] < sea_y - 0.8:
					h = minf(h, sea_y - 0.8)
				heights[i] = h


## Heightmap sample with a small blur, so detail finer than the terrain grid doesn't alias
## into spikes.
func _smooth_height(p: Vector2) -> float:
	var r := spacing * 0.75
	return (_source.sample_height(p) * 2.0
		+ _source.sample_height(p + Vector2(r, 0.0)) + _source.sample_height(p - Vector2(r, 0.0))
		+ _source.sample_height(p + Vector2(0.0, r)) + _source.sample_height(p - Vector2(0.0, r))) / 6.0


## Terrain type at a point from the Gaea data itself (masks, height, slope), not the hex.
func _natural_terrain(p: Vector2) -> int:
	var h := _source.sample_height(p)
	var e := spacing
	var sx := _source.sample_height(p + Vector2(e, 0.0)) - _source.sample_height(p - Vector2(e, 0.0))
	var sz := _source.sample_height(p + Vector2(0.0, e)) - _source.sample_height(p - Vector2(0.0, e))
	var slope := sqrt(sx * sx + sz * sz) * _source.height_range / (2.0 * e)
	var m: Dictionary = {}
	for key in _source.masks:
		m[key] = _source.sample_mask(key, p)
	var t := _gen.classify(h, slope, m, _gen.forest_fallback_at(p, h, slope))
	# Snow doesn't stick to steep faces.
	if t == T.SNOW and slope > _settings.cliff_slope * 0.8:
		t = T.ROCK
	# Land never gets a water texture from this; the sea floor is handled in finish_weights().
	return T.SAND if HexMapGenerator.is_water(t) else t


func _sink_edge(x: int, z: int) -> void:
	var i := z * nx + x
	heights[i] = minf(heights[i], sea_y - 12.0)


## Marks lake beds (keeps trees and grass out, gives them muddy banks).
func mark_lakes(hydro: Hydrology) -> void:
	if hydro.lake_level.is_empty():
		return
	for z in nz:
		for x in nx:
			var p := Vector2(x * spacing, z * spacing)
			if hydro.lake_at(p) >= 0:
				# Lake beds sit under water; only a light muddy tint so the coarse lake grid
				# doesn't show as jagged patches along the shore.
				river_mask[z * nx + x] = maxf(river_mask[z * nx + x], 0.5)
				clear_mask[z * nx + x] = 1
			elif hydro.filled_at(p) > heights[z * nx + x] + 0.3:
				clear_mask[z * nx + x] = 1


## Cuts river valleys and channels. Valleys first: around every river the land is brought
## down to a floor just above the water of the nearest stretch of river, with walls rising at
## `valley_slope` to the untouched ground (`valley_reach`). Then the channel itself: the bed
## sits below each path's water surface and blends into the banks; at a waterfall the lip is
## kept (nothing below the fall is carved back past it).
func carve(paths: Array) -> void:
	if paths.is_empty():
		return
	_carve_valleys(paths)
	for path: RiverPath in paths:
		var lips: Array = []
		for f in path.falls:
			if f + 1 < path.points.size():
				var a := path.points[f]
				var b := path.points[f + 1]
				lips.append([f, Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z).normalized()])
		for k in path.points.size():
			var pt := path.points[k]
			var w := path.widths[k]
			var depth := RiverMeshBuilder.depth_for(w)
			var bed := pt.y - depth
			var r := maxf(w * 1.9, w * 0.5 + 6.0)
			# Below a waterfall: don't carve back past its lip.
			var guard: Array = []
			for lip: Array in lips:
				if lip[0] < k and Vector2(pt.x, pt.z).distance_to(lip[1]) < r + 3.0:
					guard = lip
			var x0 := maxi(0, floori((pt.x - r) / spacing))
			var x1 := mini(nx - 1, ceili((pt.x + r) / spacing))
			var z0 := maxi(0, floori((pt.z - r) / spacing))
			var z1 := mini(nz - 1, ceili((pt.z + r) / spacing))
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var d := Vector2(gx * spacing - pt.x, gz * spacing - pt.z).length()
					if d >= r:
						continue
					if not guard.is_empty() and (Vector2(gx * spacing, gz * spacing) - guard[1]).dot(guard[2]) < 0.0:
						continue
					var i := gz * nx + gx
					var prof := 1.0 - smoothstep(w * 0.3, w * 1.5, d)
					if prof > 0.0:
						heights[i] = minf(heights[i], lerpf(heights[i], bed, prof))
					river_mask[i] = maxf(river_mask[i], 1.0 - smoothstep(w * 0.45, w * 1.2, d))
					if d < w * 0.5 + 6.0:
						clear_mask[i] = 1


## Valley walls from a nearest-river field on a coarse grid (two-pass vector chamfer: every
## cell learns which river point is closest, and that point's water level and width).
func _carve_valleys(paths: Array) -> void:
	var slope := _settings.valley_slope
	var reach := _settings.valley_reach
	if slope <= 0.0 or reach <= 0.0:
		return
	var gs := spacing * 2.0
	var gnx := int(ceil((nx - 1) * spacing / gs)) + 1
	var gnz := int(ceil((nz - 1) * spacing / gs)) + 1
	var n := gnx * gnz
	var seed_p := PackedVector2Array()
	seed_p.resize(n)
	var seed_y := PackedFloat32Array()
	seed_y.resize(n)
	var seed_w := PackedFloat32Array()
	seed_w.resize(n)
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	for path: RiverPath in paths:
		for k in path.points.size():
			var pt := path.points[k]
			var p := Vector2(pt.x, pt.z)
			var cx := roundi(p.x / gs)
			var cz := roundi(p.y / gs)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var z := cz + dz
					if x < 0 or z < 0 or x >= gnx or z >= gnz:
						continue
					var c := z * gnx + x
					var d := p.distance_to(Vector2(x * gs, z * gs))
					if d < dist[c]:
						dist[c] = d
						seed_p[c] = p
						seed_y[c] = pt.y
						seed_w[c] = path.widths[k]
	for it in 2:
		var s := -1 if it == 0 else 1
		var zr := range(gnz) if it == 0 else range(gnz - 1, -1, -1)
		var xr := range(gnx) if it == 0 else range(gnx - 1, -1, -1)
		for z: int in zr:
			for x: int in xr:
				var c := z * gnx + x
				var here := Vector2(x * gs, z * gs)
				for o: Vector2i in [Vector2i(s, 0), Vector2i(0, s), Vector2i(s, s), Vector2i(-s, s)]:
					var xx := x + o.x
					var zz := z + o.y
					if xx < 0 or zz < 0 or xx >= gnx or zz >= gnz:
						continue
					var m := zz * gnx + xx
					if dist[m] == INF:
						continue
					var d := here.distance_to(seed_p[m])
					if d < dist[c]:
						dist[c] = d
						seed_p[c] = seed_p[m]
						seed_y[c] = seed_y[m]
						seed_w[c] = seed_w[m]
	var target := PackedFloat32Array()
	target.resize(n)
	for c in n:
		if dist[c] > reach:
			target[c] = 1.0e5
			continue
		var here := Vector2((c % gnx) * gs, (c / gnx) * gs)
		var fw := seed_w[c] * 0.8 + 3.0
		var rag := (BorderNoise.value_noise(here * 0.03 + Vector2(5.5, 2.2)) - 0.5) * 5.0 * smoothstep(fw, fw + 40.0, dist[c])
		target[c] = seed_y[c] + 1.5 + slope * maxf(dist[c] - fw, 0.0) + rag
	# Soften the seams where two rivers' valleys meet.
	for it in 2:
		var src := target.duplicate()
		for z in range(1, gnz - 1):
			for x in range(1, gnx - 1):
				var c := z * gnx + x
				target[c] = minf(src[c], (src[c] * 4.0 + src[c - 1] + src[c + 1] + src[c - gnx] + src[c + gnx]) / 8.0)
	for z in nz:
		for x in nx:
			var fx := clampf(x * spacing / gs, 0.0, gnx - 1.001)
			var fz := clampf(z * spacing / gs, 0.0, gnz - 1.001)
			var x0 := int(fx)
			var z0 := int(fz)
			var tx := fx - x0
			var tz := fz - z0
			var c := z0 * gnx + x0
			var t := lerpf(lerpf(target[c], target[c + 1], tx), lerpf(target[c + gnx], target[c + gnx + 1], tx), tz)
			var i := z * nx + x
			if t < heights[i] and heights[i] > sea_y:
				heights[i] = maxf(t, sea_y + 0.6)


## Final terrain weights: hex terrain blend adjusted for sea floor, beaches, cliffs and banks.
func finish_weights() -> void:
	var cliff := _settings.cliff_slope
	arable.resize(nx * nz)
	arable.fill(0.0)
	var relief := maxf(_meters, 1.0)
	for z in nz:
		for x in nx:
			var vi := z * nx + x
			var base := vi * LAYERS
			var h := heights[vi]
			var xa := maxi(x - 1, 0)
			var xb := mini(x + 1, nx - 1)
			var za := maxi(z - 1, 0)
			var zb := mini(z + 1, nz - 1)
			var gx := (heights[z * nx + xb] - heights[z * nx + xa]) / ((xb - xa) * spacing)
			var gz := (heights[zb * nx + x] - heights[za * nx + x]) / ((zb - za) * spacing)
			var slope := sqrt(gx * gx + gz * gz)

			var under := smoothstep(sea_y + 0.2, sea_y - 1.5, h)
			if under > 0.0:
				var deep := smoothstep(sea_y - 6.0, sea_y - 22.0, h)
				_pull(base, T.SHALLOW_WATER, under * (1.0 - deep))
				_pull(base, T.DEEP_WATER, under * deep)
			else:
				var beach := 1.0 - smoothstep(sea_y + 0.8, sea_y + 3.5, h)
				_pull(base, T.SAND, beach * 0.85)
			var p := Vector2(x * spacing, z * spacing)
			var n1 := BorderNoise.value_noise(p * 0.021 + Vector2(3.1, 7.7))
			var n2 := BorderNoise.value_noise(p * 0.067 + Vector2(1.3, 2.9))
			var flat := 1.0 - smoothstep(0.08, 0.3, slope)
			if under <= 0.0:
				# Dunes: sand drifts a little further inland on low, gentle coasts.
				var dune := (1.0 - smoothstep(sea_y + 2.5, sea_y + 8.0, h)) * flat
				_pull(base, T.SAND, dune * smoothstep(0.45, 0.7, n1) * 0.8)
				# Scree and bare earth on the steeper slopes below the cliffs.
				var scree := smoothstep(cliff * 0.35, cliff * 0.7, slope) * (1.0 - smoothstep(cliff * 0.75, cliff, slope))
				_pull(base, T.DIRT, scree * (0.35 + 0.4 * n2))
				# Worn, dry patches in open grassland.
				var grassy := weights[base + T.GRASS]
				_pull(base, T.DIRT, grassy * smoothstep(0.72, 0.85, n2) * 0.45)
			_pull(base, T.ROCK, smoothstep(cliff * 0.65, cliff * 1.25, slope))
			if under <= 0.0:
				var rel := clampf((h - sea_y) / relief, 0.0, 1.0)
				# Ridges and crests: convex ground sheds its soil and shows bare rock.
				var x2a := maxi(x - 2, 0)
				var x2b := mini(x + 2, nx - 1)
				var z2a := maxi(z - 2, 0)
				var z2b := mini(z + 2, nz - 1)
				var around := (heights[z * nx + x2a] + heights[z * nx + x2b] + heights[z2a * nx + x] + heights[z2b * nx + x]) * 0.25
				var convex := h - around
				_pull(base, T.ROCK, smoothstep(1.2, 3.5, convex) * (0.3 + 0.7 * smoothstep(0.2, 0.55, rel)) * 0.8)
				# High ground: broken, rocky patches between the grass and snow.
				_pull(base, T.ROCK, smoothstep(0.5, 0.8, rel) * smoothstep(0.55, 0.75, n1) * 0.7)
				# Sea cliffs: steep coasts are bare rock down to the water.
				_pull(base, T.ROCK, smoothstep(cliff * 0.35, cliff * 0.7, slope) * (1.0 - smoothstep(sea_y + 4.0, sea_y + 30.0, h)) * 0.85)
				# Outcrops poking through the grass on moderate slopes.
				_pull(base, T.ROCK, smoothstep(0.18, 0.4, slope) * smoothstep(0.8, 0.9, n2) * 0.8)
			# Volcanic ground: bare basalt with ash in the hollows; little grows there.
			var volc := volcanic[vi]
			if volc > 0.0 and under <= 0.0:
				_pull(base, T.ROCK, volc * (0.55 + 0.3 * n2))
				_pull(base, T.DIRT, volc * 0.3 * (1.0 - n2))
			var bank := river_mask[vi]
			var low := 1.0 - smoothstep(sea_y + 6.0, sea_y + relief * 0.25, h)
			if bank > 0.0 and under < 0.5:
				# Muddy banks, and a muddy (not rocky) bed under the water; slow lowland rivers
				# drop sand bars along their edges instead.
				_pull(base, T.DIRT, bank * 0.4 + smoothstep(0.75, 1.0, bank) * 0.5)
				var bar := smoothstep(0.35, 0.8, bank) * (1.0 - smoothstep(0.9, 1.0, bank)) * low * flat
				_pull(base, T.SAND, bar * smoothstep(0.35, 0.6, n2) * 0.7)
			# Floodplains: lush meadow on silt.
			var fm := flood_mask[vi]
			if fm > 0.0 and under < 0.5:
				_pull(base, T.GRASS, fm * 0.6)
				_pull(base, T.DIRT, fm * 0.12)
			# Arable land: flat, low, soft ground (grass or light woodland), best on floodplains.
			if under <= 0.0:
				var soil := weights[base + T.GRASS] + weights[base + T.DIRT] * 0.8 + weights[base + T.FOREST] * 0.3
				var a := flat * smoothstep(sea_y + 1.5, sea_y + 4.0, h) * (1.0 - smoothstep(sea_y + relief * 0.22, sea_y + relief * 0.4, h))
				a *= clampf(soil, 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.6, river_mask[vi]))
				a *= smoothstep(0.35, 0.6, n1 * 0.7 + 0.3 + fm * 0.4)
				arable[vi] = clampf(a + fm * flat * 0.3, 0.0, 1.0)

			var total := 0.0
			for k in LAYERS:
				total += weights[base + k]
			total = maxf(total, 1e-5)
			for k in LAYERS:
				weights[base + k] /= total


## Moves `amount` (0..1) of a vertex's blend towards one layer.
func _pull(base: int, layer: int, amount: float) -> void:
	if amount <= 0.0:
		return
	amount = minf(amount, 1.0)
	for k in LAYERS:
		weights[base + k] *= 1.0 - amount
	weights[base + layer] += amount
