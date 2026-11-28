class_name Villager
extends Node3D
## One of a settlement's people, seen at work: a jointed figure going about its round. Men
## wear a knee-length tunic with a belt and buckle, trousers with leg wraps, and a cloak in the
## owner's colour pinned at the shoulder; women a long underdress with an apron dress over it,
## held by two oval brooches with a string of beads between, and a shawl in the owner's colour.
## Hair, beards, braids, buns, hoods and headscarves vary from one to the next. Arms bend at
## the elbow and legs at the knee; cloaks and skirts swing as they walk.
##
## Each trade dresses its own way (Outfits, setup(..., occupation)): its colours, headgear,
## apron, cloak, belt kit, what it carries on its back and the tool in its hand.
##
## Soldiers (setup(..., soldier = true)) wear an iron helmet with a nose guard, carry a round
## shield in the owner's colour on the left arm and a long spear. They march to a place given
## by march_to() (their spot in an army's formation) and stand there in a stance: "guard"
## (spear upright, shield at the side) or "brace" (shields up, spears levelled: a shield wall).
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
var _cloak: Node3D
var _skirt: Node3D
var _female := false
var _tool: MeshInstance3D
var _load: MeshInstance3D
var _i := 0
var _working := 0.0
var _t := 0.0
var _phase := 0.0
var _walk := 0.0
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var soldier := false
var _shield: MeshInstance3D
## Marching (soldiers): where to go, which way to face there, and how to stand.
var marching := false
var goal := Vector2.ZERO
var goal_face := 0.0
var stance := "guard"

static var _parts := {}
const LINEN_DYES := [Color(0.88, 0.85, 0.76), Color(0.7, 0.25, 0.2), Color(0.3, 0.4, 0.6)]


## The clan's colour in a sash over the belt, for those without a cloak.
func _sash_mesh() -> Mesh:
	if _parts.has("sash"):
		return _parts["sash"]
	var k := BuildingModels.Kit.new()
	k.frustum(Vector3(0, -0.045, 0), 0.208, 0.206, 0.065, BuildingModels.TEAM, 16)
	k.box(Vector3(0.12, -0.12, -0.17), Vector3(0.05, 0.14, 0.02), BuildingModels.TEAM, Vector3(0, 0, 0.2))
	var m := k.commit()
	_parts["sash"] = m
	return m


var occupation := "commoner"


func setup(_team: Color, tunic: Color, mat: ShaderMaterial, ground: Callable, p_act := "idle", p_soldier := false, p_occupation := "") -> void:
	occupation = p_occupation if p_occupation != "" else "commoner"
	var sp := Outfits.spec(occupation)
	height_at = ground
	_mat = mat
	act = p_act
	soldier = p_soldier
	if soldier:
		act = "spear"
	_rng.randomize()
	_phase = _rng.randf() * TAU
	speed = _rng.randf_range(1.3, 1.7)
	var skin := Color(0.9, 0.73, 0.6).lerp(Color(0.74, 0.54, 0.42), _rng.randf())
	var hair: Color = [Color(0.86, 0.72, 0.42), Color(0.92, 0.82, 0.55), Color(0.55, 0.35, 0.18), Color(0.3, 0.2, 0.12), Color(0.72, 0.36, 0.14), Color(0.62, 0.5, 0.32)][_rng.randi() % 6]
	if _rng.randf() < float(sp.get("elder", 0.12)):
		hair = Color(0.82, 0.8, 0.76).lerp(Color(0.62, 0.6, 0.58), _rng.randf())
	_female = _rng.randf() < float(sp.get("women", 0.45)) and not soldier
	# Clothes: plant-dyed wool and linen in the trade's colours.
	if not soldier and occupation != "commoner":
		var tp: Array = sp.get("tunic", [tunic])
		tunic = tp[_rng.randi() % tp.size()]
		tunic = tunic * (0.92 + 0.16 * _rng.randf())
		tunic.a = 1.0
	var dp: Array = sp.get("dress", [Color(0.62, 0.22, 0.16), Color(0.28, 0.36, 0.55), Color(0.4, 0.5, 0.3), Color(0.7, 0.58, 0.32), Color(0.5, 0.36, 0.5)])
	var dress: Color = dp[_rng.randi() % dp.size()]
	var under := Color(0.86, 0.82, 0.72).lerp(Color(0.72, 0.66, 0.55), _rng.randf())
	var lp: Array = sp.get("legs", [Color(0.36, 0.3, 0.22), Color(0.3, 0.32, 0.36), Color(0.4, 0.36, 0.3)])
	var legs: Color = lp[_rng.randi() % lp.size()]
	var hat := String(sp.get("hat_f", "none") if _female else sp.get("hat", "none"))
	if soldier:
		hat = "none"
	var style := _rng.randi() % 3
	# A hat hides the hood (men); a headscarf is a woman's hat of its own.
	if not _female and hat != "none" and style == 1:
		style = 0 if _rng.randf() < 0.6 else 2
	if _female and hat == "scarf":
		style = 2
		hat = "none"
	elif _female and hat != "none" and style == 2:
		style = 0
	var body := (under if _female else tunic)
	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.95, 0)
	add_child(_hips)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_mesh(_torso, _torso_mesh(dress if _female else tunic, _female, under))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, 0)
	_torso.add_child(_head)
	_mesh(_head, _head_mesh(skin, hair, _female, style))
	if soldier:
		_mesh(_head, _helmet_mesh())
	elif hat != "none":
		var hcol: Color = sp.get("hood_col", [Color(0.6, 0.2, 0.15), Color(0.25, 0.35, 0.55), Color(0.4, 0.45, 0.35), LINEN_DYES[_rng.randi() % LINEN_DYES.size()]][_rng.randi() % 4])
		_mesh(_head, Outfits.hat_mesh(hat, hcol))
	# A skirt (or the tunic's hem) that hangs from the hips and swings as the legs move.
	_skirt = Node3D.new()
	_skirt.position = Vector3(0, -0.02, 0)
	_hips.add_child(_skirt)
	_mesh(_skirt, _skirt_mesh(dress if _female else tunic, _female, under))
	# A cloak (men) or a shawl (women) in the owner's colour, hanging from the shoulders.
	_cloak = Node3D.new()
	_cloak.position = Vector3(0, 0.56, 0.13)
	_torso.add_child(_cloak)
	var cloak := "team" if soldier else String(sp.get("cloak", "team"))
	match cloak:
		"team":
			_mesh(_cloak, _cloak_mesh(_female))
		"fur":
			_mesh(_cloak, Outfits.fur_cloak_mesh(Outfits.FUR if _rng.randf() < 0.6 else Outfits.FUR_GREY))
		"team_fur":
			_mesh(_cloak, _cloak_mesh(_female))
			_mesh(_cloak, Outfits.collar_mesh())
		_:
			# No cloak: the clan's colour in a woven sash at the waist.
			_mesh(_hips, _sash_mesh())
	if not soldier:
		if sp.has("apron"):
			_mesh(_skirt, Outfits.apron_mesh(sp.apron, _female))
			if sp.get("bib", false):
				_mesh(_torso, Outfits.bib_mesh(sp.apron))
		if String(sp.get("back", "none")) != "none":
			_mesh(_torso, Outfits.back_mesh(String(sp.back)))
		if sp.has("belt"):
			_mesh(_hips, Outfits.belt_mesh(sp.belt))
	var bare: bool = sp.get("bare_arms", false) and not soldier
	for s: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(s * (0.19 if _female else 0.23), 0.52, 0)
		_torso.add_child(sh)
		_mesh(sh, _limb_mesh(body, 0.07, 0.058, 0.3))
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		_mesh(el, _forearm_mesh(skin if bare else body, skin))
		_sh.append(sh)
		_el.append(el)
		var hp := Node3D.new()
		hp.position = Vector3(s * 0.1, 0.0, 0)
		_hips.add_child(hp)
		_mesh(hp, _limb_mesh(legs, 0.085, 0.068, 0.46))
		var kn := Node3D.new()
		kn.position = Vector3(0, -0.46, 0)
		hp.add_child(kn)
		_mesh(kn, _shin_mesh())
		_hp.append(hp)
		_kn.append(kn)
	# The tool in the right hand and whatever is being carried, on the left shoulder.
	_tool = MeshInstance3D.new()
	_tool.mesh = Outfits.tool_mesh(String(sp.tool)) if sp.has("tool") and not soldier else _tool_mesh(act)
	_tool.material_override = mat
	_tool.position = Vector3(0, -0.27, 0)
	(_el[1] as Node3D).add_child(_tool)
	_load = MeshInstance3D.new()
	_load.material_override = mat
	_load.position = Vector3(-0.12, 0.62, 0.05)
	_load.visible = false
	_torso.add_child(_load)
	if soldier:
		_shield = MeshInstance3D.new()
		_shield.mesh = _shield_mesh()
		_shield.material_override = mat
		_shield.position = Vector3(-0.02, -0.16, -0.1)
		(_el[0] as Node3D).add_child(_shield)
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


## Soldiers: go to `p` and face `face` (radians) there, standing in `how` ("guard"/"brace").
func march_to(p: Vector2, face: float, how := "guard") -> void:
	marching = true
	goal = p
	goal_face = face
	stance = how


func _process(delta: float) -> void:
	_t += delta
	if marching:
		_march(delta)
		return
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


func _march(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	var to := goal - here
	var dist := to.length()
	if dist > 0.25:
		var spd := clampf(dist * 1.6, 0.6, 3.6)
		here += to.normalized() * minf(spd * delta, dist)
		var face := atan2(-to.x, -to.y) if dist > 1.2 else goal_face
		rotation.y = lerp_angle(rotation.y, face, minf(delta * 6.0, 1.0))
		_walk += delta * spd * 3.0
		_pose_walk(_walk, false)
		# Spear sloped on the shoulder, shield on the arm.
		(_sh[1] as Node3D).rotation = Vector3(-0.25, 0, 0.12)
		(_el[1] as Node3D).rotation.x = -1.3
		_tool.rotation.x = PI * 0.5 - 0.35
		(_sh[0] as Node3D).rotation = Vector3(-0.4 + sin(_walk) * 0.1, 0, -0.2)
		(_el[0] as Node3D).rotation.x = -1.0
		if _shield != null:
			_shield.rotation.x = 1.0
		position = Vector3(here.x, height_at.call(here), here.y)
	else:
		rotation.y = lerp_angle(rotation.y, goal_face, minf(delta * 5.0, 1.0))
		_pose_stance()


## Standing in formation: on guard, or braced in the shield wall.
func _pose_stance() -> void:
	var br := sin(_t * 1.6 + _phase)
	_cloak.rotation = Vector3(0.04 + 0.02 * br, 0, 0)
	_skirt.rotation = Vector3.ZERO
	_tool.visible = true
	for i in 2:
		(_hp[i] as Node3D).rotation.x = 0.0
		(_kn[i] as Node3D).rotation.x = 0.0
	_head.rotation = Vector3.ZERO
	if stance == "brace":
		# Crouched a little, shield up in front, spear levelled over it.
		_hips.position.y = 0.88
		_hips.rotation = Vector3(0.12, 0, 0)
		(_hp[0] as Node3D).rotation.x = 0.35
		(_kn[0] as Node3D).rotation.x = -0.45
		(_hp[1] as Node3D).rotation.x = -0.15
		(_kn[1] as Node3D).rotation.x = -0.2
		(_sh[0] as Node3D).rotation = Vector3(-1.2, 0, -0.1)
		(_el[0] as Node3D).rotation.x = -0.5
		if _shield != null:
			_shield.rotation.x = 1.7
		(_sh[1] as Node3D).rotation = Vector3(-1.4, 0, 0.15)
		(_el[1] as Node3D).rotation.x = 0.0
		_tool.rotation.x = -1.45
	else:
		# Spear upright at the side, shield on the arm.
		_hips.position.y = 0.95 + 0.004 * br
		_hips.rotation = Vector3.ZERO
		(_sh[0] as Node3D).rotation = Vector3(-0.35, 0, -0.2)
		(_el[0] as Node3D).rotation.x = -1.1
		if _shield != null:
			_shield.rotation.x = 1.45
		(_sh[1] as Node3D).rotation = Vector3(-0.15, 0, 0.12)
		(_el[1] as Node3D).rotation.x = -1.4
		_tool.rotation.x = PI * 0.5 - 0.1


func _set_load(kind: String) -> void:
	if kind == "":
		_load.visible = false
		return
	_load.visible = true
	_load.mesh = _load_mesh(kind)


# --------------------------------------------------------------------------- poses

func _pose_walk(ph: float, carrying: bool) -> void:
	_cloak.rotation = Vector3(0.28 + 0.06 * sin(ph * 2.0 + 0.6), 0, 0.05 * sin(ph))
	_skirt.rotation = Vector3(0.05 * cos(ph * 2.0), 0, 0.07 * sin(ph))
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
	_cloak.rotation = Vector3(0.04 + 0.02 * sin(_t * 0.9 + _phase), 0, 0.02 * sin(_t * 0.7))
	_skirt.rotation = Vector3.ZERO
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
	_cloak.rotation = Vector3(0.1 + 0.05 * sin(t * 2.0 + _phase), 0, 0)
	_skirt.rotation = Vector3.ZERO
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

## The body from the waist up. Men: tunic with a belt and buckle. Women: the underdress's
## sleeves and an apron dress over the chest held by two oval brooches with beads between.
func _torso_mesh(cloth: Color, female: bool, under: Color) -> Mesh:
	var key := "torso_%s_%s_%s" % [cloth.to_html(), female, under.to_html()]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	if female:
		k.frustum(Vector3(0, -0.02, 0), 0.16, 0.18, 0.5, under, 14)
		k.frustum(Vector3(0, 0.02, 0), 0.17, 0.185, 0.36, cloth, 14)
		for sd: float in [-1.0, 1.0]:
			k.sphere(Vector3(sd * 0.09, 0.36, -0.16), 0.045, Color(0.85, 0.66, 0.25), 4, 8)
			k.box(Vector3(sd * 0.09, 0.42, -0.15), Vector3(0.025, 0.12, 0.02), cloth * 0.85)
		for i in 5:
			var x := -0.08 + i * 0.04
			k.sphere(Vector3(x, 0.31 - 0.03 * (1.0 - absf(x) / 0.08), -0.175), 0.016, [Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7), Color(0.9, 0.75, 0.3)][i % 3], 3, 6)
		k.frustum(Vector3(0, 0.5, 0), 0.17, 0.09, 0.1, under, 12)
	else:
		k.frustum(Vector3(0, 0.0, 0), 0.19, 0.23, 0.48, cloth, 14)
		k.frustum(Vector3(0, -0.02, 0), 0.2, 0.2, 0.07, Color(0.3, 0.2, 0.12), 14)
		k.box(Vector3(0.05, 0.015, -0.2), Vector3(0.08, 0.07, 0.03), Color(0.8, 0.65, 0.3))
		# The neck opening, trimmed.
		k.frustum(Vector3(0, 0.46, 0), 0.2, 0.1, 0.1, cloth * 0.9, 14)
	k.frustum(Vector3(0, 0.54, 0), 0.06, 0.055, 0.1, Color(0.88, 0.69, 0.56), 8)
	var m := k.commit()
	_parts[key] = m
	return m


## From the waist down: the tunic's flared hem to the knee, or a dress to the ankle with the
## apron dress over it.
func _skirt_mesh(cloth: Color, female: bool, under: Color) -> Mesh:
	var key := "skirt_%s_%s_%s" % [cloth.to_html(), female, under.to_html()]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	if female:
		k.frustum(Vector3(0, -0.84, 0), 0.3, 0.19, 0.86, under, 16)
		k.frustum(Vector3(0, -0.66, 0), 0.27, 0.19, 0.68, cloth, 16)
	else:
		k.frustum(Vector3(0, -0.36, 0), 0.27, 0.2, 0.36, cloth, 16)
		k.frustum(Vector3(0, -0.37, 0), 0.275, 0.272, 0.04, cloth * 0.7, 16)
	var m := k.commit()
	_parts[key] = m
	return m


## A cloak (to the knee, wide at the hem) or a shawl (round the shoulders), in the owner's colour.
func _cloak_mesh(female: bool) -> Mesh:
	var key := "cloak_%s" % female
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	var T := BuildingModels.TEAM
	if female:
		k.quad2(Vector3(-0.24, 0.02, -0.02), Vector3(0.24, 0.02, -0.02), Vector3(0.0, -0.42, 0.06), Vector3(0.0, -0.42, 0.06), T)
		k.quad2(Vector3(-0.24, 0.02, -0.02), Vector3(-0.26, -0.2, -0.05), Vector3(-0.1, -0.3, 0.05), Vector3(0.0, -0.42, 0.06), T)
		k.quad2(Vector3(0.24, 0.02, -0.02), Vector3(0.26, -0.2, -0.05), Vector3(0.1, -0.3, 0.05), Vector3(0.0, -0.42, 0.06), T)
	else:
		var top := [Vector3(-0.25, 0.0, -0.06), Vector3(-0.15, 0.03, 0.02), Vector3(0.15, 0.03, 0.02), Vector3(0.25, 0.0, -0.06)]
		var hem := [Vector3(-0.36, -0.95, 0.02), Vector3(-0.17, -0.97, 0.12), Vector3(0.17, -0.97, 0.12), Vector3(0.36, -0.95, 0.02)]
		for i in 3:
			k.quad2(top[i], top[i + 1], hem[i + 1], hem[i], T)
		# The ring brooch on the right shoulder.
		k.cylinder(Vector3(0.2, 0.02, -0.08), 0.05, 0.02, Color(0.82, 0.66, 0.3), 10, Vector3.BACK)
	var m := k.commit()
	_parts[key] = m
	return m


## The head: face, hair in one of several styles; men bearded or not, some hooded; women with
## a bun, long braids or a headscarf.
func _head_mesh(skin: Color, hair: Color, female: bool, style: int) -> Mesh:
	var key := "head_%s_%s_%s_%d" % [skin.to_html(), hair.to_html(), female, style]
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	k.sphere(Vector3(0, 0.11, 0), 0.12, skin, 10, 14)
	# Jaw and chin a little forward, the nose.
	k.sphere(Vector3(0, 0.055, -0.035), 0.085, skin, 6, 10)
	k.box(Vector3(0, 0.105, -0.122), Vector3(0.032, 0.05, 0.04), skin * 0.93, Vector3(0.25, 0, 0))
	for sd: float in [-1.0, 1.0]:
		k.box(Vector3(sd * 0.042, 0.133, -0.11), Vector3(0.03, 0.02, 0.008), Color(0.95, 0.93, 0.88))
		k.box(Vector3(sd * 0.042, 0.133, -0.115), Vector3(0.014, 0.018, 0.006), Color(0.16, 0.22, 0.3) if hair.r > 0.6 else Color(0.18, 0.13, 0.08))
		k.box(Vector3(sd * 0.043, 0.158, -0.113), Vector3(0.042, 0.011, 0.012), hair * 0.75, Vector3(0, 0, -sd * 0.12))
		k.sphere(Vector3(sd * 0.121, 0.11, 0.0), 0.026, skin * 0.95, 3, 6)
		k.sphere(Vector3(sd * 0.068, 0.088, -0.098), 0.02, skin.lerp(Color(0.85, 0.5, 0.45), 0.18), 3, 6)
	k.box(Vector3(0, 0.058, -0.113), Vector3(0.046, 0.009, 0.01), Color(0.55, 0.3, 0.26))
	# Hair over the crown and down the back.
	k.sphere(Vector3(0, 0.15, 0.025), 0.128, hair, 6, 12)
	k.sphere(Vector3(0, 0.07, 0.06), 0.112, hair, 6, 12)
	if female:
		match style:
			0:
				# A bun at the back.
				k.sphere(Vector3(0, 0.15, 0.15), 0.065, hair, 5, 8)
			1:
				# Two long braids over the shoulders.
				for sd: float in [-1.0, 1.0]:
					k.frustum(Vector3(sd * 0.1, -0.26, -0.02), 0.022, 0.034, 0.36, hair, 6)
			_:
				# A linen headscarf.
				k.sphere(Vector3(0, 0.16, 0.03), 0.138, Color(0.9, 0.87, 0.8), 6, 12)
				k.frustum(Vector3(0, -0.02, 0.07), 0.13, 0.12, 0.16, Color(0.9, 0.87, 0.8), 10)
	else:
		match style:
			0:
				# A full beard and moustache.
				k.frustum(Vector3(0, -0.07, -0.06), 0.04, 0.1, 0.15, hair, 10)
				k.box(Vector3(0, 0.07, -0.115), Vector3(0.1, 0.025, 0.03), hair)
			1:
				# A long braided beard, and a hood in the owner's colour.
				k.frustum(Vector3(0, -0.16, -0.08), 0.025, 0.08, 0.24, hair, 8)
				k.frustum(Vector3(0, 0.06, 0.02), 0.15, 0.02, 0.3, BuildingModels.TEAM, 12)
			_:
				# Clean-shaven but for a moustache, a ponytail.
				k.box(Vector3(0, 0.07, -0.115), Vector3(0.1, 0.025, 0.03), hair)
				k.frustum(Vector3(0, -0.12, 0.12), 0.02, 0.035, 0.2, hair, 6)
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
	k.frustum(Vector3(0, -0.22, 0), 0.045, 0.056, 0.22, tunic, 10)
	k.frustum(Vector3(0, -0.24, 0), 0.05, 0.05, 0.04, tunic * 0.75, 10)
	k.sphere(Vector3(0, -0.28, -0.01), 0.048, skin, 5, 8)
	var m := k.commit()
	_parts[key] = m
	return m


func _shin_mesh() -> Mesh:
	if _parts.has("shin"):
		return _parts["shin"]
	var k := BuildingModels.Kit.new()
	# Leg wrappings and a leather shoe.
	k.frustum(Vector3(0, -0.42, 0), 0.05, 0.066, 0.42, Color(0.5, 0.44, 0.36), 10)
	# The cross-gartering of the wraps.
	for i in 3:
		k.frustum(Vector3(0, -0.36 + i * 0.12, 0), 0.062 - i * 0.003, 0.064 - i * 0.003, 0.025, Color(0.3, 0.22, 0.15), 10)
	k.box(Vector3(0, -0.45, -0.05), Vector3(0.11, 0.08, 0.25), Color(0.25, 0.17, 0.1))
	k.box(Vector3(0, -0.41, 0.0), Vector3(0.1, 0.06, 0.12), Color(0.25, 0.17, 0.1))
	var m := k.commit()
	_parts["shin"] = m
	return m


## The tool for a trade, held in the right hand (along -y from the hand, head forward).
## An iron helmet: a rounded cap with a rim and a nose guard.
func _helmet_mesh() -> Mesh:
	if _parts.has("helmet"):
		return _parts["helmet"]
	var k := BuildingModels.Kit.new()
	var iron := Color(0.5, 0.5, 0.53)
	k.sphere(Vector3(0, 0.16, 0.0), 0.138, iron, 6, 12)
	k.frustum(Vector3(0, 0.12, 0), 0.142, 0.142, 0.035, iron * 0.8, 14)
	k.box(Vector3(0, 0.08, -0.135), Vector3(0.03, 0.11, 0.02), iron * 0.9)
	k.box(Vector3(0, 0.22, 0), Vector3(0.025, 0.12, 0.28), iron * 0.85)
	var m := k.commit()
	_parts["helmet"] = m
	return m


## A round shield in the owner's colour, an iron boss, a dark rim; facing -Z.
func _shield_mesh() -> Mesh:
	if _parts.has("shield"):
		return _parts["shield"]
	var k := BuildingModels.Kit.new()
	k.cylinder(Vector3(0, 0, 0.02), 0.44, 0.04, BuildingModels.DARK_WOOD, 16, Vector3(0, 0, -1))
	k.disc(Vector3(0, 0, -0.025), 0.41, BuildingModels.TEAM, Vector3(0, 0, -1))
	var m := k.commit()
	_parts["shield"] = m
	return m


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
		"spear":
			# Held near its middle: a long ash shaft, an iron head forward.
			k.box(Vector3(0, 0, -0.35), Vector3(0.035, 0.035, 2.4), haft)
			k.cone(Vector3(0, 0, 0), 0.04, 0.3, BuildingModels.IRON, 6)
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
