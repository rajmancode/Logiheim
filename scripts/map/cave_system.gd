class_name CaveSystem
extends RefCounted
## Cave systems in the hills, with resources inside.
##
## plan() (finest level, finished terrain): picks hillsides that are steep but not cliffs, well
## above the sea, preferably bare rock, spaced well apart; each becomes a cave system with one
## to three entrances along the same hillside. What's inside depends on where it is: silver,
## gems and iron ore in high rock; iron and coal in the lower hills; on the volcano, lava tubes
## with gems and silver. apply() (every level): cuts a ledge in front of each entrance and
## marks the hexes (`level.cave`). place_resources(): after the open-country resources, gives
## each entrance hex its cave resources (deposit flagged as a cave, so icons say so).
## build_meshes(): the mouths. A height grid can't have holes, so a mouth is a dark, recessed
## arch set into the rock face at the back of the ledge, framed by fractured rock slabs, with a
## few fallen stones in front.

## Each: {entrances: Array of {p: Vector2, dir: Vector2 (outward, downhill)}, kinds: Array[int],
## lava: bool}.
var systems: Array = []
const K := NaturalResources.Kind

static var _mouth_mat: StandardMaterial3D


static func plan(level: HexLevel, surface: TerrainSurface, settings: HexMapSettings) -> CaveSystem:
	var cs := CaveSystem.new()
	if settings.cave_count <= 0:
		return cs
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(6060)
	var relief := maxf(level.max_top_y() - surface.sea_y, 10.0)
	var cands: Array = []
	var stepv := maxi(1, int(10.0 / surface.spacing))
	for z in range(4, surface.nz - 4, stepv):
		for x in range(4, surface.nx - 4, stepv):
			var i := z * surface.nx + x
			var h := surface.heights[i]
			if h < surface.sea_y + 12.0 or surface.river_mask[i] > 0.2 or surface.path_mask[i] > 0.1:
				continue
			var p := Vector2(x, z) * surface.spacing
			if surface.wetland_at(p) > 0.3:
				continue
			var g := RockFeatures._gradient(surface, p)
			var slope := g.length()
			if slope < 0.55 or slope > 1.15:
				continue
			var rock := surface.weight_at(p, HexMapGenerator.Terrain.ROCK)
			var rel := (h - surface.sea_y) / relief
			cands.append([rock + rel * 0.5 + surface.volcanic[i] * 0.4 + rng.randf() * 0.5, p, -g.normalized(), rel, surface.volcanic[i]])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var spacing := 420.0
	for cand in cands:
		if cs.systems.size() >= settings.cave_count:
			break
		var p: Vector2 = cand[1]
		var far := true
		for sy: Dictionary in cs.systems:
			if (sy.entrances[0].p as Vector2).distance_to(p) < spacing:
				far = false
				break
		if not far:
			continue
		var entrances := [{"p": p, "dir": cand[2]}]
		# More mouths of the same system along the hillside.
		for c2 in cands:
			if entrances.size() >= 1 + rng.randi_range(0, 2):
				break
			var q: Vector2 = c2[1]
			var d := q.distance_to(p)
			if d < 60.0 or d > 220.0:
				continue
			var ok := true
			for e: Dictionary in entrances:
				if (e.p as Vector2).distance_to(q) < 60.0:
					ok = false
			if ok:
				entrances.append({"p": q, "dir": c2[2]})
		var rel: float = cand[3]
		var lava: bool = cand[4] > 0.5
		var kinds: Array = []
		if lava:
			kinds = [K.GEMS, K.SILVER]
		elif rel > 0.5:
			kinds = [[K.SILVER, K.GEMS], [K.SILVER, K.IRON], [K.GEMS, K.IRON]][rng.randi() % 3]
		else:
			kinds = [[K.IRON, K.COAL], [K.COAL, K.SOAPSTONE], [K.IRON, K.SILVER]][rng.randi() % 3]
		cs.systems.append({"entrances": entrances, "kinds": kinds, "lava": lava})
	print("CaveSystem: %d systems, %d entrances" % [cs.systems.size(), cs.systems.reduce(func(a, s): return a + s.entrances.size(), 0)])
	return cs


## Cuts a ledge in front of each mouth and marks the entrance hexes.
func apply(level: HexLevel, surface: TerrainSurface) -> void:
	if level.cave.size() != level.cell_count():
		level.cave.resize(level.cell_count())
	level.cave.fill(-1)
	for si in systems.size():
		for e: Dictionary in systems[si].entrances:
			var p: Vector2 = e.p
			var dir: Vector2 = e.dir
			var cell := level.cell_at(p)
			if cell >= 0:
				level.cave[cell] = si
			# A small ledge in front of the mouth only: the hillside behind stays as the rock
			# face the mouth opens into.
			var floor_y := surface.sample(p) - 0.5
			var r := 9.0
			var x0 := maxi(0, floori((p.x - r) / surface.spacing))
			var x1 := mini(surface.nx - 1, ceili((p.x + r) / surface.spacing))
			var z0 := maxi(0, floori((p.y - r) / surface.spacing))
			var z1 := mini(surface.nz - 1, ceili((p.y + r) / surface.spacing))
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var q := Vector2(x, z) * surface.spacing
					var rel := q - p
					var ahead := rel.dot(dir)
					if ahead < -1.0 or rel.length() > r:
						continue
					var i := z * surface.nx + x
					var t := (1.0 - smoothstep(r * 0.5, r, rel.length())) * smoothstep(-1.0, 1.5, ahead)
					surface.heights[i] = lerpf(surface.heights[i], minf(surface.heights[i], floor_y), t)
					surface.clear_mask[i] = 1


## After the open-country resources: each entrance hex holds the system's cave resources.
func place_resources(levels: Array[HexLevel]) -> void:
	if systems.is_empty() or levels.is_empty():
		return
	var lv := levels[0]
	for si in systems.size():
		var kinds: Array = systems[si].kinds
		for e: Dictionary in systems[si].entrances:
			var cell := lv.cell_at(e.p)
			if cell < 0:
				continue
			lv.resource[cell] = kinds[0]
			lv.resource_amount[cell] = 3
			if lv.resource2.size() == lv.cell_count():
				lv.resource2[cell] = kinds[1] if kinds.size() > 1 else 0
			lv.deposit[cell] = lv.deposits.size()
			lv.deposits.append({"kind": kinds[0], "center": cell, "size": 1, "cave": true})
			# Coarser levels: the cave shows on the hex that contains it.
			var c := cell
			for li in range(1, levels.size()):
				c = levels[li - 1].parent[c]
				if c < 0:
					break
				var up := levels[li]
				up.resource[c] = kinds[0]
				up.resource_amount[c] = 3
				up.deposits.append({"kind": kinds[0], "center": c, "size": 1, "cave": true})


## The cave mouths: a dark recessed arch, a frame of rock slabs, fallen stones.
func build_meshes(surface: TerrainSurface, parent: Node3D) -> void:
	if systems.is_empty():
		return
	var mouths := MeshData.new()
	var items: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(6161)
	for sy: Dictionary in systems:
		for e: Dictionary in sy.entrances:
			var p: Vector2 = e.p
			var dir: Vector2 = e.dir
			var side := Vector2(-dir.y, dir.x)
			var floor_y := surface.sample(p + dir * 2.0) + 0.1
			var w := rng.randf_range(4.5, 7.0)
			var h := rng.randf_range(4.0, 6.0)
			var back := p - dir * 0.5
			_mouth(mouths, Vector3(back.x, floor_y, back.y), dir, side, w, h)
			var basalt := surface.volcanic_at(p)
			# Frame: slabs around the arch.
			for k in 7:
				var a := PI * (float(k) / 6.0)
				var off := side * cos(a) * (w * 0.62) + dir * rng.randf_range(0.2, 1.2)
				var pos := Vector3(back.x + off.x, floor_y + sin(a) * h * 1.02 + 0.5, back.y + off.y)
				# Never above the hillside around it: frame stones sit on or in the ground.
				pos.y = minf(pos.y, surface.sample(Vector2(pos.x, pos.z)) + size_hint(sin(a), h))
				var size := rng.randf_range(2.5, 4.5)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.7, 1.1), size))
				_add(items, ["rock_a", "rock_c", "rock_e"][rng.randi() % 3], Transform3D(basis, pos), Color(1, 1, 1, basalt))
			# Fallen stones on the ledge.
			for k in rng.randi_range(2, 4):
				var q := p + dir * rng.randf_range(3.0, 8.0) + side * rng.randf_range(-w, w)
				var size := rng.randf_range(0.8, 2.0)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
				_add(items, ["rock_b", "rock_d"][rng.randi() % 2], Transform3D(basis, Vector3(q.x, surface.ground_min(q, size * 0.6) - size * 0.1, q.y)), Color(1, 1, 1, basalt))
	var mi := MeshInstance3D.new()
	mi.name = "CaveMouths"
	mi.mesh = mouths.to_mesh()
	mi.material_override = _mouth_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	for model: String in items:
		var m := Vegetation.mesh(model)
		if m == null:
			continue
		var data: Array = items[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = data[0].size()
		for j in data[0].size():
			mm.set_instance_transform(j, data[0][j])
			mm.set_instance_custom_data(j, data[1][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "CaveRocks_" + model
		mmi.multimesh = mm
		parent.add_child(mmi)


## A recessed arch: a half-dome opening facing `dir`, black deep inside, dark grey at the rim.
static func _mouth(data: MeshData, base: Vector3, dir: Vector2, side: Vector2, w: float, h: float) -> void:
	const SEG := 12
	const RINGS := 4
	var out := Vector3(dir.x, 0, dir.y)
	var sd := Vector3(side.x, 0, side.y)
	var rim: Array[Vector3] = []
	for k in SEG + 1:
		var a := PI * float(k) / SEG
		rim.append(base + sd * cos(a) * w * 0.5 + Vector3.UP * sin(a) * h + out * 0.6)
	var deep := base - out * 5.0 + Vector3.UP * h * 0.3
	var prev := rim
	for r in range(1, RINGS + 1):
		var t := float(r) / RINGS
		var ring: Array[Vector3] = []
		for k in SEG + 1:
			ring.append(rim[k].lerp(deep, t))
		for k in SEG:
			var c0 := Color(0.1, 0.09, 0.08) * (1.0 - (t - 1.0 / RINGS))
			var c1 := Color(0.1, 0.09, 0.08) * (1.0 - t)
			var col := c0.lerp(c1, 0.5)
			data.tri(prev[k], prev[k + 1], ring[k + 1], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, col)
			data.tri(prev[k], ring[k + 1], ring[k], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, col)
		prev = ring
	# Floor of the opening.
	data.tri(rim[0], rim[SEG], deep - Vector3.UP * h * 0.3, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO, Color(0.06, 0.05, 0.045))


## How far a frame stone may stand above the ground: the top of the arch rises clear, the
## sides hug the slope.
static func size_hint(up: float, h: float) -> float:
	return 1.0 + up * h * 0.6


static func _mouth_material() -> StandardMaterial3D:
	if _mouth_mat == null:
		_mouth_mat = StandardMaterial3D.new()
		_mouth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mouth_mat.vertex_color_use_as_albedo = true
		_mouth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mouth_mat


static func _add(items: Dictionary, model: String, xform: Transform3D, custom: Color) -> void:
	if not items.has(model):
		items[model] = [[], []]
	items[model][0].append(xform)
	items[model][1].append(custom)
