extends Node

signal state_changed

const TowerProgressionCatalog = preload("res://scripts/systems/TowerCatalog.gd")
const RareSpawnRules = preload("res://scripts/systems/RareLootRules.gd")
const Shop = preload("res://scripts/systems/ShopCatalog.gd")
const Equipment = preload("res://scripts/systems/EquipmentCatalog.gd")
const Hub = preload("res://scripts/systems/HubCatalog.gd")
const HeroDatabase = preload("res://data/HeroDatabase.gd")
const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const STATE_DOMAIN := "tower_player_state"
# Gems granted the first time a floor is cleared or a clue is found.
const FLOOR_CLEAR_GEMS := 150
const BOSS_CLEAR_GEMS := 600
const CLUE_GEMS := 50

var _state: Dictionary = {}
var _mutex := Mutex.new()
var _storage_writable := true
# Gems granted by the most recent successful complete_floor/record_discovery.
var last_gem_reward := 0


func _ready() -> void:
	# Load into an untyped variable: assigning a non-Dictionary to the typed
	# `_state` would raise before the root check below could run.
	var loaded = GachaManager.get_persistent_domain(STATE_DOMAIN, {})
	if typeof(loaded) == TYPE_DICTIONARY:
		# Copy: the domain is GachaManager's live data, and filling defaults
		# into it must not leak into the save before validation passes.
		_state = loaded.duplicate(true)
	else:
		_state = _default_state()
		_storage_writable = false
		push_error("Saved tower state has an invalid root; it will not be overwritten.")
		return
	# Fill fields added by newer versions before validating, so an older save
	# gains the new defaults instead of failing validation and becoming
	# read-only.
	var defaults = _default_state()
	var changed = false
	for key in defaults:
		if not _state.has(key):
			_state[key] = defaults[key]
			changed = true
	if not _valid_state(_state):
		_state = _default_state()
		_storage_writable = false
		push_error("Saved tower state failed validation; it will not be overwritten.")
		return
	# JSON stores every number as a float. All numeric tower-state fields are
	# integers, so restore them; otherwise membership checks such as
	# `1 in [1.0]` fail after a reload and duplicate progression entries.
	_state = _normalize_integral_numbers(_state)
	if changed:
		_storage_writable = _persist_candidate(_state)
		if not _storage_writable:
			push_error("Initial tower state could not be saved; progression writes are disabled.")


func _default_state() -> Dictionary:
	return {
		"schema_version": 1,
		"world_seed": int(Time.get_unix_time_from_system()),
		"current_floor": 1,
		"highest_unlocked_floor": 1,
		"completed_floors": [],
		"visited_floors": [],
		"investigation_journal": {},
		"quests": {},
		"faction_relations": {},
		"important_world_changes": {},
		"shortcuts": [],
		"floor_loot": {},
		"rare_interval_counts": {},
		"rare_spawn_history": [],
		"inventory": [],
		"equipped": {},
		"selected_hero_instance_id": "",
		"achievements": [],
		"shop_purchases": {},
		"hub": Hub.default_hub(),
		# Floor 20: Dragonbane pieces found on floors 16-19 and whether the
		# blade has been forged from them.
		"dragonbane": {"pieces": [], "forged": false},
		"ending_seen": false
	}


func get_state() -> Dictionary:
	_mutex.lock()
	var result = _state.duplicate(true)
	_mutex.unlock()
	return result


func replace_state(candidate: Dictionary, gem_reward: int = 0) -> bool:
	if not _storage_writable:
		push_error("Tower progression cannot be saved; player data is read-only.")
		return false
	if not _valid_state(candidate):
		push_error("Refusing to save invalid tower player state.")
		return false
	_mutex.lock()
	if not _persist_candidate(candidate, gem_reward):
		_mutex.unlock()
		return false
	_state = candidate.duplicate(true)
	_mutex.unlock()
	call_deferred("_emit_state_changed")
	return true


func save_now() -> bool:
	if not _storage_writable:
		return false
	_mutex.lock()
	if not _valid_state(_state):
		_mutex.unlock()
		return false
	var saved = _persist_candidate(_state)
	_mutex.unlock()
	return saved


func _emit_state_changed() -> void:
	state_changed.emit()


func save_section(section: String, value: Variant) -> bool:
	if section.is_empty():
		return false
	var candidate = get_state()
	candidate[section] = value.duplicate(true) if value is Array or value is Dictionary else value
	return replace_state(candidate)


func enter_floor(floor_number: int) -> bool:
	if floor_number < 1 or floor_number > TowerProgressionCatalog.FLOOR_LIMIT:
		return false
	var candidate = get_state()
	if floor_number > int(candidate["highest_unlocked_floor"]):
		return false
	candidate["current_floor"] = floor_number
	if floor_number not in candidate["visited_floors"]:
		candidate["visited_floors"].append(floor_number)
	return replace_state(candidate)


func floor_clear_reward(floor_number: int) -> int:
	return BOSS_CLEAR_GEMS if floor_number % 5 == 0 else FLOOR_CLEAR_GEMS


func complete_floor(floor_number: int) -> bool:
	last_gem_reward = 0
	if floor_number < 1 or floor_number > TowerProgressionCatalog.FLOOR_LIMIT:
		return false
	var candidate = get_state()
	var completed: Array = candidate["completed_floors"]
	var reward := 0
	if floor_number not in completed:
		completed.append(floor_number)
		reward = floor_clear_reward(floor_number)
		# First clears also bring materials home to the camp.
		var hub: Dictionary = candidate["hub"]
		hub["materials"] = int(hub["materials"]) + (Hub.BOSS_FLOOR_MATERIALS if floor_number % 5 == 0 else Hub.FLOOR_MATERIALS)
		candidate["hub"] = hub
	completed.sort()
	candidate["completed_floors"] = completed
	candidate["highest_unlocked_floor"] = min(
		TowerProgressionCatalog.FLOOR_LIMIT,
		max(int(candidate["highest_unlocked_floor"]), floor_number + 1)
	)
	if floor_number == TowerProgressionCatalog.FLOOR_LIMIT:
		candidate["ending_seen"] = true
	if not replace_state(candidate, reward):
		return false
	last_gem_reward = reward
	return true


func record_discovery(discovery_id: String, entry: Dictionary) -> bool:
	if discovery_id.is_empty():
		return false
	var candidate = get_state()
	var journal: Dictionary = candidate["investigation_journal"]
	last_gem_reward = 0
	if journal.has(discovery_id):
		return true
	journal[discovery_id] = entry.duplicate(true)
	candidate["investigation_journal"] = journal
	if not replace_state(candidate, CLUE_GEMS):
		return false
	last_gem_reward = CLUE_GEMS
	return true


# Why a shop item can or cannot be bought right now: "ok", "locked",
# "sold_out", "gems" (not enough), "unknown" or "unavailable" (save read-only).
func shop_item_status(item_id: String) -> String:
	var entry = Shop.get_entry(item_id)
	if entry.is_empty():
		return "unknown"
	if not _storage_writable or not GachaManager.is_save_writable():
		return "unavailable"
	var state = get_state()
	if int(state["highest_unlocked_floor"]) < int(entry["unlock_floor"]):
		return "locked"
	if int(state["shop_purchases"].get(item_id, 0)) >= int(entry["limit"]):
		return "sold_out"
	if GachaManager.get_gem_balance() < int(entry["price"]):
		return "gems"
	return "ok"


# Buys one shop item: the gems are spent and the item added to the inventory
# in a single save. Returns the same status codes as shop_item_status.
func buy_shop_item(item_id: String) -> String:
	var status = shop_item_status(item_id)
	if status != "ok":
		return status
	var entry = Shop.get_entry(item_id)
	var item = Equipment.get_item(item_id)
	if item.is_empty():
		return "unknown"
	var candidate = get_state()
	var purchases: Dictionary = candidate["shop_purchases"]
	var bought = int(purchases.get(item_id, 0))
	item["instance_id"] = "shop_%s_%d" % [item_id, bought + 1]
	item["floor_found"] = clampi(int(candidate["highest_unlocked_floor"]), 1, TowerProgressionCatalog.FLOOR_LIMIT)
	item["source"] = "shop"
	var inventory: Array = candidate["inventory"]
	inventory.append(item)
	candidate["inventory"] = inventory
	purchases[item_id] = bought + 1
	candidate["shop_purchases"] = purchases
	if not _storage_writable or not _valid_state(candidate):
		return "unavailable"
	_mutex.lock()
	var saved = GachaManager.save_persistent_domain_spending_gems(STATE_DOMAIN, candidate, int(entry["price"]))
	if saved:
		_state = candidate.duplicate(true)
	_mutex.unlock()
	if not saved:
		return "gems" if GachaManager.get_gem_balance() < int(entry["price"]) else "unavailable"
	call_deferred("_emit_state_changed")
	return "ok"


# --- Dragonbane (floor 20) ----------------------------------------------------

func dragonbane_pieces() -> Array:
	return get_state()["dragonbane"]["pieces"]


func has_dragonbane_piece(piece_id: String) -> bool:
	return piece_id in dragonbane_pieces()


func has_dragonbane() -> bool:
	return bool(get_state()["dragonbane"]["forged"])


func can_forge_dragonbane() -> bool:
	var record: Dictionary = get_state()["dragonbane"]
	if bool(record["forged"]):
		return false
	for piece_id in SpecialFloors.DRAGONBANE_PIECES:
		if piece_id not in record["pieces"]:
			return false
	return true


# Records a found piece in one atomic save. True when the piece is (now)
# owned; false for unknown pieces or a failed save.
func collect_dragonbane_piece(piece_id: String) -> bool:
	if piece_id not in SpecialFloors.DRAGONBANE_PIECES:
		return false
	var candidate = get_state()
	var record: Dictionary = candidate["dragonbane"]
	if piece_id in record["pieces"]:
		return true
	record["pieces"].append(piece_id)
	candidate["dragonbane"] = record
	return replace_state(candidate)


# Forges the three pieces into Dragonbane in one atomic save. True when the
# blade is (now) forged; false when pieces are missing or the save fails.
func forge_dragonbane() -> bool:
	var candidate = get_state()
	var record: Dictionary = candidate["dragonbane"]
	if bool(record["forged"]):
		return true
	if not can_forge_dragonbane():
		return false
	record["forged"] = true
	candidate["dragonbane"] = record
	return replace_state(candidate)


func _validate_dragonbane(record: Variant) -> bool:
	if typeof(record) != TYPE_DICTIONARY or record.size() != 2:
		return false
	var pieces = record.get("pieces")
	if typeof(pieces) != TYPE_ARRAY or typeof(record.get("forged")) != TYPE_BOOL:
		return false
	var seen := {}
	for piece_id in pieces:
		if typeof(piece_id) != TYPE_STRING or piece_id not in SpecialFloors.DRAGONBANE_PIECES or seen.has(piece_id):
			return false
		seen[piece_id] = true
	# The blade can only exist if every piece went into it.
	if bool(record["forged"]) and seen.size() != SpecialFloors.DRAGONBANE_PIECES.size():
		return false
	return true


# --- Camp (hub) ---------------------------------------------------------------

func get_hub() -> Dictionary:
	return get_state()["hub"]


func hub_capacity() -> int:
	return Hub.BARRACKS_CAPACITY[clampi(int(get_hub()["buildings"].get("barracks", 0)), 0, 3)]


func hub_add_resident(instance_id: String) -> bool:
	if GachaManager.get_hero_instance(instance_id).is_empty():
		return false
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	if hub["residents"].has(instance_id) or hub["residents"].size() >= hub_capacity():
		return false
	hub["residents"][instance_id] = "rest"
	candidate["hub"] = hub
	return replace_state(candidate)


func hub_remove_resident(instance_id: String) -> bool:
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	if not hub["residents"].has(instance_id) or hub["expeditions"].has(instance_id):
		return false
	hub["residents"].erase(instance_id)
	candidate["hub"] = hub
	return replace_state(candidate)


# Assigns a resident to a job whose building is built. Scouts are sent with
# hub_send_expedition instead.
func hub_assign_job(instance_id: String, job: String) -> bool:
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	if not hub["residents"].has(instance_id) or hub["expeditions"].has(instance_id):
		return false
	if not Hub.JOBS.has(job) or job == "scout":
		return false
	for building_id in Hub.BUILDINGS:
		if Hub.BUILDINGS[building_id]["job"] == job and int(hub["buildings"].get(building_id, 0)) <= 0:
			return false
	hub["residents"][instance_id] = job
	candidate["hub"] = hub
	return replace_state(candidate)


func hub_send_expedition(instance_id: String, hours: int, now: int = -1) -> bool:
	if hours not in Hub.EXPEDITION_HOURS:
		return false
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	if not hub["residents"].has(instance_id) or hub["expeditions"].has(instance_id):
		return false
	if int(hub["buildings"].get("scout_hall", 0)) <= 0:
		return false
	var start = now if now >= 0 else int(Time.get_unix_time_from_system())
	hub["expeditions"][instance_id] = {"ends": start + hours * 3600, "hours": hours}
	hub["residents"][instance_id] = "scout"
	candidate["hub"] = hub
	return replace_state(candidate)


# Builds (level 0 -> 1) or upgrades a building with materials.
func hub_upgrade(building_id: String) -> bool:
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	var level = int(hub["buildings"].get(building_id, -1))
	var cost = Hub.upgrade_cost(building_id, level)
	if level < 0 or cost < 0 or int(hub["materials"]) < cost:
		return false
	hub["materials"] = int(hub["materials"]) - cost
	hub["buildings"][building_id] = level + 1
	candidate["hub"] = hub
	return replace_state(candidate)


# Builds a sanctuary work once its floor is reached, spending materials.
# Returns "ok", "locked", "built", "materials" or "unknown".
func hub_build_improvement(improvement_id: String) -> String:
	var spec: Dictionary = Hub.IMPROVEMENTS.get(improvement_id, {})
	if spec.is_empty():
		return "unknown"
	var candidate = get_state()
	var hub: Dictionary = candidate["hub"]
	if int(hub["buildings"].get(improvement_id, 0)) > 0:
		return "built"
	if int(candidate["highest_unlocked_floor"]) < int(spec["unlock_floor"]):
		return "locked"
	if int(hub["materials"]) < int(spec["cost"]):
		return "materials"
	hub["materials"] = int(hub["materials"]) - int(spec["cost"])
	hub["buildings"][improvement_id] = 1
	candidate["hub"] = hub
	return "ok" if replace_state(candidate) else "unknown"


# Applies everything the camp produced since the last visit, in one save:
# hub state, found equipment and hero experience. Returns a report.
func hub_collect(now: int = -1) -> Dictionary:
	var timestamp = now if now >= 0 else int(Time.get_unix_time_from_system())
	var candidate = get_state()
	var classes := {}
	for instance_id in candidate["hub"]["residents"]:
		var instance = GachaManager.get_hero_instance(instance_id)
		var hero = _hero_record(instance.get("hero_id", ""))
		classes[instance_id] = hero.get("class", "")
	var seed_value = ("hub:%d:%d" % [int(candidate["world_seed"]), timestamp]).hash()
	var outcome = Hub.tick(candidate["hub"], classes, str(candidate["selected_hero_instance_id"]), timestamp, seed_value)
	candidate["hub"] = outcome["hub"]
	var inventory: Array = candidate["inventory"]
	var found := []
	for index in range(outcome["items"].size()):
		var spec: Dictionary = outcome["items"][index]
		var item = Equipment.roll_item(spec["rarity"], int(spec["seed"]))
		if item.is_empty():
			continue
		item["instance_id"] = "scout_%d_%d" % [timestamp, index]
		item["floor_found"] = clampi(int(candidate["highest_unlocked_floor"]), 1, TowerProgressionCatalog.FLOOR_LIMIT)
		item["source"] = "expedition"
		inventory.append(item)
		found.append(item)
	candidate["inventory"] = inventory
	var report := {"ok": false, "hours": outcome["hours"], "materials": outcome["materials"], "xp": outcome["xp"], "items": found, "levels": {}}
	if not _storage_writable or not _valid_state(candidate):
		return report
	_mutex.lock()
	var levels := {}
	var saved := false
	if outcome["xp"].is_empty():
		saved = _persist_candidate(candidate)
	else:
		var xp_result = GachaManager.save_persistent_domain_with_hero_xp(
			STATE_DOMAIN, candidate, outcome["xp"], 100, 50, Hub.MAX_HERO_LEVEL
		)
		saved = xp_result["saved"]
		levels = xp_result["levels"]
	if saved:
		_state = candidate.duplicate(true)
	_mutex.unlock()
	if saved:
		call_deferred("_emit_state_changed")
	report["ok"] = saved
	report["levels"] = levels
	return report


# Returns and clears the rest bonus (percent of extra vitality) for the climb
# that is starting.
func consume_rest_bonus() -> int:
	var candidate = get_state()
	var bonus = int(candidate["hub"].get("rest_bonus", 0))
	if bonus <= 0:
		return 0
	candidate["hub"]["rest_bonus"] = 0
	return bonus if replace_state(candidate) else 0


func _hero_record(hero_id: String) -> Dictionary:
	for hero in HeroDatabase.get_heroes():
		if hero["id"] == hero_id:
			return hero
	return {}


func _validate_hub(hub: Dictionary) -> bool:
	if not _is_integer_in_range(hub.get("materials"), 0, 1000000000):
		return false
	if not _is_integer_in_range(hub.get("last_tick"), 0, 9007199254740991):
		return false
	if not _is_integer_in_range(hub.get("rest_bonus"), 0, 100):
		return false
	for key in ["buildings", "residents", "expeditions"]:
		if typeof(hub.get(key)) != TYPE_DICTIONARY:
			return false
	for building_id in hub["buildings"]:
		if typeof(building_id) != TYPE_STRING or not _is_integer_in_range(hub["buildings"][building_id], 0, Hub.MAX_BUILDING_LEVEL):
			return false
	for instance_id in hub["residents"]:
		if not _is_nonempty_string(instance_id) or not _is_nonempty_string(hub["residents"][instance_id]):
			return false
	for instance_id in hub["expeditions"]:
		var expedition = hub["expeditions"][instance_id]
		if typeof(expedition) != TYPE_DICTIONARY:
			return false
		if not _is_integer_in_range(expedition.get("ends"), 0, 9007199254740991) or not _is_integer_in_range(expedition.get("hours"), 1, 48):
			return false
	return true


func _persist_candidate(candidate: Dictionary, gem_reward: int = 0) -> bool:
	if gem_reward > 0:
		return GachaManager.save_persistent_domain_with_gems(STATE_DOMAIN, candidate, gem_reward)
	return GachaManager.save_persistent_domain(STATE_DOMAIN, candidate)


func _valid_state(candidate: Dictionary) -> bool:
	if not _is_integer_in_range(candidate.get("schema_version"), 1, 1):
		return false
	if not _is_integer_in_range(candidate.get("world_seed"), 0, 9007199254740991):
		return false
	if not _is_integer_in_range(candidate.get("current_floor"), 1, TowerProgressionCatalog.FLOOR_LIMIT):
		return false
	if not _is_integer_in_range(candidate.get("highest_unlocked_floor"), 1, TowerProgressionCatalog.FLOOR_LIMIT):
		return false
	if int(candidate["current_floor"]) > int(candidate["highest_unlocked_floor"]):
		return false
	if typeof(candidate.get("selected_hero_instance_id")) != TYPE_STRING:
		return false
	for key in ["floor_loot", "rare_interval_counts", "investigation_journal", "quests", "faction_relations", "important_world_changes", "equipped", "shop_purchases", "hub"]:
		if typeof(candidate.get(key)) != TYPE_DICTIONARY:
			return false
	for key in ["rare_spawn_history", "inventory", "completed_floors", "visited_floors", "shortcuts", "achievements"]:
		if typeof(candidate.get(key)) != TYPE_ARRAY:
			return false
	for interval in candidate["rare_interval_counts"]:
		if not _is_valid_rare_interval(interval):
			return false
		var count = candidate["rare_interval_counts"][interval]
		if not _is_integer_in_range(count, 0, RareSpawnRules.MAX_RARE_SPAWNS_PER_INTERVAL):
			return false
	for floor_number in candidate["completed_floors"] + candidate["visited_floors"]:
		if not _is_integer_in_range(floor_number, 1, TowerProgressionCatalog.FLOOR_LIMIT):
			return false
	if not _validate_inventory(candidate["inventory"]):
		return false
	if not _validate_floor_loot(candidate["floor_loot"]):
		return false
	if not _validate_equipped(candidate["equipped"], candidate["inventory"]):
		return false
	if not _validate_rare_spawn_history(candidate["rare_spawn_history"], candidate["rare_interval_counts"], candidate["floor_loot"]):
		return false
	if not _validate_journal(candidate["investigation_journal"]):
		return false
	if not _validate_hub(candidate["hub"]):
		return false
	if not _validate_dragonbane(candidate.get("dragonbane")):
		return false
	# Purchase counts only need to be sane numbers: an item later removed from
	# the shop, or a lowered limit, must not make an old save read-only.
	for item_id in candidate["shop_purchases"]:
		if typeof(item_id) != TYPE_STRING or not _is_integer_in_range(candidate["shop_purchases"][item_id], 0, 1000000):
			return false
	return typeof(candidate.get("ending_seen")) == TYPE_BOOL


func _validate_inventory(inventory: Array) -> bool:
	var seen_instance_ids := {}
	for item in inventory:
		if not _is_valid_equipment_item(item):
			return false
		var instance_id: String = item["instance_id"]
		if seen_instance_ids.has(instance_id):
			return false
		seen_instance_ids[instance_id] = true
	return true


func _validate_floor_loot(floor_loot: Dictionary) -> bool:
	var seen_instance_ids := {}
	for key in floor_loot:
		var record = floor_loot[key]
		if typeof(key) != TYPE_STRING or typeof(record) != TYPE_DICTIONARY:
			return false
		var floor_number = record.get("floor")
		var location_id = record.get("location_id")
		if not _is_integer_in_range(floor_number, 1, TowerProgressionCatalog.FLOOR_LIMIT):
			return false
		if not _is_nonempty_string(location_id) or key != "%d:%s" % [int(floor_number), location_id]:
			return false
		if typeof(record.get("collected")) != TYPE_BOOL:
			return false
		var item = record.get("item")
		if not _is_valid_equipment_item(item):
			return false
		var instance_id: String = item["instance_id"]
		if seen_instance_ids.has(instance_id):
			return false
		seen_instance_ids[instance_id] = true
		if int(item["floor_found"]) != int(floor_number):
			return false
	return true


func _validate_equipped(equipped: Dictionary, inventory: Array) -> bool:
	var inventory_by_id := {}
	for item in inventory:
		inventory_by_id[item["instance_id"]] = item
	for slot in equipped:
		if typeof(slot) != TYPE_STRING or slot not in ["weapon", "armor", "relic"]:
			return false
		var instance_id = equipped[slot]
		if not _is_nonempty_string(instance_id) or not inventory_by_id.has(instance_id):
			return false
		if inventory_by_id[instance_id]["slot"] != slot:
			return false
	return true


func _validate_rare_spawn_history(history: Array, counts: Dictionary, floor_loot: Dictionary) -> bool:
	var observed_counts := {}
	var seen_spawn_ids := {}
	for spawn in history:
		if typeof(spawn) != TYPE_DICTIONARY:
			return false
		var floor_number = spawn.get("floor")
		var location_id = spawn.get("location_id")
		var interval = spawn.get("interval")
		var instance_id = spawn.get("instance_id")
		if not _is_integer_in_range(floor_number, 1, TowerProgressionCatalog.FLOOR_LIMIT):
			return false
		if not _is_nonempty_string(location_id) or not _is_nonempty_string(instance_id):
			return false
		if not _is_valid_rare_interval(interval) or interval != RareSpawnRules.interval_key(int(floor_number)):
			return false
		if seen_spawn_ids.has(instance_id):
			return false
		seen_spawn_ids[instance_id] = true
		var loot_key = "%d:%s" % [int(floor_number), location_id]
		if not floor_loot.has(loot_key):
			return false
		var item: Dictionary = floor_loot[loot_key].get("item", {})
		if item.get("instance_id", "") != instance_id or item.get("rarity", "") != "rare":
			return false
		observed_counts[interval] = int(observed_counts.get(interval, 0)) + 1
	for record in floor_loot.values():
		var item: Dictionary = record["item"]
		if item["rarity"] == "rare" and not seen_spawn_ids.has(item["instance_id"]):
			return false
	for interval in counts:
		if int(counts[interval]) != int(observed_counts.get(interval, 0)):
			return false
	for interval in observed_counts:
		if int(counts.get(interval, -1)) != int(observed_counts[interval]):
			return false
	return true


func _validate_journal(journal: Dictionary) -> bool:
	for discovery_id in journal:
		if not _is_nonempty_string(discovery_id):
			return false
		var entry = journal[discovery_id]
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		if not _is_integer_in_range(entry.get("floor"), 1, TowerProgressionCatalog.FLOOR_LIMIT):
			return false
		if not _is_integer_in_range(entry.get("stage"), 0, 3):
			return false
		if not _is_nonempty_string(entry.get("region")) or typeof(entry.get("text")) != TYPE_STRING:
			return false
	return true


func _is_valid_equipment_item(item: Variant) -> bool:
	if typeof(item) != TYPE_DICTIONARY:
		return false
	if not _is_nonempty_string(item.get("instance_id")):
		return false
	if not _is_nonempty_string(item.get("id")) or not _is_nonempty_string(item.get("name")):
		return false
	if item.get("slot") not in ["weapon", "armor", "relic"]:
		return false
	if item.get("rarity") not in ["common", "unusual", "rare"]:
		return false
	if not _is_integer_in_range(item.get("attack"), 0, 1000000):
		return false
	if not _is_integer_in_range(item.get("defense"), 0, 1000000):
		return false
	if not _is_integer_in_range(item.get("floor_found"), 1, TowerProgressionCatalog.FLOOR_LIMIT):
		return false
	return typeof(item.get("effect")) == TYPE_STRING


func _is_valid_rare_interval(interval: Variant) -> bool:
	if typeof(interval) != TYPE_STRING:
		return false
	for start_floor in range(1, TowerProgressionCatalog.FLOOR_LIMIT + 1, 10):
		if interval == "%d-%d" % [start_floor, start_floor + 9]:
			return true
	return false


func _is_nonempty_string(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	return not String(value).is_empty()


func _normalize_integral_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0:
				return int(value)
			return value
		TYPE_ARRAY:
			var normalized_array := []
			for element in value:
				normalized_array.append(_normalize_integral_numbers(element))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary := {}
			for key in value:
				normalized_dictionary[key] = _normalize_integral_numbers(value[key])
			return normalized_dictionary
	return value


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) != TYPE_FLOAT or not is_finite(value):
		return false
	return value >= minimum and value <= maximum and value == floor(value)
