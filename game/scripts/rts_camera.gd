extends Node3D
## RTS camera rig: this node is the ground focus point, the Camera3D child orbits it.
## WASD/arrows pan, screen edges pan, wheel zooms, Q/E or middle mouse drag rotates.

@export var pan_speed := 30.0
@export var edge_margin := 12
@export var min_distance := 8.0
@export var max_distance := 90.0
@export var distance := 32.0
@export var pitch_degrees := 52.0
@export var edge_pan_enabled := true

var _yaw := deg_to_rad(35.0)
var _target_distance := distance
var _rotating := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
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
	camera.look_at(global_position, Vector3.UP)
