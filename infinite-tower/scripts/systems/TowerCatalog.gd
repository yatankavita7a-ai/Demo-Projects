extends RefCounted
class_name TowerCatalog

const FLOOR_LIMIT := 50

const REGIONS := [
	{"name": "Ashen Threshold", "terrain": "volcanic ruins", "color": Color("#44373a")},
	{"name": "Whispering Canopy", "terrain": "ancient forest", "color": Color("#33483d")},
	{"name": "Crown of Dust", "terrain": "abandoned kingdom", "color": Color("#655642")},
	{"name": "Drowned Reach", "terrain": "flooded city", "color": Color("#354b55")},
	{"name": "The Pale March", "terrain": "snowbound valley", "color": Color("#78838a")},
	{"name": "Hollow Deep", "terrain": "underground caves", "color": Color("#373948")},
	{"name": "Gloamwood", "terrain": "haunted woodland", "color": Color("#414348")},
	{"name": "Sunken Sepulchre", "terrain": "forgotten temple", "color": Color("#65534a")},
	{"name": "The Red Expanse", "terrain": "desolate battlefield", "color": Color("#63403b")},
	{"name": "Nightglass Summit", "terrain": "black-stone citadel", "color": Color("#3c3b50")}
]

const BOSSES := [
	{"name": "The Cinder Warden", "history": "A guardian that sealed the first breach in flame.", "attacks": "A sweeping ember arc followed by a delayed ground burst.", "weakness": "Its furnace core dims after a missed charge.", "preparation": "Heatproof wraps and a vent lever disrupt its recovery."},
	{"name": "Mother of Briars", "history": "A forest spirit bound beneath the old canopy.", "attacks": "Root snares mark the ground before thorn eruptions.", "weakness": "Cutting the marked roots interrupts her growth.", "preparation": "A sickle hidden in the ranger camp severs root armor."},
	{"name": "The Brass Regent", "history": "The last ruler of a kingdom that outlawed grief.", "attacks": "A shielded advance and a three-strike royal form.", "weakness": "The shield arm is exposed after the third strike.", "preparation": "A cracked signet opens the side armory for a blunt weapon."},
	{"name": "The Drowned Cantor", "history": "A voice that lured an entire harbor below the tide.", "attacks": "A rising-water pulse and a resonant cone attack.", "weakness": "Breaking the bell pylons silences the cone.", "preparation": "A rebreather charm grants longer recovery windows underwater."},
	{"name": "The Pale Huntress", "history": "A captain who never returned from the winter pass.", "attacks": "A ranged volley, then a fast pouncing strike.", "weakness": "A blocked pounce leaves her bow hand vulnerable.", "preparation": "Fur-lined armor reduces frost slow in the arena."},
	{"name": "The Maw Below", "history": "A cave-in survivor changed by the dark beneath the tower.", "attacks": "A burrowing lunge and a darkness field.", "weakness": "Echoing crystals reveal its location while submerged.", "preparation": "A miner's lantern shortens the darkness phase."},
	{"name": "The Hollow Knight", "history": "An oath-bound sentinel abandoned by its order.", "attacks": "A feinting sword combo and a shield bash.", "weakness": "A parry during the feint breaks its stance.", "preparation": "A sparring journal teaches the sentinel's false opening."},
	{"name": "The Sepulchre Twin", "history": "Two keepers who chose to share one immortal vow.", "attacks": "One pins the player while the other marks a beam.", "weakness": "Their shared ward falters when they are separated.", "preparation": "A temple chain can pull one keeper across the chamber."},
	{"name": "The Red Marshal", "history": "A war leader who turned every retreat into a trap.", "attacks": "Banner calls summon soldiers and artillery marks lanes.", "weakness": "Destroying a banner cancels its next reinforcement.", "preparation": "Scavenged charges can disable the artillery nest."},
	{"name": "The Starless Sovereign", "history": "The architect of the tower, waiting beyond its final gate.", "attacks": "A shifting stance combines every prior boss pattern.", "weakness": "Recorded investigations expose openings between stances.", "preparation": "Allies and relics gathered across the tower weaken its final ward."}
]

# Floor 20's guardian. The Drowned Cantor (BOSSES[3]) stays defined for the
# Starless Sovereign's borrowed stances but no longer guards a floor; the
# Drowned Reach's clues (floors 16-19) describe Vharzul instead.
const VHARZUL := {"name": "Vharzul, the Unburnt Wyrm", "moveset": 10, "special": "dragon",
	"history": "A dragon the Tower could not burn, so it chained it here as a warden.",
	"attacks": "Fire breath sweeps the ground; from the sky it rains fire, then lands like a falling tower.",
	"weakness": "Its scales turn every blade. Dragonbane, forged from three pieces on these floors, finds the seam.",
	"preparation": "Old chains still bind it to four pillars. Lit together, they drag it to the ground.",
	"lore": "The Tower could not burn the last dragon, so it chained it. Vharzul guards the gate that drinks its own sky."}
# Floor 10 has no guardian: the region's floor is the Dead Tide. Mother of
# Briars (BOSSES[1]) stays defined but no longer guards a floor; floors 6-9
# carry the tide's clues, and each one found thins the horde.
const DEAD_TIDE := {"name": "The Dead Tide", "special": "dead_tide",
	"history": "The canopy kingdoms fell to the Tower's thirst. Their people never left the forest.",
	"attacks": "The dead come in tides: slow walkers, then runners, and bloated ones that burst into poison.",
	"weakness": "The tide swells every two minutes. Brute packs break through near the fourth and eighth minute.",
	"preparation": "Those who learn the tide's ways meet fewer of the dead. Endure ten minutes and the Tower lets go.",
	"lore": "The kingdoms the Tower drained did not rest. Their people still walk, and they remember you are alive."}


# The guardian whose clues and chamber belong to a region.
static func region_boss(region_index: int) -> Dictionary:
	if region_index == 1:
		return DEAD_TIDE
	if region_index == 3:
		return VHARZUL
	return BOSSES[region_index]


static func get_floor(floor_number: int) -> Dictionary:
	if floor_number < 1 or floor_number > FLOOR_LIMIT:
		return {}
	var region_index = floori(float(floor_number - 1) / 5.0)
	var position_in_arc = (floor_number - 1) % 5
	var data = {
		"floor": floor_number,
		"region_index": region_index,
		"region": REGIONS[region_index]["name"],
		"terrain": REGIONS[region_index]["terrain"],
		"color": REGIONS[region_index]["color"],
		"boss_floor": position_in_arc == 4,
		"boss": {},
		"clue_stage": position_in_arc,
		"clue": ""
	}
	var boss = region_boss(region_index)
	match position_in_arc:
		0:
			data["clue"] = boss["history"]
		1:
			data["clue"] = boss["attacks"]
		2:
			data["clue"] = boss["weakness"]
		3:
			data["clue"] = boss["preparation"]
		4:
			data["boss"] = boss.duplicate(true)
			data["special"] = String(data["boss"].get("special", ""))
	return data


static func boss_floor_numbers() -> Array[int]:
	var floors: Array[int] = []
	for floor_number in range(5, FLOOR_LIMIT + 1, 5):
		floors.append(floor_number)
	return floors


static func rare_interval_start(floor_number: int) -> int:
	if floor_number < 1 or floor_number > FLOOR_LIMIT:
		return 0
	return floori(float(floor_number - 1) / 10.0) * 10 + 1


static func can_stealth_exit(boss_floor: bool, crouching: bool, enemies_alerted: bool) -> bool:
	return not boss_floor and crouching and not enemies_alerted
