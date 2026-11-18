extends Node

const HeroDatabase = preload("res://data/HeroDatabase.gd")

const SAVE_PATH = "user://save_game.json"
# Copy of the previous good save, refreshed before every successful write.
const BACKUP_SAVE_PATH = "user://save_game.backup.json"
const LOAD_OK = 0
const LOAD_CORRUPT = 1
const LOAD_UNREADABLE = 2
const LOAD_UNSUPPORTED = 3
const LOAD_FAILED = 4
const SAVE_VERSION = 2
const INSTANCE_ID_PREFIX = "hero_"
const MAX_SAFE_JSON_INTEGER = 9007199254740991

signal currency_changed
signal heroes_changed

var gems = 3000
var hero_instances: Array = []
var next_instance_id: int = 1
var legacy_owned_heroes: Dictionary = {}
var legacy_save_data: Dictionary = {}
var save_data_writable = false
# Player-facing explanation when the save had to be recovered or is locked.
var load_warning := ""
# True only once the file at SAVE_PATH is known to be a valid save, so a
# damaged file is never copied over the backup.
var _save_file_is_valid := false
var owned_claim_tokens: Dictionary = {}
var _save_mutex := Mutex.new()

var rng = RandomNumberGenerator.new()


func _ready():
	rng.randomize()
	if not load_game():
		push_error("Could not load or initialize the player save.")

	print("TOTAL HEROES: ", HeroDatabase.get_heroes().size())
	print("ONE STAR HEROES: ", HeroDatabase.get_heroes_by_rarity(1).size())
	print("SEVEN STAR HEROES: ", HeroDatabase.get_heroes_by_rarity(7).size())


func get_random_rarity():
	_save_mutex.lock()
	var rarity = _get_random_rarity_locked()
	_save_mutex.unlock()
	return rarity


func _get_random_rarity_locked() -> int:
	var chance = rng.randf() * 100.0

	if chance < 0.001:
		return 7
	elif chance < 0.201:
		return 6
	elif chance < 1.001:
		return 5
	elif chance < 9.0:
		return 4
	elif chance < 25.0:
		return 3
	elif chance < 55.0:
		return 2
	else:
		return 1


# Summon sizes and the highest reached floor that unlocks each one. Every
# hero in a pull costs the same, so smaller pulls are a convenience, not a
# discount.
const GEMS_PER_SUMMON = 100
# Per-hero price by highest reached floor: summoning costs more as the
# player climbs (and earns more gems per floor). Highest threshold first.
const SUMMON_PRICE_TIERS = [[40, 150], [20, 120], [1, 100]]
const SUMMON_SIZE_UNLOCK_FLOORS = {10: 1, 5: 20, 2: 40}
const TOWER_STATE_DOMAIN = "tower_player_state"


func summon_ten():
	return summon(10)


func summon(count: int) -> Array:
	_save_mutex.lock()
	var results = _summon_locked(count)
	_save_mutex.unlock()
	if not results.is_empty():
		currency_changed.emit()
		heroes_changed.emit()
	return results


func summon_cost(count: int) -> int:
	_save_mutex.lock()
	var cost = count * _price_per_hero_locked()
	_save_mutex.unlock()
	return cost


func _price_per_hero_locked() -> int:
	var highest = _highest_reached_floor_locked()
	for tier in SUMMON_PRICE_TIERS:
		if highest >= int(tier[0]):
			return int(tier[1])
	return GEMS_PER_SUMMON


func is_summon_size_unlocked(count: int) -> bool:
	_save_mutex.lock()
	var unlocked = _is_summon_size_unlocked_locked(count)
	_save_mutex.unlock()
	return unlocked


func _is_summon_size_unlocked_locked(count: int) -> bool:
	if not SUMMON_SIZE_UNLOCK_FLOORS.has(count):
		return false
	return _highest_reached_floor_locked() >= int(SUMMON_SIZE_UNLOCK_FLOORS[count])


func _highest_reached_floor_locked() -> int:
	var tower_state = _get_persistent_domain_locked(TOWER_STATE_DOMAIN, {})
	if typeof(tower_state) != TYPE_DICTIONARY:
		return 1
	var highest = tower_state.get("highest_unlocked_floor", 1)
	return int(highest) if _is_safe_integral_number(highest) else 1


func _summon_locked(count: int) -> Array:
	if not save_data_writable:
		push_error("Summoning is unavailable because the player save is not valid.")
		return []
	if not _is_summon_size_unlocked_locked(count):
		push_error("A %d-hero summon is not unlocked yet." % count)
		return []
	var cost = summon_cost(count)
	if gems < cost:
		print("Not enough gems!")
		return []

	var candidate_gems = gems - cost
	var candidate_instances = hero_instances.duplicate(true)
	var candidate_next_instance_id = next_instance_id
	var used_ids = {}
	for instance in candidate_instances:
		used_ids[instance["instance_id"]] = true

	var results = []

	for i in range(count):
		var rarity = _get_random_rarity_locked()
		var available_heroes = HeroDatabase.get_heroes_by_rarity(rarity)

		if available_heroes.is_empty():
			# Abort without charging rather than taking full price for fewer
			# heroes. Nothing has been persisted yet.
			push_error("No heroes are available for rarity: %s" % rarity)
			return []

		var index = rng.randi_range(0, available_heroes.size() - 1)
		var hero = available_heroes[index]

		results.append(hero.duplicate(true))

		var new_instance = _make_hero_instance(
			hero["id"], used_ids, candidate_next_instance_id
		)
		candidate_instances.append(new_instance["instance"])
		candidate_next_instance_id = new_instance["next_instance_id"]

	var candidate_save = _build_save_data(
		candidate_gems,
		candidate_instances,
		candidate_next_instance_id,
		legacy_owned_heroes,
		legacy_save_data
	)
	if not _persist_save_data(candidate_save):
		push_error("Summon results could not be saved.")
		return []

	gems = candidate_gems
	hero_instances = candidate_instances
	next_instance_id = candidate_next_instance_id

	return results


func get_gem_balance() -> int:
	_save_mutex.lock()
	var result = gems
	_save_mutex.unlock()
	return result


func get_owned_counts() -> Dictionary:
	_save_mutex.lock()
	var counts = {}
	for instance in hero_instances:
		var hero_id = instance["hero_id"]
		counts[hero_id] = int(counts.get(hero_id, 0)) + 1
	_save_mutex.unlock()
	return counts


func get_owned_hero_instances(hero_id: String = "") -> Array:
	_save_mutex.lock()
	var result = []
	for instance in hero_instances:
		if hero_id.is_empty() or instance["hero_id"] == hero_id:
			result.append(instance.duplicate(true))
	_save_mutex.unlock()
	return result


func get_hero_instance(instance_id: String) -> Dictionary:
	_save_mutex.lock()
	for instance in hero_instances:
		if instance["instance_id"] == instance_id:
			var result = instance.duplicate(true)
			_save_mutex.unlock()
			return result
	_save_mutex.unlock()
	return {}


func get_persistent_domain(domain: String, fallback: Variant = null) -> Variant:
	_save_mutex.lock()
	var result = _get_persistent_domain_locked(domain, fallback)
	_save_mutex.unlock()
	return result


func _get_persistent_domain_locked(domain: String, fallback: Variant) -> Variant:
	var domains = legacy_save_data.get("game_domains", {})
	if typeof(domains) != TYPE_DICTIONARY:
		return fallback
	return domains.get(domain, fallback)


func save_persistent_domain(domain: String, value: Variant) -> bool:
	_save_mutex.lock()
	var result = _save_persistent_domain_locked(domain, value)
	_save_mutex.unlock()
	return result


# Saves a domain and grants gems in one write, so a reward is never recorded
# without its progress (or the reverse).
func save_persistent_domain_with_gems(domain: String, value: Variant, gem_reward: int) -> bool:
	if gem_reward < 0:
		return false
	_save_mutex.lock()
	var result = _save_persistent_domain_locked(domain, value, gem_reward)
	_save_mutex.unlock()
	if result and gem_reward > 0:
		currency_changed.emit()
	return result


# Saves a domain and grants hero experience in one write (hub training).
# xp_gains maps instance ids to XP; heroes level up along the hub curve,
# capped at max_level. Returns {"saved": bool, "levels": {instance_id: level}}.
func save_persistent_domain_with_hero_xp(domain: String, value: Variant, xp_gains: Dictionary, curve_base: int, curve_step: int, max_level: int) -> Dictionary:
	_save_mutex.lock()
	var result := {}
	var candidate_instances = hero_instances.duplicate(true)
	for instance in candidate_instances:
		var gain = int(xp_gains.get(instance["instance_id"], 0))
		if gain <= 0:
			continue
		var level = int(instance["level"])
		var xp = int(instance["xp"]) + gain
		while level < max_level and xp >= curve_base + curve_step * (level - 1):
			xp -= curve_base + curve_step * (level - 1)
			level += 1
		if level >= max_level:
			xp = 0
		instance["level"] = level
		instance["xp"] = xp
		result[instance["instance_id"]] = level
	var saved = false
	if save_data_writable and not domain.is_empty():
		var candidate_legacy_data = legacy_save_data.duplicate(true)
		var domains = candidate_legacy_data.get("game_domains", {})
		if typeof(domains) == TYPE_DICTIONARY:
			domains[domain] = value.duplicate(true) if value is Array or value is Dictionary else value
			candidate_legacy_data["game_domains"] = domains
			var candidate_save = _build_save_data(gems, candidate_instances, next_instance_id, legacy_owned_heroes, candidate_legacy_data)
			if _persist_save_data(candidate_save):
				legacy_save_data = candidate_legacy_data
				hero_instances = candidate_instances
				saved = true
	_save_mutex.unlock()
	if saved and not result.is_empty():
		heroes_changed.emit()
	return {"saved": saved, "levels": result if saved else {}}


# Saves a domain and spends gems in one write: a purchase is either fully
# recorded (gems gone, item owned) or not at all.
func save_persistent_domain_spending_gems(domain: String, value: Variant, cost: int) -> bool:
	if cost < 0:
		return false
	_save_mutex.lock()
	var result = false
	if gems >= cost:
		result = _save_persistent_domain_locked(domain, value, -cost)
	_save_mutex.unlock()
	if result and cost > 0:
		currency_changed.emit()
	return result


func _save_persistent_domain_locked(domain: String, value: Variant, gem_reward: int = 0) -> bool:
	if not save_data_writable or domain.is_empty():
		return false
	var candidate_legacy_data = legacy_save_data.duplicate(true)
	var domains = candidate_legacy_data.get("game_domains", {})
	if typeof(domains) != TYPE_DICTIONARY:
		push_error("Player data domain storage is invalid; save was left unchanged.")
		return false
	domains[domain] = value.duplicate(true) if value is Array or value is Dictionary else value
	candidate_legacy_data["game_domains"] = domains
	# Clamp rather than refuse: progress must still save at the gem ceiling.
	var candidate_gems = mini(gems + gem_reward, MAX_SAFE_JSON_INTEGER)
	if candidate_gems < 0:
		return false
	var candidate_save = _build_save_data(
		candidate_gems,
		hero_instances,
		next_instance_id,
		legacy_owned_heroes,
		candidate_legacy_data
	)
	if not _persist_save_data(candidate_save):
		return false
	legacy_save_data = candidate_legacy_data
	gems = candidate_gems
	return true


func _make_hero_instance(hero_id: String, used_ids: Dictionary, starting_id: int) -> Dictionary:
	var candidate_id_number = max(1, starting_id)
	var instance_id = "hero_%d" % candidate_id_number
	while used_ids.has(instance_id):
		candidate_id_number += 1
		instance_id = "hero_%d" % candidate_id_number

	used_ids[instance_id] = true
	return {
		"instance": {
			"instance_id": instance_id,
			"hero_id": hero_id,
			"level": 1,
			"xp": 0
		},
		"next_instance_id": candidate_id_number + 1
	}


func save_game() -> bool:
	_save_mutex.lock()
	var result = _save_game_locked()
	_save_mutex.unlock()
	return result


func _save_game_locked() -> bool:
	if not save_data_writable:
		return false
	var save_data = _build_save_data(
		gems,
		hero_instances,
		next_instance_id,
		legacy_owned_heroes,
		legacy_save_data
	)
	return _persist_save_data(save_data)


func load_game() -> bool:
	_save_mutex.lock()
	var result = _load_game_locked()
	_save_mutex.unlock()
	return result


func _load_game_locked() -> bool:
	save_data_writable = false
	load_warning = ""
	_save_file_is_valid = false
	var main_exists = FileAccess.file_exists(SAVE_PATH)
	var status = LOAD_CORRUPT
	if main_exists:
		status = _read_save_file(SAVE_PATH, true)
		if status == LOAD_OK:
			_save_file_is_valid = true
			save_data_writable = true
			return true
	# Recover from the backup only when the save is missing or damaged. A save
	# from a newer version, or one that could not be opened, is left alone.
	var recoverable = not main_exists or status == LOAD_CORRUPT
	if recoverable and FileAccess.file_exists(BACKUP_SAVE_PATH):
		return _recover_from_backup(main_exists)
	if main_exists:
		load_warning = "Your save file could not be loaded. It has been left untouched and saving is disabled."
		return false

	var initial_save = _build_save_data(
		gems, hero_instances, next_instance_id,
		legacy_owned_heroes, legacy_save_data
	)
	if not _persist_save_data(initial_save):
		load_warning = "A new save file could not be created. Saving is disabled."
		return false
	save_data_writable = true
	return true


func _read_save_file(path: String, allow_migration: bool) -> int:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open the player save for reading.")
		return LOAD_UNREADABLE

	var parsed_data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed_data) != TYPE_DICTIONARY:
		push_error("Player save is not a valid JSON dictionary; it was left unchanged.")
		return LOAD_CORRUPT

	var version_value = parsed_data.get("save_version", 1)
	if not _is_safe_integral_number(version_value):
		push_error("Player save has an invalid version; it was left unchanged.")
		return LOAD_CORRUPT
	version_value = int(version_value)

	if version_value == SAVE_VERSION:
		return LOAD_OK if _load_versioned_save(parsed_data) else LOAD_CORRUPT
	if version_value == 1 and allow_migration:
		return LOAD_OK if _migrate_legacy_save(parsed_data) else LOAD_FAILED
	if version_value > SAVE_VERSION:
		push_error("Player save version is unsupported; it was left unchanged.")
		return LOAD_UNSUPPORTED
	return LOAD_CORRUPT


func _recover_from_backup(main_exists: bool) -> bool:
	# Check the backup first so an unrecoverable pair does not pile up a new
	# damaged-file copy on every launch.
	if _read_save_file(BACKUP_SAVE_PATH, false) != LOAD_OK:
		load_warning = "Your save file and its backup could not be loaded. Saving is disabled."
		return false
	if main_exists:
		var preserved = _preserve_damaged_save()
		if preserved.is_empty():
			load_warning = "Your save file is damaged and could not be set aside for recovery. Saving is disabled."
			return false
		print("Damaged save preserved at: ", preserved)
	# The damaged main file must not replace the good backup on this write.
	_save_file_is_valid = false
	var restored = _build_save_data(
		gems, hero_instances, next_instance_id,
		legacy_owned_heroes, legacy_save_data
	)
	if not _persist_save_data(restored):
		load_warning = "Your backup save was found but could not be restored. Saving is disabled."
		return false
	save_data_writable = true
	if main_exists:
		load_warning = "Your save file was damaged, so the most recent backup was restored. Your last action may have been lost."
	else:
		load_warning = "Your save file was missing, so the most recent backup was restored."
	return true


func _preserve_damaged_save() -> String:
	var target = "user://save_game.damaged.%d.json" % Time.get_unix_time_from_system()
	var attempt = 0
	while FileAccess.file_exists(target):
		attempt += 1
		target = "user://save_game.damaged.%d.%d.json" % [Time.get_unix_time_from_system(), attempt]
	var copy_error = DirAccess.copy_absolute(
		ProjectSettings.globalize_path(SAVE_PATH),
		ProjectSettings.globalize_path(target)
	)
	return target if copy_error == OK else ""


func get_load_warning() -> String:
	_save_mutex.lock()
	var warning = load_warning
	_save_mutex.unlock()
	return warning


func is_save_writable() -> bool:
	_save_mutex.lock()
	var writable = save_data_writable
	_save_mutex.unlock()
	return writable


func _load_versioned_save(data: Dictionary) -> bool:
	if not _validate_save_data(data):
		push_error("Player save failed validation; it was left unchanged.")
		return false

	gems = int(data["gems"])
	hero_instances = data["hero_instances"].duplicate(true)
	for instance in hero_instances:
		instance["level"] = int(instance["level"])
		instance["xp"] = int(instance["xp"])
	next_instance_id = int(data["next_instance_id"])
	legacy_owned_heroes = {}
	for hero_id in data["legacy_owned_heroes"]:
		legacy_owned_heroes[hero_id] = int(data["legacy_owned_heroes"][hero_id])
	legacy_save_data = data["legacy_save_data"].duplicate(true)
	return true


func _migrate_legacy_save(data: Dictionary) -> bool:
	var legacy_gems = data.get("gems", 3000)
	var old_owned_heroes = data.get("owned_heroes", {})
	var preserved_legacy = data.get("legacy_owned_heroes", {})
	if not _is_safe_integral_number(legacy_gems) or legacy_gems < 0:
		push_error("Legacy gem balance failed validation; save was left unchanged.")
		return false
	legacy_gems = int(legacy_gems)
	if typeof(old_owned_heroes) != TYPE_DICTIONARY:
		push_error("Legacy hero roster failed validation; save was left unchanged.")
		return false
	if typeof(preserved_legacy) != TYPE_DICTIONARY:
		push_error("Legacy preserved roster failed validation; save was left unchanged.")
		return false

	var known_heroes = {}
	for hero in HeroDatabase.get_heroes():
		known_heroes[hero["id"]] = true

	var migrated_instances = []
	var used_ids = {}
	var migrated_legacy = {}
	for preserved_hero_id in preserved_legacy:
		var preserved_count = preserved_legacy[preserved_hero_id]
		if not _is_safe_integral_number(preserved_count) or preserved_count < 0:
			push_error("Legacy preserved hero count failed validation; save was left unchanged.")
			return false
		migrated_legacy[preserved_hero_id] = int(preserved_count)
	var candidate_next_instance_id = 1

	for hero_id_value in old_owned_heroes:
		var hero_id = str(hero_id_value)
		var count = old_owned_heroes[hero_id_value]
		if not _is_safe_integral_number(count) or count < 0:
			push_error("Legacy hero count failed validation; save was left unchanged.")
			return false
		count = int(count)

		if not known_heroes.has(hero_id):
			migrated_legacy[hero_id] = count
			continue

		for copy_index in range(count):
			var new_instance = _make_hero_instance(
				hero_id, used_ids, candidate_next_instance_id
			)
			migrated_instances.append(new_instance["instance"])
			candidate_next_instance_id = new_instance["next_instance_id"]

	var migrated_legacy_data = {}
	for key in data:
		if key not in ["save_version", "gems", "owned_heroes", "legacy_owned_heroes"]:
			migrated_legacy_data[key] = data[key]

	var migrated_save = _build_save_data(
		legacy_gems,
		migrated_instances,
		candidate_next_instance_id,
		migrated_legacy,
		migrated_legacy_data
	)
	if not _validate_save_data(migrated_save):
		push_error("Migrated player save failed validation; original was left unchanged.")
		return false

	var backup_path = _create_legacy_backup()
	if backup_path.is_empty():
		push_error("Could not preserve the original save; migration was cancelled.")
		return false

	if not _persist_save_data(migrated_save):
		push_error("Could not save the migrated roster; original save was left unchanged.")
		return false

	gems = legacy_gems
	hero_instances = migrated_instances
	next_instance_id = candidate_next_instance_id
	legacy_owned_heroes = migrated_legacy
	legacy_save_data = migrated_legacy_data
	print("Original save backed up to: ", backup_path)
	return true


func _create_legacy_backup() -> String:
	for attempt in range(1000):
		var backup_path = "user://save_game.json.v1"
		if attempt > 0:
			backup_path += ".%d" % attempt
		backup_path += ".bak"

		if _path_exists(backup_path):
			continue

		# An exclusively created directory gives this migration ownership of
		# the staging area before it copies or cleans up any backup data.
		var claim_path = backup_path + ".claim"
		if _claim_backup_directory(claim_path).is_empty():
			continue

		if _path_exists(backup_path):
			_release_backup_claim(claim_path)
			continue

		var staged_path = claim_path + "/save_game.json"
		if _path_exists(staged_path):
			_release_backup_claim(claim_path)
			continue

		var copy_error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(staged_path)
		)
		if copy_error != OK:
			_cleanup_attempt_file(staged_path, "backup staging")
			_release_backup_claim(claim_path)
			return ""

		if FileAccess.get_file_as_bytes(SAVE_PATH) != FileAccess.get_file_as_bytes(staged_path):
			_cleanup_attempt_file(staged_path, "backup staging")
			_release_backup_claim(claim_path)
			return ""

		if _path_exists(backup_path):
			_cleanup_attempt_file(staged_path, "backup staging")
			_release_backup_claim(claim_path)
			continue

		var rename_error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(staged_path),
			ProjectSettings.globalize_path(backup_path)
		)
		if rename_error != OK:
			_cleanup_attempt_file(staged_path, "backup staging")
			_release_backup_claim(claim_path)
			return ""

		_release_backup_claim(claim_path)
		return backup_path

	return ""


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(path)
	)


func _claim_backup_directory(claim_path: String) -> String:
	if _path_exists(claim_path):
		return ""

	var claim_absolute = ProjectSettings.globalize_path(claim_path)
	if DirAccess.make_dir_absolute(claim_absolute) != OK:
		return ""

	var token = "%d-%d-%d" % [Time.get_ticks_usec(), get_instance_id(), rng.randi()]
	var owner_path = claim_path.path_join(".owner")
	var owner_file = FileAccess.open(owner_path, FileAccess.WRITE)
	if owner_file == null:
		DirAccess.remove_absolute(claim_absolute)
		return ""
	owner_file.store_string(token)
	owner_file.flush()
	var write_error = owner_file.get_error()
	owner_file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(owner_path))
		DirAccess.remove_absolute(claim_absolute)
		return ""

	owned_claim_tokens[claim_path] = token
	return token


func _owns_backup_claim(claim_path: String) -> bool:
	if not owned_claim_tokens.has(claim_path):
		return false

	var owner_path = claim_path.path_join(".owner")
	var owner_file = FileAccess.open(owner_path, FileAccess.READ)
	if owner_file == null:
		return false
	var stored_token = owner_file.get_as_text()
	owner_file.close()
	return stored_token == owned_claim_tokens[claim_path]


func _release_backup_claim(claim_path: String) -> void:
	if not _owns_backup_claim(claim_path):
		owned_claim_tokens.erase(claim_path)
		return

	var claim_absolute = ProjectSettings.globalize_path(claim_path)
	var owner_path = ProjectSettings.globalize_path(claim_path.path_join(".owner"))
	var owner_remove_error = DirAccess.remove_absolute(owner_path)
	if owner_remove_error != OK:
		push_error("Could not remove the owned backup claim marker.")
		return

	var remove_error = DirAccess.remove_absolute(claim_absolute)
	if remove_error != OK:
		push_error("Could not release the owned backup claim directory.")
		return
	owned_claim_tokens.erase(claim_path)


func _build_save_data(
		gems_value: int,
		instances_value: Array,
		next_id_value: int,
		legacy_owned_value: Dictionary,
		legacy_data_value: Dictionary
	) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"gems": gems_value,
		"hero_instances": instances_value.duplicate(true),
		"next_instance_id": next_id_value,
		"legacy_owned_heroes": legacy_owned_value.duplicate(true),
		"legacy_save_data": legacy_data_value.duplicate(true)
	}


func _validate_save_data(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not _is_safe_integral_number(data.get("save_version")) or int(data["save_version"]) != SAVE_VERSION:
		return false
	if not _is_safe_integral_number(data.get("gems")) or data["gems"] < 0:
		return false
	if typeof(data.get("hero_instances")) != TYPE_ARRAY:
		return false
	if not _is_safe_integral_number(data.get("next_instance_id")) or data["next_instance_id"] < 1:
		return false
	if typeof(data.get("legacy_owned_heroes")) != TYPE_DICTIONARY:
		return false
	if typeof(data.get("legacy_save_data")) != TYPE_DICTIONARY:
		return false

	for legacy_count in data["legacy_owned_heroes"].values():
		if not _is_safe_integral_number(legacy_count) or legacy_count < 0:
			return false

	var seen_ids = {}
	var highest_generated_id = 0
	for instance in data["hero_instances"]:
		if typeof(instance) != TYPE_DICTIONARY:
			return false
		var instance_id = instance.get("instance_id", "")
		var hero_id = instance.get("hero_id", "")
		var level = instance.get("level", null)
		var xp = instance.get("xp", null)
		if typeof(instance_id) != TYPE_STRING or instance_id.is_empty():
			return false
		if seen_ids.has(instance_id):
			return false
		var generated_id_number = _get_generated_id_number(instance_id)
		if generated_id_number < 1:
			return false
		if typeof(hero_id) != TYPE_STRING or hero_id.is_empty():
			return false
		if not _is_safe_integral_number(level) or level < 1:
			return false
		if not _is_safe_integral_number(xp) or xp < 0:
			return false
		seen_ids[instance_id] = true
		highest_generated_id = max(highest_generated_id, generated_id_number)

	return data["next_instance_id"] > highest_generated_id


func _is_safe_integral_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= -MAX_SAFE_JSON_INTEGER and value <= MAX_SAFE_JSON_INTEGER
	if typeof(value) != TYPE_FLOAT or not is_finite(value):
		return false
	if value < -MAX_SAFE_JSON_INTEGER or value > MAX_SAFE_JSON_INTEGER:
		return false
	return value == floor(value)


func _get_generated_id_number(instance_id: String) -> int:
	if not instance_id.begins_with(INSTANCE_ID_PREFIX):
		return -1
	var number_text = instance_id.substr(INSTANCE_ID_PREFIX.length())
	if not number_text.is_valid_int():
		return -1
	var number = int(number_text)
	if number < 1 or str(number) != number_text:
		return -1
	return number


func _persist_save_data(data: Dictionary) -> bool:
	if not _validate_save_data(data):
		push_error("Refusing to write invalid player save data.")
		return false

	var temp_path = _make_temp_save_path()
	if temp_path.is_empty():
		push_error("Could not claim a unique temporary player save directory.")
		return false
	var temp_claim_path = temp_path.get_base_dir()
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_release_backup_claim(temp_claim_path)
		push_error("Could not open temporary player save for writing.")
		return false

	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		_cleanup_attempt_file(temp_path, "temporary save")
		_release_backup_claim(temp_claim_path)
		push_error("Could not finish writing temporary player save.")
		return false

	var verify_file = FileAccess.open(temp_path, FileAccess.READ)
	if verify_file == null:
		_cleanup_attempt_file(temp_path, "temporary save")
		_release_backup_claim(temp_claim_path)
		push_error("Could not reopen temporary player save for validation.")
		return false
	var verified_data = JSON.parse_string(verify_file.get_as_text())
	verify_file.close()
	if not _validate_save_data(verified_data):
		_cleanup_attempt_file(temp_path, "temporary save")
		_release_backup_claim(temp_claim_path)
		push_error("Temporary player save failed validation.")
		return false

	# Keep the previous good save as a backup before replacing it. If the
	# replace below is interrupted, loading restores from this copy.
	if _save_file_is_valid and FileAccess.file_exists(SAVE_PATH):
		var backup_error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
		)
		if backup_error != OK:
			push_warning("Could not refresh the backup save.")

	var rename_error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if rename_error != OK:
		_cleanup_attempt_file(temp_path, "temporary save")
		_release_backup_claim(temp_claim_path)
		push_error("Could not replace player save with the validated save.")
		return false
	_release_backup_claim(temp_claim_path)
	_save_file_is_valid = true
	return true


func _cleanup_attempt_file(path: String, artifact_name: String) -> void:
	if not _owns_backup_claim(path.get_base_dir()):
		return
	if not FileAccess.file_exists(path):
		return
	var remove_error = DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
	if remove_error != OK:
		push_error("Could not clean up the failed " + artifact_name + " artifact.")


func _make_temp_save_path() -> String:
	for attempt in range(1000):
		var suffix = str(Time.get_ticks_usec())
		if attempt > 0:
			suffix += ".%d" % attempt
		var claim_path = SAVE_PATH + ".tmp." + suffix + ".claim"
		if _claim_backup_directory(claim_path).is_empty():
			continue

		var candidate = claim_path.path_join("save_game.json")
		if _path_exists(candidate):
			_release_backup_claim(claim_path)
			continue
		return candidate
	return ""
