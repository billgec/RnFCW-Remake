class_name Building
extends Node3D
## A building: hit points, training queue, rally point, construction progress and the
## drop site role for gathered resources (town centers).

signal destroyed(building: Building)
signal queue_changed(building: Building)

const HealthBar := preload("res://scripts/health_bar.gd")
const SelectionRing := preload("res://scripts/selection_ring.gd")
const RallyFlag := preload("res://scripts/rally_flag.gd")
## Units that are trained one at a time instead of in a batch.
const SINGLE_UNITS := ["worker", "citizen", "ladder", "onager", "catapult", "ram", "siege"]

var definition_id := ""
var display_name := ""
var team := 0
var max_hit_points := 1000.0
var hit_points := 1000.0
var trains: Array = []
var family := "Building"
var damage := 0.0
var attack_range := 0.0
var attack_interval := 2.0
var _cooldown := 0.0
var is_drop_site := false
var footprint := Rect2()  # world XZ
var radius := 4.0
var rally_point := Vector3.ZERO:
	set(value):
		rally_point = value
		if _flag:
			_flag.global_position = Vector3(value.x, 0.0, value.z)
var queue: Array[Dictionary] = []  # {unit, cost, time, elapsed}
var build_progress := 1.0  # < 1 while under construction
var build_time := 30.0

var selected := false:
	set(value):
		selected = value and is_alive()
		if _ring:
			_ring.visible = selected
		if _flag:
			_flag.visible = selected and team == GameState.human_team

var _model: Node3D
var _ring: MeshInstance3D
var _bar: Node3D
var _dead := false
var _flag: Node3D
var _height := 4.0

static var all_buildings: Array[Building] = []


static func create(id: String, team_index: int, under_construction := false) -> Building:
	var b := Building.new()
	b.definition_id = id
	b.team = team_index
	b._model = Assets.spawn_unit(id, GameState.team_color(team_index))
	b.add_child(b._model)
	if under_construction:
		b.build_progress = 0.02
	return b


func _ready() -> void:
	all_buildings.append(self)
	var def := Assets.unit_def(definition_id)
	var stats: Dictionary = def.get("stats") if def.get("stats") != null else {}
	display_name = stats.get("name", definition_id)
	max_hit_points = float(stats.get("hit_points", 1000))
	trains = def.get("trains", [])
	family = stats.get("family", "Building")
	damage = float(stats.get("damage", 0))
	attack_range = float(stats.get("range_m", 0))
	attack_interval = maxf(float(stats.get("attack_interval_s", 2.0)), 0.8)
	if trains.is_empty() and is_drop_site:
		# The settlement shows no train list in the data but does produce citizens.
		var citizen: String = GameState.civ(team).get("citizen", "")
		if citizen != "":
			trains = [{"unit": citizen, "name": Assets.unit_def(citizen).get("stats", {}).get("name", "Citizen"), "slot": 7}]
	is_drop_site = "towncenter" in definition_id or "settlement" in definition_id or "governmentcenter" in definition_id
	build_time = clampf(max_hit_points / 90.0, 20.0, 90.0)
	_height = _measure_height()
	footprint = compute_footprint(self)
	radius = maxf(footprint.size.x, footprint.size.y) * 0.5
	rally_point = global_position + global_basis.z * (radius + 4.0)

	_ring = SelectionRing.new()
	_ring.setup_rect(footprint.size + Vector2(1.5, 1.5))
	_ring.visible = false
	add_child(_ring)
	# The ring is placed in world axes around the footprint center regardless of rotation.
	_ring.top_level = true
	var c := footprint.get_center()
	_ring.global_position = Vector3(c.x, 0.05, c.y)

	_flag = RallyFlag.create()
	_flag.top_level = true
	_flag.visible = false
	add_child(_flag)
	_flag.global_position = Vector3(rally_point.x, 0.0, rally_point.z)

	_bar = HealthBar.new()
	add_child(_bar)
	_bar.set_width(clampf(radius * 0.8, 2.0, 6.0))
	_bar.top_level = true
	_bar.global_position = Vector3(c.x, _height + 1.0, c.y)
	hit_points = max_hit_points * build_progress
	_apply_construction_look()
	_update_bar()


func _exit_tree() -> void:
	all_buildings.erase(self)


func is_alive() -> bool:
	return not _dead


func is_complete() -> bool:
	return build_progress >= 1.0


func unit_def_for(unit_id: String) -> Dictionary:
	return Assets.unit_def(unit_id)


## How many units one training order produces: soldiers come as a group (the original
## trains whole formations), citizens and siege pieces one by one.
func batch_size(unit_id: String) -> int:
	for token in SINGLE_UNITS:
		if token in unit_id:
			return 1
	return GameState.batch_size(team)


## Adds a training order to the queue (paying for the whole batch).
func enqueue(unit_id: String) -> bool:
	if not is_complete() or queue.size() >= 8:
		return false
	var def := Assets.unit_def(unit_id)
	var unit_cost: Dictionary = def.get("cost", {})
	var count := batch_size(unit_id)
	var cost := {}
	for key in unit_cost:
		cost[key] = unit_cost[key] * count if key != "time_s" else unit_cost[key]
	if not GameState.spend(team, cost):
		return false
	queue.append({"unit": unit_id, "cost": cost, "count": count,
		"time": maxf(float(unit_cost.get("time_s", 10.0)) * (1.0 + (count - 1) * 0.35), 3.0), "elapsed": 0.0})
	queue_changed.emit(self)
	return true


func cancel_last() -> void:
	if queue.is_empty():
		return
	var entry: Dictionary = queue.pop_back()
	GameState.refund(team, entry["cost"])
	queue_changed.emit(self)


func add_construction(amount: float) -> void:
	if is_complete() or not is_alive():
		return
	var before := build_progress
	build_progress = minf(1.0, build_progress + amount / build_time)
	hit_points = minf(max_hit_points, hit_points + (build_progress - before) * max_hit_points)
	_apply_construction_look()
	_update_bar()


## Citizens repairing a finished building.
func add_repair(amount: float) -> bool:
	if _dead or not is_complete() or hit_points >= max_hit_points:
		return false
	hit_points = minf(max_hit_points, hit_points + amount * max_hit_points / (build_time * 1.5))
	_update_bar()
	return true


func take_damage(amount: float, _attacker) -> void:
	if _dead:
		return
	hit_points -= amount
	_update_bar()
	if hit_points <= 0.0:
		_destroy()


func _process(delta: float) -> void:
	if _dead or not is_complete():
		return
	if damage > 0.0 and attack_range > 1.0:
		_shoot(delta)
	if queue.is_empty():
		return
	var entry: Dictionary = queue[0]
	entry["elapsed"] += delta
	if entry["elapsed"] >= entry["time"]:
		queue.pop_front()
		var count := int(entry.get("count", 1))
		for i in count:
			_spawn(entry["unit"])
		if team == GameState.human_team:
			var name: String = Assets.unit_def(entry["unit"]).get("stats", {}).get("name", "Einheit")
			GameState.message.emit("%s ausgebildet" % name if count == 1 else "%d %s ausgebildet" % [count, name])
		queue_changed.emit(self)


## Towers shoot at the nearest enemy in range.
func _shoot(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var center := Vector3(footprint.get_center().x, 0.0, footprint.get_center().y)
	var best: Unit = null
	var best_distance := attack_range
	for unit in Unit.all_units:
		if unit.team == team or not unit.is_alive():
			continue
		var d := center.distance_to(unit.position)
		if d < best_distance:
			best_distance = d
			best = unit
	if best == null:
		return
	_cooldown = attack_interval
	var projectile := preload("res://scripts/projectile.gd").new()
	get_parent().add_child(projectile)
	var multiplier := GameState.damage_multiplier(family, best.family, false)
	projectile.launch(null, best, center + Vector3.UP * (_height * 0.8), damage * multiplier)


func _spawn(unit_id: String) -> void:
	var unit := Unit.create(unit_id, team, GameState.team_color(team))
	var exit := global_position + global_basis.z * (radius + 1.5)
	unit.position = exit + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.0, 1.0))
	get_parent().add_child(unit)
	unit.order_move(rally_point + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))



func _destroy() -> void:
	_dead = true
	selected = false
	_bar.alive = false
	all_buildings.erase(self)
	for entry in queue:
		GameState.refund(team, entry["cost"])
	queue.clear()
	destroyed.emit(self)
	GameState.check_defeat(team)
	var tween := create_tween()
	tween.tween_property(_model, "position:y", -_height - 2.0, 6.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _apply_construction_look() -> void:
	# Under construction the model rises out of the ground.
	var height := _height
	_model.position.y = -height * (1.0 - build_progress) * 0.9


func _update_bar() -> void:
	_bar.set_fraction(clampf(hit_points / max_hit_points, 0.0, 1.0), GameState.team_color(team))


func _measure_height() -> float:
	var top := 4.0
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh.get_aabb()
		for i in 8:
			top = maxf(top, (mesh.global_transform * aabb.get_endpoint(i)).y - global_position.y)
	return minf(top, 25.0)


## World-space XZ rectangle covered by a node's meshes, shrunk a little because building
## bounds include overhanging roofs and banners.
static func compute_footprint(node: Node3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh.get_aabb()
		for i in 8:
			var corner := mesh.global_transform * aabb.get_endpoint(i)
			var p := Vector2(corner.x, corner.z)
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect.grow(-0.8)


static func nearest_drop_site(from: Vector3, team_index: int) -> Building:
	var best: Building = null
	var best_distance := INF
	for b in all_buildings:
		if b.team != team_index or not b.is_drop_site or not b.is_complete():
			continue
		var d := from.distance_to(b.global_position)
		if d < best_distance:
			best_distance = d
			best = b
	return best
