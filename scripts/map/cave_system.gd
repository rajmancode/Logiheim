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
## arch set into the back wall of an alcove cut into the hillside (apply()), opening from an
## outcrop of big, half-buried rock round and over it, on bare rock ground, with a few fallen
## stones in front.

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
			# The mouth is set into the hill: an alcove cut back into the slope (its back wall is
			# the face the cave opens from), with a smooth apron in front of it. The ground all
			# round turns to bare rock.
			var floor_y := surface.sample(p) - 0.5
			var side := Vector2(-dir.y, dir.x)
			var reach := 22.0
			var x0 := maxi(0, floori((p.x - reach) / surface.spacing))
			var x1 := mini(surface.nx - 1, ceili((p.x + reach) / surface.spacing))
			var z0 := maxi(0, floori((p.y - reach) / surface.spacing))
			var z1 := mini(surface.nz - 1, ceili((p.y + reach) / surface.spacing))
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					var q := Vector2(x, z) * surface.spacing
					var rel := q - p
					var ahead := rel.dot(dir)
					var lat := absf(rel.dot(side))
					var i := z * surface.nx + x
					# Alcove: from 6 m into the hill out to the apron, ~14 m wide, wider at the front.
					var half_w := 6.0 + maxf(ahead, 0.0) * 0.4
					var t := (1.0 - smoothstep(half_w - 2.0, half_w + 3.0, lat)) \
						* smoothstep(-7.5, -4.5, ahead) * (1.0 - smoothstep(9.0, 16.0, ahead))
					if t > 0.0:
						surface.heights[i] = lerpf(surface.heights[i], minf(surface.heights[i], floor_y + maxf(ahead, 0.0) * 0.08), t)
						surface.clear_mask[i] = 1
					# Behind and above the mouth, a knoll of rock at least as high as the opening
					# plus its lintel: the face backs onto solid ground and the dark tunnel stays
					# inside the hill (never seen from above).
					var kt := (1.0 - smoothstep(half_w + 1.0, half_w + 7.0, lat)) * smoothstep(-18.0, -12.0, ahead) 						* (1.0 - smoothstep(-8.5, -6.5, ahead))
					if kt > 0.0:
						var top := floor_y + 7.5 + (BorderNoise.snoise(q * 0.15) - 0.5) * 1.5
						surface.heights[i] = maxf(surface.heights[i], lerpf(surface.heights[i], top, kt))
					var d := rel.length()
					if d < reach:
						surface.rock_boost[i] = maxf(surface.rock_boost[i], 1.0 - smoothstep(8.0, reach, d))


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


# --------------------------------------------------------------------------- interiors

## Prop model for each cave resource.
const CAVE_PROPS := {
	K.IRON: "outcrop_iron", K.SILVER: "outcrop_silver", K.GEMS: "crystals",
	K.COAL: "outcrop_coal", K.SOAPSTONE: "outcrop_soapstone",
}


## Where a tunnel starts just inside a mouth (matches build_meshes()).
static func _mouth_point(surface: TerrainSurface, e: Dictionary) -> Vector3:
	var p: Vector2 = e.p
	var dir: Vector2 = e.dir
	var back := p - dir * 1.0
	return Vector3(back.x, surface.sample(p + dir * 2.0) + 2.4, back.y)


## The explorable inside of every cave system, built under the hills (finest level only):
## chambers joined by winding tunnels to every entrance, stalactites and stalagmites, the
## system's resources on the chamber floors, and lights. Each system is its own hidden node;
## HexMap.enter_cave() shows one. Walls face inwards, so from outside (the camera stays above
## the floor, outside the rock) you see straight in, like a cutaway.
func build_interiors(surface: TerrainSurface, parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(6262)
	for si in systems.size():
		var sy: Dictionary = systems[si]
		var node := Node3D.new()
		node.name = "CaveInterior_%d" % si
		node.visible = false
		parent.add_child(node)
		var e0: Dictionary = sy.entrances[0]
		var in0 := -(e0.dir as Vector2)
		var m0 := _mouth_point(surface, e0)
		# Chambers, leading on into the hill.
		var chambers: Array = []
		var c := Vector2(m0.x, m0.z) + in0 * rng.randf_range(30.0, 42.0)
		var y := minf(m0.y - rng.randf_range(5.0, 9.0), surface.sample(c) - 16.0)
		var heading := in0
		for k in rng.randi_range(2, 4):
			var rad := Vector3(rng.randf_range(9.0, 15.0), rng.randf_range(5.0, 8.0), rng.randf_range(9.0, 15.0))
			chambers.append({"c": Vector3(c.x, y, c.y), "r": rad, "open": []})
			heading = heading.rotated(rng.randf_range(-1.1, 1.1))
			c += heading * rng.randf_range(30.0, 42.0)
			y = minf(y + rng.randf_range(-7.0, 3.0), surface.sample(c) - 16.0)
		# Tunnels: from every mouth to the nearest chamber, and chamber to chamber.
		var tunnels: Array = []
		for e: Dictionary in sy.entrances:
			var m := _mouth_point(surface, e)
			var best := 0
			for k in chambers.size():
				if Vector2(m.x, m.z).distance_to(Vector2(chambers[k].c.x, chambers[k].c.z)) < Vector2(m.x, m.z).distance_to(Vector2(chambers[best].c.x, chambers[best].c.z)):
					best = k
			var start := m
			var lead := Vector3(-(e.dir as Vector2).x, -0.15, -(e.dir as Vector2).y)
			tunnels.append(_tunnel(start, lead, chambers[best], surface, rng, true))
		for k in range(1, chambers.size()):
			var a: Dictionary = chambers[k - 1]
			var b: Dictionary = chambers[k]
			var toward := ((b.c as Vector3) - (a.c as Vector3))
			toward.y = 0.0
			toward = toward.normalized()
			var start: Vector3 = (a.c as Vector3) + toward * minf(a.r.x, a.r.z) * 0.8 - Vector3.UP * a.r.y * 0.25
			a.open.append(toward)
			tunnels.append(_tunnel(start, toward, b, surface, rng, false))
		# Geometry.
		var g := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
		var floor_pts := PackedVector3Array()
		for t: Array in tunnels:
			_tube(t[0], t[1], g)
			for q in t[0]:
				floor_pts.append(q - Vector3.UP * t[1] * 0.55)
		for ch: Dictionary in chambers:
			_chamber(ch, g)
			floor_pts.append((ch.c as Vector3) - Vector3.UP * ch.r.y * 0.5)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var walls := MeshInstance3D.new()
		walls.name = "Walls"
		walls.mesh = mesh
		walls.material_override = Vegetation._material("Rock")
		node.add_child(walls)
		# Stalactites and stalagmites.
		var drips := MeshData.new()
		for ch: Dictionary in chambers:
			var cc: Vector3 = ch.c
			var r: Vector3 = ch.r
			for k in rng.randi_range(10, 18):
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.1, 0.75)
				var x := cc.x + cos(a) * r.x * d
				var z := cc.z + sin(a) * r.z * d
				var len := rng.randf_range(1.0, 3.5)
				var w := rng.randf_range(0.25, 0.6)
				var top := cc.y + r.y * sqrt(maxf(1.0 - d * d, 0.05)) * 0.8
				var bottom := cc.y - r.y * 0.5
				if rng.randf() < 0.55:
					_cone(drips, Vector3(x, top + 0.3, z), Vector3(x, top - len, z), w)
				else:
					_cone(drips, Vector3(x, bottom - 0.2, z), Vector3(x, bottom + len * 0.8, z), w * 1.2)
		var dm := MeshInstance3D.new()
		dm.name = "Formations"
		dm.mesh = drips.to_mesh()
		dm.material_override = Vegetation._material("Rock")
		node.add_child(dm)
		# Resources on the chamber floors, and lights.
		var items: Dictionary = {}
		for ch: Dictionary in chambers:
			var cc: Vector3 = ch.c
			var r: Vector3 = ch.r
			for kind: int in sy.kinds:
				var model: String = CAVE_PROPS.get(kind, "")
				if model == "":
					continue
				for k in rng.randi_range(1, 3):
					var a := rng.randf() * TAU
					var d := rng.randf_range(0.15, 0.55)
					var pos := Vector3(cc.x + cos(a) * r.x * d, cc.y - r.y * 0.5, cc.z + sin(a) * r.z * d)
					var size := rng.randf_range(0.8, 1.3)
					_add(items, model, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), pos), Color.WHITE)
				if kind == K.GEMS:
					var glow := OmniLight3D.new()
					glow.light_color = Color(0.5, 0.6, 1.0)
					glow.light_energy = 2.0
					glow.omni_range = maxf(r.x, r.z) * 1.2
					glow.position = cc - Vector3.UP * r.y * 0.3
					node.add_child(glow)
			var torch := OmniLight3D.new()
			torch.light_color = Color(1.0, 0.72, 0.45)
			torch.light_energy = 3.0
			torch.omni_range = maxf(r.x, r.z) * 2.4
			torch.position = cc + Vector3.UP * r.y * 0.2
			node.add_child(torch)
		for t: Array in tunnels:
			var path: PackedVector3Array = t[0]
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.7, 0.45)
			lamp.light_energy = 1.6
			lamp.omni_range = 14.0
			lamp.position = path[path.size() / 2]
			node.add_child(lamp)
		for model: String in items:
			var m := ResourceProps._mesh(model)
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
			mmi.multimesh = mm
			node.add_child(mmi)
		var box := AABB((chambers[0].c as Vector3), Vector3.ZERO)
		for q in floor_pts:
			box = box.expand(q)
		sy["interior"] = node
		sy["floor"] = floor_pts
		sy["view"] = (chambers[0].c as Vector3) - Vector3.UP * chambers[0].r.y * 0.5
		sy["bounds"] = box.grow(15.0)


## A winding tunnel from `start` (heading `lead`) into chamber `to`; returns [path, radius].
func _tunnel(start: Vector3, lead: Vector3, to: Dictionary, surface: TerrainSurface, rng: RandomNumberGenerator, from_mouth: bool) -> Array:
	var cc: Vector3 = to.c
	var toward := start - cc
	toward.y = 0.0
	toward = toward.normalized()
	var end: Vector3 = cc + toward * minf(to.r.x, to.r.z) * 0.8 - Vector3.UP * to.r.y * 0.25
	to.open.append(toward)
	var radius := rng.randf_range(2.6, 3.6)
	var a := start + lead.normalized() * 6.0
	var mid := a.lerp(end, 0.5) + Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-8.0, 8.0))
	var ctrl := [start, a, mid, end]
	var path := PackedVector3Array()
	var total := 0.0
	for k in ctrl.size() - 1:
		total += (ctrl[k] as Vector3).distance_to(ctrl[k + 1])
	var steps := maxi(8, int(total / 2.0))
	for k in steps + 1:
		var t := float(k) / steps * (ctrl.size() - 1)
		var i := mini(int(t), ctrl.size() - 2)
		var f := t - i
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)
		# Stay inside the hill (except right at the mouth).
		if not from_mouth or k * 2.0 > 6.0:
			q.y = minf(q.y, surface.sample(Vector2(q.x, q.z)) - radius - 2.0)
		path.append(q)
	return [path, radius]


## A tube along `path`, walls facing inwards, a flat floor, a lumpy rock surface.
static func _tube(path: PackedVector3Array, radius: float, g: Dictionary) -> void:
	const SIDES := 14
	var base: int = (g.v as PackedVector3Array).size()
	var n := path.size()
	for k in n:
		var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var up := side.cross(t).normalized()
		var r := radius * (0.85 + 0.3 * BorderNoise.snoise(Vector2(k * 0.25, radius * 3.0)))
		var floor_y := path[k].y - r * 0.55
		for j in SIDES:
			var a := TAU * j / SIDES
			var o := side * cos(a) * r * 1.15 + up * sin(a) * r * 0.9
			var bump := (BorderNoise.snoise(Vector2(path[k].x + path[k].z, path[k].y) * 0.3 + Vector2(j * 1.7, 0.0)) - 0.5)
			var v := path[k] + o + o.normalized() * bump * r * 0.35
			var nrm := -o.normalized()
			if v.y < floor_y:
				v.y = floor_y + bump * 0.08
				nrm = Vector3.UP
			g.v.append(v)
			g.n.append(nrm)
			var ao := clampf(0.6 + bump * 0.8, 0.2, 1.0)
			g.c.append(Color(ao, ao, ao))
	for k in n - 1:
		for j in SIDES:
			var a := base + k * SIDES + j
			var b := base + k * SIDES + (j + 1) % SIDES
			_quad(g, a, b, b + SIDES, a + SIDES)


## A chamber: a lumpy, flattened sphere seen from inside, with holes where tunnels come in.
static func _chamber(ch: Dictionary, g: Dictionary) -> void:
	const LAT := 12
	const LON := 22
	var c: Vector3 = ch.c
	var r: Vector3 = ch.r
	var base: int = (g.v as PackedVector3Array).size()
	var floor_y := c.y - r.y * 0.5
	for i in LAT + 1:
		var th := PI * i / LAT
		for j in LON + 1:
			var ph := TAU * j / LON
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var noise := BorderNoise.snoise(Vector2(ph * 2.5 + c.x * 0.01, th * 3.0 + c.z * 0.01)) - 0.5
			var v := c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * (1.0 + noise * 0.35)
			var nrm := -(v - c).normalized()
			if v.y < floor_y:
				v.y = floor_y + noise * 0.25
				nrm = Vector3.UP
			g.v.append(v)
			g.n.append(nrm)
			var ao := clampf(0.65 + noise, 0.2, 1.0)
			g.c.append(Color(ao, ao, ao))
	var opens: Array = ch.open
	for i in LAT:
		for j in LON:
			var a := base + i * (LON + 1) + j
			var b := a + 1
			var cc := a + LON + 1
			var dd := cc + 1
			# Leave an opening where a tunnel comes in.
			var mid: Vector3 = ((g.v[a] + g.v[dd]) * 0.5 - c)
			var flat := Vector3(mid.x, 0.0, mid.z).normalized()
			var hole := false
			for o: Vector3 in opens:
				if flat.dot(o) > 0.93 and mid.y < r.y * 0.25 and mid.y > -r.y * 0.38:
					hole = true
			if not hole:
				_quad(g, a, b, dd, cc)


## Two triangles a-b-c and a-c-d, each wound on its own so it faces along its stored normals
## (inwards) - the flattened floor folds some quads, so one winding per quad isn't enough.
static func _quad(g: Dictionary, a: int, b: int, c: int, d: int) -> void:
	_tri(g, a, b, c)
	_tri(g, a, c, d)


static func _tri(g: Dictionary, a: int, b: int, c: int) -> void:
	var va: Vector3 = g.v[a]
	var vb: Vector3 = g.v[b]
	var vc: Vector3 = g.v[c]
	var cr := (vb - va).cross(vc - va)
	if cr.length_squared() < 1e-8:
		return
	var nrm: Vector3 = (g.n[a] as Vector3) + (g.n[b] as Vector3) + (g.n[c] as Vector3)
	# Godot draws clockwise faces: the cross product must point away from the viewer.
	if cr.dot(nrm) < 0.0:
		g.i.append_array([a, b, c])
	else:
		g.i.append_array([a, c, b])


## A cone (stalactite or stalagmite) from a wide base to a tip.
static func _cone(data: MeshData, base: Vector3, tip: Vector3, w: float) -> void:
	const SIDES := 7
	var axis := (tip - base).normalized()
	var side := axis.cross(Vector3.FORWARD)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up := side.cross(axis).normalized()
	for k in SIDES:
		var a0 := TAU * k / SIDES
		var a1 := TAU * (k + 1) / SIDES
		var p0 := base + (side * cos(a0) + up * sin(a0)) * w
		var p1 := base + (side * cos(a1) + up * sin(a1)) * w
		var nrm := ((p0 + p1) * 0.5 - base).normalized()
		data.tri(p0, p1, tip, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nrm, Vector2.ZERO, Color(0.75, 0.75, 0.75))


## Floor height of the cave nearest to world point p (for the camera while exploring).
func floor_at(si: int, p: Vector2) -> float:
	var pts: PackedVector3Array = systems[si].get("floor", PackedVector3Array())
	var best := INF
	var y := 0.0
	for q in pts:
		var d := Vector2(q.x, q.z).distance_squared_to(p)
		if d < best:
			best = d
			y = q.y
	return y


## The cave mouths: a dark recessed arch, a frame of rock slabs, fallen stones.
func build_meshes(surface: TerrainSurface, parent: Node3D, terrain_mat: Material = null) -> void:
	if systems.is_empty():
		return
	var mouths := MeshData.new()
	var faces := {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(),
		"uvs": PackedVector2Array(), "uv2s": PackedVector2Array(), "custom0": PackedFloat32Array(), "custom1": PackedFloat32Array()}
	var items: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = MapSeed.mix(6161)
	for sy: Dictionary in systems:
		for e: Dictionary in sy.entrances:
			var p: Vector2 = e.p
			var dir: Vector2 = e.dir
			var side := Vector2(-dir.y, dir.x)
			# The mouth opens from the alcove's back wall, as tall as that wall allows.
			var back := p - dir * 5.0
			var floor_y := surface.sample(back + dir * 1.5) + 0.05
			var wall := surface.sample(back - dir * 6.0) - floor_y
			var w := rng.randf_range(5.5, 7.5)
			var h := clampf(minf(rng.randf_range(4.5, 6.0), wall * 0.9), 3.4, 6.0)
			_mouth(mouths, Vector3(back.x, floor_y, back.y), dir, side, w, h, surface)
			var basalt := surface.volcanic_at(p)
			# The rock face the cave opens from: a sculpted wall standing at the back of the
			# alcove, leaning back into the hill, its ragged edges sinking into the slope.
			_rock_face(faces, surface, back, floor_y, dir, side, w, h, rng.randf() * 100.0)
			# A few blocks fallen from it, half buried at its foot.
			for k in 3:
				var q := back + dir * rng.randf_range(1.5, 3.5) + side * (rng.randf_range(0.6, 1.1) * w * (1.0 if k % 2 == 0 else -1.0))
				var size := rng.randf_range(1.6, 3.2)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.8, size))
				_add(items, ["rock_a", "rock_c"][k % 2], Transform3D(basis, Vector3(q.x, surface.ground_min(q, size * 0.6) - size * 0.2, q.y)), Color(1, 1, 1, basalt))
			# Fallen stones on the ledge.
			for k in rng.randi_range(2, 4):
				var q := p + dir * rng.randf_range(3.0, 8.0) + side * rng.randf_range(-w, w)
				var size := rng.randf_range(0.8, 2.0)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
				_add(items, ["rock_b", "rock_d"][rng.randi() % 2], Transform3D(basis, Vector3(q.x, surface.ground_min(q, size * 0.6) - size * 0.1, q.y)), Color(1, 1, 1, basalt))
	if not (faces.verts as PackedVector3Array).is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces.verts
		arrays[Mesh.ARRAY_NORMAL] = faces.normals
		arrays[Mesh.ARRAY_COLOR] = faces.colors
		arrays[Mesh.ARRAY_TEX_UV] = faces.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = faces.uv2s
		arrays[Mesh.ARRAY_CUSTOM0] = faces.custom0
		arrays[Mesh.ARRAY_CUSTOM1] = faces.custom1
		var fm := ArrayMesh.new()
		var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		var fmi := MeshInstance3D.new()
		fmi.name = "CaveFaces"
		fmi.mesh = fm
		fmi.material_override = terrain_mat if terrain_mat != null else Vegetation._material("Rock")
		parent.add_child(fmi)
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


## The rock face round a cave mouth: a grid (across x up) pushed in and out by noise, bulging
## out of the hill in the middle and leaning back as it rises, with a ragged rounded outline
## whose edges sink into the ground. Grid points inside the arch are moved onto its outline, so
## the opening has a clean edge that meets the dark recess's rim exactly. Drawn with the
## terrain's own material as pure rock, so it is the hillside's rock, not a separate object.
static func _rock_face(f: Dictionary, surface: TerrainSurface, back: Vector2, floor_y: float, dir: Vector2, side: Vector2, w: float, h: float, seed: float) -> void:
	const NU := 44
	const NV := 30
	var fw := w + 12.0
	var fh := h + 6.0
	var out3 := Vector3(dir.x, 0.0, dir.y)
	var sd3 := Vector3(side.x, 0.0, side.y)
	var o := Vector3(back.x, floor_y, back.y)
	var volc := surface.volcanic_at(back)
	var pos := PackedVector3Array()
	var inside := PackedByteArray()
	var keep := PackedByteArray()
	for j in NV + 1:
		for i in NU + 1:
			var u := (float(i) / NU - 0.5) * fw
			var v := float(j) / NV * (fh + 2.0) - 2.0
			var arch := pow(u / (w * 0.5), 2.0) + pow(maxf(v, 0.0) / h, 2.0)
			var inn := arch < 1.0
			if inn:
				# Onto the arch outline (straight sides below the springing line).
				if v > 0.0:
					var k := 1.0 / sqrt(maxf(arch, 1e-4))
					u *= k
					v *= k
				else:
					u = signf(u if u != 0.0 else 1.0) * w * 0.5
				arch = 1.0
			var cv := v - fh * 0.35
			var a := atan2(cv, u * 0.8)
			var rag := 1.0 + 0.3 * (BorderNoise.snoise(Vector2(cos(a), sin(a)) * 2.2 + Vector2(seed, 3.0)) - 0.5)
			var ex := u / (fw * 0.5)
			var ez := cv / (fh * 0.72)
			var rr := sqrt(ex * ex + ez * ez) / rag
			var band := smoothstep(0.68, 1.0, rr)
			var n1 := BorderNoise.snoise(Vector2(u, v) * 0.32 + Vector2(seed, 1.0))
			var n2 := BorderNoise.snoise(Vector2(u, v) * 1.05 + Vector2(seed * 2.0, 5.0))
			var bulge := 1.4 * (1.0 - clampf(rr, 0.0, 1.0))
			var depth := (n1 - 0.5) * 1.8 + (n2 - 0.5) * 0.55 + bulge - maxf(v, 0.0) * 0.3 - band * 4.5
			depth = lerpf(0.6, depth, smoothstep(1.0, 1.9, arch))
			var q := o + sd3 * u + Vector3.UP * v + out3 * depth
			var g := surface.sample(Vector2(q.x, q.z))
			q.y = lerpf(q.y, minf(q.y, g - 0.8), band)
			# Never a blister on the hill: the face rises at most ~a metre above the hillside
			# just behind it, except over the opening, which keeps a lintel of rock.
			var hill := surface.sample(Vector2(q.x, q.z) - dir * 3.0) + 1.2
			var lintel := -INF
			var lu := absf(u) / (w * 0.8)
			if lu < 1.0:
				lintel = floor_y + (h + 1.4) * sqrt(1.0 - lu * lu)
			q.y = minf(q.y, maxf(hill, lintel))
			pos.append(q)
			inside.append(1 if inn else 0)
			keep.append(1 if rr < 1.08 else 0)
	var row := NU + 1
	# Smooth normals from the grid (facing out of the hill).
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for j in NV + 1:
		for i in NU + 1:
			var k := j * row + i
			var du := pos[j * row + mini(i + 1, NU)] - pos[j * row + maxi(i - 1, 0)]
			var dv := pos[mini(j + 1, NV) * row + i] - pos[maxi(j - 1, 0) * row + i]
			var nn := dv.cross(du).normalized()
			if nn.dot(out3) < 0.0:
				nn = -nn
			nrm[k] = nn
	var verts: PackedVector3Array = f.verts
	var norms: PackedVector3Array = f.normals
	var cols: PackedColorArray = f.colors
	var uvs: PackedVector2Array = f.uvs
	var uv2s: PackedVector2Array = f.uv2s
	var c0: PackedFloat32Array = f.custom0
	var c1: PackedFloat32Array = f.custom1
	for j in NV:
		for i in NU:
			var a := j * row + i
			var b := a + 1
			var c := a + row + 1
			var d := a + row
			if keep[a] == 0 or keep[b] == 0 or keep[c] == 0 or keep[d] == 0:
				continue
			if inside[a] == 1 and inside[b] == 1 and inside[c] == 1 and inside[d] == 1:
				continue
			for k: int in [a, b, d, b, c, d]:
				verts.append(pos[k])
				norms.append(nrm[k])
				# Terrain layer weights: all rock (layer 5 = UV.y).
				cols.append(Color(0, 0, 0, 0))
				uvs.append(Vector2(0.0, 1.0))
				uv2s.append(Vector2.ZERO)
				c0.append_array(PackedFloat32Array([0.0, 0.0, 0.0, volc]))
				c1.append_array(PackedFloat32Array([0.25, 0.6, 0.0, 0.0]))
	f.verts = verts
	f.normals = norms
	f.colors = cols
	f.uvs = uvs
	f.uv2s = uv2s
	f.custom0 = c0
	f.custom1 = c1


## A recessed arch: a half-dome opening facing `dir`, black deep inside, dark grey at the rim.
static func _mouth(data: MeshData, base: Vector3, dir: Vector2, side: Vector2, w: float, h: float, surface: TerrainSurface = null) -> void:
	# The opening: a dark jamb stepping in from the face's arch, then a black backdrop just
	# behind it, darkest at the middle so it reads as depth. It stands in front of the hill
	# behind, so the ground can't show through it and nothing of it pokes out of the slope.
	const SEG := 16
	var out := Vector3(dir.x, 0, dir.y)
	var sd := Vector3(side.x, 0, side.y)
	var rim: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for k in SEG + 1:
		var a := PI * float(k) / SEG
		var off := sd * cos(a) * w * 0.5 + Vector3.UP * sin(a) * h
		rim.append(base + off + out * 0.6)
		inner.append(base + off * 0.9 + out * -0.1)
	var centre := base + Vector3.UP * h * 0.35 - out * 0.15
	var c_rim := Color(0.035, 0.032, 0.03)
	var c_in := Color(0.012, 0.011, 0.01)
	var c_mid := Color(0.0, 0.0, 0.0)
	for k in SEG:
		data.tri(rim[k], rim[k + 1], inner[k + 1], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, c_rim.lerp(c_in, 0.5))
		data.tri(rim[k], inner[k + 1], inner[k], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, c_rim.lerp(c_in, 0.5))
		data.tri(inner[k], inner[k + 1], centre, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, c_mid)
	# Close the bottom between the two legs.
	data.tri(inner[0], centre, inner[SEG], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, out, Vector2.ZERO, c_mid)
	data.tri(rim[0], inner[0], inner[SEG], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO, c_in)
	data.tri(rim[0], inner[SEG], rim[SEG], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO, c_in)


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
