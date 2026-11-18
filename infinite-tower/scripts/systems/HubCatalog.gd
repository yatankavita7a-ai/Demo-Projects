extends RefCounted
class_name HubCatalog

# The Master's camp at the foot of the Tower. Heroes live here, work jobs
# while the player is offline, and the camp grows as buildings are built and
# upgraded with materials.
#
# Offline time is measured in real seconds between visits and capped, so a
# long absence is rewarded without breaking the economy.

const MAX_BUILDING_LEVEL := 3
const OFFLINE_CAP_HOURS := 12.0
const MAX_HERO_LEVEL := 30

# costs[i] = materials needed to reach level i + 1. start_level 0 means the
# building must be constructed first.
const BUILDINGS := {
	"barracks": {
		"name": "Barracks", "job": "rest", "start_level": 1, "costs": [0, 60, 160],
		"description": "Where your heroes live. More levels house more heroes and raise the rest bonus your hero brings into the next climb."
	},
	"training_grounds": {
		"name": "Training Grounds", "job": "training", "start_level": 1, "costs": [0, 80, 200],
		"description": "Heroes assigned here gain experience while you are away. Upgrades speed up training."
	},
	"quarry": {
		"name": "Quarry and Lumber Yard", "job": "miner", "start_level": 0, "costs": [40, 100, 220],
		"description": "Miners and lumberjacks gather the materials used to build and upgrade the camp."
	},
	"scout_hall": {
		"name": "Scout Hall", "job": "scout", "start_level": 0, "costs": [80, 160, 300],
		"description": "Send a hero on a timed expedition. They return with materials and sometimes equipment (never rare)."
	}
}

# Sanctuary works: one-time projects that turn the crude broken island into
# a fortified sanctuary as the player climbs. Each unlocks at a floor, costs
# materials and grants a small permanent perk.
const IMPROVEMENTS := {
	"courtyard": {"name": "Stone Courtyard", "cost": 60, "unlock_floor": 1,
		"description": "Pave the camp's heart. Heroes keep working 2 hours longer while you're away."},
	"gardens": {"name": "Garden Terraces", "cost": 120, "unlock_floor": 5,
		"description": "Lawns and blossom trees. Raises the rest bonus cap by 10%."},
	"walls": {"name": "Sanctuary Walls", "cost": 220, "unlock_floor": 10,
		"description": "White stone walls and towers around the island. Miners gather 15% more materials."},
	"rune_circle": {"name": "Rune Circle", "cost": 300, "unlock_floor": 15,
		"description": "Glowing rune plazas that focus the mind. Training is 15% faster."},
	"arena": {"name": "Sparring Arena", "cost": 380, "unlock_floor": 20,
		"description": "A sand arena for drills. Training is a further 15% faster."},
	"barrier": {"name": "Barrier Dome", "cost": 600, "unlock_floor": 30,
		"description": "A shimmering shield over the sanctuary. Heroes keep working 4 hours longer while you're away."}
}

# Jobs; classes listed work 25% faster.
const JOBS := {
	"rest": {"name": "Resting", "classes": []},
	"training": {"name": "Training", "classes": ["Warrior"]},
	"miner": {"name": "Miner / Lumberjack", "classes": ["Tank", "Warrior"]},
	"scout": {"name": "Scout", "classes": ["Assassin", "Archer"]}
}

const BARRACKS_CAPACITY := [0, 4, 6, 8]
const REST_BONUS_CAP := [0, 20, 30, 40]
const REST_BONUS_PER_HOUR := 5.0
const TRAINING_XP_PER_HOUR := 40.0
const MINER_MATERIALS_PER_HOUR := 6.0
const EXPEDITION_HOURS := [2, 4, 8]
const AFFINITY_BONUS := 1.25

# Materials for a first clear of a floor; Guardians yield more.
const FLOOR_MATERIALS := 20
const BOSS_FLOOR_MATERIALS := 80


static func default_hub() -> Dictionary:
	var buildings := {}
	for id in BUILDINGS:
		buildings[id] = int(BUILDINGS[id]["start_level"])
	for id in IMPROVEMENTS:
		buildings[id] = 0
	return {
		"materials": 0,
		"buildings": buildings,
		"residents": {},
		"expeditions": {},
		"last_tick": 0,
		"rest_bonus": 0
	}


static func xp_to_next(level: int) -> int:
	return 100 + 50 * (maxi(level, 1) - 1)


static func upgrade_cost(building_id: String, current_level: int) -> int:
	var building: Dictionary = BUILDINGS.get(building_id, {})
	if building.is_empty() or current_level >= MAX_BUILDING_LEVEL:
		return -1
	return int(building["costs"][current_level])


static func has_improvement(hub: Dictionary, improvement_id: String) -> bool:
	return int(hub.get("buildings", {}).get(improvement_id, 0)) > 0


static func offline_cap_hours(hub: Dictionary) -> float:
	var cap = OFFLINE_CAP_HOURS
	if has_improvement(hub, "courtyard"):
		cap += 2.0
	if has_improvement(hub, "barrier"):
		cap += 4.0
	return cap


static func affinity(job: String, hero_class: String) -> float:
	return AFFINITY_BONUS if hero_class in JOBS.get(job, {}).get("classes", []) else 1.0


# Advances the camp by the real time elapsed since its last tick.
# hero_classes maps resident instance ids to their class. Returns:
#   hub        - the updated hub dictionary
#   xp         - {instance_id: xp gained}
#   items      - equipment found by returning scouts
#   materials  - materials gained
#   hours      - offline hours counted (after the cap)
static func tick(hub_in: Dictionary, hero_classes: Dictionary, selected_id: String, now: int, seed_value: int) -> Dictionary:
	var hub: Dictionary = hub_in.duplicate(true)
	var result := {"hub": hub, "xp": {}, "items": [], "materials": 0, "hours": 0.0}
	var last = int(hub.get("last_tick", 0))
	hub["last_tick"] = now
	if last <= 0 or now <= last:
		return result
	var hours = minf(float(now - last) / 3600.0, offline_cap_hours(hub))
	var training_bonus = 1.0 + (0.15 if has_improvement(hub, "rune_circle") else 0.0) + (0.15 if has_improvement(hub, "arena") else 0.0)
	var material_bonus = 1.15 if has_improvement(hub, "walls") else 1.0
	var rest_cap_bonus = 10 if has_improvement(hub, "gardens") else 0
	result["hours"] = hours
	var buildings: Dictionary = hub["buildings"]
	var materials := 0.0
	for instance_id in hub["residents"]:
		var job: String = hub["residents"][instance_id]
		var hero_class: String = hero_classes.get(instance_id, "")
		var rate = affinity(job, hero_class)
		match job:
			"training":
				var level = int(buildings.get("training_grounds", 0))
				if level > 0:
					result["xp"][instance_id] = int(TRAINING_XP_PER_HOUR * hours * (0.5 + 0.5 * level) * rate * training_bonus)
			"miner":
				var level = int(buildings.get("quarry", 0))
				if level > 0:
					materials += MINER_MATERIALS_PER_HOUR * hours * level * rate * material_bonus
			"rest":
				if instance_id == selected_id:
					var cap = REST_BONUS_CAP[clampi(int(buildings.get("barracks", 0)), 0, 3)] + rest_cap_bonus
					hub["rest_bonus"] = mini(cap, int(hub.get("rest_bonus", 0)) + int(REST_BONUS_PER_HOUR * hours))
	# Scouts come home when their expedition time is up.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var returned := []
	for instance_id in hub["expeditions"]:
		var expedition: Dictionary = hub["expeditions"][instance_id]
		if int(expedition["ends"]) > now:
			continue
		returned.append(instance_id)
		var expedition_hours = int(expedition["hours"])
		var hall_level = maxi(1, int(buildings.get("scout_hall", 1)))
		var scout_rate = affinity("scout", hero_classes.get(instance_id, ""))
		materials += 10.0 * expedition_hours * (0.5 + 0.5 * hall_level) * scout_rate
		if rng.randf() < minf(0.15 * expedition_hours, 0.75):
			result["items"].append({
				"rarity": "unusual" if rng.randf() < 0.3 + 0.1 * hall_level else "common",
				"seed": rng.randi()
			})
	for instance_id in returned:
		hub["expeditions"].erase(instance_id)
		if hub["residents"].has(instance_id):
			hub["residents"][instance_id] = "rest"
	result["materials"] = int(materials)
	hub["materials"] = int(hub.get("materials", 0)) + int(materials)
	return result
