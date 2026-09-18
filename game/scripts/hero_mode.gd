class_name HeroMode
extends Node
## Direct control of the hero, the original's second way to play: the camera drops behind
## Alexander, WASD moves him relative to the view, the mouse looks around, the left button
## swings his sword in a three hit combo, the right button raises his shield and the space
## bar sets off his special attack. Soldiers standing around him when he takes over become
## his retinue and follow him into the fight.
##
## While hero mode is on, the unit's own state machine is switched off (Unit.player_controlled)
## and input is consumed here, so neither the RTS camera nor the selection controller react.
## This node also brings fallen heroes back at their town center - a hero is never lost for
## good in the original either.

signal mode_changed(active: bool)

const SPEED_SCALE := 2.2        # the hero runs in hero mode instead of marching
const BLOCK_SPEED := 0.45
const BLOCK_REDUCTION := 0.75
const ATTACK_INTERVAL := 0.5
const COMBO_WINDOW := 1.1
const ATTACK_ARC := 0.35        # dot product, about a 140 degree swing
const ATTACK_REACH := 1.8
const SPECIAL_COOLDOWN := 18.0
const SPECIAL_RADIUS := 5.0
const SPECIAL_PULSE := 0.6
const SPECIAL_DAMAGE := 0.5
const RETINUE_RADIUS := 36.0
const RETINUE_MAX := 24
const RETINUE_LEASH := 7.0
const RESPAWN_DELAY := 45.0

var team := 0
var camera_rig: Node3D
var selection: Node  # selection_controller.gd
var active := false

var _hero: Unit
var _retinue: Array[Unit] = []
var _attack_timer := 0.0
var _combo := 0
var _combo_timer := 0.0
var _swing := -1.0
var _special_timer := 0.0
var _special_left := 0.0
var _special_pulse := 0.0
var _blocking := false
var _order_timer := 0.0
var _move_input := Vector2.ZERO
var _respawn := {}  # team -> seconds until the hero returns


# --- state ------------------------------------------------------------------

func hero() -> Unit:
	return _hero if is_instance_valid(_hero) and _hero.is_alive() else null


func special_ready() -> float:
	return 1.0 - clampf(_special_timer / SPECIAL_COOLDOWN, 0.0, 1.0)


func retinue_size() -> int:
	return _retinue.size()


func toggle() -> void:
	if active:
		leave()
	else:
		enter()


func enter() -> bool:
	if active or GameState.over:
		return false
	var candidate := hero_of(team)
	if candidate == null:
		GameState.message.emit("Kein Held verfügbar")
		return false
	_hero = candidate
	active = true
	if GameState.speed == 0.0:
		GameState.set_speed(1.0)  # there is nothing to steer while the game is paused
	_hero.player_controlled = true
	_hero.selected = false
	if selection:
		selection.cancel_placement()
		selection.clear_selection()
		selection.selection_changed.emit()
	_gather_retinue()
	if camera_rig:
		camera_rig.begin_follow(_hero)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_attack_timer = 0.0
	_swing = -1.0
	_special_left = 0.0
	_combo = 0
	_order_timer = 0.0
	GameState.message.emit("Heldenmodus – Esc oder H beendet ihn")
	mode_changed.emit(true)
	return true


func leave() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_hero) and _hero.is_alive():
		_hero.resume_idle()
	_retinue.clear()
	_blocking = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if camera_rig:
		camera_rig.end_follow()
	mode_changed.emit(false)


## The living hero of a team, if it has one.
static func hero_of(team_index: int) -> Unit:
	for unit in Unit.all_units:
		if unit.team == team_index and unit.is_hero and unit.is_alive():
			return unit
	return null


# --- input ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		if camera_rig:
			camera_rig.look_delta(event.relative)
	elif event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_attack()
				MOUSE_BUTTON_WHEEL_UP:
					camera_rig.zoom_follow(-0.8)
				MOUSE_BUTTON_WHEEL_DOWN:
					camera_rig.zoom_follow(0.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_H:
				leave()
			KEY_SPACE:
				_special()
			_:
				return
	else:
		return
	get_viewport().set_input_as_handled()


## H enters hero mode from the normal view.
func _unhandled_key_input(event: InputEvent) -> void:
	if active or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_H:
		enter()
		get_viewport().set_input_as_handled()


# --- simulation -------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_respawn(delta)
	if not active:
		return
	if hero() == null or GameState.over:
		leave()
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_special_timer = maxf(0.0, _special_timer - delta)
	if _swing >= 0.0:
		_swing -= delta
		if _swing < 0.0:
			_land_swing()
	if _special_left > 0.0:
		_update_special(delta)
	_update_movement(delta)
	_order_timer -= delta
	if _order_timer <= 0.0:
		_order_timer = 1.0
		_command_retinue()


func _update_movement(delta: float) -> void:
	var yaw: float = camera_rig.yaw() if camera_rig else _hero.rotation.y
	_move_input = Vector2(
		Input.get_axis("cam_left", "cam_right"),
		Input.get_axis("cam_forward", "cam_back"))
	_blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _special_left <= 0.0
	_hero.damage_reduction = BLOCK_REDUCTION if _blocking else 0.0
	# Like the original, the hero always faces where the camera looks and strafes sideways -
	# that is what the separate left/right/back run animations are for.
	_hero.turn_to(yaw, delta)
	var moving := _move_input != Vector2.ZERO and _special_left <= 0.0
	if moving:
		var speed := _hero.move_speed * SPEED_SCALE * (BLOCK_SPEED if _blocking else 1.0)
		var direction := (Basis(Vector3.UP, yaw) * Vector3(_move_input.x, 0.0, _move_input.y)).normalized()
		_hero.step(direction * speed * delta)
	if _swing >= 0.0 or _special_left > 0.0:
		return  # an attack animation is running
	if moving:
		_hero.play_animation(_move_anim(_blocking), 0.18, _hero.move_speed * SPEED_SCALE / 4.5)
	else:
		_hero.play_animation("heross_3p_mdfnd1" if _blocking else "heross_matck_idle1", 0.2)


## Direction suffix of the 3p animation set: forward, back, strafe and the two diagonals.
func _direction_suffix() -> String:
	if _move_input.y < 0.0:
		if _move_input.x < 0.0:
			return "fl"
		return "fr" if _move_input.x > 0.0 else "f"
	if _move_input.y > 0.0:
		return "b"
	if _move_input.x < 0.0:
		return "l"
	return "r" if _move_input.x > 0.0 else "f"


func _move_anim(blocking: bool) -> String:
	var suffix := _direction_suffix()
	if blocking:
		return "heross_3p_mrun%sdfnd" % suffix
	return "heross_3p_mrun%s%s" % [suffix, {"f": "wd", "b": "ck", "l": "ft", "r": "gt",
		"fl": "ft", "fr": "gt"}[suffix]]


# --- fighting ---------------------------------------------------------------

func _attack() -> void:
	if _attack_timer > 0.0 or _special_left > 0.0 or hero() == null:
		return
	_attack_timer = ATTACK_INTERVAL
	_combo = (_combo % 2) + 1 if _combo_timer > 0.0 else 1
	_combo_timer = COMBO_WINDOW
	var length := _hero.play_animation(_attack_anim(), 0.08, 1.2, false)
	_swing = maxf(length * 0.45, 0.05)


## Attacking on the move uses the matching directional swing.
func _attack_anim() -> String:
	var base := "heross_3p_mpatck%d" % _combo
	if _move_input != Vector2.ZERO:
		var candidate := "heross_3p_mrun%satck%ds" % [_direction_suffix(), _combo]
		if _hero.has_animation(candidate):
			return candidate
	return base + "s"


## The swing connects: everything in front of the hero within reach is hit.
func _land_swing() -> void:
	if hero() == null:
		return
	var forward := -_hero.global_transform.basis.z
	for target in _targets_near(_hero.attack_range + ATTACK_REACH):
		var to: Vector3 = _target_position(target) - _hero.global_position
		to.y = 0.0
		if to.length() > 0.01 and forward.dot(to.normalized()) < ATTACK_ARC:
			continue
		target.take_damage(_hero.damage_against(target), _hero)


func _special() -> void:
	if _special_timer > 0.0 or _special_left > 0.0 or hero() == null:
		return
	_special_timer = SPECIAL_COOLDOWN
	_special_left = _hero.play_animation("heross_3p_mspecial1", 0.1, 1.6, false)
	_special_pulse = 0.0
	_swing = -1.0


## The special attack sweeps everyone around the hero, several times while it lasts.
func _update_special(delta: float) -> void:
	_special_left -= delta
	_special_pulse -= delta
	if _special_pulse <= 0.0:
		_special_pulse = SPECIAL_PULSE
		for target in _targets_near(SPECIAL_RADIUS):
			target.take_damage(_hero.damage_against(target) * SPECIAL_DAMAGE, _hero)
	if _special_left <= 0.0:
		_special_left = 0.0
		_attack_timer = 0.2


func _targets_near(reach: float) -> Array:
	var found := []
	for unit in Unit.all_units:
		if unit.team == team or not unit.is_alive():
			continue
		if _hero.global_position.distance_to(unit.global_position) <= reach + unit.radius + _hero.radius:
			found.append(unit)
	for building in Building.all_buildings:
		if building.team == team or not building.is_alive():
			continue
		var near := Vector3(
			clampf(_hero.global_position.x, building.footprint.position.x, building.footprint.end.x), 0.0,
			clampf(_hero.global_position.z, building.footprint.position.y, building.footprint.end.y))
		if _hero.global_position.distance_to(near) <= reach + _hero.radius:
			found.append(building)
	return found


func _target_position(target) -> Vector3:
	if target is Building:
		return Vector3(
			clampf(_hero.global_position.x, target.footprint.position.x, target.footprint.end.x), 0.0,
			clampf(_hero.global_position.z, target.footprint.position.y, target.footprint.end.y))
	return target.global_position


# --- retinue ----------------------------------------------------------------

func _gather_retinue() -> void:
	_retinue.clear()
	var nearby: Array[Unit] = []
	for unit in Unit.all_units:
		if unit.team != team or not unit.is_alive() or unit.is_worker or unit.is_hero:
			continue
		if unit.position.distance_to(_hero.position) <= RETINUE_RADIUS:
			nearby.append(unit)
	nearby.sort_custom(func(a, b): return a.position.distance_to(_hero.position) < b.position.distance_to(_hero.position))
	for unit in nearby.slice(0, RETINUE_MAX):
		_retinue.append(unit)


## Followers that are not busy fighting close by are pulled back behind the hero. They move
## as an attack-move, so they pick up enemies on the way instead of running past them.
func _command_retinue() -> void:
	var alive: Array[Unit] = []
	for unit in _retinue:
		if is_instance_valid(unit) and unit.is_alive():
			alive.append(unit)
	_retinue = alive
	if _retinue.is_empty():
		return
	var forward := -_hero.global_transform.basis.z
	var rally := _hero.global_position - forward * 3.5
	var stragglers := []
	for unit in _retinue:
		var distance := unit.position.distance_to(_hero.position)
		if unit.state == Unit.State.ATTACK and distance < RETINUE_RADIUS * 0.5:
			continue
		if distance > RETINUE_LEASH:
			stragglers.append(unit)
	if not stragglers.is_empty():
		Formation.move(stragglers, rally, true)


# --- respawn ----------------------------------------------------------------

## A fallen hero returns at his town center after a while - losing him for good would end
## the glory economy, which is what the hero levels are paid from.
func _tick_respawn(delta: float) -> void:
	if GameState.over:
		return
	for index in GameState.players.size():
		if hero_of(index) != null:
			_respawn.erase(index)
			continue
		if not _respawn.has(index):
			_respawn[index] = RESPAWN_DELAY
			if index == GameState.human_team:
				GameState.message.emit("Dein Held ist gefallen – er kehrt in %d s zurück" % int(RESPAWN_DELAY))
			continue
		_respawn[index] -= delta
		if _respawn[index] <= 0.0:
			_respawn.erase(index)
			_spawn_hero(index)


func _spawn_hero(index: int) -> void:
	var home := Building.nearest_drop_site(Vector3.ZERO, index)
	if home == null:
		return
	var id: String = GameState.civ(index).get("hero", {}).get("unit", "")
	if id == "":
		return
	var hero_unit := Unit.create(id, index, GameState.team_color(index))
	hero_unit.position = home.global_position + Vector3(0, 0, home.radius + 3.0) * (1.0 if home.global_position.z < 0.0 else -1.0)
	get_parent().add_child(hero_unit)
	if index == GameState.human_team:
		GameState.message.emit("%s ist zurück" % hero_unit.display_name)
