extends Node3D
## Groups (the original's formation banners): at least MIN_SIZE soldiers of the same type
## and team standing together form a persistent group marked by the original banner above
## its centre - freshly trained soldiers that gather at a rally point form one by themselves.
## A group stays together once formed: clicking any member, or the banner, or catching part
## of it in a selection box takes the whole group, and it marches as a block (see march()).

const MIN_SIZE := 9
const MAX_SIZE := 64
const LINK_DISTANCE := 4.5
const JOIN_DISTANCE := 7.0
const DISSOLVE_BELOW := 4
const BANNER_HEIGHT := 5.6
const BANNER_SCALE := 0.62

## Marching: how far the block may run ahead of its stragglers before it waits for them,
## how often the soldiers are given their updated slot, and when the march counts as done.
const MARCH_LEASH := 6.0
const MARCH_REISSUE := 0.4
const MARCH_ARRIVED := 1.5
const MARCH_PATIENCE := 3.0   # after waiting this long for a straggler, the block moves on

## Fighting as a group: how often the block looks for enemies, and how far the enemy has to
## move before the charge is aimed at its new place.
const ENGAGE_INTERVAL := 0.6
const ENGAGE_RETARGET := 4.0

var squads: Array[Dictionary] = []  # {id, members, banner, team, type, march?}

var _timer := 0.0
var _squad_of := {}  # unit instance id -> squad dictionary
var _banner_pool: Array[Node3D] = []
var _next_id := 1
var _marches: Array[Dictionary] = []
var _engage_timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_update_membership()
	_engage_timer -= delta
	if _engage_timer <= 0.0:
		_engage_timer = ENGAGE_INTERVAL
		_update_engagements()
	for record in _marches.duplicate():
		_advance_march(record, delta)
	var t := Time.get_ticks_msec() / 1000.0
	var camera := get_viewport().get_camera_3d()
	for squad in squads:
		var center := _center(squad["members"])
		var banner: Node3D = squad["banner"]
		var goal := center + Vector3.UP * (BANNER_HEIGHT + sin(t * 1.6 + center.x) * 0.12)
		banner.global_position = banner.global_position.lerp(goal, 1.0 - exp(-6.0 * delta))
		if camera:
			banner.rotation.y = camera.global_rotation.y


## The group a unit belongs to, or an empty dictionary.
func squad_of(unit) -> Dictionary:
	var squad = _squad_of.get(unit.get_instance_id())
	return squad if squad != null else {}


## Group whose banner is under the given screen point, or an empty dictionary.
func squad_at(screen_point: Vector2, camera: Camera3D) -> Dictionary:
	for squad in squads:
		var banner: Node3D = squad["banner"]
		if camera.is_position_behind(banner.global_position):
			continue
		if camera.unproject_position(banner.global_position + Vector3.UP * 0.6).distance_to(screen_point) < 38.0:
			return squad
	return {}


func _update_membership() -> void:
	# Drop the dead, dissolve groups that got too small.
	for squad in squads.duplicate():
		var members: Array = squad["members"].filter(func(u): return is_instance_valid(u) and u.is_alive())
		squad["members"] = members
		if members.size() < DISSOLVE_BELOW:
			for u in members:
				_squad_of.erase(u.get_instance_id())
				u.holds_formation = false
			_release_banner(squad["banner"])
			squads.erase(squad)

	var loose := {}  # "team:type" -> Array of ungrouped units
	for unit in Unit.all_units:
		if unit.is_worker or unit.is_hero or not unit.is_alive() or _squad_of.has(unit.get_instance_id()):
			continue
		var key := "%d:%s" % [unit.team, unit.definition_id]
		if not loose.has(key):
			loose[key] = []
		loose[key].append(unit)

	# Existing groups take in stragglers of their own type that are standing with them.
	for squad in squads:
		var key := "%d:%s" % [squad["team"], squad["type"]]
		if not loose.has(key) or squad["members"].size() >= MAX_SIZE:
			continue
		for unit in loose[key].duplicate():
			if squad["members"].size() >= MAX_SIZE:
				break
			if _distance_to_nearest(squad["members"], unit) <= JOIN_DISTANCE:
				squad["members"].append(unit)
				_squad_of[unit.get_instance_id()] = squad
				loose[key].erase(unit)

	# New groups from clusters of at least MIN_SIZE.
	for key in loose:
		for cluster in _clusters(loose[key]):
			while cluster.size() >= MIN_SIZE:
				var members: Array = cluster.slice(0, mini(MAX_SIZE, cluster.size()))
				cluster = cluster.slice(members.size())
				var banner := _take_banner()
				banner.global_position = _center(members) + Vector3.UP * BANNER_HEIGHT
				var squad := {
					"id": _next_id, "members": members, "banner": banner,
					"team": members[0].team, "type": members[0].definition_id,
				}
				_next_id += 1
				squads.append(squad)
				for u in members:
					_squad_of[u.get_instance_id()] = squad
					u.holds_formation = true


# --- marching ---------------------------------------------------------------

## Sends [param members] to [param target] as a block, whether they are a group or just a
## handful of soldiers the player picked. The formation is laid out facing the way it
## travels, everyone gets the slot nearest to where they already stand, and the block then
## walks as one - see _advance_march. Pass the group in [param squad] so the block follows
## its membership as soldiers join or fall.
## [param engage] marks a march the group may re-aim: an attack move or a charge follows
## enemies that come into sight, a plain move order is carried out as given.
func march(members: Array, target: Vector3, attack_move := false, squad := {}, engage := false) -> void:
	var living := _living(members)
	if living.is_empty():
		return
	_stop_marches_of(living)
	var center := _center(living)
	var forward := Vector3(target.x - center.x, 0.0, target.z - center.z)
	forward = forward.normalized() if forward.length() > 0.5 else Vector3.FORWARD
	var record := {
		"squad": squad, "members": living, "anchor": center,
		"target": Vector3(target.x, 0.0, target.z),
		"forward": forward, "right": forward.cross(Vector3.UP),
		"attack": attack_move, "engage": engage,
		"timer": MARCH_REISSUE, "slots": {}, "waited": 0.0,
	}
	_marches.append(record)
	_assign_slots(record, living)
	_issue_march(record, living, true)


## New orders replace old ones: a soldier only ever marches in one block.
func _stop_marches_of(members: Array) -> void:
	var ids := {}
	for unit in members:
		ids[unit.get_instance_id()] = true
	for record in _marches.duplicate():
		for unit in _march_members(record):
			if ids.has(unit.get_instance_id()):
				_marches.erase(record)
				break


func _march_members(record: Dictionary) -> Array:
	var squad: Dictionary = record["squad"]
	return _living(squad["members"] if not squad.is_empty() else record["members"])


## The block walks as one: its anchor creeps towards the target at the pace of the slowest
## soldier and holds whenever somebody falls too far behind, so the formation keeps its
## shape on the way instead of only at the destination.
func _advance_march(record: Dictionary, delta: float) -> void:
	var members := _march_members(record)
	if members.is_empty():
		_marches.erase(record)
		return
	if record["slots"].size() != members.size():
		_assign_slots(record, members)
	var lag := 0.0
	var speed := INF
	for unit in members:
		lag = maxf(lag, unit.position.distance_to(_slot_position(record, unit)))
		speed = minf(speed, unit.move_speed)
	var to_target: Vector3 = record["target"] - record["anchor"]
	to_target.y = 0.0
	var remaining := to_target.length()
	if remaining > 0.2 and (lag < MARCH_LEASH or record["waited"] > MARCH_PATIENCE):
		record["anchor"] += to_target / remaining * minf(speed * delta, remaining)
		if lag < MARCH_LEASH:
			record["waited"] = 0.0
	elif remaining > 0.2:
		# Somebody is stuck or fighting: wait for them, but not for ever.
		record["waited"] += delta
	record["timer"] -= delta
	if record["timer"] <= 0.0:
		record["timer"] = MARCH_REISSUE
		_issue_march(record, members)
	if remaining <= 0.2 and lag <= MARCH_ARRIVED:
		_marches.erase(record)


func _assign_slots(record: Dictionary, members: Array) -> void:
	var spacing := Formation.spacing_for(members[0])
	record["slots"] = Formation.assign(members, Formation.slots(members.size(), spacing),
		record["anchor"], record["forward"], record["right"])


func _issue_march(record: Dictionary, members: Array, force := false) -> void:
	for unit in members:
		# Someone in a fight keeps fighting and falls back in once it is over.
		if unit.state == Unit.State.ATTACK:
			continue
		var goal := _slot_position(record, unit)
		if force or unit.position.distance_to(goal) > 1.2:
			unit.order_move(goal, record["attack"])


func _slot_position(record: Dictionary, unit) -> Vector3:
	var offset: Vector2 = record["slots"].get(unit.get_instance_id(), Vector2.ZERO)
	return record["anchor"] + record["right"] * offset.x - record["forward"] * offset.y


static func _living(members: Array) -> Array:
	return members.filter(func(u): return is_instance_valid(u) and u.is_alive())


static func _distance_to_nearest(members: Array, unit) -> float:
	var best := INF
	for member in members:
		best = minf(best, member.position.distance_to(unit.position))
	return best


# --- fighting as a group ----------------------------------------------------

## A group fights as a group: as soon as one of them sees an enemy within reach, the whole
## block advances on it instead of single soldiers peeling off one by one. Individuals only
## strike what comes into their own reach (Unit.engage_range), so the ranks stay closed
## until the block itself charges.
func _update_engagements() -> void:
	for squad in squads:
		var members := _living(squad["members"])
		if members.is_empty():
			continue
		var record := _march_of(squad)
		# A plain move order from the player is left alone; a charge is re-aimed.
		if not record.is_empty() and not record.get("engage", false):
			continue
		var center := _center(members)
		var enemy := _nearest_enemy(center, squad["team"], members[0].sight)
		if enemy == null:
			continue
		var target := _contact_point(members[0], center, enemy.global_position)
		if not record.is_empty() and record["target"].distance_to(target) < ENGAGE_RETARGET:
			continue  # already charging that spot
		march(members, target, true, squad, true)


## Where the block stops: just inside its own weapon reach, so melee walks into contact and
## archers halt where they can shoot.
static func _contact_point(example, center: Vector3, enemy: Vector3) -> Vector3:
	var direction := Vector3(enemy.x - center.x, 0.0, enemy.z - center.z)
	if direction.length() < 0.5:
		return enemy
	var reach: float = example.attack_range + example.radius
	var stand_off: float = reach * 0.8 if example.ranged else reach + 1.0
	return enemy - direction.normalized() * stand_off


## Nearest living enemy soldier. Buildings are left to the player - a group should not walk
## into a tower on its own.
static func _nearest_enemy(from: Vector3, team: int, range_m: float) -> Unit:
	var best: Unit = null
	var best_distance := range_m
	for unit in Unit.all_units:
		if unit.team == team or not unit.is_alive():
			continue
		var distance := from.distance_to(unit.global_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


func _march_of(squad: Dictionary) -> Dictionary:
	for record in _marches:
		var owner: Dictionary = record["squad"]
		if not owner.is_empty() and owner.get("id", -1) == squad.get("id", -2):
			return record
	return {}


static func _clusters(units: Array) -> Array:
	var result: Array = []
	var visited := {}
	for start in units:
		if visited.has(start):
			continue
		var cluster: Array = []
		var open: Array = [start]
		visited[start] = true
		while not open.is_empty():
			var u = open.pop_back()
			cluster.append(u)
			for other in units:
				if visited.has(other):
					continue
				if u.position.distance_to(other.position) <= LINK_DISTANCE:
					visited[other] = true
					open.append(other)
		result.append(cluster)
	return result


static func _center(members: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in members:
		if is_instance_valid(u) and u.is_alive():
			c += u.global_position
			n += 1
	return c / maxi(n, 1)


func _take_banner() -> Node3D:
	if not _banner_pool.is_empty():
		var pooled: Node3D = _banner_pool.pop_back()
		pooled.visible = true
		return pooled
	var banner := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(Assets.resolve("textures/sfx_ybaseformationflags_t.png"))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flag: Node3D = load(Assets.resolve("models/sfx_ymbaseformationflags_model.glb")).instantiate()
	for mesh: MeshInstance3D in flag.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flag.scale = Vector3.ONE * BANNER_SCALE
	banner.add_child(flag)
	add_child(banner)
	return banner


func _release_banner(banner: Node3D) -> void:
	banner.visible = false
	_banner_pool.append(banner)
