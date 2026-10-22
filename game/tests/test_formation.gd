extends SceneTree
## The block a group marches in: how wide it stands, where each slot sits, who gets which
## slot, and how several blocks line up side by side. All of it is arithmetic on arrays and
## vectors, so it runs without the game - the soldiers are stand-ins with nothing but a
## position and a radius, which is all the formation code asks of them.
##
##   godot --headless --path game --script res://tests/test_formation.gd

const Formation := preload("res://scripts/formation.gd")
const Check := preload("res://tests/check.gd")

var _check := Check.new()


## A soldier as far as the formation code is concerned.
class Soldier extends RefCounted:
	var position := Vector3.ZERO
	var radius := 0.6
	var ranged := false
	var is_worker := false

	func _init(at := Vector3.ZERO, size := 0.6) -> void:
		position = at
		radius = size


func _initialize() -> void:
	_a_block_is_wider_than_it_is_deep()
	_a_block_stands_centred_on_its_front()
	_ranks_fill_from_the_front()
	_spacing_leaves_room_between_men()
	_the_width_covers_every_file()
	_every_slot_goes_to_a_man_of_its_own()
	_nobody_walks_through_the_block()
	_a_short_block_takes_what_men_there_are()
	_blocks_stand_side_by_side()
	_blocks_are_centred_on_where_they_were_sent()
	_blocks_line_up_across_the_march()
	_each_kind_has_its_place_in_the_line()
	quit(_check.report("formations"))


## Melee up front, archers beside them, riders on the flank, citizens last.
func _each_kind_has_its_place_in_the_line() -> void:
	var melee := Soldier.new()
	var archer := Soldier.new()
	archer.ranged = true
	var rider := Soldier.new(Vector3.ZERO, 1.1)
	var citizen := Soldier.new()
	citizen.is_worker = true
	var melee_place := Formation.type_order(melee)
	_check.ok(melee_place < Formation.type_order(archer), "melee stand ahead of archers")
	_check.ok(melee_place < Formation.type_order(rider), "melee stand ahead of riders")
	_check.ok(Formation.type_order(citizen) > Formation.type_order(rider), "citizens come last of all")
	var armed_rider := Soldier.new(Vector3.ZERO, 1.1)
	armed_rider.ranged = true
	_check.same(Formation.type_order(armed_rider), Formation.type_order(archer),
		"a mounted archer lines up with the archers, not with the riders")


func _men(positions: Array) -> Array:
	var result: Array = []
	for p in positions:
		result.append(Soldier.new(p))
	return result


## A line of battle is wider than deep - about two files to every rank.
func _a_block_is_wider_than_it_is_deep() -> void:
	for count in [2, 4, 9, 16, 32, 64]:
		var columns := Formation.columns_for(count)
		var rows := int(ceil(float(count) / columns))
		_check.ok(columns >= rows, "%d men stand %d wide and %d deep" % [count, columns, rows])
		_check.ok(columns <= count, "%d men never stand in more than %d files" % [count, count])
	_check.same(Formation.columns_for(1), 1, "one man is a file of his own")
	_check.ok(Formation.columns_for(0) >= 1, "an empty block still has a file, not none")


## The slots are centred sideways on the spot the block was sent to, so a group arrives
## where it was clicked rather than half a block to the left.
func _a_block_stands_centred_on_its_front() -> void:
	for count in [1, 2, 3, 5, 12, 30]:
		var offsets := Formation.slots(count, 2.0)
		var leftmost := INF
		var rightmost := -INF
		for offset in offsets:
			leftmost = minf(leftmost, offset.x)
			rightmost = maxf(rightmost, offset.x)
		_check.near((leftmost + rightmost) * 0.5, 0.0, "a block of %d stands centred" % count)


func _ranks_fill_from_the_front() -> void:
	var spacing := 2.0
	var offsets := Formation.slots(10, spacing)
	_check.same(offsets.size(), 10, "every man gets a slot")
	var columns := Formation.columns_for(10)
	for i in offsets.size():
		var slot: Vector2 = offsets[i]
		_check.near(slot.y, float(i / columns) * spacing, "slot %d stands in its own rank" % i)
	_check.near(offsets[0].y, 0.0, "the first man stands in the front rank")
	var last: Vector2 = offsets[offsets.size() - 1]
	_check.ok(last.y >= offsets[0].y, "later men stand behind, never in front")


func _spacing_leaves_room_between_men() -> void:
	var small := Formation.spacing_for(Soldier.new(Vector3.ZERO, 0.6))
	var big := Formation.spacing_for(Soldier.new(Vector3.ZERO, 1.2))
	_check.ok(small > 1.2, "two men of 0.6 m do not stand inside each other")
	_check.ok(big > small, "a rider takes more room than a foot soldier")
	# Neighbours in a rank must be at least as far apart as the two of them are wide.
	var offsets := Formation.slots(6, small)
	_check.near(absf(offsets[1].x - offsets[0].x), small, "neighbours stand one spacing apart")
	_check.ok(absf(offsets[1].x - offsets[0].x) > 0.6 * 2.0, "and that is wider than the two of them")


func _the_width_covers_every_file() -> void:
	var spacing := 2.0
	for count in [1, 4, 9, 25]:
		var width := Formation.block_width(count, spacing)
		var offsets := Formation.slots(count, spacing)
		var span := 0.0
		for offset in offsets:
			span = maxf(span, absf(offset.x) * 2.0)
		_check.ok(width >= span, "a block of %d is %.1f m wide and spans %.1f m" % [count, width, span])


## Every slot goes to a man of its own: nobody is sent to two places and nobody is left out.
func _every_slot_goes_to_a_man_of_its_own() -> void:
	var men := _men([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3)])
	var offsets := Formation.slots(men.size(), 2.0)
	var taken := Formation.assign(men, offsets, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	_check.same(taken.size(), men.size(), "every man is given a slot")
	var seen := {}
	for id in taken:
		var slot: Vector2 = taken[id]
		var key := "%.2f/%.2f" % [slot.x, slot.y]
		_check.ok(not seen.has(key), "no slot is handed out twice")
		seen[key] = true


## The point of handing slots to the nearest free man: the one standing on the left ends up
## on the left, so the block forms without anyone crossing through it.
func _nobody_walks_through_the_block() -> void:
	var left := Soldier.new(Vector3(-10, 0, 0))
	var right := Soldier.new(Vector3(10, 0, 0))
	var offsets := Formation.slots(2, 2.0)
	var taken := Formation.assign([left, right], offsets, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	var left_slot: Vector2 = taken[left.get_instance_id()]
	var right_slot: Vector2 = taken[right.get_instance_id()]
	_check.ok(left_slot.x < right_slot.x, "the man on the left keeps the left hand slot")

	# Same again front to back: the man already up ahead takes the front rank.
	var ahead := Soldier.new(Vector3(0, 0, -10))
	var behind := Soldier.new(Vector3(0, 0, 10))
	var ranks := Formation.slots(4, 2.0)
	var deep := Formation.assign([behind, ahead], ranks, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	_check.ok(deep[ahead.get_instance_id()].y <= deep[behind.get_instance_id()].y,
		"the man already up ahead takes the front rank")


func _a_short_block_takes_what_men_there_are() -> void:
	var men := _men([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var offsets := Formation.slots(10, 2.0)  # more slots than men
	var taken := Formation.assign(men, offsets, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	_check.same(taken.size(), 2, "two men fill two slots and no more")
	var nobody := Formation.assign([], offsets, Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT)
	_check.ok(nobody.is_empty(), "no men, no slots handed out")


## Several blocks going to the same place stand beside each other instead of on each other.
func _blocks_stand_side_by_side() -> void:
	var widths := [6.0, 10.0, 4.0]
	var centers := Formation.spread(Vector3(0, 0, 20), Vector3(0, 0, 0), widths)
	_check.same(centers.size(), widths.size(), "every block is given a place")
	for i in range(1, centers.size()):
		var apart: float = centers[i].distance_to(centers[i - 1])
		var needed: float = (float(widths[i]) + float(widths[i - 1])) * 0.5
		_check.ok(apart > needed, "block %d clears block %d: %.1f m apart, %.1f m needed" % [i, i - 1, apart, needed])


func _blocks_are_centred_on_where_they_were_sent() -> void:
	var point := Vector3(5, 0, 25)
	var alone := Formation.spread(point, Vector3.ZERO, [8.0])
	_check.near(alone[0].distance_to(point), 0.0, "a single block lands on the spot itself")

	var three := Formation.spread(point, Vector3.ZERO, [6.0, 6.0, 6.0])
	var middle: Vector3 = (three[0] + three[2]) * 0.5
	_check.near(middle.distance_to(point), 0.0, "three blocks are centred on the spot between them")
	# Sent nowhere at all, the blocks still have to come out somewhere sensible.
	var standing := Formation.spread(point, point, [6.0, 6.0])
	_check.same(standing.size(), 2, "blocks ordered onto their own spot still get places")
	_check.ok(standing[0].distance_to(standing[1]) > 1.0, "and those places are not the same one")


## The line of blocks runs across the march, not along it - men arrive abreast.
func _blocks_line_up_across_the_march() -> void:
	var from := Vector3(0, 0, 0)
	var point := Vector3(0, 0, 30)          # marching north
	var centers := Formation.spread(point, from, [6.0, 6.0])
	var line: Vector3 = centers[1] - centers[0]
	var march := (point - from).normalized()
	_check.near(line.normalized().dot(march), 0.0, "the blocks line up across the way they march")
	for center in centers:
		_check.near(center.y, 0.0, "blocks stay on the ground")

	# Marching east instead, the line has to turn with it.
	var eastward := Formation.spread(Vector3(30, 0, 0), from, [6.0, 6.0])
	var east_line: Vector3 = (eastward[1] - eastward[0]).normalized()
	_check.near(east_line.dot(Vector3(1, 0, 0)), 0.0, "marching east, the blocks line up north to south")
