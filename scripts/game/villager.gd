class_name Villager
extends Node3D
## One of a settlement's people: a sculpted, rigged and animated figure (a man or a woman,
## assets/models/people, made by tools/blender/make_people.py) in the clothes of their trade,
## going about their round.
##
## The figure is skinned to a full skeleton; it walks with a real gait (heel strike, knees
## bending, hips swaying, arms swinging against the legs, the body counter-rotating), breathes
## and shifts its weight when idle, and works with eased swings and follow-through: chopping,
## picking, hammering, digging, reaping, hauling nets, stirring. Carrying, the left hand
## steadies the load on the shoulder. Animations cross-fade from one to the next.
##
## How it is dressed (Outfits, by occupation): the colours of its clothes per body region
## (shaders/people.gdshader), a hair style and beard, and pieces hung on its bones: headgear
## on the head, the cloak (in the owner's colour), a bib and what is carried on the back on
## the chest, belt kit, sash and apron at the hips, the tool in the right hand.
##
## Soldiers (setup(..., soldier = true)) wear an iron helmet, a round shield in the owner's
## colour on the left forearm and carry a long spear; they march to the place given by
## march_to() and stand there on guard or braced in the shield wall.

const ACTS := ["chop", "pick", "hammer", "dig", "reap", "net", "stir", "idle"]
const WALK_SPEED := 1.05     # metres a second at playback speed 1 (before scaling)
const SIZE := 1.25

var height_at: Callable
var round_points: Array = []
var speed := 1.5
var active := true
var act := "idle"
var occupation := "commoner"
var soldier := false
## Marching (soldiers): where to go, which way to face there, and how to stand.
var marching := false
var goal := Vector2.ZERO
var goal_face := 0.0
var stance := "guard"

var _model: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _playing := ""
var _female := false
var _mat: ShaderMaterial
var _tool: MeshInstance3D
var _load: MeshInstance3D
var _cloak: Node3D
var _shield: MeshInstance3D
var _i := 0
var _working := 0.0
var _t := 0.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()

static var _scenes := {}
static var _parts := {}
static var _body_mat: ShaderMaterial
const LINEN_DYES := [Color(0.88, 0.85, 0.76), Color(0.7, 0.25, 0.2), Color(0.3, 0.4, 0.6)]
const HAIRS := [Color(0.86, 0.72, 0.42), Color(0.92, 0.82, 0.55), Color(0.55, 0.35, 0.18), Color(0.3, 0.2, 0.12), Color(0.72, 0.36, 0.14), Color(0.62, 0.5, 0.32)]


static func _scene(female: bool) -> PackedScene:
	if not _scenes.has(female):
		_scenes[female] = load("res://assets/models/people/%s.glb" % ("villager_f" if female else "villager_m"))
	return _scenes[female]


static func body_material() -> ShaderMaterial:
	if _body_mat == null:
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = load("res://shaders/people.gdshader")
	return _body_mat


func setup(_team: Color, tunic: Color, mat: ShaderMaterial, ground: Callable, p_act := "idle", p_soldier := false, p_occupation := "") -> void:
	height_at = ground
	_mat = mat
	act = p_act
	soldier = p_soldier
	occupation = p_occupation if p_occupation != "" else "commoner"
	if soldier:
		act = "guard"
	var sp := Outfits.spec(occupation)
	_rng.randomize()
	_phase = _rng.randf() * TAU
	speed = _rng.randf_range(1.3, 1.7)
	_female = _rng.randf() < float(sp.get("women", 0.45)) and not soldier
	# --- Colours -------------------------------------------------------------------------------
	var skin := Color(0.9, 0.73, 0.6).lerp(Color(0.72, 0.52, 0.4), _rng.randf())
	var hair: Color = HAIRS[_rng.randi() % HAIRS.size()]
	var elder := _rng.randf() < float(sp.get("elder", 0.12))
	if elder:
		hair = Color(0.82, 0.8, 0.76).lerp(Color(0.6, 0.58, 0.56), _rng.randf())
	if not soldier and occupation != "commoner":
		var tp: Array = sp.get("tunic", [tunic])
		tunic = tp[_rng.randi() % tp.size()]
	if soldier:
		tunic = tunic
	tunic = Color(tunic.r, tunic.g, tunic.b) * (0.92 + 0.16 * _rng.randf())
	var dp: Array = sp.get("dress", [Color(0.62, 0.22, 0.16), Color(0.28, 0.36, 0.55), Color(0.4, 0.5, 0.3), Color(0.7, 0.58, 0.32), Color(0.5, 0.36, 0.5)])
	var dress: Color = dp[_rng.randi() % dp.size()]
	var under := Color(0.88, 0.85, 0.76).lerp(Color(0.74, 0.68, 0.56), _rng.randf())
	var lp: Array = sp.get("legs", [Color(0.36, 0.3, 0.22), Color(0.3, 0.32, 0.36), Color(0.4, 0.36, 0.3)])
	var legs: Color = lp[_rng.randi() % lp.size()]
	var trim: Color = [Color(0.62, 0.18, 0.12), Color(0.2, 0.3, 0.55), Color(0.75, 0.6, 0.25), Color(0.25, 0.45, 0.3)][_rng.randi() % 4]
	var bare: bool = sp.get("bare_arms", false) and not soldier
	# --- The figure --------------------------------------------------------------------------
	_model = _scene(_female).instantiate()
	add_child(_model)
	_skel = _model.find_child("*", true, false) as Skeleton3D
	for n in _model.find_children("*", "Skeleton3D", true, false):
		_skel = n
	for n in _model.find_children("*", "AnimationPlayer", true, false):
		_anim = n
	if _anim != null:
		for an in _anim.get_animation_list():
			_anim.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	# Hair and beard: one style of each.
	var hat := String(sp.get("hat_f", "none") if _female else sp.get("hat", "none"))
	if soldier:
		hat = "helmet"
	var hair_style: String = ["hair_short", "hair_long", "hair_bun", "hair_braids"][_rng.randi() % 4] if _female else ["hair_short", "hair_long", "hair_bald"][_rng.randi() % 3]
	if _female and hair_style == "hair_short":
		hair_style = "hair_bun"
	var beard: String = "" if _female else ["beard_full", "beard_long", "beard_moustache", "beard_full", ""][_rng.randi() % 5]
	if elder and not _female and beard == "":
		beard = "beard_long"
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("hair_"):
			mi.visible = nm == hair_style
		elif nm.begins_with("beard_"):
			mi.visible = nm == beard
		mi.material_override = body_material()
		mi.set_instance_shader_parameter("skin_col", skin)
		mi.set_instance_shader_parameter("hair_col", hair)
		mi.set_instance_shader_parameter("outer_col", dress if _female else tunic)
		mi.set_instance_shader_parameter("under_col", under)
		mi.set_instance_shader_parameter("legs_col", legs)
		mi.set_instance_shader_parameter("trim_col", skin if bare else trim)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# --- What it wears and carries, hung on its bones --------------------------------------------
	var head := _attach("head", Vector3(0, 1.57, 0))
	if soldier:
		_mesh(head, _helmet_mesh())
	elif hat != "none":
		var hcol: Color = sp.get("hood_col", [Color(0.6, 0.2, 0.15), Color(0.25, 0.35, 0.55), Color(0.4, 0.45, 0.35), LINEN_DYES[_rng.randi() % LINEN_DYES.size()]][_rng.randi() % 4])
		if hat == "scarf":
			hat = "kerchief"
		_mesh(head, Outfits.hat_mesh(hat, hcol))
	var chest := _attach("chest", Vector3(0, 0.95, 0))
	var hips := _attach("hips", Vector3(0, 0.95, 0))
	_cloak = Node3D.new()
	_cloak.position = Vector3(0, 0.53, 0.1)
	chest.add_child(_cloak)
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
			_mesh(hips, _sash_mesh(_female))
	if not soldier:
		if sp.has("apron"):
			_mesh(hips, Outfits.apron_mesh(sp.apron, _female))
			if sp.get("bib", false):
				_mesh(chest, Outfits.bib_mesh(sp.apron))
		if String(sp.get("back", "none")) != "none":
			_mesh(chest, Outfits.back_mesh(String(sp.back)))
		if sp.has("belt"):
			_mesh(hips, Outfits.belt_mesh(sp.belt))
	# The tool in the right hand; a load on the left shoulder when carrying.
	var hand := _attach("hand.R", Vector3(0.335, 0.87, -0.055))
	_tool = MeshInstance3D.new()
	_tool.mesh = _tool_mesh("spear") if soldier else (Outfits.tool_mesh(String(sp.tool)) if sp.has("tool") else _tool_mesh(act))
	_tool.material_override = mat
	hand.add_child(_tool)
	_load = MeshInstance3D.new()
	_load.material_override = mat
	_load.position = Vector3(-0.13, 0.64, 0.02)
	_load.visible = false
	chest.add_child(_load)
	if soldier:
		var fore := _attach("forearm.L", Vector3(-0.38, 1.05, -0.04))
		_shield = MeshInstance3D.new()
		_shield.mesh = _shield_mesh()
		_shield.material_override = mat
		_shield.basis = Basis(Vector3.UP, PI * 0.5)
		fore.add_child(_shield)
	scale = Vector3.ONE * SIZE
	_play("idle", 0.0)


## A node that follows a bone, placed so that in the figure's rest pose its origin sits at
## `at` (model space, the figure facing -Z, y up) with the model's axes: so pieces made for the
## figure standing at rest can be hung on it as they are.
func _attach(bone: String, at: Vector3) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	_skel.add_child(ba)
	var idx := _skel.find_bone(bone)
	var rest := _skel.get_bone_global_rest(idx)
	var holder := Node3D.new()
	holder.transform = rest.affine_inverse() * Transform3D(Basis(), at)
	ba.add_child(holder)
	return holder


func _mesh(parent: Node3D, m: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _play(anim_name: String, blend := 0.25, spd := 1.0) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		anim_name = "idle"
	if anim_name != _playing:
		_playing = anim_name
		_anim.play(anim_name, blend)
		# Not everyone in step.
		_anim.seek(fmod(_phase, 1.0) * _anim.current_animation_length, false)
	_anim.speed_scale = spd


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
	if round_points.is_empty() or not active:
		_load.visible = false
		_tool.visible = true
		_play("idle")
		_sway(0.0)
		return
	var stop: Dictionary = round_points[_i]
	var target: Vector2 = stop.at
	var here := Vector2(position.x, position.z)
	var to := target - here
	if to.length() > 0.3:
		var step := to.normalized() * minf(speed * delta, to.length())
		here += step
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), minf(delta * 6.0, 1.0))
		var carry := String(stop.get("carry", ""))
		_set_load(carry)
		_tool.visible = carry == ""
		_play("walk_carry" if carry != "" else "walk", 0.25, speed / (WALK_SPEED * SIZE))
		_sway(1.0)
		position = Vector3(here.x, height_at.call(here), here.y)
		_working = 0.0
		return
	_working += delta
	var a := String(stop.get("act", act))
	_set_load("")
	_tool.visible = true
	if a == "drop" or not ACTS.has(a):
		_play("idle")
	else:
		_play(a, 0.3)
	_sway(0.0)
	if _working >= float(stop.get("work", 2.0)):
		_i = (_i + 1) % round_points.size()
		_working = 0.0


## The cloak trails out behind on the move and settles at rest.
func _sway(moving: float) -> void:
	if _cloak == null:
		return
	var want := Vector3(0.22 * moving + 0.03 * sin(_t * 3.1 + _phase) * moving + 0.02 * sin(_t * 0.9 + _phase), 0, 0.03 * sin(_t * 2.0 + _phase) * moving)
	_cloak.rotation = _cloak.rotation.lerp(want, 0.15)


func _march(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	var to := goal - here
	var dist := to.length()
	if dist > 0.25:
		var spd := clampf(dist * 1.6, 0.6, 3.6)
		here += to.normalized() * minf(spd * delta, dist)
		var face := atan2(-to.x, -to.y) if dist > 1.2 else goal_face
		rotation.y = lerp_angle(rotation.y, face, minf(delta * 6.0, 1.0))
		_play("march", 0.25, spd / (WALK_SPEED * SIZE))
		_sway(1.0)
		position = Vector3(here.x, height_at.call(here), here.y)
	else:
		rotation.y = lerp_angle(rotation.y, goal_face, minf(delta * 5.0, 1.0))
		_play("brace" if stance == "brace" else "guard", 0.35)
		_sway(0.0)


func _set_load(kind: String) -> void:
	if kind == "":
		_load.visible = false
		return
	_load.visible = true
	_load.mesh = _load_mesh(kind)


# --------------------------------------------------------------------------- pieces

## The clan's colour in a sash over the belt, for those without a cloak.
func _sash_mesh(female: bool) -> Mesh:
	var key := "sash_%s" % female
	if _parts.has(key):
		return _parts[key]
	var k := BuildingModels.Kit.new()
	var rx := 0.2 if not female else 0.192
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		var p0 := Vector3(cos(a0) * rx, 0, sin(a0) * rx * 0.81)
		var p1 := Vector3(cos(a1) * rx, 0, sin(a1) * rx * 0.81)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5) * 1.2).normalized()
		k.quad(p0 + Vector3(0, -0.06, 0), p1 + Vector3(0, -0.06, 0), p1 + Vector3(0, 0.005, 0), p0 + Vector3(0, 0.005, 0), n, BuildingModels.TEAM)
	k.box(Vector3(0.11, -0.12, -0.135), Vector3(0.05, 0.13, 0.02), BuildingModels.TEAM, Vector3(0, 0, 0.2))
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
