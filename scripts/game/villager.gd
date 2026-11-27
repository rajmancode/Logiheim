class_name Villager
extends Node3D
## One of a settlement's people, seen at work: walks (legs scissoring, body bobbing) between
## places on its round, and at each stop works with its tool (the arm swings - chopping,
## hammering, digging, hauling) for a while. Rounds are lists of {at: Vector2, work: seconds}.

var height_at: Callable          # Vector2 -> ground y
var round_points: Array = []     # [{at, work}]
var speed := 1.6
var active := true

var _body: MeshInstance3D
var _legs: MeshInstance3D
var _arm: MeshInstance3D
var _i := 0
var _working := 0.0
var _t := 0.0
var _phase := 0.0


func setup(team: Color, tunic: Color, mat: ShaderMaterial, ground: Callable) -> void:
	height_at = ground
	var parts := BuildingModels.person(tunic)
	_body = MeshInstance3D.new()
	_body.mesh = parts.body
	_legs = MeshInstance3D.new()
	_legs.mesh = parts.legs
	_arm = MeshInstance3D.new()
	_arm.mesh = parts.arm
	_arm.position = Vector3(0.3, 1.35, 0)
	for m in [_body, _legs, _arm]:
		(m as MeshInstance3D).material_override = mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
	_phase = randf() * TAU
	scale = Vector3.ONE * 1.25


func set_round(points: Array) -> void:
	round_points = points
	_i = 0
	_working = 0.0
	if not points.is_empty():
		var p: Vector2 = points[0].at
		position = Vector3(p.x, height_at.call(p), p.y)


func _process(delta: float) -> void:
	if round_points.is_empty():
		return
	_t += delta
	if not active:
		# Standing about: a slow idle sway.
		_legs.rotation.x = 0.0
		_arm.rotation.x = sin(_t * 1.5 + _phase) * 0.1
		return
	var stop: Dictionary = round_points[_i]
	var target: Vector2 = stop.at
	var here := Vector2(position.x, position.z)
	var to := target - here
	if to.length() > 0.25:
		# Walk: face the way, scissor the legs, bob, swing the arm.
		var step := to.normalized() * minf(speed * delta, to.length())
		here += step
		rotation.y = atan2(-to.x, -to.y)
		var w := _t * 7.0 + _phase
		_legs.rotation.x = sin(w) * 0.35
		_arm.rotation.x = -sin(w) * 0.4
		position = Vector3(here.x, height_at.call(here) + absf(sin(w)) * 0.06, here.y)
		_working = 0.0
		return
	# At the stop: work (the arm swings the tool down, again and again).
	_legs.rotation.x = 0.0
	_working += delta
	var a := fmod(_t * 2.2 + _phase, 1.0)
	_arm.rotation.x = -2.2 * (1.0 - pow(1.0 - smoothstep(0.0, 0.6, a), 2.0)) + 2.2 * smoothstep(0.6, 0.75, a)
	if _working >= float(stop.get("work", 2.0)):
		_i = (_i + 1) % round_points.size()
		_working = 0.0
