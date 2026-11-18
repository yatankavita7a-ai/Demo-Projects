extends Node3D
class_name RegionBuilder

# Builds one floor's environment from its region profile: rolling terrain
# with collision, wind-blown grass, trees, rocks, ruined architecture that
# doubles as stealth cover, distant landmarks for scale, water and weather.
# Everything is generated in code from the world seed, so a floor looks the
# same on every visit. Gameplay positions passed in as reserved points stay
# flat and clear.

const RegionProfilesScript = preload("res://scripts/world/RegionProfiles.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const GRASS_SHADER = preload("res://shaders/grass.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const FOLIAGE_CARDS_SHADER = preload("res://shaders/foliage_cards.gdshader")

const SCANNED_ROOT := "res://assets/polyhaven/%s/%s_%s_2k.jpg"
# Photo-scanned ground per region: [primary, secondary, ground tint, rock tint].
# Tints keep each region's palette while the textures supply real detail.
const GROUND_SETS := [
	["aerial_rocks_02", "rocky_terrain_02", Color("#8a6a64"), Color("#6a5450")],
	["forest_ground_04", "brown_mud_leaves_01", Color("#f0dcb0"), Color("#c8bca0")],
	["coast_sand_01", "rocky_terrain_02", Color("#f2d9a8"), Color("#d8c0a0")],
	["brown_mud_leaves_01", "rocky_terrain_02", Color("#9fb0a8"), Color("#90a0a4")],
	["snow_02", "rocky_terrain_02", Color("#f4f8ff"), Color("#a8b2bc")],
	["aerial_rocks_02", "rock_face", Color("#7c84a4"), Color("#6c7290")],
	["brown_mud_leaves_01", "forest_ground_04", Color("#8aa098"), Color("#7a8a8a")],
	["coast_sand_01", "rocky_terrain_02", Color("#e8c890"), Color("#c8a880")],
	["rocky_terrain_02", "aerial_rocks_02", Color("#b88870"), Color("#8a6a60")],
	["aerial_rocks_02", "rock_face", Color("#7a7096"), Color("#605878")]
]
const HALF_SIZE := 75 # Terrain spans -75..75 with one sample per metre.
const PLAY_LIMIT := 70.0
const FLAT_INNER := 6.0
const FLAT_OUTER := 16.0

var profile: Dictionary = {}
var _noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
# Displaces primitive meshes into weathered stone, craggy rock and foliage.
var _shape_noise := FastNoiseLite.new()
# Landform noise: domain warp bends the hills into natural, non-repeating
# shapes; ridged noise adds spurs and gullies.
var _warp_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _reserved := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _noise_texture: NoiseTexture2D
var _stone_texture: NoiseTexture2D
var _stone_material: StandardMaterial3D
var _bark_material: StandardMaterial3D
var _ground_set: Array = []
# Terrain heights on the 0.5 m visual grid, kept for fast scatter placement.
var _fine_heights := PackedFloat32Array()
var _cover_bodies: Array[StaticBody3D] = []
# Where rain pools (1 m per pixel over the terrain); grass stays out of it.
var _puddle_image: Image
# Radius of a trampled clearing around the origin (used by the camp): no
# grass, flowers, trees, rocks or ruins inside it.
var clearing_radius := 0.0


func build(region_index: int, seed_value: int, reserved_points: Array) -> void:
	configure(region_index, seed_value, reserved_points)
	_noise_texture = _make_noise_texture(seed_value)
	_stone_texture = _make_noise_texture(seed_value + 5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.62))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	_stone_texture.color_ramp = ramp
	_ground_set = GROUND_SETS[clampi(region_index, 0, GROUND_SETS.size() - 1)]
	_stone_material = _make_scanned_material("castle_wall_slates", _texture_tint(profile["ruin_color"]), 0.32)
	_bark_material = _make_scanned_material("bark_brown_02", Color(1, 1, 1).lerp(_texture_tint(profile["foliage_color"]), 0.3), 0.6)
	_build_terrain()
	_build_bounds()
	if profile["water_level"] != null:
		_build_water(float(profile["water_level"]))
	_build_grass()
	_build_flowers()
	_build_ground_scatter()
	_build_trees()
	_build_rocks()
	_build_ruins()
	_build_landmarks()


# Sets up the profile, noise and reserved spots without building anything,
# so height_at() can be queried (and tested) cheaply.
func configure(region_index: int, seed_value: int, reserved_points: Array) -> void:
	profile = RegionProfilesScript.get_profile(region_index)
	_reserved = PackedVector2Array()
	for point in reserved_points:
		_reserved.append(Vector2(point.x, point.z))
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.012
	_noise.fractal_octaves = 4
	_detail_noise.seed = seed_value + 17
	_detail_noise.frequency = 0.08
	_shape_noise.seed = seed_value + 31
	_shape_noise.frequency = 1.0
	_shape_noise.fractal_octaves = 3
	_warp_noise.seed = seed_value + 47
	_warp_noise.frequency = 0.01
	_ridge_noise.seed = seed_value + 59
	_ridge_noise.frequency = 0.02
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4


# Ground height at a world position. Reserved gameplay spots and the main
# path from the spawn to the exit stay flat at 0; the rim rises into hills.
func height_at(x: float, z: float) -> float:
	var hill = float(profile.get("hill_height", 4.0))
	var wx = x + _warp_noise.get_noise_2d(x, z) * 14.0
	var wz = z + _warp_noise.get_noise_2d(x + 113.0, z - 71.0) * 14.0
	var base = (_noise.get_noise_2d(wx, wz) * 0.5 + 0.5) * hill
	base += (_ridge_noise.get_noise_2d(wx, wz) * 0.5 + 0.5) * hill * 0.35
	base += _detail_noise.get_noise_2d(x, z) * 0.25
	# The rim is masked too, so the exit and the path to it stay at ground
	# level; the path cuts a flat pass through the rising rim.
	var edge = maxf(absf(x), absf(z))
	base += smoothstep(52.0, 75.0, edge) * hill * 2.2
	# A few centimetres of unmasked micro-relief so even cleared ground is
	# never perfectly flat.
	return base * _flat_mask(x, z) + _detail_noise.get_noise_2d(x * 3.1, z * 3.1) * 0.03


func _flat_mask(x: float, z: float) -> float:
	var mask := 1.0
	var here := Vector2(x, z)
	for point in _reserved:
		var distance = here.distance_to(point)
		if distance < FLAT_OUTER:
			mask = minf(mask, smoothstep(FLAT_INNER, FLAT_OUTER, distance))
	if z < 34.0 and z > -72.0:
		mask = minf(mask, smoothstep(4.0, 11.0, absf(x)))
	if clearing_radius > 0.0:
		mask = minf(mask, smoothstep(clearing_radius - 4.0, clearing_radius + 8.0, here.length()))
	return mask


func _near_reserved(position: Vector3, clearance: float) -> bool:
	var here := Vector2(position.x, position.z)
	for point in _reserved:
		if here.distance_to(point) < clearance:
			return true
	return absf(position.x) < 5.0 and position.z < 34.0 and position.z > -72.0


# True inside the clearing; its edge wobbles so it looks worn, not drawn.
func _in_clearing(x: float, z: float, margin: float) -> bool:
	if clearing_radius <= 0.0:
		return false
	var edge = clearing_radius + margin + _detail_noise.get_noise_2d(x * 0.3, z * 0.3) * 4.0
	return Vector2(x, z).length() < edge


func get_noise_texture() -> NoiseTexture2D:
	return _noise_texture


func get_cover_bodies() -> Array[StaticBody3D]:
	return _cover_bodies


# --- Terrain -------------------------------------------------------------

func _build_terrain() -> void:
	# The visible ground is sampled every 0.5 m; collision uses every other
	# sample (1 m), which matches it closely on these smooth landforms.
	var samples := HALF_SIZE * 2 + 1
	var fine := (samples - 1) * 2 + 1
	var fine_heights := PackedFloat32Array()
	fine_heights.resize(fine * fine)
	_fine_heights = fine_heights
	for zi in range(fine):
		for xi in range(fine):
			fine_heights[zi * fine + xi] = height_at(xi * 0.5 - HALF_SIZE, zi * 0.5 - HALF_SIZE)
	var heights := PackedFloat32Array()
	heights.resize(samples * samples)
	for zi in range(samples):
		for xi in range(samples):
			heights[zi * samples + xi] = fine_heights[(zi * 2) * fine + xi * 2]

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in range(fine):
		for xi in range(fine):
			var h = fine_heights[zi * fine + xi]
			# Hollows (where the ground sits below its neighbours) collect
			# shadow and debris: store a cavity term for the shader.
			var neighbours = 0.0
			var count = 0
			for offset in [[-2, 0], [2, 0], [0, -2], [0, 2]]:
				var nx = xi + offset[0]
				var nz = zi + offset[1]
				if nx >= 0 and nx < fine and nz >= 0 and nz < fine:
					neighbours += fine_heights[nz * fine + nx]
					count += 1
			var cavity = clampf((neighbours / maxf(count, 1) - h) * 1.4, 0.0, 1.0)
			surface.set_color(Color(1.0 - cavity, 0, 0))
			surface.set_uv(Vector2(float(xi) / fine, float(zi) / fine))
			surface.add_vertex(Vector3(xi * 0.5 - HALF_SIZE, h, zi * 0.5 - HALF_SIZE))
	for zi in range(fine - 1):
		for xi in range(fine - 1):
			var a = zi * fine + xi
			var b = a + 1
			var c = a + fine
			var d = c + 1
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(d)
			surface.add_index(c)
	surface.generate_normals()
	surface.generate_tangents()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Terrain"
	mesh_instance.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("primary_albedo", _scanned(_ground_set[0], "diff"))
	material.set_shader_parameter("primary_normal", _scanned(_ground_set[0], "nor_gl"))
	material.set_shader_parameter("primary_rough", _scanned(_ground_set[0], "rough"))
	material.set_shader_parameter("secondary_albedo", _scanned(_ground_set[1], "diff"))
	material.set_shader_parameter("secondary_normal", _scanned(_ground_set[1], "nor_gl"))
	material.set_shader_parameter("rock_albedo", _scanned("rock_face", "diff"))
	material.set_shader_parameter("rock_normal", _scanned("rock_face", "nor_gl"))
	material.set_shader_parameter("tint", _ground_set[2])
	material.set_shader_parameter("rock_tint", _ground_set[3])
	material.set_shader_parameter("hill_height", profile["hill_height"])
	material.set_shader_parameter("lava_strength", 1.0 if profile.get("lava", false) else 0.0)
	material.set_shader_parameter("wetness", profile.get("wetness", 0.0))
	var rainy: bool = profile["weather"] == "rain"
	var puddle_amount: float = 1.0 if rainy else float(profile.get("wetness", 0.0)) * 0.6
	material.set_shader_parameter("rain_amount", 1.0 if rainy else 0.0)
	material.set_shader_parameter("puddle_amount", puddle_amount)
	if puddle_amount > 0.0:
		material.set_shader_parameter("puddle_mask", _build_puddle_mask(puddle_amount))
		material.set_shader_parameter("terrain_half_size", float(HALF_SIZE))
	material.set_shader_parameter("noise_tex", _noise_texture)
	mesh_instance.material_override = material

	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := HeightMapShape3D.new()
	shape.map_width = samples
	shape.map_depth = samples
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(mesh_instance)
	add_child(body)


# Rain pools on flat, low ground in broad noise patches. Purely visual: the
# ground shader turns the mask into puddles and grass avoids it.
func _build_puddle_mask(amount: float) -> ImageTexture:
	var size := HALF_SIZE * 2
	var noise := FastNoiseLite.new()
	noise.seed = _noise.seed + 71
	noise.frequency = 0.07
	noise.fractal_octaves = 2
	var threshold := lerpf(0.45, 0.12, clampf(amount, 0.0, 1.0))
	var water_level = profile["water_level"]
	_puddle_image = Image.create(size, size, false, Image.FORMAT_L8)
	for zi in range(size):
		for xi in range(size):
			var x := xi - HALF_SIZE + 0.5
			var z := zi - HALF_SIZE + 0.5
			var h := _fast_height(x, z)
			var slope := absf(_fast_height(x + 1.0, z) - _fast_height(x - 1.0, z)) + absf(_fast_height(x, z + 1.0) - _fast_height(x, z - 1.0))
			var value := clampf((noise.get_noise_2d(x, z) - threshold) * 5.0, 0.0, 1.0)
			value *= 1.0 - smoothstep(0.12, 0.45, slope)
			value *= 1.0 - smoothstep(0.6, 2.2, h)
			if water_level != null and h < float(water_level):
				value = 0.0
			_puddle_image.set_pixel(xi, zi, Color(value, value, value))
	return ImageTexture.create_from_image(_puddle_image)


func _puddle_at(x: float, z: float) -> float:
	if _puddle_image == null:
		return 0.0
	var xi := clampi(int(x + HALF_SIZE), 0, _puddle_image.get_width() - 1)
	var zi := clampi(int(z + HALF_SIZE), 0, _puddle_image.get_height() - 1)
	return _puddle_image.get_pixel(xi, zi).r


# Invisible walls keep the player inside; the rising rim hides them.
func _build_bounds() -> void:
	for side in [-1.0, 1.0]:
		_add_invisible_wall(Vector3(side * 74.0, 10.0, 0), Vector3(2, 40, 150))
		_add_invisible_wall(Vector3(0, 10.0, side * 74.0), Vector3(150, 40, 2))


func _add_invisible_wall(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.position = position
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_water(level: float) -> void:
	var water := MeshInstance3D.new()
	water.name = "Floodwater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(520, 520)
	water.mesh = plane
	water.position.y = level
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("noise_tex", _noise_texture)
	material.set_shader_parameter("deep_color", Color(profile["fog_color"]).darkened(0.8))
	material.set_shader_parameter("shallow_color", Color(profile["fog_color"]).darkened(0.45))
	water.material_override = material
	add_child(water)


# --- Vegetation ------------------------------------------------------------

const GRASS_TILE := 10.0

func _build_grass() -> void:
	var density = float(profile["grass_density"])
	if density <= 0.0:
		return
	# Grass is grouped into 10 m tiles. Each tile is its own MultiMesh with a
	# visibility range, so off-screen and distant tiles cost nothing and the
	# field can be dense around the player.
	var tiles_per_side = int(ceil(PLAY_LIMIT * 2.0 / GRASS_TILE))
	var tufts_per_tile = int(1250 * density)
	var blade_mesh = _make_blade_mesh()
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("base_color", profile["grass_color"])
	material.set_shader_parameter("tip_color", profile["grass_tip"])
	material.set_shader_parameter("wind_strength", 0.45 if profile["weather"] in ["leaves", "dust", "rain"] else 0.25)
	var water_level = profile["water_level"]
	var grass_height = float(profile.get("grass_height", 1.0))
	for tile_z in range(tiles_per_side):
		for tile_x in range(tiles_per_side):
			var min_x = -PLAY_LIMIT + tile_x * GRASS_TILE
			var min_z = -PLAY_LIMIT + tile_z * GRASS_TILE
			var buffer := PackedFloat32Array()
			buffer.resize(tufts_per_tile * 12)
			var placed := 0
			for attempt in range(tufts_per_tile):
				var x = min_x + _rng.randf() * GRASS_TILE
				var z = min_z + _rng.randf() * GRASS_TILE
				# Only the barest patches are left open, for natural clumping.
				if _detail_noise.get_noise_2d(x * 0.6, z * 0.6) < -0.45 or _in_clearing(x, z, 0.0):
					continue
				var y = _fast_height(x, z)
				if water_level != null and y < float(water_level) + 0.05:
					continue
				if _puddle_at(x, z) > 0.2:
					continue
				var angle = _rng.randf() * TAU
				var scale = _rng.randf_range(0.75, 1.3)
				var tall = scale * _rng.randf_range(0.7, 1.4) * grass_height
				var c = cos(angle) * scale
				var s_ = sin(angle) * scale
				var o = placed * 12
				# Row-major 3x4: rotation about Y with scale, then translation.
				buffer[o] = c
				buffer[o + 1] = 0.0
				buffer[o + 2] = s_
				buffer[o + 3] = x
				buffer[o + 4] = 0.0
				buffer[o + 5] = tall
				buffer[o + 6] = 0.0
				buffer[o + 7] = y
				buffer[o + 8] = -s_
				buffer[o + 9] = 0.0
				buffer[o + 10] = c
				buffer[o + 11] = z
				placed += 1
			if placed == 0:
				continue
			buffer.resize(placed * 12)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = blade_mesh
			multimesh.instance_count = placed
			multimesh.buffer = buffer
			var instance := MultiMeshInstance3D.new()
			instance.name = "Grass"
			instance.multimesh = multimesh
			instance.material_override = material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = 78.0
			# Grass is too dense (and too thin) to be worth voxelising for SDFGI.
			instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			instance.visibility_range_end_margin = 6.0
			add_child(instance)


# Bilinear lookup on the 0.5 m terrain grid: much cheaper than height_at()
# for the tens of thousands of grass tufts.
func _fast_height(x: float, z: float) -> float:
	var fine := HALF_SIZE * 4 + 1
	var gx = clampf((x + HALF_SIZE) * 2.0, 0.0, fine - 1.001)
	var gz = clampf((z + HALF_SIZE) * 2.0, 0.0, fine - 1.001)
	var ix = int(gx)
	var iz = int(gz)
	var fx = gx - ix
	var fz = gz - iz
	var a = _fine_heights[iz * fine + ix]
	var b = _fine_heights[iz * fine + ix + 1]
	var c = _fine_heights[(iz + 1) * fine + ix]
	var d = _fine_heights[(iz + 1) * fine + ix + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


# Six narrow blades from one root, each curving outward in two segments;
# UV.y runs from 0 at the root to 1 at the tip.
func _make_blade_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(6):
		var angle = TAU * float(blade) / 6.0 + 0.4 + float(blade % 2) * 0.3
		var side := Vector3(cos(angle), 0, sin(angle))
		var out := Vector3(-sin(angle), 0, cos(angle))
		var height = 0.34 + 0.1 * float(blade % 2)
		var width = 0.022
		var base_l = -side * width
		var base_r = side * width
		var mid = out * 0.05 + Vector3(0, height * 0.55, 0)
		var mid_l = mid - side * width * 0.7
		var mid_r = mid + side * width * 0.7
		var tip = out * 0.15 + Vector3(0, height, 0)
		var quad = [[base_l, 0.0], [base_r, 0.0], [mid_r, 0.55], [base_l, 0.0], [mid_r, 0.55], [mid_l, 0.55]]
		for corner in quad:
			surface.set_uv(Vector2(0.5, corner[1]))
			surface.add_vertex(corner[0])
		for corner in [[mid_l, 0.55], [mid_r, 0.55], [tip, 1.0]]:
			surface.set_uv(Vector2(0.5, corner[1]))
			surface.add_vertex(corner[0])
	surface.generate_normals()
	return surface.commit()


# Flower fields: drifts of one or two bold colours, grouped by noise so they
# form sweeping patches rather than an even sprinkle.
func _build_flowers() -> void:
	var colors: Array = profile.get("flower_colors", [])
	if colors.is_empty():
		return
	var water_level = profile["water_level"]
	var count = int(profile.get("flower_count", 9000))
	for color_index in range(colors.size()):
		var transforms: Array[Transform3D] = []
		var attempts = count * 3
		while transforms.size() < count / colors.size() and attempts > 0:
			attempts -= 1
			var x = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
			var z = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
			var patch = _warp_noise.get_noise_2d(x * 3.0 + color_index * 200.0, z * 3.0)
			if patch < 0.05 or _in_clearing(x, z, 2.0):
				continue
			var y = height_at(x, z)
			if water_level != null and y < float(water_level):
				continue
			var scale = _rng.randf_range(0.8, 1.25)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale * _rng.randf_range(0.8, 1.3), scale))
			transforms.append(Transform3D(basis, Vector3(x, y, z)))
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.7
		material.backlight_enabled = true
		material.backlight = Color(colors[color_index]).darkened(0.3)
		_add_multimesh("Flowers", _make_flower_mesh(colors[color_index]), material, transforms)
		get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# A thin green stem with a cup of petals; colours are baked into vertex
# colours so the stem stays green whatever the bloom colour.
func _make_flower_mesh(bloom_color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_color = Color(0.22, 0.32, 0.16)
	var height = 0.55
	for side in [Vector3(0.012, 0, 0), Vector3(0, 0, 0.012)]:
		for corner in [[-side, 0.0], [side, 0.0], [side + Vector3(0, height, 0), 1.0], [-side, 0.0], [side + Vector3(0, height, 0), 1.0], [-side + Vector3(0, height, 0), 1.0]]:
			surface.set_color(stem_color)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corner[0])
	var bloom = Vector3(0, height, 0)
	# Upturned petals form a cup that reads as a bloom from any angle.
	for petal in range(7):
		var angle = TAU * float(petal) / 7.0
		var out = Vector3(cos(angle), 1.1, sin(angle)) * 0.075
		var side = Vector3(-sin(angle), 0, cos(angle)) * 0.035
		for corner in [bloom, bloom + out + side, bloom + out - side]:
			surface.set_color(bloom_color)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corner)
	return surface.commit()


# Pebbles everywhere, and fallen leaves on wooded floors: the small debris
# that makes ground read as real at walking distance.
func _build_ground_scatter() -> void:
	var water_level = profile["water_level"]
	var pebbles: Array[Transform3D] = []
	for index in range(900):
		var x = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var z = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var y = height_at(x, z)
		if water_level != null and y < float(water_level):
			continue
		var size = _rng.randf_range(0.06, 0.28)
		var basis := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		basis = basis.scaled(Vector3(size * _rng.randf_range(1.0, 1.7), size * _rng.randf_range(0.5, 0.9), size))
		pebbles.append(Transform3D(basis, Vector3(x, y - size * 0.2, z)))
	var pebble := SphereMesh.new()
	pebble.radial_segments = 8
	pebble.rings = 5
	var pebble_material = _make_scanned_material("rock_face", _ground_set[3], 1.4)
	var instance_count = pebbles.size()
	_add_multimesh("Pebbles", _weathered(pebble, 0.12, 4.0, true), pebble_material, pebbles)
	if instance_count > 0:
		get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if profile["tree_kind"] != "broadleaf" and profile["weather"] != "fireflies":
		return
	var leaves: Array[Transform3D] = []
	for index in range(5000):
		var x = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var z = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var y = height_at(x, z) + 0.02
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.18, 0.35))
		leaves.append(Transform3D(basis, Vector3(x, y, z)))
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners = [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	var local = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for index in [0, 2, 1, 0, 3, 2]:
		leaf.set_normal(Vector3.UP)
		leaf.set_color(Color(0.8, 0, 0))
		leaf.set_uv(local[index] * 0.45)
		leaf.set_uv2(local[index])
		leaf.add_vertex(corners[index])
	var leaf_material = _make_leaf_material()
	leaf_material.set_shader_parameter("leaf_color", Color(profile["foliage_color"]).darkened(0.25))
	leaf_material.set_shader_parameter("sway", 0.0)
	_add_multimesh("Fallen Leaves", leaf.commit(), leaf_material, leaves)
	get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_trees() -> void:
	var kind: String = profile["tree_kind"]
	var target = int(profile["tree_count"])
	if kind == "none" or target <= 0:
		return
	var trunk_mesh: Mesh
	var canopy_mesh: Mesh
	match kind:
		"pine":
			trunk_mesh = _offset_mesh(_cylinder(0.05, 0.36, 7.6, Vector3.ZERO), Vector3(0, 3.8, 0))
			canopy_mesh = _make_pine_canopy()
		"broadleaf":
			trunk_mesh = _offset_mesh(_cylinder(0.25, 0.5, 4.0, Vector3.ZERO), Vector3(0, 2.0, 0))
			canopy_mesh = _make_broadleaf_canopy()
		_:
			trunk_mesh = _make_dead_tree()
	var trunk_transforms: Array[Transform3D] = []
	var water_level = profile["water_level"]
	var attempts = target * 8
	while trunk_transforms.size() < target and attempts > 0:
		attempts -= 1
		var x = _rng.randf_range(-PLAY_LIMIT + 2.0, PLAY_LIMIT - 2.0)
		var z = _rng.randf_range(-PLAY_LIMIT + 2.0, PLAY_LIMIT - 2.0)
		var position = Vector3(x, 0, z)
		if _near_reserved(position, 9.0) or _in_clearing(position.x, position.z, 6.0):
			continue
		# Forest stands: trees gather where the broad noise is high.
		if _noise.get_noise_2d(x * 1.8, z * 1.8) < -0.1 and _rng.randf() < 0.7:
			continue
		position.y = height_at(x, z) - 0.15
		if water_level != null and position.y < float(water_level) - 0.3 and kind != "dead":
			continue
		var scale = _rng.randf_range(0.85, 1.6)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		trunk_transforms.append(Transform3D(basis, position))
		_add_cover_cylinder(position, 0.45 * scale, 6.0 * scale)
	_add_multimesh("Tree Trunks", trunk_mesh, _bark_material, trunk_transforms)
	if canopy_mesh:
		var material: ShaderMaterial
		if kind == "broadleaf":
			material = _make_leaf_material()
		elif kind == "pine":
			material = _make_leaf_material(true)
		else:
			material = ShaderMaterial.new()
			material.shader = FOLIAGE_SHADER
			material.set_shader_parameter("leaf_color", profile["foliage_color"])
			material.set_shader_parameter("noise_tex", _noise_texture)
		_add_multimesh("Tree Canopies", canopy_mesh, material, trunk_transforms)


# Conifer as drooping branch cards: tiers of branches radiate from the trunk,
# longest at the bottom, each card cut out by the needle pattern.
func _make_pine_canopy() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := 16
	for tier in range(tiers):
		var t = float(tier) / float(tiers - 1)
		var height = lerpf(1.6, 7.2, t)
		var length = lerpf(2.6, 0.5, t)
		var branches = int(lerpf(13.0, 6.0, t))
		var twist = _rng.randf() * TAU
		for branch in range(branches):
			var yaw = twist + TAU * float(branch) / float(branches) + _rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(yaw), 0, sin(yaw))
			var side := Vector3(-sin(yaw), 0, cos(yaw))
			var droop = _rng.randf_range(0.25, 0.5)
			var root = Vector3(0, height, 0)
			var tip = root + out * length + Vector3(0, -length * droop, 0)
			var width = length * 0.85
			var normal = (out + Vector3(0, 0.6, 0)).normalized()
			# Two crossed cards per branch (flat spray + upright spray) give
			# the bough volume from every viewing angle.
			var axis = (tip - root).normalized()
			for plane in range(2):
				var spread = side if plane == 0 else side.rotated(axis, 1.2)
				var corners = [root - spread * width * 0.2, root + spread * width * 0.2, tip + spread * width * 0.5, tip - spread * width * 0.5]
				var local = [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1)]
				var uv_offset = Vector2(_rng.randf(), _rng.randf())
				for index in [0, 1, 2, 0, 2, 3]:
					surface.set_normal(normal)
					surface.set_color(Color(lerpf(0.5, 1.0, float(index in [2, 3])), 0, 0))
					surface.set_uv(uv_offset + local[index] * Vector2(0.45, 0.9))
					surface.set_uv2(Vector2(local[index].x, (local[index].y - 0.5) * 0.5 + 0.25))
					surface.add_vertex(corners[index])
	return surface.commit()


# Broadleaf canopy as leaf cards scattered through five overlapping clusters.
func _make_broadleaf_canopy() -> ArrayMesh:
	var clusters = [
		[Vector3(0, 5.2, 0), 2.4], [Vector3(1.5, 4.6, 0.6), 1.7], [Vector3(-1.4, 4.8, -0.5), 1.8],
		[Vector3(0.3, 6.4, -1.0), 1.5], [Vector3(-0.6, 4.3, 1.4), 1.6]
	]
	var canopy_center := Vector3(0, 5.1, 0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cluster in clusters:
		var center: Vector3 = cluster[0]
		var radius: float = cluster[1]
		for card in range(int(radius * 17.0)):
			var direction = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.7, 1), _rng.randf_range(-1, 1)).normalized()
			var position = center + direction * radius * sqrt(_rng.randf()) * 0.85
			var outward = (position - canopy_center).normalized()
			var depth = clampf((position - canopy_center).length() / 3.2, 0.0, 1.0)
			var basis := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
			var size = _rng.randf_range(1.5, 2.2)
			var right = basis.x * size * 0.5
			var up = basis.y * size * 0.5
			var uv_offset = Vector2(_rng.randf(), _rng.randf())
			var corners = [position - right - up, position + right - up, position + right + up, position - right + up]
			var local = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for index in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(outward)
				surface.set_color(Color(depth, 0, 0))
				surface.set_uv(uv_offset + local[index] * 0.45)
				surface.set_uv2(local[index])
				surface.add_vertex(corners[index])
	return surface.commit()


func _make_leaf_material(needles: bool = false) -> ShaderMaterial:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	# Needles: smaller, denser cells read as fine conifer sprays.
	noise.frequency = 0.055 if needles else 0.035
	noise.seed = _rng.randi()
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.invert = true
	texture.generate_mipmaps = true
	texture.noise = noise
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_CARDS_SHADER
	material.set_shader_parameter("leaf_color", profile["foliage_color"])
	material.set_shader_parameter("leaf_mask", texture)
	return material


func _make_dead_tree() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(_cylinder(0.12, 0.38, 5.0, Vector3.ZERO), 0, Transform3D(Basis(), Vector3(0, 2.5, 0)))
	var branches = [
		[Vector3(0, 3.2, 0), Vector3(0, 0, 0.9), 2.0], [Vector3(0, 3.8, 0), Vector3(0.8, 2.1, -0.7), 1.7],
		[Vector3(0, 2.6, 0), Vector3(-0.9, 4.0, 0.6), 1.5], [Vector3(0, 4.4, 0), Vector3(0.5, 1.0, -0.4), 1.2]
	]
	for branch in branches:
		var basis := Basis.from_euler(branch[1])
		var offset: Vector3 = branch[0] + basis * Vector3(0, branch[2] * 0.5, 0)
		surface.append_from(_cylinder(0.04, 0.11, branch[2], Vector3.ZERO), 0, Transform3D(basis, offset))
	surface.generate_normals()
	return surface.commit()


func _cylinder(top: float, bottom: float, height: float, _offset: Vector3) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return mesh


func _build_rocks() -> void:
	var variants: Array = [[], [], []]
	for index in range(70):
		var x = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var z = _rng.randf_range(-PLAY_LIMIT, PLAY_LIMIT)
		var position = Vector3(x, 0, z)
		if _near_reserved(position, 7.0) or _in_clearing(position.x, position.z, 2.0):
			continue
		var size = _rng.randf_range(0.4, 1.0) if _rng.randf() < 0.8 else _rng.randf_range(1.6, 3.2)
		position.y = height_at(x, z) - size * 0.25
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.4, _rng.randf() * TAU, _rng.randf() * 0.4))
		basis = basis.scaled(Vector3(size * _rng.randf_range(1.0, 1.6), size * _rng.randf_range(0.6, 1.0), size))
		variants[index % 3].append(Transform3D(basis, position))
		if size > 1.5:
			_add_cover_box(position + Vector3(0, size * 0.3, 0), Vector3.ONE * size * 1.3, basis.get_euler().y)
	var rock_material = _make_scanned_material("rock_face", _ground_set[3], 0.45)
	for variant in range(3):
		var sphere := SphereMesh.new()
		sphere.radial_segments = 18
		sphere.rings = 12
		var boulder = _weathered(sphere, 0.2, 2.0 + variant * 0.6, true)
		var typed: Array[Transform3D] = []
		typed.assign(variants[variant])
		_add_multimesh("Rocks", boulder, rock_material, typed)


# --- Architecture ----------------------------------------------------------

func _build_ruins() -> void:
	var placed = 0
	var attempts = 0
	while placed < 16 and attempts < 200:
		attempts += 1
		var x = _rng.randf_range(-62, 62)
		var z = _rng.randf_range(-58, 55)
		var position = Vector3(x, 0, z)
		# Pieces spread up to ~7 m from their origin, so keep origins well
		# clear of gameplay spots and the main path.
		if position.length() < maxf(14.0, clearing_radius + 10.0) or _near_reserved(position, 17.0) or (absf(x) < 13.0 and z < 40.0 and z > -76.0):
			continue
		position.y = height_at(x, z)
		var yaw = _rng.randf() * TAU
		match _rng.randi_range(0, 3):
			0:
				_add_pillar_group(position, yaw)
			1:
				_add_broken_wall(position, yaw)
			2:
				_add_arch(position, yaw)
			_:
				_add_fallen_column(position, yaw)
		placed += 1


func _add_pillar_group(origin: Vector3, yaw: float) -> void:
	for index in range(_rng.randi_range(2, 4)):
		var offset := Vector3(index * 3.2 - 3.0, 0, _rng.randf_range(-0.6, 0.6)).rotated(Vector3.UP, yaw)
		var height = _rng.randf_range(2.0, 7.5)
		var base = origin + offset
		base.y = height_at(base.x, base.z)
		_add_stone_box(base + Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 1.8), yaw)
		var column := CylinderMesh.new()
		column.top_radius = 0.62
		column.bottom_radius = 0.7
		column.height = height
		column.radial_segments = 14
		column.rings = maxi(2, int(height * 1.5))
		_add_stone_mesh(_weathered(column, 0.07, 1.3, true), Transform3D(Basis(Vector3.UP, yaw).rotated(Vector3.FORWARD, _rng.randf_range(-0.05, 0.05)), base + Vector3(0, 0.6 + height * 0.5, 0)))
		_add_cover_cylinder(base, 0.7, height + 0.6)
		if _rng.randf() < 0.5:
			_add_stone_box(base + Vector3(0, 0.6 + height + 0.25, 0), Vector3(1.6, 0.5, 1.6), yaw)


func _add_broken_wall(origin: Vector3, yaw: float) -> void:
	var segments = _rng.randi_range(3, 5)
	for index in range(segments):
		var offset := Vector3(index * 2.0 - segments, 0, 0).rotated(Vector3.UP, yaw)
		var base = origin + offset
		base.y = height_at(base.x, base.z)
		var height = _rng.randf_range(1.2, 5.5)
		_add_stone_box(base + Vector3(0, height * 0.5, 0), Vector3(2.0, height, 1.1), yaw)


func _add_arch(origin: Vector3, yaw: float) -> void:
	var span = 4.5
	for side in [-1.0, 1.0]:
		var base = origin + Vector3(side * span * 0.5, 0, 0).rotated(Vector3.UP, yaw)
		base.y = height_at(base.x, base.z)
		_add_stone_box(base + Vector3(0, 3.0, 0), Vector3(1.2, 6.0, 1.2), yaw)
	if _rng.randf() < 0.75:
		_add_stone_box(origin + Vector3(0, 6.4, 0), Vector3(span + 1.6, 0.9, 1.3), yaw)


func _add_fallen_column(origin: Vector3, yaw: float) -> void:
	var column := CylinderMesh.new()
	column.top_radius = 0.65
	column.bottom_radius = 0.65
	column.height = _rng.randf_range(4.0, 7.0)
	column.radial_segments = 14
	column.rings = int(column.height * 1.5)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)
	_add_stone_mesh(_weathered(column, 0.08, 1.3, true), Transform3D(basis, origin + Vector3(0, 0.45, 0)))
	_add_cover_box(origin + Vector3(0, 0.5, 0), Vector3(column.height, 1.2, 1.2), yaw)


func _add_stone_box(center: Vector3, size: Vector3, yaw: float) -> void:
	_add_stone_mesh(_weathered_box(size), Transform3D(Basis(Vector3.UP, yaw), center))
	_add_cover_box(center, size, yaw)


func _add_stone_mesh(mesh: Mesh, transform_value: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _stone_material
	instance.transform = transform_value
	add_child(instance)


# Cover bodies block movement and line of sight, and count as "ruined
# cover" for equipment such as the Mossmantle.
func _add_cover_box(center: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Ruined Stone"
	body.add_to_group("world_cover")
	body.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_cover_bodies.append(body)


func _add_cover_cylinder(base: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Cover"
	body.add_to_group("world_cover")
	body.position = base + Vector3(0, height * 0.5, 0)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_cover_bodies.append(body)


# --- Landmarks ---------------------------------------------------------------

func _build_landmarks() -> void:
	_build_mountain_ring()
	_build_tower_spire()
	var far_material = _make_scanned_material("castle_wall_slates", _texture_tint(profile["ruin_color"]).darkened(0.2), 0.08)
	match profile["landmark"]:
		"volcano":
			var volcano_material := _make_scanned_material("rock_face", Color.WHITE, 0.03)
			volcano_material.vertex_color_use_as_albedo = true
			_add_far_mesh(_make_mountain(110.0, 150.0, Color(profile["ground_rock"]), Color(0, 0, 0, 0)), Transform3D(Basis(), Vector3(-140, -6, -190)), volcano_material)
			var glow := OmniLight3D.new()
			glow.position = Vector3(-140, 90, -190)
			glow.light_color = Color("#ff5a1a")
			glow.light_energy = 8.0
			glow.omni_range = 120.0
			add_child(glow)
		"great_tree":
			var trunk := _cylinder(7.0, 12.0, 120.0, Vector3.ZERO)
			_add_far_mesh(trunk, Transform3D(Basis(), Vector3(150, 60, -170)), _bark_material)
			# The ancient tree: an ordinary canopy scaled up, so it shares the
			# broken leaf silhouette instead of reading as one smooth dome.
			_add_far_mesh(_make_broadleaf_canopy(), Transform3D(Basis().scaled(Vector3.ONE * 16.0), Vector3(150, 40, -170)), _make_leaf_material())
		"castle":
			for index in range(5):
				var x = -120.0 + index * 45.0
				_add_far_box(Vector3(x, 0, -200), Vector3(14, 70 + (index % 2) * 30, 14), far_material)
				if index < 4:
					_add_far_box(Vector3(x + 22.5, 0, -200), Vector3(32, 34, 8), far_material)
		"drowned_spires":
			for index in range(7):
				var angle = -0.9 + index * 0.3
				var position = Vector3(sin(angle) * 180.0, -4.0, -cos(angle) * 180.0)
				_add_far_cone(position, 10.0 + index % 3 * 4.0, 60.0 + (index * 13) % 50, far_material)
		"colossus":
			_build_colossus(Vector3(110, 0, -150), far_material)
		"crystals":
			_build_crystal_field()
		"chapel":
			_add_far_box(Vector3(-110, 0, -160), Vector3(30, 40, 60), far_material)
			_add_far_cone(Vector3(-110, 40, -185), 9.0, 50.0, far_material)
		"temple":
			for step in range(6):
				var size = 120.0 - step * 18.0
				_add_far_box(Vector3(0, step * 9.0, -230), Vector3(size, 9.0, size), far_material)
		"war_banners":
			_build_war_banners()
		"citadel":
			for index in range(6):
				var angle = -0.6 + index * 0.24
				var position = Vector3(sin(angle) * 200.0, 0, -cos(angle) * 200.0)
				_add_far_box(position, Vector3(16, 110 + (index * 37) % 90, 16), far_material)
				_add_far_cone(position + Vector3(0, 110 + (index * 37) % 90, 0), 11.0, 40.0, far_material)


func _build_mountain_ring() -> void:
	var rock = Color(profile["ground_rock"]).lerp(Color(profile["fog_color"]), 0.25)
	var snow = Color("#e6ecf0") if profile["weather"] == "snow" else Color(0, 0, 0, 0)
	var material := _make_scanned_material("rock_face", Color.WHITE, 0.025)
	material.vertex_color_use_as_albedo = true
	for index in range(16):
		var angle = TAU * float(index) / 16.0 + _rng.randf_range(-0.1, 0.1)
		var distance = _rng.randf_range(175.0, 240.0)
		var position = Vector3(cos(angle) * distance, -8.0, sin(angle) * distance)
		var mountain = _make_mountain(_rng.randf_range(60.0, 95.0), _rng.randf_range(45.0, 115.0), rock, snow)
		_add_far_mesh(mountain, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), position), material)


# A mountain from ridged noise over a radial falloff: sharp ridgelines and
# gullies instead of a cone. Optional snow settles on the upper slopes.
func _make_mountain(radius: float, height: float, rock: Color, snow: Color) -> ArrayMesh:
	var ridge := FastNoiseLite.new()
	ridge.seed = _rng.randi()
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 2.2 / radius
	ridge.fractal_octaves = 5
	var steps := 44
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in range(steps + 1):
		for xi in range(steps + 1):
			var x = (float(xi) / steps * 2.0 - 1.0) * radius
			var z = (float(zi) / steps * 2.0 - 1.0) * radius
			var falloff = pow(clampf(1.0 - Vector2(x, z).length() / radius, 0.0, 1.0), 1.3)
			var y = height * falloff * (0.45 + 0.55 * (ridge.get_noise_2d(x, z) * 0.5 + 0.5)) - 4.0
			var color = rock.darkened(0.15 * (1.0 - falloff))
			if snow.a > 0.0 and y > height * (0.42 + ridge.get_noise_2d(z, x) * 0.08):
				color = snow
			surface.set_color(color)
			surface.add_vertex(Vector3(x, y, z))
	for zi in range(steps):
		for xi in range(steps):
			var a = zi * (steps + 1) + xi
			var b = a + 1
			var c = a + steps + 1
			var d = c + 1
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(d)
			surface.add_index(c)
	surface.generate_normals()
	return surface.commit()


# The Infinite Tower itself rises behind every floor: a colossal, tapering
# spire whose upper windows glow, so the player always sees where they climb.
func _build_tower_spire() -> void:
	var material := _make_textured_material(Color("#2e2b33"), 0.9)
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("#141218")
	band.emission_enabled = true
	band.emission = Color("#c9a6ff")
	band.emission_energy_multiplier = 1.4
	var origin := Vector3(-30, -10, -330)
	var height := 0.0
	for tier in range(8):
		var radius = 34.0 - tier * 3.6
		var tier_height = 70.0 - tier * 4.0
		var section := _cylinder(radius * 0.92, radius, tier_height, Vector3.ZERO)
		section.radial_segments = 16
		_add_far_mesh(section, Transform3D(Basis(), origin + Vector3(0, height + tier_height * 0.5, 0)), material)
		height += tier_height
		var ring := _cylinder(radius * 0.95, radius * 0.95, 1.5, Vector3.ZERO)
		ring.radial_segments = 16
		_add_far_mesh(ring, Transform3D(Basis(), origin + Vector3(0, height, 0)), band if tier >= 4 else material)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 7.0
	cap.height = 60.0
	cap.radial_segments = 16
	_add_far_mesh(cap, Transform3D(Basis(), origin + Vector3(0, height + 30.0, 0)), material)


func _build_colossus(origin: Vector3, material: Material) -> void:
	# A kneeling stone giant gripping a sword planted in the ground.
	_add_far_box(origin, Vector3(30, 26, 22), material)
	_add_far_box(origin + Vector3(0, 26, 0), Vector3(26, 34, 16), material)
	_add_far_box(origin + Vector3(0, 66, 2), Vector3(13, 14, 13), material)
	_add_far_box(origin + Vector3(-17, 30, 4), Vector3(8, 30, 8), material)
	_add_far_box(origin + Vector3(17, 30, 4), Vector3(8, 30, 8), material)
	_add_far_box(origin + Vector3(0, 0, -16), Vector3(4, 70, 2), material)
	_add_far_box(origin + Vector3(0, 52, -16), Vector3(18, 3, 3), material)


func _build_crystal_field() -> void:
	var colors = [Color("#4ad0ff"), Color("#7a6aff"), Color("#3affc8")]
	for index in range(14):
		var x = _rng.randf_range(-62, 62)
		var z = _rng.randf_range(-62, 62)
		var position = Vector3(x, 0, z)
		if _near_reserved(position, 9.0) or _in_clearing(position.x, position.z, 6.0):
			continue
		position.y = height_at(x, z)
		var color: Color = colors[index % colors.size()]
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.4)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.5
		for shard in range(_rng.randi_range(2, 4)):
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = _rng.randf_range(0.3, 0.7)
			crystal.height = _rng.randf_range(1.5, 4.0)
			crystal.radial_segments = 5
			var tilt = Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4)))
			var instance := MeshInstance3D.new()
			instance.mesh = crystal
			instance.material_override = material
			instance.transform = Transform3D(tilt, position + Vector3(0, crystal.height * 0.4, 0))
			add_child(instance)
		var light := OmniLight3D.new()
		light.position = position + Vector3(0, 2.0, 0)
		light.light_color = color
		light.light_energy = 1.6
		light.omni_range = 11.0
		add_child(light)


func _build_war_banners() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#6a1a16")
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index in range(22):
		var x = _rng.randf_range(-64, 64)
		var z = _rng.randf_range(-64, 64)
		var position = Vector3(x, 0, z)
		if _near_reserved(position, 8.0):
			continue
		position.y = height_at(x, z)
		var lean = Basis.from_euler(Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25)))
		var pole := _cylinder(0.05, 0.07, 5.0, Vector3.ZERO)
		_add_far_mesh(pole, Transform3D(lean, position + lean * Vector3(0, 2.5, 0)), _bark_material)
		if _rng.randf() < 0.5:
			var flag := QuadMesh.new()
			flag.size = Vector2(1.4, 2.0)
			_add_far_mesh(flag, Transform3D(lean, position + lean * Vector3(0.7, 3.8, 0)), cloth)


func _add_far_cone(base: Vector3, radius: float, height: float, material: Material) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = radius * 0.06
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 12
	cone.rings = 8
	_add_far_mesh(_weathered(cone, radius * 0.12, 3.0 / maxf(radius, 1.0), true), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(0, height * 0.5, 0)), material)


func _add_far_box(base: Vector3, size: Vector3, material: Material) -> void:
	_add_far_mesh(_weathered_box(size), Transform3D(Basis(), base + Vector3(0, size.y * 0.5, 0)), material)


func _add_far_mesh(mesh: Mesh, transform_value: Transform3D, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = transform_value
	# Scenery is far outside the arena; its shadows would cut across it.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


# --- Weather -------------------------------------------------------------------

# Returns a particle emitter for the region's weather. Attach it to the
# player: it emits in world space around them, so weather follows the
# camera without moving particles already in the air.
func make_weather() -> GPUParticles3D:
	var kind: String = profile["weather"]
	var particles := GPUParticles3D.new()
	particles.name = "Weather"
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 50, 80))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var draw := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var color := Color.WHITE
	var glow := false
	match kind:
		"snow":
			particles.amount = 3500
			particles.lifetime = 9.0
			process.emission_box_extents = Vector3(30, 1, 30)
			particles.position.y = 14.0
			process.gravity = Vector3(0.4, -1.6, 0.2)
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.6
			draw.size = Vector2(0.07, 0.07)
			color = Color(1, 1, 1, 0.9)
		"rain":
			particles.amount = 5000
			particles.lifetime = 1.1
			process.emission_box_extents = Vector3(28, 1, 28)
			particles.position.y = 16.0
			process.gravity = Vector3(0.6, -32.0, 0.0)
			draw.size = Vector2(0.025, 0.7)
			material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			color = Color(0.75, 0.82, 0.9, 0.45)
		"leaves":
			particles.amount = 420
			particles.lifetime = 8.0
			process.emission_box_extents = Vector3(28, 6, 28)
			particles.position.y = 8.0
			process.gravity = Vector3(1.4, -0.7, 0.5)
			process.angular_velocity_min = -180.0
			process.angular_velocity_max = 180.0
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 1.2
			draw.size = Vector2(0.14, 0.1)
			color = Color(profile["foliage_color"]).lightened(0.2)
		"dust":
			particles.amount = 700
			particles.lifetime = 7.0
			process.emission_box_extents = Vector3(28, 4, 28)
			particles.position.y = 3.0
			process.gravity = Vector3(1.8, 0.05, 0.6)
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.8
			draw.size = Vector2(0.05, 0.05)
			color = Color(1.0, 0.85, 0.55, 0.55)
		"embers", "ash":
			var embers = kind == "embers"
			particles.amount = 900 if embers else 1600
			particles.lifetime = 6.0
			process.emission_box_extents = Vector3(28, 4, 28)
			particles.position.y = 2.0 if embers else 12.0
			process.gravity = Vector3(0.5, 0.9, 0.2) if embers else Vector3(0.6, -0.8, 0.2)
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 1.0
			draw.size = Vector2(0.06, 0.06) if embers else Vector2(0.08, 0.08)
			color = Color(1.0, 0.45, 0.12) if embers else Color(0.55, 0.52, 0.5, 0.7)
			glow = embers
		_:
			# Floating motes: spores, fireflies, temple dust, starlight.
			particles.amount = 260
			particles.lifetime = 6.0
			process.emission_box_extents = Vector3(24, 3, 24)
			particles.position.y = 2.0
			process.gravity = Vector3(0, 0.05, 0)
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.9
			draw.size = Vector2(0.09, 0.09)
			glow = true
			match kind:
				"fireflies":
					color = Color(0.85, 1.0, 0.4)
				"spores":
					color = Color(0.4, 0.85, 1.0)
				"stars":
					color = Color(0.75, 0.6, 1.0)
				"petals":
					color = Color(1.0, 0.72, 0.85)
				_:
					color = Color(1.0, 0.85, 0.55, 0.8)
	process.color = color
	if glow:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 3.0
	if kind != "rain":
		material.albedo_texture = _soft_dot_texture()
	draw.material = material
	particles.process_material = process
	particles.draw_pass_1 = draw
	particles.preprocess = minf(particles.lifetime, 6.0)
	return particles


# --- Helpers -------------------------------------------------------------------

# Pushes each vertex in or out from the mesh centre by 3D noise. Coincident
# vertices move identically, so seams stay closed. Flat shading suits stone.
func _weathered(mesh: Mesh, amount: float, frequency: float, flat_shaded: bool = false) -> ArrayMesh:
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var center = mesh.get_aabb().get_center()
	var offset = Vector3(_rng.randf() * 100.0, _rng.randf() * 100.0, _rng.randf() * 100.0)
	for index in range(vertices.size()):
		var vertex = vertices[index]
		var direction = vertex - center
		direction = Vector3.UP if direction.length_squared() < 0.000001 else direction.normalized()
		vertices[index] = vertex + direction * _shape_noise.get_noise_3dv(vertex * frequency + offset) * amount
	var clean := []
	clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX] = vertices
	clean[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	clean[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean)
	var surface := SurfaceTool.new()
	surface.create_from(raw, 0)
	if flat_shaded:
		surface.deindex()
	surface.generate_normals()
	return surface.commit()


# A subdivided box chipped and eroded like old masonry.
func _weathered_box(size: Vector3) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = clampi(int(size.x * 1.5), 2, 24)
	box.subdivide_height = clampi(int(size.y * 1.5), 2, 24)
	box.subdivide_depth = clampi(int(size.z * 1.5), 2, 24)
	var smallest = minf(size.x, minf(size.y, size.z))
	return _weathered(box, clampf(smallest * 0.09, 0.04, 2.5), 1.4 / maxf(smallest, 0.6), true)


func _soft_dot_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


func _offset_mesh(mesh: Mesh, offset: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(mesh, 0, Transform3D(Basis(), offset))
	return surface.commit()


func _add_multimesh(label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _make_noise_texture(seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture


# Loads one map (diff, nor_gl or rough) of a Poly Haven scanned texture set.
# Import settings (mipmaps, VRAM compression, normal-map mode) are fixed in
# the committed .import files, since these are only used at runtime.
func _scanned(asset: String, kind: String) -> Texture2D:
	return load(SCANNED_ROOT % [asset, asset, kind])


# A world-space (triplanar) material from a scanned texture set, tinted to
# the region. uv_scale is repeats per metre.
func _make_scanned_material(asset: String, tint: Color, uv_scale: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = _scanned(asset, "diff")
	material.normal_enabled = true
	material.normal_texture = _scanned(asset, "nor_gl")
	material.roughness_texture = _scanned(asset, "rough")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * uv_scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


# Scanned textures carry their own colour, so a region colour is applied as a
# gentle tint: normalised to its brightest channel and blended toward white.
func _texture_tint(color: Color) -> Color:
	var brightest = maxf(color.r, maxf(color.g, color.b))
	if brightest <= 0.0:
		return Color.WHITE
	var normalised = Color(color.r / brightest, color.g / brightest, color.b / brightest)
	return Color.WHITE.lerp(normalised, 0.55)


func _make_textured_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = _stone_texture
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.18
	material.roughness = roughness
	return material
