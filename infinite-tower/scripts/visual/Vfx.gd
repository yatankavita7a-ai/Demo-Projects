extends RefCounted

# One-shot combat particles: hit sparks, ember bursts, dust and debris on
# heavy impacts (matched to the region's ground: dirt, sand, ash, snow,
# water, stone), water splashes, shockwave dust rings and golden magic
# waves; plus a few looping emitters (arena edge flames, sandstorm streaks,
# fine ash). Every burst is a GPUParticles3D that frees itself when done;
# materials are built once and shared. Purely visual.
#
# TowerGame sets `region_material` per floor and `intensity` from the
# graphics settings (fewer particles on "off").

const MAX_ACTIVE := 40
const GROUP := "vfx_burst"
const MATERIAL_COLORS := {
	"dirt": Color(0.33, 0.27, 0.2), "dust": Color(0.8, 0.66, 0.47), "ash": Color(0.46, 0.43, 0.42),
	"snow": Color(0.93, 0.96, 1.0), "water": Color(0.75, 0.83, 0.9), "stone": Color(0.45, 0.45, 0.5),
}

static var region_material := "dirt"
static var intensity := 1.0
static var _cache := {}


# --- Public bursts ------------------------------------------------------------

# A blade landing on flesh or armour: a spray of sparks; heavy and critical
# hits throw a bigger radial burst, and fire regions add embers.
static func hit(parent: Node, position: Vector3, heavy: bool, critical: bool = false) -> void:
	var gold := critical
	_burst(parent, "sparks_gold" if gold else "sparks", position, 26 if heavy else 14, 1.3 if heavy else 1.0)
	if heavy or critical:
		_burst(parent, "flash", position, 1, 1.3 if critical else 1.0)
	if region_material == "ash" and heavy:
		_burst(parent, "embers", position, 40, 1.2)


# Blade glancing off scales or a guard: pale sparks, no blood or dust.
static func deflect(parent: Node, position: Vector3) -> void:
	_burst(parent, "sparks_pale", position, 18, 1.0)


# The player being struck: a short dark spray and a few sparks.
static func player_struck(parent: Node, position: Vector3) -> void:
	_burst(parent, "sparks", position, 10, 0.8)
	_burst(parent, "blood", position, 14, 1.0)


# A heavy blow into the ground (boss slam, landing): material-matched dust,
# debris chunks and, depending on the ground, a splash, snow or embers.
static func impact(parent: Node, position: Vector3, strength: float = 1.0) -> void:
	var kind := region_material
	var count_scale := clampf(strength, 0.5, 3.0)
	if kind == "water":
		splash(parent, position, strength)
		return
	_burst(parent, "dust_" + kind, position, int(10 * count_scale), strength)
	_burst(parent, "debris_" + kind, position, int(18 * count_scale), strength)
	if kind == "ash":
		_burst(parent, "embers", position + Vector3.UP * 0.2, int(40 * count_scale), strength)
	elif kind == "snow":
		_burst(parent, "powder", position, int(30 * count_scale), strength)


# Landing from a jump or roll: a small dust (or water) puff at the feet.
static func landing(parent: Node, position: Vector3, in_water: bool) -> void:
	if in_water:
		splash(parent, position, 0.5)
	else:
		_burst(parent, "dust_" + ("dust" if region_material == "water" else region_material), position, 5, 0.45)


static func splash(parent: Node, position: Vector3, strength: float = 1.0) -> void:
	_burst(parent, "droplets", position, int(30 * clampf(strength, 0.4, 3.0)), strength)
	_burst(parent, "dust_water", position, int(6 * clampf(strength, 0.4, 3.0)), strength * 0.8)


# Dust kicked up by an expanding shockwave ring: emitted on a ring and
# carried outward at the wave's speed until it reaches its edge.
static func shock_wave(parent: Node, origin: Vector3, start_radius: float, max_radius: float, speed: float) -> void:
	var particles := _burst(parent, "wave_" + ("dust" if region_material == "water" else region_material),
		origin + Vector3.UP * 0.15, int(clampf(max_radius * 9.0, 40, 220)), 1.0)
	if particles == null:
		return
	var process: ParticleProcessMaterial = particles.process_material.duplicate()
	process.emission_ring_radius = maxf(0.3, start_radius)
	process.emission_ring_inner_radius = maxf(0.0, start_radius - 0.3)
	process.radial_velocity_min = speed * 0.9
	process.radial_velocity_max = speed * 1.05
	particles.process_material = process
	particles.lifetime = clampf((max_radius - start_radius) / maxf(speed, 0.1), 0.3, 4.0)
	particles.visibility_aabb = AABB(Vector3(-max_radius - 2.0, -2.0, -max_radius - 2.0),
		Vector3(max_radius * 2.0 + 4.0, 6.0, max_radius * 2.0 + 4.0))


# A golden ring of light rushing outward (spells, rites).
static func magic_wave(parent: Node, position: Vector3, radius: float = 6.0) -> void:
	var particles := _burst(parent, "magic", position + Vector3.UP * 0.3, 90, 1.0)
	if particles == null:
		return
	var process: ParticleProcessMaterial = particles.process_material.duplicate()
	process.radial_velocity_min = radius / particles.lifetime * 0.9
	process.radial_velocity_max = radius / particles.lifetime * 1.1
	particles.process_material = process
	particles.visibility_aabb = AABB(Vector3(-radius - 2.0, -2.0, -radius - 2.0),
		Vector3(radius * 2.0 + 4.0, 6.0, radius * 2.0 + 4.0))


# --- Looping emitters ---------------------------------------------------------

# A low patch of flames for an arena's edge (fire regions).
static func make_edge_flame() -> GPUParticles3D:
	var particles := _make_emitter("flame", int(22 * intensity))
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.lifetime = 1.1
	particles.preprocess = 1.0
	return particles


# Extra airborne layer that follows the player like the weather: sandstorm
# streaks or fine drifting ash. Returns null for none.
static func make_ambient(kind: String) -> GPUParticles3D:
	if kind != "sand" and kind != "fine_ash":
		return null
	var particles := _make_emitter(kind, int((900 if kind == "sand" else 600) * intensity))
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.lifetime = 3.0 if kind == "sand" else 7.0
	particles.preprocess = particles.lifetime
	particles.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	particles.position.y = 2.0
	return particles


# --- Internals ----------------------------------------------------------------

static func _burst(parent: Node, kind: String, position: Vector3, amount: int, size_scale: float) -> GPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var tree := parent.get_tree()
	if tree.get_node_count_in_group(GROUP) >= MAX_ACTIVE:
		return null
	amount = maxi(1, int(amount * intensity))
	var particles := _make_emitter(kind, amount)
	particles.add_to_group(GROUP)
	# Freeze with the game while paused (the tower root processes always).
	particles.process_mode = Node.PROCESS_MODE_PAUSABLE
	particles.one_shot = true
	particles.explosiveness = 0.95 if not kind.begins_with("wave") else 1.0
	if size_scale != 1.0:
		particles.scale = Vector3.ONE * size_scale
	parent.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


static func _make_emitter(kind: String, amount: int) -> GPUParticles3D:
	var spec: Dictionary = _spec(kind)
	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = spec["lifetime"]
	particles.process_material = spec["process"]
	particles.draw_pass_1 = spec["mesh"]
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.transform_align = spec.get("align", GPUParticles3D.TRANSFORM_ALIGN_DISABLED)
	particles.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	particles.fixed_fps = 0
	return particles


static func _spec(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var spec := {}
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.direction = Vector3.UP
	var parts := kind.split("_", true, 1)
	var family := parts[0]
	var material_name := parts[1] if parts.size() > 1 else region_material
	var ground: Color = MATERIAL_COLORS.get(material_name, MATERIAL_COLORS["dirt"])
	match family:
		"sparks":
			var hot := Color(4.0, 2.2, 0.8)
			if material_name == "gold":
				hot = Color(5.0, 3.6, 1.2)
			elif material_name == "pale":
				hot = Color(2.6, 2.9, 3.4)
			process.spread = 70.0
			process.initial_velocity_min = 5.0
			process.initial_velocity_max = 11.0
			process.gravity = Vector3(0, -14, 0)
			process.damping_min = 2.0
			process.damping_max = 4.0
			process.color_ramp = _ramp([hot, Color(hot.r * 0.6, hot.g * 0.3, hot.b * 0.1, 0.0)])
			process.scale_min = 0.6
			process.scale_max = 1.2
			spec["lifetime"] = 0.38
			spec["mesh"] = _quad(Vector2(0.025, 0.32), _unshaded(false))
			spec["align"] = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		"flash":
			process.emission_sphere_radius = 0.01
			process.spread = 0.0
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.0
			process.gravity = Vector3.ZERO
			process.scale_curve = _curve([0.4, 1.0])
			process.color_ramp = _ramp([Color(1.6, 1.2, 0.8, 0.55), Color(1.0, 0.6, 0.3, 0.0)])
			spec["lifetime"] = 0.1
			spec["mesh"] = _quad(Vector2(0.55, 0.55), _unshaded(true))
		"embers":
			process.spread = 180.0
			process.initial_velocity_min = 2.0
			process.initial_velocity_max = 7.5
			process.gravity = Vector3(0, 1.2, 0)
			process.damping_min = 1.5
			process.damping_max = 3.0
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 1.4
			process.scale_min = 0.5
			process.scale_max = 1.3
			process.color_ramp = _ramp([Color(5.0, 1.8, 0.4), Color(2.5, 0.6, 0.1), Color(0.6, 0.1, 0.0, 0.0)])
			spec["lifetime"] = 1.4
			spec["mesh"] = _quad(Vector2(0.06, 0.06), _unshaded(true))
		"blood":
			process.spread = 55.0
			process.initial_velocity_min = 2.0
			process.initial_velocity_max = 4.5
			process.gravity = Vector3(0, -12, 0)
			process.scale_min = 0.5
			process.scale_max = 1.0
			process.color_ramp = _ramp([Color(0.35, 0.02, 0.02, 0.95), Color(0.2, 0.01, 0.01, 0.0)])
			spec["lifetime"] = 0.5
			spec["mesh"] = _quad(Vector2(0.07, 0.07), _lit(true))
		"dust", "powder":
			var thin := family == "powder"
			process.emission_sphere_radius = 0.5
			process.spread = 85.0
			process.initial_velocity_min = 1.0 if not thin else 2.0
			process.initial_velocity_max = 3.2 if not thin else 6.0
			process.gravity = Vector3(0, -0.4 if not thin else -3.0, 0)
			process.damping_min = 1.5
			process.damping_max = 2.5
			process.angle_min = 0.0
			process.angle_max = 360.0
			process.scale_min = 0.7
			process.scale_max = 1.3
			process.scale_curve = _curve([0.35, 1.0, 1.4])
			var tone := ground if family == "dust" else MATERIAL_COLORS["snow"]
			process.color_ramp = _ramp([Color(tone, 0.0), Color(tone, 0.5), Color(tone, 0.0)])
			spec["lifetime"] = 1.6 if not thin else 1.0
			spec["mesh"] = _quad(Vector2(1.4, 1.4) if not thin else Vector2(0.12, 0.12), _lit(true))
		"debris":
			process.emission_sphere_radius = 0.4
			process.spread = 55.0
			process.initial_velocity_min = 3.5
			process.initial_velocity_max = 8.0
			process.gravity = Vector3(0, -16, 0)
			process.angular_velocity_min = -400.0
			process.angular_velocity_max = 400.0
			process.scale_min = 0.5
			process.scale_max = 1.6
			process.scale_curve = _curve([1.0, 1.0, 0.0])
			process.particle_flag_rotate_y = true
			spec["lifetime"] = 0.9
			var chunk := BoxMesh.new()
			chunk.size = Vector3(0.09, 0.06, 0.08)
			var stone := StandardMaterial3D.new()
			stone.albedo_color = ground.darkened(0.25)
			stone.roughness = 0.95
			stone.vertex_color_use_as_albedo = false
			chunk.material = stone
			spec["mesh"] = chunk
		"droplets":
			process.emission_sphere_radius = 0.35
			process.spread = 30.0
			process.initial_velocity_min = 3.0
			process.initial_velocity_max = 7.0
			process.gravity = Vector3(0, -15, 0)
			process.scale_min = 0.6
			process.scale_max = 1.2
			process.color_ramp = _ramp([Color(0.85, 0.92, 1.0, 0.85), Color(0.7, 0.8, 0.9, 0.0)])
			spec["lifetime"] = 0.8
			spec["mesh"] = _quad(Vector2(0.04, 0.22), _lit(false))
			spec["align"] = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		"wave":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_height = 0.1
			process.emission_ring_radius = 1.0
			process.emission_ring_inner_radius = 0.8
			# Radial: particles fly away from the ring's centre.
			process.direction = Vector3.ZERO
			process.radial_velocity_min = 8.0
			process.radial_velocity_max = 9.0
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.0
			process.gravity = Vector3(0, 0.6, 0)
			process.angle_min = 0.0
			process.angle_max = 360.0
			process.scale_min = 0.6
			process.scale_max = 1.2
			process.scale_curve = _curve([0.5, 1.0, 1.3])
			var tone := ground if material_name != "ash" else Color(0.25, 0.22, 0.22)
			process.color_ramp = _ramp([Color(tone, 0.55), Color(tone, 0.35), Color(tone, 0.0)])
			spec["lifetime"] = 1.0
			spec["mesh"] = _quad(Vector2(1.2, 0.8), _lit(true))
		"magic":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_height = 0.05
			process.emission_ring_radius = 0.6
			process.emission_ring_inner_radius = 0.5
			process.direction = Vector3.ZERO
			process.radial_velocity_min = 8.0
			process.radial_velocity_max = 9.0
			process.gravity = Vector3(0, 0.8, 0)
			process.scale_min = 0.6
			process.scale_max = 1.3
			process.color_ramp = _ramp([Color(4.0, 3.0, 1.0, 1.0), Color(2.0, 1.2, 0.3, 0.6), Color(1.0, 0.5, 0.1, 0.0)])
			spec["lifetime"] = 0.7
			spec["mesh"] = _quad(Vector2(0.14, 0.14), _unshaded(true))
		"flame":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			process.emission_box_extents = Vector3(1.6, 0.1, 0.6)
			process.spread = 12.0
			process.initial_velocity_min = 0.8
			process.initial_velocity_max = 2.0
			process.gravity = Vector3(0, 1.5, 0)
			process.angle_min = -30.0
			process.angle_max = 30.0
			process.scale_min = 0.6
			process.scale_max = 1.2
			process.scale_curve = _curve([0.6, 1.0, 0.2])
			process.color_ramp = _ramp([Color(3.5, 1.6, 0.4, 0.0), Color(3.0, 1.0, 0.2, 0.8), Color(0.6, 0.12, 0.02, 0.0)])
			spec["lifetime"] = 1.1
			spec["mesh"] = _quad(Vector2(0.7, 1.0), _unshaded(true))
		"sand":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			process.emission_box_extents = Vector3(26, 3, 26)
			process.direction = Vector3(1, 0, 0.3)
			process.spread = 6.0
			process.initial_velocity_min = 9.0
			process.initial_velocity_max = 14.0
			process.gravity = Vector3.ZERO
			process.color_ramp = _ramp([Color(0.9, 0.75, 0.5, 0.0), Color(0.9, 0.75, 0.5, 0.35), Color(0.9, 0.75, 0.5, 0.0)])
			spec["lifetime"] = 3.0
			spec["mesh"] = _quad(Vector2(0.025, 0.9), _lit(false))
			spec["align"] = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		"fine":  # fine_ash
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			process.emission_box_extents = Vector3(22, 4, 22)
			process.spread = 180.0
			process.initial_velocity_min = 0.1
			process.initial_velocity_max = 0.4
			process.gravity = Vector3(0.3, -0.15, 0.1)
			process.turbulence_enabled = true
			process.turbulence_noise_strength = 0.6
			process.color_ramp = _ramp([Color(0.5, 0.48, 0.46, 0.0), Color(0.5, 0.48, 0.46, 0.6), Color(0.5, 0.48, 0.46, 0.0)])
			spec["lifetime"] = 7.0
			spec["mesh"] = _quad(Vector2(0.025, 0.025), _lit(true))
		_:
			push_warning("Vfx: unknown kind " + kind)
			spec["lifetime"] = 0.3
			spec["mesh"] = _quad(Vector2(0.1, 0.1), _unshaded(true))
	spec["process"] = process
	_cache[kind] = spec
	return spec


static func _quad(size: Vector2, material: Material) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


# Bright, unlit particles (sparks, embers, magic). Values above 1 bloom.
static func _unshaded(billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# Lit soft particles (dust, droplets, ash): they take the scene's light and
# fade where they meet the ground.
static func _lit(billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	material.billboard_keep_scale = true
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.6
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _soft_dot() -> GradientTexture2D:
	if _cache.has("_dot"):
		return _cache["_dot"]
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_cache["_dot"] = texture
	return texture


static func _ramp(colors: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	for index in range(colors.size()):
		offsets.append(float(index) / maxf(1.0, colors.size() - 1.0))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.use_hdr = true
	return texture


static func _curve(values: Array) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 2.0
	for index in range(values.size()):
		curve.add_point(Vector2(float(index) / maxf(1.0, values.size() - 1.0), values[index]))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
