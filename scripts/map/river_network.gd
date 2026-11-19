class_name RiverNetwork
extends RefCounted
## Works out where water flows on one hex level and which hexes carry a river.
##
## 1. Drainage: a priority flood starts from the sea and the map edge and grows uphill, so
##    every land hex drains to exactly one neighbour. Pits spill over their lowest rim instead
##    of trapping water, so every river reaches the sea or the map edge.
## 2. Flow: each land hex adds its own area and passes the total downstream.
## 3. Rivers: hexes whose catchment is large enough, plus hexes under an optional Gaea "river"
##    mask, become river; every hex below a river hex is river too, all the way to the sea.


static func build(level: HexLevel, source: TerrainSource, settings: HexMapSettings) -> void:
	var n := level.cell_count()
	level.downstream.fill(-1)
	level.flow.fill(0.0)
	level.river.fill(0)
	level.river_width.fill(0.0)
	level.river_order = PackedInt32Array()

	var cell_area := 2.598076 * level.hex_size * level.hex_size
	var visited := PackedByteArray()
	visited.resize(n)
	var fill := PackedFloat64Array()
	fill.resize(n)
	var heap := MinHeap.new()
	var land_area := 0.0
	for i in n:
		fill[i] = level.height[i]
		var water := HexMapGenerator.is_water(level.terrain[i])
		if not water:
			land_area += cell_area
		if water or _on_border(level, i):
			visited[i] = 1
			heap.push(fill[i], i)

	# Pop order runs downstream -> upstream.
	var order := PackedInt32Array()
	while not heap.is_empty():
		var i := heap.pop()
		order.append(i)
		for k in 6:
			var j := level.index_of(HexCoords.neighbor(level.coords[i], k))
			if j < 0 or visited[j] == 1:
				continue
			visited[j] = 1
			fill[j] = maxf(fill[j], fill[i] + 1e-7)
			level.downstream[j] = i
			heap.push(fill[j], j)

	if land_area <= 0.0:
		return
	var threshold := maxf(settings.river_catchment * land_area, cell_area * 2.5)
	var mask_rivers := source.masks.has("river")

	# Upstream first: accumulate flow and mark river sources.
	for idx in range(order.size() - 1, -1, -1):
		var i := order[idx]
		if HexMapGenerator.is_water(level.terrain[i]):
			continue
		level.flow[i] += cell_area
		var d := level.downstream[i]
		if d >= 0 and not HexMapGenerator.is_water(level.terrain[d]):
			level.flow[d] += level.flow[i]
		if level.flow[i] >= threshold or (mask_rivers and _mask_value(level, source, i) > settings.mask_threshold):
			level.river[i] = 1

	# A river never stops: carry it down to the sea or the map edge.
	for idx in range(order.size() - 1, -1, -1):
		var i := order[idx]
		if level.river[i] == 0:
			continue
		level.river_order.append(i)
		var d := level.downstream[i]
		if d >= 0 and not HexMapGenerator.is_water(level.terrain[d]):
			level.river[d] = 1
		var grow := log(maxf(level.flow[i] / threshold, 1.0)) / log(2.0)
		var w := settings.river_width * (1.0 + 0.35 * grow)
		level.river_width[i] = level.hex_size * clampf(w, settings.river_width, settings.river_max_width)


static func _on_border(level: HexLevel, i: int) -> bool:
	for k in 6:
		if level.index_of(HexCoords.neighbor(level.coords[i], k)) < 0:
			return true
	return false


static func _mask_value(level: HexLevel, source: TerrainSource, i: int) -> float:
	var c := level.cell_center(i)
	var total := source.sample_mask("river", c)
	for k in 6:
		total += source.sample_mask("river", c + HexCoords.corner(k, level.hex_size) * 0.5)
	return total / 7.0


## Binary min-heap of (key, id) pairs.
class MinHeap:
	var keys := PackedFloat64Array()
	var ids := PackedInt32Array()

	func is_empty() -> bool:
		return ids.is_empty()

	func push(key: float, id: int) -> void:
		keys.append(key)
		ids.append(id)
		var i := ids.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := ids[0]
		var last := ids.size() - 1
		keys[0] = keys[last]
		ids[0] = ids[last]
		keys.resize(last)
		ids.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var d := ids[a]
		ids[a] = ids[b]
		ids[b] = d
