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

const Projectile := preload("res://scripts/projectile.gd")

const CONFIG_PATH := "res://data/hero.json"
const BOW_RANGE := 55.0
const BOW_ARC := 0.55           # dot product: roughly a 110 degree cone in front
const SPEED_SCALE := 2.2        # the hero runs in hero mode instead of marching
const BLOCK_SPEED := 0.45
const BLOCK_REDUCTION := 0.75
const ATTACK_SPEED := 1.2
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
var _attack_left := 0.0   # seconds the current swing or recovery still runs
var _recovering := false  # the swing is done, the sword is going back to guard
var _queued := false      # clicked during a swing: chain the next hit onto it
var _queued_kind := ""
var _kind := "swing"      # what the running attack is
var _bow := false         # sword or bow in hand
var _stamina := 100.0
var _rest := 0.0          # seconds before stamina starts coming back
var _hint := 0.0          # keeps the "too exhausted" notice from repeating
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


static var _config := {}


# --- state ------------------------------------------------------------------

## Everything the hero's attacks cost and do, see data/hero.json.
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
	return _config


func stamina() -> float:
	return _stamina


## The hero grows tougher with his level: more stamina, and every blow lands harder.
func stamina_max() -> float:
	var s: Dictionary = config().get("stamina", {})
	return float(s.get("base", 100.0)) + float(s.get("per_level", 20.0)) * maxi(GameState.hero_level(team) - 1, 0)


func using_bow() -> bool:
	return _bow

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
	_hero.add_alternate_body(_bow_unit())
	_bow = false
	_hero.use_alternate_body(false)
	_stamina = stamina_max()
	_rest = 0.0
	if not _hero.damaged.is_connected(_on_damaged):
		_hero.damaged.connect(_on_damaged)
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
	_attack_left = 0.0
	_recovering = false
	_queued = false
	_swing = -1.0
	_special_left = 0.0
	_combo = 0
	_order_timer = 0.0
	GameState.message.emit("Heldenmodus – Q wechselt die Waffe, Esc beendet ihn")
	Audio.effect("hero_enter", _hero.global_position)
	mode_changed.emit(true)
	return true


func leave() -> void:
	if not active:
		return
	active = false
	_bow = false
	if is_instance_valid(_hero):
		if _hero.damaged.is_connected(_on_damaged):
			_hero.damaged.disconnect(_on_damaged)
		if _hero.is_alive():
			_hero.resume_idle()
	_retinue.clear()
	_blocking = false
	if is_instance_valid(_hero):
		Audio.effect("hero_exit", _hero.global_position)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if camera_rig:
		camera_rig.end_follow()
	mode_changed.emit(false)


## The hero's bow body: the original keeps it as a unit of its own next to the sword one.
func _bow_unit() -> String:
	if _hero == null or not "melee" in _hero.definition_id:
		return ""
	var id: String = _hero.definition_id.replace("melee", "ranged")
	return id if not Assets.unit_def(id).is_empty() else ""


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
					_attack("heavy" if event.shift_pressed and not _bow else "")
				MOUSE_BUTTON_RIGHT:
					if _bow:
						_attack("aimed")  # with the sword the right button is the shield
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
			KEY_Q:
				switch_weapon()
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
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_special_timer = maxf(0.0, _special_timer - delta)
	_hint = maxf(0.0, _hint - delta)
	_rest = maxf(0.0, _rest - delta)
	if _rest <= 0.0 and _stamina < stamina_max():
		var regain := float(config().get("stamina", {}).get("regain_per_s", 14.0))
		_stamina = minf(stamina_max(), _stamina + regain * delta)
	if _swing >= 0.0:
		_swing -= delta
		if _swing < 0.0:
			_land_swing()
	if _attack_left > 0.0:
		_advance_attack(delta)
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
	# No shield while the bow is in his hands.
	_blocking = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _special_left <= 0.0 and not _bow
	_hero.damage_reduction = BLOCK_REDUCTION if _blocking else 0.0
	# Like the original, the hero always faces where the camera looks and strafes sideways -
	# that is what the separate left/right/back run animations are for.
	_hero.turn_to(yaw, delta)
	var moving := _move_input != Vector2.ZERO and _special_left <= 0.0
	if moving:
		var speed := _hero.move_speed * SPEED_SCALE * (BLOCK_SPEED if _blocking else 1.0)
		var direction := (Basis(Vector3.UP, yaw) * Vector3(_move_input.x, 0.0, _move_input.y)).normalized()
		_hero.step(direction * speed * delta)
	if _recovering and (moving or _blocking):
		_attack_left = 0.0  # moving on or raising the shield cuts the recovery short
		_recovering = false
	if _attack_left > 0.0 or _special_left > 0.0:
		return  # let the attack animation play out
	if _bow:
		if moving:
			_hero.play_animation("heross_3p_rrunst", 0.18, _hero.move_speed * SPEED_SCALE / 4.5)
		else:
			_bow_ready()
	elif moving:
		_hero.play_animation(_move_anim(_blocking), 0.18, _hero.move_speed * SPEED_SCALE / 4.5)
	else:
		_hero.play_animation("heross_3p_mdfnd1" if _blocking else "heross_matck_idle1", 0.2)


## Standing with the bow: the draw animation held at its ready pose - the original has no
## separate idle for it, the hero simply stands there with the arrow nocked.
func _bow_ready() -> void:
	var player := _hero.animation_player()
	if player == null or not _hero.has_animation("heross_3p_ratckst"):
		return
	if player.current_animation == "heross_3p_ratckst" and not player.is_playing():
		return
	_hero.play_animation("heross_3p_ratckst", 0.2, 1.0, false)
	player.seek(0.25, true)
	player.pause()


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

## A click starts an attack. Clicking again while one is running does not throw it away -
## it is remembered and chained on as soon as the blade comes round, which is what makes
## the combo read as one movement instead of a series of cut off swings. Every blow costs
## stamina, and the heavier it is the more it takes.
func _attack(kind := "") -> void:
	if hero() == null or _special_left > 0.0:
		return
	if kind == "":
		kind = "arrow" if _bow else "swing"
	var attack: Dictionary = config().get("attacks", {}).get(kind, {})
	if attack.is_empty():
		return
	if _bow and _aim_target() == null:
		return  # no arrow is wasted on empty ground
	if _attack_left > 0.0:
		if not _recovering:
			_queued = true
			_queued_kind = kind
			return
		_attack_left = 0.0  # a new blow cancels the recovery
	if not _spend(float(attack.get("stamina", 0.0)), str(attack.get("name", kind))):
		return
	_start_attack(kind)


## Takes stamina for a blow, or refuses it and says so.
func _spend(cost: float, what: String) -> bool:
	if _stamina < cost:
		if team == GameState.human_team and _hint <= 0.0:
			_hint = 1.5
			GameState.message.emit("Zu erschöpft: %s" % what)
		return false
	_stamina -= cost
	_rest = float(config().get("stamina", {}).get("rest_after_attack_s", 0.7))
	return true


func _start_attack(kind: String) -> void:
	_kind = kind
	_combo = (_combo % 2) + 1 if (_combo_timer > 0.0 and kind == "swing") else 1
	_combo_timer = COMBO_WINDOW
	_queued = false
	_queued_kind = ""
	_recovering = false
	var speed := ATTACK_SPEED if kind == "swing" else 1.0
	Audio.effect("bow" if _bow else ("hero_swing" if kind == "heavy" else "swing"), _hero.global_position, -2.0)
	_attack_left = _hero.play_animation(_attack_anim(kind, false), 0.1, speed, false)
	if _attack_left <= 0.0:
		_attack_left = 0.6
	# The arrow leaves the bow later in the animation than a sword lands.
	_swing = maxf(_attack_left * (0.6 if _bow else 0.45), 0.05)


## The original splits every sword swing into a strike ("...s") and the recovery back to
## guard ("...r"). The strike runs to its end, then either the next hit of the combo
## follows or the hero lowers the sword again. Bow shots and the heavy blow are one piece.
func _advance_attack(delta: float) -> void:
	_attack_left -= delta
	if _attack_left > 0.0:
		return
	_attack_left = 0.0
	if _queued:
		var kind := _queued_kind
		_queued = false
		var attack: Dictionary = config().get("attacks", {}).get(kind, {})
		if _spend(float(attack.get("stamina", 0.0)), str(attack.get("name", kind))):
			_start_attack(kind)
		return
	if not _recovering and not _bow and _kind == "swing":
		_recovering = true
		_attack_left = _hero.play_animation(_attack_anim(_kind, true), 0.12, ATTACK_SPEED, false)
	else:
		_recovering = false


## Which animation a blow uses: the bow set (r...) or the sword set (m...), and on the move
## the one for the direction he is running in.
func _attack_anim(kind: String, recovery: bool) -> String:
	if _bow:
		if _move_input != Vector2.ZERO:
			var running := "heross_3p_rrun%satckst" % _direction_suffix()
			if _hero.has_animation(running):
				return running
		return "heross_3p_ratckst"
	if kind == "heavy":
		return "alex_3p_msatck"
	var ending := "r" if recovery else "s"
	if _move_input != Vector2.ZERO:
		var candidate := "heross_3p_mrun%satck%d%s" % [_direction_suffix(), _combo, ending]
		if _hero.has_animation(candidate):
			return candidate
	return "heross_3p_mpatck%d%s" % [_combo, ending]


## What a blow does to this target: its own damage, the hero's level, and the class bonus.
func _damage(kind: String, target) -> float:
	var attack: Dictionary = config().get("attacks", {}).get(kind, {})
	var base := float(attack.get("damage", _hero.damage))
	var level := 1.0 + float(config().get("damage_per_level", 0.0)) * maxi(GameState.hero_level(team) - 1, 0)
	var family: String = target.family if "family" in target else ""
	return base * level * GameState.damage_multiplier(_hero.family, family, target is Building)


## The blow connects: an arrow flies at what he is aiming at, a sword hits everything in
## front of him.
func _land_swing() -> void:
	if hero() == null:
		return
	if _bow:
		var target = _aim_target()
		if target == null:
			return
		var arrow := Projectile.new()
		get_parent().add_child(arrow)
		arrow.launch(_hero, target, _hero.global_position + Vector3.UP * 1.7, _damage(_kind, target))
		return
	var forward := -_hero.global_transform.basis.z
	var reach: float = _hero.attack_range + ATTACK_REACH + (0.8 if _kind == "heavy" else 0.0)
	for target in _targets_near(reach):
		var to: Vector3 = _target_position(target) - _hero.global_position
		to.y = 0.0
		if to.length() > 0.01 and forward.dot(to.normalized()) < ATTACK_ARC:
			continue
		Audio.effect("hit_building" if target is Building else "hit_hero", _target_position(target) + Vector3.UP, 0.0)
		target.take_damage(_damage(_kind, target), _hero)


## What the bow is pointed at: whatever enemy sits most directly in front of him.
func _aim_target():
	var forward := -_hero.global_transform.basis.z
	var best = null
	var best_score := -1.0
	for unit in Unit.all_units:
		if unit.team == team or not unit.is_alive():
			continue
		var to := unit.global_position - _hero.global_position
		to.y = 0.0
		var distance := to.length()
		if distance > BOW_RANGE or distance < 0.5:
			continue
		var aim := forward.dot(to / distance)
		if aim < BOW_ARC:
			continue
		var score := aim * 2.0 - distance / BOW_RANGE
		if score > best_score:
			best_score = score
			best = unit
	return best


## Sword or bow. The bow is a body of its own in the original, with its own animations.
func switch_weapon() -> void:
	if hero() == null or _special_left > 0.0 or not _hero.has_alternate_body():
		return
	_bow = not _bow
	_hero.use_alternate_body(_bow)
	_attack_left = 0.0
	_recovering = false
	_queued = false
	_swing = -1.0
	_blocking = false
	_hero.damage_reduction = 0.0
	if team == GameState.human_team:
		GameState.message.emit("Bogen" if _bow else "Schwert")
		if _bow:
			Audio.effect("bow_pickup", _hero.global_position)


func _special() -> void:
	if _special_timer > 0.0 or _special_left > 0.0 or hero() == null:
		return
	var attack: Dictionary = config().get("attacks", {}).get("special", {})
	if not _spend(float(attack.get("stamina", 45.0)), str(attack.get("name", "Spezialangriff"))):
		return
	_special_timer = SPECIAL_COOLDOWN
	_special_left = _hero.play_animation("heross_3p_rspecial1" if _bow else "heross_3p_mspecial1", 0.1, 1.6, false)
	if _special_left <= 0.0:
		_special_left = 2.5
	_special_pulse = 0.0
	_swing = -1.0
	_attack_left = 0.0
	_recovering = false
	_queued = false


## The special attack sweeps everyone around the hero, several times while it lasts.
func _update_special(delta: float) -> void:
	_special_left -= delta
	_special_pulse -= delta
	if _special_pulse <= 0.0:
		_special_pulse = SPECIAL_PULSE
		for target in _targets_near(SPECIAL_RADIUS):
			target.take_damage(_damage("special", target) * SPECIAL_DAMAGE, _hero)
	if _special_left <= 0.0:
		_special_left = 0.0


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


## Raising the shield costs stamina with every blow it stops; when he has nothing left, his
## guard breaks until he has caught his breath.
func _on_damaged(_amount: float) -> void:
	if not _blocking:
		return
	var cost := float(config().get("stamina", {}).get("block_cost_per_hit", 6.0))
	if _stamina < cost:
		_blocking = false
		_hero.damage_reduction = 0.0
		if team == GameState.human_team and _hint <= 0.0:
			_hint = 1.5
			GameState.message.emit("Deckung gebrochen")
		return
	_stamina -= cost
	_rest = float(config().get("stamina", {}).get("rest_after_attack_s", 0.7))


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
		Audio.effect("hero_back", hero_unit.global_position)
		Audio.voice("alert/hero_returned")
