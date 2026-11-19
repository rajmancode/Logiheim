class_name HexMapGenerator
extends RefCounted
## Builds HexLevels from a TerrainSource.
##   level 0 (finest) is sampled directly from the Gaea heightmap and masks;
##   coarser levels aggregate their finest descendants (majority terrain, mean height),
##   and each level links parent <-> children with the next one.

enum Terrain { DEEP_WATER, SHALLOW_WATER, SAND, GRASS, FOREST, ROCK, SNOW, DIRT }
const TERRAIN_COUNT := 8
const TERRAIN_NAMES := ["Deep water", "Shallow water", "Sand", "Grass", "Forest", "Rock", "Snow", "Dirt"]

var source: TerrainSource
var settings: HexMapSettings
var sea_level := 0.3
var _sea_step := 0
var _meters_per_unit := 1.0


func _init(p_source: TerrainSource, p_settings: HexMapSettings) -> void:
	source = p_source
	settings = p_settings
	sea_level = source.sea_level if source.sea_level >= 0.0 else settings.sea_level
	_meters_per_unit = source.height_range * settings.height_scale
	_sea_step = roundi(sea_level * _meters_per_unit / settings.step_height)


static func is_water(t: int) -> bool:
	return t <= Terrain.SHALLOW_WATER


## Terrain shown on the vertical sides of a hex (the shader adds rock further down).
static func wall_terrain(t: int) -> int:
	match t:
		Terrain.SAND, Terrain.DEEP_WATER, Terrain.SHALLOW_WATER:
			return Terrain.SAND
		Terrain.ROCK, Terrain.SNOW:
			return Terrain.ROCK
		_:
			return Terrain.DIRT


func build_levels() -> Array[HexLevel]:
	var factors := settings.lod_factors.duplicate()
	if factors.is_empty():
		factors.append(1.0)
	factors.sort()

	var levels: Array[HexLevel] = []
	for i in factors.size():
		var level := _make_grid(settings.base_hex_size * factors[i])
		level.level_index = i
		if i == 0:
			for c in level.cell_count():
				_sample_cell(level, c)
		else:
			_aggregate(level, levels[0])
			_link(levels[i - 1], level)
		level.update_elevation_range()
		levels.append(level)
	return levels


func _make_grid(size: float) -> HexLevel:
	var level := HexLevel.new()
	level.hex_size = size
	level.step_height = settings.step_height
	var w := source.world_size.x
	var d := source.world_size.y
	var hex_w := HexCoords.SQRT3 * size
	level.cols = maxi(1, floori(w / hex_w - 0.5))
	level.rows = maxi(1, floori((d - 2.0 * size) / (1.5 * size)) + 1)
	var used_w := hex_w * (level.cols + 0.5)
	var used_d := 2.0 * size + 1.5 * size * (level.rows - 1)
	level.origin = Vector2((w - used_w) * 0.5 + hex_w * 0.5, (d - used_d) * 0.5 + size)
	for row in level.rows:
		for col in level.cols:
			var a := HexCoords.offset_to_axial(Vector2i(col, row))
			level.index[a] = level.coords.size()
			level.coords.append(a)
	level.allocate()
	return level


## Sample the Gaea data at the centre and six inner points of a hex.
func _sample_cell(level: HexLevel, i: int) -> void:
	var c := level.cell_center(i)
	var points: Array[Vector2] = [c]
	for k in 6:
		points.append(c + HexCoords.corner(k, level.hex_size) * 0.6)

	var h_sum := 0.0
	var h_min := INF
	var h_max := -INF
	var mask_sum: Dictionary = {}
	for key in source.masks:
		mask_sum[key] = 0.0
	for p in points:
		var h := source.sample_height(p)
		h_sum += h
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
		for key in source.masks:
			mask_sum[key] += source.sample_mask(key, p)

	var n := float(points.size())
	for key in mask_sum:
		mask_sum[key] /= n
	var h_mean := h_sum / n
	var slope := (h_max - h_min) * source.height_range / (1.2 * level.hex_size)
	var t := classify(h_mean, slope, mask_sum)
	level.height[i] = h_mean
	level.slope[i] = slope
	level.terrain[i] = t
	level.elevation[i] = elevation_for(h_mean, t)


func classify(h: float, slope: float, m: Dictionary) -> int:
	if _flag(m, "water", h < sea_level):
		var deep := _flag(m, "deep_water", h < sea_level - settings.shallow_depth)
		return Terrain.DEEP_WATER if deep else Terrain.SHALLOW_WATER
	if _flag(m, "snow", h > settings.snow_level):
		return Terrain.SNOW
	if _flag(m, "rock", slope > settings.rock_slope):
		return Terrain.ROCK
	if _flag(m, "sand", h < sea_level + settings.beach_height):
		return Terrain.SAND
	if _flag(m, "forest", false):
		return Terrain.FOREST
	if _flag(m, "dirt", false):
		return Terrain.DIRT
	return Terrain.GRASS


## A mask, when present, decides; otherwise the height/slope fallback rule does.
func _flag(m: Dictionary, key: String, fallback: bool) -> bool:
	if m.has(key):
		return float(m[key]) > settings.mask_threshold
	return fallback


func elevation_for(h: float, t: int) -> int:
	if is_water(t):
		return _sea_step
	return maxi(_sea_step + 1, roundi(h * _meters_per_unit / settings.step_height))


## Coarse cells take the majority terrain and mean height of the finest cells inside them.
func _aggregate(level: HexLevel, finest: HexLevel) -> void:
	var n := level.cell_count()
	var count := PackedInt32Array()
	count.resize(n)
	var land_count := PackedInt32Array()
	land_count.resize(n)
	var h_all := PackedFloat32Array()
	h_all.resize(n)
	var h_land := PackedFloat32Array()
	h_land.resize(n)
	var slope_max := PackedFloat32Array()
	slope_max.resize(n)
	var votes := PackedInt32Array()
	votes.resize(n * TERRAIN_COUNT)

	for fi in finest.cell_count():
		var ci := level.nearest_cell(finest.cell_center(fi))
		if ci < 0:
			continue
		var t := finest.terrain[fi]
		count[ci] += 1
		h_all[ci] += finest.height[fi]
		slope_max[ci] = maxf(slope_max[ci], finest.slope[fi])
		votes[ci * TERRAIN_COUNT + t] += 1
		if not is_water(t):
			land_count[ci] += 1
			h_land[ci] += finest.height[fi]

	for ci in n:
		if count[ci] == 0:
			_sample_cell(level, ci)
			continue
		var base := ci * TERRAIN_COUNT
		var t: int = Terrain.GRASS
		var h := h_all[ci] / count[ci]
		if land_count[ci] * 2 < count[ci]:
			t = Terrain.DEEP_WATER if votes[base + Terrain.DEEP_WATER] >= votes[base + Terrain.SHALLOW_WATER] else Terrain.SHALLOW_WATER
		else:
			var best := -1
			for k in range(Terrain.SAND, TERRAIN_COUNT):
				if votes[base + k] > best:
					best = votes[base + k]
					t = k
			h = h_land[ci] / land_count[ci]
		level.height[ci] = h
		level.slope[ci] = slope_max[ci]
		level.terrain[ci] = t
		level.elevation[ci] = elevation_for(h, t)


func _link(fine: HexLevel, coarse: HexLevel) -> void:
	for fi in fine.cell_count():
		var ci := coarse.nearest_cell(fine.cell_center(fi))
		fine.parent[fi] = ci
		if ci >= 0:
			coarse.children[ci].append(fi)
