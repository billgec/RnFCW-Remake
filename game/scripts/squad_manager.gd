extends Node3D
## Groups (the original's formation banners): at least MIN_SIZE soldiers of the same type
## and team standing together form a persistent group marked by the original banner above
## its centre. A group stays together once formed - clicking any member, or the banner,
## selects the whole group, and single units of the same type join a group they walk into.

const MIN_SIZE := 9
const MAX_SIZE := 20
const LINK_DISTANCE := 4.5
const JOIN_DISTANCE := 7.0
const DISSOLVE_BELOW := 4
const BANNER_HEIGHT := 5.6
const BANNER_SCALE := 0.62

var squads: Array[Dictionary] = []  # {members: Array, banner: Node3D, team: int, type: String}

var _timer := 0.0
var _squad_of := {}  # unit instance id -> squad dictionary
var _banner_pool: Array[Node3D] = []


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_update_membership()
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
		var center := _center(squad["members"])
		for unit in loose[key].duplicate():
			if squad["members"].size() >= MAX_SIZE:
				break
			if unit.position.distance_to(center) <= JOIN_DISTANCE:
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
					"members": members, "banner": banner,
					"team": members[0].team, "type": members[0].definition_id,
				}
				squads.append(squad)
				for u in members:
					_squad_of[u.get_instance_id()] = squad


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
