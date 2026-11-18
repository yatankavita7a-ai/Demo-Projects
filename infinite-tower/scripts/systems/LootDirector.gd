extends Node

signal loot_spawned(floor_number: int, location_id: String, item: Dictionary)

const EquipmentCatalog = preload("res://scripts/systems/EquipmentCatalog.gd")
const RareLootRules = preload("res://scripts/systems/RareLootRules.gd")
const TowerProgressionCatalog = preload("res://scripts/systems/TowerCatalog.gd")

var _mutex := Mutex.new()


func generate_hidden_equipment(floor_number: int, location_id: String) -> Dictionary:
	if floor_number < 1 or floor_number > TowerProgressionCatalog.FLOOR_LIMIT or location_id.is_empty():
		return {}
	_mutex.lock()
	var result = _generate_locked(floor_number, location_id)
	_mutex.unlock()
	if not result.is_empty() and result.get("newly_generated", false):
		var item: Dictionary = result["item"]
		loot_spawned.emit(floor_number, location_id, item.duplicate(true))
		result.erase("newly_generated")
	return result


func _generate_locked(floor_number: int, location_id: String) -> Dictionary:
	var candidate = PlayerData.get_state()
	var key = "%d:%s" % [floor_number, location_id]
	var floor_loot: Dictionary = candidate["floor_loot"]
	if floor_loot.has(key):
		return floor_loot[key].duplicate(true)

	var interval = RareLootRules.interval_key(floor_number)
	var counts: Dictionary = candidate["rare_interval_counts"]
	var rare_count = int(counts.get(interval, 0))
	var world_seed = int(candidate["world_seed"])
	var seed_key = "%d|%d|%s" % [world_seed, floor_number, location_id]
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_key.hash()
	var rarity = RareLootRules.choose_rarity(rng.randf() * 100.0, rare_count)
	var item = EquipmentCatalog.roll_item(rarity, rng.randi())
	if item.is_empty():
		return {}
	item["instance_id"] = "gear_v2_%d_%d_%d_%s" % [
		world_seed,
		floor_number,
		location_id.length(),
		location_id
	]
	item["floor_found"] = floor_number
	var record = {
		"floor": floor_number,
		"location_id": location_id,
		"item": item,
		"collected": false
	}
	floor_loot[key] = record
	candidate["floor_loot"] = floor_loot
	if rarity == "rare":
		counts[interval] = rare_count + 1
		candidate["rare_interval_counts"] = counts
		var history: Array = candidate["rare_spawn_history"]
		history.append({
			"interval": interval,
			"floor": floor_number,
			"location_id": location_id,
			"instance_id": item["instance_id"]
		})
		candidate["rare_spawn_history"] = history
	if not PlayerData.replace_state(candidate):
		return {}
	record["newly_generated"] = true
	return record.duplicate(true)


func collect_hidden_equipment(floor_number: int, location_id: String) -> bool:
	_mutex.lock()
	var candidate = PlayerData.get_state()
	var key = "%d:%s" % [floor_number, location_id]
	var floor_loot: Dictionary = candidate["floor_loot"]
	if not floor_loot.has(key) or floor_loot[key].get("collected", false):
		_mutex.unlock()
		return false
	var record: Dictionary = floor_loot[key]
	var inventory: Array = candidate["inventory"]
	inventory.append(record["item"].duplicate(true))
	record["collected"] = true
	floor_loot[key] = record
	candidate["floor_loot"] = floor_loot
	candidate["inventory"] = inventory
	var saved = PlayerData.replace_state(candidate)
	_mutex.unlock()
	return saved


func equip_item(instance_id: String) -> bool:
	var candidate = PlayerData.get_state()
	var inventory: Array = candidate["inventory"]
	for item in inventory:
		if item.get("instance_id", "") == instance_id:
			var equipped: Dictionary = candidate["equipped"]
			equipped[item["slot"]] = instance_id
			candidate["equipped"] = equipped
			return PlayerData.replace_state(candidate)
	return false


# Rares the player has actually collected in this floor's interval. Unlike
# interval_rare_count, this does not reveal rares that spawned but are unfound.
func interval_rares_found(floor_number: int) -> int:
	var interval = RareLootRules.interval_key(floor_number)
	if interval.is_empty():
		return 0
	var found := 0
	for record in PlayerData.get_state()["floor_loot"].values():
		var item: Dictionary = record.get("item", {})
		if (
			record.get("collected", false)
			and item.get("rarity", "") == "rare"
			and RareLootRules.interval_key(int(record.get("floor", 0))) == interval
		):
			found += 1
	return found


func interval_rare_count(floor_number: int) -> int:
	var interval = RareLootRules.interval_key(floor_number)
	if interval.is_empty():
		return 0
	return int(PlayerData.get_state()["rare_interval_counts"].get(interval, 0))
