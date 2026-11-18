extends SceneTree

# Run through tests/run_tests.sh, which executes this script inside a
# disposable copy of the project so the real player save is never touched.
# Godot's assert() does not stop a headless run, so every check is recorded
# explicitly and the process exits with a non-zero code on any failure.

const TowerCatalogScript = preload("res://scripts/systems/TowerCatalog.gd")
const RareLootRulesScript = preload("res://scripts/systems/RareLootRules.gd")
const EquipmentCatalogScript = preload("res://scripts/systems/EquipmentCatalog.gd")
const PlayerControllerScript = preload("res://scripts/player/PlayerController.gd")
const REAL_PROJECT_NAME := "Infinite Tower"

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("FAIL: ", label)


func _run() -> void:
	_test_floor_catalog()
	_test_rare_rules()
	_test_player_state_validation()
	await _test_parry_window()
	_test_guard_break()
	_test_terrain_keeps_gameplay_spots_level()
	if _save_tests_allowed():
		_test_loot_and_rare_cap()
		_test_floor_progression()
		_test_journal()
		_test_hero_duplicates()
		_test_summon_unlocks_and_rewards()
		_test_persistence_after_reload()
		_test_rares_found_counter()
		_test_new_state_fields_are_filled()
		_test_shop()
		_test_hub()
		# Runs last: it deliberately damages the save files.
		_test_backup_recovery()
	else:
		print("SKIPPED save-writing integration tests (run tests/run_tests.sh).")

	if _failures.is_empty():
		print("ALL TESTS PASSED (%d checks)." % _checks)
		quit(0)
	else:
		printerr("%d of %d checks FAILED." % [_failures.size(), _checks])
		quit(1)


func _save_tests_allowed() -> bool:
	var project_name = str(ProjectSettings.get_setting("application/config/name"))
	return OS.get_environment("IT_ALLOW_SAVE_TESTS") == "1" and project_name != REAL_PROJECT_NAME


func _test_floor_catalog() -> void:
	check(TowerCatalogScript.get_floor(1)["floor"] == 1, "floor 1 exists")
	check(TowerCatalogScript.get_floor(50)["floor"] == 50, "floor 50 exists")
	check(TowerCatalogScript.get_floor(0).is_empty(), "floor 0 does not exist")
	check(TowerCatalogScript.get_floor(51).is_empty(), "floor 51 does not exist")
	check(
		TowerCatalogScript.boss_floor_numbers() == [5, 10, 15, 20, 25, 30, 35, 40, 45, 50],
		"boss floors are every fifth floor"
	)
	check(TowerCatalogScript.can_stealth_exit(false, true, false), "stealth exit allowed")
	check(not TowerCatalogScript.can_stealth_exit(true, true, false), "no stealth exit on boss floor")
	check(not TowerCatalogScript.can_stealth_exit(false, false, false), "stealth exit needs crouch")
	check(not TowerCatalogScript.can_stealth_exit(false, true, true), "stealth exit blocked when alerted")
	for arc in range(10):
		for clue_stage in range(4):
			var floor_number = arc * 5 + clue_stage + 1
			var data = TowerCatalogScript.get_floor(floor_number)
			check(not data["boss_floor"], "floor %d is not a boss floor" % floor_number)
			check(data["clue_stage"] == clue_stage, "floor %d clue stage" % floor_number)
			check(not data["clue"].is_empty(), "floor %d has a clue" % floor_number)
		var boss_data = TowerCatalogScript.get_floor(arc * 5 + 5)
		check(boss_data["boss_floor"], "floor %d is a boss floor" % (arc * 5 + 5))
		check(not boss_data["boss"].is_empty(), "floor %d has a boss" % (arc * 5 + 5))


func _test_rare_rules() -> void:
	var expected = {
		1: "1-10", 10: "1-10", 11: "11-20", 20: "11-20", 21: "21-30",
		30: "21-30", 31: "31-40", 40: "31-40", 41: "41-50", 50: "41-50"
	}
	for floor_number in expected:
		check(
			RareLootRulesScript.interval_key(floor_number) == expected[floor_number],
			"interval key for floor %d" % floor_number
		)
	check(RareLootRulesScript.interval_key(51).is_empty(), "no interval for floor 51")

	var interval_count := 0
	for attempt in range(1000):
		if RareLootRulesScript.choose_rarity(float(attempt % 100), interval_count) == "rare":
			interval_count += 1
	check(
		interval_count == RareLootRulesScript.MAX_RARE_SPAWNS_PER_INTERVAL,
		"rarity roll caps rares at the interval limit"
	)
	check(RareLootRulesScript.choose_rarity(0.0, interval_count) == "unusual", "capped rare roll downgrades")
	check(
		EquipmentCatalogScript.roll_item("rare", 8731)["id"]
		== EquipmentCatalogScript.roll_item("rare", 8731)["id"],
		"equipment rolls are deterministic"
	)


func _test_player_state_validation() -> void:
	# Loaded at runtime because the service references the GachaManager autoload.
	var service = load("res://scripts/systems/PlayerDataService.gd").new()
	var state: Dictionary = service._default_state()
	check(service._valid_state(state), "default state is valid")

	var gear := {
		"instance_id": "gear_v2_12345_1_14_hidden_cache_a",
		"id": "rusted_sabre",
		"name": "Rusted Sabre",
		"slot": "weapon",
		"rarity": "common",
		"attack": 3,
		"defense": 0,
		"effect": "Reliable, if worn.",
		"floor_found": 1
	}
	state["floor_loot"]["1:hidden_cache_a"] = {
		"floor": 1,
		"location_id": "hidden_cache_a",
		"item": gear.duplicate(true),
		"collected": true
	}
	state["inventory"].append(gear.duplicate(true))
	state["equipped"]["weapon"] = gear["instance_id"]
	check(service._valid_state(state), "state with collected gear is valid")

	var malformed_gear_state: Dictionary = state.duplicate(true)
	malformed_gear_state["inventory"][0]["slot"] = "unknown_slot"
	check(not service._valid_state(malformed_gear_state), "unknown gear slot rejected")

	var duplicate_gear_state: Dictionary = state.duplicate(true)
	duplicate_gear_state["inventory"].append(gear.duplicate(true))
	check(not service._valid_state(duplicate_gear_state), "duplicate gear instance rejected")

	var rare_state: Dictionary = service._default_state()
	var rare_gear: Dictionary = gear.duplicate(true)
	rare_gear["rarity"] = "rare"
	rare_state["floor_loot"]["1:hidden_cache_a"] = {
		"floor": 1,
		"location_id": "hidden_cache_a",
		"item": rare_gear,
		"collected": false
	}
	rare_state["rare_interval_counts"]["1-10"] = 1
	rare_state["rare_spawn_history"].append({
		"interval": "1-10",
		"floor": 1,
		"location_id": "hidden_cache_a",
		"instance_id": rare_gear["instance_id"]
	})
	check(service._valid_state(rare_state), "consistent rare history is valid")

	var inconsistent_rare_state: Dictionary = rare_state.duplicate(true)
	inconsistent_rare_state["rare_interval_counts"]["1-10"] = 2
	check(not service._valid_state(inconsistent_rare_state), "inconsistent rare count rejected")
	service.free()


func _test_parry_window() -> void:
	var player = PlayerControllerScript.new()
	var attacker := Node3D.new()
	root.add_child(player)
	root.add_child(attacker)
	await process_frame
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3.ZERO
	player._camera_yaw = 0.0
	var full_health: float = player.maximum_health
	player.health = full_health
	player.stamina = 100.0

	attacker.global_position = Vector3(0, 0, -1)
	player._start_parry()
	check(absf(player._parry_window - 0.24) < 0.001, "parry opens a 0.24s window")
	var stamina_after_start: float = player.stamina
	check(player.receive_enemy_attack(25.0, attacker), "frontal hit is parried")
	check(player.health == full_health, "parried hit deals no damage")
	check(is_equal_approx(player.stamina, stamina_after_start - 8.0), "parry costs 8 stamina")

	attacker.global_position = Vector3(0, 0, 1)
	player._parry_window = 0.24
	check(not player.receive_enemy_attack(25.0, attacker), "rear hit is not parried")
	check(player.health < full_health, "rear hit deals damage")
	player.queue_free()
	attacker.queue_free()
	await process_frame


func _test_loot_and_rare_cap() -> void:
	var loot = root.get_node("LootDirector")
	var player_data = root.get_node("PlayerData")
	var first = loot.generate_hidden_equipment(1, "test_cache_0")
	check(not first.is_empty(), "loot generated on floor 1")
	var again = loot.generate_hidden_equipment(1, "test_cache_0")
	check(again.get("item", {}) == first.get("item", {}), "revisiting returns the same item")
	var loot_count = player_data.get_state()["floor_loot"].size()
	loot.generate_hidden_equipment(1, "test_cache_0")
	check(player_data.get_state()["floor_loot"].size() == loot_count, "revisit does not add loot")

	check(loot.collect_hidden_equipment(1, "test_cache_0"), "first collection succeeds")
	check(not loot.collect_hidden_equipment(1, "test_cache_0"), "second collection is refused")
	var inventory: Array = player_data.get_state()["inventory"]
	check(inventory.size() == 1, "collected item appears exactly once")
	check(loot.equip_item(inventory[0]["instance_id"]), "collected item can be equipped")

	check(loot.generate_hidden_equipment(51, "test_cache_0").is_empty(), "no loot on floor 51")
	check(loot.generate_hidden_equipment(0, "test_cache_0").is_empty(), "no loot on floor 0")

	# Generate many caches on every floor; no interval may exceed the rare cap.
	for floor_number in range(1, 51):
		for index in range(12):
			loot.generate_hidden_equipment(floor_number, "test_cache_%d" % index)
	var state: Dictionary = player_data.get_state()
	var rare_by_interval := {}
	for record in state["floor_loot"].values():
		if record["item"]["rarity"] == "rare":
			var interval = RareLootRulesScript.interval_key(int(record["floor"]))
			rare_by_interval[interval] = int(rare_by_interval.get(interval, 0)) + 1
	var any_rare := false
	for interval in ["1-10", "11-20", "21-30", "31-40", "41-50"]:
		var spawned = int(rare_by_interval.get(interval, 0))
		any_rare = any_rare or spawned > 0
		check(spawned <= 2, "interval %s spawned at most 2 rares (got %d)" % [interval, spawned])
		check(
			int(state["rare_interval_counts"].get(interval, 0)) == spawned,
			"interval %s counter matches spawned rares" % interval
		)
	check(any_rare, "rare equipment can spawn at all")
	check(state["rare_spawn_history"].size() == rare_by_interval.values().reduce(
		func(total, value): return total + value, 0
	), "rare spawn history matches world records")


func _test_floor_progression() -> void:
	var player_data = root.get_node("PlayerData")
	check(not player_data.enter_floor(2), "cannot enter a locked floor")
	for floor_number in range(1, 51):
		check(player_data.enter_floor(floor_number), "enter floor %d" % floor_number)
		check(player_data.complete_floor(floor_number), "complete floor %d" % floor_number)
	var state: Dictionary = player_data.get_state()
	check(int(state["highest_unlocked_floor"]) == 50, "highest unlocked floor caps at 50")
	check(state["completed_floors"].size() == 50, "all 50 floors completed")
	check(state["ending_seen"], "completing floor 50 records the ending")
	check(not player_data.enter_floor(51), "floor 51 cannot be entered")
	check(not player_data.complete_floor(51), "floor 51 cannot be completed")


func _test_journal() -> void:
	var player_data = root.get_node("PlayerData")
	var entry = {"floor": 1, "stage": 0, "region": "Test Region", "text": "Recorded by tests."}
	check(player_data.record_discovery("test_clue", entry), "discovery recorded")
	check(player_data.record_discovery("test_clue", entry), "repeat discovery is harmless")
	check(player_data.get_state()["investigation_journal"].has("test_clue"), "journal keeps discovery")


func _test_hero_duplicates() -> void:
	var gacha = root.get_node("GachaManager")
	var before_count = gacha.get_owned_hero_instances().size()
	var before_gems: int = gacha.get_gem_balance()
	var price: int = gacha.summon_cost(10)
	var results: Array = gacha.summon_ten()
	if results.is_empty():
		check(before_gems < price, "ten-pull only fails without enough gems")
		return
	var instances: Array = gacha.get_owned_hero_instances()
	check(instances.size() == before_count + 10, "ten-pull adds ten separate instances")
	check(gacha.get_gem_balance() == before_gems - price, "ten-pull costs ten times the tier price")
	var ids := {}
	for instance in instances:
		ids[instance["instance_id"]] = true
	check(ids.size() == instances.size(), "every hero instance ID is unique")
	var counts: Dictionary = gacha.get_owned_counts()
	var total := 0
	for hero_id in counts:
		total += int(counts[hero_id])
	check(total == instances.size(), "owned counts match instances (duplicates kept)")
	var ten_cost: int = gacha.summon_cost(10)
	var gems_now: int = gacha.get_gem_balance()
	if gems_now >= ten_cost:
		check(not gacha.summon(10).is_empty(), "ten-pull at the current tier succeeds")
		check(gacha.get_gem_balance() == gems_now - ten_cost, "ten-pull charges the tier price")


func _test_persistence_after_reload() -> void:
	var gacha = root.get_node("GachaManager")
	var player_data = root.get_node("PlayerData")
	var expected_state: Dictionary = player_data.get_state()
	var expected_heroes: Array = gacha.get_owned_hero_instances()
	var expected_gems: int = gacha.get_gem_balance()
	check(gacha.load_game(), "save reloads from disk")
	check(gacha.get_gem_balance() == expected_gems, "gems survive reload")
	check(gacha.get_owned_hero_instances() == expected_heroes, "hero instances survive reload")
	var reloaded = load("res://scripts/systems/PlayerDataService.gd").new()
	reloaded._ready()
	var reloaded_state: Dictionary = reloaded.get_state()
	for key in expected_state:
		check(reloaded_state.get(key) == expected_state[key], "tower state '%s' survives reload" % key)
	# Regression: JSON floats once made `floor in completed_floors` fail after a
	# reload, so repeating progression appended duplicate entries.
	check(reloaded.complete_floor(1), "completed floor can be completed again after reload")
	check(reloaded.enter_floor(1), "visited floor can be entered again after reload")
	var repeated_state: Dictionary = reloaded.get_state()
	check(
		repeated_state["completed_floors"].size() == expected_state["completed_floors"].size(),
		"no duplicate completed floor after reload"
	)
	check(
		repeated_state["visited_floors"].size() == expected_state["visited_floors"].size(),
		"no duplicate visited floor after reload"
	)
	reloaded.free()


func _test_rares_found_counter() -> void:
	var loot = root.get_node("LootDirector")
	var player_data = root.get_node("PlayerData")
	var state: Dictionary = player_data.get_state()
	for interval_start in [1, 11, 21, 31, 41]:
		var interval = RareLootRulesScript.interval_key(interval_start)
		var collected := 0
		for record in state["floor_loot"].values():
			if (
				record["collected"]
				and record["item"]["rarity"] == "rare"
				and RareLootRulesScript.interval_key(int(record["floor"])) == interval
			):
				collected += 1
		check(
			loot.interval_rares_found(interval_start) == collected,
			"HUD rare counter for %s counts only collected rares" % interval
		)
	# Collect one uncollected rare, if any spawned, and confirm the count moves.
	for record in state["floor_loot"].values():
		if record["item"]["rarity"] == "rare" and not record["collected"]:
			var floor_number = int(record["floor"])
			var before = loot.interval_rares_found(floor_number)
			check(loot.collect_hidden_equipment(floor_number, record["location_id"]), "rare cache can be collected")
			check(loot.interval_rares_found(floor_number) == before + 1, "collecting a rare raises the HUD counter")
			break


func _test_new_state_fields_are_filled() -> void:
	var gacha = root.get_node("GachaManager")
	var player_data = root.get_node("PlayerData")
	var full_state: Dictionary = player_data.get_state()
	var older_state: Dictionary = full_state.duplicate(true)
	older_state.erase("achievements")
	check(gacha.save_persistent_domain("tower_player_state", older_state), "older-format state can be stored")
	var service = load("res://scripts/systems/PlayerDataService.gd").new()
	service._ready()
	check(service._storage_writable, "a save missing a newer field stays writable")
	check(service.get_state().get("achievements") == [], "missing newer field gets its default")
	check(
		int(service.get_state()["highest_unlocked_floor"]) == int(full_state["highest_unlocked_floor"]),
		"filling a new field keeps existing progress"
	)
	service.free()


func _write_text(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _damaged_save_count() -> int:
	var count := 0
	for file_name in DirAccess.get_files_at("user://"):
		if file_name.begins_with("save_game.damaged."):
			count += 1
	return count


func _test_backup_recovery() -> void:
	var gacha = root.get_node("GachaManager")
	check(FileAccess.file_exists(gacha.BACKUP_SAVE_PATH), "successful saves keep a backup")
	var backup_data = JSON.parse_string(FileAccess.get_file_as_string(gacha.BACKUP_SAVE_PATH))
	check(typeof(backup_data) == TYPE_DICTIONARY, "backup save is valid JSON")
	if typeof(backup_data) != TYPE_DICTIONARY:
		return
	var backup_gems = int(backup_data["gems"])

	# A damaged main save is set aside and the backup restored.
	var damaged_before = _damaged_save_count()
	_write_text(gacha.SAVE_PATH, "{ not json")
	check(gacha.load_game(), "damaged save recovers from backup")
	check(gacha.is_save_writable(), "recovered save is writable")
	check(gacha.get_gem_balance() == backup_gems, "recovered save has the backup's gems")
	check(not gacha.get_load_warning().is_empty(), "recovery is reported to the player")
	check(_damaged_save_count() == damaged_before + 1, "damaged save is preserved, not deleted")
	check(
		typeof(JSON.parse_string(FileAccess.get_file_as_string(gacha.SAVE_PATH))) == TYPE_DICTIONARY,
		"main save is valid again after recovery"
	)

	# A missing main save (e.g. an interrupted replace) also recovers.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gacha.SAVE_PATH))
	check(gacha.load_game(), "missing save recovers from backup")
	check(gacha.get_gem_balance() == backup_gems, "missing-save recovery keeps progress")

	# With both files damaged, nothing is overwritten and saving is disabled.
	_write_text(gacha.SAVE_PATH, "garbage main")
	_write_text(gacha.BACKUP_SAVE_PATH, "garbage backup")
	check(not gacha.load_game(), "load fails when save and backup are both damaged")
	check(not gacha.is_save_writable(), "saving is disabled when nothing can be loaded")
	check(gacha.summon(10).is_empty(), "summoning is refused when saving is disabled")
	check(not gacha.get_load_warning().is_empty(), "unrecoverable save is reported to the player")
	check(FileAccess.get_file_as_string(gacha.BACKUP_SAVE_PATH) == "garbage backup", "damaged backup is left untouched")


func _test_guard_break() -> void:
	var player = PlayerControllerScript.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.action_press("guard")
	player.stamina = 0.1
	check(player.is_guarding(), "guard is up while stamina remains")
	player._physics_process(1.0 / 60.0)
	check(not player.is_guarding(), "guard drops when stamina runs out")
	var guard_flickered := false
	for frame in range(120):
		player._physics_process(1.0 / 60.0)
		guard_flickered = guard_flickered or player.is_guarding()
	check(not guard_flickered, "empty guard stays down while the key is held")
	var health_before: float = player.health
	player.take_damage(40.0)
	check(health_before - player.health > 30.0, "hits on a broken guard are not reduced")
	Input.action_release("guard")
	player.stamina = 25.0
	player._physics_process(1.0 / 60.0)
	Input.action_press("guard")
	check(player.is_guarding(), "guard recovers after release and some stamina")
	Input.action_release("guard")
	player.queue_free()



func _test_summon_unlocks_and_rewards() -> void:
	var gacha = root.get_node("GachaManager")
	var player_data = root.get_node("PlayerData")
	check(not gacha.is_summon_size_unlocked(1), "single summons do not exist")
	check(gacha.summon(1).is_empty(), "a single summon is refused")
	check(gacha.summon(3).is_empty(), "an unsupported summon size is refused")
	var highest = int(player_data.get_state()["highest_unlocked_floor"])
	check(gacha.is_summon_size_unlocked(10), "ten-pulls are available from the start")
	check(gacha.is_summon_size_unlocked(5) == (highest >= 20), "five-pulls unlock at floor 20")
	check(gacha.is_summon_size_unlocked(2) == (highest >= 40), "two-pulls unlock at floor 40")
	var expected_price = 150 if highest >= 40 else (120 if highest >= 20 else 100)
	check(gacha.summon_cost(1) == expected_price, "per-hero price follows the floor tier")
	check(gacha.summon_cost(5) == expected_price * 5, "five-pull costs five heroes")
	check(gacha.summon_cost(10) == expected_price * 10, "ten-pull costs ten heroes")

	# First clears pay once; repeat clears pay nothing.
	var gems_before: int = gacha.get_gem_balance()
	var floor_number = int(player_data.get_state()["highest_unlocked_floor"])
	var already_done = floor_number in player_data.get_state()["completed_floors"]
	check(player_data.complete_floor(floor_number), "floor can be completed")
	var expected = 0 if already_done else player_data.floor_clear_reward(floor_number)
	check(gacha.get_gem_balance() == gems_before + expected, "first clear grants its gem reward")
	check(player_data.last_gem_reward == expected, "reward amount is reported")
	var gems_after: int = gacha.get_gem_balance()
	check(player_data.complete_floor(floor_number), "floor can be completed again")
	check(gacha.get_gem_balance() == gems_after, "repeat clears grant no gems")
	check(player_data.floor_clear_reward(5) > player_data.floor_clear_reward(4), "boss floors pay more")

	var gems_before_clue: int = gacha.get_gem_balance()
	var entry = {"floor": 1, "stage": 1, "region": "Test", "text": "Reward test clue."}
	check(player_data.record_discovery("reward_test_clue", entry), "new clue recorded")
	check(gacha.get_gem_balance() == gems_before_clue + player_data.CLUE_GEMS, "new clue grants gems")
	check(player_data.record_discovery("reward_test_clue", entry), "repeat clue is harmless")
	check(gacha.get_gem_balance() == gems_before_clue + player_data.CLUE_GEMS, "repeat clue grants nothing")


func _test_terrain_keeps_gameplay_spots_level() -> void:
	var tower_script = load("res://scenes/dungeon/TowerGame.gd")
	var builder_script = load("res://scripts/world/RegionBuilder.gd")
	for region in range(10):
		var game = tower_script.new()
		game.floor_number = region * 5 + 1
		var points: Array = game._reserved_points()
		game.free()
		var builder = builder_script.new()
		builder.configure(region, 1234 + region, points)
		var worst := 0.0
		for point in points:
			worst = maxf(worst, absf(builder.height_at(point.x, point.z)))
		check(worst < 0.05, "region %d: gameplay spots are at ground level (worst %.2f m)" % [region, worst])
		var path_worst := 0.0
		for step in range(0, 100):
			var z = 30.0 - step
			path_worst = maxf(path_worst, absf(builder.height_at(0.0, z)))
		check(path_worst < 0.05, "region %d: path to the exit is level (worst %.2f m)" % [region, path_worst])
		builder.free()


func _test_shop() -> void:
	var gacha = root.get_node("GachaManager")
	var player_data = root.get_node("PlayerData")
	var shop_script = load("res://scripts/systems/ShopCatalog.gd")
	check(player_data.buy_shop_item("not_an_item") == "unknown", "unknown shop items are refused")
	for entry in shop_script.STOCK:
		var item = load("res://scripts/systems/EquipmentCatalog.gd").get_item(entry["item"])
		check(not item.is_empty(), "shop item %s exists in the equipment catalog" % entry["item"])
		check(item.get("rarity", "") != "rare", "shop never sells rare equipment (%s)" % entry["item"])

	# Locked items: temporarily lower the highest floor reached.
	var state: Dictionary = player_data.get_state()
	var saved_highest = int(state["highest_unlocked_floor"])
	var saved_current = int(state["current_floor"])
	state["highest_unlocked_floor"] = 1
	state["current_floor"] = 1
	check(player_data.replace_state(state), "highest floor can be lowered for the shop test")
	check(player_data.shop_item_status("ironwood_bow") == "locked", "floor-gated items are locked below their floor")
	check(player_data.buy_shop_item("ironwood_bow") == "locked", "locked items cannot be bought")
	state = player_data.get_state()
	state["highest_unlocked_floor"] = saved_highest
	state["current_floor"] = saved_current
	check(player_data.replace_state(state), "highest floor restored")

	# A purchase spends gems and adds the item in one save.
	var price = int(shop_script.get_entry("copper_knife")["price"])
	var gems_before: int = gacha.get_gem_balance()
	var inventory_before = player_data.get_state()["inventory"].size()
	if gems_before >= price:
		check(player_data.buy_shop_item("copper_knife") == "ok", "an unlocked, affordable item can be bought")
		check(gacha.get_gem_balance() == gems_before - price, "buying spends exactly the price")
		check(player_data.get_state()["inventory"].size() == inventory_before + 1, "the bought item joins the inventory")
		check(player_data.buy_shop_item("copper_knife") == "sold_out", "purchase limits are enforced")
		check(gacha.get_gem_balance() == gems_before - price, "a refused purchase spends nothing")
		check(gacha.load_game(), "save reloads after a purchase")
		check(gacha.get_gem_balance() == gems_before - price, "the spent gems stay spent after reload")
		var reloaded = load("res://scripts/systems/PlayerDataService.gd").new()
		reloaded._ready()
		check(int(reloaded.get_state()["shop_purchases"].get("copper_knife", 0)) == 1, "the purchase survives reload")
		var found := false
		for item in reloaded.get_state()["inventory"]:
			found = found or item["instance_id"] == "shop_copper_knife_1"
		check(found, "the bought item survives reload")
		reloaded.free()
	# Not enough gems.
	var expensive = "ironwood_bow"
	if gacha.get_gem_balance() < int(shop_script.get_entry(expensive)["price"]):
		check(player_data.buy_shop_item(expensive) == "gems", "items you cannot afford are refused")
	check(not gacha.save_persistent_domain_spending_gems("tower_player_state", player_data.get_state(), gacha.get_gem_balance() + 1), "spending more gems than owned is refused")


func _test_hub() -> void:
	var gacha = root.get_node("GachaManager")
	var player_data = root.get_node("PlayerData")
	var hub_script = load("res://scripts/systems/HubCatalog.gd")
	var owned: Array = gacha.get_owned_hero_instances()
	check(owned.size() >= 3, "test save owns heroes for the hub")
	if owned.size() < 3:
		return
	var trainee: String = owned[0]["instance_id"]
	var miner: String = owned[1]["instance_id"]
	var scout: String = owned[2]["instance_id"]
	var hub: Dictionary = player_data.get_hub()
	check(int(hub["buildings"]["barracks"]) == 1 and int(hub["buildings"]["training_grounds"]) == 1, "camp starts with barracks and training grounds")
	check(int(hub["buildings"]["quarry"]) == 0 and int(hub["buildings"]["scout_hall"]) == 0, "quarry and scout hall must be built")
	check(player_data.hub_capacity() == 4, "level 1 barracks houses four heroes")
	check(player_data.hub_add_resident(trainee), "a hero can move into the camp")
	check(not player_data.hub_add_resident(trainee), "a hero cannot move in twice")
	check(not player_data.hub_add_resident("hero_999999"), "unknown heroes cannot move in")
	check(player_data.hub_add_resident(miner) and player_data.hub_add_resident(scout), "more heroes can move in")
	check(not player_data.hub_assign_job(miner, "miner"), "miners need a quarry first")
	check(player_data.hub_assign_job(trainee, "training"), "a resident can be assigned to training")

	# First clears bring materials: complete a fresh floor-like state.
	var state: Dictionary = player_data.get_state()
	state["hub"]["materials"] = 500
	check(player_data.replace_state(state), "materials can be granted for the test")
	check(player_data.hub_upgrade("quarry"), "the quarry can be built with materials")
	check(int(player_data.get_hub()["materials"]) == 500 - hub_script.upgrade_cost("quarry", 0), "building costs its materials")
	check(player_data.hub_upgrade("scout_hall"), "the scout hall can be built")
	check(player_data.hub_assign_job(miner, "miner"), "miners can work once the quarry exists")

	var t0 := 2000000000
	var first = player_data.hub_collect(t0)
	check(first["ok"] and is_equal_approx(first["hours"], 0.0) or first["hours"] < 0.01, "the first visit only starts the clock")
	var trainee_before = gacha.get_hero_instance(trainee)
	var materials_before = int(player_data.get_hub()["materials"])
	var report = player_data.hub_collect(t0 + 3 * 3600)
	check(report["ok"], "collecting three hours saves")
	check(is_equal_approx(report["hours"], 3.0), "three offline hours are counted")
	var trainee_after = gacha.get_hero_instance(trainee)
	var gained_levels = int(trainee_after["level"]) - int(trainee_before["level"])
	check(gained_levels >= 1 or int(trainee_after["xp"]) > int(trainee_before["xp"]), "training raises hero experience")
	check(int(report["xp"].get(trainee, 0)) > 0, "the report lists training experience")
	check(int(player_data.get_hub()["materials"]) > materials_before, "miners gather materials")

	check(player_data.hub_send_expedition(scout, 2, t0 + 3 * 3600), "a scout can leave on a two-hour expedition")
	check(not player_data.hub_assign_job(scout, "training"), "a scout away cannot take another job")
	check(not player_data.hub_remove_resident(scout), "a scout away cannot leave the camp")
	player_data.hub_collect(t0 + 4 * 3600)
	check(player_data.get_hub()["expeditions"].has(scout), "the scout is still away after one hour")
	var before_return = int(player_data.get_hub()["materials"])
	player_data.hub_collect(t0 + 5 * 3600 + 60)
	check(not player_data.get_hub()["expeditions"].has(scout), "the scout returns when the expedition ends")
	check(player_data.get_hub()["residents"][scout] == "rest", "a returned scout rests")
	check(int(player_data.get_hub()["materials"]) > before_return, "expeditions bring back materials")

	var capped = player_data.hub_collect(t0 + 500 * 3600)
	check(is_equal_approx(capped["hours"], hub_script.OFFLINE_CAP_HOURS), "long absences are capped")

	# Rest bonus for the selected hero.
	state = player_data.get_state()
	state["selected_hero_instance_id"] = scout
	check(player_data.replace_state(state), "a resting resident can be the selected hero")
	player_data.hub_collect(t0 + 503 * 3600)
	var bonus = int(player_data.get_hub()["rest_bonus"])
	check(bonus > 0 and bonus <= 20, "resting builds a capped rest bonus (got %d)" % bonus)
	check(player_data.consume_rest_bonus() == bonus, "the rest bonus is used on the next climb")
	check(player_data.consume_rest_bonus() == 0, "the rest bonus is used only once")

	# Sanctuary works.
	state = player_data.get_state()
	state["hub"]["materials"] = 2000
	var saved_highest = int(state["highest_unlocked_floor"])
	var saved_current = int(state["current_floor"])
	state["highest_unlocked_floor"] = 4
	state["current_floor"] = 1
	check(player_data.replace_state(state), "materials and floor set for sanctuary works")
	check(player_data.hub_build_improvement("gardens") == "locked", "garden terraces wait for floor 5")
	check(player_data.hub_build_improvement("courtyard") == "ok", "the courtyard can be built from the start")
	check(player_data.hub_build_improvement("courtyard") == "built", "a work is built only once")
	check(int(player_data.get_hub()["materials"]) == 2000 - int(hub_script.IMPROVEMENTS["courtyard"]["cost"]), "a work costs its materials")
	check(is_equal_approx(hub_script.offline_cap_hours(player_data.get_hub()), hub_script.OFFLINE_CAP_HOURS + 2.0), "the courtyard extends the offline cap")
	check(player_data.hub_build_improvement("nonsense") == "unknown", "unknown works are refused")
	state = player_data.get_state()
	state["highest_unlocked_floor"] = saved_highest
	state["current_floor"] = saved_current
	check(player_data.replace_state(state), "floor restored after sanctuary works")
	check(player_data.hub_remove_resident(miner), "a resident can leave the camp")
	var bad: Dictionary = player_data.get_state()
	bad["hub"]["materials"] = -5
	check(not player_data._valid_state(bad), "negative materials are rejected")
	bad = player_data.get_state()
	bad["hub"]["buildings"]["barracks"] = 9
	check(not player_data._valid_state(bad), "building levels above 3 are rejected")
