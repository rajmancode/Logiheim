class_name Villager
extends Node3D
## One of a settlement's people, seen at work: a jointed figure (tunic flaring over the hips
## with a belt, head with hair and a beard or braids, a hood in the owner's colour; arms that
## bend at the elbow, legs at the knee) going about its round.
##
## Walking: a real gait - legs swing and the knee bends as each foot lifts, the arms swing
## against the legs, the hips bob and the shoulders turn a little. At work each trade has its
## own motion and tool: chopping with an axe (raised over the shoulder and brought down with a
## lean), mining with a pick, hammering at an anvil or a frame, digging with a shovel, reaping
## with a sickle, hauling a net, stirring a vat. Coming back they carry what they made on the
## shoulder (a log, a stone, a sack, a basket of fish); between times they stand and breathe,
## and look about. Rounds: [{at: Vector2, work: seconds, act: String, carry: String}].

const ACTS := ["chop", "pick", "hammer", "dig", "reap", "net", "stir", "idle"]

var height_at: Callable
var round_points: Array = []
var speed := 1.5
var active := true
var act := "idle"

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _sh := []    # shoulders [L, R]
var _el := []    # elbows
var _hp := []    # hip joints
var _kn := []    # knees
var _tool: MeshInstance3D
var _load: MeshInstance3D
var _i := 0
var _working := 0.0
var _t := 0.0
var _phase := 0.0
var _walk := 0.0
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()

static var _parts := {}


func setup(_team: Color, tunic: Color, mat: ShaderMaterial, ground: Callable, p_act := "idle") -> void:
	height_at = ground
	_mat = mat
	act = p_act
	_rng.randomize()
	_phase = _rng.randf() * TAU
	speed = _rng.randf_range(1.3, 1.7)
	var skin := Color(0.88, 0.7, 0.58).lerp(Color(0.72, 0.52, 0.4), _rng.randf())
	var hair: Color = [Color(0.85, 0.7, 0.4), Color(0.55, 0.35, 0.18), Color(0.3, 0.2, 0.12), Color(0.7, 0.35, 0.15), Color(0.8, 0.78, 0.72)][_rng.randi() % 5]
	var bearded := _rng.randf() < 0.55
	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.95, 0)
	add_child(_hips)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_mesh(_torso, _torso_mesh(tunic))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, 0)
	_torso.add_child(_head)
	_mesh(_head, _head_mesh(skin, hair, bearded))
	for s: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(s * 0.21, 0.52, 0)
		_torso.add_child(sh)
		_mesh(sh, _limb_mesh(tunic, 0.065, 0.055, 0.3))
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		_mesh(el, _forearm_mesh(tunic, skin))
		_sh.append(sh)
		_el.append(el)
		var hp := Node3D.new()
		hp.position = Vector3(s * 0.1, 0.0, 0)
		_hips.add_child(hp)
		_mesh(hp, _limb_mesh(Color(0.36, 0.3, 0.22), 0.08, 0.065, 0.46))
		var kn := Node3D.new()
		kn.position = Vector3(0, -0.46, 0)
		hp.add_child(kn)
		_mesh(kn, _shin_mesh())
		_hp.append(hp)
		_kn.append(kn)
	# The tool in the right hand and whatever is being carried, on the left shoulder.
	_tool = MeshInstance3D.new()
	_tool.mesh = _tool_mesh(act)
	_tool.material_override = mat
	_tool.position = Vector3(0, -0.27, 0)
	(_el[1] as Node3D).add_child(_tool)
	_load = MeshInstance3D.new()
	_load.material_override = mat
	_load.position = Vector3(-0.12, 0.62, 0.05)
	_load.visible = false
	_torso.add_child(_load)
	scale = Vector3.ONE * 1.3


func _mesh(parent: Node3D, m: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func set_round(points: Array) -> void:
	round_points = points
	_i = 0
	_working = 0.0
	if not points.is_empty():
		var p: Vector2 = points[0].at
		position = Vector3(p.x, height_at.call(p), p.y)


func _process(delta: float) -> void:
	_t += delta
	if round_points.is_empty():
		_pose_idle()
		return
	if not active:
		_load.visible = false
		_pose_idle()
		return
	var stop: Dictionary = round_points[_i]
	var target: Vector2 = stop.at
	var here := Vector2(position.x, position.z)
	var to := target - here
	if to.length() > 0.3:
		var step := to.normalized() * minf(speed * delta, to.length())
		here += step
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), minf(delta * 6.0, 1.0))
		_walk += delta * speed * 4.2
		var carry := String(stop.get("carry", ""))
		_set_load(carry)
		_pose_walk(_walk, carry != "")
		position = Vector3(here.x, height_at.call(here), here.y)
		_working = 0.0
		return
	_working += delta
	var a := String(stop.get("act", act))
	if a == "drop":
		_set_load("")
		_pose_idle()
	else:
		_set_load("")
		_pose_work(a, _t)
	if _working >= float(stop.get("work", 2.0)):
		_i = (_i + 1) % round_points.size()
		_working = 0.0


func _set_load(kind: String) -> void:
	if kind == "":
		_load.visible = false
		return
	_load.visible = true
	_load.mesh = _load_mesh(kind)


# --------------------------------------------------------------------------- poses

func _pose_walk(ph: float, carrying: bool) -> void:
	_hips.position.y = 0.95 + 0.035 * cos(ph * 2.0)
	_hips.rotation = Vector3(0.05, 0, 0)
	_torso.rotation = Vector3(0.0, sin(ph) * 0.12, 0.0)
	_head.rotation = Vector3(-0.05, -sin(ph) * 0.1, 0.0)
	for i in 2:
		var p := ph + PI * i
		# Leg: swing from the hip; the knee bends as the foot lifts and comes through.
		(_hp[i] as Node3D).rotation.x = sin(p) * 0.5
		(_kn[i] as Node3D).rotation.x = -(0.1 + 0.75 * maxf(0.0, sin(p - 1.3)))
		# Arm: against the leg on the same side.
		var arm := -sin(p) * 0.45
		(_sh[i] as Node3D).rotation = Vector3(arm, 0, (0.08 if i == 1 else -0.08))
		(_el[i] as Node3D).rotation.x = -0.35 - 0.25 * maxf(0.0, -sin(p))
	if carrying:
		# Left arm up, steadying the load on the shoulder.
		(_sh[0] as Node3D).rotation = Vector3(-2.7, 0, -0.25)
		(_el[0] as Node3D).rotation.x = -1.6
	_tool.visible = not carrying


func _pose_idle() -> void:
	var br := sin(_t * 1.6 + _phase)
	_hips.position.y = 0.95
	_hips.rotation = Vector3.ZERO
	_torso.rotation = Vector3(0.02 * br, 0, 0)
	_torso.scale = Vector3(1.0 + 0.015 * br, 1.0, 1.0 + 0.015 * br)
	# Now and then a look about.
	_head.rotation.y = sin(_t * 0.37 + _phase) * 0.6 * smoothstep(0.3, 0.8, sin(_t * 0.21 + _phase * 2.0))
	for i in 2:
		(_hp[i] as Node3D).rotation.x = 0.0
		(_kn[i] as Node3D).rotation.x = 0.0
		(_sh[i] as Node3D).rotation = Vector3(0.05 * br, 0, (0.12 if i == 1 else -0.12))
		(_el[i] as Node3D).rotation.x = -0.25
	_tool.visible = true


## Working poses: a cycle per trade (the swing timing is eased - slow wind-up, fast strike).
func _pose_work(a: String, t: float) -> void:
	_torso.scale = Vector3.ONE
	_tool.visible = true
	for i in 2:
		(_hp[i] as Node3D).rotation.x = 0.0
		(_kn[i] as Node3D).rotation.x = 0.0
	var sh_l := _sh[0] as Node3D
	var sh_r := _sh[1] as Node3D
	var el_l := _el[0] as Node3D
	var el_r := _el[1] as Node3D
	match a:
		"chop", "pick":
			# Both hands on the haft: raise over the right shoulder, then bring it down hard.
			var c := fmod(t / 1.4 + _phase, 1.0)
			var up := smoothstep(0.0, 0.55, c) * (1.0 - smoothstep(0.6, 0.72, c))
			var lean := smoothstep(0.6, 0.72, c) * (1.0 - smoothstep(0.8, 1.0, c))
			var arm := lerpf(-0.6, -2.9, up)
			sh_r.rotation = Vector3(arm, 0, 0.15)
			sh_l.rotation = Vector3(arm + 0.15, 0, 0.45)
			el_r.rotation.x = lerpf(-0.6, -0.9, up)
			el_l.rotation.x = lerpf(-0.9, -1.1, up)
			_hips.rotation = Vector3(0.25 * lean, 0, 0)
			_torso.rotation = Vector3(0.2 * lean, -0.25 * up, 0)
			_hips.position.y = 0.95 - 0.06 * lean
			(_kn[0] as Node3D).rotation.x = -0.25 * lean
			(_kn[1] as Node3D).rotation.x = -0.25 * lean
			(_hp[0] as Node3D).rotation.x = 0.15 * lean
			(_hp[1] as Node3D).rotation.x = 0.15 * lean
		"hammer":
			# Quick blows with the right hand; the left holds the work steady.
			var c := fmod(t / 0.75 + _phase, 1.0)
			var up := smoothstep(0.0, 0.6, c) * (1.0 - smoothstep(0.65, 0.78, c))
			sh_r.rotation = Vector3(lerpf(-0.7, -2.1, up), 0, 0.2)
			el_r.rotation.x = lerpf(-0.9, -1.5, up)
			sh_l.rotation = Vector3(-0.9, 0, -0.1)
			el_l.rotation.x = -0.6
			_torso.rotation = Vector3(0.15, 0, 0)
			_hips.rotation = Vector3(0.1, 0, 0)
			_hips.position.y = 0.95
		"dig":
			# Shovel: lean in, push down, lever up and throw.
			var c := fmod(t / 1.8 + _phase, 1.0)
			var push := smoothstep(0.0, 0.35, c) * (1.0 - smoothstep(0.5, 0.75, c))
			var lift := smoothstep(0.45, 0.7, c) * (1.0 - smoothstep(0.85, 1.0, c))
			sh_r.rotation = Vector3(-0.6 - 0.6 * lift + 0.3 * push, 0, 0.1)
			sh_l.rotation = Vector3(-1.0 - 0.6 * lift, 0, 0.3)
			el_r.rotation.x = -0.4
			el_l.rotation.x = -0.9
			_hips.rotation = Vector3(0.35 * push + 0.15, 0, 0)
			_torso.rotation = Vector3(0.25 * push, 0.3 * lift, 0)
			_hips.position.y = 0.95 - 0.12 * push
			(_kn[0] as Node3D).rotation.x = -0.5 * push
			(_kn[1] as Node3D).rotation.x = -0.3 * push
			(_hp[0] as Node3D).rotation.x = 0.35 * push
		"reap":
			# Bent over, sweeping the sickle through the stalks, the other hand gathering.
			var c := sin(t * 2.6 + _phase)
			_hips.rotation = Vector3(0.55, 0, 0)
			_hips.position.y = 0.88
			_torso.rotation = Vector3(0.2, c * 0.25, 0)
			sh_r.rotation = Vector3(-0.9, c * 0.6, 0.3 + 0.4 * c)
			el_r.rotation.x = -0.5
			sh_l.rotation = Vector3(-1.0, 0, -0.2)
			el_l.rotation.x = -0.7
			(_kn[0] as Node3D).rotation.x = -0.4
			(_kn[1] as Node3D).rotation.x = -0.4
			(_hp[0] as Node3D).rotation.x = 0.2
			(_hp[1] as Node3D).rotation.x = 0.2
		"net":
			# Hauling in a net hand over hand.
			var c := fmod(t / 1.2 + _phase, 1.0)
			var s := sin(c * TAU)
			sh_r.rotation = Vector3(-1.3 + 0.6 * s, 0, 0.1)
			sh_l.rotation = Vector3(-1.3 - 0.6 * s, 0, -0.1)
			el_r.rotation.x = -0.6 - 0.4 * maxf(s, 0.0)
			el_l.rotation.x = -0.6 - 0.4 * maxf(-s, 0.0)
			_hips.rotation = Vector3(-0.1 + 0.08 * s, 0, 0)
			_torso.rotation = Vector3(0.1, 0, 0)
			_hips.position.y = 0.93
		"stir":
			# Both hands on a paddle, stirring round and round.
			var c := t * 1.8 + _phase
			sh_r.rotation = Vector3(-1.2 + 0.3 * sin(c), 0.3 * cos(c), 0.1)
			sh_l.rotation = Vector3(-1.4 + 0.3 * sin(c), 0.3 * cos(c), -0.1)
			el_r.rotation.x = -0.7
			el_l.rotation.x = -0.6
			_torso.rotation = Vector3(0.15, 0.15 * sin(c), 0)
			_hips.rotation = Vector3(0.05, 0, 0)
			_hips.position.y = 0.95
		_:
			_pose_idle()


# --------------------------------------------------------------------------- meshes

func _torso_mesh(tunic: Color) -> Mesh:
	var key := "torso_" + tunic.to_html()
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	# Tunic skirt flaring over the hips, the body, shoulders; a belt.
	k.frustum(Vector3(0, -0.22, 0), 0.24, 0.17, 0.26, tunic)
	k.frustum(Vector3(0, 0.04, 0), 0.17, 0.2, 0.46, tunic)
	k.frustum(Vector3(0, 0.0, 0), 0.18, 0.18, 0.07, Color(0.3, 0.2, 0.12))
	k.box(Vector3(0.06, 0.03, -0.17), Vector3(0.07, 0.06, 0.03), BuildingModels.IRON)
	k.frustum(Vector3(0, 0.5, 0), 0.2, 0.1, 0.1, tunic)
	k.frustum(Vector3(0, 0.56, 0), 0.06, 0.06, 0.08, Color(0.85, 0.66, 0.54))
	var m := k.commit()
	_parts[key] = m
	return m


func _head_mesh(skin: Color, hair: Color, bearded: bool) -> Mesh:
	var key := "head_%s_%s_%s" % [skin.to_html(), hair.to_html(), bearded]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	k.sphere(Vector3(0, 0.1, 0), 0.115, skin)
	# Nose, eyes.
	k.box(Vector3(0, 0.09, -0.115), Vector3(0.035, 0.05, 0.04), skin * 0.95)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 0.04, 0.13, -0.105), Vector3(0.025, 0.018, 0.01), Color(0.12, 0.1, 0.08))
	# Hair at the back and sides, and either a beard or braids.
	k.box(Vector3(0, 0.12, 0.05), Vector3(0.24, 0.16, 0.14), hair)
	if bearded:
		k.frustum(Vector3(0, -0.05, -0.06), 0.03, 0.09, 0.12, hair)
	else:
		for s: float in [-1.0, 1.0]:
			k.frustum(Vector3(s * 0.11, -0.12, 0.03), 0.025, 0.03, 0.22, hair)
	# A hood in the owner's colour.
	k.frustum(Vector3(0, 0.08, 0.02), 0.14, 0.015, 0.26, BuildingModels.TEAM)
	var m := k.commit()
	_parts[key] = m
	return m


## An upper arm or thigh hanging down from its joint.
func _limb_mesh(col: Color, r0: float, r1: float, length: float) -> Mesh:
	var key := "limb_%s_%.3f_%.2f" % [col.to_html(), r0, length]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	k.frustum(Vector3(0, -length, 0), r1, r0, length, col)
	k.sphere(Vector3.ZERO, r0, col)
	var m := k.commit()
	_parts[key] = m
	return m


func _forearm_mesh(tunic: Color, skin: Color) -> Mesh:
	var key := "fore_%s_%s" % [tunic.to_html(), skin.to_html()]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	k.frustum(Vector3(0, -0.22, 0), 0.045, 0.055, 0.22, tunic.lerp(skin, 0.5))
	k.sphere(Vector3(0, -0.26, 0), 0.05, skin)
	var m := k.commit()
	_parts[key] = m
	return m


func _shin_mesh() -> Mesh:
	if _parts.has("shin"):
		return _parts["shin"]
	var k := BuildingModels.Kit.new()
	# Leg wrappings and a leather shoe.
	k.frustum(Vector3(0, -0.42, 0), 0.05, 0.065, 0.42, Color(0.5, 0.44, 0.36))
	k.box(Vector3(0, -0.45, -0.05), Vector3(0.11, 0.08, 0.24), Color(0.25, 0.17, 0.1))
	var m := k.commit()
	_parts["shin"] = m
	return m


## The tool for a trade, held in the right hand (along -y from the hand, head forward).
static func _tool_mesh(a: String) -> Mesh:
	var key := "tool_" + a
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	var haft := BuildingModels.PALE_WOOD
	match a:
		"chop":
			k.box(Vector3(0, 0, -0.35), Vector3(0.04, 0.04, 0.8), haft)
			k.box(Vector3(0, 0.0, -0.74), Vector3(0.03, 0.2, 0.14), BuildingModels.IRON)
		"pick":
			k.box(Vector3(0, 0, -0.35), Vector3(0.04, 0.04, 0.8), haft)
			k.box(Vector3(0, 0.0, -0.72), Vector3(0.04, 0.4, 0.05), BuildingModels.IRON)
		"hammer":
			k.box(Vector3(0, 0, -0.18), Vector3(0.035, 0.035, 0.42), haft)
			k.box(Vector3(0, 0, -0.4), Vector3(0.08, 0.08, 0.14), BuildingModels.IRON)
		"dig":
			k.box(Vector3(0, 0, -0.4), Vector3(0.035, 0.035, 0.9), haft)
			k.box(Vector3(0, 0, -0.88), Vector3(0.18, 0.02, 0.22), BuildingModels.IRON)
		"reap":
			k.box(Vector3(0, 0, -0.1), Vector3(0.03, 0.03, 0.2), haft)
			k.box(Vector3(0.07, 0, -0.24), Vector3(0.16, 0.015, 0.04), BuildingModels.IRON)
		"net":
			k.box(Vector3(0, -0.15, -0.1), Vector3(0.35, 0.3, 0.02), Color(0.55, 0.5, 0.4))
		"stir":
			k.box(Vector3(0, 0, -0.5), Vector3(0.035, 0.035, 1.1), haft)
			k.box(Vector3(0, 0, -1.05), Vector3(0.12, 0.02, 0.2), haft)
		_:
			k.box(Vector3(0, -0.02, -0.02), Vector3(0.01, 0.01, 0.01), haft)
	var m := k.commit()
	_parts[key] = m
	return m


static func _load_mesh(kind: String) -> Mesh:
	var key := "load_" + kind
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	match kind:
		"log":
			k.log(Vector3(0, 0.08, 0), 0.11, 1.4, BuildingModels.PALE_WOOD, Vector3(0.2, 0, 1).normalized())
		"stone":
			k.box(Vector3(0, 0.1, 0), Vector3(0.32, 0.24, 0.3), BuildingModels.STONE)
		"fish":
			k.frustum(Vector3(0, -0.02, 0), 0.16, 0.2, 0.24, BuildingModels.THATCH)
			for i in 3:
				k.box(Vector3(-0.08 + i * 0.08, 0.24, 0), Vector3(0.05, 0.08, 0.26), Color(0.6, 0.64, 0.66))
		_:
			k.sphere(Vector3(0, 0.12, 0), 0.17, Color(0.72, 0.64, 0.48))
			k.frustum(Vector3(0, 0.26, 0), 0.05, 0.03, 0.08, Color(0.6, 0.52, 0.38))
	var m := k.commit()
	_parts[key] = m
	return m
