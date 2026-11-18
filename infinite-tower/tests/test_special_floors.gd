extends SceneTree

# Special guardian floors (docs/BOSS_SYSTEM.md, scripts/systems/
# SpecialFloors.gd): floor 10's Dead Tide survival and floor 20's Vharzul
# with Dragonbane and the Chain Rite. Run through tests/run_tests.sh (a
# disposable project copy, so save-writing checks never touch the real
# save). Godot's assert() does not stop a headless run, so checks are
# counted explicitly and the exit code reports failures.

const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const TowerCatalogScript = preload("res://scripts/systems/TowerCatalog.gd")
const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const BossBrain = preload("res://scripts/battle/BossBrain.gd")
const REAL_PROJECT_NAME := "Infinite Tower"
const DT := 1.0 / 60.0

# Loaded at run time: these use autoloads that a preload would compile
# before the autoloads exist.
var EnemyScript: GDScript
var TideScript: GDScript
var RiteScript: GDScript
var _failures: Array[String] = []
var _checks := 0


class FakePlayer extends CharacterBody3D:
	var health := 100000.0
	var maximum_health := 100000.0
	var hits: Array = []
	var forward := Vector3.FORWARD

	func receive_enemy_attack(amount: float, source: Node, info: Dictionary = {}) -> bool:
		hits.append({"amount": amount, "source": source, "info": info})
		return false

	func is_invulnerable() -> bool:
		return false

	func camera_shake(_strength: float) -> void:
		pass

	func has_equipped_effect(_id: String) -> bool:
		return false

	func is_crouching() -> bool:
		return false

	func is_guarding() -> bool:
		return false

	func _camera_forward() -> Vector3:
		return forward


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("FAIL: ", label)


func _run() -> void:
	EnemyScript = load("res://scripts/battle/EnemyAgent.gd")
	TideScript = load("res://scripts/battle/DeadTideDirector.gd")
	RiteScript = load("res://scripts/battle/ChainRite.gd")
	_test_catalog()
	_test_tide_data()
	_test_dragonbane_data()
	_test_dragon_moveset()
	_test_terrain_spots()
	await _test_dragon_armor_and_weak_point()
	await _test_chain_down()
	await _test_flight()
	await _test_sweep_and_aggression()
	await _test_chain_rite()
	await _test_dead_tide()
	await _test_tide_pause()
	if _save_tests_allowed():
		_test_dragonbane_saves()
	else:
		print("SKIPPED save-writing Dragonbane tests (run tests/run_tests.sh).")
	if _failures.is_empty():
		print("ALL SPECIAL FLOOR TESTS PASSED (%d checks)." % _checks)
		quit(0)
	else:
		printerr("%d of %d special floor checks FAILED." % [_failures.size(), _checks])
		quit(1)


func _save_tests_allowed() -> bool:
	var project_name = str(ProjectSettings.get_setting("application/config/name"))
	return OS.get_environment("IT_ALLOW_SAVE_TESTS") == "1" and project_name != REAL_PROJECT_NAME


# --- Helpers ---------------------------------------------------------------------

func _make_player(position: Vector3 = Vector3.ZERO) -> FakePlayer:
	var player := FakePlayer.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	player.add_child(shape)
	root.add_child(player)
	player.global_position = position
	return player


func _make_dragon(player: FakePlayer, dragonbane: bool) -> Node:
	var dragon = EnemyScript.new()
	dragon.configure_enemy(player, SpecialFloors.DRAGON_FLOOR, true, TowerCatalogScript.get_floor(20)["boss"])
	root.add_child(dragon)
	dragon.set_physics_process(false)
	dragon.global_position = Vector3.ZERO
	dragon.rotation = Vector3.ZERO
	dragon.dragonbane = dragonbane
	return dragon


func _step(boss, seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		if not is_instance_valid(boss) or boss._brain == null:
			return
		boss._brain.physics_step(DT, true)


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


# --- Data ------------------------------------------------------------------------

func _test_catalog() -> void:
	var tide := TowerCatalogScript.get_floor(10)
	check(tide["boss_floor"] and tide["special"] == "dead_tide", "floor 10 is the Dead Tide")
	check(tide["boss"]["name"] == "The Dead Tide" and not tide["boss"].has("moveset"), "floor 10 has no guardian moveset")
	check(not String(tide["boss"].get("lore", "")).is_empty(), "the Dead Tide has a lore line")
	for floor_number in range(6, 10):
		check(TowerCatalogScript.get_floor(floor_number)["clue"] != "" and TowerCatalogScript.region_boss(1)["name"] == "The Dead Tide",
			"floor %d clues describe the Dead Tide" % floor_number)
	var wyrm := TowerCatalogScript.get_floor(20)
	check(wyrm["special"] == "dragon" and int(wyrm["boss"]["moveset"]) == BossMoves.DRAGON_INDEX, "floor 20 is Vharzul")
	check(wyrm["boss"]["name"] == SpecialFloors.DRAGON_NAME, "floor 20 names Vharzul")
	check(not String(wyrm["boss"].get("lore", "")).is_empty(), "Vharzul has a lore line")
	check(TowerCatalogScript.get_floor(17)["clue"] == TowerCatalogScript.VHARZUL["attacks"], "floor 17 clue describes Vharzul")
	check(TowerCatalogScript.BOSSES[3]["name"] == "The Drowned Cantor", "the Drowned Cantor stays defined")
	check(TowerCatalogScript.BOSSES[1]["name"] == "Mother of Briars", "Mother of Briars stays defined")
	check(String(TowerCatalogScript.get_floor(15).get("special", "")) == "", "other guardian floors are unchanged")
	check(TowerCatalogScript.get_floor(15)["boss"]["name"] == "The Brass Regent", "floor 15 keeps its guardian")


func _test_tide_data() -> void:
	check(is_equal_approx(SpecialFloors.TIDE_DURATION, 600.0), "the Dead Tide lasts 10:00")
	check(is_equal_approx(SpecialFloors.TIDE_TIER_SECONDS, 120.0), "the tide escalates every 2:00")
	check(SpecialFloors.TIDE_TIERS.size() == 5, "five tiers fill the ten minutes")
	check(SpecialFloors.TIDE_SURGES == [240.0, 480.0], "surges at 4:00 and 8:00")
	check(SpecialFloors.TIDE_HARD_CAP <= 40, "hard cap of at most 40 live zombies")
	var previous: Dictionary = {}
	for index in range(SpecialFloors.TIDE_TIERS.size()):
		var tier: Dictionary = SpecialFloors.TIDE_TIERS[index]
		check(int(tier["cap"]) <= SpecialFloors.TIDE_HARD_CAP, "tier %d cap within the hard cap" % index)
		for kind in tier["weights"]:
			check(SpecialFloors.ZOMBIE_KINDS.has(kind), "tier %d kind %s exists" % [index, kind])
		if not previous.is_empty():
			check(float(tier["interval"]) < float(previous["interval"]), "tier %d spawns faster" % index)
			check(int(tier["cap"]) >= int(previous["cap"]), "tier %d allows more zombies" % index)
			check(float(tier["health"]) > float(previous["health"]) and float(tier["speed"]) >= float(previous["speed"]), "tier %d zombies are tougher" % index)
		previous = tier
	check(SpecialFloors.tide_tier_index(0.0) == 0 and SpecialFloors.tide_tier_index(119.0) == 0, "tier 0 for the first two minutes")
	check(SpecialFloors.tide_tier_index(121.0) == 1 and SpecialFloors.tide_tier_index(599.0) == 4, "tiers advance every two minutes")
	var plain := SpecialFloors.tide_settings(300.0, 0, 0)
	var helped := SpecialFloors.tide_settings(300.0, 4, 3)
	check(float(helped["interval"]) > float(plain["interval"]) and int(helped["cap"]) < int(plain["cap"]), "clues and allies thin the tide")
	check(SpecialFloors.format_clock(600.0) == "10:00" and SpecialFloors.format_clock(59.2) == "01:00", "countdown formatting")
	for kind in ["shambler", "runner", "bloated", "brute"]:
		check(ResourceLoader.exists(String(SpecialFloors.ZOMBIE_KINDS[kind]["model"])), "zombie %s reuses an existing model" % kind)
	check(float(SpecialFloors.ZOMBIE_KINDS["runner"]["speed"]) > float(SpecialFloors.ZOMBIE_KINDS["shambler"]["speed"]) * 2.0, "runners are much faster than shamblers")
	check(float(SpecialFloors.ZOMBIE_KINDS["brute"]["armor"]) < 1.0, "brutes are armoured")


func _test_dragonbane_data() -> void:
	check(SpecialFloors.DRAGONBANE_PIECES.size() == 3, "three Dragonbane pieces")
	check(SpecialFloors.piece_floor("scalebreaker_shard", 7) == 16, "Scalebreaker Shard on floor 16")
	check(SpecialFloors.piece_floor("wyrms_eye", 7) == 19, "Wyrm's Eye on floor 19")
	var ember := [SpecialFloors.piece_floor("emberward_charm", 10), SpecialFloors.piece_floor("emberward_charm", 11)]
	check(ember.has(17) and ember.has(18), "Emberward Charm sits on floor 17 or 18 by world seed")
	for seed_value in [0, 1, 99, 123456789]:
		var found := []
		for floor_number in range(16, 20):
			found.append_array(SpecialFloors.pieces_on_floor(floor_number, seed_value))
		found.sort()
		var expected: Array = SpecialFloors.DRAGONBANE_PIECES.duplicate()
		expected.sort()
		check(found == expected, "every piece is placed exactly once (seed %d)" % seed_value)
	check(SpecialFloors.pieces_on_floor(20, 1).is_empty() and SpecialFloors.pieces_on_floor(15, 1).is_empty(), "no pieces outside floors 16-19")
	check(is_equal_approx(SpecialFloors.rite_windup_mult(0), 0.8), "Chain Rite starts at x0.8 wind-ups")
	check(SpecialFloors.rite_windup_mult(2) < SpecialFloors.rite_windup_mult(1) and SpecialFloors.rite_windup_mult(50) >= SpecialFloors.RITE_MIN_WINDUP, "each cycle is faster, down to a floor")
	check(SpecialFloors.rite_damage_mult(1) > SpecialFloors.rite_damage_mult(0), "each cycle hits harder")
	check(SpecialFloors.rite_pillar_positions().size() == 4, "four chain pillars")


func _test_dragon_moveset() -> void:
	var index := BossMoves.DRAGON_INDEX
	check(is_equal_approx(BossMoves.boss_size(index), 5.0), "Vharzul is 5x the player")
	var moves := BossMoves.scaled_moves(index)
	var breath: Dictionary = moves["fire_breath"]
	check(breath["color"] == "red" and breath["shape"]["type"] == "cone" and float(breath.get("sweep", 0.0)) > 0.0, "fire breath is a sweeping red cone")
	check(moves["tail_sweep"]["shape"]["type"] == "box", "tail sweep is a box")
	check(moves["wing_gust"]["kind"] == "pulse" and moves["wing_gust"].has("ring"), "wing gust is a ring")
	check(moves["wyrm_charge"]["kind"] == "charge", "Vharzul charges")
	check(moves["take_off"]["kind"] == "flight", "Vharzul takes flight")
	check(bool(moves["landing_slam"]["land"]) and bool(moves["landing_slam"]["air"]) and moves["landing_slam"].has("ring"), "landing slam ends the flight with a shockwave")
	check(bool(moves["fire_rain"]["air"]) and moves["fire_rain"]["hazard"]["tint"] == "fire" and float(moves["fire_rain"]["hazard"]["duration"]) > 0.0, "fire rain hazards while airborne")
	var air := 0
	var phase_two := 0
	for id in moves:
		if bool(moves[id].get("air", false)) and not bool(moves[id].get("land", false)):
			air += 1
		if int(moves[id]["phase"]) >= 2:
			phase_two += 1
	check(air >= 2, "at least two airborne attacks")
	check(phase_two >= 1, "Vharzul unlocks phase-two moves")


func _test_terrain_spots() -> void:
	var tower_script = load("res://scenes/dungeon/TowerGame.gd")
	var builder_script = load("res://scripts/world/RegionBuilder.gd")
	for floor_number in [16, 17, 18, 19, 20]:
		var game = tower_script.new()
		game.floor_number = floor_number
		var points: Array = game._reserved_points()
		var pieces: Array = game._pieces_here()
		game.free()
		if floor_number == 20:
			for pillar in SpecialFloors.rite_pillar_positions():
				check(points.has(pillar), "floor 20 reserves the chain pillars")
		elif not pieces.is_empty():
			check(points.has(SpecialFloors.PIECE_POSITION), "floor %d reserves the Dragonbane shrine" % floor_number)
		var builder = builder_script.new()
		builder.configure(3, 4321 + floor_number, points)
		var worst := 0.0
		for point in points:
			worst = maxf(worst, absf(builder.height_at(point.x, point.z)))
		check(worst < 0.05, "floor %d special spots are level (worst %.2f m)" % [floor_number, worst])
		builder.free()


# --- Vharzul -----------------------------------------------------------------------

func _test_dragon_armor_and_weak_point() -> void:
	var player := _make_player(Vector3(0, 0, 20))
	var dragon = _make_dragon(player, false)
	check(dragon.dragon and dragon.boss_index == BossMoves.DRAGON_INDEX, "floor 20 spawns Vharzul")
	check(is_equal_approx(dragon.get_size_scale(), 5.0), "Vharzul is spawned at 5x")
	var reasons: Array = []
	dragon.deflected.connect(func(_enemy, reason: String): reasons.append(reason))
	var before: float = dragon.health
	dragon.take_hit(40.0, true, true, {"posture": 40.0})
	check(is_equal_approx(dragon.health, before), "without Dragonbane a hit does no damage")
	check(dragon.posture == 0.0, "without Dragonbane a hit builds no posture")
	check(reasons == ["armored"], "a deflected hit signals the HUD hint")
	check(dragon._burn_time == 0.0, "the scales do not catch fire")
	check(dragon.is_armored() and dragon.is_invulnerable(), "Vharzul reports its armour")
	# With Dragonbane: normal damage away from the weak point, double on it.
	dragon.dragonbane = true
	player.global_position = Vector3(0, 0, 6)   # behind the wyrm (it faces -Z)
	before = dragon.health
	dragon.take_hit(20.0, false, false, {"posture": 6.0})
	var normal: float = before - dragon.health
	check(normal > 0.0, "Dragonbane lets hits land")
	check(is_equal_approx(dragon.posture, 6.0), "a normal hit adds its posture")
	player.global_position = dragon.weak_point_position()
	before = dragon.health
	dragon.take_hit(20.0, false, false, {"posture": 6.0})
	var weak: float = before - dragon.health
	check(is_equal_approx(weak, normal * SpecialFloors.WEAK_POINT_MULT), "the weak point takes double damage (%.1f vs %.1f)" % [weak, normal])
	check(is_equal_approx(dragon.posture, 6.0 + 12.0), "the weak point takes double posture")
	check(dragon._weak_marker != null, "the weak point has a glowing marker")
	await _cleanup([dragon, player])


func _test_chain_down() -> void:
	var player := _make_player(Vector3(0, 0, 6))
	var dragon = _make_dragon(player, false)
	check(dragon.chain_down(5.0), "the chains can drag Vharzul down")
	check(dragon.is_chained() and not dragon.is_armored(), "chained, the scales can be cut")
	var before: float = dragon.health
	dragon.take_hit(20.0, false, false, {"posture": 30.0})
	check(dragon.health < before, "a chained Vharzul takes damage without Dragonbane")
	check(dragon.posture == 0.0, "no posture break while chained")
	check(not dragon.apply_immobilize(2.5), "Immobilize cannot stretch the chain window")
	_step(dragon, 5.1)
	check(not dragon.is_chained() and dragon.is_armored(), "it breaks free and the scales close again")
	await _cleanup([dragon, player])


func _test_flight() -> void:
	var player := _make_player(Vector3(0, 0, -14))
	var dragon = _make_dragon(player, true)
	var brain = dragon._brain
	brain.start_move("take_off")
	_step(dragon, 0.9 + 0.65)
	check(brain.airborne and dragon.is_airborne(), "take-off lifts Vharzul into the air")
	check(dragon.collision_layer == 0, "the player can pass beneath a flying wyrm")
	_step(dragon, 1.0)
	check(brain.lift > 3.0, "the model rises (%.1f m)" % brain.lift)
	check(dragon.get_lock_point().y > 5.0 * 1.8 * 0.6 + 3.0, "lock-on follows it into the air")
	var reasons: Array = []
	dragon.deflected.connect(func(_enemy, reason: String): reasons.append(reason))
	var before: float = dragon.health
	dragon.take_hit(30.0, true)
	check(is_equal_approx(dragon.health, before) and reasons == ["airborne"], "a flying wyrm is out of reach")
	brain.state = BossBrain.State.IDLE
	var only_air := true
	var landed_early := false
	for i in range(40):
		var id: String = brain.choose_move(12.0)
		if id != "" and not bool(brain.moves[id].get("air", false)):
			only_air = false
		if id == "landing_slam":
			landed_early = true
	check(only_air, "only air attacks while flying")
	check(not landed_early, "no landing before three air attacks")
	brain._air_count = BossMoves.AIR_ATTACKS
	check(brain.choose_move(12.0) == "landing_slam", "after three air attacks it must land")
	brain.start_move("landing_slam")
	_step(dragon, brain._windup + 0.05)
	check(not brain.airborne and dragon.collision_layer != 0, "the landing slam puts it back on the ground")
	_step(dragon, 1.0)
	check(brain.lift < 0.5, "the model is back on the ground")
	var only_ground := true
	brain.state = BossBrain.State.IDLE
	for i in range(30):
		var id: String = brain.choose_move(6.0)
		if id != "" and bool(brain.moves[id].get("air", false)):
			only_ground = false
	check(only_ground, "no air attacks on the ground")
	await _cleanup([dragon, player])


func _test_sweep_and_aggression() -> void:
	var player := _make_player(Vector3(0, 0, -6))
	var dragon = _make_dragon(player, true)
	var brain = dragon._brain
	brain.start_move("fire_breath")
	check(brain._indicator != null and float(brain._indicator.shape["angle"]) > float(brain.move["shape"]["angle"]), "the telegraph marks the whole swept arc")
	_step(dragon, brain._windup + 0.05)
	var start_yaw: float = dragon.rotation.y
	_step(dragon, 0.6)
	check(absf(dragon.rotation.y - start_yaw) > 0.3, "the breath sweeps across the arc")
	check(not player.hits.is_empty() and player.hits[0]["info"]["unblockable"], "the red breath burns the player")
	brain.state = BossBrain.State.IDLE
	brain._clear_indicator()
	dragon.set_aggression(0.8, 1.15)
	brain.start_move("tail_sweep")
	check(is_equal_approx(brain._windup, 1.0 * 0.8), "aggression shortens wind-ups")
	check(is_equal_approx(brain.attack_damage(brain.move), float(dragon.attack_power) * 1.0 * 1.15), "aggression raises damage")
	await _cleanup([dragon, player])


func _test_chain_rite() -> void:
	var player := _make_player(Vector3(0, 0, 30))
	var dragon = _make_dragon(player, false)
	dragon.global_position = Vector3(0, 0, -8)
	var rite = RiteScript.new()
	rite.setup(dragon, player)
	root.add_child(rite)
	rite.set_physics_process(false)
	check(is_equal_approx(dragon._brain.windup_mult, 0.8), "the rite starts at full aggression")
	var bound_cycles: Array = []
	var broke: Array = []
	rite.bound.connect(func(cycle: int): bound_cycles.append(cycle))
	rite.broke_free.connect(func(cycle: int): broke.append(cycle))
	var pillars: Array = rite.positions
	check(pillars.size() == 4, "four pillars are built")
	# Half a channel, then step away: the progress drains.
	player.global_position = pillars[0]
	for i in range(int(4.0 / DT)):
		rite.step(DT)
	player.global_position = Vector3(0, 0, 30)
	for i in range(int(2.0 / DT)):
		rite.step(DT)
	check(float(rite.progress[0]) < 3.5 and float(rite.progress[0]) > 2.0, "progress drains outside the circle (%.2f)" % rite.progress[0])
	check(rite.lit_count() == 0, "a half-channelled pillar is not lit")
	for index in range(4):
		player.global_position = pillars[index]
		for i in range(int((SpecialFloors.RITE_CHANNEL + 0.1) / DT)):
			rite.step(DT)
			if dragon.is_chained():
				break
		if index < 3:
			check(rite.lit[index], "pillar %d lights after %.0f s in its circle" % [index, SpecialFloors.RITE_CHANNEL])
	check(dragon.is_chained() and bound_cycles == [0], "four lit pillars chain Vharzul down")
	check(rite.status_text().begins_with("CHAINED"), "the HUD shows the chain window")
	for i in range(int((SpecialFloors.RITE_STUN + 0.2) / DT)):
		dragon._brain.physics_step(DT, true)
		rite.step(DT)
	check(not dragon.is_chained() and broke == [1], "it breaks free after the stun window")
	check(rite.lit_count() == 0 and float(rite.progress[0]) == 0.0, "the pillars reset")
	check(is_equal_approx(dragon._brain.windup_mult, SpecialFloors.rite_windup_mult(1)) and dragon._brain.damage_mult > 1.0, "each cycle is harder")
	await _cleanup([rite, dragon, player])


# --- The Dead Tide -----------------------------------------------------------------

func _make_tide(player: FakePlayer, clues: int = 0) -> Node:
	var tide = TideScript.new()
	tide.setup(player, clues, 0)
	tide.world = root
	root.add_child(tide)
	tide.set_physics_process(false)
	return tide


func _test_dead_tide() -> void:
	var player := _make_player(Vector3.ZERO)
	var tide = _make_tide(player)
	var survived := []
	var surges := []
	tide.survived.connect(func(): survived.append(true))
	tide.surge.connect(func(index: int): surges.append(index))
	tide.step(3.0)
	check(tide.live_count() > 0, "zombies spawn")
	var spawned_ok := true
	for zombie in tide.zombies():
		var distance: float = Vector2(zombie.global_position.x, zombie.global_position.z).length()
		if not zombie.horde or not zombie.summoned or distance < SpecialFloors.TIDE_SPAWN_RADIUS.x - 0.1 or distance > SpecialFloors.TIDE_SPAWN_RADIUS.y + 0.1:
			spawned_ok = false
		# The camera looks down -Z, so the dead arrive from behind (+Z side).
		if zombie.global_position.z < -SpecialFloors.TIDE_SPAWN_RADIUS.y * 0.2:
			spawned_ok = false
	check(spawned_ok, "zombies spawn out of view at the arena edge and are horde members")
	# The cap holds at every tier.
	var max_live := 0
	for i in range(240):
		tide.step(2.0)
		max_live = maxi(max_live, tide.live_count())
	check(max_live <= SpecialFloors.TIDE_HARD_CAP, "live zombies never exceed the hard cap (%d)" % max_live)
	check(surges == [0, 1], "brute surges at 4:00 and 8:00 (%s)" % [surges])
	var brutes := 0
	for zombie in tide.zombies():
		if zombie.zombie_kind == "brute":
			brutes += 1
	check(brutes > 0, "brutes are on the field after the surges")
	check(survived.is_empty() and tide.time_left() > 0.0, "not cleared before 10:00")
	# Kinds behave differently.
	var settings: Dictionary = tide.current_settings()
	var runner = tide._spawn_one("runner", settings, 0.0)
	var shambler = tide._spawn_one("shambler", settings, 0.0)
	var brute = tide._spawn_one("brute", settings, 0.0)
	if runner != null and shambler != null and brute != null:
		check(runner.move_speed > shambler.move_speed * 2.0, "runners outpace shamblers")
		check(brute.maximum_health > shambler.maximum_health * 3.0 and brute.light_armor < 1.0, "brutes are tough and armoured")
		var before: float = brute.health
		brute.take_hit(10.0, false)
		check(is_equal_approx(before - brute.health, 10.0 * brute.light_armor), "light hits glance off brutes")
	else:
		# The cap may be full; free room and retry once.
		for zombie in tide.zombies():
			tide._remove(zombie)
		await process_frame
		runner = tide._spawn_one("runner", settings, 0.0)
		shambler = tide._spawn_one("shambler", settings, 0.0)
		check(runner != null and shambler != null and runner.move_speed > shambler.move_speed * 2.0, "runners outpace shamblers")
	# A bloated zombie bursts into a poison pool.
	for zombie in tide.zombies():
		tide._remove(zombie)
	await process_frame
	var kills_before: int = tide.kills
	var bloated = tide._spawn_one("bloated", settings, 0.0)
	check(bloated != null, "a bloated zombie can be spawned")
	var hazards_before := _count_hazards()
	if bloated != null:
		bloated.take_hit(100000.0, true)
	check(tide.kills == kills_before + 1, "kills are counted")
	check(_count_hazards() == hazards_before + 1, "the bloated burst leaves a poison pool")
	# Far-away zombies are recycled.
	var straggler = tide._spawn_one("shambler", settings, 0.0)
	straggler.global_position = Vector3(0, 0, 200)
	tide.step(0.01)
	check(not tide.zombies().has(straggler), "zombies far from the player are recycled")
	# Surviving to the end clears the floor.
	tide.fast_forward(SpecialFloors.TIDE_DURATION)
	check(survived == [true] and tide.finished, "surviving 10:00 clears the floor")
	check(tide.live_count() == 0, "the remaining dead collapse")
	var count_after := 0
	tide.step(5.0)
	for node in root.get_children():
		if node.get("horde") == true and not node.is_queued_for_deletion():
			count_after += 1
	check(count_after == 0, "no zombies spawn after the tide ends")
	await _cleanup([tide, player])
	for node in root.get_children():
		if node.get_script() == load("res://scripts/battle/BossHazard.gd"):
			node.queue_free()
	await process_frame
	# Clues thin the tide.
	var plain_player := _make_player(Vector3.ZERO)
	var plain = _make_tide(plain_player, 0)
	var helped = _make_tide(plain_player, 4)
	check(float(helped.current_settings()["interval"]) > float(plain.current_settings()["interval"]), "known clues slow the spawns")
	await _cleanup([plain, helped, plain_player])


func _count_hazards() -> int:
	var count := 0
	var hazard_script = load("res://scripts/battle/BossHazard.gd")
	for node in root.get_children():
		if node.get_script() == hazard_script and not node.is_queued_for_deletion():
			count += 1
	return count


# Paused time does not count: the director is a pausable node.
func _test_tide_pause() -> void:
	var player := _make_player(Vector3.ZERO)
	var tide = TideScript.new()
	tide.setup(player)
	tide.world = root
	tide.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(tide)
	for i in range(10):
		await physics_frame
	var running: float = tide.elapsed
	check(running > 0.0, "the tide clock runs during play")
	paused = true
	for i in range(20):
		await physics_frame
	check(is_equal_approx(tide.elapsed, running), "the tide clock stops while paused")
	paused = false
	for zombie in tide.zombies():
		tide._remove(zombie)
	await _cleanup([tide, player])


# --- Save data ---------------------------------------------------------------------

func _test_dragonbane_saves() -> void:
	var player_data = root.get_node("PlayerData")
	var gacha = root.get_node("GachaManager")
	var state: Dictionary = player_data.get_state()
	check(state.has("dragonbane"), "the save has a Dragonbane record")
	check(not player_data.collect_dragonbane_piece("dragon_tooth"), "unknown pieces are refused")
	check(player_data.collect_dragonbane_piece("scalebreaker_shard"), "a piece can be collected")
	check(player_data.collect_dragonbane_piece("scalebreaker_shard"), "collecting a piece twice is harmless")
	check(player_data.dragonbane_pieces() == ["scalebreaker_shard"], "a piece is stored once")
	check(not player_data.can_forge_dragonbane() and not player_data.forge_dragonbane(), "Dragonbane needs all three pieces")
	check(not player_data.has_dragonbane(), "no blade before forging")
	check(player_data.collect_dragonbane_piece("emberward_charm") and player_data.collect_dragonbane_piece("wyrms_eye"), "the other pieces can be collected")
	check(player_data.can_forge_dragonbane(), "all three pieces can be forged")
	check(player_data.forge_dragonbane() and player_data.has_dragonbane(), "Dragonbane is forged")
	check(player_data.forge_dragonbane() and not player_data.can_forge_dragonbane(), "forging twice is harmless")
	# Validation.
	var service = load("res://scripts/systems/PlayerDataService.gd").new()
	var base: Dictionary = player_data.get_state()
	check(service._valid_state(base), "the forged state is valid")
	var bad_records := [
		{"pieces": ["scalebreaker_shard"], "forged": true},
		{"pieces": ["wyrms_eye", "wyrms_eye"], "forged": false},
		{"pieces": ["dragon_tooth"], "forged": false},
		{"pieces": "scalebreaker_shard", "forged": false},
		{"pieces": [], "forged": 1},
		{"pieces": [], "forged": false, "extra": 1},
		[],
	]
	for record in bad_records:
		var candidate: Dictionary = base.duplicate(true)
		candidate["dragonbane"] = record
		check(not service._valid_state(candidate), "invalid Dragonbane record rejected: %s" % [record])
	var missing: Dictionary = base.duplicate(true)
	missing.erase("dragonbane")
	check(not service._valid_state(missing), "a state without the record is invalid until defaults are filled")
	service.free()
	# Persistence: a fresh service reads the same record back from disk.
	check(gacha.load_game(), "the save reloads from disk")
	var reloaded = load("res://scripts/systems/PlayerDataService.gd").new()
	reloaded._ready()
	check(reloaded.has_dragonbane() and reloaded.dragonbane_pieces().size() == 3, "Dragonbane survives a reload")
	reloaded.free()
	# An older save without the record gains the default and stays writable.
	var older: Dictionary = base.duplicate(true)
	older.erase("dragonbane")
	check(gacha.save_persistent_domain("tower_player_state", older), "an older-format state can be stored")
	var upgraded = load("res://scripts/systems/PlayerDataService.gd").new()
	upgraded._ready()
	check(upgraded._storage_writable, "an older save stays writable")
	check(upgraded.get_state()["dragonbane"] == {"pieces": [], "forged": false}, "an older save gets an empty Dragonbane record")
	upgraded.free()
	# Restore the live state for any later checks.
	check(gacha.save_persistent_domain("tower_player_state", base), "the test state is restored")
