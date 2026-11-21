class_name RockFeatures
extends RefCounted
## Overhangs and talus. A height grid can't hang over itself, so overhangs are rock: wide,
## flat, fractured slabs (the Blender boulders, stretched) set into the crest of the steepest
## slopes and jutting out over them, like a ledge of harder rock the slope below has worn back
## from. Below each, the rock that has already fallen: a spill of boulders at the foot.
## Uses the boulder shader (photo-scanned rock, moss on top; basalt near the volcano).

const SLABS := ["rock_d", "rock_e", "rock_b"]
const BOULDERS := ["rock_a", "rock_b", "rock_c", "rock_e"]


static func build(level: HexLevel, surface: TerrainSurface, settings: HexMapSettings, parent: Node3D) -> void:
	if settings.overhang_spacing <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + level.level_index
	var cap := maxf(settings.max_slope, 0.3)
	var grid := maxi(1, int(8.0 / surface.spacing))
	# Crest candidates: as steep as the ground may get, on the convex upper edge.
	var cands: Array = []
	for z in range(2, surface.nz - 2, grid):
		for x in range(2, surface.nx - 2, grid):
			var i := z * surface.nx + x
			var h := surface.heights[i]
			if h < surface.sea_y + 4.0 or surface.river_mask[i] > 0.3 or surface.path_mask[i] > 0.1:
				continue
			var p := Vector2(x, z) * surface.spacing
			var g := _gradient(surface, p)
			var slope := g.length()
			if slope < cap * 0.75 or surface.convexity[i] < 0.12:
				continue
			cands.append([slope + surface.convexity[i] + rng.randf() * 0.3, p, g])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var spacing := settings.overhang_spacing * (1.0 + level.level_index)
	var picked: Array = []
	var items: Dictionary = {}
	for cand in cands:
		var p: Vector2 = cand[1]
		var close := false
		for q: Vector2 in picked:
			if q.distance_squared_to(p) < spacing * spacing:
				close = true
				break
		if close:
			continue
		picked.append(p)
		var g: Vector2 = cand[2]
		var down := -g.normalized()
		var along := Vector2(-down.y, down.x)
		var crest := surface.sample(p)
		var basalt := surface.volcanic_at(p)
		# A ledge of two or three slabs along the crest, deep enough to jut well out over the
		# slope, each a little tilted and offset like a broken band of harder rock.
		var wide := rng.randf_range(16.0, 28.0)
		var x_axis := Vector3(down.x, 0, down.y)
		var z_axis := Vector3(along.x, 0, along.y)
		for s in rng.randi_range(2, 3):
			var off := along * (s - 1) * wide * 0.7 + down * rng.randf_range(-2.0, 2.0)
			var q := p + off
			var deep := rng.randf_range(12.0, 20.0)
			var thick := rng.randf_range(4.0, 8.0)
			var top := surface.sample(q)
			var basis := Basis(x_axis * deep, Vector3.UP * thick * 2.8, z_axis * wide * rng.randf_range(0.75, 1.1))
			basis = Basis(z_axis, rng.randf_range(-0.14, 0.04)) * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)) * basis
			var pos := Vector3(q.x, top - thick * 0.4, q.y) + x_axis * deep * 0.25
			_add(items, SLABS[rng.randi() % SLABS.size()], Transform3D(basis, pos), Color(1, 1, 1, basalt))
		# Talus: walk downhill to where the slope eases, scatter fallen boulders there.
		var foot := p
		for s in 25:
			var q := foot + down * 3.0
			if _gradient(surface, q).length() < 0.45 or surface.sample(q) < surface.sea_y:
				break
			foot = q
		for b in rng.randi_range(3, 6):
			var bp := foot + down * rng.randf_range(0.0, 10.0) + along * rng.randf_range(-wide * 0.6, wide * 0.6)
			if surface.sample(bp) < surface.sea_y - 0.3 or surface.river_at(bp) > 0.3:
				continue
			var size := rng.randf_range(1.5, 5.0)
			var bb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * rng.randf_range(0.8, 1.3), size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.8, 1.3)))
			_add(items, BOULDERS[rng.randi() % BOULDERS.size()], Transform3D(bb, Vector3(bp.x, surface.sample(bp) - size * 0.15, bp.y)), Color(1, 1, 1, surface.volcanic_at(bp)))
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
		mmi.name = "Overhangs_" + model
		mmi.multimesh = mm
		parent.add_child(mmi)
	print("RockFeatures: level %d, %d overhangs" % [level.level_index, picked.size()])


## Uphill gradient (rise/run) of the ground at p.
static func _gradient(surface: TerrainSurface, p: Vector2) -> Vector2:
	var e := surface.spacing
	return Vector2(surface.sample(p + Vector2(e, 0)) - surface.sample(p - Vector2(e, 0)),
		surface.sample(p + Vector2(0, e)) - surface.sample(p - Vector2(0, e))) / (2.0 * e)


static func _add(items: Dictionary, model: String, xform: Transform3D, custom: Color) -> void:
	if not items.has(model):
		items[model] = [[], []]
	items[model][0].append(xform)
	items[model][1].append(custom)
