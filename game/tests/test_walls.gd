extends SceneTree
## The wall grid, without starting the game: where the segments of a leg land, which way
## they face, and how much ground a piece covers. All of it is plain arithmetic, so it runs
## in a fraction of a second. What needs a world - the models, a gate opening, the navmesh -
## is checked by tests/test_game.tscn and by the `--demo-select=` runs listed in main.gd.
##
##   godot --headless --path game --script res://tests/test_walls.gd

const WallGrid := preload("res://scripts/wall_grid.gd")
const Check := preload("res://tests/check.gd")

var _check := Check.new()


func _initialize() -> void:
	_a_click_that_goes_nowhere()
	_a_leg_follows_the_longer_axis()
	_a_leg_runs_both_ways()
	_segments_stand_a_tile_apart()
	_a_leg_ends_on_the_grid()
	_a_leg_is_capped()
	_facing_follows_the_leg()
	_a_piece_covers_whole_tiles()
	_a_turned_piece_turns_its_ground()
	_pieces_of_a_leg_touch_without_overlapping()
	quit(_check.report("wall grid"))


## Clicking twice on the same spot still puts one segment down.
func _a_click_that_goes_nowhere() -> void:
	for target in [Vector3(10, 0, 10), Vector3(11, 0, 10), Vector3(10, 0, 12)]:
		var leg := WallGrid.run(Vector3(10, 0, 10), target)
		_check.same(leg.size(), 1, "a leg shorter than a tile is one segment")
		_check.ok(leg[0] == Vector3(10, 0, 10), "that segment sits where the click was")


## A leg runs along one axis only - the one it reaches further on - never diagonally.
func _a_leg_follows_the_longer_axis() -> void:
	var tile := WallGrid.TILE
	var eastwards := WallGrid.run(Vector3(0, 0, 0), Vector3(tile * 3, 0, tile))
	_check.same(eastwards.size(), 4, "three tiles east are four segments")
	for p in eastwards:
		_check.near(p.z, 0.0, "an eastward leg keeps to its line")
	var northwards := WallGrid.run(Vector3(0, 0, 0), Vector3(tile, 0, tile * 3))
	_check.same(northwards.size(), 4, "three tiles north are four segments")
	for p in northwards:
		_check.near(p.x, 0.0, "a northward leg keeps to its line")
	# Dead even: the leg has to pick one, and picks the x axis.
	var even := WallGrid.run(Vector3(0, 0, 0), Vector3(tile * 2, 0, tile * 2))
	_check.near(even[even.size() - 1].z, 0.0, "an even drag runs east, not north")


## Dragging back the way you came works the same as dragging forward.
func _a_leg_runs_both_ways() -> void:
	var tile := WallGrid.TILE
	var west := WallGrid.run(Vector3(0, 0, 0), Vector3(-tile * 3, 0, 0))
	_check.same(west.size(), 4, "three tiles west are four segments")
	_check.near(west[3].x, -tile * 3, "the westmost segment is three tiles out")
	var south := WallGrid.run(Vector3(0, 0, 0), Vector3(0, 0, -tile * 2))
	_check.same(south.size(), 3, "two tiles south are three segments")
	_check.near(south[2].z, -tile * 2, "the southmost segment is two tiles out")


func _segments_stand_a_tile_apart() -> void:
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(36, 0, 0))
	_check.ok(leg.size() > 2, "a 36 m leg is more than two segments")
	for i in range(1, leg.size()):
		_check.near(leg[i].x - leg[i - 1].x, WallGrid.TILE, "segments stand one tile apart")


## The leg ends on the grid its first segment set up. That is what lets the next leg start
## flush against this one instead of drifting off the corner, so a run can enclose a yard.
func _a_leg_ends_on_the_grid() -> void:
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(36, 0, 0))
	var corner: Vector3 = leg[leg.size() - 1]
	var tiles_out := corner.x / WallGrid.TILE
	_check.near(tiles_out, roundf(tiles_out), "the corner sits a whole number of tiles out")
	var back := WallGrid.run(corner, Vector3(corner.x, 0, 36))
	_check.ok(back[0] == corner, "the next leg starts on the corner the last one ended at")
	# Four legs around a yard have to come back to where they started.
	var south := WallGrid.run(Vector3(0, 0, 0), Vector3(36, 0, 0))
	var east := WallGrid.run(south[south.size() - 1], Vector3(36, 0, 36))
	var north := WallGrid.run(east[east.size() - 1], Vector3(0, 0, 36))
	var west := WallGrid.run(north[north.size() - 1], Vector3(0, 0, 0))
	_check.near(west[west.size() - 1].distance_to(Vector3(0, 0, 0)), 0.0,
		"four legs around a yard close on their own starting point", 0.6)


func _a_leg_is_capped() -> void:
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(10000, 0, 0))
	_check.ok(leg.size() <= WallGrid.MAX_RUN + 1,
		"one leg laid %d segments, past the cap of %d" % [leg.size(), WallGrid.MAX_RUN])


## Walls face across their run, so a leg that turns a corner turns its segments with it.
func _facing_follows_the_leg() -> void:
	var eastwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(30, 0, 0))
	var westwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(-30, 0, 0))
	var northwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(0, 0, 30))
	var southwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(0, 0, -30))
	_check.near(eastwards, 0.0, "an eastward leg faces along X")
	_check.near(westwards, 0.0, "a westward leg faces the same way as an eastward one")
	_check.near(northwards, PI * 0.5, "a northward leg faces along Z")
	_check.near(southwards, PI * 0.5, "a southward leg faces the same way as a northward one")
	_check.ok(absf(eastwards - northwards) > 1.0, "a corner really does turn its segments")


func _a_piece_covers_whole_tiles() -> void:
	var tile := WallGrid.TILE
	var segment := WallGrid.footprint(Vector3(10, 0, 20))
	_check.near_vector(segment.size, Vector2(tile, tile), "a segment covers one tile")
	_check.near_vector(segment.get_center(), Vector2(10, 20), "a segment is centred where it stands")

	var gate := WallGrid.footprint(Vector3(0, 0, 0), 0.0, Vector2i(WallGrid.GATE_TILES, 1))
	_check.near_vector(gate.size, Vector2(tile * 2, tile), "a gate is two tiles wide")
	_check.ok(gate.size.x > segment.size.x, "a gate takes more ground than a plain segment")

	var platform := WallGrid.footprint(Vector3(-5, 0, -5), 0.0, Vector2i(2, 2))
	_check.near_vector(platform.size, Vector2(tile * 2, tile * 2), "a siege platform covers two by two")
	_check.near_vector(platform.get_center(), Vector2(-5, -5), "a piece on negative ground is centred too")


## A gate in a wall running north to south has to stand across that wall, not along it.
func _a_turned_piece_turns_its_ground() -> void:
	var tile := WallGrid.TILE
	var tiles := Vector2i(WallGrid.GATE_TILES, 1)
	var turned := WallGrid.footprint(Vector3(0, 0, 0), PI * 0.5, tiles)
	_check.near_vector(turned.size, Vector2(tile, tile * 2), "a quarter turn turns the ground with it")
	var half_turned := WallGrid.footprint(Vector3(0, 0, 0), PI, tiles)
	_check.near_vector(half_turned.size, Vector2(tile * 2, tile), "a half turn leaves the ground as it was")
	var square := WallGrid.footprint(Vector3(0, 0, 0), PI * 0.5)
	_check.near_vector(square.size, Vector2(tile, tile), "turning a one tile piece changes nothing")


## Neighbouring segments have to touch exactly: a gap lets men walk through the wall, an
## overlap makes the next segment refuse to go down.
func _pieces_of_a_leg_touch_without_overlapping() -> void:
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(30, 0, 0))
	for i in range(1, leg.size()):
		var here := WallGrid.footprint(leg[i - 1])
		var next := WallGrid.footprint(leg[i])
		_check.near(next.position.x, here.end.x, "one segment ends where the next begins")
		_check.ok(not here.grow(-0.05).intersects(next.grow(-0.05)), "touching segments do not overlap")
