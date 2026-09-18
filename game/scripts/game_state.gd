extends Node
## Global match state: players, their resources and civilization data.

signal resources_changed(team: int)
signal message(text: String)
signal match_over(winner_team: int)
signal speed_changed(speed: float)
signal research_completed(team: int, research_id: int)
signal hero_level_changed(team: int, level: int)

const RESOURCES := ["gold", "wood", "glory"]

var players: Array[Dictionary] = []
var human_team := 0
var over := false
var speed := 1.0
var _civs := {}
var _researched := {}  # team -> { research id: true }
var _bonuses := {}
var _glory := {}


func setup_players(definitions: Array) -> void:
	players.clear()
	over = false
	set_speed(1.0)
	for d in definitions:
		_researched[d["team"]] = {}
		players.append({
			"team": d["team"], "name": d["name"], "color": d["color"], "civ": d.get("civ", "greek"),
			"gold": d.get("gold", 300), "wood": d.get("wood", 300), "glory": d.get("glory", 0),
			"hero_level": 1,
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


## Hero level, the original's "epoch": upgrades, buildings and siege units only become
## available once the hero has reached their level.
func hero_level(team: int) -> int:
	return int(players[team].get("hero_level", 1))


func set_hero_level(team: int, level: int) -> void:
	if level <= hero_level(team):
		return
	players[team]["hero_level"] = level
	resources_changed.emit(team)
	hero_level_changed.emit(team, level)
	if team == human_team:
		message.emit("Held erreicht Stufe %d" % level)


func level_reached(team: int, level: int) -> bool:
	return level <= hero_level(team)


func glory_rates() -> Dictionary:
	if _glory.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/glory.json"))
		_glory = parsed if parsed is Dictionary else {}
	return _glory


## Glory for a kill, an own loss, a finished building or a statue tick.
func add_glory(team: int, reason: String) -> void:
	if team < 0 or team >= players.size():
		return
	var amount := int(glory_rates().get(reason, 0))
	if amount > 0:
		add_resource(team, "glory", amount)


func has_research(team: int, research_id: int) -> bool:
	return research_id == 0 or _researched.get(team, {}).has(research_id)


## Marks a research as done and upgrades the units it replaces.
func complete_research(team: int, research_id: int, label := "") -> void:
	if has_research(team, research_id):
		return
	_researched.get(team, {})[research_id] = true
	_apply_unit_upgrades(team, research_id)
	research_completed.emit(team, research_id)
	if team == human_team and label != "":
		message.emit("%s erforscht" % label)


## Every unit that the finished research unlocks replaces its lower-level siblings in the
## field - in this game a veteran unit is a different object, not a stat change.
func _apply_unit_upgrades(team: int, research_id: int) -> void:
	for building_id in civ(team).get("buildings", {}):
		for entry in civ(team)["buildings"][building_id].get("trains", []):
			if int(entry.get("requires_research", 0)) != research_id:
				continue
			var new_id: String = entry["unit"]
			var line: String = entry.get("line", "")
			var level := int(entry.get("level", 1))
			for unit in Unit.all_units.duplicate():
				if unit.team == team and unit.line == line and unit.level < level:
					Unit.replace_with(unit, new_id)


func research_count(team: int) -> int:
	return _researched.get(team, {}).size()


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
					missing.append({"gold": "Gold", "wood": "Holz", "glory": "Ruhm"}[r])
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
