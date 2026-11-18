extends "res://scripts/world/RegionBuilder.gd"
class_name SkyIslandBuilder

# The Master's sanctuary: a walled stone courtyard on a rock island floating
# above the clouds at the Tower's threshold, sheltered by a shimmering
# hexagonal barrier. Reuses the region builder's scanned materials, foliage
# and weather; replaces its terrain with the island.

const DOME_SHADER = preload("res://shaders/barrier_dome.gdshader")
const CLOUD_SHADER = preload("res://shaders/cloud_sea.gdshader")
const RUNE_SHADER = preload("res://shaders/rune_circle.gdshader")

const ISLAND_RADIUS := 50.0
# Walkable radius: the broken rim beyond it is scenery behind invisible walls.
const WALK_RADIUS := 43.0
const WALL_RADIUS := 41.0

# Sanctuary works built so far ({id: level}); only built ones are shown.
var improvements: Dictionary = {}

const SKY_PROFILE := {
	"sky_top": Color("#3f7fd0"), "sky_horizon": Color("#d9c8f0"),
	"ground_horizon": Color("#c8d2f0"), "ground_bottom": Color("#8fa6d8"),
	"sun_color": Color("#fff2dc"), "sun_energy": 1.7, "sun_pitch": -48.0, "sun_yaw": 35.0,
	"ambient": Color("#a8b8e0"), "ambient_energy": 0.75,
	"fog_color": Color("#dce6fa"), "fog_density": 0.0018, "fog_emission": Color("#000000"),
	"ground_low": Color("#5a7a3a"), "ground_high": Color("#6e8a44"), "ground_rock": Color("#5a5a5e"),
	"grass_color": Color("#3f6a2a"), "grass_tip": Color("#9cc45a"), "grass_density": 1.0,
	"tree_kind": "broadleaf", "tree_count": 0, "foliage_color": Color("#e08ab0"),
	"rock_color": Color("#6a6670"), "ruin_color": Color("#e8e4dc"),
	"weather": "petals", "water_level": null, "hill_height": 0.0,
	"landmark": "none", "stars": false, "lava": false
}

var _white_stone: StandardMaterial3D
var _slate_roof: StandardMaterial3D


func build(_region_index: int, seed_value: int, reserved_points: Array) -> void:
	profile = SKY_PROFILE.duplicate(true)
	_reserved = PackedVector2Array()
	for point in reserved_points:
		_reserved.append(Vector2(point.x, point.z))
	_rng.seed = seed_value
	_noise.seed = seed_value
	_detail_noise.seed = seed_value + 17
	_detail_noise.frequency = 0.08
	_shape_noise.seed = seed_value + 31
	_shape_noise.frequency = 1.0
	_shape_noise.fractal_octaves = 3
	_noise_texture = _make_noise_texture(seed_value)
	_stone_texture = _make_noise_texture(seed_value + 5)
	_ground_set = ["forest_ground_04", "forest_ground_04", Color.WHITE, Color.WHITE]
	_white_stone = _make_scanned_material("castle_wall_slates", Color("#f2efe8"), 0.35)
	_slate_roof = StandardMaterial3D.new()
	_slate_roof.albedo_color = Color("#3d4a63")
	_slate_roof.roughness = 0.7
	_stone_material = _white_stone
	_bark_material = _make_scanned_material("bark_brown_02", Color("#c8a882"), 0.6)
	# The island starts crude and broken; each sanctuary work transforms it.
	_build_island()
	_build_rubble_and_grass()
	_build_floating_debris()
	if _built("courtyard"):
		_build_courtyard()
	if _built("walls"):
		_build_wall_ring()
	if _built("rune_circle"):
		_build_rune_plazas()
	if _built("arena"):
		_build_arena()
	if _built("gardens"):
		_build_gardens()
	if _built("barrier"):
		_build_barrier_dome()
	_build_tower_spire()
	_build_cloud_sea()


func _built(improvement_id: String) -> bool:
	return int(improvements.get(improvement_id, 0)) > 0


# The courtyard is level everywhere on the island.
func height_at(_x: float, _z: float) -> float:
	return 0.0


func white_stone() -> StandardMaterial3D:
	return _white_stone


func slate_roof() -> StandardMaterial3D:
	return _slate_roof


func _build_island() -> void:
	# Ragged top: a fan whose rim radius wanders with noise, textured with
	# scanned rock and earth through the terrain shader.
	var rim := FastNoiseLite.new()
	rim.seed = _rng.randi()
	rim.frequency = 0.9
	# An even 1 m grid trimmed to a wandering rim: long thin fan triangles
	# would distort the normal-mapped lighting.
	var half := int(ISLAND_RADIUS + 7.0)
	var size := half * 2 + 1
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in range(size):
		for xi in range(size):
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(1, 0, 0))
			surface.set_uv(Vector2(xi, zi) * 0.1)
			surface.add_vertex(Vector3(xi - half, 0.0, zi - half))
	for zi in range(size - 1):
		for xi in range(size - 1):
			var cx = xi - half + 0.5
			var cz = zi - half + 0.5
			var angle = atan2(cz, cx)
			var rim_radius = ISLAND_RADIUS + rim.get_noise_1d((angle + PI) / TAU * 8.0) * 6.0
			if Vector2(cx, cz).length() > rim_radius:
				continue
			var a = zi * size + xi
			surface.add_index(a)
			surface.add_index(a + 1)
			surface.add_index(a + size)
			surface.add_index(a + 1)
			surface.add_index(a + size + 1)
			surface.add_index(a + size)
	surface.generate_tangents()
	var top := MeshInstance3D.new()
	top.mesh = surface.commit()
	var ground := ShaderMaterial.new()
	ground.shader = GROUND_SHADER
	ground.set_shader_parameter("primary_albedo", _scanned("rocky_terrain_02", "diff"))
	ground.set_shader_parameter("primary_normal", _scanned("rocky_terrain_02", "nor_gl"))
	ground.set_shader_parameter("primary_rough", _scanned("rocky_terrain_02", "rough"))
	ground.set_shader_parameter("secondary_albedo", _scanned("forest_ground_04", "diff"))
	ground.set_shader_parameter("secondary_normal", _scanned("forest_ground_04", "nor_gl"))
	ground.set_shader_parameter("rock_albedo", _scanned("rock_face", "diff"))
	ground.set_shader_parameter("rock_normal", _scanned("rock_face", "nor_gl"))
	ground.set_shader_parameter("tint", Color("#d8ccb8"))
	ground.set_shader_parameter("rock_tint", Color("#b0a898"))
	ground.set_shader_parameter("hill_height", 1.0)
	ground.set_shader_parameter("noise_tex", _noise_texture)
	top.material_override = ground
	add_child(top)
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position.y = -1.0
	var shape := CylinderShape3D.new()
	shape.radius = WALK_RADIUS + 2.0
	shape.height = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	# Jagged rock hanging beneath the island.
	var rock_material = _make_scanned_material("rock_face", Color("#9a948e"), 0.12)
	var underside := CylinderMesh.new()
	underside.top_radius = ISLAND_RADIUS - 2.0
	underside.bottom_radius = 4.0
	underside.height = 58.0
	underside.radial_segments = 40
	underside.rings = 14
	# No lid (the paved top covers it), and the roughened rock is clamped so
	# no part of it can poke up through the ground.
	underside.cap_top = false
	var rock := MeshInstance3D.new()
	rock.mesh = _clamp_mesh_top(_weathered(underside, 9.0, 0.05, true), 28.6)
	rock.position.y = -29.5
	rock.material_override = rock_material
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock)
	# Invisible edge so nobody walks off the broken rim.
	var edge := StaticBody3D.new()
	add_child(edge)
	for index in range(40):
		var angle = TAU * index / 40.0
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(7.5, 14.0, 1.0)
		wall.shape = box
		wall.transform = Transform3D(Basis(Vector3.UP, -angle + PI * 0.5), Vector3(cos(angle) * WALK_RADIUS, 7.0, sin(angle) * WALK_RADIUS))
		edge.add_child(wall)


# Pushes every vertex above max_y down to max_y (keeps flat normals).
func _clamp_mesh_top(mesh: ArrayMesh, max_y: float) -> ArrayMesh:
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in range(vertices.size()):
		if vertices[index].y > max_y:
			vertices[index].y = max_y
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


# Broken stone, boulders and sparse wild grass across the unbuilt island.
func _build_rubble_and_grass() -> void:
	var fragments: Array[Transform3D] = []
	var boulders: Array[Transform3D] = []
	for index in range(140):
		var angle = _rng.randf() * TAU
		var radius = sqrt(_rng.randf()) * (ISLAND_RADIUS - 3.0)
		var position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _near_reserved(position, 6.5) or (_built("courtyard") and radius < 22.0):
			continue
		var size = _rng.randf_range(0.3, 1.1)
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6)).scaled(Vector3(size * 1.4, size * 0.6, size))
		if index % 3 == 0:
			boulders.append(Transform3D(basis.scaled(Vector3.ONE * 1.6), position))
		else:
			fragments.append(Transform3D(basis, position + Vector3(0, size * 0.15, 0)))
	var box := BoxMesh.new()
	box.subdivide_width = 2
	box.subdivide_height = 2
	box.subdivide_depth = 2
	_add_multimesh("Rubble", _weathered(box, 0.12, 2.0, true), _make_scanned_material("castle_wall_slates", Color("#e0dbd0"), 0.5), fragments)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 14
	sphere.rings = 9
	_add_multimesh("Boulders", _weathered(sphere, 0.2, 2.2, true), _make_scanned_material("rock_face", Color("#a49e96"), 0.6), boulders)
	var blades: Array[Transform3D] = []
	for index in range(9000):
		var angle = _rng.randf() * TAU
		var radius = sqrt(_rng.randf()) * (ISLAND_RADIUS - 2.0)
		var x = cos(angle) * radius
		var z = sin(angle) * radius
		if _detail_noise.get_noise_2d(x * 0.4, z * 0.4) < 0.05 or (_built("courtyard") and radius < 22.0):
			continue
		var scale = _rng.randf_range(0.7, 1.2)
		blades.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale, scale)), Vector3(x, 0.0, z)))
	var grass := ShaderMaterial.new()
	grass.shader = GRASS_SHADER
	grass.set_shader_parameter("base_color", Color("#4a6a2e"))
	grass.set_shader_parameter("tip_color", Color("#b8c46a"))
	grass.set_shader_parameter("wind_strength", 0.35)
	_add_multimesh("Wild Grass", _make_blade_mesh(), grass, blades)
	get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Broken-off chunks of the island drifting nearby.
func _build_floating_debris() -> void:
	var rock_material = _make_scanned_material("rock_face", Color("#9a948e"), 0.08)
	for index in range(9):
		var angle = TAU * index / 9.0 + _rng.randf_range(-0.2, 0.2)
		var distance = ISLAND_RADIUS + _rng.randf_range(10.0, 34.0)
		var chunk := CylinderMesh.new()
		chunk.top_radius = _rng.randf_range(2.0, 6.5)
		chunk.bottom_radius = 0.6
		chunk.height = chunk.top_radius * _rng.randf_range(2.0, 3.0)
		chunk.radial_segments = 14
		chunk.rings = 5
		var piece := MeshInstance3D.new()
		piece.mesh = _weathered(chunk, chunk.top_radius * 0.35, 0.3, true)
		piece.position = Vector3(cos(angle) * distance, _rng.randf_range(-14.0, 6.0), sin(angle) * distance)
		piece.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
		piece.material_override = rock_material
		add_child(piece)


# Paved heart of the camp and a path to the Tower gate.
func _build_courtyard() -> void:
	var paving = _make_scanned_material("castle_wall_slates", Color("#e6e1d6"), 0.22)
	var plaza := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 21.0
	disk.bottom_radius = 21.3
	disk.height = 0.12
	disk.radial_segments = 64
	plaza.mesh = disk
	plaza.material_override = paving
	plaza.position.y = 0.06
	add_child(plaza)
	var path := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(5.0, 0.12, 16.0)
	path.mesh = strip
	path.material_override = paving
	path.position = Vector3(0, 0.06, -27.0)
	add_child(path)


func _build_wall_ring() -> void:
	var segments := 32
	for index in range(segments):
		var angle = TAU * index / segments
		var center = Vector3(cos(angle) * WALL_RADIUS, 0, sin(angle) * WALL_RADIUS)
		var basis := Basis(Vector3.UP, -angle + PI * 0.5)
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(TAU * WALL_RADIUS / segments + 0.2, 5.0, 1.6)
		wall.mesh = box
		wall.material_override = _white_stone
		wall.transform = Transform3D(basis, center + Vector3(0, 2.5, 0))
		add_child(wall)
		# Crenellations along the walkway.
		for merlon in range(2):
			var tooth := MeshInstance3D.new()
			var tooth_box := BoxMesh.new()
			tooth_box.size = Vector3(1.6, 1.0, 1.7)
			tooth.mesh = tooth_box
			tooth.material_override = _white_stone
			tooth.transform = Transform3D(basis, center + Vector3(0, 5.5, 0) + basis.x * (merlon * 3.6 - 1.8))
			add_child(tooth)
		if index % 4 == 0 and absf(sin(angle) + 1.0) > 0.15:
			_add_wall_tower(Vector3(cos(angle) * WALL_RADIUS, 0, sin(angle) * WALL_RADIUS))


func _add_wall_tower(base: Vector3) -> void:
	var tower := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 2.4
	column.bottom_radius = 2.8
	column.height = 10.0
	column.radial_segments = 16
	tower.mesh = column
	tower.material_override = _white_stone
	tower.position = base + Vector3(0, 5.0, 0)
	add_child(tower)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.3
	cone.height = 4.5
	cone.radial_segments = 16
	roof.mesh = cone
	roof.material_override = _slate_roof
	roof.position = base + Vector3(0, 12.25, 0)
	add_child(roof)


# Circular plazas inlaid with slowly turning, softly glowing rune rings.
func _build_rune_plazas() -> void:
	for spec in [[Vector3(0, 0, -16), 6.5], [Vector3(-12, 0, -26), 4.0], [Vector3(12, 0, -26), 4.0]]:
		var center: Vector3 = spec[0]
		var radius: float = spec[1]
		var dais := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = radius
		disk.bottom_radius = radius + 0.3
		disk.height = 0.4
		disk.radial_segments = 48
		dais.mesh = disk
		dais.material_override = _white_stone
		dais.position = center + Vector3(0, 0.2, 0)
		add_child(dais)
		var runes := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(radius * 2.0, radius * 2.0)
		runes.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = RUNE_SHADER
		runes.material_override = material
		runes.position = center + Vector3(0, 0.42, 0)
		runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(runes)
		var glow := OmniLight3D.new()
		glow.position = center + Vector3(0, 1.5, 0)
		glow.light_color = Color("#8fd8ff")
		glow.light_energy = 1.2
		glow.omni_range = radius * 1.6
		add_child(glow)


# Sand training arena with a low stone border.
func _build_arena() -> void:
	var center := Vector3(0, 0, 14)
	var floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(20, 0.2, 14)
	floor.mesh = box
	floor.material_override = _make_scanned_material("coast_sand_01", Color("#f0dcb8"), 0.3)
	floor.position = center + Vector3(0, 0.1, 0)
	add_child(floor)
	for side in [[Vector3(0, 0, -7.2), Vector3(20.8, 0.8, 0.6)], [Vector3(0, 0, 7.2), Vector3(20.8, 0.8, 0.6)], [Vector3(-10.2, 0, 0), Vector3(0.6, 0.8, 14.4)], [Vector3(10.2, 0, 0), Vector3(0.6, 0.8, 14.4)]]:
		var border := MeshInstance3D.new()
		var border_box := BoxMesh.new()
		border_box.size = side[1]
		border.mesh = border_box
		border.material_override = _white_stone
		border.position = center + side[0] + Vector3(0, 0.4, 0)
		add_child(border)


# Lawns with blossom trees, grass and flowers between the paths.
func _build_gardens() -> void:
	var lawn_material = _make_scanned_material("forest_ground_04", Color("#b8d090"), 0.25)
	var leaf_material = _make_leaf_material()
	var canopy = _make_broadleaf_canopy()
	var trunk = _offset_mesh(_cylinder(0.25, 0.5, 4.0, Vector3.ZERO), Vector3(0, 2.0, 0))
	var tree_transforms: Array[Transform3D] = []
	var blade_mesh = _make_blade_mesh()
	var grass_material := ShaderMaterial.new()
	grass_material.shader = GRASS_SHADER
	grass_material.set_shader_parameter("base_color", profile["grass_color"])
	grass_material.set_shader_parameter("tip_color", profile["grass_tip"])
	grass_material.set_shader_parameter("wind_strength", 0.2)
	for lawn in [Rect2(-37, -12, 12, 20), Rect2(25, -12, 12, 20), Rect2(-30, 24, 16, 8), Rect2(14, 24, 16, 8)]:
		var patch := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(lawn.size.x, 0.12, lawn.size.y)
		patch.mesh = box
		patch.material_override = lawn_material
		patch.position = Vector3(lawn.position.x + lawn.size.x * 0.5, 0.06, lawn.position.y + lawn.size.y * 0.5)
		add_child(patch)
		var transforms: Array[Transform3D] = []
		for index in range(int(lawn.size.x * lawn.size.y * 5.0)):
			var x = lawn.position.x + _rng.randf() * lawn.size.x
			var z = lawn.position.y + _rng.randf() * lawn.size.y
			var scale = _rng.randf_range(0.7, 1.2)
			transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale, scale)), Vector3(x, 0.1, z)))
		_add_multimesh("Garden Grass", blade_mesh, grass_material, transforms)
		get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for tree in range(int(lawn.size.x * lawn.size.y / 120.0) + 1):
			var position = Vector3(lawn.position.x + _rng.randf_range(2.0, lawn.size.x - 2.0), 0.0, lawn.position.y + _rng.randf_range(2.0, lawn.size.y - 2.0))
			if _near_reserved(position, 6.0):
				continue
			tree_transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.1)), position))
			_add_cover_cylinder(position, 0.45, 5.0)
	_add_multimesh("Garden Trunks", trunk, _bark_material, tree_transforms)
	_add_multimesh("Garden Canopies", canopy, leaf_material, tree_transforms)


# A sea of clouds far below the island.
func _build_cloud_sea() -> void:
	for layer in range(2):
		var clouds := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(1400, 1400)
		clouds.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		material.set_shader_parameter("noise_tex", _noise_texture)
		material.set_shader_parameter("offset", Vector2(layer * 0.37, layer * 0.21))
		material.set_shader_parameter("density", 0.75 - layer * 0.25)
		clouds.material_override = material
		clouds.position.y = -70.0 - layer * 25.0
		clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clouds)


# The sanctuary's protective barrier: a faint hexagonal dome.
func _build_barrier_dome() -> void:
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 110.0
	sphere.height = 220.0
	sphere.radial_segments = 64
	sphere.rings = 32
	dome.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = DOME_SHADER
	dome.material_override = material
	dome.position.y = -30.0
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
