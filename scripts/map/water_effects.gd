class_name WaterEffects
extends RefCounted
## Splashes: spray where waves break on the coast (finest level), and droplets thrown up at the
## foot of waterfalls (see RiverMeshBuilder.build_falls).

static var _drop_mesh: QuadMesh


## Spray bursts along the shore, every ~45 m of coastline, more on steep rocky shores where
## waves hit hard. Bursts are staggered so the coast never splashes in unison.
static func build_shore_spray(surface: TerrainSurface, parent: Node3D) -> void:
	var picked: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(8080)
	var step := maxi(1, int(9.0 / surface.spacing))
	for z in range(2, surface.nz - 2, step):
		for x in range(2, surface.nx - 2, step):
			var i := z * surface.nx + x
			var h := surface.heights[i]
			if h < surface.sea_y - 0.6 or h > surface.sea_y + 0.6:
				continue
			# The waterline: open water a little way out on at least one side.
			var seaward := Vector2.ZERO
			for o: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
				var j := (z + o.y) * surface.nx + (x + o.x)
				if j >= 0 and j < surface.heights.size() and surface.heights[j] < surface.sea_y - 1.5:
					seaward += Vector2(o)
			if seaward == Vector2.ZERO:
				continue
			var p := Vector2(x, z) * surface.spacing
			var close := false
			for q in picked:
				if q.distance_squared_to(p) < 45.0 * 45.0:
					close = true
					break
			if close:
				continue
			picked.append(p)
			var rocky := smoothstep(0.2, 0.6, 1.0 - surface.normal_at(p + seaward.normalized() * -4.0).y)
			var spray := GPUParticles3D.new()
			spray.name = "ShoreSpray"
			spray.amount = 10 + int(rocky * 14.0)
			spray.lifetime = rng.randf_range(2.2, 3.8)
			spray.explosiveness = 0.85
			spray.randomness = 0.4
			spray.preprocess = rng.randf_range(0.0, 4.0)
			spray.position = Vector3(p.x, surface.sea_y + 0.2, p.y)
			spray.visibility_range_end = 550.0
			spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			spray.visibility_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 12, 24))
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(5.0, 0.2, 5.0)
			var landward := -seaward.normalized()
			pm.direction = Vector3(landward.x * 0.5, 1.0, landward.y * 0.5)
			pm.spread = 30.0
			pm.initial_velocity_min = 1.5 + rocky * 2.0
			pm.initial_velocity_max = 3.5 + rocky * 4.0
			pm.gravity = Vector3(0, -7.0, 0)
			pm.scale_min = 0.6
			pm.scale_max = 1.8 + rocky * 1.5
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 0.5))
			curve.add_point(Vector2(1.0, 1.6))
			var ct := CurveTexture.new()
			ct.curve = curve
			pm.scale_curve = ct
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 0.0))
			grad.set_color(1, Color(1, 1, 1, 0.0))
			grad.add_point(0.1, Color(1, 1, 1, 0.8))
			grad.add_point(0.5, Color(1, 1, 1, 0.4))
			var gt := GradientTexture1D.new()
			gt.gradient = grad
			pm.color_ramp = gt
			spray.process_material = pm
			spray.draw_pass_1 = RiverMeshBuilder._mist_quad()
			parent.add_child(spray)
			if picked.size() >= 220:
				print("WaterEffects: %d shore spray points" % picked.size())
				return
	print("WaterEffects: %d shore spray points" % picked.size())


## Where a river runs into the sea or a lake: the current meets standing water and churns -
## low bursts of spray and droplets across the mouth, stronger for wide, fast rivers.
static func build_river_mouths(paths: Array[RiverPath], hydro: Hydrology, surface: TerrainSurface, parent: Node3D) -> void:
	var made := 0
	for path in paths:
		var n := path.points.size()
		if n < 2:
			continue
		var q := path.points[n - 1]
		var prev := path.points[n - 2]
		var dir := Vector3(q.x - prev.x, 0.0, q.z - prev.z).normalized()
		var w := path.widths[n - 1]
		var ahead := Vector2(q.x + dir.x * (w + 3.0), q.z + dir.z * (w + 3.0))
		var water_y := 0.0
		if path.to_sea:
			water_y = surface.sea_y
		elif hydro != null and hydro.lake_at(ahead) >= 0:
			water_y = hydro.lake_level[hydro.lake_at(ahead)]
		else:
			continue
		var speed := path.speeds[n - 1] if path.speeds.size() == n else 1.0
		var strength := clampf(w / 12.0, 0.25, 1.5) * clampf(0.6 + speed * 0.4, 0.6, 1.6)
		var pos := Vector3(q.x, water_y + 0.15, q.z)
		# Droplets kicked up across the mouth.
		var p := GPUParticles3D.new()
		p.name = "RiverMouthSplash"
		p.amount = clampi(int(24 + 40 * strength), 24, 90)
		p.lifetime = 1.3
		p.preprocess = 1.3
		p.randomness = 0.5
		p.position = pos
		p.visibility_range_end = 380.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-w - 10, -2, -w - 10), Vector3(w * 2 + 20, 10, w * 2 + 20))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(w * 0.5, 0.1, w * 0.5)
		pm.direction = Vector3(dir.x * 0.8, 1.0, dir.z * 0.8)
		pm.spread = 50.0
		pm.initial_velocity_min = 1.2 * strength + 0.8
		pm.initial_velocity_max = 2.8 * strength + 1.5
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.15
		pm.scale_max = 0.4
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.85))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		p.process_material = pm
		p.draw_pass_1 = _drops()
		parent.add_child(p)
		# A soft spray cloud drifting out over the open water.
		var mist := GPUParticles3D.new()
		mist.name = "RiverMouthMist"
		mist.amount = clampi(int(6 + 10 * strength), 6, 24)
		mist.lifetime = 3.0
		mist.preprocess = 3.0
		mist.position = pos + dir * w * 0.6
		mist.visibility_range_end = 380.0
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mist.visibility_aabb = AABB(Vector3(-w - 15, -2, -w - 15), Vector3(w * 2 + 30, 10, w * 2 + 30))
		var mm := ParticleProcessMaterial.new()
		mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mm.emission_box_extents = Vector3(w * 0.6, 0.1, w * 0.6)
		mm.direction = Vector3(dir.x, 0.4, dir.z)
		mm.spread = 40.0
		mm.initial_velocity_min = 0.6
		mm.initial_velocity_max = 1.6 * strength + 0.6
		mm.gravity = Vector3(0, -0.4, 0)
		mm.scale_min = 0.5
		mm.scale_max = 1.2 + strength
		var mg := Gradient.new()
		mg.set_color(0, Color(1, 1, 1, 0.0))
		mg.set_color(1, Color(1, 1, 1, 0.0))
		mg.add_point(0.15, Color(1, 1, 1, 0.55))
		mg.add_point(0.6, Color(1, 1, 1, 0.25))
		var mgt := GradientTexture1D.new()
		mgt.gradient = mg
		mm.color_ramp = mgt
		mist.process_material = mm
		mist.draw_pass_1 = RiverMeshBuilder._mist_quad()
		parent.add_child(mist)
		made += 1
	print("WaterEffects: %d river mouth splashes" % made)


## Droplets thrown up where a waterfall hits its pool.
static func waterfall_splash(foot: Vector3, dir: Vector3, w: float, drop: float, parent: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "WaterfallSplash"
	p.amount = clampi(int(30 + drop * 3.0 + w * 2.0), 30, 120)
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.position = foot + Vector3(0, 0.2, 0)
	p.visibility_range_end = 600.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-w - 8, -2, -w - 8), Vector3(w * 2 + 16, drop * 0.6 + 10, w * 2 + 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.45, 0.1, w * 0.3)
	pm.direction = Vector3(dir.x * 0.4, 1.0, dir.z * 0.4)
	pm.spread = 55.0
	pm.initial_velocity_min = 2.0 + drop * 0.12
	pm.initial_velocity_max = 4.0 + drop * 0.25
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.45
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _drops()
	parent.add_child(p)


static func _drops() -> QuadMesh:
	if _drop_mesh != null:
		return _drop_mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(1, 1)
	_drop_mesh.material = mat
	return _drop_mesh
