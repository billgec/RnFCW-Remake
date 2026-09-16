extends Node
## Global match state: players, their resources and civilization data.

signal resources_changed(team: int)
signal message(text: String)
signal match_over(winner_team: int)
signal speed_changed(speed: float)

const RESOURCES := ["gold", "wood"]

var players: Array[Dictionary] = []
var human_team := 0
var over := false
var speed := 1.0
var _civs := {}
var _bonuses := {}


func setup_players(definitions: Array) -> void:
	players.clear()
	over = false
	set_speed(1.0)
	for d in definitions:
		players.append({
			"team": d["team"], "name": d["name"], "color": d["color"], "civ": d.get("civ", "greek"),
			"gold": d.get("gold", 300), "wood": d.get("wood", 300),
		})


## Game speed, changeable at any time (the original only offered this before a mission).
func set_speed(value: float) -> void:
	speed = clampf(value, 0.0, 4.0)
	Engine.time_scale = speed
	speed_changed.emit(speed)


func bonuses() -> Dictionary:
	if _bonuses.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/bonuses.json"))
		_bonuses = parsed if parsed is Dictionary else {"default": 1.0, "table": {}, "vs_building": {}}
	return _bonuses


## Damage multiplier of one unit family against another (see data/bonuses.json).
func damage_multiplier(attacker_family: String, target_family: String, target_is_building: bool) -> float:
	var b := bonuses()
	if target_is_building:
		var vs: Dictionary = b.get("vs_building", {})
		return float(vs.get(attacker_family, b.get("vs_building_default", 0.4)))
	var table: Dictionary = b.get("table", {})
	var row: Dictionary = table.get(attacker_family, {})
	return float(row.get(target_family, b.get("default", 1.0)))


## Soldiers per training order. The original grows the formation with every outpost the
## player holds; here every settlement beyond the first counts as one, capped at 6.
func batch_size(team: int) -> int:
	var settlements := 0
	for b in Building.all_buildings:
		if b.team == team and b.is_alive() and b.is_drop_site:
			settlements += 1
	return clampi(3 + maxi(0, settlements - 1), 3, 6)


func player(team: int) -> Dictionary:
	return players[team]


func team_color(team: int) -> Color:
	return players[team]["color"] if team < players.size() else Color.WHITE


func civ(team: int) -> Dictionary:
	var id: String = players[team]["civ"]
	if not _civs.has(id):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(Assets.resolve("civs/%s.json" % id)))
		_civs[id] = parsed if parsed is Dictionary else {"buildings": {}}
	return _civs[id]


func can_afford(team: int, cost: Dictionary) -> bool:
	for r in RESOURCES:
		if players[team][r] < int(cost.get(r, 0)):
			return false
	return true


## Deducts the cost if affordable. Tells the human player what is missing otherwise.
func spend(team: int, cost: Dictionary) -> bool:
	if not can_afford(team, cost):
		if team == human_team:
			var missing := []
			for r in RESOURCES:
				if players[team][r] < int(cost.get(r, 0)):
					missing.append({"gold": "Gold", "wood": "Holz"}[r])
			message.emit("Nicht genug %s" % " und ".join(missing))
		return false
	for r in RESOURCES:
		players[team][r] -= int(cost.get(r, 0))
	resources_changed.emit(team)
	return true


func refund(team: int, cost: Dictionary) -> void:
	for r in RESOURCES:
		players[team][r] += int(cost.get(r, 0))
	resources_changed.emit(team)


func add_resource(team: int, kind: String, amount: int) -> void:
	players[team][kind] += amount
	resources_changed.emit(team)


func check_defeat(team: int) -> void:
	if over:
		return
	for building in Building.all_buildings:
		if building.team == team and building.is_alive() and building.is_drop_site:
			return
	over = true
	var winner := 1 - team
	match_over.emit(winner)
	message.emit("Sieg!" if winner == human_team else "Niederlage – dein Stadtzentrum ist gefallen")
