extends RefCounted
class_name ShopCatalog

# The Tower's quartermaster: equipment bought with gems. Each entry unlocks
# once the player has reached its floor and can be bought a limited number of
# times. Rare equipment is never sold, so the "two rare finds per ten floors"
# rule stays a property of exploration.
#
# Keys: item (EquipmentCatalog id), price (gems), unlock_floor, limit.

const STOCK := [
	{"item": "copper_knife", "price": 200, "unlock_floor": 1, "limit": 1},
	{"item": "rusted_sabre", "price": 250, "unlock_floor": 1, "limit": 1},
	{"item": "pilgrim_mail", "price": 400, "unlock_floor": 1, "limit": 1},
	{"item": "wayfarer_blade", "price": 450, "unlock_floor": 3, "limit": 1},
	{"item": "broken_compass", "price": 350, "unlock_floor": 5, "limit": 1},
	{"item": "quiet_steps", "price": 900, "unlock_floor": 8, "limit": 1},
	{"item": "mossmantle", "price": 1100, "unlock_floor": 12, "limit": 1},
	{"item": "echo_lantern", "price": 1000, "unlock_floor": 15, "limit": 1},
	{"item": "deep_delver", "price": 1300, "unlock_floor": 20, "limit": 1},
	{"item": "ironwood_bow", "price": 1600, "unlock_floor": 25, "limit": 1}
]


static func get_entry(item_id: String) -> Dictionary:
	for entry in STOCK:
		if entry["item"] == item_id:
			return entry.duplicate(true)
	return {}
