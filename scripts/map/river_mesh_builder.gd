class_name RiverMeshBuilder
extends RefCounted
## Draws the rivers of a HexLevel as ribbons that follow the drainage (RiverNetwork).
##
## Each river hex gets a curved ribbon from its centre to the edge it drains through, then on
## to the downstream hex's centre. Where the downstream hex is lower, the ribbon runs off the
## lip and drops as a waterfall. Rivers that reach the sea end a little way into the water.

const SHADER_PATH := "res://shaders/river.gdshader"
## Height of the ribbon above the hex top, in metres (avoids z-fighting).
const LIFT := 0.35

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


static func build(level: HexLevel, noise: BorderNoise, parent: Node3D) -> void:
	if level.river_order.is_empty():
		return
	var data := HexMeshBuilder.MeshData.new()
	var s := level.hex_size
	var fall_offset := 0.3 + 0.04 * s
	## Distance along the river at each cell centre, so the flow texture continues downstream.
	var dist := PackedFloat32Array()
	dist.resize(level.cell_count())

	for i in level.river_order:
		var c := level.cell_center(i)
		var w := level.river_width[i]
		var yi := level.top_y(i) + LIFT
		_add_pool(data, Vector3(c.x, yi - 0.02, c.y), w * 0.45, dist[i])

		var j := level.downstream[i]
		if j < 0:
			continue
		var k := _direction_to(level, i, j)
		if k < 0:
			continue
		var cj := level.cell_center(j)
		var to_sea := HexMapGenerator.is_water(level.terrain[j])
		var yj := level.top_y(j) + (0.2 if to_sea else LIFT)
		var dir := (cj - c).normalized()
		var side := Vector2(-dir.y, dir.x)
		var e := noise.edge_mid(c, s, k)

		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(level.coords[i].x, level.coords[i].y, level.level_index))
		var wob1 := rng.randf_range(-1.0, 1.0) * s * 0.16
		var wob2 := rng.randf_range(-1.0, 1.0) * s * 0.16

		var p_lip := e + dir * fall_offset
		var upper: Array[Vector3] = [
			_v3(c, yi), _v3(c.lerp(e, 0.5) + side * wob1, yi), _v3(e, yi)]
		var lower: Array[Vector3] = []
		if to_sea:
			lower = [_v3(p_lip, yj), _v3(e + dir * s * 0.35, yj)]
		else:
			lower = [_v3(p_lip, yj), _v3(p_lip.lerp(cj, 0.5) + side * wob2, yj), _v3(cj, yj)]

		var d := dist[i]
		if yj < yi - 0.05:
			var top := _chaikin(upper, 2)
			top.append(_v3(p_lip, yi))
			d = _strip(data, top, w, side, d, false)
			var fall: Array[Vector3] = [_v3(p_lip, yi), _v3(p_lip, yj)]
			d = _strip(data, fall, w, side, d, true)
			d = _strip(data, _chaikin(lower, 2), w, side, d, false)
		else:
			# Level or (rarely, after spilling out of a pit) slightly uphill: one smooth ribbon.
			var all: Array[Vector3] = []
			all.append_array(upper)
			all.append_array(lower)
			d = _strip(data, _chaikin(all, 2), w, side, d, false)
		if not to_sea:
			dist[j] = maxf(dist[j], d)

	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = data.to_mesh()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _direction_to(level: HexLevel, i: int, j: int) -> int:
	for k in 6:
		if level.index_of(HexCoords.neighbor(level.coords[i], k)) == j:
			return k
	return -1


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Corner-cutting smoothing that keeps both end points.
static func _chaikin(pts: Array[Vector3], iterations: int) -> Array[Vector3]:
	var out := pts
	for it in iterations:
		var nxt: Array[Vector3] = [out[0]]
		for k in out.size() - 1:
			nxt.append(out[k].lerp(out[k + 1], 0.25))
			nxt.append(out[k].lerp(out[k + 1], 0.75))
		nxt.append(out[out.size() - 1])
		out = nxt
	return out


## Extrudes a polyline into a ribbon `width` wide. Returns the distance at its end.
static func _strip(data: HexMeshBuilder.MeshData, pts: Array[Vector3], width: float, flow_side: Vector2, dist0: float, fall: bool) -> float:
	var n := pts.size()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for k in n:
		var side := flow_side
		if not fall:
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, n - 1)]
			var t := Vector2(b.x - a.x, b.z - a.z)
			if t.length_squared() > 1e-6:
				t = t.normalized()
				side = Vector2(-t.y, t.x)
		var off := Vector3(side.x, 0.0, side.y) * width * 0.5
		lefts.append(pts[k] - off)
		rights.append(pts[k] + off)

	var uv2 := Vector2(1.0 if fall else 0.0, width)
	var nrm := Vector3(flow_side.y, 0.0, -flow_side.x) if fall else Vector3.UP
	var d := dist0
	for k in n - 1:
		var d1 := d + pts[k].distance_to(pts[k + 1])
		data.tri(lefts[k], rights[k], rights[k + 1], Vector2(0.0, d), Vector2(1.0, d), Vector2(1.0, d1), nrm, uv2)
		data.tri(lefts[k], rights[k + 1], lefts[k + 1], Vector2(0.0, d), Vector2(1.0, d1), Vector2(0.0, d1), nrm, uv2)
		d = d1
	return d


## Small hexagonal pool under the ribbon at a hex centre, so bends and confluences have no gaps.
static func _add_pool(data: HexMeshBuilder.MeshData, center: Vector3, radius: float, d: float) -> void:
	var uv := Vector2(0.5, d)
	var uv2 := Vector2(0.0, radius * 2.0)
	for k in 6:
		var a := center + Vector3(cos(k * TAU / 6.0), 0.0, sin(k * TAU / 6.0)) * radius
		var b := center + Vector3(cos((k + 1) * TAU / 6.0), 0.0, sin((k + 1) * TAU / 6.0)) * radius
		data.tri(center, a, b, uv, uv, uv, Vector3.UP, uv2)
