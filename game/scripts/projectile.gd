extends Node3D
## Arrow/javelin: flies on a ballistic arc to where the target will be and deals damage on
## arrival if the target is still close to the impact point.

const GRAVITY := 9.8

var _shooter
var _target
var _damage := 0.0
var _start := Vector3.ZERO
var _end := Vector3.ZERO
var _duration := 1.0
var _time := 0.0
var _arc_height := 0.0


func launch(shooter, target, from: Vector3, damage: float) -> void:
	_shooter = shooter
	_target = target
	_damage = damage
	_start = from
	var aim: Vector3 = target.global_position
	if target is Building:
		var r: Rect2 = target.footprint
		aim = Vector3(clampf(from.x, r.position.x, r.end.x), 0.0, clampf(from.z, r.position.y, r.end.y))
	var distance := from.distance_to(aim)
	_duration = clampf(distance / 28.0, 0.25, 1.6)
	var lead := Vector3.ZERO
	if target is Unit and target.state in [Unit.State.MOVE, Unit.State.GATHER, Unit.State.RETURN]:
		lead = -target.global_basis.z * target.move_speed * _duration
	_end = aim + lead + Vector3.UP * 1.1
	_arc_height = GRAVITY * _duration * _duration / 8.0
	global_position = _start
	_build_mesh()


func _process(delta: float) -> void:
	_time += delta
	var t := clampf(_time / _duration, 0.0, 1.0)
	var previous := global_position
	var point := _start.lerp(_end, t)
	point.y += _arc_height * 4.0 * t * (1.0 - t)
	global_position = point
	var velocity := point - previous
	if velocity.length_squared() > 1e-8:
		look_at(point + velocity, Vector3.UP)
	if t >= 1.0:
		var hit := false
		if is_instance_valid(_target) and _target.is_alive():
			hit = _target is Building or _target.global_position.distance_to(_end - Vector3.UP * 1.1) < 1.6
		if hit:
			_target.take_damage(_damage, _shooter if is_instance_valid(_shooter) else null)
		queue_free()


func _build_mesh() -> void:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.04, 0.04, 1.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.25, 0.15)
	shaft.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = shaft
	add_child(mesh)
