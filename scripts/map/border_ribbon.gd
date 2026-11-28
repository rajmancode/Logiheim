class_name BorderRibbon
extends RefCounted
## Smooth borders round groups of hexes (a settlement's land, a resource deposit), drawn with
## shaders/border.gdshader.
##
## The hex edges where a region ends are chained into closed loops, the loops' corners are cut
## round (Chaikin, so the outline flows instead of zig-zagging along hex sides), resampled
## every couple of metres and draped over the ground as a ribbon reaching `inner` metres into
## the region and `outer` metres out of it. UV.x runs across the ribbon (0 at its outer edge, 1
## at its inner edge, the border itself at outer / (inner + outer)), UV.y along it in metres;
## COLOR is the region's colour.

const SMOOTHING := 3
const STEP := 2.0


## The closed outlines of a region of cells (`inside.call(cell) -> bool`), as loops of points
## going round with the region on their left.
static func loops(level: HexLevel, cells: Array, inside: Callable) -> Array:
	var s := level.hex_size
	var edges: Array = []           # [a, b]
	var from := {}                  # key of a -> [edge indices]
	for i: int in cells:
		var c := level.cell_center(i)
		for k in 6:
			var ca := HexCoords.corner(k, s)
			var cb := HexCoords.corner((k + 1) % 6, s)
			var j := level.cell_at(c + (ca + cb))
			if j >= 0 and bool(inside.call(j)):
				continue
			var a := c + ca
			var b := c + cb
			var key := _key(a)
			if not from.has(key):
				from[key] = []
			(from[key] as Array).append(edges.size())
			edges.append([a, b])
	var used := PackedByteArray()
	used.resize(edges.size())
	var out: Array = []
	for e0 in edges.size():
		if used[e0] == 1:
			continue
		var pts := PackedVector2Array()
		var e := e0
		while e >= 0 and used[e] == 0:
			used[e] = 1
			pts.append(edges[e][0])
			var nxt := -1
			for cand: int in from.get(_key(edges[e][1]), []):
				if used[cand] == 0:
					nxt = cand
					break
			e = nxt
		if pts.size() >= 3:
			out.append(pts)
	# Which side is in? Check one loop point stepped to its left; flip loops that go the other way.
	for li in out.size():
		var pts: PackedVector2Array = out[li]
		var votes := 0
		for t in mini(pts.size(), 8):
			var i := t * pts.size() / mini(pts.size(), 8)
			var d := (pts[(i + 1) % pts.size()] - pts[i]).normalized()
			var left := Vector2(d.y, -d.x)
			var probe := (pts[i] + pts[(i + 1) % pts.size()]) * 0.5 + left * s * 0.4
			var j := level.cell_at(probe)
			votes += 1 if (j >= 0 and bool(inside.call(j))) else -1
		if votes < 0:
			pts.reverse()
			out[li] = pts
	return out


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))


## A loop with its corners cut round and points every STEP metres.
static func smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var p := pts
	for it in SMOOTHING:
		var q := PackedVector2Array()
		var n := p.size()
		for i in n:
			var a := p[i]
			var b := p[(i + 1) % n]
			q.append(a.lerp(b, 0.25))
			q.append(a.lerp(b, 0.75))
		p = q
	var out := PackedVector2Array()
	var n2 := p.size()
	for i in n2:
		var a := p[i]
		var b := p[(i + 1) % n2]
		var steps := maxi(1, int(ceil(a.distance_to(b) / STEP)))
		for k in steps:
			out.append(a.lerp(b, float(k) / steps))
	return out


## Adds a ribbon along each loop to `data`: `inner` metres into the region, `outer` out of it,
## `lift` above the ground (never below the sea).
static func add_ribbons(data: MeshData, loops_in: Array, surface: TerrainSurface, sea_y: float, inner: float, outer: float, lift: float, col: Color) -> void:
	var width := inner + outer
	for raw: PackedVector2Array in loops_in:
		var pts := smooth(raw)
		var n := pts.size()
		if n < 3:
			continue
		var along := 0.0
		var prev_o := Vector3.ZERO
		var prev_i := Vector3.ZERO
		var prev_u := 0.0
		for k in n + 1:
			var i := k % n
			var p := pts[i]
			var d := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
			var left := Vector2(d.y, -d.x)
			var po := p - left * outer
			var pi := p + left * inner
			var vo := Vector3(po.x, maxf(surface.sample_mesh(po), sea_y) + lift, po.y)
			var vi := Vector3(pi.x, maxf(surface.sample_mesh(pi), sea_y) + lift, pi.y)
			if k > 0:
				along += pts[i].distance_to(pts[(i - 1 + n) % n])
				var ua := Vector2(0.0, prev_u)
				var ub := Vector2(1.0, prev_u)
				var uc := Vector2(0.0, along)
				var ud := Vector2(1.0, along)
				data.tri(prev_o, vo, vi, ua, uc, ud, Vector3.UP, Vector2(outer / width, width), col)
				data.tri(prev_o, vi, prev_i, ua, ud, ub, Vector3.UP, Vector2(outer / width, width), col)
			prev_o = vo
			prev_i = vi
			prev_u = along


## The material for a ribbon: style 0 a settlement's border, 1 a resource deposit's outline.
static func material(style: int, priority := 4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/border.gdshader")
	m.set_shader_parameter("style", style)
	m.render_priority = priority
	return m
