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
var _flag: MeshInstance3D
var _cart: MeshInstance3D
var _boat: MeshInstance3D
var _light: OmniLight3D
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
	if info.flag != null:
		_flag = MeshInstance3D.new()
		_flag.mesh = BuildingModels.banner()
		_flag.material_override = _people_mat
		_flag.position = info.flag
		add_child(_flag)
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
	# Builders at the site while it goes up.
	for i in 2:
		var v := _villager(Color(0.55, 0.45, 0.32), "hammer")
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
}


func _villager(tunic: Color, a := "idle") -> Villager:
	var v := Villager.new()
	v.setup(settlement.color, tunic, _people_mat, height_at, a)
	get_tree_root_add(v)
	return v


## Villagers move in world space (their rounds cross the ground outside the building).
func get_tree_root_add(v: Node3D) -> void:
	v.top_level = true
	add_child(v)


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
		var v := _villager(tunics[_workers.size() % tunics.size()], trade[0])
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
	if _flag != null:
		_flag.rotation = Vector3(0, sin(_t * 1.1) * 0.35, sin(_t * 2.3) * 0.06)
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


## A "+2 Wood" over the roof, rising and fading.
func pop(gains: Dictionary) -> void:
	var parts := PackedStringArray()
	var col := Color.WHITE
	for k in gains:
		if k == "influence":
			parts.append("+%d Influence" % int(gains[k]))
			col = Color(0.75, 0.6, 1.0)
		else:
			parts.append("+%d %s" % [int(gains[k]), Goods.display_name(k)])
			col = Goods.color(k).lightened(0.35)
	var lb := UiStyle.map_label(" ".join(parts), 64, col, Vector2.ZERO, 14)
	lb.position = Vector3(0, float(info.height) + 1.0, 0)
	add_child(lb)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lb, "position:y", float(info.height) + 6.0, 2.2)
	tw.tween_property(lb, "modulate:a", 0.0, 2.2).set_delay(0.6)
	var sh := lb.get_node_or_null("Shadow") as Label3D
	if sh != null:
		tw.tween_property(sh, "modulate:a", 0.0, 2.0).set_delay(0.6)
	tw.chain().tween_callback(lb.queue_free)


func set_selected(on: bool) -> void:
	_flash = 0.6 if on else 0.0
	_mat.set_shader_parameter("flash", _flash)
