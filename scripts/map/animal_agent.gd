class_name AnimalAgent
extends Node3D
## One living animal: a rigged model (assets/models/animals) with looping "idle", "graze" and
## "walk" animations ("swim" for whales), and a small routine that drives them.
##
## Land animals graze and look around for a while, then walk to a new spot in their pasture
## (within `radius` of `home`), following the terrain and avoiding water. Seals and walrus
## mostly rest on the shore and shuffle a short way now and then. Whales swim slow circles at
## the surface. Far from the camera the animal stops thinking and animating.

const THINK_DISTANCE := 450.0

var surface: TerrainSurface
var home := Vector2.ZERO
var radius := 20.0
var speed := 1.2          ## m/s when walking (already scaled with the model)
var kind := "land"        ## "land", "shore" or "sea"

var _player: AnimationPlayer
var _state := ""
var _timer := 0.0
var _target := Vector2.ZERO
var _heading := 0.0
var _angle := 0.0         ## whales: position on their circle
var _rng := RandomNumberGenerator.new()
var _far_check := 0.0
var _awake := true


func setup(p_surface: TerrainSurface, p_home: Vector2, p_radius: float, p_speed: float, p_kind: String, heading: float, seed_value: int) -> void:
	surface = p_surface
	home = p_home
	radius = p_radius
	speed = p_speed
	kind = p_kind
	_heading = heading
	_rng.seed = seed_value
	_angle = _rng.randf() * TAU


func _ready() -> void:
	_player = _find_player(self)
	if _player != null:
		for anim_name in _player.get_animation_list():
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if kind == "sea":
		_play("swim", 0.0)
		_player_seek_random()
	else:
		_enter(["graze", "idle"][_rng.randi() % 2], _rng.randf_range(2.0, 14.0))
		_player_seek_random()
	_place(Vector2(position.x, position.z))


func _process(delta: float) -> void:
	_far_check -= delta
	if _far_check <= 0.0:
		_far_check = 0.5
		var cam := get_viewport().get_camera_3d()
		var awake := is_visible_in_tree() and cam != null and cam.global_position.distance_to(global_position) < THINK_DISTANCE
		if awake != _awake:
			_awake = awake
			if _player != null:
				_player.speed_scale = 1.0 if awake else 0.0
	if not _awake:
		return
	if kind == "sea":
		_swim(delta)
		return
	_timer -= delta
	match _state:
		"walk":
			var pos := Vector2(position.x, position.z)
			var to := _target - pos
			if to.length() < 0.6 or _timer <= 0.0:
				_enter(["graze", "graze", "idle"][_rng.randi() % 3], _rng.randf_range(6.0, 18.0) if kind == "land" else _rng.randf_range(10.0, 30.0))
				return
			var want := atan2(-to.y, to.x)
			_heading = lerp_angle(_heading, want, 1.0 - exp(-3.0 * delta))
			var fwd := Vector2(cos(_heading), -sin(_heading))
			var next := pos + fwd * speed * delta
			if not _walkable(next):
				_enter("idle", _rng.randf_range(2.0, 5.0))
				return
			_place(next)
		_:
			if _timer <= 0.0:
				if _rng.randf() < (0.6 if kind == "land" else 0.25):
					_pick_target()
				else:
					_enter("idle" if _state == "graze" else "graze", _rng.randf_range(5.0, 15.0))


func _enter(state: String, duration: float) -> void:
	_state = state
	_timer = duration
	_play(state, 0.5)


func _pick_target() -> void:
	var reach := radius if kind == "land" else radius * 0.4
	for attempt in 8:
		var t := home + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * reach
		if _walkable(t):
			_target = t
			var dist := t.distance_to(Vector2(position.x, position.z))
			_enter("walk", dist / maxf(speed, 0.05) * 1.6 + 2.0)
			return
	_enter("idle", _rng.randf_range(3.0, 6.0))


func _walkable(p: Vector2) -> bool:
	if surface == null:
		return true
	var h := surface.sample(p)
	if kind == "shore":
		return h < surface.sea_y + 6.0 and surface.is_dry(p, 1.0, 0.2)
	# Dry land only: never into the sea, a river, a lake, an oxbow or a pond.
	return surface.is_dry(p, 1.5) and surface.normal_at(p).y > 0.7


func _swim(delta: float) -> void:
	_angle += speed / maxf(radius, 1.0) * delta
	var p := home + Vector2(cos(_angle), sin(_angle)) * radius
	var tangent := Vector2(-sin(_angle), cos(_angle))
	_heading = atan2(-tangent.y, tangent.x)
	position = Vector3(p.x, surface.sea_y if surface != null else position.y, p.y)
	rotation = Vector3(0.0, _heading, 0.0)


## Puts the animal on the ground at p, facing its heading and leaning with the slope.
func _place(p: Vector2) -> void:
	if surface == null or kind == "sea":
		return
	var n := surface.normal_at(p).lerp(Vector3.UP, 0.5).normalized()
	var yaw := Basis(Vector3.UP, _heading)
	var tilt := Basis(Quaternion(Vector3.UP, n))
	var s := scale
	transform = Transform3D(tilt * yaw, Vector3(p.x, surface.sample(p) - 0.03, p.y))
	scale = s


func _play(anim: String, blend: float) -> void:
	if _player != null and _player.has_animation(anim):
		_player.play(anim, blend)


func _player_seek_random() -> void:
	if _player != null and _player.current_animation != "":
		_player.seek(_rng.randf() * _player.current_animation_length, true)


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
