class_name RiverMeshBuilder
extends RefCounted
## Turns the river hexes of a level (RiverNetwork) into smooth river paths, then into ribbons.
##
## 1. compute_paths(): one path per river hex, from its centre through the shared border to the
##    downstream hex's centre (or out into the sea). Paths are smoothed and resampled, and the
##    water level along them never rises downstream, so rivers cut gorges through ridges
##    instead of flowing uphill.
## 2. TerrainSurface.carve() digs the channels using those paths.
## 3. build(): the water ribbons, with foam where the river runs steeply.

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


static func depth_for(width: float) -> float:
	return clampf(width * 0.35, 0.6, 3.5)


static func compute_paths(level: HexLevel, surface: TerrainSurface) -> Array[RiverPath]:
	var paths: Array[RiverPath] = []
	if level.river_order.is_empty():
		return paths
	var s := level.hex_size
	var n := level.cell_count()

	# Water level at each river hex centre, never higher than anything upstream.
	var cap := PackedFloat32Array()
	cap.resize(n)
	cap.fill(INF)
	var wy := PackedFloat32Array()
	wy.resize(n)
	var dist := PackedFloat32Array()
	dist.resize(n)
	for i in level.river_order:
		var c := level.cell_center(i)
		var base := surface.sample(c) - depth_for(level.river_width[i]) * 0.3
		wy[i] = maxf(minf(base, cap[i]), surface.sea_y + 0.05)
		var d := level.downstream[i]
		if d >= 0:
			cap[d] = minf(cap[d], wy[i])

	for i in level.river_order:
		var j := level.downstream[i]
		if j < 0:
			continue
		var c := level.cell_center(i)
		var cj := level.cell_center(j)
		var to_sea := HexMapGenerator.is_water(level.terrain[j])
		var dir := (cj - c).normalized()
		var side := Vector2(-dir.y, dir.x)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(level.coords[i].x, level.coords[i].y, level.level_index))
		var e := (c + cj) * 0.5 + side * rng.randf_range(-1.0, 1.0) * s * 0.12
		var ctrl := PackedVector2Array([c, c.lerp(e, 0.5) + side * rng.randf_range(-1.0, 1.0) * s * 0.18, e])
		if to_sea:
			ctrl.append(e + dir * s * 0.7)
		else:
			ctrl.append(e.lerp(cj, 0.5) + side * rng.randf_range(-1.0, 1.0) * s * 0.18)
			ctrl.append(cj)
		var smooth := _chaikin(ctrl, 3)

		var w0 := level.river_width[i]
		var w1 := w0 if to_sea else level.river_width[j]
		var y_hi := wy[i]
		var y_lo := surface.sea_y + 0.05 if to_sea else wy[j]
		var step := clampf(w0 * 0.4, 0.5, surface.spacing)
		var path := RiverPath.new()
		path.to_sea = to_sea
		var along := dist[i]
		var prev_y := y_hi
		var prev := smooth[0]
		for k in smooth.size() - 1:
			var a := smooth[k]
			var b := smooth[k + 1]
			var seg := a.distance_to(b)
			var count := maxi(1, ceili(seg / step))
			for m in count:
				var p := a.lerp(b, float(m) / count)
				along += p.distance_to(prev)
				prev = p
				var t := float(path.points.size()) / maxf(1.0, smooth.size() * 2.0)
				var w := lerpf(w0, (w0 + w1) * 0.5, clampf(t, 0.0, 1.0))
				var y := surface.sample(p) - depth_for(w) * 0.3
				y = clampf(y, y_lo, prev_y)
				prev_y = y
				path.points.append(Vector3(p.x, y, p.y))
				path.widths.append(w)
				path.dist.append(along)
		var last := smooth[smooth.size() - 1]
		along += last.distance_to(prev)
		path.points.append(Vector3(last.x, y_lo, last.y))
		path.widths.append(w1 if not to_sea else w0)
		path.dist.append(along)
		if not to_sea:
			dist[j] = maxf(dist[j], along)
		paths.append(path)
	return paths


static func build(paths: Array[RiverPath], parent: Node3D) -> void:
	if paths.is_empty():
		return
	var data := MeshData.new()
	for path in paths:
		_ribbon(data, path)
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = data.to_mesh()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _ribbon(data: MeshData, path: RiverPath) -> void:
	var n := path.points.size()
	if n < 2:
		return
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	var steep := PackedFloat32Array()
	for k in n:
		var a := path.points[maxi(k - 1, 0)]
		var b := path.points[mini(k + 1, n - 1)]
		var t := Vector2(b.x - a.x, b.z - a.z)
		var run := maxf(t.length(), 0.001)
		t /= run
		var side := Vector3(-t.y, 0.0, t.x) * path.widths[k] * 0.5
		var lift := Vector3(0.0, 0.05, 0.0)
		lefts.append(path.points[k] - side + lift)
		rights.append(path.points[k] + side + lift)
		steep.append(clampf((a.y - b.y) / run * 2.5, 0.0, 1.0))
	for k in n - 1:
		var d0 := path.dist[k]
		var d1 := path.dist[k + 1]
		var la := lefts[k]
		var ra := rights[k]
		var lb := lefts[k + 1]
		var rb := rights[k + 1]
		var nrm := (rb - la).cross(ra - la).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var uv2a := Vector2(steep[k], path.widths[k])
		data.tri(la, ra, rb, Vector2(0.0, d0), Vector2(1.0, d0), Vector2(1.0, d1), nrm, uv2a)
		data.tri(la, rb, lb, Vector2(0.0, d0), Vector2(1.0, d1), Vector2(0.0, d1), nrm, uv2a)
	# Round pool at the start so joints and confluences have no gaps.
	var c := path.points[0] + Vector3(0.0, 0.04, 0.0)
	var r := path.widths[0] * 0.5
	for k in 8:
		var a := c + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * r
		var b := c + Vector3(cos((k + 1) * TAU / 8.0), 0.0, sin((k + 1) * TAU / 8.0)) * r
		data.tri(c, a, b, Vector2(0.5, path.dist[0]), Vector2(0.5, path.dist[0]), Vector2(0.5, path.dist[0]), Vector3.UP, Vector2(0.0, r * 2.0))


static func _chaikin(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var out := pts
	for it in iterations:
		var nxt := PackedVector2Array([out[0]])
		for k in out.size() - 1:
			nxt.append(out[k].lerp(out[k + 1], 0.25))
			nxt.append(out[k].lerp(out[k + 1], 0.75))
		nxt.append(out[out.size() - 1])
		out = nxt
	return out
