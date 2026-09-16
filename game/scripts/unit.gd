class_name Unit
extends Node3D
## A controllable unit. Wraps a converted model, reads its gameplay values from the unit
## manifest (stats exported from dbobjects.dat), follows navmesh paths, fights units and
## buildings, and - for citizens - gathers resources and constructs buildings.

signal died(unit: Unit)

enum State { IDLE, MOVE, ATTACK, GATHER, RETURN, BUILD, DEAD }

const Projectile := preload("res://scripts/projectile.gd")
const HealthBar := preload("res://scripts/health_bar.gd")
const SelectionRing := preload("res://scripts/selection_ring.gd")
const CARRY_CAPACITY := 10
const GATHER_INTERVAL := {"gold": 0.9, "wood": 1.1}

var definition_id := ""
var display_name := ""
var icon_path := ""
var team := 0
var team_color := Color.WHITE

var max_hit_points := 100.0
var hit_points := 100.0
var damage := 10.0
var attack_range := 1.8
var sight := 24.0
var attack_interval := 2.0
var move_speed := 2.5
var radius := 0.6
var ranged := false
var is_worker := false
var family := ""
var is_hero := false
var state := State.IDLE

var carrying := 0
var carry_kind := ""

var selected := false:
	set(value):
		selected = value and state != State.DEAD
		if _ring:
			_ring.visible = selected

var _model: Node3D
var _player: AnimationPlayer
var _anims := {}
var _path := PackedVector3Array()
var _path_index := 0
var _attack_move := false
var _target  # Unit or Building
var _resource: ResourceNode
var _construction: Building
var _cooldown := 0.0
var _swing_timer := -1.0
var _scan_timer := 0.0
var _repath_timer := 0.0
var _work_timer := 0.0
var _stuck_timer := 0.0
var _stuck_from := Vector3.ZERO
var _repaths := 0
var _ring: MeshInstance3D
var _health_bar: Node3D

static var all_units: Array[Unit] = []


static func create(id: String, team_index: int, color: Color) -> Unit:
	var unit := Unit.new()
	unit.definition_id = id
	unit.team = team_index
	unit.team_color = color
	unit._model = Assets.spawn_unit(id, color)
	unit.add_child(unit._model)
	return unit


func _ready() -> void:
	all_units.append(self)
	var def := Assets.unit_def(definition_id)
	var stats: Dictionary = def.get("stats") if def.get("stats") != null else {}
	display_name = stats.get("name", definition_id)
	icon_path = def.get("icon", "") if def.get("icon") != null else ""
	max_hit_points = float(stats.get("hit_points", 100))
	hit_points = max_hit_points
	damage = float(stats.get("damage", 10))
	attack_range = maxf(float(stats.get("range_m", 1.8)), 1.2)
	sight = maxf(float(stats.get("sight_m", 24.0)), 12.0)
	attack_interval = maxf(float(stats.get("attack_interval_s", 2.0)), 0.6)
	move_speed = maxf(float(stats.get("speed_mps", 2.5)), 1.0)
	var footprint: Array = stats.get("footprint_m", [1.2, 1.2])
	radius = clampf(maxf(footprint[0], footprint[1]) * 0.45, 0.45, 1.4)
	family = stats.get("family", "")
	is_worker = int(stats.get("attack_type", 0)) == 5
	is_hero = "alexander" in definition_id or "hero" in definition_id
	ranged = int(stats.get("attack_type", 0)) == 1
	if is_worker:
		attack_range = 1.5  # citizens fight in melee; their 15 m value is not a weapon range

	_player = _model.find_child("AnimationPlayer", true, false)
	var names: Array = def.get("animations", [])
	_anims = {
		"idle": _pick(names, ["fidget1", "fidget", "fdgt", "idle"], ["alert", "attack", "atck"]),
		"combat_idle": _pick(names, ["cmbt_idle", "attack_idle", "atck_idle", "alert_idle"], []),
		"walk": _pick(names, ["walk"], []),
		"run": _pick(names, ["run", "jog"], ["atck", "attack"]),
		"attack": _pick(names, ["attack1", "atck1", "shootlow", "attack", "atck"], ["idle", "high", "run"]),
		"death": _pick(names, ["death"], ["water", "thrown", "impct"]),
		"dead": _pick(names, ["dead"], ["water"]),
		"chop": _pick(names, ["chop"], []),
		"mine": _pick(names, ["mine"], []),
		"build": _pick(names, ["build"], []),
		"carry": _pick(names, ["carry"], []),
	}
	_ring = SelectionRing.new()
	_ring.setup_circle(radius * 1.3)
	_ring.visible = selected
	add_child(_ring)
	_health_bar = HealthBar.new()
	_health_bar.position.y = _bar_height()
	add_child(_health_bar)
	_update_health_bar()
	_scan_timer = randf() * 0.3
	_play("idle", 0.0)


func _exit_tree() -> void:
	all_units.erase(self)


func is_alive() -> bool:
	return state != State.DEAD


# --- orders ---------------------------------------------------------------

func order_move(target: Vector3, attack_move := false) -> void:
	if not is_alive():
		return
	_clear_work()
	_target = null
	_attack_move = attack_move
	_set_destination(target)
	state = State.MOVE


func order_attack(enemy) -> void:
	if not is_alive() or enemy == null or not enemy.is_alive():
		return
	_clear_work()
	_target = enemy
	_attack_move = false
	_repath_timer = 0.0
	state = State.ATTACK


func order_gather(node: ResourceNode) -> void:
	if not is_alive() or not is_worker or node == null or not node.is_available():
		return
	_clear_work()
	_resource = node
	_resource.gatherers += 1
	if carrying > 0 and carry_kind != node.kind:
		carrying = 0
	_set_destination(node.global_position)
	state = State.GATHER


## Founding a new building, finishing one, or repairing a damaged one.
func order_build(building: Building) -> void:
	if not is_alive() or not is_worker or building == null:
		return
	if building.is_complete() and building.hit_points >= building.max_hit_points:
		return
	_clear_work()
	_construction = building
	_set_destination(building.global_position)
	state = State.BUILD


func take_damage(amount: float, attacker) -> void:
	if not is_alive():
		return
	hit_points -= amount
	_update_health_bar()
	if hit_points <= 0.0:
		_die()
		return
	var busy: bool = state == State.ATTACK and _target != null and _target.is_alive()
	if attacker and attacker.is_alive() and attacker is Unit and not busy and state != State.MOVE:
		if not is_worker or state == State.IDLE:
			order_attack(attacker)


# --- simulation -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	_cooldown -= delta
	_scan_timer -= delta
	if _swing_timer >= 0.0:
		_swing_timer -= delta
		if _swing_timer < 0.0:
			_release_attack()

	match state:
		State.IDLE:
			if not is_worker and _scan_timer <= 0.0:
				_scan_timer = 0.35
				var enemy = _nearest_enemy(sight)
				if enemy:
					order_attack(enemy)
			_apply_separation(delta)
		State.MOVE:
			if _attack_move and _scan_timer <= 0.0:
				_scan_timer = 0.35
				var enemy = _nearest_enemy(sight)
				if enemy:
					order_attack(enemy)
					return
			if _follow_path(delta):
				state = State.IDLE
				_play("idle")
		State.ATTACK:
			_update_attack(delta)
		State.GATHER:
			_update_gather(delta)
		State.RETURN:
			_update_return(delta)
		State.BUILD:
			_update_build(delta)


func _update_attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		_target = null if is_worker else _nearest_enemy(sight)
		if _target == null:
			state = State.IDLE
			_play("idle")
			return
		_repath_timer = 0.0
	var target_pos: Vector3 = _target.global_position
	var target_radius: float = _target.radius
	if _target is Building:
		target_pos = _closest_point_on(_target.footprint)
		target_radius = 0.3
	var offset := target_pos - position
	offset.y = 0.0
	var reach := attack_range + radius + target_radius
	if offset.length() > reach:
		if _swing_timer >= 0.0:
			return  # finish the swing that is already in progress
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = 0.5
			_set_destination(target_pos)
		_follow_path(delta)
		return
	_face(offset, delta)
	_apply_separation(delta)
	if _cooldown <= 0.0 and _swing_timer < 0.0:
		_cooldown = attack_interval
		var anim_length := _play_attack()
		_swing_timer = anim_length * (0.55 if ranged else 0.45)
	elif _swing_timer < 0.0 and not _is_playing("attack"):
		_play("combat_idle" if _anims["combat_idle"] != "" else "idle")


## Damage after the class bonus for this attacker/target pair (see data/bonuses.json).
func damage_against(target) -> float:
	var target_family: String = target.family if "family" in target else ""
	return damage * GameState.damage_multiplier(family, target_family, target is Building)


func _release_attack() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		return
	if ranged:
		var projectile := Projectile.new()
		get_parent().add_child(projectile)
		projectile.launch(self, _target, global_position + Vector3.UP * 1.6, damage_against(_target))
	else:
		_target.take_damage(damage_against(_target), self)


func _update_gather(delta: float) -> void:
	if _resource == null or not is_instance_valid(_resource) or not _resource.is_available():
		var kind := carry_kind if carry_kind != "" else (_resource.kind if is_instance_valid(_resource) else "gold")
		_release_resource()
		var next := ResourceNode.nearest(position, kind, 60.0)
		if next:
			order_gather(next)
		elif carrying > 0:
			_start_return()
		else:
			state = State.IDLE
			_play("idle")
		return
	var offset := _resource.global_position - position
	offset.y = 0.0
	if offset.length() > _resource.radius + radius + 0.6:
		_follow_path(delta)
		_work_timer = 0.0
		return
	_face(offset, delta)
	var anim := "mine" if _resource.kind == "gold" else "chop"
	if not _is_playing(anim):
		_play(anim, 0.2)
	_work_timer += delta
	if _work_timer >= GATHER_INTERVAL[_resource.kind]:
		_work_timer = 0.0
		carry_kind = _resource.kind
		carrying += _resource.harvest(1)
		if carrying >= CARRY_CAPACITY:
			_start_return()


func _start_return() -> void:
	var drop := Building.nearest_drop_site(position, team)
	if drop == null:
		state = State.IDLE
		_play("idle")
		return
	_set_destination(_closest_point_on(drop.footprint), "carry" if carry_kind == "wood" else "")
	state = State.RETURN


func _update_return(delta: float) -> void:
	var drop := Building.nearest_drop_site(position, team)
	if drop == null:
		state = State.IDLE
		return
	var near := _closest_point_on(drop.footprint)
	if position.distance_to(near) > radius + 1.2:
		if _follow_path(delta):
			_set_destination(near)
		return
	GameState.add_resource(team, carry_kind, carrying)
	carrying = 0
	if _resource and is_instance_valid(_resource) and _resource.is_available():
		_set_destination(_resource.global_position)
		state = State.GATHER
	else:
		var next := ResourceNode.nearest(position, carry_kind, 80.0)
		if next:
			order_gather(next)
		else:
			state = State.IDLE
			_play("idle")


func _update_build(delta: float) -> void:
	var done := _construction == null or not is_instance_valid(_construction) or not _construction.is_alive()
	if not done and _construction.is_complete() and _construction.hit_points >= _construction.max_hit_points:
		done = true
	if done:
		_construction = null
		state = State.IDLE
		_play("idle")
		return
	var near := _closest_point_on(_construction.footprint)
	var offset := near - position
	offset.y = 0.0
	if offset.length() > radius + 1.0:
		if _follow_path(delta):
			_set_destination(near)
		return
	_face(offset, delta)
	if not _is_playing("build"):
		_play("build", 0.2)
	if _construction.is_complete():
		_construction.add_repair(delta)
	else:
		_construction.add_construction(delta)


func _clear_work() -> void:
	_release_resource()
	_construction = null


func _release_resource() -> void:
	if _resource and is_instance_valid(_resource):
		_resource.gatherers = maxi(0, _resource.gatherers - 1)
	_resource = null


func _die() -> void:
	state = State.DEAD
	selected = false
	_clear_work()
	_target = null
	all_units.erase(self)
	_health_bar.alive = false
	died.emit(self)
	var length := _play("death", 0.1)
	await get_tree().create_timer(maxf(length - 0.1, 0.1)).timeout
	if _anims["dead"] != "":
		_play("dead", 0.1)
	elif _player:
		_player.pause()
	await get_tree().create_timer(12.0).timeout
	var tween := create_tween()
	tween.tween_property(self, "position:y", -1.5, 4.0)
	tween.tween_callback(queue_free)


# --- movement -------------------------------------------------------------

func _set_destination(target: Vector3, move_anim := "") -> void:
	var destination := Vector3(target.x, 0.0, target.z)
	_stuck_timer = 0.0
	_stuck_from = position
	var map := get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, position, destination, true)
	if _path.size() < 2:
		_path = PackedVector3Array([position, destination])
	_path_index = 1
	var anim := move_anim
	if anim == "" or _anims.get(anim, "") == "":
		anim = "run" if (move_speed > 3.5 or _anims["walk"] == "") else "walk"
	if not _is_playing(anim):
		var reference := 4.0 if anim == "run" else 1.6
		_play(anim, 0.15, move_speed / reference)


## Returns true when the end of the current path has been reached.
func _follow_path(delta: float) -> bool:
	while _path_index < _path.size():
		var waypoint := _path[_path_index]
		var to_waypoint := waypoint - position
		to_waypoint.y = 0.0
		var distance := to_waypoint.length()
		var last := _path_index == _path.size() - 1
		if distance < (0.2 if last else 0.6):
			_path_index += 1
			continue
		var direction := to_waypoint / distance
		position += direction * minf(move_speed * delta, distance) + _separation() * delta
		position.y = 0.0
		position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, position)
		position.y = 0.0
		if _check_stuck(delta):
			return true
		_face(direction, delta)
		if not (_is_playing("walk") or _is_playing("run") or _is_playing("carry")):
			var anim := "run" if (move_speed > 3.5 or _anims["walk"] == "") else "walk"
			_play(anim, 0.15, move_speed / (4.0 if anim == "run" else 1.6))
		return false
	return true


## True when the unit has been grinding against obstacles or a crowd long enough to stop.
## One fresh path is tried first; a unit that still cannot move gives up rather than jitter.
func _check_stuck(delta: float) -> bool:
	_stuck_timer += delta
	if _stuck_timer < 1.0:
		return false
	var travelled := position.distance_to(_stuck_from)
	_stuck_timer = 0.0
	_stuck_from = position
	if travelled > 0.35:
		_repaths = 0
		return false
	_repaths += 1
	if _repaths <= 1:
		var goal := _path[_path.size() - 1] if _path.size() > 0 else position
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, position, goal, true)
		_path_index = 1
		return false
	_repaths = 0
	return true


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var facing := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-10.0 * delta))


func _apply_separation(delta: float) -> void:
	var push := _separation()
	if push.length_squared() > 0.0001:
		position += push * delta
		position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, position)
		position.y = 0.0


## Soft crowd avoidance. Units never block each other: while someone is moving only real
## overlap pushes (so columns can walk through a crowd), standing units keep full spacing.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	var moving := state in [State.MOVE, State.ATTACK, State.GATHER, State.RETURN, State.BUILD]
	for other in all_units:
		if other == self:
			continue
		var offset := position - other.position
		offset.y = 0.0
		var spacing := radius + other.radius
		if moving or other.state == State.MOVE:
			spacing *= 0.65
		if absf(offset.x) > spacing or absf(offset.z) > spacing:
			continue
		var d := offset.length()
		if d >= spacing:
			continue
		if d < 0.001:
			offset = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			d = maxf(offset.length(), 0.001)
		push += offset / d * (spacing - d) * 2.5
	return push.limit_length(move_speed * 0.8)


func _closest_point_on(rect: Rect2) -> Vector3:
	return Vector3(clampf(position.x, rect.position.x, rect.end.x), 0.0,
		clampf(position.z, rect.position.y, rect.end.y))


func _nearest_enemy(max_distance: float):
	var best = null
	var best_distance := max_distance
	for other in all_units:
		if other.team == team or not other.is_alive():
			continue
		var d := position.distance_to(other.position)
		if d < best_distance:
			best_distance = d
			best = other
	if best == null:
		for building in Building.all_buildings:
			if building.team == team or not building.is_alive():
				continue
			var d := position.distance_to(_closest_point_on(building.footprint))
			if d < best_distance:
				best_distance = d
				best = building
	return best


# --- animation / presentation ---------------------------------------------

func _play(role: String, blend := 0.2, speed := 1.0) -> float:
	var anim: String = _anims.get(role, "")
	if _player == null or anim == "":
		return 0.5
	var animation := _player.get_animation(anim)
	animation.loop_mode = Animation.LOOP_NONE if role in ["attack", "death", "dead"] else Animation.LOOP_LINEAR
	_player.play(anim, blend, speed)
	return animation.length / speed


func _play_attack() -> float:
	var anim: String = _anims["attack"]
	if _player == null or anim == "":
		return 0.5
	var length := _player.get_animation(anim).length
	# Never let the swing take longer than the attack interval.
	var speed := maxf(1.0, length / (attack_interval * 0.95))
	_player.stop()
	return _play("attack", 0.1, speed)


func _is_playing(role: String) -> bool:
	return _player != null and _anims.get(role, "") != "" and _player.current_animation == _anims[role]


static func _pick(animations: Array, tokens: Array, excluded: Array) -> String:
	for token in tokens:
		for name in animations:
			if not token in name or "3p" in name:
				continue
			var skip := false
			for word in excluded:
				if word in name:
					skip = true
			if not skip:
				return name
	return ""


func _bar_height() -> float:
	var tag := _model.find_child("tag_hpbar", true, false) as Node3D
	if tag:
		return maxf(tag.global_position.y - global_position.y + 0.3, 1.8)
	return 2.4 if radius > 0.9 else 2.1


func _update_health_bar() -> void:
	if _health_bar == null:
		return
	_health_bar.set_fraction(clampf(hit_points / max_hit_points, 0.0, 1.0), team_color)
