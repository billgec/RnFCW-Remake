extends SceneTree
## Wall geometry, without starting the game: where the segments of a leg land, which way
## they face, and how much ground a piece covers. Everything here is pure arithmetic, so it
## runs in a second - the things that need a running world (the navmesh, the gate opening
## and shutting) are checked by `--demo-select=walls` and `--demo-select=wallchain`.
##
##   godot --headless --path game --script res://tests/test_walls.gd

const WallGrid := preload("res://scripts/wall_grid.gd")

var _checks := 0


func _initialize() -> void:
	_leg_of_one()
	_leg_along_the_longer_axis()
	_legs_meet_at_their_corner()
	_a_leg_is_capped()
	_facing_follows_the_leg()
	_a_piece_covers_whole_tiles()
	print("%d checks passed" % _checks)
	quit()


func _ok(condition: bool, what: String) -> void:
	_checks += 1
	assert(condition, what)


## A click that goes nowhere still puts one segment down.
func _leg_of_one() -> void:
	var points := WallGrid.run(Vector3(10, 0, 10), Vector3(11, 0, 10))
	_ok(points.size() == 1, "a leg shorter than a tile is one segment, not %d" % points.size())
	_ok(points[0] == Vector3(10, 0, 10), "the single segment sits where the click was")


## The leg runs along whichever axis it reaches further on, never diagonally.
func _leg_along_the_longer_axis() -> void:
	var tile := WallGrid.TILE
	var eastwards := WallGrid.run(Vector3(0, 0, 0), Vector3(tile * 3, 0, tile))
	_ok(eastwards.size() == 4, "three tiles east are four segments, not %d" % eastwards.size())
	for p in eastwards:
		_ok(p.z == 0.0, "an eastward leg stays on its own line, not z=%.1f" % p.z)
	var northwards := WallGrid.run(Vector3(0, 0, 0), Vector3(tile, 0, tile * 3))
	_ok(northwards.size() == 4, "three tiles north are four segments, not %d" % northwards.size())
	for p in northwards:
		_ok(p.x == 0.0, "a northward leg stays on its own line, not x=%.1f" % p.x)


## Segments sit a whole tile apart, and the leg ends on that grid - that is what lets the
## next leg start flush against this one instead of drifting off the corner.
func _legs_meet_at_their_corner() -> void:
	var tile := WallGrid.TILE
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(36, 0, 0))
	for i in range(1, leg.size()):
		var step := leg[i].x - leg[i - 1].x
		_ok(absf(step - tile) < 0.001, "segments stand %.2f m apart, not %.2f" % [step, tile])
	var corner: Vector3 = leg[leg.size() - 1]
	var back := WallGrid.run(corner, Vector3(corner.x, 0, 36))
	_ok(back[0] == corner, "the next leg starts on the corner the last one ended at")


func _a_leg_is_capped() -> void:
	var leg := WallGrid.run(Vector3(0, 0, 0), Vector3(10000, 0, 0))
	_ok(leg.size() <= WallGrid.MAX_RUN + 1,
		"one leg laid %d segments, more than the cap of %d" % [leg.size(), WallGrid.MAX_RUN])


## Walls face across their run, so a leg that turns a corner turns its segments with it.
func _facing_follows_the_leg() -> void:
	var eastwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(30, 0, 0))
	var northwards := WallGrid.run_yaw(Vector3(0, 0, 0), Vector3(0, 0, 30))
	_ok(absf(eastwards - northwards) > 1.0, "both ways of running a wall face the same way")
	_ok(is_equal_approx(eastwards, 0.0), "an eastward leg faces along X")
	_ok(is_equal_approx(northwards, PI * 0.5), "a northward leg faces along Z")


## A piece covers whole tiles, centred on where it stands; turning it a quarter turn turns
## its footprint with it, which is what a gate in a wall running north to south needs.
func _a_piece_covers_whole_tiles() -> void:
	var tile := WallGrid.TILE
	var segment := WallGrid.footprint(Vector3(10, 0, 20))
	_ok(segment.size.is_equal_approx(Vector2(tile, tile)), "a segment covers one tile, not %v" % segment.size)
	_ok(segment.get_center().is_equal_approx(Vector2(10, 20)), "a segment is centred where it stands")

	var gate := WallGrid.footprint(Vector3(0, 0, 0), 0.0, Vector2i(WallGrid.GATE_TILES, 1))
	_ok(gate.size.is_equal_approx(Vector2(tile * 2, tile)), "a gate is two tiles wide, not %v" % gate.size)
	var turned := WallGrid.footprint(Vector3(0, 0, 0), PI * 0.5, Vector2i(WallGrid.GATE_TILES, 1))
	_ok(turned.size.is_equal_approx(Vector2(tile, tile * 2)), "a turned gate is two tiles deep, not %v" % turned.size)

	# A gate takes more ground than a segment: that is what gives its two door leaves the
	# room to meet. How far they actually reach is a fact about the models, checked on
	# screen and by --demo-select=walls, not something this grid knows.
	_ok(gate.size.x > segment.size.x, "a gate is no wider than a plain segment")
