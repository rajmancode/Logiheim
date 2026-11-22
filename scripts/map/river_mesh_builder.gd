class_name RiverMeshBuilder
extends RefCounted
## Rivers and lakes.
##
## courses(): traces the river network once, on the finest level's Hydrology, into smooth
##   world-space courses: corner-cut, meandering where the ground is flat, and with every
##   tributary ending exactly on the river it joins.
## place(): fits the courses onto one level's terrain: water level (never rising downstream),
##   width from the catchment (square-root law), speed and white water from the slope,
##   estuaries at the sea, and gaps where a river runs through a lake.
## build() / build_lakes(): the water meshes.

const SHADER_PATH := "res://shaders/river.gdshader"

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 5.0
	tex.generate_mipmaps = true
	tex.noise = noise
	_material.set_shader_parameter("flow_noise", tex)
	return _material


## Lakes use the sea shader with fresh-water colours and calmer waves.
static func lake_material(wave_normal: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_normal", wave_normal)
	mat.set_shader_parameter("shallow_color", Color(0.2, 0.36, 0.3))
	mat.set_shader_parameter("deep_color", Color(0.025, 0.08, 0.085))
	mat.set_shader_parameter("clarity", 2.5)
	mat.set_shader_parameter("colour_depth", 8.0)
	mat.set_shader_parameter("foam_width", 0.6)
	mat.set_shader_parameter("wave_height", 0.04)
	mat.set_shader_parameter("edge_alpha", true)
	mat.set_shader_parameter("surf", 0.0)
	return mat


static func width_for(area: float, settings: HexMapSettings) -> float:
	return clampf(settings.river_width_scale * sqrt(area / 1.0e6), settings.river_min_width, settings.river_max_width)


static func depth_for(width: float) -> float:
	return clampf(0.3 + width * 0.09, 0.5, 4.0)


# --------------------------------------------------------------------------- courses

## World-space river courses: Array of {pts: PackedVector2Array, areas: PackedFloat32Array,
## to_sea: bool, joins: bool}.
static func courses(hydro: Hydrology, settings: HexMapSettings) -> Array:
	var land_area := 0.0
	for c in hydro.nx * hydro.nz:
		if hydro.land(c):
			land_area += hydro.spacing * hydro.spacing
	var threshold := maxf(settings.river_catchment * land_area, hydro.spacing * hydro.spacing * 6.0)
	var out: Array = []
	for seg: Dictionary in hydro.trace_segments(threshold):
		var cells: PackedInt32Array = seg.cells
		var pts := PackedVector2Array()
		var areas := PackedFloat32Array()
		for c in cells:
			pts.append(hydro.cell_pos(c))
			areas.append(hydro.area[c] if hydro.land(c) else hydro.area[cells[maxi(0, cells.size() - 2)]])
		var smooth := _smooth(_relax(pts, 3), areas, 3)
		var course := _meander(smooth[0], smooth[1], hydro, settings)
		out.append({"pts": course[0], "areas": course[1], "to_sea": seg.to_sea, "delta": false,
			"joins": not seg.to_sea and hydro.parent[cells[cells.size() - 1]] >= 0})
	_snap_junctions(out, hydro.spacing * 3.0)
	# Deltas: wide rivers reaching the sea over low, flat land split into distributaries.
	var deltas: Array = []
	for c: Dictionary in out:
		if c.to_sea:
			deltas.append_array(_make_delta(c, hydro, settings))
	out.append_array(deltas)
	return out


## Laplacian smoothing with fixed ends: pulls each point towards its neighbours so the
## 45-degree steps of the drainage grid melt into curves.
static func _relax(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var p := pts
	for it in passes:
		if p.size() < 3:
			break
		var np := p.duplicate()
		for k in range(1, p.size() - 1):
			np[k] = (p[k - 1] + p[k] * 2.0 + p[k + 1]) * 0.25
		p = np
	return p


## If a wide river crosses low, flat land on its way into the sea, cuts its course where that
## land begins and returns 2-4 distributary courses fanning out from there to the coast.
## (The river's own course is shortened in place.)
static func _make_delta(c: Dictionary, hydro: Hydrology, settings: HexMapSettings) -> Array:
	var pts: PackedVector2Array = c.pts
	var areas: PackedFloat32Array = c.areas
	var n := pts.size()
	if n < 8:
		return []
	var w_end := width_for(areas[n - 2], settings)
	if w_end < settings.delta_min_width:
		return []
	# Walk upstream from the mouth while the land stays low.
	var max_len := minf(w_end * 40.0, 600.0)
	var along := 0.0
	var ks := n - 1
	while ks > 1:
		var step := pts[ks].distance_to(pts[ks - 1])
		if along + step > max_len or hydro.filled_at(pts[ks - 1]) - hydro.sea_y > settings.delta_height:
			break
		along += step
		ks -= 1
	if along < maxf(w_end * 3.0, 30.0):
		return []
	var start := pts[ks]
	var main_dir := (pts[n - 1] - start).normalized()
	var branches := clampi(int(along / (w_end * 5.0)) + 1, 2, settings.delta_max_branches)
	var spread := 0.85
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(hash(start))
	var out: Array = []
	for b in branches:
		var ang := lerpf(-spread, spread, float(b) / (branches - 1)) + rng.randf_range(-0.12, 0.12)
		var dir := main_dir.rotated(ang)
		var bw := w_end * (0.7 if branches == 2 else 0.55) * rng.randf_range(0.8, 1.1)
		var step := maxf(bw * 0.6, hydro.spacing * 0.4)
		var bp := PackedVector2Array([start])
		var p := start
		var reached := false
		for i in int(along * 2.2 / step) + 4:
			# Head downhill, keep fanning out, wander a little.
			var e := hydro.spacing
			var grad := Vector2(hydro.filled_at(p + Vector2(e, 0)) - hydro.filled_at(p - Vector2(e, 0)),
				hydro.filled_at(p + Vector2(0, e)) - hydro.filled_at(p - Vector2(0, e)))
			var down := -grad.normalized() if grad.length() > 1e-4 else dir
			var wander := BorderNoise.snoise(p * 0.02 + Vector2(b * 7.3, 1.7)) - 0.5
			dir = (dir * 0.8 + down * 0.2).normalized().rotated(wander * 0.25)
			p += dir * step
			bp.append(p)
			if hydro.height_at(p) < hydro.sea_y - 0.5:
				reached = true
				bp.append(p + dir * step * 2.0)
				break
		if not reached:
			continue
		var area := pow(bw / settings.river_width_scale, 2.0) * 1.0e6
		var ba := PackedFloat32Array()
		for k in bp.size():
			ba.append(area)
		var sm := _smooth(_relax(bp, 3), ba, 2)
		out.append({"pts": sm[0], "areas": sm[1], "to_sea": true, "joins": false, "delta": true})
	if out.size() >= 2:
		# The river now ends where its delta begins.
		c.pts = pts.slice(0, ks + 1)
		c.areas = areas.slice(0, ks + 1)
		c.to_sea = false
		c.delta = true
		return out
	return []


## Corner-cutting smoothing that keeps both ends (so junctions stay put).
static func _smooth(pts: PackedVector2Array, areas: PackedFloat32Array, iterations: int) -> Array:
	var p := pts
	var a := areas
	for it in iterations:
		if p.size() < 3:
			break
		var np := PackedVector2Array([p[0]])
		var na := PackedFloat32Array([a[0]])
		for k in p.size() - 1:
			np.append(p[k].lerp(p[k + 1], 0.25))
			np.append(p[k].lerp(p[k + 1], 0.75))
			na.append(lerpf(a[k], a[k + 1], 0.25))
			na.append(lerpf(a[k], a[k + 1], 0.75))
		np.append(p[p.size() - 1])
		na.append(a[a.size() - 1])
		p = np
		a = na
	return [p, a]


## Resamples a course and makes it wind: sideways sine offsets about 12 widths long (the
## natural meander wavelength) on flat ground, plus a slower, irregular wander everywhere so no
## stretch runs ruler-straight. Both fade out near the ends (sources, junctions, mouths).
static func _meander(pts: PackedVector2Array, areas: PackedFloat32Array, hydro: Hydrology, settings: HexMapSettings) -> Array:
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	var out_p := PackedVector2Array()
	var out_a := PackedFloat32Array()
	if total <= 0.0:
		return [pts, areas]
	var step := clampf(width_for(areas[0], settings) * 0.5, 1.0, hydro.spacing * 0.5)
	var phase := float(absi(MapSeed.mix(hash(pts[0]))) % 1000) / 1000.0 * TAU
	var along := 0.0
	var k := 0
	var seg_start := 0.0
	var seg_len := pts[0].distance_to(pts[1]) if pts.size() > 1 else 0.0
	while along <= total:
		while k < pts.size() - 2 and along > seg_start + seg_len:
			seg_start += seg_len
			k += 1
			seg_len = pts[k].distance_to(pts[k + 1])
		var t := clampf((along - seg_start) / maxf(seg_len, 1e-4), 0.0, 1.0)
		var p := pts[k].lerp(pts[k + 1], t)
		var a := lerpf(areas[k], areas[k + 1], t)
		var w := width_for(a, settings)
		var dir := (pts[k + 1] - pts[k]).normalized()
		var side := Vector2(-dir.y, dir.x)
		# Slope from the filled terrain a few widths up and down the course.
		var probe := maxf(w * 2.0, hydro.spacing)
		var slope := absf(hydro.filled_at(p - dir * probe) - hydro.filled_at(p + dir * probe)) / (2.0 * probe)
		var flat := 1.0 - smoothstep(0.004, 0.035, slope)
		var taper := smoothstep(0.0, w * 6.0, along) * smoothstep(0.0, w * 6.0, total - along)
		var wavelength := 12.0 * w * (0.8 + 0.4 * BorderNoise.snoise(p * 0.004))
		phase += step * TAU / wavelength
		var amp := w * 1.3 * settings.river_meander * flat * taper
		var seed_v := float(absi(MapSeed.mix(hash(pts[0]))) % 997)
		var wander := (BorderNoise.snoise(Vector2(along * 0.011, seed_v)) - 0.5) * 2.0 			+ (BorderNoise.snoise(Vector2(along * 0.032, seed_v + 31.0)) - 0.5) * 0.8
		var w_taper := smoothstep(0.0, 40.0, along) * smoothstep(0.0, 40.0, total - along)
		var w_amp := maxf(w * 1.5, 9.0) * settings.river_meander * w_taper * (1.0 - 0.4 * flat)
		out_p.append(p + side * (sin(phase) * amp + wander * w_amp))
		out_a.append(a)
		step = clampf(w * 0.5, 1.0, hydro.spacing * 0.5)
		along += step
	out_p.append(pts[pts.size() - 1])
	out_a.append(areas[areas.size() - 1])
	# Iron out the small kinks where the sideways direction turns at a corner.
	return [_relax(out_p, 2), out_a]


## Moves the end of every tributary onto the nearest point of the river it flows into.
static func _snap_junctions(all: Array, radius: float) -> void:
	for i in all.size():
		var c: Dictionary = all[i]
		if not c.joins:
			continue
		var pts: PackedVector2Array = c.pts
		var end := pts[pts.size() - 1]
		var best := end
		var best_d := radius * radius
		for j in all.size():
			if j == i:
				continue
			var other: PackedVector2Array = all[j].pts
			for q in other:
				var d := q.distance_squared_to(end)
				if d < best_d:
					best_d = d
					best = q
		# Shift the last stretch gradually so the tributary bends in instead of kinking.
		var off := best - end
		var m := mini(pts.size() - 1, 8)
		for j in m + 1:
			pts[pts.size() - 1 - j] += off * (1.0 - float(j) / (m + 1))
		pts[pts.size() - 1] = best
		c.pts = pts


# --------------------------------------------------------------------------- per level

## Fits the courses onto one level's terrain. Also marks the level's river and lake hexes.
static func place(all: Array, level: HexLevel, surface: TerrainSurface, hydro: Hydrology, noise: BorderNoise, settings: HexMapSettings, source: TerrainSource) -> Array[RiverPath]:
	var paths: Array[RiverPath] = []
	var min_w := level.hex_size * settings.river_min_width_per_hex if level.level_index > 0 else 0.0
	level.river.fill(0)
	level.river_width.fill(0.0)
	for i in level.cell_count():
		level.lake[i] = 1 if hydro.lake_at(level.cell_center(i)) >= 0 else 0

	# Pass 1: water level, width and speed along each course.
	var placed: Array = []
	for c: Dictionary in all:
		var pts: PackedVector2Array = c.pts
		var areas: PackedFloat32Array = c.areas
		var n := pts.size()
		var ys := PackedFloat32Array()
		var ws := PackedFloat32Array()
		ys.resize(n)
		ws.resize(n)
		var total := 0.0
		for k in n - 1:
			total += pts[k].distance_to(pts[k + 1])
		var along := 0.0
		var prev_y := INF
		for k in n:
			if k > 0:
				along += pts[k].distance_to(pts[k - 1])
			var w := width_for(areas[k], settings)
			# Rivers are born thin: from a trickle at the source, widening over the first
			# few hundred metres (delta branches start from a full river, so not those).
			if not (c.get("delta", false) and c.to_sea):
				w *= lerpf(0.25, 1.0, smoothstep(0.0, 300.0, along))
			w = maxf(w, min_w)
			if c.to_sea and not c.get("delta", false):
				w *= lerpf(1.0, 1.8, smoothstep(total * 0.75, total, along))
			var y := hydro.filled_at(pts[k]) - depth_for(w) * 0.25
			if c.to_sea and k == n - 1:
				y = surface.sea_y + 0.03
			y = maxf(minf(y, prev_y), surface.sea_y + 0.03)
			prev_y = y
			ys[k] = y
			ws[k] = w
		# Waterfalls: where the ground drops sharply, the whole drop is gathered into one fall
		# (level water above, a sheer drop, level water below) instead of a steep ramp.
		var falls := PackedInt32Array()
		var seg_id := PackedInt32Array()
		seg_id.resize(n)
		if settings.waterfall_min_drop > 0.0:
			var last_fall := -INF
			var along_k := PackedFloat32Array([0.0])
			for q in range(1, n):
				along_k.append(along_k[q - 1] + pts[q].distance_to(pts[q - 1]))
			var k := 0
			while k < n - 1:
				var j := k + 1
				var span := pts[k].distance_to(pts[j])
				while j < n - 1 and span < 15.0:
					span += pts[j].distance_to(pts[j + 1])
					j += 1
				var drop := ys[k] - ys[j]
				if drop >= settings.waterfall_min_drop and drop / maxf(span, 1.0) >= 0.55 and k > 2 						and along_k[k] - last_fall > 150.0:
					last_fall = along_k[k]
					# The lip is where the single steepest step was.
					var lip := k
					var steepest := -1.0
					for q in range(k, j):
						var st := (ys[q] - ys[q + 1]) / maxf(pts[q].distance_to(pts[q + 1]), 0.1)
						if st > steepest:
							steepest = st
							lip = q
					# (Only ever lowered: the channel is carved down to it, never left floating.)
					for q in range(k, lip + 1):
						ys[q] = ys[lip]
					for q in range(lip + 1, j + 1):
						ys[q] = ys[j]
					falls.append(lip)
					k = j
				else:
					k += 1
			var sid := 0
			for q in n:
				seg_id[q] = sid
				if falls.has(q):
					sid += 1
		# Smooth the water surface along the river so it slopes evenly instead of tilting in
		# steps between terraces (never across a waterfall), then keep it falling downstream.
		var sm_y := ys.duplicate()
		for k in range(1, n - 1):
			var acc := 0.0
			var cnt := 0
			for q in range(maxi(0, k - 5), mini(n, k + 6)):
				if seg_id[q] == seg_id[k]:
					acc += ys[q]
					cnt += 1
			sm_y[k] = acc / cnt
		for k in range(1, n):
			sm_y[k] = maxf(minf(sm_y[k], sm_y[k - 1]), surface.sea_y + 0.03)
		placed.append([pts, sm_y, ws, falls])

	# Pass 2: tributaries meet the main river at its water level.
	for i in all.size():
		if not all[i].joins:
			continue
		var pts: PackedVector2Array = placed[i][0]
		var ys: PackedFloat32Array = placed[i][1]
		var end := pts[pts.size() - 1]
		for j in all.size():
			if j == i:
				continue
			var other: PackedVector2Array = placed[j][0]
			var idx := other.find(end)
			if idx >= 0:
				ys[ys.size() - 1] = placed[j][1][idx]
				for k in range(ys.size() - 2, -1, -1):
					ys[k] = maxf(ys[k], ys[k + 1])
				break
		placed[i][1] = ys

	# Pass 3: split around lakes, add speed and turbulence, mark hexes.
	for i in placed.size():
		var pts: PackedVector2Array = placed[i][0]
		var ys: PackedFloat32Array = placed[i][1]
		var ws: PackedFloat32Array = placed[i][2]
		var path: RiverPath = null
		var along := 0.0
		for k in pts.size():
			if k > 0:
				along += pts[k].distance_to(pts[k - 1])
			# Rivers stop where they reach the sea or enter a lake; the open water takes over.
			# (Any river: a meander can swing a little past the shoreline too.)
			if k > 0 and surface.sample(pts[k]) < surface.sea_y - 0.4:
				if path != null and path.points.size() >= 2:
					var last_y := path.points[path.points.size() - 1].y
					path.points.append(Vector3(pts[k].x, surface.sea_y + 0.03, pts[k].y))
					path.widths.append(ws[k])
					path.dist.append(along)
					path.speeds.append(path.speeds[path.speeds.size() - 1])
					# A river spilling off a cliff into the sea stays white all the way down.
					path.turbulence.append(1.0 if last_y - surface.sea_y > 1.5 else 0.0)
					paths.append(path)
				path = null
				break
			var in_lake := hydro.lake_at(pts[k]) >= 0
			if in_lake:
				if path != null and path.points.size() >= 2:
					paths.append(path)
				path = null
				continue
			if path == null:
				path = RiverPath.new()
				path.to_sea = all[i].to_sea
			# Rapids follow the real lie of the land: the slope of the Gaea terrain over a
			# stretch of ~30 m, not the stairs the hex terraces put in the water surface.
			var reach_m := maxf(ws[k] * 3.0, 30.0)
			var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			# (on this map's own ground, after the island has been shaped and hills lowered)
			var up := surface.sample(pts[k] - dir * reach_m * 0.5)
			var down := surface.sample(pts[k] + dir * reach_m * 0.5)
			var nat_slope := maxf(up - down, 0.0) / reach_m
			# Cascades: short drops where the water steps down a terrace.
			var k2 := mini(k + 1, pts.size() - 1)
			var step_drop := maxf(ys[k] - ys[k2], 0.0) / maxf(pts[k].distance_to(pts[k2]), 0.3)
			# Terrace cascades read as rapids (up to 0.6); only real falls go fully white.
			# Only genuinely steep water is rough: a mountain stream is mostly clear and fast.
			var turb := maxf(smoothstep(0.3, 0.8, nat_slope), 0.5 * smoothstep(0.8, 1.6, step_drop) + 0.5 * smoothstep(1.8, 3.0, step_drop))
			# Water running steeply downhill (over a few points) is white too.
			var ka := maxi(k - 2, 0)
			var kb := mini(k + 2, pts.size() - 1)
			var run := 0.0
			for q in range(ka, kb):
				run += pts[q].distance_to(pts[q + 1])
			var water_slope := maxf(ys[ka] - ys[kb], 0.0) / maxf(run, 0.5)
			turb = maxf(turb, smoothstep(0.25, 0.6, water_slope))
			path.points.append(Vector3(pts[k].x, ys[k], pts[k].y))
			path.widths.append(ws[k])
			path.dist.append(along)
			path.speeds.append(clampf(sqrt(maxf(nat_slope, step_drop * 0.5)) * 9.0, 0.35, 6.0))
			path.turbulence.append(turb)
			if (placed[i][3] as PackedInt32Array).has(k):
				path.falls.append(path.points.size() - 1)
			var cell := noise.cell_at(level, pts[k])
			if cell >= 0 and not HexMapGenerator.is_water(level.terrain[cell]):
				level.river[cell] = 1
				level.river_width[cell] = maxf(level.river_width[cell], ws[k])
		if path != null and path.points.size() >= 2:
			paths.append(path)
	return paths


## After all shaping of the ground: wherever the land just outside a river's channel has ended
## up lower than its water (a bank cut back by the slope limit, a trail, a valley), the water
## comes down to it, so no river ever runs above the ground beside it. Water keeps falling
## downstream. Carve the channels again afterwards.
static func settle(paths: Array[RiverPath], surface: TerrainSurface) -> void:
	for path in paths:
		var n := path.points.size()
		for k in n:
			var pt := path.points[k]
			var a := path.points[maxi(k - 1, 0)]
			var b := path.points[mini(k + 1, n - 1)]
			var t := Vector2(b.x - a.x, b.z - a.z).normalized()
			var side := Vector2(-t.y, t.x)
			var c := Vector2(pt.x, pt.z)
			var reach := path.widths[k] * 1.6 + 1.5
			var bank := minf(surface.sample(c + side * reach), surface.sample(c - side * reach))
			bank = maxf(bank, surface.sea_y + 0.03)
			if bank < pt.y - 0.05:
				pt.y = bank - 0.05
				path.points[k] = pt
		for k in range(1, n):
			if path.points[k].y > path.points[k - 1].y:
				var q := path.points[k]
				q.y = path.points[k - 1].y
				path.points[k] = q


# --------------------------------------------------------------------------- meshes

static var _sea_level := -INF
## Vertices across a river ribbon, minus one.
const ACROSS := 6


static func build(paths: Array[RiverPath], parent: Node3D, sea_y := -INF) -> void:
	if paths.is_empty():
		return
	_sea_level = sea_y
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for path in paths:
		_ribbon(path, verts, normals, uvs, uv2s, colors, indices)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## One indexed ribbon with per-vertex flow data, so speed and white water blend smoothly.
## UV = (across 0..1, metres along); UV2 = (turbulence, width); COLOR.r = speed / 6 m/s.
static func _ribbon(path: RiverPath, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		uv2s: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var n := path.points.size()
	if n < 2:
		return
	# Soften turbulence and speed along the river (a few points either side).
	var turb := PackedFloat32Array()
	var speed := PackedFloat32Array()
	turb.resize(n)
	speed.resize(n)
	for k in n:
		var t_sum := 0.0
		var s_sum := 0.0
		var cnt := 0
		for q in range(maxi(k - 3, 0), mini(k + 4, n)):
			t_sum += path.turbulence[q]
			s_sum += path.speeds[q]
			cnt += 1
		turb[k] = t_sum / cnt
		speed[k] = s_sum / cnt
	# Waterfalls stay white from the lip to the plunge pool and a little beyond.
	for f in path.falls:
		for q in range(f, mini(f + 3, n)):
			turb[q] = maxf(turb[q], 1.0 if q <= f + 1 else 0.8)
			speed[q] = maxf(speed[q], 5.0)
	# At the sea the river fades into it over its last couple of widths (COLOR.g), so the
	# ribbon never shows as a flat slab over the waves.
	var fade := PackedFloat32Array()
	fade.resize(n)
	fade.fill(1.0)
	var sea_mix := PackedFloat32Array()
	sea_mix.resize(n)
	# Any river ending at sea level runs into the sea (delta trunks and estuaries too).
	if path.to_sea or path.points[n - 1].y < _sea_level + 0.15:
		# Where the river comes down to sea level it is the sea's: its water takes the sea's
		# colour over the last stretch above that point and fades out soon after it.
		var s0 := n - 1
		for k in n:
			if path.points[k].y < _sea_level + 0.15:
				s0 = k
				break
		var run := 0.0
		for k in range(s0, -1, -1):
			if k < s0:
				run += path.points[k].distance_to(path.points[k + 1])
			sea_mix[k] = 1.0 - smoothstep(0.0, maxf(path.widths[k] * 3.0, 25.0), run)
		var past := 0.0
		for k in range(s0, n):
			if k > s0:
				past += path.points[k].distance_to(path.points[k - 1])
			sea_mix[k] = 1.0
			fade[k] = minf(fade[k], 1.0 - smoothstep(0.0, maxf(path.widths[k] * 1.5, 14.0), past))
		var from_end := 0.0
		var reach := maxf(path.widths[n - 1] * 5.0, 30.0)
		for k in range(n - 1, -1, -1):
			if k < n - 1:
				from_end += path.points[k].distance_to(path.points[k + 1])
			fade[k] = smoothstep(0.0, reach, from_end)
			if from_end > reach:
				break
	var base := verts.size()
	for k in n:
		var a := path.points[maxi(k - 1, 0)]
		var b := path.points[mini(k + 1, n - 1)]
		var t := Vector2(b.x - a.x, b.z - a.z)
		t /= maxf(t.length(), 0.001)
		var side := Vector3(-t.y, 0.0, t.x) * path.widths[k] * 0.5
		var lift := Vector3(0.0, 0.04, 0.0)
		var along3 := (b - a).normalized()
		var nrm := Vector3(-t.y, 0.0, t.x).cross(along3).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		# Several vertices across, so the shader can shape the surface (a slight crown,
		# waves running downstream, standing waves in rapids).
		for c in ACROSS + 1:
			var u := float(c) / ACROSS
			verts.append(path.points[k] + side * (u * 2.0 - 1.0) + lift)
			normals.append(nrm)
			uv2s.append(Vector2(turb[k], path.widths[k]))
			colors.append(Color(speed[k] / 6.0, fade[k], sea_mix[k]))
			uvs.append(Vector2(u, path.dist[k]))
	var row := ACROSS + 1
	for k in n - 1:
		for c in ACROSS:
			var l0 := base + k * row + c
			var r0 := l0 + 1
			var l1 := l0 + row
			var r1 := l1 + 1
			# Wound so the top face points up: Godot treats clockwise (seen from the front) as
			# front-facing, i.e. the right-hand-rule cross product points away from the viewer.
			var cross_up := (verts[r0] - verts[l0]).cross(verts[r1] - verts[l0]).y > 0.0
			if cross_up:
				indices.append_array([l0, r1, r0, l0, l1, r1])
			else:
				indices.append_array([l0, r0, r1, l0, r1, l1])


## Flat water at each lake's level, built on the terrain's own (finer) grid: every vertex under
## the lake level that connects to the lake, plus two rings into the rising shore so the edge of
## the water mesh always ends inside the ground and the shoreline is where the terrain meets
## the water (smooth, not the 10 m flow grid). Never spreads over lower ground (dams).
static func build_lakes(hydro: Hydrology, surface: TerrainSurface, material: Material, parent: Node3D) -> void:
	if hydro.lake_level.is_empty():
		return
	var nx := surface.nx
	var nz := surface.nz
	var sp := surface.spacing
	var cover := PackedInt32Array()
	cover.resize(nx * nz)
	cover.fill(-1)
	# Water may only spread a little beyond the flow grid's lake cells, and never into a river
	# channel outside the lake, so it can't run off down the carved outlet.
	var reach := hydro.lake_id.duplicate()
	for grow in 2:
		var nr := reach.duplicate()
		for c in hydro.nx * hydro.nz:
			if reach[c] >= 0:
				continue
			var cx := c % hydro.nx
			var cz := c / hydro.nx
			for m in [c - 1 if cx > 0 else -1, c + 1 if cx < hydro.nx - 1 else -1, c - hydro.nx if cz > 0 else -1, c + hydro.nx if cz < hydro.nz - 1 else -1]:
				if m >= 0 and reach[m] >= 0:
					nr[c] = reach[m]
					break
		reach = nr
	var queue := PackedInt32Array()
	for z in nz:
		for x in nx:
			var i := z * nx + x
			var id := hydro.lake_at(Vector2(x * sp, z * sp))
			# (Outlet channels carved into the lake edge belong to the river ribbon.)
			if id >= 0 and surface.heights[i] < hydro.lake_level[id] and surface.river_mask[i] < 0.7:
				cover[i] = id
				queue.append(i)
	# Fill everything below the water level that connects to the lake.
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var id := cover[i]
		var x := i % nx
		var z := i / nx
		for m in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if z > 0 else -1, i + nx if z < nz - 1 else -1]:
			if m < 0 or cover[m] >= 0 or surface.heights[m] >= hydro.lake_level[id]:
				continue
			var mp := Vector2(m % nx * sp, m / nx * sp)
			# (Beyond the lake itself it never spreads out over the sea floor.)
			var own := hydro.lake_at(mp) == id
			if reach[_hcell(hydro, mp.x, mp.y)] == id and surface.river_mask[m] < (0.7 if own else 0.6) \
					and (own or surface.heights[m] > surface.sea_y + 0.3):
				cover[m] = id
				queue.append(m)
	# Two rings into the shore, only where the ground rises out of the water.
	for ring in 2:
		var nxt := cover.duplicate()
		for i in nx * nz:
			if cover[i] >= 0:
				continue
			var x := i % nx
			var z := i / nx
			for m in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if z > 0 else -1, i + nx if z < nz - 1 else -1]:
				if m >= 0 and cover[m] >= 0 and surface.heights[i] >= hydro.lake_level[cover[m]] - 0.05:
					nxt[i] = cover[m]
					break
		cover = nxt
	# Where the water mesh ends over ground lower than the water (e.g. at an outlet), the
	# edge would show as a hard line: fade those edge vertices out instead.
	var edge := PackedFloat32Array()
	edge.resize(nx * nz)
	for i in nx * nz:
		var id := cover[i]
		if id < 0:
			continue
		edge[i] = 1.0
		# Kept opaque only where the ground clearly rises out of the water; anywhere else (lower
		# ground, or a flat shelf right at water level) the edge fades.
		if surface.heights[i] >= hydro.lake_level[id] + 0.4:
			continue
		var x := i % nx
		var z := i / nx
		for m in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if z > 0 else -1, i + nx if z < nz - 1 else -1]:
			if m < 0 or cover[m] != id:
				edge[i] = 0.0
				break
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for z in nz - 1:
		for x in nx - 1:
			var i := z * nx + x
			var id := cover[i]
			if id < 0 or cover[i + 1] != id or cover[i + nx] != id or cover[i + nx + 1] != id:
				continue
			var y := hydro.lake_level[id] - 0.05
			# Clockwise from above: a, b, e and a, e, d.
			for q in [[x, z], [x + 1, z], [x + 1, z + 1], [x, z], [x + 1, z + 1], [x, z + 1]]:
				verts.append(Vector3(q[0] * sp, y, q[1] * sp))
				colors.append(Color(1, 1, 1, edge[q[1] * nx + q[0]]))
	if verts.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Lakes"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _hcell(hydro: Hydrology, x: float, z: float) -> int:
	return clampi(roundi(z / hydro.spacing), 0, hydro.nz - 1) * hydro.nx + clampi(roundi(x / hydro.spacing), 0, hydro.nx - 1)


# --------------------------------------------------------------------------- waterfalls

static var _mist_mesh: QuadMesh


## Spray at the foot of every waterfall: soft white puffs drifting up and out of the plunge
## pool (the falling water itself is the river ribbon, which runs sheer and white there).
static func build_falls(paths: Array[RiverPath], parent: Node3D) -> void:
	for path in paths:
		for f in path.falls:
			if f + 1 >= path.points.size():
				continue
			var top := path.points[f]
			var foot := path.points[f + 1]
			var drop := top.y - foot.y
			if drop < 2.0:
				continue
			var w := path.widths[f + 1]
			var dir := Vector3(foot.x - top.x, 0.0, foot.z - top.z).normalized()
			var mist := GPUParticles3D.new()
			mist.name = "WaterfallMist"
			mist.amount = clampi(int(8 + drop * 2.0 + w), 12, 48)
			mist.lifetime = 3.0
			mist.preprocess = 3.0
			mist.position = foot + dir * w * 0.3 + Vector3(0, 0.3, 0)
			mist.visibility_range_end = 900.0
			mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(w * 0.5, 0.3, w * 0.3)
			pm.direction = Vector3(dir.x * 0.6, 1.0, dir.z * 0.6)
			pm.spread = 35.0
			pm.initial_velocity_min = 0.6 + drop * 0.08
			pm.initial_velocity_max = 1.4 + drop * 0.15
			pm.gravity = Vector3(0, -0.2, 0)
			pm.damping_min = 0.3
			pm.damping_max = 0.6
			var sz := clampf(w * 0.35 + drop * 0.12, 1.5, 8.0)
			pm.scale_min = sz * 0.7
			pm.scale_max = sz * 1.3
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 0.4))
			curve.add_point(Vector2(1.0, 1.0))
			var ct := CurveTexture.new()
			ct.curve = curve
			pm.scale_curve = ct
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 0.0))
			grad.set_color(1, Color(1, 1, 1, 0.0))
			grad.add_point(0.15, Color(1, 1, 1, 0.55))
			grad.add_point(0.6, Color(1, 1, 1, 0.3))
			var gt := GradientTexture1D.new()
			gt.gradient = grad
			pm.color_ramp = gt
			mist.process_material = pm
			mist.draw_pass_1 = _mist_quad()
			mist.visibility_aabb = AABB(Vector3(-w - 10, -2, -w - 10), Vector3(w * 2 + 20, drop + 14, w * 2 + 20))
			parent.add_child(mist)
			WaterEffects.waterfall_splash(foot, dir, w, drop, parent)


static func _mist_quad() -> QuadMesh:
	if _mist_mesh != null:
		return _mist_mesh
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.92, 0.95, 1.0, 0.8)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.5
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(1, 1)
	_mist_mesh.material = mat
	return _mist_mesh
