class_name Hydrology
extends RefCounted
## Water flow over a terrain grid: where rain drains to, how much land feeds each point,
## where it pools into lakes, and the river network that comes out of it.
##
## 1. Priority flood (bucket queue, 8 neighbours) from the sea and the map edge, growing
##    uphill. Every cell gets one downstream neighbour; hollows are filled to their spill
##    level instead of trapping water (`filled`).
## 2. Catchment: every land cell adds its area and passes the total downstream.
## 3. Lakes: connected cells where the filled level is clearly above the ground.
## 4. Rivers: cells whose catchment passes a threshold, traced into segments that end at
##    the sea, the map edge or where they join a bigger river.

## Metres between grid cells and grid size.
var spacing := 10.0
var nx := 0
var nz := 0
var sea_y := 0.0
var height := PackedFloat32Array()
## Ground raised to the level water would pool at.
var filled := PackedFloat32Array()
## Downstream cell, -1 at the sea or the map edge.
var parent := PackedInt32Array()
## Land area draining through each cell, m^2.
var area := PackedFloat32Array()
## Lake index per cell, -1 if none.
var lake_id := PackedInt32Array()
## Water surface height of each lake.
var lake_level := PackedFloat32Array()
## Cells in pop order (downstream first).
var order := PackedInt32Array()

const BUCKET := 0.05  ## metres per priority bucket


## Builds the flow from a TerrainSurface, sampling every `stride`-th vertex.
static func from_surface(surface: TerrainSurface, stride: int, settings: HexMapSettings, source: TerrainSource) -> Hydrology:
	var h := Hydrology.new()
	stride = maxi(1, stride)
	h.spacing = surface.spacing * stride
	h.nx = (surface.nx - 1) / stride + 1
	h.nz = (surface.nz - 1) / stride + 1
	h.sea_y = surface.sea_y
	h.height.resize(h.nx * h.nz)
	for z in h.nz:
		for x in h.nx:
			h.height[z * h.nx + x] = surface.heights[(z * stride) * surface.nx + x * stride]
	h._flood()
	h._accumulate(source)
	h._find_lakes(settings)
	return h


func land(c: int) -> bool:
	return height[c] > sea_y


## Bilinear filled height (water level a river would run at) at world (x, z).
func filled_at(p: Vector2) -> float:
	return _bilinear(filled, p)


## Bilinear ground height (before pooling) at world (x, z).
func height_at(p: Vector2) -> float:
	return _bilinear(height, p)


func area_at(p: Vector2) -> float:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return area[z * nx + x]


## Lake index at world (x, z), or -1.
func lake_at(p: Vector2) -> int:
	var x := clampi(roundi(p.x / spacing), 0, nx - 1)
	var z := clampi(roundi(p.y / spacing), 0, nz - 1)
	return lake_id[z * nx + x]


func cell_pos(c: int) -> Vector2:
	return Vector2((c % nx) * spacing, (c / nx) * spacing)


func _bilinear(arr: PackedFloat32Array, p: Vector2) -> float:
	var fx := clampf(p.x / spacing, 0.0, nx - 1.001)
	var fz := clampf(p.y / spacing, 0.0, nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * nx + x0
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + nx], arr[i + nx + 1], tx), tz)


# --------------------------------------------------------------------------- flood

func _flood() -> void:
	var n := nx * nz
	filled = height.duplicate()
	parent.resize(n)
	parent.fill(-1)
	var visited := PackedByteArray()
	visited.resize(n)
	var lo := INF
	var hi := -INF
	for c in n:
		lo = minf(lo, height[c])
		hi = maxf(hi, height[c])
	lo = minf(lo, sea_y)
	var buckets := int((hi - lo) / BUCKET) + 2
	# FIFO queue per bucket as linked lists.
	var head := PackedInt32Array()
	head.resize(buckets)
	head.fill(-1)
	var tail := PackedInt32Array()
	tail.resize(buckets)
	tail.fill(-1)
	var nxt := PackedInt32Array()
	nxt.resize(n)
	nxt.fill(-1)

	for c in n:
		var x := c % nx
		var z := c / nx
		if height[c] <= sea_y or x == 0 or z == 0 or x == nx - 1 or z == nz - 1:
			visited[c] = 1
			if height[c] <= sea_y:
				filled[c] = sea_y
			var b := clampi(int((filled[c] - lo) / BUCKET), 0, buckets - 1)
			if tail[b] >= 0:
				nxt[tail[b]] = c
			else:
				head[b] = c
			tail[b] = c

	var dx := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
	var dz := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])
	order.resize(0)
	var b := 0
	while b < buckets:
		var c := head[b]
		if c < 0:
			b += 1
			continue
		head[b] = nxt[c]
		if head[b] < 0:
			tail[b] = -1
		order.append(c)
		var x := c % nx
		var z := c / nx
		for k in 8:
			var xx := x + dx[k]
			var zz := z + dz[k]
			if xx < 0 or zz < 0 or xx >= nx or zz >= nz:
				continue
			var m := zz * nx + xx
			if visited[m] == 1:
				continue
			visited[m] = 1
			parent[m] = c
			filled[m] = maxf(height[m], filled[c] + 0.001)
			var bm := clampi(int((filled[m] - lo) / BUCKET), b, buckets - 1)
			if tail[bm] >= 0:
				nxt[tail[bm]] = m
			else:
				head[bm] = m
			tail[bm] = m


func _accumulate(source: TerrainSource) -> void:
	var n := nx * nz
	area.resize(n)
	area.fill(0.0)
	var cell := spacing * spacing
	var has_mask := source.masks.has("river")
	for idx in range(order.size() - 1, -1, -1):
		var c := order[idx]
		if not land(c):
			continue
		area[c] += cell
		# A Gaea river mask acts like extra rain, so rivers form where it is painted.
		if has_mask:
			area[c] += cell * 60.0 * source.sample_mask("river", cell_pos(c))
		var p := parent[c]
		if p >= 0:
			area[p] += area[c]


func _find_lakes(settings: HexMapSettings) -> void:
	var n := nx * nz
	lake_id.resize(n)
	lake_id.fill(-1)
	lake_level.resize(0)
	var min_cells := maxi(4, int(settings.lake_min_area / (spacing * spacing)))
	var queue := PackedInt32Array()
	for start in n:
		if lake_id[start] != -1 or not land(start) or filled[start] - height[start] < settings.lake_min_depth:
			continue
		# Flood one basin (4-neighbour) of cells that sit under pooled water.
		var id := lake_level.size()
		queue.resize(0)
		queue.append(start)
		lake_id[start] = id
		var top := filled[start]
		var head := 0
		while head < queue.size():
			var c := queue[head]
			head += 1
			top = maxf(top, filled[c])
			var x := c % nx
			var z := c / nx
			for m in [c - 1 if x > 0 else -1, c + 1 if x < nx - 1 else -1, c - nx if z > 0 else -1, c + nx if z < nz - 1 else -1]:
				if m >= 0 and lake_id[m] == -1 and land(m) and filled[m] - height[m] > 0.15:
					lake_id[m] = id
					queue.append(m)
		if queue.size() < min_cells:
			for c in queue:
				lake_id[c] = -2  # too small: the river just runs through
			continue
		lake_level.append(top)
	for c in n:
		if lake_id[c] == -2:
			lake_id[c] = -1


# --------------------------------------------------------------------------- rivers

## Traces the river network. Each segment is a list of cells from a source (or a junction)
## downstream to the sea, the map edge, or a cell already on a river.
## Returns Array of {cells: PackedInt32Array, to_sea: bool}.
func trace_segments(threshold: float) -> Array:
	var n := nx * nz
	var channel := PackedByteArray()
	channel.resize(n)
	var feeders := PackedInt32Array()
	feeders.resize(n)
	for c in n:
		if land(c) and area[c] >= threshold:
			channel[c] = 1
	for c in n:
		if channel[c] == 1 and parent[c] >= 0 and channel[parent[c]] == 1:
			feeders[parent[c]] += 1
	# Trace from the largest sources first so the main stems come out as long segments.
	var heads: Array = []
	for c in n:
		if channel[c] == 1 and feeders[c] == 0:
			heads.append(c)
	var done := PackedByteArray()
	done.resize(n)
	var segments: Array = []
	for start: int in heads:
		var cells := PackedInt32Array([start])
		done[start] = 1
		var c := start
		var to_sea := false
		while true:
			var p := parent[c]
			if p < 0:
				break
			cells.append(p)
			if not land(p):
				to_sea = true
				break
			if done[p] == 1:
				break
			done[p] = 1
			c = p
		if cells.size() >= 2:
			segments.append({"cells": cells, "to_sea": to_sea})
	return segments
