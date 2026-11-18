extends RefCounted
class_name RegionProfiles

# Visual direction for each of the ten tower regions (one per boss arc).
# Mood follows the cinematic dark-fantasy reference set: low sun, heavy
# atmosphere, weather and large ruined architecture. Indices match
# TowerCatalog.REGIONS.
#
# Keys:
#   sky_top / sky_horizon / ground_*  procedural sky colours
#   sun_color, sun_energy, sun_pitch, sun_yaw  key light
#   ambient, ambient_energy           fill light
#   fog_color, fog_density            volumetric fog (albedo, density)
#   fog_emission                      fog glow colour (fire, haze, magic)
#   ground_low / ground_high / ground_rock  terrain colours
#   grass_color, grass_tip, grass_density (0..1)
#   tree_kind: "pine", "broadleaf", "dead", "none"; tree_count
#   foliage_color                     canopy colour
#   rock_color, ruin_color
#   weather: "embers", "leaves", "dust", "rain", "snow", "spores",
#            "fireflies", "motes", "ash", "stars"
#   water_level (null for none), hill_height
#   landmark: distant set piece kind
#   stars: show a night sky

const PROFILES := [
	{ # 0 Ashen Threshold — volcanic ruins at dusk
		"sky_top": Color("#1a1013"), "sky_horizon": Color("#a5482a"),
		"ground_horizon": Color("#3a1f1a"), "ground_bottom": Color("#120b0b"),
		"sun_color": Color("#ff9a5c"), "sun_energy": 1.6, "sun_pitch": -12.0, "sun_yaw": -40.0,
		"ambient": Color("#7a4a3a"), "ambient_energy": 0.6,
		"fog_color": Color("#5a3026"), "fog_density": 0.018, "fog_emission": Color("#3a1006"),
		"ground_low": Color("#2a2223"), "ground_high": Color("#3d3030"), "ground_rock": Color("#1c1819"),
		"grass_color": Color("#3b2f22"), "grass_tip": Color("#6b4a2a"), "grass_density": 0.15,
		"tree_kind": "dead", "tree_count": 28, "foliage_color": Color("#2a2020"),
		"rock_color": Color("#262022"), "ruin_color": Color("#4a3c38"),
		"weather": "embers", "water_level": null, "hill_height": 4.0,
		"landmark": "volcano", "stars": false, "lava": true
	},
	{ # 1 Whispering Canopy — ancient golden forest, shafts of light
		"sky_top": Color("#4d6a7a"), "sky_horizon": Color("#d9b77a"),
		"ground_horizon": Color("#4a4a30"), "ground_bottom": Color("#1a1c14"),
		"sun_color": Color("#ffd28a"), "sun_energy": 1.8, "sun_pitch": -22.0, "sun_yaw": 30.0,
		"ambient": Color("#6f7a55"), "ambient_energy": 0.55,
		"fog_color": Color("#c9b080"), "fog_density": 0.014, "fog_emission": Color("#000000"),
		"ground_low": Color("#3d4a26"), "ground_high": Color("#5a5a2e"), "ground_rock": Color("#4a4636"),
		"grass_color": Color("#55602a"), "grass_tip": Color("#c8a447"), "grass_density": 0.85,
		"tree_kind": "broadleaf", "tree_count": 120, "foliage_color": Color("#b07a2a"),
		"rock_color": Color("#5a5848"), "ruin_color": Color("#7a7360"),
		"weather": "leaves", "water_level": null, "hill_height": 5.0,
		"landmark": "great_tree", "stars": false, "lava": false, "wetness": 0.25,
		"flower_colors": [Color("#b81e24"), Color("#f2efe6")], "flower_count": 9000
	},
	{ # 2 Crown of Dust — golden fields around a fallen kingdom
		"sky_top": Color("#5b7ca0"), "sky_horizon": Color("#f0c27a"),
		"ground_horizon": Color("#6a5838"), "ground_bottom": Color("#2a2418"),
		"sun_color": Color("#ffc070"), "sun_energy": 2.0, "sun_pitch": -15.0, "sun_yaw": -70.0,
		"ambient": Color("#8a7458"), "ambient_energy": 0.55,
		"fog_color": Color("#e0b882"), "fog_density": 0.009, "fog_emission": Color("#000000"),
		"ground_low": Color("#6e5e36"), "ground_high": Color("#8a7444"), "ground_rock": Color("#6a5e4e"),
		"grass_color": Color("#8a7a3a"), "grass_tip": Color("#e6c46a"), "grass_density": 1.0,
		"tree_kind": "broadleaf", "tree_count": 24, "foliage_color": Color("#c46a2a"),
		"rock_color": Color("#7a6e5c"), "ruin_color": Color("#a89878"),
		"weather": "dust", "water_level": null, "hill_height": 6.0,
		"landmark": "castle", "stars": false, "lava": false,
		"grass_height": 1.9, "flower_colors": [Color("#f4e7c8")], "flower_count": 5000
	},
	{ # 3 Drowned Reach — rain over a flooded city
		"sky_top": Color("#2a343e"), "sky_horizon": Color("#6a7a82"),
		"ground_horizon": Color("#2e3a40"), "ground_bottom": Color("#121a1e"),
		"sun_color": Color("#a8bcc8"), "sun_energy": 0.7, "sun_pitch": -40.0, "sun_yaw": 10.0,
		"ambient": Color("#4a5a66"), "ambient_energy": 0.65,
		"fog_color": Color("#6a7c86"), "fog_density": 0.022, "fog_emission": Color("#000000"),
		"ground_low": Color("#2e3a36"), "ground_high": Color("#3e4a44"), "ground_rock": Color("#2a3032"),
		"grass_color": Color("#2e4a3a"), "grass_tip": Color("#5a7a5a"), "grass_density": 0.4,
		"tree_kind": "dead", "tree_count": 18, "foliage_color": Color("#2a3a30"),
		"rock_color": Color("#3a4246"), "ruin_color": Color("#5a6a6e"),
		"weather": "rain", "water_level": -0.6, "hill_height": 3.5,
		"landmark": "drowned_spires", "stars": false, "lava": false, "wetness": 0.85
	},
	{ # 4 The Pale March — snowbound pine valley
		"sky_top": Color("#7a8ea0"), "sky_horizon": Color("#d8dde2"),
		"ground_horizon": Color("#a0a8b0"), "ground_bottom": Color("#50585e"),
		"sun_color": Color("#e8eef8"), "sun_energy": 1.3, "sun_pitch": -20.0, "sun_yaw": 50.0,
		"ambient": Color("#8a98a8"), "ambient_energy": 0.7,
		"fog_color": Color("#c8d2dc"), "fog_density": 0.02, "fog_emission": Color("#000000"),
		"ground_low": Color("#c8ced4"), "ground_high": Color("#e6eaee"), "ground_rock": Color("#5a6066"),
		"grass_color": Color("#6a7468"), "grass_tip": Color("#c0c8c0"), "grass_density": 0.06,
		"tree_kind": "pine", "tree_count": 110, "foliage_color": Color("#2a3a34"),
		"rock_color": Color("#5e646a"), "ruin_color": Color("#8a9098"),
		"weather": "snow", "water_level": null, "hill_height": 7.0,
		"landmark": "colossus", "stars": false, "lava": false
	},
	{ # 5 Hollow Deep — dark caverns lit by crystals
		"sky_top": Color("#05060a"), "sky_horizon": Color("#141826"),
		"ground_horizon": Color("#0c0e14"), "ground_bottom": Color("#05060a"),
		"sun_color": Color("#6a7aa8"), "sun_energy": 0.5, "sun_pitch": -60.0, "sun_yaw": 0.0,
		"ambient": Color("#3a4468"), "ambient_energy": 0.9,
		"fog_color": Color("#1a2238"), "fog_density": 0.03, "fog_emission": Color("#0a1430"),
		"ground_low": Color("#22242c"), "ground_high": Color("#2e3038"), "ground_rock": Color("#18191e"),
		"grass_color": Color("#1e3040"), "grass_tip": Color("#3a7a9a"), "grass_density": 0.25,
		"tree_kind": "none", "tree_count": 0, "foliage_color": Color("#000000"),
		"rock_color": Color("#2a2c34"), "ruin_color": Color("#3a3c48"),
		"weather": "spores", "water_level": null, "hill_height": 3.0,
		"landmark": "crystals", "stars": false, "lava": false
	},
	{ # 6 Gloamwood — moonlit haunted woods
		"sky_top": Color("#0a1018"), "sky_horizon": Color("#2a3a44"),
		"ground_horizon": Color("#141c20"), "ground_bottom": Color("#080a0c"),
		"sun_color": Color("#8aa8c8"), "sun_energy": 0.55, "sun_pitch": -35.0, "sun_yaw": -20.0,
		"ambient": Color("#3a5060"), "ambient_energy": 0.85,
		"fog_color": Color("#3a5254"), "fog_density": 0.028, "fog_emission": Color("#000000"),
		"ground_low": Color("#1e2620"), "ground_high": Color("#2a3228"), "ground_rock": Color("#1a1e1e"),
		"grass_color": Color("#1e2e24"), "grass_tip": Color("#3e5a44"), "grass_density": 0.55,
		"tree_kind": "dead", "tree_count": 90, "foliage_color": Color("#1a221e"),
		"rock_color": Color("#262c2c"), "ruin_color": Color("#3a4242"),
		"weather": "fireflies", "water_level": null, "hill_height": 4.0,
		"landmark": "chapel", "stars": true, "lava": false, "wetness": 0.5,
		"flower_colors": [Color("#9fb8e8")], "flower_count": 4000
	},
	{ # 7 Sunken Sepulchre — dusty temple in amber light
		"sky_top": Color("#3a3020"), "sky_horizon": Color("#c89a5a"),
		"ground_horizon": Color("#5a4630"), "ground_bottom": Color("#1e1810"),
		"sun_color": Color("#ffb860"), "sun_energy": 1.6, "sun_pitch": -28.0, "sun_yaw": 80.0,
		"ambient": Color("#6a5238"), "ambient_energy": 0.5,
		"fog_color": Color("#b08a5a"), "fog_density": 0.016, "fog_emission": Color("#000000"),
		"ground_low": Color("#6a5638"), "ground_high": Color("#7e6a48"), "ground_rock": Color("#5a4a38"),
		"grass_color": Color("#5a5030"), "grass_tip": Color("#9a8a4a"), "grass_density": 0.3,
		"tree_kind": "none", "tree_count": 0, "foliage_color": Color("#000000"),
		"rock_color": Color("#6a5a46"), "ruin_color": Color("#b0986e"),
		"weather": "motes", "water_level": null, "hill_height": 2.5,
		"landmark": "temple", "stars": false, "lava": false,
		"flower_colors": [Color("#e8b040")], "flower_count": 3000
	},
	{ # 8 The Red Expanse — smouldering battlefield
		"sky_top": Color("#2a1414"), "sky_horizon": Color("#b04a30"),
		"ground_horizon": Color("#4a2420"), "ground_bottom": Color("#140a0a"),
		"sun_color": Color("#ff7a50"), "sun_energy": 1.3, "sun_pitch": -10.0, "sun_yaw": -100.0,
		"ambient": Color("#5a2e28"), "ambient_energy": 0.45,
		"fog_color": Color("#7a3a2a"), "fog_density": 0.02, "fog_emission": Color("#200804"),
		"ground_low": Color("#3e2a24"), "ground_high": Color("#523830"), "ground_rock": Color("#2a201e"),
		"grass_color": Color("#4a3424"), "grass_tip": Color("#8a5a34"), "grass_density": 0.35,
		"tree_kind": "dead", "tree_count": 20, "foliage_color": Color("#2a1a16"),
		"rock_color": Color("#3a2c28"), "ruin_color": Color("#5e4a42"),
		"weather": "ash", "water_level": null, "hill_height": 4.5,
		"landmark": "war_banners", "stars": false, "lava": false
	},
	{ # 9 Nightglass Summit — black citadel under the stars
		"sky_top": Color("#04040c"), "sky_horizon": Color("#2e2448"),
		"ground_horizon": Color("#141024"), "ground_bottom": Color("#04040a"),
		"sun_color": Color("#a89ae0"), "sun_energy": 0.9, "sun_pitch": -45.0, "sun_yaw": 20.0,
		"ambient": Color("#40386a"), "ambient_energy": 0.9,
		"fog_color": Color("#2a2448"), "fog_density": 0.02, "fog_emission": Color("#100830"),
		"ground_low": Color("#1c1a24"), "ground_high": Color("#26232e"), "ground_rock": Color("#121118"),
		"grass_color": Color("#241e34"), "grass_tip": Color("#5a4a8a"), "grass_density": 0.2,
		"tree_kind": "none", "tree_count": 0, "foliage_color": Color("#000000"),
		"rock_color": Color("#1a1820"), "ruin_color": Color("#2c2a36"),
		"weather": "stars", "water_level": null, "hill_height": 5.0,
		"landmark": "citadel", "stars": true, "lava": false
	}
]


static func get_profile(region_index: int) -> Dictionary:
	return PROFILES[clampi(region_index, 0, PROFILES.size() - 1)]
