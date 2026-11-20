class_name Floodplain
extends RefCounted
## Floodplains: the flat, low land beside big rivers that goes under water when they flood.
##
## Found per level from the placed rivers: ground near a river at least `floodplain_min_width`
## wide and no more than `floodplain_depth` above its water. That land is levelled into a flat
## valley floor, gets lush meadow and silt and a few oxbow ponds. When it rains the terrain
## shader floods it: each vertex carries its floodplain strength and river level, and water is
## painted wherever the ground lies below river level + `flood` x depth (global shader
## parameter `flood`, driven by Atmosphere), so the flood spreads from the river outwards.

var level_index := 0
## World pond list: [Vector2 centre, Vector2 radii, float angle, float water y].
var ponds: Array = []


static func build(level: HexLevel, surface: TerrainSurface, paths: Array[RiverPath], settings: HexMapSettings) -> Floodplain:
	var fp := Floodplain.new()
	fp.level_index = level.level_index
	level.floodplain.fill(0)
	if paths.is_empty() or not settings.floodplains_enabled:
		return fp
	var mask := surface.flood_mask
	var fy := surface.flood_y
	var sp := surface.spacing

	# 1. Mask: near a big river and only a little above its water.
	for path in paths:
		var next_at := -INF
		for k in path.points.size():
			var w := path.widths[k]
			if w < settings.floodplain_min_width:
				continue
			var reach := clampf(w * settings.floodplain_reach, 30.0, 260.0)
			if path.dist[k] < next_at:
				continue
			next_at = path.dist[k] + reach * 0.3
			var pt := path.points[k]
			var x0 := maxi(0, floori((pt.x - reach) / sp))
			var x1 := mini(surface.nx - 1, ceili((pt.x + reach) / sp))
			var z0 := maxi(0, floori((pt.z - reach) / sp))
			var z1 := mini(surface.nz - 1, ceili((pt.z + reach) / sp))
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var d := Vector2(gx * sp - pt.x, gz * sp - pt.z).length()
					if d > reach:
						continue
					var i := gz * surface.nx + gx
					var rise := surface.heights[i] - pt.y
					if rise > settings.floodplain_depth or rise < -0.5 or surface.heights[i] < surface.sea_y + 0.3:
						continue
					var m := (1.0 - smoothstep(settings.floodplain_depth * 0.35, settings.floodplain_depth, rise)) * (1.0 - smoothstep(reach * 0.55, reach, d))
					if m > mask[i]:
						mask[i] = m
						fy[i] = pt.y

	# 2. Level it into a flat valley floor (only lowers bumps, never raises).
	for i in mask.size():
		if mask[i] <= 0.0:
			continue
		var floor_y := fy[i] + 0.9
		if surface.heights[i] > floor_y and surface.river_mask[i] < 0.5:
			surface.heights[i] = lerpf(surface.heights[i], floor_y, mask[i] * 0.75)

	# 3. Oxbow ponds: a few shallow, elongated hollows on the floor, away from the river.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + level.level_index
	var area_cells := 0
	for i in mask.size():
		if mask[i] > 0.7:
			area_cells += 1
	var want := int(area_cells * sp * sp / settings.floodplain_pond_every)
	var tries := 0
	while fp.ponds.size() < want and tries < want * 30:
		tries += 1
		var i := rng.randi() % mask.size()
		if mask[i] < 0.75 or surface.river_mask[i] > 0.05:
			continue
		var c := Vector2((i % surface.nx) * sp, (i / surface.nx) * sp)
		var r := Vector2(rng.randf_range(10.0, 22.0), rng.randf_range(4.0, 8.0)) * maxf(1.0, level.hex_size / 20.0)
		var clash := false
		for p in fp.ponds:
			if (p[0] as Vector2).distance_to(c) < 80.0:
				clash = true
		if clash or surface.keep_clear(c):
			continue
		var ang := rng.randf() * PI
		var water := fy[i] + 0.5
		fp.ponds.append([c, r, ang, water])
		_dig_pond(surface, c, r, ang, water)

	# 4. Hex flags.
	for i in level.cell_count():
		if surface_mask_at(surface, level.cell_center(i)) > 0.35:
			level.floodplain[i] = 1
	return fp


static func surface_mask_at(surface: TerrainSurface, p: Vector2) -> float:
	var x := clampi(roundi(p.x / surface.spacing), 0, surface.nx - 1)
	var z := clampi(roundi(p.y / surface.spacing), 0, surface.nz - 1)
	return surface.flood_mask[z * surface.nx + x]


static func _dig_pond(surface: TerrainSurface, c: Vector2, r: Vector2, ang: float, water: float) -> void:
	var sp := surface.spacing
	var reach := r.x + sp * 2.0
	var ax := Vector2(cos(ang), sin(ang))
	var ay := Vector2(-ax.y, ax.x)
	for gz in range(maxi(0, floori((c.y - reach) / sp)), mini(surface.nz - 1, ceili((c.y + reach) / sp)) + 1):
		for gx in range(maxi(0, floori((c.x - reach) / sp)), mini(surface.nx - 1, ceili((c.x + reach) / sp)) + 1):
			var d := Vector2(gx * sp, gz * sp) - c
			var e := Vector2(d.dot(ax) / r.x, d.dot(ay) / r.y).length()
			if e > 1.4:
				continue
			var i := gz * surface.nx + gx
			var bed := water - 1.4 * (1.0 - smoothstep(0.0, 1.0, e))
			var target := lerpf(bed, surface.heights[i], smoothstep(0.85, 1.4, e))
			surface.heights[i] = minf(surface.heights[i], target)
			if e < 1.15:
				surface.river_mask[i] = maxf(surface.river_mask[i], 0.6)
				surface.clear_mask[i] = 1


## Water in the oxbow ponds (lake shader). The flood itself is drawn by the terrain shader.
func build_meshes(pond_material: Material, parent: Node3D) -> void:
	if not ponds.is_empty():
		var data := MeshData.new()
		for p in ponds:
			var c: Vector2 = p[0]
			var r: Vector2 = p[1] * 1.25
			var ang: float = p[2]
			var y: float = p[3]
			var ax := Vector2(cos(ang), sin(ang))
			var ay := Vector2(-ax.y, ax.x)
			var mid := Vector3(c.x, y, c.y)
			for k in 16:
				var a0 := k * TAU / 16.0
				var a1 := (k + 1) * TAU / 16.0
				var p0 := c + ax * cos(a0) * r.x + ay * sin(a0) * r.y
				var p1 := c + ax * cos(a1) * r.x + ay * sin(a1) * r.y
				data.tri(mid, Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO)
		var mi := MeshInstance3D.new()
		mi.name = "Ponds"
		mi.mesh = data.to_mesh()
		mi.material_override = pond_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
