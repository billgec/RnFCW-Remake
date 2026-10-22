extends Node
## The rules a soldier goes by: the values he is built from, what his blow is worth against
## a given enemy, how far he looks for one, what he does when he is hit, which target he
## picks, and what an order does to him. All of it settles the moment it is asked, so no
## time has to pass - this runs as a scene for the autoloads, but builds no skirmish.
##
##   godot --headless --path game res://tests/test_units.tscn
##
## Everything that only plays out over time - gathering, building, a fight being decided,
## a block marching - is left to the `--demo-select=` runs listed in main.gd.

const Check := preload("res://tests/check.gd")

const SWORD := "men_yminfantry_l1_02"      # Human Sword, 420 hp, 20 damage
const SWORD_VETERAN := "men_yminfantry_l2_02"
const SPEAR := "men_ymspear_l1_02"         # Human Spear, 410 hp, 35 damage
const ARCHER := "men_ymarcher_02"          # Human Archer, ranged
const LANCER := "cav_ymspear_l1"           # Lancer, the horse the spear is for
const WORKER := "men_ymworker_02"          # Citizen
const WALL := "wall_ymstraight_02"
const GATE := "wall_ymgateleft_00"

var _check := Check.new()


func _ready() -> void:
	GameState.setup_players([
		{"team": 0, "name": "Blau", "color": Color.BLUE, "gold": 1000, "wood": 1000, "glory": 100},
		{"team": 1, "name": "Rot", "color": Color.RED, "gold": 1000, "wood": 1000, "glory": 100},
	])
	await _a_soldier_is_built_from_the_original_values()
	await _a_blow_is_worth_more_against_the_right_enemy()
	await _a_blow_against_a_building_is_its_own_matter()
	await _how_far_a_soldier_looks_for_a_fight()
	await _a_wound_is_taken_off_and_answered()
	await _a_shield_takes_some_of_it()
	await _a_dead_man_takes_no_more()
	await _the_nearest_corner_of_a_building()
	await _who_a_soldier_goes_for()
	await _a_shut_gate_stands_in_the_way()
	await _an_order_takes_hold_at_once()
	await _a_veteran_steps_into_his_place()
	_an_animation_is_picked_by_name()
	get_tree().quit(_check.report("units"))


func _raise(id: String, team: int, at := Vector3.ZERO) -> Unit:
	var unit := Unit.create(id, team, GameState.team_color(team))
	unit.position = at
	add_child(unit)
	return unit


func _wall(id: String, team: int, at: Vector3, yaw := 0.0) -> Building:
	var building := Building.create(id, team)
	building.position = at
	building.rotation.y = yaw
	add_child(building)
	return building


## Clears the board between cases - Unit and Building keep their lists statically.
func _clear() -> void:
	for unit in Unit.all_units.duplicate():
		Unit.all_units.erase(unit)
		unit.queue_free()
	for building in Building.all_buildings.duplicate():
		Building.all_buildings.erase(building)
		building.queue_free()
	Building.all_gates.clear()
	await get_tree().process_frame


## The numbers are the original's, read out of dbobjects by the converter.
func _a_soldier_is_built_from_the_original_values() -> void:
	var sword := _raise(SWORD, 0)
	var spear := _raise(SPEAR, 0, Vector3(5, 0, 0))
	var archer := _raise(ARCHER, 0, Vector3(10, 0, 0))
	var worker := _raise(WORKER, 0, Vector3(15, 0, 0))

	_check.near(sword.max_hit_points, 420.0, "a swordsman has the original's hit points", 1.0)
	_check.near(sword.damage, 20.0, "and the original's damage", 0.5)
	_check.same(sword.family, "Human Sword", "and the original's family, which the bonuses go by")
	_check.near(sword.hit_points, sword.max_hit_points, "a fresh soldier is unhurt")
	_check.ok(sword.is_alive(), "and alive")
	_check.ok(sword in Unit.all_units, "and on the roll, where everyone else looks for him")

	_check.ok(spear.damage > sword.damage, "a spear hits harder than a sword")
	_check.ok(sword.move_speed > spear.move_speed, "a swordsman is the quicker of the two")
	_check.ok(archer.ranged, "an archer shoots")
	_check.ok(not sword.ranged, "a swordsman does not")
	_check.ok(archer.attack_range > sword.attack_range * 5.0, "an archer reaches far further than a sword")
	_check.ok(worker.is_worker, "a citizen counts as a worker")
	_check.ok(not sword.is_worker, "a soldier does not")
	await _clear()


## Spears beat horses, swords beat spears - the table in data/bonuses.json, and it is not
## the same both ways round.
func _a_blow_is_worth_more_against_the_right_enemy() -> void:
	var spear := _raise(SPEAR, 0)
	var sword := _raise(SWORD, 0, Vector3(5, 0, 0))
	var archer := _raise(ARCHER, 0, Vector3(10, 0, 0))
	var lancer := _raise(LANCER, 1, Vector3(15, 0, 0))
	var other_sword := _raise(SWORD, 1, Vector3(20, 0, 0))

	_check.near(spear.damage_against(lancer), spear.damage * 2.0, "a spear is worth double against a horse")
	_check.near(sword.damage_against(spear), sword.damage * 1.35, "a sword has the better of a spear")
	_check.near(lancer.damage_against(spear), lancer.damage * 0.5, "a horse fares badly against a spear")
	_check.ok(spear.damage_against(lancer) > spear.damage_against(other_sword),
		"a spearman would rather meet the horse than the swordsman")
	_check.near(archer.damage_against(lancer), archer.damage * 0.6, "arrows do little against a rider")
	# A pairing the table says nothing about is worth a plain blow.
	_check.near(sword.damage_against(other_sword), sword.damage, "sword against sword is worth its own damage")
	await _clear()


## Against walls and houses it is a different table, and most soldiers are poor at it.
func _a_blow_against_a_building_is_its_own_matter() -> void:
	var sword := _raise(SWORD, 0)
	var archer := _raise(ARCHER, 0, Vector3(5, 0, 0))
	var wall := _wall(WALL, 1, Vector3(40, 0, 0))

	_check.near(sword.damage_against(wall), sword.damage * 0.4, "a sword does little to a wall")
	_check.near(archer.damage_against(wall), archer.damage * 0.25, "arrows do less still")
	_check.ok(sword.damage_against(wall) < sword.damage, "hacking at stone is worse than at a man")
	await _clear()


## On his own a soldier answers anything he can see; in a block he only strikes what comes
## within his own reach, because the block decides for all of them together.
func _how_far_a_soldier_looks_for_a_fight() -> void:
	var sword := _raise(SWORD, 0)
	var archer := _raise(ARCHER, 0, Vector3(5, 0, 0))

	sword.holds_formation = false
	_check.near(sword.engage_range(), sword.sight, "alone, a soldier answers anything in sight")
	sword.holds_formation = true
	_check.ok(sword.engage_range() < sword.sight * 0.5, "in a block he waits for what comes to him")
	_check.ok(sword.engage_range() >= 3.0, "but always far enough to reach the man in front")

	archer.holds_formation = true
	_check.near(archer.engage_range(), archer.attack_range + archer.radius,
		"an archer in a block shoots as far as he can shoot")
	await _clear()


func _a_wound_is_taken_off_and_answered() -> void:
	var defender := _raise(SWORD, 0)
	var attacker := _raise(SPEAR, 1, Vector3(3, 0, 0))
	var before := defender.hit_points

	defender.take_damage(100.0, attacker)
	_check.near(defender.hit_points, before - 100.0, "a wound comes off the hit points")
	_check.ok(defender.is_alive(), "a flesh wound is not the end of him")
	_check.same(defender.state, Unit.State.ATTACK, "and he turns on whoever struck him")
	_check.ok(defender._target == attacker, "on that one, not another")
	await _clear()

	# A citizen at work does not drop his tools to chase a soldier.
	var worker := _raise(WORKER, 0)
	var raider := _raise(SWORD, 1, Vector3(3, 0, 0))
	worker.state = Unit.State.GATHER
	worker.take_damage(10.0, raider)
	_check.ok(worker.state != Unit.State.ATTACK, "a citizen at work does not go for the man hitting him")
	await _clear()


func _a_shield_takes_some_of_it() -> void:
	var guarded := _raise(SWORD, 0)
	var attacker := _raise(SPEAR, 1, Vector3(3, 0, 0))
	guarded.damage_reduction = 0.5
	var before := guarded.hit_points
	guarded.take_damage(100.0, attacker)
	_check.near(guarded.hit_points, before - 50.0, "a raised shield stops half the blow")
	guarded.damage_reduction = 1.0
	var held := guarded.hit_points
	guarded.take_damage(100.0, attacker)
	_check.near(guarded.hit_points, held, "a blow stopped outright costs nothing")
	await _clear()


func _a_dead_man_takes_no_more() -> void:
	var soldier := _raise(SWORD, 0)
	var attacker := _raise(SPEAR, 1, Vector3(3, 0, 0))
	soldier.take_damage(soldier.max_hit_points + 10.0, attacker)
	_check.ok(not soldier.is_alive(), "a blow past his last hit point kills him")
	_check.same(soldier.state, Unit.State.DEAD, "and he is counted among the dead")
	_check.ok(not (soldier in Unit.all_units), "and off the roll, so nobody aims at him any more")
	var after := soldier.hit_points
	soldier.take_damage(100.0, attacker)
	_check.near(soldier.hit_points, after, "hitting a dead man changes nothing")
	await _clear()


## A building is not a point: a soldier walks to the nearest piece of its wall.
func _the_nearest_corner_of_a_building() -> void:
	var soldier := _raise(SWORD, 0)
	var rect := Rect2(10, 10, 6, 6)          # from (10,10) to (16,16)

	soldier.position = Vector3(0, 0, 13)
	_check.near(soldier._closest_point_on(rect).x, 10.0, "from the west he makes for the west face")
	_check.near(soldier._closest_point_on(rect).z, 13.0, "straight across, not round a corner")

	soldier.position = Vector3(0, 0, 0)
	var corner := soldier._closest_point_on(rect)
	_check.near(corner.x, 10.0, "from the south west he makes for the corner")
	_check.near(corner.z, 10.0, "in both directions at once")

	soldier.position = Vector3(13, 0, 13)
	_check.near(soldier._closest_point_on(rect).distance_to(Vector3(13, 0, 13)), 0.0,
		"standing inside it, he is already there")
	await _clear()


func _who_a_soldier_goes_for() -> void:
	var soldier := _raise(SWORD, 0)
	var near_enemy := _raise(SPEAR, 1, Vector3(5, 0, 0))
	var far_enemy := _raise(SPEAR, 1, Vector3(15, 0, 0))
	var friend := _raise(SPEAR, 0, Vector3(1, 0, 0))

	_check.ok(soldier._nearest_enemy(30.0) == near_enemy, "he goes for the nearest enemy")
	_check.ok(soldier._nearest_enemy(30.0) != friend, "never for one of his own, however close")
	near_enemy.state = Unit.State.DEAD
	_check.ok(soldier._nearest_enemy(30.0) == far_enemy, "a fallen enemy is passed over for a standing one")
	_check.ok(soldier._nearest_enemy(10.0) == null, "and nothing out of range is picked at all")
	await _clear()

	# With no enemy soldier about, a building will do - but a man always comes first, even
	# when the wall is nearer.
	var lone := _raise(SWORD, 0)
	var wall := _wall(WALL, 1, Vector3(8, 0, 0))
	_check.ok(lone._nearest_enemy(30.0) == wall, "with nobody about, he sets about the wall")
	var distant_man := _raise(SPEAR, 1, Vector3(20, 0, 0))
	_check.ok(lone._nearest_enemy(30.0) == distant_man, "a man is answered before a wall, near or far")
	await _clear()


## The navmesh keeps a gateway open so its owner can use it, so a stranger has to be
## stopped at it by hand - that is what this rule is for.
func _a_shut_gate_stands_in_the_way() -> void:
	var stranger := _raise(SWORD, 1, Vector3(0, 0, -5))
	var northwards := Vector3(0, 0, 1)
	_check.ok(stranger._gate_in_the_way(northwards) == null, "with no gate about, nothing stands in the way")

	var gate := _wall(GATE, 0, Vector3.ZERO)
	stranger.position = Vector3(0, 0, gate.footprint.position.y - 0.3)
	_check.ok(stranger._gate_in_the_way(northwards) == gate, "a stranger is stopped at the gateway")
	_check.ok(stranger._gate_in_the_way(Vector3(0, 0, -1)) == null, "walking away from it, he is not")

	var owner := _raise(SWORD, 0, stranger.position)
	_check.ok(owner._gate_in_the_way(northwards) == null, "its own men walk through unhindered")

	gate.take_damage(gate.max_hit_points + 1.0, stranger)
	_check.ok(stranger._gate_in_the_way(northwards) == null, "once it is broken the way is open")
	await _clear()


func _an_order_takes_hold_at_once() -> void:
	var soldier := _raise(SWORD, 0)
	var enemy := _raise(SPEAR, 1, Vector3(10, 0, 0))

	soldier.order_move(Vector3(20, 0, 0))
	_check.same(soldier.state, Unit.State.MOVE, "an order to march is taken at once")
	soldier.order_attack(enemy)
	_check.same(soldier.state, Unit.State.ATTACK, "and so is an order to attack")
	_check.ok(soldier._target == enemy, "with the right man named")

	soldier.order_attack(null)
	_check.ok(soldier._target == enemy, "an order against nobody is no order at all")
	enemy.state = Unit.State.DEAD
	soldier.state = Unit.State.IDLE
	soldier.order_attack(enemy)
	_check.ok(soldier.state != Unit.State.ATTACK, "nor is one against a man already down")

	# A citizen's work is not a soldier's.
	var whole := _wall(WALL, 0, Vector3(40, 0, 0))
	whole.add_construction(whole.build_time)
	soldier.state = Unit.State.IDLE
	soldier.order_build(whole)
	_check.ok(soldier.state != Unit.State.BUILD, "a soldier does not pick up a hammer")
	var citizen := _raise(WORKER, 0, Vector3(38, 0, 0))
	citizen.order_build(whole)
	_check.ok(citizen.state != Unit.State.BUILD, "and nobody builds what is finished and sound")
	await _clear()


## Researching the next level of a unit line swaps the men already in the field for their
## veteran version, and a man who was half dead stays half dead.
func _a_veteran_steps_into_his_place() -> void:
	var recruit := _raise(SWORD, 0, Vector3(7, 0, 3))
	recruit.rotation.y = 1.0
	recruit.selected = true
	recruit.take_damage(recruit.max_hit_points * 0.5, null)
	var fraction := recruit.hit_points / recruit.max_hit_points

	var veteran := Unit.replace_with(recruit, SWORD_VETERAN)
	_check.ok(veteran != null, "the veteran takes his place")
	if veteran:
		_check.near(veteran.position.distance_to(Vector3(7, 0, 3)), 0.0, "on the same spot")
		_check.near(veteran.rotation.y, 1.0, "facing the same way")
		_check.same(veteran.team, 0, "on the same side")
		_check.ok(veteran.selected, "and still picked out, if his predecessor was")
		_check.near(veteran.hit_points / veteran.max_hit_points, fraction,
			"carrying the same share of his wounds", 0.02)
		_check.ok(veteran.max_hit_points >= recruit.max_hit_points, "a veteran is no frailer than a recruit")
		_check.ok(veteran in Unit.all_units, "the veteran is on the roll")
	_check.ok(not (recruit in Unit.all_units), "and the recruit is off it")

	var fallen := _raise(SWORD, 0)
	fallen.state = Unit.State.DEAD
	_check.ok(Unit.replace_with(fallen, SWORD_VETERAN) == null, "the dead are not promoted")
	await _clear()


## Which clip plays for a role is decided by what the original called its animations. The
## third person set belongs to hero mode and must never be picked for a soldier in the field.
func _an_animation_is_picked_by_name() -> void:
	var clips := ["men_ymwalk", "men_ymrun", "men_ymatck_01", "men_ymatck_3p", "men_ymdeath_01", "men_ymfdgt_01"]
	_check.same(Unit._pick(clips, ["walk"], []), "men_ymwalk", "a walk is found by its name")
	_check.same(Unit._pick(clips, ["atck"], []), "men_ymatck_01", "and a swing by its own")
	_check.ok(not "3p" in Unit._pick(clips, ["atck"], []), "the hero's own set is passed over")
	_check.same(Unit._pick(clips, ["sprint", "run"], []), "men_ymrun", "the first name on the list wins")
	_check.same(Unit._pick(clips, ["death"], ["death"]), "", "an excluded word rules a clip out")
	_check.same(Unit._pick(clips, ["swim"], []), "", "and what is not there comes back empty")
	_check.same(Unit._pick([], ["walk"], []), "", "a unit with no clips at all is no trouble")
