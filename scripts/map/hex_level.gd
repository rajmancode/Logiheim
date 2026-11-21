class_name HexLevel
extends RefCounted
## One hex grid (one scale / level of detail). Cell data is stored in parallel arrays by index.

var level_index := 0
var hex_size := 20.0
var step_height := 6.0
## World position (x, z) of axial (0, 0).
var origin := Vector2.ZERO
var cols := 0
var rows := 0

var coords: Array[Vector2i] = []
## axial Vector2i -> cell index
var index: Dictionary = {}

var height := PackedFloat32Array()      ## mean normalised height
var slope := PackedFloat32Array()       ## rise/run estimate
var terrain := PackedByteArray()        ## HexMapGenerator.Terrain
var elevation := PackedInt32Array()     ## stepped elevation, in steps
var parent := PackedInt32Array()        ## cell index in the next coarser level, -1 if none
var children: Array = []                ## Array[int] cell indices in the next finer level

## Drainage and rivers (filled by RiverNetwork).
var downstream := PackedInt32Array()    ## neighbour this cell drains into, -1 = sea / off the map
var flow := PackedFloat32Array()        ## land area draining through this cell, m^2
var river := PackedByteArray()          ## 1 if a river runs through this cell
var river_width := PackedFloat32Array() ## metres
var lake := PackedByteArray()           ## 1 if the hex centre is under a lake
var floodplain := PackedByteArray()     ## 1 if the hex is on a river floodplain (floods in rain)
var resource := PackedByteArray()       ## NaturalResources.Kind (0 = none)
var resource_amount := PackedByteArray() ## 1 small .. 3 rich
var resource2 := PackedByteArray()      ## companion resource sharing the hex (0 = none)
var road := PackedByteArray()          ## 1 if a trail runs through this cell
var cave := PackedInt32Array()         ## cave system with an entrance in this cell, -1 if none
var deposit := PackedInt32Array()       ## index into `deposits`, -1 if none
## Resource deposits on this level: {kind, center (cell index), size (finest hexes)}.
var deposits: Array = []

var min_elevation := 0
var max_elevation := 0


func allocate() -> void:
	var n := coords.size()
	height.resize(n)
	slope.resize(n)
	terrain.resize(n)
	elevation.resize(n)
	parent.resize(n)
	parent.fill(-1)
	children.resize(n)
	downstream.resize(n)
	downstream.fill(-1)
	flow.resize(n)
	river.resize(n)
	river_width.resize(n)
	lake.resize(n)
	floodplain.resize(n)
	resource.resize(n)
	resource_amount.resize(n)
	deposit.resize(n)
	deposit.fill(-1)
	road.resize(n)
	cave.resize(n)
	cave.fill(-1)
	resource2.resize(n)
	for i in n:
		children[i] = []


## Relative cost for a unit to enter cell i (1 = open ground). Trails halve it; rough,
## steep, snowy and wet ground costs more; water can't be entered on foot.
func move_cost(i: int) -> float:
	var T := HexMapGenerator.Terrain
	var t := terrain[i]
	if HexMapGenerator.is_water(t) or lake[i] == 1:
		return INF
	var c := 1.0
	match t:
		T.FOREST:
			c = 1.5
		T.ROCK:
			c = 2.0
		T.SNOW:
			c = 2.5
	if river[i] == 1:
		c += 1.0
	c *= 1.0 + clampf(slope[i], 0.0, 2.0)
	if road.size() == terrain.size() and road[i] == 1:
		c = minf(c, 1.0) * 0.5
	return c


func cell_count() -> int:
	return coords.size()


func index_of(a: Vector2i) -> int:
	return index.get(a, -1)


func cell_center(i: int) -> Vector2:
	return origin + HexCoords.axial_to_world(coords[i], hex_size)


func top_y(i: int) -> float:
	return elevation[i] * step_height


func base_y() -> float:
	return (min_elevation - 3) * step_height


func max_top_y() -> float:
	return max_elevation * step_height


## Exact cell containing world point p (x, z), or -1.
func cell_at(p: Vector2) -> int:
	return index_of(HexCoords.world_to_axial(p - origin, hex_size))


## Cell containing p, or the nearest cell if p is just outside the grid.
func nearest_cell(p: Vector2) -> int:
	var a := HexCoords.world_to_axial(p - origin, hex_size)
	if index.has(a):
		return index[a]
	var best := -1
	var best_d := INF
	for dq in range(-2, 3):
		for dr in range(-2, 3):
			var i := index_of(a + Vector2i(dq, dr))
			if i < 0:
				continue
			var d := cell_center(i).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best


func update_elevation_range() -> void:
	if elevation.is_empty():
		return
	min_elevation = elevation[0]
	max_elevation = elevation[0]
	for e in elevation:
		min_elevation = mini(min_elevation, e)
		max_elevation = maxi(max_elevation, e)
