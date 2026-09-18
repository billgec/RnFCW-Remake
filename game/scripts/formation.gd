class_name Formation
extends RefCounted
## Block formations: the slot layout every group marches in, and the one-off move used for
## soldiers that do not belong to a group (and by the computer player).

const GAP := 0.6   # space between two soldiers on top of their own width
const BLOCK_GAP := 2.0


## Spacing between the ranks and files of a block of these units.
static func spacing_for(unit) -> float:
	return unit.radius * 2.0 + GAP


## The slot offsets of a block, centred on its front rank: x to the side, y to the rear.
static func slots(count: int, spacing: float) -> Array:
	var columns := columns_for(count)
	var result: Array = []
	for i in count:
		result.append(Vector2((i % columns - (columns - 1) * 0.5) * spacing, (i / columns) * spacing))
	return result


static func columns_for(count: int) -> int:
	return maxi(1, int(ceil(sqrt(count * 2.0))))


static func block_width(count: int, spacing: float) -> float:
	return columns_for(count) * spacing


## Hands out the slots so nobody has to walk through the block: every slot goes to the
## nearest soldier that is still free, which keeps left on the left and front in front.
static func assign(members: Array, offsets: Array, anchor: Vector3, forward: Vector3, right: Vector3) -> Dictionary:
	var result := {}
	var free := members.duplicate()
	for offset in offsets:
		if free.is_empty():
			break
		var world: Vector3 = anchor + right * offset.x - forward * offset.y
		var best = free[0]
		var best_distance: float = best.position.distance_to(world)
		for unit in free:
			var distance: float = unit.position.distance_to(world)
			if distance < best_distance:
				best_distance = distance
				best = unit
		free.erase(best)
		result[best.get_instance_id()] = offset
	return result


## Places several blocks side by side around [param point], as seen from [param from].
static func spread(point: Vector3, from: Vector3, widths: Array) -> Array:
	var forward := point - from
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.1 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var total := 0.0
	for width in widths:
		total += float(width) + BLOCK_GAP
	var x := -total * 0.5
	var result: Array = []
	for width in widths:
		result.append(point + right * (x + (float(width) + BLOCK_GAP) * 0.5))
		x += float(width) + BLOCK_GAP
	return result


## Moves [param units] to [param point] as blocks - one block per unit type, melee in the
## middle-front, ranged next to it, cavalry on the side - facing the direction of travel.
static func move(units: Array, point: Vector3, attack_move := false) -> void:
	if units.is_empty():
		return
	var center := Vector3.ZERO
	for unit in units:
		center += unit.position
	center /= units.size()
	var forward := point - center
	forward.y = 0
	forward = forward.normalized() if forward.length() > 0.1 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var by_type := {}
	for unit in units:
		if not by_type.has(unit.definition_id):
			by_type[unit.definition_id] = []
		by_type[unit.definition_id].append(unit)
	var types := by_type.keys()
	types.sort_custom(func(a, b): return type_order(by_type[a][0]) < type_order(by_type[b][0]))
	var widths: Array = []
	for type in types:
		widths.append(block_width(by_type[type].size(), spacing_for(by_type[type][0])))
	var centers := spread(point, center, widths)
	for i in types.size():
		var members: Array = by_type[types[i]]
		var spacing := spacing_for(members[0])
		var offsets := slots(members.size(), spacing)
		var assignment := assign(members, offsets, centers[i], forward, right)
		for unit in members:
			var offset: Vector2 = assignment.get(unit.get_instance_id(), Vector2.ZERO)
			unit.order_move(centers[i] + right * offset.x - forward * offset.y, attack_move)


## Where a type belongs in a line: melee in front, ranged beside it, big units on the flank.
static func type_order(unit: Unit) -> int:
	if unit.is_worker:
		return 4
	if unit.ranged:
		return 2
	if unit.radius > 0.9:
		return 3
	return 1
