extends RefCounted

# Boss data for the boss-combat system (docs/BOSS_SYSTEM.md): per-boss size,
# stats and moveset, plus the attack-shape geometry shared by the brain, the
# ground telegraphs and the tests.
#
# Move records use these fields (all optional except kind/windup/active/
# recovery):
#   kind        melee | slam | pulse | charge | projectile | hazard | summon |
#               stance | evade | flight (take to the air)
#   shape       {type: cone|circle|ring|line|box, radius, angle (degrees,
#               full width), offset (forward), length, width}
#   windup, track_until, active, recovery   seconds
#   damage      multiplier on the boss's attack_power
#   color       normal (orange) | yellow (parryable flash) | red (unblockable)
#   lunge       metres moved forward at the start of the active window
#   charge      metres travelled along the locked line (kind charge)
#   next        follow-up move id (combo strings); next_chance (0..1)
#   phase       first phase the move is available in (1 or 2)
#   weight, min_range, max_range, cooldown
#   delayed     the wind-up pose is held (delayed swing); hold = held seconds
#   feint_at / feint_into   the wind-up is abandoned at feint_at and the
#               move turns into feint_into (Hollow Knight feints)
#   anim        ModelRig action state for the wind-up
#   ring        expanding shockwave {max, width, speed, count, interval}
#   projectile  {count, spread (degrees), speed, radius, damage}
#   hazard      {pattern, count, spacing, shape, arm, duration, tick, damage,
#               tint, color}
#   summon      {count}
#   heavy       big impact: camera shake
#   air         usable only while airborne (flying bosses); land = the move
#               that ends the flight
#   sweep       degrees a narrow cone swings across during the active window
#   fire        fire damage (breath, fire rain)
#
# Sizes are multiples of the 1.8 m player. Shape sizes, lunges and melee
# ranges are written per unit of size and multiplied by the boss's size in
# scaled_moves(); anything marked "fixed" (charges, projectiles, hazards,
# shockwave rings) is in metres and is not scaled.

const PLAYER_HEIGHT := 1.8
const PHASE_TWO_WINDUP := 0.88
const STANCE_LENGTH := 3 # Sovereign: attacks per stance before shifting.

# Timing ranges the data must respect (tests/test_boss.gd checks them).
const WINDUP_RANGE := Vector2(0.6, 1.5)       # opening attacks
const DELAYED_RANGE := Vector2(1.1, 2.2)      # delayed swings (pose held)
const FOLLOWUP_RANGE := Vector2(0.3, 0.55)    # combo follow-ups
const UTILITY_RANGE := Vector2(0.2, 1.5)      # stance shifts, backsteps, casts
const RECOVERY_RANGE := Vector2(0.3, 2.0)
const ACTIVE_RANGE := Vector2(0.1, 1.6)

const BOSSES := [
	# 0 The Cinder Warden: 4.5x. Ember arc that leaves fire pools, delayed
	# ground burst with a shockwave, stomp, charge (phase 2).
	{
		"size": 4.5, "health": 3.2, "speed": 2.2, "posture_max": 120.0,
		"moves": {
			"ember_arc": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 120.0},
				"windup": 1.0, "track_until": 0.6, "active": 0.25, "recovery": 0.9, "damage": 1.0,
				"anim": "swipe", "max_range": 1.5,
				"hazard": {"pattern": "along_cone", "count": 3, "shape": {"type": "circle", "radius": 2.2},
					"arm": 0.25, "duration": 5.0, "tick": 0.5, "damage": 0.15, "tint": "fire"}},
			"ground_burst": {"kind": "slam", "shape": {"type": "circle", "radius": 0.85, "offset": 1.0},
				"windup": 1.8, "hold": 0.8, "delayed": true, "track_until": 1.2, "active": 0.2, "recovery": 1.4,
				"damage": 1.3, "anim": "slam", "heavy": true, "max_range": 2.0,
				"ring": {"max": 15.0, "width": 1.6, "speed": 9.0, "count": 1, "interval": 0.0}},
			"stomp": {"kind": "slam", "shape": {"type": "circle", "radius": 0.85},
				"windup": 0.8, "track_until": 0.0, "active": 0.15, "recovery": 0.8, "damage": 0.9,
				"anim": "slam", "heavy": true, "max_range": 0.9, "weight": 1.4},
			"ember_arc_return": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 120.0},
				"windup": 0.45, "track_until": 0.25, "active": 0.25, "recovery": 1.0, "damage": 1.2,
				"anim": "swipe", "phase": 2, "followup": true},
			"ember_combo": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 120.0},
				"windup": 0.95, "track_until": 0.6, "active": 0.25, "recovery": 0.3, "damage": 1.0,
				"anim": "swipe", "phase": 2, "max_range": 1.5, "next": "ember_arc_return"},
			"charge": {"kind": "charge", "shape": {"type": "line", "width": 0.45, "length": 0.0},
				"charge": 18.0, "windup": 1.1, "track_until": 0.9, "active": 0.9, "recovery": 1.6,
				"damage": 1.3, "anim": "crouch", "heavy": true, "phase": 2, "min_range": 8.0,
				"max_range": 26.0, "range_fixed": true},
		},
	},
	# 1 Mother of Briars: 3x. Root snares then eruptions, thorn sweep, vine
	# grab (red), briar hazards (phase 2).
	{
		"size": 3.0, "health": 2.9, "speed": 2.4, "posture_max": 110.0,
		"moves": {
			"root_snare": {"kind": "hazard", "windup": 0.8, "track_until": 0.8, "active": 0.2, "recovery": 0.9,
				"anim": "roar", "max_range": 22.0, "range_fixed": true, "min_range": 3.0, "cooldown": 4.0,
				"hazard": {"pattern": "at_target", "count": 3, "spacing": 3.2, "shape": {"type": "circle", "radius": 1.7},
					"arm": 1.1, "duration": 0.0, "damage": 1.0, "tint": "root"}},
			"thorn_sweep": {"kind": "melee", "shape": {"type": "box", "length": 1.3, "width": 3.0},
				"windup": 0.9, "track_until": 0.55, "active": 0.3, "recovery": 0.8, "damage": 0.9,
				"anim": "swipe", "max_range": 1.3},
			"vine_grab": {"kind": "melee", "shape": {"type": "line", "length": 2.6, "width": 0.5},
				"windup": 1.0, "track_until": 0.7, "active": 0.3, "recovery": 1.3, "damage": 2.0,
				"color": "red", "anim": "crouch", "max_range": 2.5, "weight": 0.8},
			"briar_field": {"kind": "hazard", "windup": 1.0, "track_until": 1.0, "active": 0.2, "recovery": 0.8,
				"anim": "roar", "phase": 2, "max_range": 30.0, "range_fixed": true, "cooldown": 12.0,
				"hazard": {"pattern": "ring_around_target", "count": 4, "spacing": 5.5, "shape": {"type": "circle", "radius": 2.4},
					"arm": 1.0, "duration": 7.0, "tick": 0.5, "damage": 0.18, "tint": "root"}},
			"thorn_return": {"kind": "melee", "shape": {"type": "box", "length": 1.3, "width": 3.0},
				"windup": 0.5, "track_until": 0.3, "active": 0.3, "recovery": 1.1, "damage": 1.0,
				"anim": "swipe", "phase": 2, "followup": true},
			"thorn_double": {"kind": "melee", "shape": {"type": "box", "length": 1.3, "width": 3.0},
				"windup": 0.85, "track_until": 0.5, "active": 0.3, "recovery": 0.3, "damage": 0.9,
				"anim": "swipe", "phase": 2, "max_range": 1.3, "next": "thorn_return"},
		},
	},
	# 2 The Brass Regent: 1.3x. Shielded charge, three-strike royal combo
	# with a yellow finisher, shield bash (red), delayed overhead.
	{
		"size": 1.3, "health": 2.6, "speed": 3.4, "posture_max": 90.0,
		"moves": {
			"shield_charge": {"kind": "charge", "shape": {"type": "line", "width": 1.0, "length": 0.0},
				"charge": 10.0, "windup": 0.9, "track_until": 0.7, "active": 0.7, "recovery": 1.0,
				"damage": 1.1, "anim": "crouch", "min_range": 4.0, "max_range": 14.0, "range_fixed": true},
			"royal_1": {"kind": "melee", "shape": {"type": "cone", "radius": 2.2, "angle": 100.0},
				"windup": 0.8, "track_until": 0.55, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.8, "anim": "swipe", "max_range": 2.6, "next": "royal_2"},
			"royal_2": {"kind": "melee", "shape": {"type": "cone", "radius": 2.2, "angle": 100.0},
				"windup": 0.4, "track_until": 0.25, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.6, "anim": "swipe", "followup": true, "next": "royal_3"},
			"royal_3": {"kind": "melee", "shape": {"type": "cone", "radius": 2.4, "angle": 80.0},
				"windup": 0.5, "track_until": 0.25, "active": 0.2, "recovery": 1.5, "damage": 1.5,
				"lunge": 0.8, "color": "yellow", "anim": "slam", "followup": true},
			"shield_bash": {"kind": "melee", "shape": {"type": "cone", "radius": 1.7, "angle": 70.0},
				"windup": 0.9, "track_until": 0.6, "active": 0.2, "recovery": 1.0, "damage": 1.6,
				"lunge": 0.5, "color": "red", "anim": "crouch", "max_range": 1.9, "weight": 0.8},
			"delayed_overhead": {"kind": "melee", "shape": {"type": "circle", "radius": 1.0, "offset": 1.5},
				"windup": 1.6, "hold": 0.8, "delayed": true, "track_until": 1.2, "active": 0.2, "recovery": 1.2,
				"damage": 1.5, "anim": "slam", "max_range": 2.4},
			"charge_bash": {"kind": "charge", "shape": {"type": "line", "width": 1.0, "length": 0.0},
				"charge": 10.0, "windup": 0.85, "track_until": 0.65, "active": 0.7, "recovery": 0.2,
				"damage": 1.0, "anim": "crouch", "phase": 2, "min_range": 4.0, "max_range": 14.0,
				"range_fixed": true, "next": "shield_bash_follow"},
			"shield_bash_follow": {"kind": "melee", "shape": {"type": "cone", "radius": 1.7, "angle": 70.0},
				"windup": 0.5, "track_until": 0.3, "active": 0.2, "recovery": 1.2, "damage": 1.4,
				"color": "red", "anim": "crouch", "phase": 2, "followup": true},
			"royal_flurry": {"kind": "melee", "shape": {"type": "cone", "radius": 2.2, "angle": 100.0},
				"windup": 0.75, "track_until": 0.5, "active": 0.2, "recovery": 0.3, "damage": 0.8,
				"lunge": 0.8, "anim": "swipe", "phase": 2, "max_range": 2.6, "next": "royal_2"},
		},
	},
	# 3 The Drowned Cantor: 4x. Rising-water pulse rings, resonant cone
	# (red), water bolts, double pulse (phase 2).
	{
		"size": 4.0, "health": 3.0, "speed": 2.0, "posture_max": 115.0,
		"moves": {
			"water_pulse": {"kind": "pulse", "shape": {"type": "circle", "radius": 0.6},
				"windup": 1.1, "track_until": 0.0, "active": 0.2, "recovery": 1.0, "damage": 0.9,
				"anim": "slam", "max_range": 14.0, "range_fixed": true,
				"ring": {"max": 18.0, "width": 1.5, "speed": 8.0, "count": 1, "interval": 0.0}},
			"resonant_cone": {"kind": "melee", "shape": {"type": "cone", "radius": 3.0, "angle": 50.0},
				"windup": 1.2, "track_until": 0.9, "active": 0.5, "recovery": 1.3, "damage": 1.4,
				"color": "red", "anim": "roar", "max_range": 2.8},
			"water_bolts": {"kind": "projectile", "windup": 0.8, "track_until": 0.7, "active": 0.2, "recovery": 0.8,
				"anim": "swipe", "min_range": 5.0, "max_range": 32.0, "range_fixed": true,
				"projectile": {"count": 3, "spread": 14.0, "speed": 13.0, "radius": 0.6, "damage": 0.7}},
			"double_pulse": {"kind": "pulse", "shape": {"type": "circle", "radius": 0.6},
				"windup": 1.0, "track_until": 0.0, "active": 0.2, "recovery": 1.2, "damage": 0.9,
				"anim": "slam", "phase": 2, "max_range": 14.0, "range_fixed": true, "weight": 1.3,
				"ring": {"max": 18.0, "width": 1.5, "speed": 8.0, "count": 2, "interval": 0.7}},
			"bolt_barrage": {"kind": "projectile", "windup": 0.9, "track_until": 0.8, "active": 0.2, "recovery": 1.0,
				"anim": "swipe", "phase": 2, "min_range": 4.0, "max_range": 32.0, "range_fixed": true,
				"projectile": {"count": 5, "spread": 32.0, "speed": 14.0, "radius": 0.6, "damage": 0.65}},
		},
	},
	# 4 The Pale Huntress: 1.1x. Arrow volley, pounce (charge into a yellow
	# slam), backstep.
	{
		"size": 1.1, "health": 2.6, "speed": 4.4, "posture_max": 85.0,
		"moves": {
			"arrow_volley": {"kind": "projectile", "windup": 0.8, "track_until": 0.7, "active": 0.2, "recovery": 0.7,
				"anim": "slam", "min_range": 4.0, "max_range": 30.0, "range_fixed": true,
				"projectile": {"count": 3, "spread": 10.0, "speed": 18.0, "radius": 0.45, "damage": 0.6}},
			"pounce": {"kind": "charge", "shape": {"type": "line", "width": 0.9, "length": 0.0},
				"charge": 9.0, "windup": 0.8, "track_until": 0.65, "active": 0.45, "recovery": 0.2,
				"damage": 0.8, "anim": "crouch", "min_range": 4.0, "max_range": 12.0, "range_fixed": true,
				"next": "pounce_slam"},
			"pounce_slam": {"kind": "melee", "shape": {"type": "circle", "radius": 1.4},
				"windup": 0.45, "track_until": 0.2, "active": 0.2, "recovery": 1.4, "damage": 1.3,
				"color": "yellow", "anim": "slam", "followup": true},
			"backstep": {"kind": "evade", "windup": 0.25, "track_until": 0.25, "active": 0.35, "recovery": 0.2,
				"charge": 5.5, "anim": "crouch", "max_range": 3.0, "range_fixed": true, "next": "arrow_volley_quick",
				"weight": 0.9},
			"arrow_volley_quick": {"kind": "projectile", "windup": 0.5, "track_until": 0.45, "active": 0.2, "recovery": 0.8,
				"anim": "slam", "followup": true,
				"projectile": {"count": 3, "spread": 10.0, "speed": 18.0, "radius": 0.45, "damage": 0.6}},
			"hunting_knife": {"kind": "melee", "shape": {"type": "cone", "radius": 1.7, "angle": 90.0},
				"windup": 0.65, "track_until": 0.45, "active": 0.2, "recovery": 0.7, "damage": 0.9,
				"lunge": 0.6, "anim": "swipe", "max_range": 1.9},
			"arrow_rain": {"kind": "hazard", "windup": 0.9, "track_until": 0.9, "active": 0.2, "recovery": 0.8,
				"anim": "slam", "phase": 2, "min_range": 3.0, "max_range": 30.0, "range_fixed": true, "cooldown": 6.0,
				"hazard": {"pattern": "at_target", "count": 4, "spacing": 3.0, "shape": {"type": "circle", "radius": 1.5},
					"arm": 1.0, "duration": 0.0, "damage": 0.9, "tint": "frost"}},
			"triple_volley": {"kind": "projectile", "windup": 0.85, "track_until": 0.75, "active": 0.2, "recovery": 0.9,
				"anim": "slam", "phase": 2, "min_range": 4.0, "max_range": 30.0, "range_fixed": true, "weight": 1.2,
				"projectile": {"count": 5, "spread": 24.0, "speed": 19.0, "radius": 0.45, "damage": 0.6}},
		},
	},
	# 5 The Maw Below: 5x. Burrowing lunge, darkness hazard field, stomp,
	# tail sweep.
	{
		"size": 5.0, "health": 3.4, "speed": 2.0, "posture_max": 130.0,
		"moves": {
			"burrow_lunge": {"kind": "charge", "shape": {"type": "line", "width": 0.45, "length": 0.0},
				"charge": 16.0, "windup": 1.3, "track_until": 1.0, "active": 0.9, "recovery": 1.5,
				"damage": 1.5, "anim": "crouch", "burrow": true, "heavy": true,
				"min_range": 7.0, "max_range": 24.0, "range_fixed": true},
			"darkness_field": {"kind": "hazard", "windup": 1.1, "track_until": 1.1, "active": 0.2, "recovery": 0.9,
				"anim": "roar", "max_range": 30.0, "range_fixed": true, "cooldown": 12.0,
				"hazard": {"pattern": "at_target", "count": 1, "shape": {"type": "circle", "radius": 7.0},
					"arm": 1.2, "duration": 8.0, "tick": 0.5, "damage": 0.12, "tint": "dark"}},
			"stomp": {"kind": "slam", "shape": {"type": "circle", "radius": 0.75},
				"windup": 0.85, "track_until": 0.0, "active": 0.15, "recovery": 0.8, "damage": 1.0,
				"anim": "slam", "heavy": true, "max_range": 0.8, "weight": 1.4},
			"tail_sweep": {"kind": "melee", "shape": {"type": "box", "length": 0.9, "width": 2.4},
				"windup": 1.0, "track_until": 0.6, "active": 0.35, "recovery": 0.9, "damage": 1.0,
				"anim": "swipe", "max_range": 0.95},
			"bite": {"kind": "melee", "shape": {"type": "cone", "radius": 1.25, "angle": 60.0},
				"windup": 0.8, "track_until": 0.55, "active": 0.2, "recovery": 0.8, "damage": 1.1,
				"anim": "swipe", "max_range": 1.2},
			"frenzy_bite": {"kind": "melee", "shape": {"type": "cone", "radius": 1.25, "angle": 60.0},
				"windup": 0.75, "track_until": 0.5, "active": 0.2, "recovery": 0.3, "damage": 1.0,
				"anim": "swipe", "phase": 2, "max_range": 1.2, "next": "frenzy_bite_2"},
			"frenzy_bite_2": {"kind": "melee", "shape": {"type": "cone", "radius": 1.25, "angle": 60.0},
				"windup": 0.4, "track_until": 0.25, "active": 0.2, "recovery": 0.3, "damage": 1.0,
				"anim": "swipe", "phase": 2, "followup": true, "next": "frenzy_stomp"},
			"frenzy_stomp": {"kind": "slam", "shape": {"type": "circle", "radius": 0.75},
				"windup": 0.5, "track_until": 0.0, "active": 0.15, "recovery": 1.3, "damage": 1.3,
				"anim": "slam", "heavy": true, "phase": 2, "followup": true,
				"ring": {"max": 14.0, "width": 1.4, "speed": 9.0, "count": 1, "interval": 0.0}},
		},
	},
	# 6 The Hollow Knight: 1.2x. Feinting delayed swings, four-hit combo,
	# shield bash (red); many yellow attacks.
	{
		"size": 1.2, "health": 2.7, "speed": 3.6, "posture_max": 95.0,
		"moves": {
			"feint_swing": {"kind": "melee", "shape": {"type": "cone", "radius": 2.2, "angle": 110.0},
				"windup": 1.3, "hold": 0.5, "delayed": true, "track_until": 0.9, "active": 0.2, "recovery": 1.0,
				"damage": 1.3, "anim": "slam", "max_range": 2.5, "feint_at": 0.55, "feint_into": "delayed_swing",
				"weight": 0.8},
			"delayed_swing": {"kind": "melee", "shape": {"type": "cone", "radius": 2.2, "angle": 110.0},
				"windup": 1.4, "hold": 0.7, "delayed": true, "track_until": 1.0, "active": 0.2, "recovery": 1.2,
				"damage": 1.3, "color": "yellow", "anim": "slam", "max_range": 2.5},
			"knight_1": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 100.0},
				"windup": 0.75, "track_until": 0.5, "active": 0.2, "recovery": 0.3, "damage": 0.8,
				"lunge": 0.7, "anim": "swipe", "max_range": 2.3, "next": "knight_2"},
			"knight_2": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 100.0},
				"windup": 0.35, "track_until": 0.2, "active": 0.2, "recovery": 0.3, "damage": 0.8,
				"lunge": 0.5, "anim": "swipe", "followup": true, "next": "knight_3"},
			"knight_3": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 100.0},
				"windup": 0.5, "track_until": 0.3, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.5, "color": "yellow", "anim": "swipe", "followup": true, "next": "knight_4"},
			"knight_4": {"kind": "melee", "shape": {"type": "cone", "radius": 2.3, "angle": 70.0},
				"windup": 0.45, "track_until": 0.2, "active": 0.2, "recovery": 1.4, "damage": 1.4,
				"lunge": 0.9, "color": "yellow", "anim": "slam", "followup": true},
			"shield_bash": {"kind": "melee", "shape": {"type": "cone", "radius": 1.7, "angle": 70.0},
				"windup": 0.85, "track_until": 0.6, "active": 0.2, "recovery": 1.0, "damage": 1.5,
				"lunge": 0.6, "color": "red", "anim": "crouch", "max_range": 1.9, "weight": 0.8},
			"knight_thrust": {"kind": "melee", "shape": {"type": "line", "length": 3.4, "width": 0.6},
				"windup": 0.7, "track_until": 0.5, "active": 0.25, "recovery": 1.1, "damage": 1.2,
				"lunge": 2.0, "color": "yellow", "anim": "crouch", "phase": 2, "max_range": 4.0},
			"feint_combo": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 100.0},
				"windup": 1.2, "hold": 0.5, "delayed": true, "track_until": 0.8, "active": 0.2, "recovery": 0.8,
				"damage": 0.9, "anim": "swipe", "phase": 2, "max_range": 2.3, "feint_at": 0.45,
				"feint_into": "knight_1", "weight": 0.9},
		},
	},
	# 7 The Sepulchre Twin: 2x. Beam (red line), pinning grab, cross combo.
	{
		"size": 2.0, "health": 2.8, "speed": 3.0, "posture_max": 100.0,
		"moves": {
			"beam": {"kind": "melee", "shape": {"type": "line", "length": 22.0, "width": 1.6, "fixed": true},
				"windup": 1.2, "track_until": 0.8, "active": 0.6, "recovery": 1.2, "damage": 1.3,
				"color": "red", "anim": "roar", "min_range": 4.0, "max_range": 21.0, "range_fixed": true},
			"pinning_grab": {"kind": "melee", "shape": {"type": "cone", "radius": 1.5, "angle": 70.0},
				"windup": 1.0, "track_until": 0.7, "active": 0.25, "recovery": 0.3, "damage": 1.8,
				"lunge": 0.7, "color": "red", "anim": "crouch", "max_range": 2.0, "next": "beam_follow",
				"weight": 0.8},
			"beam_follow": {"kind": "melee", "shape": {"type": "line", "length": 22.0, "width": 1.6, "fixed": true},
				"windup": 0.55, "track_until": 0.3, "active": 0.5, "recovery": 1.3, "damage": 1.2,
				"color": "red", "anim": "roar", "followup": true},
			"cross_1": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 140.0},
				"windup": 0.75, "track_until": 0.5, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.5, "anim": "swipe", "max_range": 1.9, "next": "cross_2"},
			"cross_2": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 140.0},
				"windup": 0.45, "track_until": 0.25, "active": 0.2, "recovery": 1.2, "damage": 1.2,
				"lunge": 0.5, "color": "yellow", "anim": "swipe", "followup": true},
			"twin_lanes": {"kind": "hazard", "windup": 1.0, "track_until": 1.0, "active": 0.2, "recovery": 0.9,
				"anim": "roar", "phase": 2, "max_range": 28.0, "range_fixed": true, "cooldown": 7.0,
				"hazard": {"pattern": "cross_lanes", "count": 2, "shape": {"type": "line", "length": 24.0, "width": 2.2},
					"arm": 1.3, "duration": 0.0, "damage": 1.2, "color": "red"}},
			"cross_triple": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 140.0},
				"windup": 0.7, "track_until": 0.45, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.5, "anim": "swipe", "phase": 2, "max_range": 1.9, "next": "cross_triple_2"},
			"cross_triple_2": {"kind": "melee", "shape": {"type": "cone", "radius": 1.6, "angle": 140.0},
				"windup": 0.35, "track_until": 0.2, "active": 0.2, "recovery": 0.3, "damage": 0.9,
				"lunge": 0.4, "anim": "swipe", "phase": 2, "followup": true, "next": "cross_2"},
		},
	},
	# 8 The Red Marshal: 1.5x. Artillery lanes (line hazards), banner call
	# that summons soldiers, charge.
	{
		"size": 1.5, "health": 2.7, "speed": 3.3, "posture_max": 95.0,
		"moves": {
			"artillery": {"kind": "hazard", "windup": 0.9, "track_until": 0.9, "active": 0.2, "recovery": 0.8,
				"anim": "roar", "min_range": 3.0, "max_range": 30.0, "range_fixed": true, "cooldown": 5.0,
				"hazard": {"pattern": "lanes", "count": 3, "spacing": 6.0, "shape": {"type": "line", "length": 28.0, "width": 2.6},
					"arm": 1.4, "duration": 0.0, "damage": 1.2, "tint": "fire"}},
			"banner_call": {"kind": "summon", "windup": 1.2, "track_until": 1.2, "active": 0.3, "recovery": 1.0,
				"anim": "roar", "max_range": 40.0, "range_fixed": true, "cooldown": 20.0, "summon": {"count": 2}},
			"marshal_charge": {"kind": "charge", "shape": {"type": "line", "width": 0.9, "length": 0.0},
				"charge": 12.0, "windup": 1.0, "track_until": 0.8, "active": 0.75, "recovery": 1.1,
				"damage": 1.2, "anim": "crouch", "min_range": 4.0, "max_range": 16.0, "range_fixed": true},
			"halberd_sweep": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 160.0},
				"windup": 0.8, "track_until": 0.5, "active": 0.25, "recovery": 0.9, "damage": 1.0,
				"anim": "swipe", "max_range": 2.0},
			"artillery_cross": {"kind": "hazard", "windup": 0.9, "track_until": 0.9, "active": 0.2, "recovery": 0.8,
				"anim": "roar", "phase": 2, "min_range": 3.0, "max_range": 30.0, "range_fixed": true, "cooldown": 7.0,
				"hazard": {"pattern": "cross_lanes", "count": 2, "shape": {"type": "line", "length": 28.0, "width": 2.6},
					"arm": 1.3, "duration": 0.0, "damage": 1.2, "tint": "fire"}},
			"charge_sweep": {"kind": "charge", "shape": {"type": "line", "width": 0.9, "length": 0.0},
				"charge": 12.0, "windup": 0.95, "track_until": 0.75, "active": 0.75, "recovery": 0.2,
				"damage": 1.1, "anim": "crouch", "phase": 2, "min_range": 4.0, "max_range": 16.0,
				"range_fixed": true, "next": "sweep_follow"},
			"sweep_follow": {"kind": "melee", "shape": {"type": "cone", "radius": 2.0, "angle": 160.0},
				"windup": 0.45, "track_until": 0.25, "active": 0.25, "recovery": 1.2, "damage": 1.1,
				"color": "yellow", "anim": "swipe", "phase": 2, "followup": true},
		},
	},
	# 9 The Starless Sovereign: 4x. Stance shifts that mix earlier bosses'
	# attacks (built in _sovereign_moves); two phases.
	{
		"size": 4.0, "health": 3.6, "speed": 2.3, "posture_max": 140.0,
		"moves": {},
	},
	# 10 Vharzul, the Unburnt Wyrm (floor 20, scripts/systems/SpecialFloors.gd):
	# 5x. Sweeping fire breath (red), tail sweep, wing-gust ring, charge;
	# takes flight to rain fire and breathe from above, then lands with a
	# slam. Flying moves are marked "air"; "land" ends a flight; "sweep"
	# swings a narrow cone across `sweep` degrees during the active window.
	{
		"size": 5.0, "health": 3.6, "speed": 2.4, "posture_max": 150.0,
		"moves": {
			"fire_breath": {"kind": "melee", "shape": {"type": "cone", "radius": 2.6, "angle": 36.0},
				"sweep": 100.0, "windup": 1.3, "track_until": 0.9, "active": 1.4, "recovery": 1.2,
				"damage": 1.1, "color": "red", "anim": "roar", "fire": true, "max_range": 2.4},
			"tail_sweep": {"kind": "melee", "shape": {"type": "box", "length": 1.0, "width": 2.6},
				"windup": 1.0, "track_until": 0.6, "active": 0.35, "recovery": 0.9, "damage": 1.0,
				"anim": "swipe", "max_range": 1.0, "weight": 1.2},
			"wing_gust": {"kind": "pulse", "shape": {"type": "circle", "radius": 0.6},
				"windup": 1.1, "track_until": 0.0, "active": 0.2, "recovery": 1.0, "damage": 0.8,
				"anim": "slam", "max_range": 14.0, "range_fixed": true,
				"ring": {"max": 17.0, "width": 1.6, "speed": 10.0, "count": 1, "interval": 0.0}},
			"wyrm_charge": {"kind": "charge", "shape": {"type": "line", "width": 0.45, "length": 0.0},
				"charge": 20.0, "windup": 1.1, "track_until": 0.9, "active": 0.9, "recovery": 1.5,
				"damage": 1.3, "anim": "crouch", "heavy": true, "min_range": 9.0, "max_range": 28.0,
				"range_fixed": true},
			"take_off": {"kind": "flight", "windup": 0.9, "track_until": 0.9, "active": 0.6, "recovery": 0.3,
				"anim": "roar", "max_range": 999.0, "range_fixed": true, "cooldown": 16.0, "weight": 0.8},
			"fire_rain": {"kind": "hazard", "air": true, "fire": true, "windup": 0.9, "track_until": 0.9,
				"active": 0.2, "recovery": 0.6, "anim": "roar", "max_range": 999.0, "range_fixed": true,
				"hazard": {"pattern": "at_target", "count": 4, "spacing": 4.0, "shape": {"type": "circle", "radius": 2.4},
					"arm": 1.1, "duration": 5.0, "tick": 0.5, "damage": 0.16, "tint": "fire"}},
			"sky_breath": {"kind": "melee", "air": true, "shape": {"type": "cone", "radius": 3.0, "angle": 34.0},
				"sweep": 80.0, "windup": 1.2, "track_until": 0.85, "active": 1.2, "recovery": 0.9,
				"damage": 1.0, "color": "red", "anim": "roar", "fire": true, "max_range": 999.0, "range_fixed": true},
			"landing_slam": {"kind": "slam", "air": true, "land": true, "shape": {"type": "circle", "radius": 1.0},
				"windup": 1.4, "track_until": 1.0, "active": 0.2, "recovery": 1.6, "damage": 1.5,
				"anim": "slam", "heavy": true, "max_range": 999.0, "range_fixed": true,
				"ring": {"max": 18.0, "width": 1.8, "speed": 10.0, "count": 1, "interval": 0.0}},
			# Phase two: a wider inferno that rolls into a tail whip, and a
			# heavier storm of fire from the sky.
			"inferno": {"kind": "melee", "shape": {"type": "cone", "radius": 2.8, "angle": 36.0},
				"sweep": 150.0, "windup": 1.3, "track_until": 0.9, "active": 1.6, "recovery": 0.3,
				"damage": 1.1, "color": "red", "anim": "roar", "fire": true, "phase": 2, "max_range": 2.5,
				"next": "tail_whip"},
			"tail_whip": {"kind": "melee", "shape": {"type": "box", "length": 1.0, "width": 2.6},
				"windup": 0.5, "track_until": 0.3, "active": 0.35, "recovery": 1.3, "damage": 1.1,
				"anim": "swipe", "phase": 2, "followup": true},
			"fire_storm": {"kind": "hazard", "air": true, "fire": true, "windup": 1.0, "track_until": 1.0,
				"active": 0.2, "recovery": 0.6, "anim": "roar", "phase": 2, "max_range": 999.0, "range_fixed": true,
				"hazard": {"pattern": "ring_around_target", "count": 6, "spacing": 5.0, "shape": {"type": "circle", "radius": 2.4},
					"arm": 1.0, "duration": 6.0, "tick": 0.5, "damage": 0.16, "tint": "fire"}},
		},
	},
]
const DRAGON_INDEX := 10
const AIR_ATTACKS := 3       # attacks a flying boss makes before it must land
const FLIGHT_HEIGHT := 8.0   # metres the model rises while airborne

# Starless Sovereign stances: [boss index, move id] borrowed from earlier
# bosses. Moves keep their per-size shapes, so they grow to the Sovereign's
# size. Phase-one stances first; the rest unlock in phase two.
const SOVEREIGN_STANCES := {
	"ember": [[0, "ember_arc"], [0, "ground_burst"], [0, "stomp"]],
	"tide": [[3, "water_pulse"], [3, "resonant_cone"], [3, "water_bolts"]],
	"royal": [[2, "royal_1"], [2, "royal_2"], [2, "royal_3"], [2, "delayed_overhead"]],
	"maw": [[5, "darkness_field"], [5, "tail_sweep"], [5, "burrow_lunge"], [0, "charge"]],
	"twin": [[7, "beam"], [7, "cross_1"], [7, "cross_2"], [3, "double_pulse"]],
}
const SOVEREIGN_PHASE_ONE := ["ember", "tide", "royal"]
const SOVEREIGN_PHASE_TWO := ["maw", "twin"]
const STANCE_GLOWS := {
	"ember": Color(0.35, 0.08, 0.02), "tide": Color(0.03, 0.12, 0.3),
	"royal": Color(0.3, 0.24, 0.05), "maw": Color(0.14, 0.03, 0.2), "twin": Color(0.2, 0.2, 0.28),
}

const SCALED_SHAPE_KEYS := ["radius", "offset", "length", "width"]


static func boss_count() -> int:
	return BOSSES.size()


static func boss_size(boss_index: int) -> float:
	return float(BOSSES[clampi(boss_index, 0, BOSSES.size() - 1)]["size"])


# Stats without the moveset: size, health multiplier, speed, posture_max.
static func boss_stats(boss_index: int) -> Dictionary:
	var data: Dictionary = BOSSES[clampi(boss_index, 0, BOSSES.size() - 1)]
	return {"size": data["size"], "health": data["health"], "speed": data["speed"], "posture_max": data["posture_max"]}


# Unscaled move records keyed by id (the Sovereign's are borrowed).
static func raw_moves(boss_index: int) -> Dictionary:
	boss_index = clampi(boss_index, 0, BOSSES.size() - 1)
	if boss_index == 9:
		return _sovereign_moves()
	return (BOSSES[boss_index]["moves"] as Dictionary).duplicate(true)


# Move records with shapes, lunges and melee ranges scaled to the boss.
static func scaled_moves(boss_index: int) -> Dictionary:
	var size := boss_size(boss_index)
	var result := {}
	var raw := raw_moves(boss_index)
	for id in raw:
		result[id] = scale_move(raw[id], size)
		result[id]["id"] = id
	return result


static func scale_move(move: Dictionary, size: float) -> Dictionary:
	var scaled := move.duplicate(true)
	if scaled.has("shape") and not bool(scaled["shape"].get("fixed", false)):
		for key in SCALED_SHAPE_KEYS:
			if scaled["shape"].has(key):
				scaled["shape"][key] = float(scaled["shape"][key]) * size
	if scaled.has("lunge"):
		scaled["lunge"] = float(scaled["lunge"]) * size
	# A charge's line marker covers the whole path.
	if scaled.get("kind", "") == "charge" and scaled.has("shape"):
		scaled["shape"]["length"] = float(scaled.get("charge", 0.0))
	if not bool(scaled.get("range_fixed", false)):
		for key in ["min_range", "max_range"]:
			if scaled.has(key):
				scaled[key] = float(scaled[key]) * size
	if not scaled.has("max_range"):
		scaled["max_range"] = shape_reach(scaled.get("shape", {})) + float(scaled.get("lunge", 0.0))
	scaled["phase"] = int(scaled.get("phase", 1))
	scaled["color"] = String(scaled.get("color", "normal"))
	scaled["track_until"] = minf(float(scaled.get("track_until", 0.0)), float(scaled["windup"]))
	return scaled


static func _sovereign_moves() -> Dictionary:
	var result := {}
	for stance in SOVEREIGN_STANCES:
		var phase := 1 if stance in SOVEREIGN_PHASE_ONE else 2
		for entry in SOVEREIGN_STANCES[stance]:
			var move: Dictionary = (BOSSES[entry[0]]["moves"][entry[1]] as Dictionary).duplicate(true)
			move["stance"] = stance
			move["phase"] = maxi(phase, int(move.get("phase", 1)))
			result[entry[1]] = move
	result["stance_shift"] = {"kind": "stance", "windup": 1.0, "track_until": 1.0, "active": 0.2,
		"recovery": 0.4, "anim": "roar", "max_range": 999.0, "range_fixed": true}
	return result


# Distance from the attack origin to the far edge of a shape.
static func shape_reach(shape: Dictionary) -> float:
	match String(shape.get("type", "")):
		"cone", "ring":
			return float(shape.get("radius", 0.0))
		"circle":
			return float(shape.get("offset", 0.0)) + float(shape.get("radius", 0.0))
		"line", "box":
			return float(shape.get("offset", 0.0)) + float(shape.get("length", 0.0))
	return 0.0


# True when `point` lies inside `shape` placed at `origin` facing `forward`
# (flat XZ test). `margin` widens the shape by the target's body radius.
# Rings use ring_radius (the current wave front) and the shape's width as
# the band thickness.
static func shape_contains(shape: Dictionary, origin: Vector3, forward: Vector3, point: Vector3,
		margin: float = 0.0, ring_radius: float = -1.0) -> bool:
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var rel := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	var ahead := rel.dot(fwd)
	var side := rel.dot(right)
	match String(shape.get("type", "")):
		"cone":
			var radius := float(shape.get("radius", 0.0))
			var distance := rel.length()
			if distance > radius + margin:
				return false
			if distance <= margin + 0.05:
				return true
			var half := deg_to_rad(float(shape.get("angle", 90.0)) * 0.5)
			var angle := acos(clampf(ahead / distance, -1.0, 1.0))
			if angle <= half:
				return true
			# Allow the body radius beyond the cone's straight edges.
			return distance * sin(angle - half) <= margin and angle - half < PI * 0.5
		"circle":
			var centre := fwd * float(shape.get("offset", 0.0))
			return Vector2(rel.x - centre.x, rel.z - centre.z).length() <= float(shape.get("radius", 0.0)) + margin
		"ring":
			var r := ring_radius if ring_radius >= 0.0 else float(shape.get("radius", 0.0))
			var half_width := float(shape.get("width", 1.0)) * 0.5
			return absf(rel.length() - r) <= half_width + margin
		"line", "box":
			var start := float(shape.get("offset", 0.0))
			var length := float(shape.get("length", 0.0))
			var half_width := float(shape.get("width", 1.0)) * 0.5
			return ahead >= start - margin and ahead <= start + length + margin and absf(side) <= half_width + margin
	return false


# Seconds of the wind-up for a move in the given phase.
static func windup_for(move: Dictionary, phase: int) -> float:
	return float(move["windup"]) * (PHASE_TWO_WINDUP if phase >= 2 else 1.0)


# Hands an attack to the player. Players that accept the info dictionary
# (unblockable / parryable / knockback) get it; older two-argument versions
# get just the amount and source. Returns true when the attack was parried.
static func deliver_attack(player, amount: float, source: Node, info: Dictionary) -> bool:
	if not is_instance_valid(player) or not player.has_method("receive_enemy_attack"):
		return false
	var receive := Callable(player, "receive_enemy_attack")
	if receive.get_argument_count() >= 3:
		return bool(player.receive_enemy_attack(amount, source, info))
	return bool(player.receive_enemy_attack(amount, source))
