extends RefCounted
class_name RareLootRules

const MAX_RARE_SPAWNS_PER_INTERVAL := 2


static func choose_rarity(roll: float, rare_count: int) -> String:
	if roll < 3.0:
		if rare_count < MAX_RARE_SPAWNS_PER_INTERVAL:
			return "rare"
		return "unusual"
	if roll < 28.0:
		return "unusual"
	return "common"


static func interval_key(floor_number: int) -> String:
	var first_floor = TowerCatalog.rare_interval_start(floor_number)
	if first_floor == 0:
		return ""
	return "%d-%d" % [first_floor, first_floor + 9]
