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
## 0..1, how close each vertex is to a river (for banks and keeping trees out).
var river_mask := PackedFloat32Array()
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


func _compute_heights() -> void:
	heights.resize(nx * nz)
	weights.resize(nx * nz * LAYERS)
	weights.fill(0.0)
	river_mask.resize(nx * nz)
	river_mask.fill(0.0)
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


## Cuts river channels: the bed sits below each path's water surface and blends into the banks.
func carve(paths: Array) -> void:
	for path: RiverPath in paths:
		for k in path.points.size():
			var pt := path.points[k]
			var w := path.widths[k]
			var depth := clampf(w * 0.35, 0.6, 3.5)
			var bed := pt.y - depth
			var r := w * 1.9
			var x0 := maxi(0, floori((pt.x - r) / spacing))
			var x1 := mini(nx - 1, ceili((pt.x + r) / spacing))
			var z0 := maxi(0, floori((pt.z - r) / spacing))
			var z1 := mini(nz - 1, ceili((pt.z + r) / spacing))
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var d := Vector2(gx * spacing - pt.x, gz * spacing - pt.z).length()
					if d >= r:
						continue
					var i := gz * nx + gx
					var prof := 1.0 - smoothstep(w * 0.3, w * 1.5, d)
					if prof > 0.0:
						heights[i] = minf(heights[i], lerpf(heights[i], bed, prof))
					river_mask[i] = maxf(river_mask[i], 1.0 - smoothstep(w * 0.5, r, d))


## Final terrain weights: hex terrain blend adjusted for sea floor, beaches, cliffs and banks.
func finish_weights() -> void:
	var cliff := _settings.cliff_slope
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
			_pull(base, T.ROCK, smoothstep(cliff * 0.75, cliff * 1.35, slope))
			var bank := river_mask[vi]
			if bank > 0.0 and under < 0.5:
				_pull(base, T.DIRT, bank * 0.75)

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
