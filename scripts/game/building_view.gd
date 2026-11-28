class_name BuildingView
extends Node3D
## A building on the map, animated through its life:
##   - being built: a scaffold of poles stands round the footprint, the building rises inside
##     it from the ground up (shaders/building.gdshader), dust puffs, builders hammer at it;
##   - finished: the scaffold sinks away, a burst of dust, a flash;
##   - at work: smoke from the chimney, its people go about their round (to the work and back
##     to the door, working with their tools at each), carts roll, boats bob, banners stir,
##     forges and mead halls glow, and each finished cycle floats "+2 Wood" over the roof;
##   - idle (no people, nothing to use, stores full): still, no smoke.

var record: Dictionary
var settlement: Settlement
var info: Dictionary
var height_at: Callable

var _mat: ShaderMaterial
var _model: MeshInstance3D
var _scaffold: MeshInstance3D
var _dust: CPUParticles3D
var _smoke: CPUParticles3D
var _flag: Node3D
var _flag_mesh: MeshInstance3D

## The paints a household might pick for its doors and shutters: red and yellow ochre, woad
## blue, verdigris, lime white, a soot black, a madder pink.
const PAINTS := [Color(0.62, 0.18, 0.1), Color(0.8, 0.6, 0.2), Color(0.18, 0.3, 0.55), Color(0.2, 0.48, 0.38),
	Color(0.88, 0.85, 0.76), Color(0.14, 0.12, 0.11), Color(0.7, 0.35, 0.38)]
var _cart: MeshInstance3D
var _boat: MeshInstance3D
var _light: OmniLight3D
var _fires: Array = []
var _foundation: MeshInstance3D   # [{root, flame, embers, light, kind, seed}]
var _builders: Array = []
var _workers: Array = []
var _built := false
var _t := 0.0
var _flash := 0.0
var _people_mat: ShaderMaterial

static var _shader: Shader


static func building_material(team: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/building.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("team_color", team)
	return m


func setup(p_record: Dictionary, p_settlement: Settlement, ground: Callable) -> void:
	record = p_record
	settlement = p_settlement
	height_at = ground
	var d: Dictionary = BuildingDefs.DEFS[record.id]
	info = BuildingModels.shape(String(d.model))
	_mat = building_material(settlement.color)
	_mat.set_shader_parameter("height", float(info.height))
	_people_mat = building_material(settlement.color)
	_people_mat.set_shader_parameter("height", 100.0)
	_people_mat.set_shader_parameter("people", true)
	_model = MeshInstance3D.new()
	_model.mesh = info.mesh
	_model.material_override = _mat
	add_child(_model)
	_scaffold = MeshInstance3D.new()
	_scaffold.mesh = BuildingModels.scaffold(info.size, float(info.height))
	_scaffold.material_override = building_material(settlement.color)
	_scaffold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_scaffold)
	_dust = _particles(Color(0.72, 0.64, 0.52, 0.5), 18, 2.2, Vector3(info.size.x * 0.5, 0.5, info.size.y * 0.5), 1.4)
	_dust.position = Vector3(0, 0.5, 0)
	if info.chimney != null:
		_smoke = _particles(Color(0.55, 0.55, 0.55, 0.45), 14, 5.0, Vector3(0.2, 0.1, 0.2), 1.2)
		_smoke.position = info.chimney
		_smoke.direction = Vector3(0.3, 1, 0)
		_smoke.gravity = Vector3(0.4, 0.5, 0)
		_smoke.scale_amount_min = 1.5
		_smoke.scale_amount_max = 3.5
	_make_flag()
	# Doors, shutters and painted boards in a colour of this household's own.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(record.uid) * 104729 + settlement.index
	_mat.set_shader_parameter("accent_color", PAINTS[rng.randi() % PAINTS.size()])
	if info.cart:
		_cart = MeshInstance3D.new()
		_cart.mesh = BuildingModels.cart()
		_cart.material_override = _people_mat
		add_child(_cart)
	if info.boat:
		_boat = MeshInstance3D.new()
		_boat.mesh = BuildingModels.boat()
		_boat.material_override = _people_mat
	if record.id in ["smithy", "weaponsmith", "tavern", "bakery", "town_hall"]:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.25)
		_light.omni_range = 9.0
		_light.light_energy = 0.0
		_light.position = (info.work as Vector3) + Vector3(0, 1.5, 0) if record.id in ["smithy", "weaponsmith", "bakery"] else Vector3(0, 2.0, -float(info.size.y) * 0.5 - 0.8)
		add_child(_light)
	conform()
	_make_fires()
	make_foundation()
	# Builders at the site while it goes up.
	for i in 2:
		var v := _villager(Color(0.55, 0.45, 0.32), "hammer", "builder")
		_builders.append(v)
	_place_builders()
	_built = settlement.is_built(record)
	_apply_build()


## What its people do at their work, and what they carry home: [act, load].
const TRADES := {
	"woodcutter": ["chop", "log"], "quarry": ["pick", "stone"], "mine": ["pick", "stone"],
	"farm": ["reap", "sack"], "fishing_hut": ["net", "fish"], "hunting_lodge": ["hammer", "sack"],
	"sheepfold": ["idle", "sack"], "clay_pit": ["dig", "sack"], "salt_works": ["stir", "sack"],
	"peat_cutter": ["dig", "sack"], "tar_kiln": ["stir", "log"], "amber_gatherer": ["dig", "sack"],
	"brewery": ["stir", "sack"], "bakery": ["stir", "sack"], "smithy": ["hammer", ""],
	"weaponsmith": ["hammer", ""], "weaver": ["stir", ""], "barracks": ["chop", ""],
	"horse_farm": ["idle", "sack"], "reed_cutter": ["reap", "sack"], "smokehouse": ["stir", "fish"],
	"charcoal": ["dig", "log"], "bloomery": ["hammer", "stone"], "potter": ["stir", ""],
	"tannery": ["stir", "sack"], "tailor": ["stir", ""], "jeweller": ["hammer", ""],
	"fletcher": ["hammer", ""], "whaler": ["chop", "sack"], "sealer": ["chop", "sack"],
	"shipyard": ["hammer", "log"], "trading_post": ["idle", "sack"],
	"outpost": ["idle", "sack"],
}


func _villager(tunic: Color, a := "idle", occupation := "") -> Villager:
	var v := Villager.new()
	v.setup(settlement.color, tunic, _people_mat, height_at, a, false, occupation)
	get_tree_root_add(v)
	return v


## Villagers move in world space (their rounds cross the ground outside the building).
func get_tree_root_add(v: Node3D) -> void:
	v.top_level = true
	add_child(v)


## Everything that burns on the building: a flame of additive licks, embers rising off it, and
## a flickering light. Torches are lit at dusk and put out at dawn; braziers burn while the
## building stands; the forge, ovens and hearths blaze while it works and glow low otherwise.
## Lights come up as it gets dark, so a settlement at night is picked out in firelight.
## The footing down to the ground, fitted to where the building stands: a dry-stone wall round
## the footprint wherever the ground falls away below the floor (on the low side of a slope, or
## out over the shore as a little quay), stone by stone, down into the ground. Where the ground
## is higher it is simply dug in. The plot on top is levelled by SettlementGround.
func make_foundation() -> void:
	if _foundation != null:
		_foundation.queue_free()
		_foundation = null
	if not is_inside_tree():
		return
	var k := BuildingModels.Kit.new()
	seed(int(record.uid) * 7919)
	var hx := float(info.size.x) * 0.5 * FOOT
	var hz := float(info.size.y) * 0.5 * FOOT
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var any := false
	for e in 4:
		var a: Vector3 = corners[e]
		var b: Vector3 = corners[(e + 1) % 4]
		var out := (a + b).normalized()
		out = Vector3(signf(out.x) if absf(a.x - b.x) < 0.01 else 0.0, 0, signf(out.z) if absf(a.z - b.z) < 0.01 else 0.0)
		var n := maxi(1, int(ceil(a.distance_to(b) / 1.6)))
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var g := minf(_ground_local(p0 + out * 0.3), _ground_local(p1 + out * 0.3))
			if g > -0.08:
				continue
			any = true
			var foot := g - 0.4
			var h := -foot + 0.05
			k.stones(p0 + Vector3(0, foot, 0) + out * 0.15, p1 + Vector3(0, foot, 0) + out * 0.15, h, 0.55, maxi(1, int(round(h / 0.42))), BuildingModels.STONE)
			k.quad(p0 + Vector3(0, foot, 0), p1 + Vector3(0, foot, 0), p1 + Vector3(0, 0.02, 0), p0 + Vector3(0, 0.02, 0), out, BuildingModels.DARK_STONE)
	if not any:
		return
	_foundation = MeshInstance3D.new()
	_foundation.mesh = k.commit()
	_foundation.material_override = _mat
	add_child(_foundation)


## How much of the footprint the footing walls go round (the rest is yard).
const FOOT := 0.82

var _shift_grid := PackedFloat32Array()
var _shift_o := Vector2.ZERO
var _shift_n := Vector2i.ZERO
const SHIFT_STEP := 1.5


## Everything outside the footing - fences, woodpiles, racks, stacks, the yard's clutter -
## follows the ground it stands on instead of the floor's level: each vertex is moved up or
## down to the ground under it (so a fence's posts stay upright and its rails run with the
## slope). Inside the footing the building stands level on its terrace. Redone when the
## building is re-seated.
func conform() -> void:
	if not is_inside_tree():
		return
	var src: ArrayMesh = info.mesh
	var box := src.get_aabb()
	_shift_o = Vector2(box.position.x - SHIFT_STEP, box.position.z - SHIFT_STEP)
	_shift_n = Vector2i(int(ceil(box.size.x / SHIFT_STEP)) + 3, int(ceil(box.size.z / SHIFT_STEP)) + 3)
	_shift_grid.resize(_shift_n.x * _shift_n.y)
	for j in _shift_n.y:
		for i in _shift_n.x:
			_shift_grid[j * _shift_n.x + i] = _ground_local(Vector3(_shift_o.x + i * SHIFT_STEP, 0, _shift_o.y + j * SHIFT_STEP))
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vi in verts.size():
		var p := verts[vi]
		var dy := ground_shift(p)
		if dy != 0.0:
			verts[vi] = Vector3(p.x, p.y + dy, p.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_model.mesh = m


## How far a point of the model (local) is moved to follow the ground (0 inside the footing).
func ground_shift(p: Vector3) -> float:
	if _shift_grid.is_empty():
		return 0.0
	var hx := float(info.size.x) * 0.5 * FOOT
	var hz := float(info.size.y) * 0.5 * FOOT
	var out := maxf(absf(p.x) - hx, absf(p.z) - hz)
	if out <= 0.0:
		return 0.0
	var w := clampf(out / 1.5, 0.0, 1.0)
	var fx := clampf((p.x - _shift_o.x) / SHIFT_STEP, 0.0, _shift_n.x - 1.001)
	var fz := clampf((p.z - _shift_o.y) / SHIFT_STEP, 0.0, _shift_n.y - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var g := lerpf(lerpf(_shift_grid[j * _shift_n.x + i], _shift_grid[j * _shift_n.x + i + 1], tx),
		lerpf(_shift_grid[(j + 1) * _shift_n.x + i], _shift_grid[(j + 1) * _shift_n.x + i + 1], tx), tz)
	return g * w


## Ground height under a point in the building's own space, relative to its floor.
func _ground_local(p: Vector3) -> float:
	var w := global_transform * p
	return float(height_at.call(Vector2(w.x, w.z))) - global_position.y


## The clan's flag: on the hall's and the towers' own masts a big one; on every other building
## a smaller one on a pole at its front corner, with a gilded finial. Painted with the clan's
## emblem (shaders/flag.gdshader), rippling and streaming downwind.
func _make_flag() -> void:
	var at: Vector3
	var w := 2.2
	var h := 1.4
	if info.flag != null:
		at = info.flag
		w = 3.6
		h = 2.3
	else:
		var hx := float(info.size.x) * 0.5 * 0.8
		var hz := float(info.size.y) * 0.5 * 0.8
		var base := Vector3(-hx, 0, -hz)
		var ph := clampf(float(info.height) * 0.7, 5.0, 8.5)
		var k := BuildingModels.Kit.new()
		k.post(base, ph, 0.07, BuildingModels.DARK_WOOD)
		k.sphere(base + Vector3(0, ph + 0.12, 0), 0.14, Color(0.9, 0.72, 0.3), 4, 8)
		var pole := MeshInstance3D.new()
		pole.mesh = k.commit()
		pole.material_override = _people_mat
		pole.name = "FlagPole"
		add_child(pole)
		_pole = pole
		at = base + Vector3(0, ph - 0.05, 0)
	_flag = Node3D.new()
	_flag.position = at
	add_child(_flag)
	_flag_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(w, h)
	pm.subdivide_width = 14
	pm.subdivide_depth = 7
	_flag_mesh.mesh = pm
	_flag_mesh.position = Vector3(w * 0.5, -h * 0.5, 0)
	_flag_mesh.material_override = Emblem.flag_material(settlement.color, settlement.emblem)
	_flag_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_flag.add_child(_flag_mesh)
	_flag.visible = false


var _pole: MeshInstance3D
var _level := 0
var _enhance: MeshInstance3D


## A main building with expansions grows grander: at one, stacks of what it makes piled in its
## yard; at two, a lean-to store and more stacks; at three, carved gateposts hung with the
## clan's banners and a second flag.
func set_level(n: int) -> void:
	if n == _level:
		return
	_level = n
	if _enhance != null:
		_enhance.queue_free()
		_enhance = null
	if n <= 0:
		return
	var k := BuildingModels.Kit.new()
	var hx := float(info.size.x) * 0.5
	var hz := float(info.size.y) * 0.5
	var recs := BuildingDefs.recipes(String(record.id))
	var product := ""
	if not recs.is_empty() and not (recs[0].makes as Dictionary).is_empty():
		product = String((recs[0].makes as Dictionary).keys()[0])
	var spots := [Vector3(hx * 0.82, 0, -hz * 0.85), Vector3(-hx * 0.82, 0, -hz * 0.85), Vector3(hx * 0.85, 0, hz * 0.4), Vector3(-hx * 0.85, 0, hz * 0.4)]
	var piles := mini(2 * n, spots.size())
	var gm: ArrayMesh = GoodsModels.mesh(product) if product != "" else null
	if gm != null:
		var arrays := gm.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for pi in piles:
			var at: Vector3 = spots[pi]
			at.y = ground_shift(at)
			for i in range(0, verts.size(), 3):
				var tri := [verts[i] * 1.3 + at, verts[i + 1] * 1.3 + at, verts[i + 2] * 1.3 + at]
				k.tri(tri[0], tri[1], tri[2], norms[i], cols[i] if i < cols.size() else Color.WHITE)
	if n >= 2:
		var c := Vector3(-hx * 0.85, ground_shift(Vector3(-hx * 0.85, 0, -hz * 0.2)), -hz * 0.2)
		for x in [-1.2, 1.2]:
			for z in [-1.0, 1.0]:
				k.post(c + Vector3(x, 0, z), 2.6 if z > 0 else 2.0, 0.1, BuildingModels.DARK_WOOD)
		k.roof(c + Vector3(0, 2.2, 0), 3.2, 2.8, 0.8, BuildingModels.SHINGLE)
		for i in 3:
			k.barrel(c + Vector3(-0.7 + i * 0.7, 0, 0.2), 0.32, 0.75)
	if n >= 3:
		for sd: float in [-1.0, 1.0]:
			var g := Vector3(sd * 2.2, 0, -hz - 1.5)
			g.y = ground_shift(g)
			k.box(g + Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.8), BuildingModels.STONE)
			k.post(g + Vector3(0, 0.5, 0), 3.6, 0.2, BuildingModels.DARK_WOOD)
			for y in [1.2, 2.4, 3.4]:
				k.box(g + Vector3(0, 0.5 + y, 0), Vector3(0.46, 0.14, 0.46), BuildingModels.TEAM)
			k.quad2(g + Vector3(-0.35, 3.9, -0.25), g + Vector3(0.35, 3.9, -0.25), g + Vector3(0.35, 2.3, -0.25), g + Vector3(-0.35, 2.3, -0.25), BuildingModels.TEAM)
	_enhance = MeshInstance3D.new()
	_enhance.mesh = k.commit()
	_enhance.material_override = _mat
	add_child(_enhance)
	# A burst of dust and a flash as it grows.
	_flash = 1.0


func _make_fires() -> void:
	var lights := 0
	for f: Array in info.get("fires", []):
		var kind := String(f[1])
		var root := Node3D.new()
		root.position = (f[0] as Vector3) + Vector3(0, ground_shift(f[0]), 0)
		add_child(root)
		var big := kind in ["brazier", "forge"]
		var flame := CPUParticles3D.new()
		flame.amount = 14 if big else 9
		flame.lifetime = 0.55 if big else 0.45
		flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		flame.emission_sphere_radius = 0.22 if big else 0.08
		flame.direction = Vector3.UP
		flame.spread = 12.0
		flame.gravity = Vector3(0, 2.5, 0)
		flame.initial_velocity_min = 0.6
		flame.initial_velocity_max = 1.3
		flame.scale_amount_min = 0.5 if big else 0.32
		flame.scale_amount_max = 0.95 if big else 0.55
		var shrink := Curve.new()
		shrink.add_point(Vector2(0, 0.7))
		shrink.add_point(Vector2(0.25, 1.0))
		shrink.add_point(Vector2(1, 0.1))
		flame.scale_amount_curve = shrink
		flame.mesh = _fire_quad()
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.92, 0.55, 1.0))
		ramp.add_point(0.35, Color(1.0, 0.55, 0.15, 0.9))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.12, 0.03, 0.0))
		flame.color_ramp = ramp
		root.add_child(flame)
		var embers := CPUParticles3D.new()
		embers.amount = 6 if big else 3
		embers.lifetime = 1.8
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		embers.emission_sphere_radius = 0.15
		embers.direction = Vector3.UP
		embers.spread = 30.0
		embers.gravity = Vector3(0.3, 0.6, 0)
		embers.initial_velocity_min = 0.8
		embers.initial_velocity_max = 2.0
		embers.scale_amount_min = 0.05
		embers.scale_amount_max = 0.09
		embers.mesh = _fire_quad()
		var er := Gradient.new()
		er.set_color(0, Color(1.0, 0.7, 0.3, 1.0))
		er.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
		embers.color_ramp = er
		root.add_child(embers)
		var light: OmniLight3D = null
		if lights < 4 or big:
			light = OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.3)
			light.omni_range = 11.0 if big else 8.0
			light.omni_attenuation = 1.4
			light.light_energy = 0.0
			light.position = Vector3(0, 0.3, 0)
			root.add_child(light)
			lights += 1
		root.visible = false
		_fires.append({"root": root, "flame": flame, "embers": embers, "light": light, "kind": kind, "seed": randf() * 10.0})


static var _fire_mesh: QuadMesh


static func _fire_quad() -> QuadMesh:
	if _fire_mesh != null:
		return _fire_mesh
	_fire_mesh = QuadMesh.new()
	_fire_mesh.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_fire_mesh.material = m
	return _fire_mesh


func _update_fires(working: bool) -> void:
	var night := Atmosphere.night
	_mat.set_shader_parameter("night", night if _built else 0.0)
	for f: Dictionary in _fires:
		var kind := String(f.kind)
		var lit := _built
		var strength := 1.0
		match kind:
			"torch":
				lit = lit and night > 0.15
			"forge", "hearth":
				strength = 1.0 if working else 0.45
		(f.root as Node3D).visible = lit
		(f.flame as CPUParticles3D).emitting = lit
		(f.embers as CPUParticles3D).emitting = lit and strength > 0.5
		(f.flame as CPUParticles3D).scale = Vector3.ONE * (0.6 + 0.4 * strength)
		var light := f.light as OmniLight3D
		if light != null:
			var s: float = f.seed
			var flick := 0.8 + 0.12 * sin(_t * 11.0 + s) * sin(_t * 6.7 + s * 2.0) + 0.08 * sin(_t * 23.0 + s)
			var base := 2.6 if kind in ["brazier", "forge"] else 1.7
			light.light_energy = (base * strength * (0.15 + 0.85 * night) * flick) if lit else 0.0


func _particles(col: Color, amount: int, life: float, box: Vector3, spd: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = spd * 0.5
	p.initial_velocity_max = spd
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff()
	mesh.material = m
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	p.emitting = false
	add_child(p)
	return p


static var _puff_tex: Texture2D


static func _puff() -> Texture2D:
	if _puff_tex != null:
		return _puff_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	_puff_tex = t
	return t


func _world(local: Vector3) -> Vector2:
	var w := global_transform * local
	return Vector2(w.x, w.z)


func _place_builders() -> void:
	var sz: Vector2 = info.size
	var corners := [Vector3(-sz.x * 0.5 - 1.2, 0, -sz.y * 0.5 - 1.2), Vector3(sz.x * 0.5 + 1.2, 0, sz.y * 0.5 + 1.2),
		Vector3(sz.x * 0.5 + 1.2, 0, -sz.y * 0.5 - 1.2), Vector3(-sz.x * 0.5 - 1.2, 0, sz.y * 0.5 + 1.2)]
	for i in _builders.size():
		var a: Vector3 = corners[i * 2 % corners.size()]
		var b: Vector3 = corners[(i * 2 + 1) % corners.size()]
		(_builders[i] as Villager).set_round([{"at": _world(a), "work": 4.0 + i, "act": "hammer"},
			{"at": _world(Vector3(a.x, 0, b.z)), "work": 3.0, "act": "hammer", "carry": "log"},
			{"at": _world(b), "work": 4.0, "act": "hammer"}])


## Its people at work: from the door to the work and back, once per cycle or so.
func _set_workers(n: int) -> void:
	while _workers.size() < n:
		var tunics := [Color(0.42, 0.36, 0.28), Color(0.3, 0.38, 0.32), Color(0.48, 0.32, 0.26), Color(0.36, 0.33, 0.42)]
		var trade: Array = TRADES.get(record.id, ["idle", ""])
		var v := _villager(tunics[_workers.size() % tunics.size()], trade[0], Outfits.BY_BUILDING.get(record.id, "commoner"))
		_workers.append(v)
		var door: Vector3 = info.door
		var work: Vector3 = info.work
		var off := Vector3(1.4 * _workers.size() - 2.1, 0, 0.6 * (_workers.size() % 2))
		# To the work (empty-handed), work at it, then home with what was made, and set it down.
		v.set_round([{"at": _world(work + off), "work": 7.0 + _workers.size(), "act": trade[0]},
			{"at": _world(door + Vector3(0, 0, -1.2)), "work": 1.8, "act": "drop", "carry": trade[1]}])
		if record.id == "watchtower":
			v.top_level = false
			v.position = work
			v.round_points = []
	while _workers.size() > n:
		(_workers.pop_back() as Node).queue_free()


func _apply_build() -> void:
	var p := float(record.progress)
	_mat.set_shader_parameter("build", p if not _built else 1.0)
	_scaffold.visible = not _built
	_dust.emitting = not _built
	for b in _builders:
		(b as Villager).visible = not _built


func _process(delta: float) -> void:
	_t += delta
	var built := settlement.is_built(record)
	if built and not _built:
		_built = true
		_finish()
	if not _built:
		_mat.set_shader_parameter("build", float(record.progress))
	var working: bool = built and bool(record.working)
	if _smoke != null:
		_smoke.emitting = working or (built and record.id in ["town_hall", "longhouse"])
	if built:
		_set_workers(int(record.staff) if record.id != "town_hall" else 1)
		for w in _workers:
			(w as Villager).active = working or record.id == "town_hall"
	if _pole != null:
		_pole.visible = _built
	if _flag != null:
		_flag.visible = _built
		# The flag streams downwind.
		var wd := Atmosphere.wind_now_dir
		var want := atan2(-wd.y, wd.x)
		_flag.global_rotation.y = lerp_angle(_flag.global_rotation.y, want, minf(delta * 1.5, 1.0))
	if _cart != null:
		# Back and forth between the face and the heap.
		var k := 0.5 - 0.5 * cos(_t * (0.5 if working else 0.0) * 1.0)
		var a: Vector3 = info.door + Vector3(0, 0, -1.5)
		var b: Vector3 = info.work + Vector3(3.0, 0, -0.5)
		var lp := a.lerp(b, k)
		var wp := global_transform * lp
		_cart.position = lp + Vector3(0, height_at.call(Vector2(wp.x, wp.z)) - global_position.y, 0)
		_cart.rotation.y = atan2(b.x - a.x, b.z - a.z) + PI * 0.5
	if _boat != null and _boat.is_inside_tree():
		var bp := _boat.position
		_boat.position.y = height_at.call(Vector2(bp.x, bp.z)) + 0.15 + sin(_t * 1.3) * 0.12
		_boat.rotation = Vector3(sin(_t * 1.1) * 0.06, _boat.rotation.y, sin(_t * 0.9) * 0.08)
	_update_fires(working)
	if _light != null:
		var glow := 1.0 if working or record.id == "town_hall" else 0.0
		_light.light_energy = lerpf(_light.light_energy, glow * (1.4 + 0.5 * sin(_t * 13.0) * sin(_t * 7.3)), minf(delta * 4.0, 1.0))
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 0.8, 0.0)
		_mat.set_shader_parameter("flash", _flash)


func _finish() -> void:
	_mat.set_shader_parameter("build", 1.0)
	_dust.emitting = false
	var burst := _particles(Color(0.75, 0.68, 0.56, 0.6), 40, 1.6, Vector3(info.size.x * 0.5, 0.5, info.size.y * 0.5), 3.0)
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emitting = true
	for b in _builders:
		(b as Node).queue_free()
	_builders.clear()
	_flash = 1.0
	var tw := create_tween()
	tw.tween_property(_scaffold, "scale", Vector3(1, 0.01, 1), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _scaffold.visible = false)
	if _boat != null:
		_place_boat()


## The fishing boat on the water off the hut, rocking at its mooring.
func _place_boat() -> void:
	_boat.top_level = true
	add_child(_boat)
	var best := Vector2(global_position.x, global_position.z)
	for k in 12:
		var dir := Vector2.from_angle(TAU * k / 12.0)
		for r in [12.0, 18.0, 25.0]:
			var q: Vector2 = Vector2(global_position.x, global_position.z) + dir * float(r)
			if height_at.call(q) <= get_meta("sea_y", -INF) + 0.01:
				best = q
				break
		if best != Vector2(global_position.x, global_position.z):
			break
	_boat.position = Vector3(best.x, 0, best.y)
	_boat.rotation.y = randf() * TAU


## What a work cycle gave and took, over the roof: each good's coin with "+2" beside it, and
## underneath, smaller and in red, the goods it used up ("-1"). Rises and fades.
func pop(gains: Dictionary, uses: Dictionary = {}) -> void:
	if not UiSettings.pops:
		return
	var root := Node3D.new()
	root.position = Vector3(0, float(info.height) + 1.0, 0)
	add_child(root)
	var items: Array = []
	_pop_row(root, gains, "+", 1.0, Color(1.0, 0.97, 0.88), 0.0, items)
	_pop_row(root, uses, "-", 0.72, Color(1.0, 0.55, 0.45), -96.0, items)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "position:y", float(info.height) + 6.0, 2.4)
	for it: Node in items:
		tw.tween_property(it, "modulate:a", 0.0, 1.6).set_delay(0.9)
	tw.chain().tween_callback(root.queue_free)


const POP_PX := 0.0003


func _pop_row(root: Node3D, goods: Dictionary, prefix: String, k_size: float, col: Color, y: float, items: Array) -> void:
	if goods.is_empty():
		return
	var icon_px := 170.0 * k_size
	var gap := 34.0 * k_size
	var font := int(120 * k_size)
	var texts: Array = []
	var width := 0.0
	for k in goods:
		var t := "%s%d" % [prefix, int(goods[k])]
		texts.append(t)
		width += icon_px + font * 0.55 * t.length() + gap
	width -= gap
	var x := -width * 0.5
	var i := 0
	for k in goods:
		var tex := Goods.icon(k)
		if tex != null:
			var sp := Sprite3D.new()
			sp.texture = tex
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.fixed_size = true
			sp.no_depth_test = true
			sp.render_priority = 15
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var ps := POP_PX * icon_px / float(tex.get_width())
			sp.pixel_size = ps
			sp.offset = Vector2(x + icon_px * 0.5, y) * POP_PX / ps
			root.add_child(sp)
			items.append(sp)
		var lb := UiStyle.map_label(texts[i], font, col, Vector2(x + icon_px + 10.0 * k_size + font * 0.275 * String(texts[i]).length(), y), 14)
		root.add_child(lb)
		items.append(lb)
		var sh := lb.get_node_or_null("Shadow") as Label3D
		if sh != null:
			items.append(sh)
		x += icon_px + font * 0.55 * String(texts[i]).length() + gap
		i += 1


func set_selected(on: bool) -> void:
	_flash = 0.6 if on else 0.0
	_mat.set_shader_parameter("flash", _flash)
