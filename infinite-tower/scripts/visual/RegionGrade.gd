extends RefCounted

# Cinematic tuning per tower region (indices match RegionProfiles): colour
# grade, how thick the haze and light shafts are, low ground mist, which
# terrain material big impacts throw up, and extra ambience. Purely visual.
#
#   sat / contrast / bright   Environment adjustments (muted, filmic)
#   shadow / highlight        split-tone: tint lifted into the blacks and
#                             blended into the highlights
#   fog                       multiplier on the profile's volumetric density
#   shafts                    sun light-shaft (volumetric) energy
#   mist                      density of the low ground-mist volume
#   impact                    Vfx material: dirt, dust, ash, snow, water, stone
#   ambient                   extra airborne layer: "", "sand", "fine_ash"
#   flames                    flames lick the guardian arena's edge

const GRADES := [
	{"sat": 0.9, "contrast": 1.12, "bright": 1.0, "shadow": Color("#1c1216"), "highlight": Color("#ffd2a0"),
		"fog": 1.2, "shafts": 2.2, "mist": 0.05, "impact": "ash", "ambient": "fine_ash", "flames": true},
	{"sat": 0.88, "contrast": 1.1, "bright": 1.02, "shadow": Color("#0e1618"), "highlight": Color("#ffe2a8"),
		"fog": 1.3, "shafts": 3.6, "mist": 0.04, "impact": "dirt", "ambient": "", "flames": false},
	{"sat": 0.84, "contrast": 1.04, "bright": 1.0, "shadow": Color("#2a1e14"), "highlight": Color("#ffe0b0"),
		"fog": 1.5, "shafts": 2.6, "mist": 0.05, "impact": "dust", "ambient": "sand", "flames": false},
	{"sat": 0.72, "contrast": 1.1, "bright": 1.0, "shadow": Color("#0a1418"), "highlight": Color("#e8eef0"),
		"fog": 1.2, "shafts": 1.4, "mist": 0.09, "impact": "water", "ambient": "", "flames": false},
	{"sat": 0.74, "contrast": 1.08, "bright": 1.0, "shadow": Color("#0e1626"), "highlight": Color("#fff2e0"),
		"fog": 1.1, "shafts": 2.0, "mist": 0.05, "impact": "snow", "ambient": "", "flames": false},
	{"sat": 0.85, "contrast": 1.12, "bright": 1.05, "shadow": Color("#080c18"), "highlight": Color("#d8e4ff"),
		"fog": 1.0, "shafts": 1.5, "mist": 0.06, "impact": "stone", "ambient": "", "flames": false},
	{"sat": 0.7, "contrast": 1.1, "bright": 1.02, "shadow": Color("#0a1214"), "highlight": Color("#dfe8f0"),
		"fog": 1.0, "shafts": 2.0, "mist": 0.1, "impact": "dirt", "ambient": "", "flames": false},
	{"sat": 0.85, "contrast": 1.06, "bright": 1.0, "shadow": Color("#1e1610"), "highlight": Color("#ffd8a0"),
		"fog": 1.4, "shafts": 3.0, "mist": 0.05, "impact": "dust", "ambient": "", "flames": false},
	{"sat": 0.85, "contrast": 1.12, "bright": 1.0, "shadow": Color("#181014"), "highlight": Color("#ffc49a"),
		"fog": 1.3, "shafts": 2.2, "mist": 0.06, "impact": "ash", "ambient": "fine_ash", "flames": true},
	{"sat": 0.8, "contrast": 1.12, "bright": 1.02, "shadow": Color("#0c0a1a"), "highlight": Color("#e8e0ff"),
		"fog": 1.0, "shafts": 1.8, "mist": 0.05, "impact": "stone", "ambient": "", "flames": false},
]


static func get_grade(region_index: int) -> Dictionary:
	return GRADES[clampi(region_index, 0, GRADES.size() - 1)]


# A per-channel 1D lookup (Environment.adjustment_color_correction): blacks
# lift slightly toward the shadow tint, mid-tones stay neutral and the
# highlights lean gently toward the region's light.
static func make_lut(grade: Dictionary) -> GradientTexture1D:
	var shadow: Color = grade["shadow"]
	var highlight: Color = Color.WHITE.lerp(grade["highlight"], 0.3)
	var gradient := Gradient.new()
	gradient.set_color(0, shadow)
	gradient.set_offset(0, 0.0)
	gradient.set_color(1, highlight)
	gradient.set_offset(1, 1.0)
	gradient.add_point(0.22, Color(0.2, 0.2, 0.2).lerp(shadow * 2.2, 0.35))
	gradient.add_point(0.55, Color(0.55, 0.55, 0.55).lerp(highlight * 0.55, 0.25))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	return texture
