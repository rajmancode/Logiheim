class_name VolcanoMaker
extends RefCounted
## Volcanoes: a cone with radial gullies and a crater, built up on the land before water is
## routed (so rivers run off its flanks), with basalt around it.
##
## plan() picks an inland spot on the finest level (land all around, away from the sea).
## apply() raises the cone on any level's TerrainSurface and writes `surface.volcanic`
## (0..1): the bare basalt and ash of the cone, plus old lava flows streaking down and out
## over the land. The terrain shader turns that into dark basalt, with columnar jointing on
## steep faces; boulders there are basalt too. build_effects() adds a glowing lava pool in the
## crater and a drifting smoke plume.

## Each: {c: Vector2, r: float (radius), h: float (height above base), base: float,
## rc: float (crater radius), depth: float (crater depth)}.
var volcanoes: Array = []
var sea_y := 0.0

static var _lava_mat: ShaderMaterial
static var _smoke_quad: QuadMesh


static func plan(surface: TerrainSurface, settings: HexMapSettings) -> VolcanoMaker:
	var vm := VolcanoMaker.new()
	vm.sea_y = surface.sea_y
	if settings.volcano_count <= 0:
		return vm
	var size := Vector2((surface.nx - 1) * surface.spacing, (surface.nz - 1) * surface.spacing)
	var R := settings.volcano_radius
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	var cands: Array = []
	var step := 40.0
	var z := R
	while z < size.y - R:
		var x := R
		while x < size.x - R:
			var c := Vector2(x, z)
			# Land all the way round, at the foot and half way up.
			var ok := surface.sample(c) > surface.sea_y + 3.0
			var ring := 0.0
			for k in 12:
				var d := Vector2.from_angle(TAU * k / 12.0)
				var a := surface.sample(c + d * R * 1.05)
				var b := surface.sample(c + d * R * 0.5)
				if a < surface.sea_y + 2.0 or b < surface.sea_y + 2.0:
					ok = false
					break
				ring += a
			if ok:
				ring /= 12.0
				# Prefer moderate ground (not the very top of the mountains), a little random.
				cands.append([ring - surface.sea_y + rng.randf() * 25.0, c, ring])
			x += step
		z += step
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for cand in cands:
		if vm.volcanoes.size() >= settings.volcano_count:
			break
		var c: Vector2 = cand[1]
		var close := false
		for v: Dictionary in vm.volcanoes:
			if v.c.distance_to(c) < R * 3.0:
				close = true
		if close:
			continue
		var h := settings.volcano_height
		vm.volcanoes.append({"c": c, "r": R, "h": h, "base": cand[2],
			"rc": minf(R * 0.12, 45.0), "depth": h * 0.28})
	print("VolcanoMaker: %d volcanoes %s" % [vm.volcanoes.size(), vm.volcanoes.map(func(v): return v.c)])
	return vm


func count() -> int:
	return volcanoes.size()


## Raises the cones and marks volcanic ground (cone and lava flows).
func apply(surface: TerrainSurface) -> void:
	for v: Dictionary in volcanoes:
		var c: Vector2 = v.c
		var R: float = v.r
		var H: float = v.h
		var base: float = v.base
		var rc: float = v.rc
		var depth: float = v.depth
		var reach := R * 1.9
		var x0 := maxi(0, floori((c.x - reach) / surface.spacing))
		var x1 := mini(surface.nx - 1, ceili((c.x + reach) / surface.spacing))
		var z0 := maxi(0, floori((c.y - reach) / surface.spacing))
		var z1 := mini(surface.nz - 1, ceili((c.y + reach) / surface.spacing))
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(x * surface.spacing, z * surface.spacing)
				var r := p.distance_to(c)
				if r > reach:
					continue
				var dir := (p - c) / maxf(r, 0.001)
				var i := z * surface.nx + x
				var h := surface.heights[i]
				if r < R:
					var f: float
					if r > rc:
						f = pow((R - r) / (R - rc), 1.7)
						# Radial gullies and ribs down the flanks.
						var g := absf(BorderNoise.value_noise(dir * 9.0 + Vector2(r * 0.004, 1.3)) - 0.5) * 2.0
						f *= 1.0 - 0.15 * (1.0 - g) * smoothstep(rc * 1.2, rc * 2.5, r)
						# Rough, blocky lava surface.
						f += (BorderNoise.value_noise(p * 0.06) - 0.5) * 2.4 / H + (BorderNoise.value_noise(p * 0.017 + Vector2(3.0, 9.0)) - 0.5) * 7.0 / H
					else:
						f = 1.0 - depth / H * (1.0 - (r / rc) * (r / rc))
					var target := base + H * f
					if r < rc * 1.2:
						h = target
					else:
						h = lerpf(h, maxf(h, target), smoothstep(R, R * 0.7, r))
					surface.heights[i] = h
				# Volcanic ground: the cone itself, and old lava flows reaching out over the land.
				var cone := 1.0 - smoothstep(R * 0.7, R * 1.1, r)
				var flow := smoothstep(0.6, 0.72, BorderNoise.value_noise(dir * 5.0 + Vector2(7.1, 3.3) + Vector2(r * 0.0015, 0.0)))
				flow *= 1.0 - smoothstep(R * 1.1, reach, r)
				surface.volcanic[i] = maxf(surface.volcanic[i], maxf(cone, flow * 0.85))


## Hexes on the cone become rock (nothing grows or settles on fresh basalt).
func mark_level(level: HexLevel, surface: TerrainSurface) -> void:
	if volcanoes.is_empty():
		return
	for i in level.cell_count():
		if not HexMapGenerator.is_water(level.terrain[i]) and surface.volcanic_at(level.cell_center(i)) > 0.6:
			level.terrain[i] = HexMapGenerator.Terrain.ROCK


## Lava pool in each crater and a smoke plume drifting downwind.
func build_effects(surface: TerrainSurface, parent: Node3D) -> void:
	for v: Dictionary in volcanoes:
		var c: Vector2 = v.c
		var floor_y := surface.sample(c)
		var lava := MeshInstance3D.new()
		lava.name = "Lava"
		var disc := CylinderMesh.new()
		disc.top_radius = v.rc * 0.62
		disc.bottom_radius = v.rc * 0.62
		disc.height = 0.4
		disc.radial_segments = 48
		lava.mesh = disc
		lava.material_override = _lava_material()
		lava.position = Vector3(c.x, floor_y + 1.2, c.y)
		lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(lava)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.15)
		glow.light_energy = 4.0
		glow.omni_range = v.rc * 2.5
		glow.position = Vector3(c.x, floor_y + 8.0, c.y)
		parent.add_child(glow)
		var smoke := GPUParticles3D.new()
		smoke.name = "VolcanoSmoke"
		smoke.amount = 48
		smoke.lifetime = 16.0
		smoke.preprocess = 16.0
		smoke.position = Vector3(c.x, floor_y + 6.0, c.y)
		smoke.visibility_aabb = AABB(Vector3(-400, -20, -400), Vector3(800, 500, 800))
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = v.rc * 0.5
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 9.0
		pm.gravity = Vector3(2.2, -0.15, 1.1)
		pm.damping_min = 0.15
		pm.damping_max = 0.3
		pm.scale_min = 18.0
		pm.scale_max = 30.0
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, 2.6))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
		var grad := Gradient.new()
		grad.set_color(0, Color(0.35, 0.32, 0.3, 0.0))
		grad.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
		grad.add_point(0.1, Color(0.3, 0.28, 0.27, 0.6))
		grad.add_point(0.6, Color(0.55, 0.54, 0.53, 0.35))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		smoke.process_material = pm
		smoke.draw_pass_1 = _smoke_mesh()
		parent.add_child(smoke)


static func _lava_material() -> ShaderMaterial:
	if _lava_mat == null:
		_lava_mat = ShaderMaterial.new()
		_lava_mat.shader = load("res://shaders/lava.gdshader")
	return _lava_mat


static func _smoke_mesh() -> QuadMesh:
	if _smoke_quad != null:
		return _smoke_quad
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
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_quad = QuadMesh.new()
	_smoke_quad.size = Vector2(1, 1)
	_smoke_quad.material = mat
	return _smoke_quad
