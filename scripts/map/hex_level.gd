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
	for i in n:
		children[i] = []


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
