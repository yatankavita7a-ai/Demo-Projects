extends RefCounted

# Data for the two special guardian floors (docs/BOSS_SYSTEM.md):
#   Floor 10 - The Dead Tide: no guardian. Survive an endless, escalating
#              horde of the consumed kingdoms' dead for 10:00.
#   Floor 20 - Vharzul, the Unburnt Wyrm: a dragon the Tower bound as its
#              warden. Its scales turn every blade unless the player carries
#              Dragonbane, forged from three pieces hidden on floors 16-19.
#              Without it, the Chain Rite drags the wyrm down for short
#              windows in which it can be hurt.

const DEAD_TIDE_FLOOR := 10
const DRAGON_FLOOR := 20

# --- The Dead Tide -------------------------------------------------------------

const TIDE_NAME := "The Dead Tide"
const TIDE_LORE := "The kingdoms the Tower drained did not rest. Their people still walk, and they remember you are alive."
const TIDE_DURATION := 600.0          # seconds of real gameplay time
const TIDE_TIER_SECONDS := 120.0      # escalation every 2:00
const TIDE_HARD_CAP := 40             # live zombies, whatever the tier says
const TIDE_SURGES := [240.0, 480.0]   # brute packs at 4:00 and 8:00
const TIDE_SURGE_BRUTES := [3, 4]
const TIDE_SURGE_ESCORT := 5          # shamblers that come with each pack
const TIDE_SPAWN_RADIUS := Vector2(26.0, 36.0)
const TIDE_DESPAWN_DISTANCE := 75.0
const TIDE_STUCK_SECONDS := 10.0
const TIDE_PLAY_LIMIT := 64.0

# Escalation tiers: seconds between spawn groups, group size, live cap,
# health and speed multipliers and the weight of each zombie kind.
const TIDE_TIERS := [
	{"interval": 2.4, "group": Vector2i(1, 2), "cap": 14, "health": 1.0, "speed": 1.0,
		"weights": {"shambler": 1.0, "runner": 0.0, "bloated": 0.15, "brute": 0.0}},
	{"interval": 1.9, "group": Vector2i(1, 3), "cap": 20, "health": 1.15, "speed": 1.05,
		"weights": {"shambler": 1.0, "runner": 0.4, "bloated": 0.25, "brute": 0.04}},
	{"interval": 1.5, "group": Vector2i(2, 3), "cap": 27, "health": 1.3, "speed": 1.1,
		"weights": {"shambler": 1.0, "runner": 0.6, "bloated": 0.35, "brute": 0.1}},
	{"interval": 1.15, "group": Vector2i(2, 4), "cap": 34, "health": 1.5, "speed": 1.15,
		"weights": {"shambler": 0.9, "runner": 0.8, "bloated": 0.4, "brute": 0.16}},
	{"interval": 0.85, "group": Vector2i(3, 4), "cap": 40, "health": 1.75, "speed": 1.2,
		"weights": {"shambler": 0.8, "runner": 1.0, "bloated": 0.45, "brute": 0.22}},
]

const MONSTERS := "res://assets/models/monsters/"
# Per kind: health / attack multipliers on a regular enemy of the floor,
# speed (m/s), size (x player), wind-up, light-hit armour (damage taken from
# light hits), model and rot tint. All reuse the existing monster pack,
# desaturated and tinted (shaders/zombie_rot.gdshader).
const ZOMBIE_KINDS := {
	"shambler": {"health": 1.0, "attack": 0.9, "speed": 1.7, "size": 1.0, "windup": 0.55,
		"armor": 1.0, "model": MONSTERS + "Big/Orc.gltf", "tint": Color(0.72, 0.88, 0.58)},
	"runner": {"health": 0.55, "attack": 0.7, "speed": 5.0, "size": 0.9, "windup": 0.4,
		"armor": 1.0, "model": MONSTERS + "Big/Tribal.gltf", "tint": Color(0.8, 0.84, 0.74)},
	"bloated": {"health": 1.3, "attack": 0.8, "speed": 1.4, "size": 1.25, "windup": 0.6,
		"armor": 1.0, "model": MONSTERS + "Blob/Orc.gltf", "tint": Color(0.8, 1.0, 0.42)},
	"brute": {"health": 4.0, "attack": 1.8, "speed": 2.2, "size": 1.6, "windup": 0.75,
		"armor": 0.5, "model": MONSTERS + "Big/Yeti.gltf", "tint": Color(0.66, 0.72, 0.66)},
}
# A bloated zombie bursts into a lingering poison pool (BossHazard).
const BLOAT_POOL := {"shape": {"type": "circle", "radius": 2.6}, "arm": 0.6, "duration": 6.0,
	"tick": 0.5, "tint": "poison"}
const BLOAT_POOL_DAMAGE := 0.3   # x the zombie's attack power, per tick


static func tide_tier_index(elapsed: float) -> int:
	return clampi(int(floor(maxf(0.0, elapsed) / TIDE_TIER_SECONDS)), 0, TIDE_TIERS.size() - 1)


# Spawn settings at `elapsed` seconds. Known clues about the region's
# guardian and Wayfarer allies thin the tide: longer gaps and a lower cap.
static func tide_settings(elapsed: float, known_clues: int = 0, allies: int = 0) -> Dictionary:
	var tier: Dictionary = (TIDE_TIERS[tide_tier_index(elapsed)] as Dictionary).duplicate(true)
	var relief := minf(0.35, 0.07 * maxi(known_clues, 0) + 0.03 * maxi(allies, 0))
	tier["interval"] = float(tier["interval"]) * (1.0 + relief)
	tier["cap"] = clampi(int(tier["cap"]) - maxi(known_clues, 0), 6, TIDE_HARD_CAP)
	tier["relief"] = relief
	tier["tier"] = tide_tier_index(elapsed)
	return tier


static func format_clock(seconds: float) -> String:
	var whole := maxi(0, ceili(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


# --- Vharzul and Dragonbane ----------------------------------------------------

const DRAGON_NAME := "Vharzul, the Unburnt Wyrm"
const DRAGON_LORE := "The Tower could not burn the last dragon, so it chained it. Vharzul guards the gate that drinks its own sky."
const DRAGONBANE_NAME := "Dragonbane"
const DRAGONBANE_PIECES := ["scalebreaker_shard", "emberward_charm", "wyrms_eye"]
const PIECES := {
	"scalebreaker_shard": {"name": "Scalebreaker Shard", "floors": [16],
		"hint": "Floor 16 - a draconic shrine west of the old harbour road."},
	"emberward_charm": {"name": "Emberward Charm", "floors": [17, 18],
		"hint": "Floor 17 or 18 - an ember-lit shrine; the Tower moves it between climbs."},
	"wyrms_eye": {"name": "Wyrm's Eye", "floors": [19],
		"hint": "Floor 19 - a shrine on the drowned terrace, west of the path."},
}
const PIECE_POSITION := Vector3(-34, 0, 18)
const DRAGON_WARNING := "Vharzul's scales turn every blade. The Dragonbane pieces lie hidden on floors 16-19."

# Weak point (with Dragonbane): hits here deal double damage and posture.
const WEAK_POINT_MULT := 2.0

# Chain Rite (no Dragonbane): four pillars bind the wyrm.
const RITE_PILLARS := 4
const RITE_CENTER := Vector3(0, 0, -8)
const RITE_RADIUS := 21.0
const RITE_CIRCLE := 3.2          # metres: stand inside to channel
const RITE_CHANNEL := 8.0         # seconds to light one pillar
const RITE_DECAY := 0.5           # progress lost per second outside the circle
const RITE_STUN := 8.0            # seconds Vharzul stays chained down
const RITE_BASE_WINDUP := 0.8     # full aggression during the rite
const RITE_WINDUP_STEP := 0.05    # each cycle: wind-ups get this much faster
const RITE_MIN_WINDUP := 0.6
const RITE_DAMAGE_STEP := 0.15    # each cycle: attacks hit this much harder


static func piece_name(piece_id: String) -> String:
	return String(PIECES.get(piece_id, {}).get("name", ""))


# The floor a piece is hidden on in this world. The Emberward Charm sits on
# floor 17 or 18, chosen by the world seed.
static func piece_floor(piece_id: String, world_seed: int) -> int:
	var floors: Array = PIECES.get(piece_id, {}).get("floors", [])
	if floors.is_empty():
		return 0
	return int(floors[absi(world_seed) % floors.size()])


static func pieces_on_floor(floor_number: int, world_seed: int) -> Array:
	var result: Array = []
	for piece_id in DRAGONBANE_PIECES:
		if piece_floor(piece_id, world_seed) == floor_number:
			result.append(piece_id)
	return result


# Rite difficulty for the given cycle (0 = first binding).
static func rite_windup_mult(cycle: int) -> float:
	return maxf(RITE_MIN_WINDUP, RITE_BASE_WINDUP - RITE_WINDUP_STEP * maxi(cycle, 0))


static func rite_damage_mult(cycle: int) -> float:
	return 1.0 + RITE_DAMAGE_STEP * maxi(cycle, 0)


static func rite_pillar_positions() -> Array:
	var result: Array = []
	for index in range(RITE_PILLARS):
		var angle := PI * 0.25 + TAU * float(index) / float(RITE_PILLARS)
		result.append(RITE_CENTER + Vector3(cos(angle), 0.0, sin(angle)) * RITE_RADIUS)
	return result
