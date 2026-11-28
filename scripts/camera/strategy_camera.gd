class_name StrategyCamera
extends Node3D
## Orbiting strategy camera. This node is the pivot on the ground; the Camera3D is a child.
## WASD/arrows or middle-drag pan, wheel zooms, Q/E or right-drag rotate.

@export var min_distance := 40.0
@export var max_distance := 3000.0
@export var zoom_step := 1.15
@export var pan_speed := 0.9          ## fraction of the view distance per second
@export var rotate_speed := 1.6       ## radians per second
@export var near_pitch_deg := 32.0    ## pitch when fully zoomed in
@export var far_pitch_deg := 68.0     ## pitch when fully zoomed out
@export var smoothing := 10.0

var camera: Camera3D
var distance := 800.0
var yaw := 0.0
var bounds := Rect2(0, 0, 1024, 1024)
## Ground height under the pivot; set by the owner each frame.
var ground_height := 0.0

var _target := Vector3.ZERO
var _target_distance := 800.0
var _target_yaw := 0.0
var _pan_drag := false
var _rot_drag := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 30000.0
	camera.fov = 50.0
	add_child(camera)
	_target = position
	_apply()


## Centre on a world rectangle (x, z) and zoom out to show it.
func frame_rect(rect: Rect2) -> void:
	bounds = rect
	max_distance = maxf(rect.size.x, rect.size.y) * 1.5
	var c := rect.get_center()
	_target = Vector3(c.x, ground_height, c.y)
	position = _target
	_target_distance = max_distance * 0.55
	distance = _target_distance
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# The wheel over the interface (menus, cards, panels) is the interface's, never a zoom.
		if (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and get_viewport().gui_get_hovered_control() != null:
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = maxf(min_distance, _target_distance / zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = minf(max_distance, _target_distance * zoom_step)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rot_drag = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_drag:
			var drag_scale := distance * 0.0016
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * drag_scale)
		if _rot_drag:
			_target_yaw -= mm.relative.x * 0.006


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move != Vector2.ZERO:
		_pan(move.normalized() * distance * pan_speed * delta)
	if Input.is_key_pressed(KEY_Q):
		_target_yaw += rotate_speed * delta
	if Input.is_key_pressed(KEY_E):
		_target_yaw -= rotate_speed * delta

	var k := 1.0 - exp(-smoothing * delta)
	_target.y = ground_height
	position = position.lerp(_target, k)
	distance = lerpf(distance, _target_distance, k)
	yaw = lerp_angle(yaw, _target_yaw, k)
	_apply()


## Moves the target in screen-aligned ground directions (x = right, y = back).
func _pan(d: Vector2) -> void:
	var ground_basis := Basis(Vector3.UP, yaw)
	var right := ground_basis * Vector3.RIGHT
	var back := ground_basis * Vector3.BACK
	_target += right * d.x + back * d.y
	_target.x = clampf(_target.x, bounds.position.x, bounds.end.x)
	_target.z = clampf(_target.z, bounds.position.y, bounds.end.y)


func _apply() -> void:
	if camera == null:
		return
	var t := inverse_lerp(min_distance, max_distance, distance)
	var pitch := deg_to_rad(lerpf(near_pitch_deg, far_pitch_deg, clampf(t, 0.0, 1.0)))
	rotation = Vector3(0.0, yaw, 0.0)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
