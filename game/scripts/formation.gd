class_name Formation
extends RefCounted
## Formation moves shared by the player's mouse orders and the computer player.

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
	types.sort_custom(func(a, b): return _type_order(by_type[a][0]) < _type_order(by_type[b][0]))
	var total_width := 0.0
	var blocks: Array = []
	for type in types:
		var members: Array = by_type[type]
		var spacing: float = members[0].radius * 2.0 + 0.5
		var columns := int(ceil(sqrt(members.size() * 2.0)))
		blocks.append([members, spacing, columns])
		total_width += columns * spacing + 1.5
	var x := -total_width / 2.0
	for block in blocks:
		var members: Array = block[0]
		var spacing: float = block[1]
		var columns: int = block[2]
		members.sort_custom(func(a, b): return a.position.distance_to(point) < b.position.distance_to(point))
		for i in members.size():
			var row := i / columns
			var column := i % columns
			var offset: Vector3 = right * (x + (column + 0.5) * spacing) - forward * row * spacing
			members[i].order_move(point + offset, attack_move)
		x += columns * spacing + 1.5


static func _type_order(unit: Unit) -> int:
	if unit.is_worker:
		return 4
	if unit.ranged:
		return 2
	if unit.radius > 0.9:
		return 3
	return 1
