class_name ResourceProps
extends RefCounted
## Puts the natural resources of a level into the world as props (Blender models in
## assets/models/resources): ore outcrops, quarries, kilns, herds, fish shoals, whales, fields...
##
## Each resource goes where it belongs inside its hex: coastal finds at the waterline, river
## and bog finds on the banks, fish on the water surface, herds in open ground. Props are
## shown a little larger than life (more so on coarse levels) so they read from the strategy
## camera.

const MODEL_DIR := "res://assets/models/resources"
const K := NaturalResources.Kind

## kind -> [model, min count, max count, spot, herd]. spot: "any", "coast", "bank", "water",
## "deep", "clearing". herd = members are grouped around one spot.
const PROPS := {
	K.TIMBER: ["log_pile", 1, 1, "clearing", false],
	K.OAK: ["@broadleaf_b", 2, 4, "any", false],
	K.TAR: ["tar_kiln", 1, 1, "clearing", false],
	K.STONE: ["quarry", 1, 1, "any", false],
	K.SOAPSTONE: ["outcrop_soapstone", 1, 2, "any", false],
	K.IRON: ["outcrop_iron", 1, 2, "any", false],
	K.BOG_IRON: ["bog", 1, 2, "bank", false],
	K.COAL: ["outcrop_coal", 1, 2, "any", false],
	K.GOLD: ["gold_gravel", 1, 2, "bank", false],
	K.SILVER: ["outcrop_silver", 1, 2, "any", false],
	K.GEMS: ["crystals", 1, 1, "any", false],
	K.FISH: ["@shoal", 2, 3, "water", false],
	K.WHALES: ["a:whale", 1, 1, "deep", false],
	K.SEALS: ["a:seal|a:seal|a:walrus", 3, 5, "coast", true],
	K.FARMLAND: ["@field", 2, 4, "any", false],
	K.WOOL: ["a:sheep", 6, 10, "clearing", true],
	K.HORSES: ["a:horse", 4, 7, "clearing", true],
	K.GAME: ["a:deer|a:deer|a:boar", 4, 6, "clearing", true],
	K.FURS: ["a:reindeer|a:reindeer|a:fox", 4, 7, "clearing", true],
	K.CLAY: ["clay_pit", 1, 1, "bank", false],
	K.SALT: ["salt_pans", 1, 1, "coast", false],
	K.PEAT: ["peat_stack", 1, 2, "any", false],
	K.AMBER: ["amber", 1, 2, "coast", false],
	K.REEDS: ["reeds", 3, 6, "bank", false],
	K.LAKE_ORE: ["bog", 1, 2, "bank", false],
}
## Coat colour variations per animal (multiplied with the painted coat).
const COATS := {
	"sheep": [Color(1, 1, 1), Color(1, 1, 1), Color(0.95, 0.88, 0.74), Color(0.55, 0.42, 0.3), Color(0.28, 0.24, 0.21)],
	"horse": [Color(1, 1, 1), Color(1, 1, 1), Color(1.12, 0.85, 0.62), Color(1.3, 1.15, 0.85), Color(1.5, 1.52, 1.55), Color(0.45, 0.4, 0.38)],
}
const ANIMAL_DIR := "res://assets/models/animals"

## Static props (ore, quarries, kilns...) are drawn this much bigger again than animals, so a
## deposit reads from the strategy camera.
const PROP_BOOST := 2.0
## Per-model correction on top of PROP_BOOST for props that are big to begin with, so they
## stay in proportion to trees (log piles and quarries would otherwise tower over a forest).
const PROP_SIZE := {"log_pile": 0.5, "quarry": 0.55, "tar_kiln": 0.75, "salt_pans": 0.8, "clay_pit": 0.8, "peat_stack": 0.8}

## Ground tint per resource: deposits colour the land they cover (rusty soil over iron, golden
## stubble on farmland, pale salt crust...), so a deposit reads as one region across its hexes.
const PATCH := {
	K.TIMBER: Color(0.16, 0.3, 0.12), K.OAK: Color(0.34, 0.4, 0.14), K.TAR: Color(0.22, 0.15, 0.1),
	K.STONE: Color(0.72, 0.72, 0.7), K.SOAPSTONE: Color(0.55, 0.65, 0.58), K.IRON: Color(0.6, 0.22, 0.12),
	K.BOG_IRON: Color(0.5, 0.28, 0.1), K.COAL: Color(0.1, 0.1, 0.1), K.GOLD: Color(0.78, 0.64, 0.3),
	K.SILVER: Color(0.8, 0.86, 0.95), K.GEMS: Color(0.6, 0.3, 0.85), K.SEALS: Color(0.75, 0.75, 0.72),
	K.WOOL: Color(0.42, 0.58, 0.2), K.HORSES: Color(0.7, 0.62, 0.35),
	K.GAME: Color(0.4, 0.5, 0.2), K.FURS: Color(0.55, 0.48, 0.32), K.CLAY: Color(0.78, 0.42, 0.22),
	K.SALT: Color(0.86, 0.84, 0.78), K.PEAT: Color(0.25, 0.17, 0.1), K.AMBER: Color(0.95, 0.55, 0.12),
	K.REEDS: Color(0.7, 0.72, 0.3), K.LAKE_ORE: Color(0.55, 0.3, 0.15),
}

const CROPS := [Color(0.36, 0.5, 0.17), Color(0.55, 0.6, 0.22), Color(0.8, 0.66, 0.3), Color(0.72, 0.6, 0.28), Color(0.42, 0.55, 0.45)]

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


static func build(level: HexLevel, surface: TerrainSurface, hydro: Hydrology, parent: Node3D, scale: float) -> void:
	var s := level.hex_size
	var rng := RandomNumberGenerator.new()
	var items: Dictionary = {}        # model -> [[Transform3D], [Color]]
	var fields := MeshData.new()
	var shoals := MeshData.new()
	for i in level.cell_count():
		var kind := level.resource[i]
		if kind == 0 or not PROPS.has(kind):
			continue
		var def: Array = PROPS[kind]
		var model: String = def[0]
		var amount := level.resource_amount[i]
		# Every hex of a deposit gets props; herds graze its richer hexes.
		if def[4] and amount < 2:
			continue
		rng.seed = hash(Vector3i(level.coords[i].x, level.coords[i].y, 4111 + level.level_index))
		var c := level.cell_center(i)
		var count := rng.randi_range(def[1], def[2]) + (amount - 1)
		if def[4]:
			count = rng.randi_range(def[1], def[2]) + (amount - 2) * 3
		elif NaturalResources.INFO[kind][7] >= 6 and amount == 1:
			count = maxi(1, count / 2)  # thin edges of big deposits
		var herd_spot := _spot(def[3], c, s, surface, hydro, rng)
		var base_model := model
		for k in count:
			var p: Vector2 = herd_spot if def[4] else _spot(def[3], c, s, surface, hydro, rng)
			if p.x == INF:
				continue
			if def[4]:
				p += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * s * 0.18 * sqrt(scale)
			if base_model.contains("|"):
				var options := base_model.split("|")
				model = options[rng.randi() % options.size()]
			match model:
				"@field":
					_add_field(fields, p, s, surface, rng)
				"@shoal":
					var wy := _water_level(p, surface, hydro)
					var r := s * 0.3 * rng.randf_range(0.7, 1.2)
					_add_quad(shoals, Vector3(p.x, wy + 0.06, p.y), r)
				_:
					var y := _water_level(p, surface, hydro) if def[3] == "deep" else surface.sample(p)
					var size := scale * rng.randf_range(0.85, 1.2)
					var custom := Color.WHITE
					if model.begins_with("a:"):
						var coats: Array = COATS.get(model.trim_prefix("a:"), [])
						if not coats.is_empty():
							custom = coats[rng.randi() % coats.size()]
						custom = custom * rng.randf_range(0.9, 1.1)
						custom.a = 1.0
					var yaw := rng.randf() * TAU
					if def[4]:
						yaw = hash(level.coords[i]) % 628 / 100.0 + rng.randf_range(-0.6, 0.6)
					var basis := Basis(Vector3.UP, yaw)
					if model == "@broadleaf_b":
						var h := rng.randf_range(12.0, 15.0) * (1.0 + 0.3 * level.level_index)
						basis = basis.scaled(Vector3(h * 1.15, h, h * 1.15))
						y -= 0.3
						_add(items, model, Transform3D(basis, Vector3(p.x, y, p.y)), Color(0.8, 0.92, 0.6))
					elif model.begins_with("a:") and level.level_index == 0:
						# Finest level: a living, animated animal.
						var home := herd_spot if def[4] and herd_spot.x != INF else p
						_spawn_animal(parent, model.trim_prefix("a:"), Vector3(p.x, y, p.y), yaw, size, custom,
							surface, home, s * (0.6 if def[3] == "deep" else 0.9) * sqrt(scale), rng.randi())
					else:
						if not model.begins_with("a:"):
							size *= PROP_BOOST * float(PROP_SIZE.get(model, 1.0))
						basis = basis.scaled(Vector3.ONE * size)
						_add(items, model, Transform3D(basis, Vector3(p.x, y - 0.05 * size, p.y)), custom)

	_wetland_plants(surface, items, scale, level.level_index)

	for model: String in items:
		var m := _mesh(model)
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
		mmi.name = "Res_" + model.trim_prefix("@").trim_prefix("a:")
		mmi.multimesh = mm
		parent.add_child(mmi)
	if not fields.verts.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Res_fields"
		mi.mesh = fields.to_mesh()
		mi.material_override = _material("field")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	if not shoals.verts.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Res_shoals"
		mi.mesh = shoals.to_mesh()
		mi.material_override = _material("shoal")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## Tints the ground under every deposit hex (PATCH colours), soft and mottled, fading out only
## at the deposit's outer edge so its hexes merge into one region. Strength follows richness.
static func build_ground(level: HexLevel, surface: TerrainSurface, parent: Node3D) -> void:
	const N := 6
	var s := level.hex_size
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for i in level.cell_count():
		var kind := level.resource[i]
		if not PATCH.has(kind):
			continue
		var c := level.cell_center(i)
		var tint: Color = PATCH[kind]
		var strength := (0.22 + 0.11 * level.resource_amount[i]) * (1.0 - 0.75 * surface.volcanic_at(c))
		for k in 6:
			var ca := HexCoords.corner(k, s * 1.02)
			var cb := HexCoords.corner((k + 1) % 6, s * 1.02)
			var j := level.cell_at(c + (ca + cb))
			var open := j < 0 or not same_deposit(level, i, j)
			# Barycentric grid over the sector (centre, corner k, corner k+1).
			var grid: Array = []
			for a in N + 1:
				var row: Array = []
				for b in N + 1 - a:
					var p := c + (ca * a + cb * b) / N
					var h := surface.sample(p)
					var t := float(a + b) / N
					var al := strength * (1.0 - smoothstep(0.55, 1.0, t) if open else 1.0)
					al *= smoothstep(0.6, 0.85, surface.normal_at(p).y)
					if h < surface.sea_y + 0.1:
						al = 0.0
					row.append([Vector3(p.x, h + 0.18, p.y), Color(tint.r, tint.g, tint.b, al)])
				grid.append(row)
			for a in N:
				for b in N - a:
					_patch_tri(verts, colors, uvs, grid[a][b], grid[a + 1][b], grid[a][b + 1])
					if b < N - a - 1:
						_patch_tri(verts, colors, uvs, grid[a + 1][b], grid[a + 1][b + 1], grid[a][b + 1])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Res_ground"
	mi.mesh = mesh
	mi.material_override = _material("ground")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _patch_tri(verts: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, a: Array, b: Array, c: Array) -> void:
	if a[1].a <= 0.0 and b[1].a <= 0.0 and c[1].a <= 0.0:
		return
	# Leave out triangles that would hang across a terrace cliff.
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var rise := maxf(pa.y, maxf(pb.y, pc.y)) - minf(pa.y, minf(pb.y, pc.y))
	if rise > Vector2(pa.x - pb.x, pa.z - pb.z).length() * 2.0:
		return
	# Clockwise seen from above (Godot front faces).
	var order := [a, c, b] if (b[0] - a[0]).cross(c[0] - a[0]).y > 0.0 else [a, b, c]
	for v: Array in order:
		verts.append(v[0])
		colors.append(v[1])
		uvs.append(Vector2(v[0].x, v[0].z))


## True if hexes i and j belong to the same deposit (on coarse levels: the same resource).
static func same_deposit(level: HexLevel, i: int, j: int) -> bool:
	if level.deposit[i] >= 0:
		return level.deposit[j] == level.deposit[i]
	return level.resource[j] == level.resource[i]


## Outline ribbons around every deposit (shown with the resource icons): a coloured line along
## each hex edge where the deposit ends, following the ground.
static func build_outlines(level: HexLevel, surface: TerrainSurface, sea_y: float) -> MeshInstance3D:
	var s := level.hex_size
	var w := s * 0.05
	var data := MeshData.new()
	for i in level.cell_count():
		var kind := level.resource[i]
		if kind == 0:
			continue
		var c := level.cell_center(i)
		var col: Color = PATCH.get(kind, Color(0.3, 0.6, 1.0)).lightened(0.25)
		for k in 6:
			var ca := HexCoords.corner(k, s)
			var cb := HexCoords.corner((k + 1) % 6, s)
			var j := level.cell_at(c + (ca + cb))
			if j >= 0 and same_deposit(level, i, j):
				continue
			# Inset a little so neighbouring deposits' lines sit side by side.
			var pa := c + ca * (1.0 - w / s)
			var pb := c + cb * (1.0 - w / s)
			var inward := -(ca + cb).normalized() * w
			const SEG := 4
			for q in SEG:
				var p0 := pa.lerp(pb, float(q) / SEG)
				var p1 := pa.lerp(pb, float(q + 1) / SEG)
				var y0 := maxf(surface.sample(p0), sea_y) + 0.6
				var y1 := maxf(surface.sample(p1), sea_y) + 0.6
				var a := Vector3(p0.x, y0, p0.y)
				var b := Vector3(p1.x, y1, p1.y)
				var a2 := Vector3(p0.x + inward.x, y0, p0.y + inward.y)
				var b2 := Vector3(p1.x + inward.x, y1, p1.y + inward.y)
				data.tri(a, b, b2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO, col)
				data.tri(a, b2, a2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP, Vector2.ZERO, col)
	if data.verts.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "DepositOutlines"
	mi.mesh = data.to_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Picks a spot in the hex that suits the resource. Returns Vector2(INF, INF) if none.
static func _spot(kind: String, c: Vector2, s: float, surface: TerrainSurface, hydro: Hydrology, rng: RandomNumberGenerator) -> Vector2:
	var best := Vector2(INF, INF)
	var best_score := -INF
	for attempt in 14:
		var p := c + Vector2(rng.randf_range(-s, s), rng.randf_range(-s, s)) * 0.85
		if not HexCoords.contains(p - c, s * 0.9):
			continue
		var h := surface.sample(p)
		var water := hydro != null and hydro.lake_at(p) >= 0
		var dry := h > surface.sea_y + 0.5 and not water
		var score := -INF
		match kind:
			"water":
				score = 1.0 if (water or h < surface.sea_y - 1.0) else -INF
			"deep":
				score = surface.sea_y - h if h < surface.sea_y - 8.0 else -INF
			"coast":
				score = -absf(h - (surface.sea_y + 1.0)) if dry else -INF
			"bank":
				var r := surface.river_at(p)
				score = (1.0 - absf(r - 0.35) * 2.0) if dry and r > 0.05 else (-2.0 if dry else -INF)
			"clearing":
				score = (1.0 - surface.weight_at(p, HexMapGenerator.Terrain.ROCK)) if dry and not surface.keep_clear(p) else -INF
				score -= surface.normal_at(p).angle_to(Vector3.UP)
			_:
				score = (0.5 + rng.randf() * 0.5) if dry and surface.river_at(p) < 0.2 else -INF
		if score > best_score:
			best_score = score
			best = p
	return best if best_score > -INF else Vector2(INF, INF)


static func _water_level(p: Vector2, surface: TerrainSurface, hydro: Hydrology) -> float:
	if hydro != null:
		var lake := hydro.lake_at(p)
		if lake >= 0:
			return hydro.lake_level[lake] - 0.05
	return surface.sea_y


## A field draped over the ground: an irregular, rounded plot (a ring of noisy radii, so no
## two fields share a shape and none is a rectangle), triangulated in rings that follow the
## terrain. Furrows run along one direction (UV.x across them, metres).
static func _add_field(data: MeshData, center: Vector2, s: float, surface: TerrainSurface, rng: RandomNumberGenerator) -> void:
	const SIDES := 14
	const RINGS := 3
	var r0 := s * rng.randf_range(0.28, 0.42)
	var stretch := rng.randf_range(1.1, 1.7)
	var yaw := rng.randf() * PI
	var ax := Vector2(cos(yaw), sin(yaw))
	var ay := Vector2(-ax.y, ax.x)
	var crop: Color = CROPS[rng.randi() % CROPS.size()]
	var seed_v := rng.randf() * 100.0
	var radii := PackedFloat32Array()
	for k in SIDES:
		var a := TAU * k / SIDES
		var wob := BorderNoise.value_noise(Vector2(cos(a), sin(a)) * 1.6 + Vector2(seed_v, 2.0))
		radii.append(r0 * (0.7 + 0.55 * wob))
	# Points: centre, then rings outwards.
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var local := Vector2.ZERO
	for ring in RINGS + 1:
		var count := 1 if ring == 0 else SIDES
		for k in count:
			var a := TAU * k / SIDES
			var rr := 0.0 if ring == 0 else radii[k] * float(ring) / RINGS
			local = Vector2(cos(a) * rr * stretch, sin(a) * rr)
			var p := center + ax * local.x + ay * local.y
			if surface.sample(p) < surface.sea_y + 0.4 or surface.keep_clear(p) or surface.wetland_at(p) > 0.5:
				return
			pts.append(Vector3(p.x, surface.sample(p) + 0.12, p.y))
			uvs.append(Vector2(local.y, local.x))
	for ring in RINGS:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			if ring == 0:
				var c := 0
				var a := 1 + k
				var b := 1 + k2
				data.tri(pts[c], pts[a], pts[b], uvs[c], uvs[a], uvs[b], Vector3.UP, Vector2.ZERO, crop)
			else:
				var i0 := 1 + (ring - 1) * SIDES
				var i1 := 1 + ring * SIDES
				data.tri(pts[i0 + k], pts[i1 + k], pts[i1 + k2], uvs[i0 + k], uvs[i1 + k], uvs[i1 + k2], Vector3.UP, Vector2.ZERO, crop)
				data.tri(pts[i0 + k], pts[i1 + k2], pts[i0 + k2], uvs[i0 + k], uvs[i1 + k2], uvs[i0 + k2], Vector3.UP, Vector2.ZERO, crop)


## Reed clumps and sedge tussocks scattered over lowland wetland (bogs up high stay open,
## with the odd tussock).
static func _wetland_plants(surface: TerrainSurface, items: Dictionary, scale: float, level_index: int) -> void:
	if surface.wetland.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + level_index
	var step := 9.0 * (1.0 + level_index * 1.5)
	var y := 0.0
	var gz := 0.0
	while gz < (surface.nz - 1) * surface.spacing:
		var gx := 0.0
		while gx < (surface.nx - 1) * surface.spacing:
			var p := Vector2(gx + rng.randf_range(-0.45, 0.45) * step, gz + rng.randf_range(-0.45, 0.45) * step)
			gx += step
			var w := surface.wetland_at(p)
			if w < 0.45 or rng.randf() > w * 0.55:
				continue
			var h := surface.sample(p)
			var upland := smoothstep(30.0, 70.0, h - surface.sea_y)
			if rng.randf() < upland * 0.75:
				continue
			var size := scale * rng.randf_range(0.7, 1.3) * 0.8
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
			y = h - 0.05
			_add(items, "reeds", Transform3D(basis, Vector3(p.x, y, p.y)), Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.05), 0.85, 1.0))
		gz += step


static func _add_quad(data: MeshData, c: Vector3, r: float) -> void:
	var a := c + Vector3(-r, 0, -r)
	var b := c + Vector3(r, 0, -r)
	var d := c + Vector3(-r, 0, r)
	var e := c + Vector3(r, 0, r)
	data.tri(a, b, e, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector3.UP, Vector2.ZERO)
	data.tri(a, e, d, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), Vector3.UP, Vector2.ZERO)


static func _add(items: Dictionary, model: String, xform: Transform3D, custom: Color) -> void:
	if not items.has(model):
		items[model] = [[], []]
	items[model][0].append(xform)
	items[model][1].append(custom)


static func _mesh(model: String) -> Mesh:
	if model.begins_with("@"):
		return Vegetation.mesh(model.trim_prefix("@"))
	if model.begins_with("a:"):
		return _animal_mesh(model.trim_prefix("a:"))
	if _meshes.has(model):
		return _meshes[model]
	var result: ArrayMesh = null
	var path := "%s/%s.glb" % [MODEL_DIR, model]
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var inst := scene.instantiate()
			var found := Vegetation._find_mesh(inst)
			if found != null:
				result = found.duplicate() as ArrayMesh
			inst.free()
	if result == null:
		push_warning("ResourceProps: missing model %s" % path)
		_meshes[model] = null
		return null
	for s in result.get_surface_count():
		var m := result.surface_get_material(s)
		var glint := m != null and m.resource_name == "Glint"
		result.surface_set_material(s, _material("glint" if glint else "body"))
	_meshes[model] = result
	return result


## The animal's mesh in its rest pose, for static instances on coarse levels (textured with
## the fur baked in Blender).
static func _animal_mesh(animal: String) -> Mesh:
	var key := "a:" + animal
	if _meshes.has(key):
		return _meshes[key]
	var scene := _animal_scene(animal)
	var result: ArrayMesh = null
	if scene != null:
		var inst := scene.instantiate()
		var found := Vegetation._find_mesh(inst)
		if found != null:
			result = found.duplicate() as ArrayMesh
			for i in result.get_surface_count():
				result.surface_set_material(i, _fur(result.surface_get_material(i), Color.WHITE))
		inst.free()
	_meshes[key] = result
	return result


static var _scenes: Dictionary = {}
static var _furs: Dictionary = {}


static func _animal_scene(animal: String) -> PackedScene:
	if not _scenes.has(animal):
		var path := "%s/%s.glb" % [ANIMAL_DIR, animal]
		_scenes[animal] = load(path) as PackedScene if ResourceLoader.exists(path) else null
		if _scenes[animal] == null:
			push_warning("ResourceProps: missing animal %s" % path)
	return _scenes[animal]


## The imported fur material, tinted for a coat variant, with a soft sheen like light on fur.
static func _fur(base: Material, tint: Color) -> Material:
	var key := str(base.get_instance_id()) + tint.to_html() if base != null else "none"
	if _furs.has(key):
		return _furs[key]
	var mat: Material = base
	if base is BaseMaterial3D:
		var m := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.albedo_color = tint
		m.roughness = 0.85
		m.rim_enabled = true
		m.rim = 0.3
		m.rim_tint = 0.6
		mat = m
	_furs[key] = mat
	return mat


## A rigged, animated animal that wanders its pasture (AnimalAgent).
static func _spawn_animal(parent: Node3D, animal: String, pos: Vector3, yaw: float, size: float, coat: Color,
		surface: TerrainSurface, home: Vector2, radius: float, seed_value: int) -> void:
	var scene := _animal_scene(animal)
	if scene == null:
		return
	var model := scene.instantiate()
	var meta: Dictionary = _animal_meta().get(animal, {})
	var agent := AnimalAgent.new()
	agent.name = "Animal_" + animal
	agent.position = pos
	if str(meta.get("kind", "land")) == "sea":
		# Whales are already huge: real size, each on its own circle.
		size = 1.0
		var r2 := RandomNumberGenerator.new()
		r2.seed = seed_value
		radius *= r2.randf_range(1.2, 2.2)
		home = Vector2(pos.x, pos.z) + Vector2(r2.randf_range(-1.0, 1.0), r2.randf_range(-1.0, 1.0)) * radius * 0.5
	agent.scale = Vector3.ONE * size
	agent.setup(surface, home, radius, float(meta.get("walk_speed", 1.0)) * size, str(meta.get("kind", "land")), yaw, seed_value)
	agent.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _fur(mi.mesh.surface_get_material(i), coat))
		mi.visibility_range_end = 700.0
	parent.add_child(agent)


static var _meta: Dictionary = {}


static func _animal_meta() -> Dictionary:
	if _meta.is_empty():
		var path := ANIMAL_DIR + "/animals.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_meta = parsed
	return _meta


static func _material(kind: String) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	var mat := ShaderMaterial.new()
	match kind:
		"field":
			mat.shader = load("res://shaders/farm_field.gdshader")
		"shoal":
			mat.shader = load("res://shaders/fish_shoal.gdshader")
		"ground":
			mat.shader = load("res://shaders/resource_ground.gdshader")
		_:
			mat.shader = load("res://shaders/resource_prop.gdshader")
			mat.set_shader_parameter("glint", kind.ends_with("glint"))
			mat.set_shader_parameter("albedo_array", TerrainMaterial.albedo_array())
			mat.set_shader_parameter("normal_array", TerrainMaterial.normal_array())
	_materials[kind] = mat
	return mat
