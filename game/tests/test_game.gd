extends Node
## What the wall grid alone cannot answer: the pieces as real buildings, with their models,
## their values out of the original data, and the rules around them. This runs as a scene
## so the autoloads are there, but it builds no skirmish - a handful of buildings on an
## empty tree, a few seconds all told.
##
##   godot --headless --path game res://tests/test_game.tscn
##
## The navmesh and the gate swinging need the running game and are checked by
## `--demo-select=walls` and `--demo-select=wallchain` instead.

const WallGrid := preload("res://scripts/wall_grid.gd")
const Check := preload("res://tests/check.gd")
const EnemyAI := preload("res://scripts/enemy_ai.gd")

const WALL := "wall_ymstraight_02"
const GATE := "wall_ymgateleft_00"
const PLATFORM := "wall_ymseigeplat_02"
const BARRACKS := "bld_ygmpbarracks_02"

var _check := Check.new()


func _ready() -> void:
	GameState.setup_players([
		{"team": 0, "name": "Blau", "color": Color.BLUE, "gold": 1000, "wood": 1000, "glory": 100},
		{"team": 1, "name": "Rot", "color": Color.RED, "gold": 1000, "wood": 1000, "glory": 100},
	])
	await _a_wall_knows_what_it_is()
	await _a_wall_covers_its_tiles()
	await _a_gate_is_two_tiles_and_two_leaves()
	await _the_data_says_what_a_piece_can_take()
	await _a_wall_goes_up_quickly()
	await _a_gate_clears_the_segments_under_it()
	await _a_wave_breaks_through_where_it_is_cheapest()
	await _a_wall_panel_offers_no_two_of_a_kind()
	_no_panel_in_the_civ_offers_two_of_a_kind()
	_a_batch_grows_with_the_settlements()
	_a_wall_is_paid_for()
	get_tree().quit(_check.report("buildings and gates"))


## Puts a building on the tree and hands it back ready to look at.
func _raise(id: String, team: int, at: Vector3, yaw := 0.0) -> Building:
	var building := Building.create(id, team)
	building.position = at
	building.rotation.y = yaw
	add_child(building)
	return building


## Clears the board between cases - Building keeps its list statically.
func _clear() -> void:
	for building in Building.all_buildings.duplicate():
		Building.all_buildings.erase(building)
		building.queue_free()
	Building.all_gates.clear()
	await get_tree().process_frame


func _a_wall_knows_what_it_is() -> void:
	var wall := _raise(WALL, 0, Vector3.ZERO)
	var gate := _raise(GATE, 0, Vector3(40, 0, 0))
	var barracks := _raise(BARRACKS, 0, Vector3(80, 0, 0))
	_check.ok(wall.is_wall(), "a wall segment counts as a wall")
	_check.ok(not wall.is_gate(), "a wall segment is not a gate")
	_check.ok(gate.is_wall(), "a gate counts as a wall")
	_check.ok(gate.is_gate(), "a gate counts as a gate")
	_check.ok(not barracks.is_wall(), "a barracks is not a wall")
	_check.ok(gate in Building.all_gates, "a gate is on the gate list, where units look for it")
	_check.ok(not (wall in Building.all_gates), "a plain segment is not on the gate list")
	await _clear()
	_check.ok(Building.all_gates.is_empty(), "a gate leaves the gate list when it goes")


func _a_wall_covers_its_tiles() -> void:
	var tile := WallGrid.TILE
	var wall := _raise(WALL, 0, Vector3(12, 0, 24))
	_check.near_vector(wall.footprint.size, Vector2(tile, tile), "a segment covers one tile")
	_check.near_vector(wall.footprint.get_center(), Vector2(12, 24), "a segment is centred where it stands")
	_check.same(wall.wall_tiles(), Vector2i.ONE, "a segment is one tile by one")

	var platform := _raise(PLATFORM, 0, Vector3(60, 0, 0))
	_check.same(platform.wall_tiles(), Vector2i(2, 2), "a siege platform measures two tiles by two")
	_check.near_vector(platform.footprint.size, Vector2(tile * 2, tile * 2), "and covers that much ground")

	var barracks := _raise(BARRACKS, 0, Vector3(100, 0, 0))
	_check.ok(barracks.footprint.size.x > tile, "a barracks takes its footprint from its own model")
	await _clear()


func _a_gate_is_two_tiles_and_two_leaves() -> void:
	var tile := WallGrid.TILE
	var gate := _raise(GATE, 0, Vector3.ZERO)
	_check.same(gate.wall_tiles(), Vector2i(WallGrid.GATE_TILES, 1), "a gate is two tiles wide")
	_check.near_vector(gate.footprint.size, Vector2(tile * 2, tile), "and covers two tiles of ground")
	# Both door leaves are mounted, each moved out to its own jamb so their free edges meet.
	var leaves := gate.find_children("*AnimationPlayer*", "AnimationPlayer", true, false)
	_check.ok(leaves.size() >= 2, "a gate hangs two door leaves, found %d" % leaves.size())
	var offsets: Array[float] = []
	for child in gate.get_children():
		if child is Node3D and not (child is MeshInstance3D) and child.name != "SelectionRing":
			if absf((child as Node3D).position.x) > 1.0:
				offsets.append((child as Node3D).position.x)
	_check.ok(offsets.size() >= 2, "both leaves are moved out of the middle")
	if offsets.size() >= 2:
		offsets.sort()
		_check.near(offsets[0], -WallGrid.GATE_LEAF_OFFSET, "the left leaf sits at its own jamb")
		_check.near(offsets[offsets.size() - 1], WallGrid.GATE_LEAF_OFFSET, "the right leaf sits at the other")
	_check.ok(not gate.is_gate_open(), "a fresh gate stands shut")

	var turned := _raise(GATE, 0, Vector3(60, 0, 0), PI * 0.5)
	_check.near_vector(turned.footprint.size, Vector2(tile, tile * 2),
		"a gate in a wall running north to south stands across it")
	await _clear()


## The values are the original's, read out of dbobjects by the converter - a gate is the
## tougher of the two, and neither of them shoots.
func _the_data_says_what_a_piece_can_take() -> void:
	var wall := _raise(WALL, 0, Vector3.ZERO)
	var gate := _raise(GATE, 0, Vector3(40, 0, 0))
	_check.near(wall.max_hit_points, 8000.0, "a wall segment has the original's hit points", 1.0)
	_check.near(gate.max_hit_points, 10000.0, "a gate has the original's hit points", 1.0)
	_check.ok(gate.max_hit_points > wall.max_hit_points, "a gate outlasts a plain segment")
	_check.near(wall.damage, 0.0, "a wall does not shoot back")
	_check.near(gate.damage, 0.0, "a gate does not shoot back")
	await _clear()


## A run is many segments, so they cannot each take as long as a barracks.
func _a_wall_goes_up_quickly() -> void:
	var wall := _raise(WALL, 0, Vector3.ZERO)
	var barracks := _raise(BARRACKS, 0, Vector3(80, 0, 0))
	_check.ok(wall.build_time < 15.0, "a wall segment goes up in under 15 s, not %.0f" % wall.build_time)
	_check.ok(wall.build_time < barracks.build_time, "a wall segment is quicker than a barracks")
	wall.add_construction(wall.build_time)
	_check.ok(wall.is_complete(), "a segment is finished once its build time is in")
	await _clear()


## A gate is dropped straight into a finished run: the segments it covers make way for it
## and are paid back, and nothing else is touched.
func _a_gate_clears_the_segments_under_it() -> void:
	var tile := WallGrid.TILE
	var kept := _raise(WALL, 0, Vector3(-tile * 2, 0, 0))
	var swallowed_left := _raise(WALL, 0, Vector3(-tile * 0.5, 0, 0))
	var swallowed_right := _raise(WALL, 0, Vector3(tile * 0.5, 0, 0))
	var theirs := _raise(WALL, 1, Vector3(0, 0, tile))
	GameState.player(0)["wood"] = 0
	var before: int = GameState.player(0)["wood"]

	var gate := _raise(GATE, 0, Vector3.ZERO)
	await get_tree().process_frame
	_check.ok(is_instance_valid(kept), "a segment clear of the gate stays")
	_check.ok(not is_instance_valid(swallowed_left), "the segment under the gate makes way")
	_check.ok(not is_instance_valid(swallowed_right), "so does the one beside it")
	_check.ok(is_instance_valid(theirs), "a wall of the other side is left alone")
	_check.ok(GameState.player(0)["wood"] > before, "the swallowed segments are paid back")
	_check.ok(is_instance_valid(gate) and gate.is_alive(), "and the gate itself stands")
	await _clear()


## The computer sends a whole wave at one piece rather than spreading along the run: the
## one that will fall soonest, and only if it is between the wave and where it is going.
func _a_wave_breaks_through_where_it_is_cheapest() -> void:
	var ai := EnemyAI.new()
	ai.team = 1
	ai.enemy_team = 0
	ai.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(ai)

	var from := Vector3(0, 0, -40)
	var goal := Vector3(0, 0, 40)
	_check.ok(ai._breach_target(from, goal) == null, "with no wall in the way the wave just marches")

	var line: Array[Building] = []
	for i in range(-2, 3):
		line.append(_raise(WALL, 0, Vector3(WallGrid.TILE * i, 0, 0)))
	var picked := ai._breach_target(from, goal)
	_check.ok(picked != null, "a wall across the way is picked as the place to break through")
	if picked:
		_check.near(picked.global_position.x, 0.0, "the piece straight ahead is the one picked", WallGrid.TILE)

	# A battered piece one tile off the way is cheaper to finish off than the fresh one
	# straight ahead; one far to the side is not worth the detour whatever state it is in.
	line[1].hit_points = 500.0
	_check.ok(ai._breach_target(from, goal) == line[1], "a battered piece beside the way is chosen")
	line[1].hit_points = line[1].max_hit_points
	line[0].hit_points = 1.0
	_check.ok(ai._breach_target(from, goal) != line[0], "a battered piece too far aside is left alone")

	# A gate is tougher than a segment, so the segment beside it wins.
	await _clear()
	var gate := _raise(GATE, 0, Vector3.ZERO)
	var beside := _raise(WALL, 0, Vector3(WallGrid.TILE * 1.5, 0, 0))
	var against := ai._breach_target(from, goal)
	_check.ok(against == beside, "the thinner segment is chosen over the tougher gate")
	_check.ok(against != gate, "the wave does not throw itself at the gate when a wall is easier")

	# Far off to the side is not in the way and is worth no detour.
	await _clear()
	_raise(WALL, 0, Vector3(300, 0, 0))
	_check.ok(ai._breach_target(from, goal) == null, "a wall nowhere near the way is left alone")
	ai.queue_free()
	await _clear()


## The original lists the left and the right half of a gate as separate conversions of a
## wall, both called "Gate" and both with the gate icon, plus a research of the same name
## that unlocks nothing: three buttons the player cannot tell apart. The converter drops
## the copies, so a selected wall offers the two things it can really become.
func _a_wall_panel_offers_no_two_of_a_kind() -> void:
	var wall := _raise(WALL, 0, Vector3.ZERO)
	var panel := wall.available_becomes()
	_check.same(panel.size(), 2, "a wall offers two ways of being rebuilt")
	var seen := {}
	for entry in panel:
		var key := "%s|%s" % [entry.get("name", ""), entry.get("icon", "")]
		_check.ok(not seen.has(key), "no two buttons read the same: %s" % key)
		seen[key] = true
	var names := panel.map(func(e): return str(e.get("name", "")))
	_check.ok("Gate" in names, "one of them turns the wall into a gate")
	_check.ok(wall.available_upgrades().is_empty(), "and no research sits next to it saying the same")
	await _clear()


## The same rule for every building the civilization has, so a later export cannot quietly
## bring the duplicates back.
func _no_panel_in_the_civ_offers_two_of_a_kind() -> void:
	var buildings: Dictionary = GameState.civ(0).get("buildings", {})
	_check.ok(not buildings.is_empty(), "the civilization has buildings to look at")
	for id in buildings:
		for panel_name in ["trains", "upgrades", "becomes"]:
			var seen := {}
			for entry in buildings[id].get(panel_name, []):
				var key := "%s|%s" % [entry.get("name", ""), entry.get("icon", "")]
				_check.ok(not seen.has(key), "%s lists %s twice in its %s" % [id, key, panel_name])
				seen[key] = true


## Soldiers come in groups, and the group grows with the settlements a player holds.
func _a_batch_grows_with_the_settlements() -> void:
	_check.same(GameState.batch_size(0), 3, "a player with no settlement trains the smallest group")
	var first := _raise("bld_ygmptowncenter", 0, Vector3(200, 0, 0))
	_check.ok(first.is_drop_site, "a town center counts as a settlement")
	_check.same(GameState.batch_size(0), 3, "the first settlement still trains three")
	_raise("bld_ygmptentsettlement", 0, Vector3(260, 0, 0))
	_check.same(GameState.batch_size(0), 4, "a second settlement adds one to the group")
	_check.same(GameState.batch_size(1), 3, "the other player's groups are its own business")


## Founding a wall costs what the original asks, and giving it back restores exactly that.
func _a_wall_is_paid_for() -> void:
	var cost: Dictionary = Assets.unit_def(WALL).get("cost", {})
	_check.ok(int(cost.get("gold", 0)) > 0, "a wall segment costs gold")
	_check.ok(int(cost.get("wood", 0)) > 0, "a wall segment costs wood")
	var gold: int = GameState.player(0)["gold"]
	var wood: int = GameState.player(0)["wood"]
	_check.ok(GameState.spend(0, cost), "a player with money can pay for a segment")
	_check.same(GameState.player(0)["gold"], gold - int(cost.get("gold", 0)), "the gold is taken")
	GameState.refund(0, cost)
	_check.same(GameState.player(0)["gold"], gold, "paying it back restores the gold")
	_check.same(GameState.player(0)["wood"], wood, "and the wood")

	GameState.player(1)["gold"] = 0
	GameState.player(1)["wood"] = 0
	_check.ok(not GameState.can_afford(1, cost), "a player with nothing cannot afford a segment")
	_check.ok(not GameState.spend(1, cost), "and paying fails rather than going negative")
	_check.same(GameState.player(1)["gold"], 0, "nothing is taken from an empty purse")
