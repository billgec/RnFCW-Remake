extends Node3D
## RTS camera rig: this node is the ground focus point, the Camera3D child orbits it.
## WASD/arrows pan, screen edges pan, wheel zooms, Q/E or middle mouse drag rotates.
##
## In hero mode the rig follows the hero instead (begin_follow): it drops behind their
## shoulder, the mouse takes over yaw and pitch, and panning is switched off.

@export var pan_speed := 30.0
@export var edge_margin := 12
@export var min_distance := 8.0
@export var max_distance := 90.0
@export var distance := 32.0
@export var pitch_degrees := 52.0
@export var edge_pan_enabled := true

## Third-person framing: how far behind and how high above the hero the camera sits.
const FOLLOW_MIN := 4.0
const FOLLOW_MAX := 14.0
const FOLLOW_PITCH := 18.0
const FOLLOW_EYE := 1.6
const FOLLOW_SHOULDER := 0.9

var follow_target: Node3D

var _yaw := deg_to_rad(35.0)
var _target_distance := distance
var _rotating := false
var _follow_distance := 6.0
var _saved := {}

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


func yaw() -> float:
	return _yaw


# --- third person -----------------------------------------------------------

func begin_follow(target: Node3D) -> void:
	_saved = {"position": position, "pitch": pitch_degrees, "distance": _target_distance, "yaw": _yaw}
	follow_target = target
	_yaw = target.rotation.y  # start out looking where the hero is already facing
	pitch_degrees = FOLLOW_PITCH
	_target_distance = _follow_distance
	position = target.global_position + Vector3.UP * FOLLOW_EYE


func end_follow() -> void:
	if follow_target == null:
		return
	follow_target = null
	position = _saved.get("position", position)
	pitch_degrees = _saved.get("pitch", 52.0)
	_target_distance = _saved.get("distance", 32.0)
	_yaw = _saved.get("yaw", _yaw)


## Mouse look while following: horizontal turns, vertical tilts.
func look_delta(relative: Vector2) -> void:
	_yaw -= relative.x * 0.004
	pitch_degrees = clampf(pitch_degrees + relative.y * 0.12, 2.0, 55.0)


func zoom_follow(step: float) -> void:
	_follow_distance = clampf(_follow_distance + step, FOLLOW_MIN, FOLLOW_MAX)
	_target_distance = _follow_distance


func _unhandled_input(event: InputEvent) -> void:
	if follow_target != null:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_distance = maxf(min_distance, _target_distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_distance = minf(max_distance, _target_distance * 1.1)
			MOUSE_BUTTON_MIDDLE:
				_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * 0.005
		pitch_degrees = clampf(pitch_degrees + event.relative.y * 0.2, 20.0, 85.0)


func _process(delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		var focus: Vector3 = follow_target.global_position + Vector3.UP * FOLLOW_EYE
		position = position.lerp(focus, 1.0 - exp(-16.0 * delta))
		distance = lerpf(distance, _target_distance, 1.0 - exp(-8.0 * delta))
		_apply()
		return
	var input := Vector2(
		Input.get_axis("cam_left", "cam_right"),
		Input.get_axis("cam_forward", "cam_back"))
	if edge_pan_enabled and DisplayServer.window_is_focused():
		var mouse := get_viewport().get_mouse_position()
		var size := get_viewport().get_visible_rect().size
		if mouse.x < edge_margin: input.x = -1
		elif mouse.x > size.x - edge_margin: input.x = 1
		if mouse.y < edge_margin: input.y = -1
		elif mouse.y > size.y - edge_margin: input.y = 1
	_yaw += Input.get_axis("cam_rotate_right", "cam_rotate_left") * 1.8 * delta
	if input != Vector2.ZERO:
		var speed := pan_speed * (distance / 32.0)
		position += Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y) * speed * delta
	distance = lerpf(distance, _target_distance, 1.0 - exp(-10.0 * delta))
	_apply()


func _apply() -> void:
	rotation = Vector3(0, _yaw, 0)
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * distance
	var look_at := global_position
	if follow_target != null:
		# Over the shoulder: step aside and keep looking straight ahead, so the hero sits
		# slightly off centre instead of blocking the view.
		camera.position.x += FOLLOW_SHOULDER
		look_at += global_transform.basis.x * FOLLOW_SHOULDER
	camera.look_at(look_at, Vector3.UP)
