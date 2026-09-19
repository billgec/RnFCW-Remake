extends Node3D
## Skirmish sandbox: two Greek bases (you in blue, the computer in red) with gold mines,
## forests, citizens and a starting army.
##
## Command-line options (after `--`), mainly for automated checks:
##   --snapshot=<png>        render, save a screenshot and quit
##   --frames=<n>            frames to wait before the snapshot (default 90)
##   --cam=<x>,<z>,<yaw°>,<distance>,<pitch°>   initial camera placement
##   --demo-move=<x>,<z>     select the blue soldiers and attack-move there
##   --demo-select=<what>    army | workers | barracks | towncenter | heromode | halfbox | squads | rally | engage | minimap | tower
##   --hero-action=<what>    with --demo-select=heromode: run | attack | special | duel
##   --show-health=1         always show hit point bars
##   --perf=<seconds>        log the frame budget every few seconds
##   --timescale=<f>         speed up the simulation (e.g. to watch the computer player)

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const SelectionController := preload("res://scripts/selection_controller.gd")
const SquadManager := preload("res://scripts/squad_manager.gd")
const Hud := preload("res://scripts/hud.gd")
const Minimap := preload("res://scripts/minimap.gd")
const EnemyAI := preload("res://scripts/enemy_ai.gd")
const HealthBar := preload("res://scripts/health_bar.gd")

const BLUE := Color(0.15, 0.35, 0.9)
const RED := Color(0.85, 0.12, 0.1)
const SETTLEMENT := "bld_ygmptentsettlement"
const TOWER := "bld_ym1x1tower_00"
const TOWN_CENTER := "bld_ygmptowncenter"
const BARRACKS := "bld_ygmpbarracks_02"
const STABLE := "bld_ygmpstable"
const MAP_HALF := 150.0

var _args := {}
var _region: NavigationRegion3D
var _navmesh: NavigationMesh
var _rebake_pending := false
var _selection: Control

@onready var camera_rig: Node3D = $CameraRig


func _ready() -> void:
	_parse_args()
	GameState.set_speed(float(_args.get("timescale", "1")))
	HealthBar.force_visible = _args.has("show-health")
	GameState.setup_players([
		{"team": 0, "name": "Du", "color": BLUE, "gold": 250, "wood": 450, "glory": 40},
		{"team": 1, "name": "Computer", "color": RED, "gold": 250, "wood": 450, "glory": 40},
	])
	_build_environment()
	_build_ground()
	_build_base(0, Vector3(0, 0, 58), 180.0)
	_build_base(1, Vector3(0, 0, -58), 0.0)
	_spawn_gold(Vector3(0, 0, 0))
	_region = NavigationRegion3D.new()
	add_child(_region)
	rebuild_navigation(true)

	var squads := SquadManager.new()
	squads.name = "Squads"
	add_child(squads)
	var ui := CanvasLayer.new()
	_selection = SelectionController.new()
	_selection.name = "Selection"
	_selection.squads = squads
	ui.add_child(_selection)
	add_child(ui)
	var hero_mode := HeroMode.new()
	hero_mode.name = "HeroMode"
	hero_mode.camera_rig = camera_rig
	hero_mode.selection = _selection
	add_child(hero_mode)
	var hud := Hud.new()
	hud.selection = _selection
	hud.hero_mode = hero_mode
	hud.camera_rig = camera_rig
	add_child(hud)
	var ai := EnemyAI.new()
	add_child(ai)
	GameState.match_over.connect(func(_w): GameState.set_speed(1.0))
	if _args.has("log"):
		_log_loop()
	if _args.has("perf"):
		_perf_loop()
	if _args.has("snapshot"):
		GameState.message.connect(func(t): print("[%.0fs] %s" % [Time.get_ticks_msec() / 1000.0 * Engine.time_scale, t]))

	camera_rig.position = Vector3(0, 0, 40)
	if _args.has("cam"):
		var c: PackedStringArray = _args["cam"].split(",")
		camera_rig.position = Vector3(c[0].to_float(), 0, c[1].to_float())
		camera_rig._yaw = deg_to_rad(c[2].to_float())
		camera_rig.distance = c[3].to_float()
		camera_rig._target_distance = camera_rig.distance
		camera_rig.pitch_degrees = c[4].to_float()
	if _args.has("demo-move"):
		_demo_move.call_deferred()
	if _args.has("demo-select"):
		_demo_select.call_deferred()
	if _args.has("snapshot"):
		camera_rig.edge_pan_enabled = false
		_take_snapshot.call_deferred()
	GameState.message.emit("Rise & Fall – Gefecht gegen den Computer")


# --- scenario ---------------------------------------------------------------

func _build_base(team: int, origin: Vector3, yaw: float) -> void:
	var facing := 1.0 if yaw == 0.0 else -1.0  # +1: base faces +Z
	var color := GameState.team_color(team)
	_place_building(TOWN_CENTER, team, origin, yaw)
	_place_building(BARRACKS, team, origin + Vector3(26 * facing, 0, 6 * facing), yaw)
	_place_building(SETTLEMENT, team, origin + Vector3(-30 * facing, 0, 22 * facing), yaw)
	_place_building(TOWER, team, origin + Vector3(12 * facing, 0, -16 * facing), yaw)
	if team == 1:
		_place_building(STABLE, team, origin + Vector3(-26 * facing, 0, 8 * facing), yaw)
	_spawn_gold(origin + Vector3(-24 * facing, 0, -16 * facing))
	_spawn_forest(origin + Vector3(40 * facing, 0, -22 * facing), 12.0, 30)
	_spawn_forest(origin + Vector3(-48 * facing, 0, 14 * facing), 10.0, 22)

	var front := origin + Vector3(0, 0, 22 * facing)
	for i in 6:
		var worker := Unit.create("men_ymworker_02", team, color)
		worker.position = origin + Vector3(-6 + i * 2.2, 0, 13 * facing)
		add_child(worker)
	var army := [["men_yminfantry_l1_02", 9], ["men_ymspear_l1_02", 9], ["men_ymarcher_02", 6]]
	var column := -12.0
	for entry in army:
		for i in entry[1]:
			var unit := Unit.create(entry[0], team, color)
			unit.position = front + Vector3(column + (i % 3) * 1.6, 0, (i / 3) * 1.6 * facing)
			unit.rotation_degrees.y = yaw + 180.0
			add_child(unit)
		column += 9.0
	var hero := Unit.create("men_ymalexandermelee_02", team, color)
	if true:
		hero.position = front + Vector3(0, 0, -3 * facing)
		hero.rotation_degrees.y = yaw + 180.0
		add_child(hero)


func _place_building(id: String, team: int, at: Vector3, yaw: float) -> Building:
	var building := Building.create(id, team)
	building.position = at
	building.rotation_degrees.y = yaw
	add_child(building)
	return building


func _spawn_gold(at: Vector3) -> void:
	var mine := ResourceNode.gold_mine(6000)
	mine.position = at
	add_child(mine)


func _spawn_forest(center: Vector3, spread: float, count: int) -> void:
	var placed: Array[Vector3] = []
	var attempts := 0
	while placed.size() < count and attempts < count * 20:
		attempts += 1
		var p := center + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread) * 0.7)
		if placed.any(func(q): return q.distance_to(p) < 2.4):
			continue
		placed.append(p)
		var tree := ResourceNode.tree(150)
		tree.position = p
		add_child(tree)


## Re-bakes the navmesh with every building footprint and gold mine cut out.
func rebuild_navigation(immediate := false) -> void:
	if _rebake_pending:
		return
	const CELL := 0.3
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL)
	_navmesh = NavigationMesh.new()
	_navmesh.cell_size = CELL
	_navmesh.cell_height = 0.25
	_navmesh.agent_radius = 0.6
	_navmesh.agent_height = 2.0
	_navmesh.agent_max_climb = 0.25
	_navmesh.filter_baking_aabb = AABB(Vector3(-MAP_HALF, -1, -MAP_HALF), Vector3(MAP_HALF * 2, 3, MAP_HALF * 2))
	var source := NavigationMeshSourceGeometryData3D.new()
	var h := MAP_HALF
	source.add_faces(PackedVector3Array([
		Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h),
		Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]), Transform3D.IDENTITY)
	for building in Building.all_buildings:
		_add_obstruction(source, building.footprint)
	for node in ResourceNode.all_nodes:
		if node.kind == "gold":
			var p := Vector2(node.global_position.x, node.global_position.z)
			_add_obstruction(source, Rect2(p - Vector2.ONE * node.radius * 0.8, Vector2.ONE * node.radius * 1.6))
	if immediate:
		NavigationServer3D.bake_from_source_geometry_data(_navmesh, source)
		_region.navigation_mesh = _navmesh
	else:
		_rebake_pending = true
		NavigationServer3D.bake_from_source_geometry_data_async(_navmesh, source, func():
			_region.navigation_mesh = _navmesh
			_rebake_pending = false)


static func _add_obstruction(source: NavigationMeshSourceGeometryData3D, box: Rect2) -> void:
	source.add_projected_obstruction(PackedVector3Array([
		Vector3(box.position.x, 0, box.position.y), Vector3(box.end.x, 0, box.position.y),
		Vector3(box.end.x, 0, box.end.y), Vector3(box.position.x, 0, box.end.y)]), -0.5, 4.0, true)


# --- automated checks -------------------------------------------------------

func _demo_move() -> void:
	await get_tree().create_timer(0.3).timeout
	for unit in Unit.all_units:
		unit.selected = unit.team == 0 and not unit.is_worker
	var c: PackedStringArray = _args["demo-move"].split(",")
	_selection.order_selected_move(Vector3(c[0].to_float(), 0, c[1].to_float()), true)


func _demo_select() -> void:
	await get_tree().create_timer(0.3).timeout
	match _args["demo-select"]:
		"army":
			for unit in Unit.all_units:
				unit.selected = unit.team == 0 and not unit.is_worker
		"workers":
			var gold := ResourceNode.nearest(Vector3(0, 0, 58), "gold")
			var i := 0
			for unit in Unit.all_units:
				if unit.team == 0 and unit.is_worker:
					unit.selected = true
					if i < 3:
						unit.order_gather(gold)
					else:
						unit.order_gather(ResourceNode.nearest(unit.position, "wood"))
					i += 1
		"build":
			var workers := Unit.all_units.filter(func(u): return u.team == 0 and u.is_worker)
			for w in workers:
				w.selected = true
			GameState.player(0)["wood"] += 400
			_selection.place_building(STABLE, Vector3(-30, 0, 30), PI)
		"member":
			# Simulated click on a single soldier: the whole group must end up selected.
			await get_tree().create_timer(1.2).timeout
			var squads: Node = get_node("Squads")
			var camera := get_viewport().get_camera_3d()
			for unit in Unit.all_units:
				if unit.team != 0 or squads.squad_of(unit).is_empty():
					continue
				var point := camera.unproject_position(unit.global_position + Vector3.UP)
				_selection._drag_start = point
				_selection._drag_end = point
				_selection._finish_selection(false)
				print("clicked %s -> %d selected (group has %d)" % [unit.display_name,
					_selection.selected_units().size(), squads.squad_of(unit)["members"].size()])
				break
		"rally":
			# Freshly trained soldiers gathering at a rally point must form a group of their own.
			await get_tree().create_timer(0.5).timeout
			for b in Building.all_buildings:
				if b.team != 0 or b.definition_id != BARRACKS:
					continue
				b.rally_point = b.global_position + Vector3(0, 0, 16)
				GameState.player(0)["gold"] += 3000
				GameState.player(0)["wood"] += 3000
				for i in 5:
					b.enqueue(b.trains[0]["unit"])
				var squads_node: Node = get_node("Squads")
				for step in 12:
					await get_tree().create_timer(15.0).timeout
					var fresh := []
					for squad in squads_node.squads:
						if squad["team"] == 0:
							fresh.append("%d x %s" % [squad["members"].size(), squad["type"]])
					print("[t=%3ds] team0 groups: %s" % [(step + 1) * 15, ", ".join(fresh)])
				break
		"engage":
			# March one group towards the enemy, then watch how it attacks: it should close
			# in as a block (small spread), not trickle in one by one.
			await get_tree().create_timer(1.2).timeout
			var squads_node: Node = get_node("Squads")
			var group := {}
			for squad in squads_node.squads:
				if squad["team"] == 0 and squad["members"][0].ranged == false:
					group = squad
					break
			if group.is_empty():
				return
			for unit in group["members"]:
				unit.selected = true
			_selection.order_selected_move(Vector3(0, 0, -28))
			for step in 24:
				await get_tree().create_timer(3.0).timeout
				var members: Array = group["members"].filter(func(u): return is_instance_valid(u) and u.is_alive())
				if members.is_empty():
					break
				var center := Vector3.ZERO
				for u in members:
					center += u.position
				center /= members.size()
				var spread := 0.0
				var states := {}
				for u in members:
					spread = maxf(spread, u.position.distance_to(center))
					var name: String = Unit.State.keys()[u.state]
					states[name] = states.get(name, 0) + 1
				var nearest := 999.0
				for u in Unit.all_units:
					if u.team == 1 and u.is_alive():
						nearest = minf(nearest, center.distance_to(u.position))
				print("[t=%3ds] %d left, spread %.1f m, nearest enemy %.0f m, %s" % [
					(step + 1) * 3, members.size(), spread, nearest, states])
		"minimap":
			await get_tree().create_timer(0.8).timeout
			var map: Control = get_tree().root.find_child("Minimap", true, false)
			for spot in [Vector2(0.5, 0.5), Vector2(0.85, 0.5), Vector2(0.5, 0.85)]:
				var local: Vector2 = spot * map.size
				var world: Vector3 = map._world_at(local)
				map._look_at_point(local)
				print("minimap %.2f/%.2f -> world %.0f,%.0f  camera %.0f,%.0f" % [spot.x, spot.y,
					world.x, world.z, camera_rig.position.x, camera_rig.position.z])
		"tower":
			await get_tree().create_timer(0.8).timeout
			for b in Building.all_buildings:
				if b.team != 0 or b.definition_id != TOWER:
					continue
				b.selected = true
				_selection.selected_building = b
				print("tower: %d defenders, upgrades to %s" % [b._defenders.size(),
					b.available_becomes().map(func(e): return "%s %s" % [e["name"], e["cost"]])])
				GameState.player(0)["gold"] += 500
				GameState.player(0)["wood"] += 500
				b.enqueue_become(b.available_becomes()[0])
				await get_tree().create_timer(float(b.queue[0]["time"]) + 1.0).timeout
				for other in Building.all_buildings:
					if other.team == 0 and "tower" in other.definition_id:
						print("after: %s, %d hp, %d defenders, range %.0f m, damage %.0f" % [
							other.definition_id, other.hit_points, other._defenders.size(),
							other.attack_range, other.damage])
				break
		"halfbox":
			# Drag a box over only the front half of a group: all of it must end up selected.
			await get_tree().create_timer(1.2).timeout
			var squads_node: Node = get_node("Squads")
			var camera := get_viewport().get_camera_3d()
			for squad in squads_node.squads:
				if squad["team"] != 0:
					continue
				var members: Array = squad["members"]
				var half: Array = members.slice(0, members.size() / 2)
				var rect := Rect2(camera.unproject_position(half[0].global_position + Vector3.UP), Vector2.ZERO)
				for unit in half:
					rect = rect.expand(camera.unproject_position(unit.global_position + Vector3.UP))
				_selection._drag_start = rect.position - Vector2(6, 6)
				_selection._drag_end = rect.end + Vector2(6, 6)
				_selection._finish_selection(false)
				print("box over %d of %d %s -> %d selected" % [half.size(), members.size(),
					members[0].display_name, _selection.selected_units().size()])
				break
		"squads":
			await get_tree().create_timer(1.2).timeout
			var node: Node = get_node("Squads")
			for squad in node.squads:
				print("group: %d x %s (team %d)" % [squad["members"].size(), squad["type"], squad["team"]])
		"doubleclick":
			await get_tree().create_timer(1.0).timeout
			var camera := get_viewport().get_camera_3d()
			for unit in Unit.all_units:
				if unit.team != 0 or unit.is_worker:
					continue
				_selection._select_same_type_on_screen(camera.unproject_position(unit.global_position + Vector3.UP), false)
				var total := 0
				for u in Unit.all_units:
					if u.team == 0 and u.definition_id == unit.definition_id:
						total += 1
				print("double click %s -> %d selected (%d of this type alive)" % [unit.display_name,
					_selection.selected_units().size(), total])
				break
		"hero":
			await get_tree().create_timer(0.5).timeout
			GameState.add_resource(0, "glory", 80)
			for unit in Unit.all_units:
				if unit.team == 0 and unit.is_hero:
					_selection.clear_selection()
					unit.selected = true
					_selection.selection_changed.emit()
					break
		"heromode":
			await get_tree().create_timer(0.6).timeout
			var mode: Node = get_node("HeroMode")
			mode.enter()
			match _args.get("hero-action", ""):
				"run":
					Input.action_press("cam_forward")
				"attack":
					mode._attack()
				"special":
					mode._special()
				"duel":
					await _hero_duel(mode)
			print("hero mode active: %s, retinue %d" % [mode.active, mode.retinue_size()])
		"builds":
			await get_tree().create_timer(0.5).timeout
			for unit in Unit.all_units:
				if unit.team == 0 and unit.is_worker:
					_selection.clear_selection()
					unit.selected = true
					_selection.selection_changed.emit()
					break
		"research":
			await get_tree().create_timer(0.5).timeout
			for b in Building.all_buildings:
				if b.team != 0 or b.definition_id != BARRACKS:
					continue
				b.selected = true
				_selection.selected_building = b
				print("upgrades at hero level 1: %d" % b.available_upgrades().size())
				GameState.add_resource(0, "glory", 200)
				GameState.set_hero_level(0, 2)
				var before := b.available_trains().map(func(e): return e["name"])
				print("upgrades at hero level 2: %s" % [b.available_upgrades().map(func(e): return e["name"])])
				var upgrade: Dictionary = b.available_upgrades()[0]
				print("researching %s (cost %s)" % [upgrade["name"], upgrade["cost"]])
				b.enqueue_research(upgrade)
				await GameState.research_completed
				print("before: %s" % [before])
				print("after:  %s" % [b.available_trains().map(func(e): return e["name"])])
				var levels := {}
				for u in Unit.all_units:
					if u.team == 0 and u.line == "sword infantry (greek)":
						levels[u.display_name] = levels.get(u.display_name, 0) + 1
				print("field:  %s" % [levels])
				print("upgrades now: %s" % [b.available_upgrades().map(func(e): return e["name"])])
				break
		"barracks", "towncenter":
			var id := BARRACKS if _args["demo-select"] == "barracks" else TOWN_CENTER
			for b in Building.all_buildings:
				if b.team == 0 and b.definition_id == id:
					b.selected = true
					_selection.selected_building = b
					b.rally_point = b.global_position + Vector3(0, 0, -14)
					b.enqueue(b.trains[0]["unit"])
					b.enqueue(b.trains[1]["unit"])
					break
	_selection.selection_changed.emit()


## Headless check of the hero's own attacks: put him in front of an enemy block, swing, then
## set off the special attack and count who took damage.
func _hero_duel(mode: Node) -> void:
	var enemies: Array[Unit] = []
	for u in Unit.all_units:
		if u.team == 1 and not u.is_worker and not u.is_hero:
			enemies.append(u)
	if enemies.is_empty():
		return
	var victim := enemies[0]
	mode._hero.position = victim.position + Vector3(0, 0, 3.0)
	camera_rig._yaw = 0.0  # look towards -Z, where the enemy stands
	await get_tree().create_timer(0.4).timeout
	var before := victim.hit_points
	mode._attack()
	await get_tree().create_timer(0.6).timeout
	print("swing: %s %.0f -> %.0f hp (damage %.0f)" % [victim.display_name, before, victim.hit_points, before - victim.hit_points])
	var hp := {}
	for u in enemies:
		hp[u] = u.hit_points
	mode._special()
	await get_tree().create_timer(3.0).timeout
	var hit := 0
	var total := 0.0
	for u in enemies:
		if u.hit_points < hp[u]:
			hit += 1
			total += hp[u] - u.hit_points
	print("special: %d enemies hit for %.0f damage in total" % [hit, total])


## Frame budget, every few seconds: where the time goes and how much of it is the GPU.
func _perf_loop() -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var interval := maxf(float(_args["perf"]), 1.0)
	while true:
		await get_tree().create_timer(interval).timeout
		var units := Unit.all_units.size()
		print("[perf] %5.1f fps | script %.2f ms | physics %.2f ms | render cpu %.2f ms gpu %.2f ms | %d draw calls | %d units %d nodes" % [
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(viewport),
			RenderingServer.viewport_get_measured_render_time_gpu(viewport),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			units, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


func _log_loop() -> void:
	var game_time := 0.0
	while true:
		await get_tree().create_timer(30.0).timeout
		game_time += 30.0
		var line := "[t=%3ds]" % game_time
		for team in 2:
			var soldiers := Unit.all_units.filter(func(u): return u.team == team and not u.is_worker).size()
			var workers := Unit.all_units.filter(func(u): return u.team == team and u.is_worker).size()
			var states := {}
			for u in Unit.all_units:
				if u.team == team:
					var s: String = Unit.State.keys()[u.state]
					states[s] = states.get(s, 0) + 1
			var p := GameState.player(team)
			var groups := 0
			var grouped := 0
			for squad in (get_node("Squads").squads if has_node("Squads") else []):
				if squad["team"] == team:
					groups += 1
					grouped += squad["members"].size()
			line += "  team%d: %d soldiers (%d in %d groups) %d workers gold %d wood %d glory %d hero %d research %d %s" % [team,
				soldiers, grouped, groups, workers, p["gold"], p["wood"], p.get("glory", 0),
				GameState.hero_level(team), GameState.research_count(team), states]
		print(line)


## Game speed hotkeys: space pauses/resumes, +/- step through the speeds.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	const STEPS := [0.0, 0.5, 1.0, 2.0, 3.0]
	match event.keycode:
		KEY_SPACE:
			GameState.set_speed(0.0 if GameState.speed > 0.0 else 1.0)
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			var i := STEPS.find(GameState.speed)
			GameState.set_speed(STEPS[clampi(i + 1, 0, STEPS.size() - 1)] if i >= 0 else 2.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			var i := STEPS.find(GameState.speed)
			GameState.set_speed(STEPS[clampi(i - 1, 0, STEPS.size() - 1)] if i >= 0 else 0.5)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]


func _take_snapshot() -> void:
	for i in int(_args.get("frames", "90")):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(_args["snapshot"])
	print("snapshot saved: ", _args["snapshot"])
	get_tree().quit()


# --- world ------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_material.sky_horizon_color = Color(0.74, 0.8, 0.86)
	sky_material.ground_horizon_color = Color(0.62, 0.62, 0.58)
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.85)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	Graphics.use(env)  # ambient occlusion, indirect light, glow and anti aliasing per level

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_blur = 1.2
	add_child(sun)


func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true

	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("albedo_tex", load(Assets.resolve("textures/trn_ybasegrasst.png")))
	material.set_shader_parameter("variation_tex", load(Assets.resolve("textures/trn_ybasegrassdirtt.png")))
	material.set_shader_parameter("noise_tex", noise_tex)

	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_HALF * 2.6, MAP_HALF * 2.6)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = material
	ground.name = "Ground"
	ground.layers = 1 | (1 << (Minimap.TERRAIN_LAYER - 1))  # also seen by the minimap camera
	add_child(ground)
