class_name ChartLayers
extends RefCounted
## The loading screen's chart gains detail as the map is made (drawn on the build thread, as
## transparent ink over the heightmap chart):
##   layer 1 - once the land is shaped: rivers in blue ink, lakes washed in, forests as little
##             tree marks, mountains as peaks;
##   layer 2 - once resources and trails are known: the old ways as dashed lines, cave mouths,
##             the volcano, and deposits as coloured dots (gold for precious things, rust for
##             ore, green for game and timber...).
## Each layer includes the ones before it.

const INK := Color(0.13, 0.09, 0.06, 0.95)
const RIVER := Color(0.12, 0.3, 0.45, 0.95)
const LAKE := Color(0.2, 0.38, 0.5, 0.6)
const FOREST := Color(0.16, 0.3, 0.14, 0.85)
const ROAD := Color(0.42, 0.18, 0.1, 0.9)
const GROUP_COLORS := [Color(0.25, 0.42, 0.18), Color(0.8, 0.6, 0.12), Color(0.55, 0.22, 0.12), Color(0.3, 0.5, 0.25), Color(0.25, 0.32, 0.55)]

static var _last: Image


## Chart size in pixels for a map of this size (the loading screen uses the same).
static func dims(world: Vector2) -> Vector2i:
	var aspect := world.x / maxf(world.y, 1.0)
	var w := 512 if aspect >= 1.0 else int(512 * aspect)
	return Vector2i(w, int(w / aspect))


static func draw(hm: HexMap, layer: int) -> Image:
	if hm.levels.is_empty() or hm.surfaces.is_empty():
		return null
	var world := hm.source.world_size
	var d := dims(world)
	var img: Image
	if layer >= 2 and _last != null and _last.get_size() == d:
		img = _last.duplicate()
	else:
		img = Image.create(d.x, d.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
	var sc := Vector2(d) / world
	var lv: HexLevel = hm.levels[0]
	if layer == 1 or _last == null:
		# Lakes.
		var hy: Hydrology = hm.hydrology[0] if not hm.hydrology.is_empty() else null
		if hy != null:
			for y in d.y:
				for x in d.x:
					var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / sc
					if hy.lake_at(p) >= 0:
						_plot(img, x, y, LAKE)
		# Forests and mountains, a mark every few hexes.
		var step := maxi(1, int(round(lv.hex_size * 2.2 * sc.x)))
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var top := maxf(lv.max_top_y() - hm.sea_y, 1.0)
		for i in lv.cell_count():
			var c := lv.cell_center(i) * sc
			if (int(c.x) / step + int(c.y) / step) % 2 != 0 or int(c.x) % step > 1 or int(c.y) % step > 1:
				continue
			var t := lv.terrain[i]
			var j := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			if t == HexMapGenerator.Terrain.FOREST:
				_tree(img, c + j, FOREST)
			elif (t == HexMapGenerator.Terrain.ROCK or t == HexMapGenerator.Terrain.SNOW) and (lv.top_y(i) - hm.sea_y) / top > 0.45:
				_peak(img, c + j, INK)
		# Rivers: wider towards the sea.
		if not hm.river_paths.is_empty():
			for path: RiverPath in hm.river_paths[0]:
				for k in range(1, path.points.size()):
					var a := Vector2(path.points[k - 1].x, path.points[k - 1].z) * sc
					var b := Vector2(path.points[k].x, path.points[k].z) * sc
					_line(img, a, b, clampf(path.widths[k] * sc.x * 1.4, 0.8, 2.6), RIVER)
		_last = img.duplicate()
	if layer >= 2:
		# The old ways, dashed.
		if hm.road_plan != null:
			for r: Dictionary in hm.road_plan.roads:
				var pts: PackedVector2Array = r.pts
				var run := 0.0
				for k in range(1, pts.size()):
					var a := pts[k - 1] * sc
					var b := pts[k] * sc
					run += a.distance_to(b)
					if fmod(run, 7.0) < 4.5:
						_line(img, a, b, 1.0, ROAD)
		# Deposits: a dot at each deposit's centre, coloured by kind of resource.
		for dep: Dictionary in lv.deposits:
			var c := lv.cell_center(dep.center) * sc
			var col: Color = GROUP_COLORS[NaturalResources.group(dep.kind) % GROUP_COLORS.size()]
			_disc(img, c, 2.2 + minf(float(dep.size), 12.0) * 0.12, INK)
			_disc(img, c, 1.4 + minf(float(dep.size), 12.0) * 0.12, col)
		# Cave mouths: a small dark arch.
		if hm.cave_plan != null:
			for sy: Dictionary in hm.cave_plan.systems:
				for e: Dictionary in sy.entrances:
					_arch(img, (e.p as Vector2) * sc, INK)
		# The volcano: a red-tipped cone.
		if hm.volcano_plan != null:
			for v: Dictionary in hm.volcano_plan.volcanoes:
				var c := (v.c as Vector2) * sc
				var r := clampf(float(v.r) * sc.x * 0.25, 5.0, 14.0)
				_line(img, c + Vector2(-r, r * 0.6), c + Vector2(-r * 0.2, -r * 0.6), 1.4, INK)
				_line(img, c + Vector2(r, r * 0.6), c + Vector2(r * 0.2, -r * 0.6), 1.4, INK)
				_disc(img, c + Vector2(0, -r * 0.7), 2.0, Color(0.85, 0.3, 0.08))
	return img


static func _plot(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var d := img.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(d.r, d.g, d.b) * d.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var cov := clampf(r + 0.5 - dd, 0.0, 1.0)
			if cov > 0.0:
				_plot(img, x, y, Color(col, col.a * cov))


static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := maxi(1, int(a.distance_to(b) * 2.0))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		_disc(img, p, w * 0.5, Color(col, col.a * 0.55))


static func _tree(img: Image, c: Vector2, col: Color) -> void:
	# A little conifer: a trunk and a triangle.
	_line(img, c + Vector2(0, 2.5), c + Vector2(0, 0.5), 0.8, col)
	_line(img, c + Vector2(-2.0, 1.0), c + Vector2(0, -3.0), 0.9, col)
	_line(img, c + Vector2(2.0, 1.0), c + Vector2(0, -3.0), 0.9, col)
	_line(img, c + Vector2(-2.0, 1.0), c + Vector2(2.0, 1.0), 0.9, col)


static func _peak(img: Image, c: Vector2, col: Color) -> void:
	_line(img, c + Vector2(-3.5, 2.0), c + Vector2(0, -2.5), 0.9, col)
	_line(img, c + Vector2(0, -2.5), c + Vector2(3.5, 2.0), 0.9, col)
	_line(img, c + Vector2(0, -2.5), c + Vector2(1.2, 0.0), 0.7, col)


static func _arch(img: Image, c: Vector2, col: Color) -> void:
	for k in 9:
		var a := PI + PI * k / 8.0
		_disc(img, c + Vector2(cos(a), sin(a)) * 3.0, 0.9, col)
	_disc(img, c + Vector2(0, 0.6), 1.6, col)
