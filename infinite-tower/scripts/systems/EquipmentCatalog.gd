extends RefCounted

const EQUIPMENT := [
	{"id": "rusted_sabre", "name": "Rusted Sabre", "slot": "weapon", "rarity": "common", "attack": 3, "defense": 0, "effect": "Reliable, if worn."},
	{"id": "wayfarer_blade", "name": "Wayfarer's Blade", "slot": "weapon", "rarity": "common", "attack": 5, "defense": 0, "effect": "A balanced traveler's weapon."},
	{"id": "ironwood_bow", "name": "Ironwood Bow", "slot": "weapon", "rarity": "unusual", "attack": 8, "defense": 0, "effect": "Heavy attacks become ranged shots that stagger foes."},
	{"id": "pilgrim_mail", "name": "Pilgrim's Mail", "slot": "armor", "rarity": "common", "attack": 0, "defense": 4, "effect": "Worn through a hundred miles."},
	{"id": "mossmantle", "name": "Mossmantle", "slot": "armor", "rarity": "unusual", "attack": 0, "defense": 6, "effect": "Recover stamina faster near ruined cover."},
	{"id": "glassward", "name": "Glassward Charm", "slot": "relic", "rarity": "rare", "attack": 2, "defense": 2, "effect": "Perfect dodges briefly reveal nearby hidden caches."},
	{"id": "embersong", "name": "Embersong", "slot": "weapon", "rarity": "rare", "attack": 13, "defense": 0, "effect": "Heavy strikes ignite foes, but cost extra stamina."},
	{"id": "quiet_steps", "name": "Quiet-Step Wraps", "slot": "armor", "rarity": "unusual", "attack": 0, "defense": 3, "effect": "Enemies notice you from a shorter distance."},
	{"id": "broken_compass", "name": "Broken Compass", "slot": "relic", "rarity": "common", "attack": 0, "defense": 1, "effect": "Its needle points toward nearby secrets, sometimes."},
	{"id": "thorn_circlet", "name": "Thorn Circlet", "slot": "relic", "rarity": "rare", "attack": 0, "defense": 5, "effect": "Blocking restores health, but blocks cost more stamina."},
	{"id": "copper_knife", "name": "Copper Knife", "slot": "weapon", "rarity": "common", "attack": 2, "defense": 0, "effect": "Small, quick, and easy to replace."},
	{"id": "deep_delver", "name": "Deep-Delver Coat", "slot": "armor", "rarity": "unusual", "attack": 0, "defense": 5, "effect": "Dense layers blunt incoming blows."},
	{"id": "echo_lantern", "name": "Echo Lantern", "slot": "relic", "rarity": "unusual", "attack": 0, "defense": 2, "effect": "Hidden caches stir when you are close."}
]

static func get_item(item_id: String) -> Dictionary:
	for item in EQUIPMENT:
		if item["id"] == item_id:
			return item.duplicate(true)
	return {}


static func roll_item(rarity: String, seed_value: int) -> Dictionary:
	var choices: Array = []
	for item in EQUIPMENT:
		if item["rarity"] == rarity:
			choices.append(item)
	if choices.is_empty():
		return {}
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return choices[rng.randi_range(0, choices.size() - 1)].duplicate(true)
