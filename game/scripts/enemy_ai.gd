extends Node
## Computer player: keeps its citizens gathering, trains citizens and soldiers as income
## allows, gathers an army at home and attacks the enemy's buildings in waves.

@export var team := 1
@export var enemy_team := 0
@export var first_attack_after := 420.0
@export var wave_size := 15

var _think_timer := 1.0
var _elapsed := 0.0
var _next_attack := 0.0
var _wave := 0


func _ready() -> void:
	_next_attack = first_attack_after


func _process(delta: float) -> void:
	if GameState.over:
		return
	_elapsed += delta
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = 1.5
	var workers: Array[Unit] = []
	var army: Array[Unit] = []
	for u in Unit.all_units:
		if u.team != team:
			continue
		if u.is_worker:
			workers.append(u)
		elif not u.is_hero:
			army.append(u)
	_manage_workers(workers)
	_train(workers.size(), army.size())
	_manage_army(army)


func _manage_workers(workers: Array[Unit]) -> void:
	var on_gold := 0
	for w in workers:
		if w.state in [Unit.State.GATHER, Unit.State.RETURN] and (w.carry_kind == "gold" or (w._resource and w._resource.kind == "gold")):
			on_gold += 1
	for w in workers:
		if w.state != Unit.State.IDLE:
			continue
		var kind := "gold" if on_gold < workers.size() * 0.55 else "wood"
		var node := ResourceNode.nearest(w.position, kind, 120.0)
		if node == null:
			node = ResourceNode.nearest(w.position, "wood" if kind == "gold" else "gold", 120.0)
		if node:
			w.order_gather(node)
			if node.kind == "gold":
				on_gold += 1


func _train(worker_count: int, army_count: int) -> void:
	for building in Building.all_buildings:
		if building.team != team or not building.is_complete() or building.queue.size() >= 2:
			continue
		if building.trains.is_empty():
			continue
		var choice := ""
		if building.is_drop_site:
			if worker_count < 16:
				choice = building.trains[0]["unit"]
		else:
			# Mostly melee and archers, skipping siege crews.
			var options: Array = building.trains.filter(func(t): return not "ladder" in t["unit"])
			if options.is_empty():
				continue
			choice = options.pick_random()["unit"]
		if choice != "" and (building.is_drop_site or army_count < 40):
			building.enqueue(choice)


func _manage_army(army: Array[Unit]) -> void:
	var home := _home()
	var idle := army.filter(func(u): return u.state == Unit.State.IDLE)
	if _elapsed >= _next_attack and army.size() >= wave_size:
		var target := _enemy_target(home)
		if target != Vector3.INF:
			Formation.move(army, target, true)
			_wave += 1
			_next_attack = _elapsed + 180.0
			GameState.message.emit("Der Gegner greift an!")
		return
	# Between waves, idle soldiers gather in front of their town center.
	if home != Vector3.INF:
		var rally := home + (Vector3(0, 0, 18) if home.z < 0 else Vector3(0, 0, -18))
		var stragglers := idle.filter(func(u): return u.position.distance_to(rally) > 14.0)
		if stragglers.size() > 0:
			Formation.move(stragglers, rally)


func _home() -> Vector3:
	for b in Building.all_buildings:
		if b.team == team and b.is_drop_site:
			return b.global_position
	return Vector3.INF


func _enemy_target(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for b in Building.all_buildings:
		if b.team != enemy_team or not b.is_alive():
			continue
		var d := from.distance_to(b.global_position)
		if d < best_distance:
			best_distance = d
			best = b.global_position
	return best
