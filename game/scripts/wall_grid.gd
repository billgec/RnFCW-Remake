extends RefCounted
## The grid a wall is built on: how long a tile is, where the segments of one leg land,
## which way they face, and how much ground a piece covers.
##
## This is plain arithmetic and deliberately depends on nothing else - no autoloads, no
## scene - so `tests/test_walls.gd` can check it without starting the game.

## One wall tile, in metres: the original's wall models are two grid cells wide.
const TILE := 6.1
## A gateway is two tiles wide: each of the original's door leaves is 6.5 m long, and the
## two of them have to meet in the middle of it.
const GATE_TILES := 2
## How far each leaf sits from the gate's centre. The leaf models are mirror images with
## their free edge 4.59 m from their own origin (measured off the door bone in the glTF),
## so this offset is exactly what makes the two edges touch when the gate is shut.
const GATE_LEAF_OFFSET := 4.59
## The longest leg one click may lay down.
const MAX_RUN := 24


## The segment centres of one leg: axis aligned along whichever axis it reaches further on,
## one tile apart, rounded to whole tiles. A leg that turns a corner therefore gets its own
## direction, and ends on the grid its first segment set up - which is what lets the next
## leg start flush against this one instead of drifting off the corner.
static func run(from: Vector3, to: Vector3) -> Array[Vector3]:
	var delta := to - from
	var sideways := absf(delta.x) >= absf(delta.z)
	var reach := absf(delta.x) if sideways else absf(delta.z)
	var step := (Vector3.RIGHT if sideways else Vector3.BACK) * signf(delta.x if sideways else delta.z)
	var tiles := mini(roundi(reach / TILE), MAX_RUN)
	var points: Array[Vector3] = [from]
	for i in range(1, tiles + 1):
		points.append(from + step * TILE * i)
	return points


## Walls face across their run, and a gate's two leaves lie along it - the same quarter
## turn serves both, so a leg that turns a corner turns its pieces with it.
static func run_yaw(from: Vector3, to: Vector3) -> float:
	return 0.0 if absf(to.x - from.x) >= absf(to.z - from.z) else PI * 0.5


## A wall piece covers whole grid tiles exactly. Its model overhangs them - battlements
## stick out over the outer face - so a footprint taken from the mesh would be too wide and
## neighbouring segments of a run would refuse to touch. A piece turned across world X
## (yaw near a quarter turn) has its length along Z instead.
static func footprint(at: Vector3, yaw := 0.0, tiles := Vector2i.ONE) -> Rect2:
	var size := Vector2(tiles) * TILE
	if absf(sin(yaw)) > 0.7:
		size = Vector2(size.y, size.x)
	return Rect2(Vector2(at.x, at.z) - size * 0.5, size)
