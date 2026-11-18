extends Node3D

# Visual body of the spectral steed: a ghostly stag built from primitives,
# translucent and glowing. Purely visual; PlayerController owns all riding
# logic and parents this node under the player. Faces -Z like other bodies.

const GHOST_COLOR := Color(0.55, 0.85, 1.0, 0.45)
const GLOW_COLOR := Color(0.35, 0.7, 1.0)
const LEG_LENGTH := 0.95
const FADE_SECONDS := 0.25

var _material: StandardMaterial3D
var _legs: Array[Node3D] = []
var _body: Node3D
var _phase := 0.0
var _light: OmniLight3D


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = GHOST_COLOR
	_material.emission_enabled = true
	_material.emission = GLOW_COLOR
	_material.emission_energy_multiplier = 1.6
	_material.rim_enabled = true
	_material.rim = 1.0
	_material.rim_tint = 0.2
	_material.roughness = 0.4
	_body = Node3D.new()
	add_child(_body)
	# Torso, chest and haunch.
	_add_part(_capsule(0.3, 1.5), Vector3(0, 1.05, 0), Vector3(PI / 2.0, 0, 0))
	_add_part(_sphere(0.34), Vector3(0, 1.1, -0.5))
	_add_part(_sphere(0.3), Vector3(0, 1.08, 0.5))
	# Neck and head lean forward and up.
	_add_part(_capsule(0.13, 0.75), Vector3(0, 1.45, -0.78), Vector3(-0.55, 0, 0))
	_add_part(_capsule(0.12, 0.55), Vector3(0, 1.78, -1.02), Vector3(PI / 2.0 - 0.35, 0, 0))
	# Ears.
	for side in [-1.0, 1.0]:
		_add_part(_capsule(0.035, 0.2), Vector3(0.1 * side, 1.92, -0.92), Vector3(0.3, 0, -0.9 * side))
	# Antlers: a main beam per side with two tines.
	for side in [-1.0, 1.0]:
		var base := Vector3(0.07 * side, 1.92, -0.98)
		_add_part(_cylinder(0.025, 0.55), base + Vector3(0.13 * side, 0.22, 0.05), Vector3(0.25, 0, -0.55 * side))
		_add_part(_cylinder(0.02, 0.3), base + Vector3(0.2 * side, 0.42, -0.08), Vector3(-0.5, 0, -0.2 * side))
		_add_part(_cylinder(0.02, 0.3), base + Vector3(0.32 * side, 0.5, 0.12), Vector3(0.35, 0, -0.7 * side))
	# Tail wisp.
	_add_part(_sphere(0.1), Vector3(0, 1.2, 0.82))
	# Legs swing from the hips and shoulders.
	for spot in [Vector3(-0.17, 0.98, -0.52), Vector3(0.17, 0.98, -0.52),
			Vector3(-0.17, 0.98, 0.52), Vector3(0.17, 0.98, 0.52)]:
		var hip := Node3D.new()
		hip.position = spot
		_body.add_child(hip)
		var leg := MeshInstance3D.new()
		leg.mesh = _cylinder(0.05, LEG_LENGTH)
		leg.position.y = -LEG_LENGTH * 0.5
		leg.material_override = _material
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hip.add_child(leg)
		_legs.append(hip)
	_light = OmniLight3D.new()
	_light.light_color = GLOW_COLOR
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)
	var wisps := CPUParticles3D.new()
	wisps.amount = 24
	wisps.lifetime = 1.2
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wisps.emission_box_extents = Vector3(0.3, 0.3, 0.8)
	wisps.position = Vector3(0, 1.0, 0)
	wisps.direction = Vector3.UP
	wisps.spread = 25.0
	wisps.initial_velocity_min = 0.3
	wisps.initial_velocity_max = 0.8
	wisps.gravity = Vector3.ZERO
	wisps.scale_amount_min = 0.5
	wisps.scale_amount_max = 1.0
	var wisp_mesh := SphereMesh.new()
	wisp_mesh.radius = 0.04
	wisp_mesh.height = 0.08
	wisp_mesh.material = _material
	wisps.mesh = wisp_mesh
	add_child(wisps)


func appear() -> void:
	scale = Vector3.ONE * 0.3
	_material.albedo_color.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE, FADE_SECONDS)
	tween.tween_property(_material, "albedo_color:a", GHOST_COLOR.a, FADE_SECONDS)


# Fades out where it stands, then frees itself.
func vanish() -> void:
	if not is_inside_tree():
		queue_free()
		return
	var keep := global_transform
	top_level = true
	global_transform = keep
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_SECONDS)
	tween.tween_property(_light, "light_energy", 0.0, FADE_SECONDS)
	tween.chain().tween_callback(queue_free)


# Gallop: legs swing in diagonal pairs, faster and wider with speed.
func set_gait(speed: float, delta: float) -> void:
	var pace := clampf(speed / 15.0, 0.0, 1.0)
	_phase = fmod(_phase + delta * (3.0 + speed * 0.8), TAU)
	var swing := 0.75 * pace
	for index in _legs.size():
		var offset := 0.0 if index == 0 or index == 3 else PI
		_legs[index].rotation.x = sin(_phase + offset) * swing
	_body.position.y = absf(sin(_phase)) * 0.08 * pace


func _add_part(mesh: Mesh, at: Vector3, rotation_euler: Vector3 = Vector3.ZERO) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rotation_euler
	part.material_override = _material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(part)


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh
