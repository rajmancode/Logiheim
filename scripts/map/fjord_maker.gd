class_name FjordMaker
extends RefCounted
## Fjords: long, narrow, steep-sided sea inlets.
##
## Planned once on the finest level's Hydrology grid: rivers that reach the sea through high
## ground (banks standing well above the water on both sides) are candidates; the ones with the
## highest banks win, kept apart from each other. Each fjord follows the river's lower course
## inland from the coast (`fjord_length`), widest and deepest at the mouth and narrowing to a
## rounded head. apply() cuts it into any level's TerrainSurface: a U-shaped trough below the
## sea with walls rising steeply to the surrounding land. The sea (one plane over the map)
## floods it, and the river now ends at the fjord head, often in a waterfall.

## Each: {pts: PackedVector2Array (mouth -> head), hw: PackedFloat32Array (half-width),
## bottom: PackedFloat32Array (floor height), along: PackedFloat32Array (0..1)}.
var fjords: Array = []
var sea_y := 0.0
const WALL_SLOPE := 1.6


static func plan(hydro: Hydrology, settings: HexMapSettings) -> FjordMaker:
	var fm := FjordMaker.new()
	fm.sea_y = hydro.sea_y
	if settings.fjord_count <= 0:
		return fm
	var land_area := 0.0
	for c in hydro.nx * hydro.nz:
		if hydro.land(c):
			land_area += hydro.spacing * hydro.spacing
	var threshold := maxf(settings.river_catchment * land_area, hydro.spacing * hydro.spacing * 6.0)
	var cands: Array = []
	for seg: Dictionary in hydro.trace_segments(threshold):
		if not seg.to_sea:
			continue
		var cells: PackedInt32Array = seg.cells
		if cells.size() < 12:
			continue
		# The lower course, mouth first, up to the fjord length (and at most 60% of the river).
		var pts := PackedVector2Array()
		var total := 0.0
		var max_len := minf(settings.fjord_length, cells.size() * hydro.spacing * 0.6)
		for k in range(cells.size() - 1, -1, -1):
			var p := hydro.cell_pos(cells[k])
			if not pts.is_empty():
				total += p.distance_to(pts[pts.size() - 1])
			pts.append(p)
			if total >= max_len:
				break
		if total < 200.0:
			continue
		# How high the land stands on both sides of the lower course.
		var relief := 0.0
		var cnt := 0
		for k in range(1, pts.size() - 1, 3):
			var dir := (pts[k + 1] - pts[k - 1]).normalized()
			var side := Vector2(-dir.y, dir.x)
			for off in [60.0, 110.0]:
				var a := hydro.height_at(pts[k] + side * off) - hydro.sea_y
				var b := hydro.height_at(pts[k] - side * off) - hydro.sea_y
				relief += minf(a, b)
				cnt += 1
		relief /= maxi(cnt, 1)
		if relief < settings.fjord_min_relief:
			continue
		cands.append([relief, pts])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for cand in cands:
		if fm.fjords.size() >= settings.fjord_count:
			break
		var pts: PackedVector2Array = cand[1]
		var close := false
		for f: Dictionary in fm.fjords:
			if f.pts[0].distance_to(pts[0]) < 500.0:
				close = true
		if close:
			continue
		fm.fjords.append(fm._shape(pts, settings, hydro))
	print("FjordMaker: %d fjords" % fm.fjords.size())
	return fm


## Smooths the course into a fjord axis and gives it its width and depth profile.
func _shape(pts: PackedVector2Array, settings: HexMapSettings, hydro: Hydrology) -> Dictionary:
	# Reach out into open water so the fjord opens onto the sea.
	var out_dir := (pts[0] - pts[mini(3, pts.size() - 1)]).normalized()
	var axis := PackedVector2Array([pts[0] + out_dir * 120.0, pts[0] + out_dir * 60.0])
	axis.append_array(pts)
	for it in 12:
		var np := axis.duplicate()
		for k in range(1, axis.size() - 1):
			np[k] = (axis[k - 1] + axis[k] * 2.0 + axis[k + 1]) * 0.25
		axis = np
	# Every second point is plenty (~20 m apart).
	var thin := PackedVector2Array()
	for k in range(0, axis.size(), 2):
		thin.append(axis[k])
	if (axis.size() - 1) % 2 != 0:
		thin.append(axis[axis.size() - 1])
	axis = thin
	var lengths := PackedFloat32Array([0.0])
	for k in range(1, axis.size()):
		lengths.append(lengths[k - 1] + axis[k].distance_to(axis[k - 1]))
	var total := lengths[lengths.size() - 1]
	var hw := PackedFloat32Array()
	var bottom := PackedFloat32Array()
	var along := PackedFloat32Array()
	for k in axis.size():
		var t := clampf((lengths[k] - 120.0) / maxf(total - 120.0, 1.0), 0.0, 1.0)
		var wobble := 0.8 + 0.4 * BorderNoise.snoise(axis[k] * 0.008 + Vector2(2.3, 8.1))
		hw.append(settings.fjord_width * 0.5 * lerpf(1.0, 0.4, t) * wobble)
		bottom.append(sea_y - lerpf(settings.fjord_depth, 2.5, pow(t, 0.8)))
		along.append(t)
	return {"pts": axis, "hw": hw, "bottom": bottom, "along": along}


func count() -> int:
	return fjords.size()


## Cuts the fjords into a surface: U-shaped trough, steep walls up to the land around.
## Each axis segment is stamped into its own neighbourhood (the deepest cut wins).
func apply(surface: TerrainSurface) -> void:
	for f: Dictionary in fjords:
		var axis: PackedVector2Array = f.pts
		var hw: PackedFloat32Array = f.hw
		var bottom: PackedFloat32Array = f.bottom
		var rim := sea_y + 1.5
		for k in axis.size() - 1:
			var a := axis[k]
			var ab := axis[k + 1] - a
			var reach := maxf(hw[k], hw[k + 1]) + 90.0
			var x0 := maxi(0, floori((minf(a.x, a.x + ab.x) - reach) / surface.spacing))
			var x1 := mini(surface.nx - 1, ceili((maxf(a.x, a.x + ab.x) + reach) / surface.spacing))
			var z0 := maxi(0, floori((minf(a.y, a.y + ab.y) - reach) / surface.spacing))
			var z1 := mini(surface.nz - 1, ceili((maxf(a.y, a.y + ab.y) + reach) / surface.spacing))
			var len2 := maxf(ab.length_squared(), 1e-4)
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var p := Vector2(x * surface.spacing, z * surface.spacing)
					var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					var w := lerpf(hw[k], hw[k + 1], t)
					if d > w + 90.0:
						continue
					var floor_y := lerpf(bottom[k], bottom[k + 1], t)
					var target: float
					if d < w:
						target = floor_y + (rim - floor_y) * pow(d / w, 2.5)
					else:
						# Walls: steep, a little ragged.
						target = rim + (d - w) * WALL_SLOPE + (BorderNoise.snoise(p * 0.05) - 0.5) * 6.0
					var i := z * surface.nx + x
					if target < surface.heights[i]:
						surface.heights[i] = target


## Marks hexes whose centre now lies in a fjord as water, so nothing grows or settles there.
func mark_level(level: HexLevel, surface: TerrainSurface) -> void:
	if fjords.is_empty():
		return
	for i in level.cell_count():
		if not HexMapGenerator.is_water(level.terrain[i]) and surface.sample(level.cell_center(i)) < sea_y - 1.0:
			level.terrain[i] = HexMapGenerator.Terrain.SHALLOW_WATER
