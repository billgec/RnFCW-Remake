extends Control
## Mouse control.
## Left click / drag: select own units (Shift adds), click a banner: select its group,
## click a building: select it. Right click: attack enemy, gather resource (citizens),
## help construct, set rally point (building selected), move (Cmd/Ctrl: attack-move).
## Placement mode (from the HUD): left click places the building, right click/Esc cancels.
## Walls are placed as a chain the way the original builds them: the first click sets where
## the wall starts, every click after it builds the leg up to that point and carries on from
## there, and only right click or Esc ends it.

const WallGrid := preload("res://scripts/wall_grid.gd")
signal selection_changed

@export var own_team := 0

var squads: Node  # squad_manager.gd
var selected_building: Building

var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _marker: MeshInstance3D
var _marker_time := 0.0
var _placing_id := ""
var _ghost: Node3D
var _ghost_valid := false
## Where the leg being laid out starts, null while no wall chain is going.
var _run_from = null
var _run_ghosts: Array[Node3D] = []


@onready var _camera: Camera3D = get_viewport().get_camera_3d()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_marker.call_deferred()


func selected_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in Unit.all_units:
		if unit.selected:
			result.append(unit)
	return result


func clear_selection() -> void:
	for unit in Unit.all_units:
		unit.selected = false
	if selected_building and is_instance_valid(selected_building):
		selected_building.selected = false
	selected_building = null


func begin_placement(building_id: String) -> void:
	cancel_placement()
	var cost: Dictionary = Assets.unit_def(building_id).get("cost", {})
	if not GameState.can_afford(own_team, cost):
		GameState.spend(own_team, cost)  # shows the "not enough" message
		return
	_placing_id = building_id
	_ghost = _spawn_ghost()
	_ghost.rotation_degrees.y = 180.0


func _spawn_ghost() -> Node3D:
	var ghost := Assets.spawn_unit(_placing_id, GameState.team_color(own_team))
	for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 0.45
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ghost)
	return ghost


func cancel_placement() -> void:
	if _ghost:
		_ghost.queue_free()
	for ghost in _run_ghosts:
		ghost.queue_free()
	_run_ghosts.clear()
	_run_from = null
	_ghost = null
	_placing_id = ""


func is_placing() -> bool:
	return _placing_id != ""


func _unhandled_input(event: InputEvent) -> void:
	if is_placing():
		_placement_input(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			_select_same_type_on_screen(event.position, event.shift_pressed)
			_dragging = false
			return
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			_drag_end = event.position
		elif _dragging:
			_dragging = false
			_finish_selection(event.shift_pressed)
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_drag_end = event.position
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_command(event.position, event.meta_pressed or event.ctrl_pressed)


func _placement_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var point = _ground_point(event.position)
		if point == null:
			return
		_ghost.global_position = (point as Vector3).snapped(Vector3(1, 0, 1))
		if "gate" in _placing_id:
			_ghost.rotation.y = _gate_yaw(_ghost.global_position)
		if _run_from != null:
			_show_run(_run_from, _ghost.global_position)
			return
		_ghost_valid = _placement_free(_ghost_footprint(_ghost))
		_tint(_ghost, _ghost_valid)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_placement()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _lays_a_run():
			# First click anchors the chain, every one after it builds the leg up to the
			# cursor and starts the next leg where that one ended.
			_run_from = _ghost.global_position if _run_from == null else _place_run()
			_show_run(_run_from, _run_from)
		elif _ghost_valid:
			Building.clear_for(own_team, _ghost_footprint(_ghost))
			place_building(_placing_id, _ghost.global_position, _ghost.rotation.y)
			if not event.shift_pressed:
				cancel_placement()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placement()


## Which way a gate being set down should face: along the wall line around it. Segments to
## its left and right mean the line runs along X, ones in front and behind mean along Z.
func _gate_yaw(at: Vector3) -> float:
	var spread := Vector2.ZERO
	for b in Building.all_buildings:
		if b.team != own_team or not b.is_wall():
			continue
		var offset := Vector2(b.global_position.x - at.x, b.global_position.z - at.z)
		if offset.length() < WallGrid.TILE * 2.5:
			spread += offset.abs()
	return 0.0 if spread.x >= spread.y else PI * 0.5


## Wall segments are laid out as a chain of legs; gates and ordinary buildings go down singly.
func _lays_a_run() -> bool:
	return _placing_id.begins_with("wall_") and not "gate" in _placing_id


## What the ghost will cover once founded - the same rule Building._ready() uses.
func _ghost_footprint(ghost: Node3D) -> Rect2:
	if _placing_id.begins_with("wall_"):
		var tiles := Vector2i(WallGrid.GATE_TILES, 1) if "gate" in _placing_id else Vector2i.ONE
		return WallGrid.footprint(ghost.global_position, ghost.rotation.y, tiles)
	return Building.compute_footprint(ghost)


## Keeps one ghost per segment of the run under the cursor.
func _show_run(from: Vector3, to: Vector3) -> void:
	var points := WallGrid.run(from, to)
	var yaw := WallGrid.run_yaw(from, to)
	while _run_ghosts.size() < points.size():
		_run_ghosts.append(_spawn_ghost())
	_ghost.visible = false
	for i in _run_ghosts.size():
		var ghost := _run_ghosts[i]
		ghost.visible = i < points.size()
		if not ghost.visible:
			continue
		ghost.global_position = points[i]
		ghost.rotation.y = yaw
		_tint(ghost, _placement_free(_ghost_footprint(ghost)))


## Founds every segment of the leg that fits and returns where it ended, which is where the
## next leg starts. A tile already taken is skipped rather than refused, so legs join at
## their corner and runs can be extended; running out of gold or wood stops the leg.
func _place_run() -> Vector3:
	var points := WallGrid.run(_run_from, _ghost.global_position)
	for ghost in _run_ghosts:
		if not ghost.visible:
			continue
		if not _placement_free(_ghost_footprint(ghost)):
			continue
		if place_building(_placing_id, ghost.global_position, ghost.rotation.y) == null:
			break  # out of gold or wood
	get_tree().current_scene.call("rebuild_navigation")
	return points[points.size() - 1]


static func _tint(node: Node3D, ok: bool) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 0.35 if ok else 0.8


## Pays for and founds a building; selected citizens start constructing it.
func place_building(building_id: String, at: Vector3, yaw: float) -> Building:
	var cost: Dictionary = Assets.unit_def(building_id).get("cost", {})
	if not GameState.spend(own_team, cost):
		return null
	var building := Building.create(building_id, own_team, true)
	building.position = at
	building.rotation.y = yaw
	get_tree().current_scene.add_child(building)
	get_tree().current_scene.call("rebuild_navigation")
	for unit in selected_units():
		if unit.is_worker:
			unit.order_build(building)
	return building


func _placement_free(footprint: Rect2) -> bool:
	# Walls butt up against each other, so instead of clearance they get a hair of slack so
	# touching tiles do not read as overlapping; everything else keeps a metre around it.
	var rect := footprint.grow(-0.05 if _placing_id.begins_with("wall_") else 1.0)
	for b in Building.all_buildings:
		# A gate is dropped straight into a finished run: the own segments it covers make
		# way for it instead of blocking it (Building.clear_for).
		if "gate" in _placing_id and b.team == own_team and b.is_wall() and not b.is_gate():
			continue
		if b.footprint.intersects(rect):
			return false
	for r in ResourceNode.all_nodes:
		if rect.grow(r.radius).has_point(Vector2(r.global_position.x, r.global_position.z)):
			return false
	return true


func _process(delta: float) -> void:
	_update_cursor()
	if _marker and _marker.visible:
		_marker_time += delta
		var s := 1.0 + _marker_time * 1.5
		_marker.scale = Vector3(s, 1.0, s)
		_marker.transparency = clampf(_marker_time / 0.6, 0.0, 1.0)
		if _marker_time > 0.6:
			_marker.visible = false


## Context pointer, using the original game's cursor art.
func _update_cursor() -> void:
	if is_placing():
		Cursors.set_pointer("Build")
		return
	var mouse := get_viewport().get_mouse_position()
	if get_viewport().get_visible_rect().size.y - mouse.y < 178.0:
		Cursors.set_pointer("Normal")  # over the HUD panel
		return
	var units := selected_units()
	var has_worker := units.any(func(u): return u.is_worker)
	var has_soldier := units.any(func(u): return not u.is_worker)
	if _unit_at(mouse, false) != null:
		Cursors.set_pointer("Attack" if has_soldier or has_worker else "Normal")
		return
	var building := _building_at(mouse)
	if building:
		if building.team != own_team:
			Cursors.set_pointer("Attack" if has_soldier or has_worker else "Normal")
		elif has_worker and not building.is_complete():
			Cursors.set_pointer("Build")
		elif has_worker and building.hit_points < building.max_hit_points:
			Cursors.set_pointer("Repair")
		else:
			Cursors.set_pointer("Normal")
		return
	var resource := _resource_at(mouse)
	if resource and has_worker:
		Cursors.set_pointer("Wood" if resource.kind == "wood" else "Mining")
		return
	if selected_building and selected_building.team == own_team and units.is_empty():
		Cursors.set_pointer("RallyPoint")
		return
	Cursors.set_pointer("Normal")


func _draw() -> void:
	if _dragging and _drag_start.distance_to(_drag_end) > 4.0:
		var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
		draw_rect(rect, Color(0.5, 1.0, 0.55, 0.1), true)
		draw_rect(rect, Color(0.6, 1.0, 0.65, 0.9), false, 1.0)


func _finish_selection(additive: bool) -> void:
	_camera = get_viewport().get_camera_3d()
	var picked: Array[Unit] = []
	var building: Building = null
	if _drag_start.distance_to(_drag_end) > 4.0:
		var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
		for unit in Unit.all_units:
			if unit.team != own_team or _camera.is_position_behind(unit.global_position):
				continue
			if rect.has_point(_camera.unproject_position(unit.global_position + Vector3.UP)):
				picked.append(unit)
		# A group is one thing: catching half of it in the box takes all of it.
		picked = _with_whole_squads(picked)
	else:
		var squad: Dictionary = squads.squad_at(_drag_end, _camera) if squads else {}
		if not squad.is_empty() and squad["members"][0].team == own_team:
			for u in squad["members"]:
				picked.append(u)
		else:
			var unit := _unit_at(_drag_end, true)
			if unit:
				# Clicking one member picks the whole group - that is what the banner is for.
				var member_squad: Dictionary = squads.squad_of(unit) if squads else {}
				if member_squad.is_empty():
					picked.append(unit)
				else:
					for u in member_squad["members"]:
						picked.append(u)
			else:
				building = _building_at(_drag_end)
	if not additive or building:
		clear_selection()
	for unit in picked:
		unit.selected = true
	if building:
		building.selected = true
		selected_building = building
	elif picked.size() > 0 and selected_building:
		selected_building.selected = false
		selected_building = null
	_answer(picked)
	selection_changed.emit()


func _command(screen_point: Vector2, attack_move: bool) -> void:
	var units := selected_units()
	var point = _ground_point(screen_point)
	if units.is_empty():
		if selected_building and selected_building.team == own_team and point != null:
			selected_building.rally_point = point
			_show_marker(point)
		return
	var enemy = _unit_at(screen_point, false)
	if enemy == null:
		var b := _building_at(screen_point)
		if b and b.team != own_team:
			enemy = b
		elif b and b.team == own_team and (not b.is_complete() or b.hit_points < b.max_hit_points):
			for u in units:
				if u.is_worker:
					u.order_build(b)
			_show_marker(b.global_position)
			return
	if enemy:
		_show_marker(enemy.global_position)
		Audio.voice("command/attack")
		# Ordered onto an enemy soldier, groups charge as blocks; buildings are walked up to
		# directly, their footprint gives everyone a place to stand anyway.
		if enemy is Unit and squads:
			order_selected_move(enemy.global_position, true, units)
		else:
			for unit in units:
				unit.order_attack(enemy)
		return
	var resource := _resource_at(screen_point)
	if resource:
		var gatherers := 0
		for unit in units:
			if unit.is_worker:
				unit.order_gather(resource)
				gatherers += 1
		if gatherers == units.size():
			_show_marker(resource.global_position)
			return
		units = units.filter(func(u): return not u.is_worker)
	if point != null:
		Audio.voice("command/charge" if attack_move else ("command/move" if units.size() > 1 else "command/move_one"))
		order_selected_move(point, attack_move, units)


## The men answer when they are picked: one of them in his own voice, a whole group with
## the group's call.
func _answer(units: Array) -> void:
	if units.is_empty():
		return
	if units.size() > 1 and squads and not squads.squad_of(units[0]).is_empty():
		Audio.group_select()
	else:
		Audio.select(units[0])


## Completes a selection: every group that any of these units belongs to comes along whole.
func _with_whole_squads(units: Array[Unit]) -> Array[Unit]:
	if squads == null:
		return units
	var result: Array[Unit] = []
	var seen := {}
	for unit in units:
		var squad: Dictionary = squads.squad_of(unit)
		var members: Array = squad["members"] if not squad.is_empty() else [unit]
		for member in members:
			if is_instance_valid(member) and member.is_alive() and not seen.has(member.get_instance_id()):
				seen[member.get_instance_id()] = true
				result.append(member)
	return result


## Double click: every own unit of that type currently on screen, like the original.
func _select_same_type_on_screen(screen_point: Vector2, additive: bool) -> void:
	var clicked := _unit_at(screen_point, true)
	if clicked == null:
		return
	if not additive:
		clear_selection()
	var view := get_viewport().get_visible_rect().grow(-4)
	var picked: Array[Unit] = []
	for unit in Unit.all_units:
		if unit.team != own_team or unit.definition_id != clicked.definition_id:
			continue
		if _camera.is_position_behind(unit.global_position):
			continue
		if view.has_point(_camera.unproject_position(unit.global_position + Vector3.UP)):
			picked.append(unit)
	var chosen := _with_whole_squads(picked)
	for unit in chosen:
		unit.selected = true
	_answer(chosen)
	selection_changed.emit()


## Closest living unit under the cursor; own units if [param own] is true, enemies otherwise.
func _unit_at(screen_point: Vector2, own: bool) -> Unit:
	_camera = get_viewport().get_camera_3d()
	var best: Unit = null
	var best_distance := 30.0
	for unit in Unit.all_units:
		if (unit.team == own_team) != own or _camera.is_position_behind(unit.global_position):
			continue
		var d := _camera.unproject_position(unit.global_position + Vector3.UP).distance_to(screen_point)
		if d < best_distance:
			best_distance = d
			best = unit
	return best


func _building_at(screen_point: Vector2) -> Building:
	var point = _ground_point(screen_point)
	if point == null:
		return null
	for b in Building.all_buildings:
		if b.footprint.grow(0.5).has_point(Vector2(point.x, point.z)):
			return b
	return null


func _resource_at(screen_point: Vector2) -> ResourceNode:
	var point = _ground_point(screen_point)
	if point == null:
		return null
	var best: ResourceNode = null
	var best_distance := 2.5
	for r in ResourceNode.all_nodes:
		var d := Vector2(point.x, point.z).distance_to(Vector2(r.global_position.x, r.global_position.z)) - r.radius
		if d < best_distance:
			best_distance = d
			best = r
	return best


func _ground_point(screen: Vector2):
	_camera = get_viewport().get_camera_3d()
	var origin := _camera.project_ray_origin(screen)
	var direction := _camera.project_ray_normal(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


## Move order: everything that is selected marches as a block - every group as itself, the
## rest gathered into one block per unit type. Several blocks are placed side by side
## instead of being sent onto the same spot.
func order_selected_move(point: Vector3, attack_move := false, units: Array = []) -> void:
	if units.is_empty():
		units = selected_units()
	if units.is_empty():
		return
	_show_marker(point)
	if squads == null:
		Formation.move(units, point, attack_move)
		return
	var blocks: Array = []  # {members, squad}
	var by_squad := {}
	var by_type := {}
	var center := Vector3.ZERO
	for unit in units:
		center += unit.position
		var squad: Dictionary = squads.squad_of(unit)
		if squad.is_empty():
			if not by_type.has(unit.definition_id):
				by_type[unit.definition_id] = []
				blocks.append({"members": by_type[unit.definition_id], "squad": {}})
			by_type[unit.definition_id].append(unit)
		elif not by_squad.has(squad["id"]):
			by_squad[squad["id"]] = true
			blocks.append({"members": squad["members"], "squad": squad})
	center /= units.size()
	blocks.sort_custom(func(a, b): return Formation.type_order(a["members"][0]) < Formation.type_order(b["members"][0]))
	var widths: Array = []
	for block in blocks:
		# A group's roster is only cleaned up twice a second, so count the living.
		var members: Array = block["members"].filter(func(u): return is_instance_valid(u) and u.is_alive())
		widths.append(Formation.block_width(members.size(), Formation.spacing_for(members[0])) if not members.is_empty() else 0.0)
	var targets := Formation.spread(point, center, widths)
	for i in blocks.size():
		squads.march(blocks[i]["members"], targets[i], attack_move, blocks[i]["squad"], attack_move)


func _build_marker() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.62
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.45, 1.0, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = material
	_marker = MeshInstance3D.new()
	_marker.mesh = torus
	_marker.visible = false
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(_marker)


func _show_marker(point: Vector3) -> void:
	_marker.global_position = point + Vector3.UP * 0.05
	_marker_time = 0.0
	_marker.visible = true
