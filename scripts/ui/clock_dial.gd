class_name ClockDial
extends Control
## The day dial: a sky disc turning behind a semicircular window, the sun crossing it by day and
## the moon and stars by night, over a dark line of hills; a gilded frame and a pointer at the
## top for "now". `hours` (0..24) sets it; `season` (0 spring .. 3 winter) tints the hills.

var hours := 12.0
var season := 0
var _stars: Array = []

const DAY := Color(0.42, 0.68, 0.94)
const DUSK := Color(0.95, 0.55, 0.3)
const NIGHT := Color(0.05, 0.07, 0.18)
const GOLD := Color(0.93, 0.76, 0.4)
const DARK := Color(0.1, 0.07, 0.05)
const HILLS := [Color(0.16, 0.26, 0.14), Color(0.2, 0.28, 0.12), Color(0.26, 0.2, 0.1), Color(0.78, 0.82, 0.86)]


func _init() -> void:
	custom_minimum_size = Vector2(150, 80)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		_stars.append([rng.randf_range(0.0, TAU), rng.randf_range(0.35, 0.92), rng.randf_range(0.8, 1.8)])


func set_time(h: float, p_season: int) -> void:
	if absf(h - hours) < 0.005 and p_season == season:
		return
	hours = h
	season = p_season
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var c := Vector2(w * 0.5, size.y - 6.0)
	var r := minf(w * 0.5 - 4.0, size.y - 8.0)
	# Where the sun is on the disc: overhead at noon, under the hills at midnight.
	var th := (hours - 12.0) / 24.0 * TAU
	var sun_dir := Vector2(sin(th), -cos(th))
	# The sky disc, each rim point coloured by how far round it is from the sun.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 72
	pts.append(c)
	var lit := clampf(-sun_dir.y * 2.0 + 0.5, 0.0, 1.0)
	cols.append(NIGHT.lerp(DAY, lit))
	for i in n + 1:
		var a := PI + PI * float(i) / n
		var d := Vector2(cos(a), sin(a))
		var k := d.dot(sun_dir)
		var col := NIGHT.lerp(DAY, smoothstep(-0.35, 0.45, k))
		# A warm band where day meets night.
		col = col.lerp(DUSK, (1.0 - absf(k)) * 0.55 * smoothstep(-0.6, 0.1, k) * (1.0 - smoothstep(0.1, 0.6, k)))
		pts.append(c + d * r)
		cols.append(col)
	draw_polygon(pts, cols)
	# Stars on the night side.
	for st: Array in _stars:
		var a: float = float(st[0]) + th
		var d := Vector2(sin(a), -cos(a))
		if d.y > -0.05:
			continue
		var vis := 1.0 - smoothstep(-0.4, 0.2, d.dot(sun_dir))
		if vis > 0.02:
			draw_circle(c + d * r * float(st[1]), float(st[2]) * 0.7, Color(1, 1, 0.9, vis * 0.9))
	# The sun, with a glow; the moon opposite, a crescent.
	var sp := c + sun_dir * r * 0.66
	if sp.y < c.y + 10.0:
		for g in 4:
			draw_circle(sp, 13.0 - g * 2.5, Color(1.0, 0.85, 0.4, 0.12 + g * 0.06))
		draw_circle(sp, 6.5, Color(1.0, 0.92, 0.55))
	var mp := c - sun_dir * r * 0.66
	if mp.y < c.y + 10.0:
		draw_circle(mp, 6.0, Color(0.92, 0.93, 0.85))
		draw_circle(mp + Vector2(2.6, -1.6), 5.2, NIGHT.lerp(DAY, lit * 0.4))
	# Hills along the horizon, in the season's colour.
	var hills := PackedVector2Array()
	hills.append(Vector2(0, size.y))
	for i in 25:
		var x := w * float(i) / 24.0
		hills.append(Vector2(x, c.y - 9.0 - 6.0 * sin(x * 0.07 + 1.3) - 4.0 * sin(x * 0.19)))
	hills.append(Vector2(w, size.y))
	draw_colored_polygon(hills, (HILLS[clampi(season, 0, 3)] as Color).darkened(0.35 + 0.4 * (1.0 - lit)))
	# The gilded frame and the base.
	draw_arc(c, r + 1.0, PI, TAU, 64, DARK, 5.0, true)
	draw_arc(c, r, PI, TAU, 64, GOLD, 2.5, true)
	draw_rect(Rect2(0, c.y - 1.0, w, size.y - c.y + 1.0), DARK)
	draw_line(Vector2(c.x - r - 2.0, c.y - 1.0), Vector2(c.x + r + 2.0, c.y - 1.0), GOLD, 2.0, true)
	# Ticks every three hours round the frame (they turn with the sky), and "now" at the top.
	for h in 8:
		var a := float(h) * TAU / 8.0 - th
		var d := Vector2(sin(a), -cos(a))
		if d.y < -0.02:
			draw_line(c + d * (r - 5.0), c + d * (r - 1.0), GOLD.darkened(0.2), 1.5, true)
	var top := c + Vector2(0, -r)
	draw_colored_polygon(PackedVector2Array([top + Vector2(-6, -2), top + Vector2(6, -2), top + Vector2(0, 8)]), GOLD)
	draw_polyline(PackedVector2Array([top + Vector2(-6, -2), top + Vector2(6, -2), top + Vector2(0, 8), top + Vector2(-6, -2)]), DARK, 1.2, true)
