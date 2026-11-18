extends CharacterBody3D
class_name EnemyAgent

signal defeated(enemy: EnemyAgent)
# A hit that did nothing: Vharzul's scales without Dragonbane ("armored"),
# or a flying boss out of reach ("airborne").
signal deflected(enemy: EnemyAgent, reason: String)

const GRAVITY := 20.0
const ModelRig = preload("res://scripts/visual/ModelRig.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const BossBrain = preload("res://scripts/battle/BossBrain.gd")
const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const Vfx = preload("res://scripts/visual/Vfx.gd")
const MONSTERS := "res://assets/models/monsters/"
# Regular enemies by region (floors 1-5, 6-10, ...), Quaternius monsters.
const REGION_MODELS := [
	MONSTERS + "Big/Demon.gltf",          # Ashen Threshold - volcanic ruins
	MONSTERS + "Blob/Mushnub.gltf",       # Whispering Canopy - ancient forest
	MONSTERS + "Big/Orc.gltf",            # Crown of Dust - abandoned kingdom
	MONSTERS + "Big/Fish.gltf",           # Drowned Reach - flooded city
	MONSTERS + "Big/Yeti.gltf",           # The Pale March - snowbound valley
	MONSTERS + "Flying/Goleling.gltf",    # Hollow Deep - underground caves
	MONSTERS + "Flying/Ghost.gltf",       # Gloamwood - haunted woodland
	MONSTERS + "Big/Tribal.gltf",         # Sunken Sepulchre - forgotten temple
	MONSTERS + "Blob/Orc.gltf",           # The Red Expanse - battlefield
	MONSTERS + "Big/BlueDemon.gltf",      # Nightglass Summit - citadel
]
# One distinct, larger monster per floor guardian (boss_index 0-9).
const BOSS_MODELS := [
	MONSTERS + "Flying/Dragon_Evolved.gltf",   # The Cinder Warden
	MONSTERS + "Big/MushroomKing.gltf",        # Mother of Briars
	MONSTERS + "Flying/Alpaking_Evolved.gltf", # The Brass Regent
	MONSTERS + "Flying/Glub_Evolved.gltf",     # The Drowned Cantor
	MONSTERS + "Big/Bunny.gltf",               # The Pale Huntress
	MONSTERS + "Blob/GreenSpikyBlob.gltf",     # The Maw Below
	MONSTERS + "Big/Ninja.gltf",               # The Hollow Knight
	MONSTERS + "Flying/Ghost_Skull.gltf",      # The Sepulchre Twin
	MONSTERS + "Big/Orc_Skull.gltf",           # The Red Marshal
	MONSTERS + "Big/Alien.gltf",               # The Starless Sovereign
	MONSTERS + "Flying/Dragon.gltf",           # Vharzul, the Unburnt Wyrm (floor 20)
]
const ENEMY_HEIGHT := 1.8
const FREEZE_GLOW := Color(0.15, 0.3, 0.6)
const WINDUP_GLOW := Color(0.55, 0.2, 0.05)
const BOSS_GLOW := Color(0.22, 0.03, 0.05)
const BOSS_COLORS := [
	Color("#a44f36"), Color("#557447"), Color("#ad8e48"), Color("#477787"),
	Color("#a9c0d0"), Color("#666584"), Color("#b4aba0"), Color("#806890"),
	Color("#9a483f"), Color("#514a77"), Color("#c9b48a")
]
const DRAGON_GLOW := Color(0.28, 0.16, 0.04)
const WEAK_POINT_COLOR := Color(1.0, 0.55, 0.15)

var health := 70.0
var maximum_health := 70.0
var attack_power := 12.0
var move_speed := 3.2
var attack_range := 2.2
var attack_timer := 0.0
var telegraph_timer := 0.0
var boss := false
var boss_floor := 0
var boss_name := ""
var boss_pattern := ""
var weakness := ""
var boss_index := -1
var player
var _alive := true
var _body_mesh: MeshInstance3D
var _body_material: StandardMaterial3D
# Animated monster model; the capsule above is only a fallback.
var _rig
var _winding_up := false
var _burn_time := 0.0
var _burn_tick := 0.0
var _stagger_time := 0.0
var _alert_recovery_time := 0.0
var alerted := false
# Boss size as a multiple of the 1.8 m player (1.0 for regular enemies).
var size_scale := 1.0
# Spawned by a boss (Red Marshal banner call): not counted by the floor.
var summoned := false
var _immobile_time := 0.0
# Boss behaviour (state machine, posture, phases); null for regular enemies.
var _brain
# Seconds a regular enemy's wind-up lasts (zombie kinds change it).
var telegraph_time := 0.45
# Dead Tide zombie (floor 10): always hunting, never counted by the floor.
var horde := false
var zombie_kind := ""
var light_armor := 1.0     # damage taken from light hits (brutes: 0.5)
var _zombie_model := ""
var _zombie_tint := Color.BLACK
# Vharzul (floor 20): scales turn every blade unless the player carries
# Dragonbane or the Chain Rite has dragged it down.
var dragon := false
var dragonbane := false
var _weak_marker: MeshInstance3D

var posture: float:
	get:
		return _brain.posture if _brain != null else 0.0
	set(value):
		if _brain != null:
			_brain.posture = clampf(value, 0.0, _brain.posture_max)
var posture_max: float:
	get:
		return _brain.posture_max if _brain != null else 100.0
	set(value):
		if _brain != null:
			_brain.posture_max = maxf(1.0, value)
var phase: int:
	get:
		return _brain.phase if _brain != null else 1
	set(value):
		pass


func _ready() -> void:
	add_to_group("tower_enemies")
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.36 * size_scale, 1.9) if boss else 0.4 * size_scale
	capsule.height = maxf(capsule.radius * 2.0 + 0.2, ENEMY_HEIGHT * size_scale * 0.85) if boss else 1.55 * size_scale
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	add_child(collision)
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = capsule.height
	_body_mesh.mesh = mesh
	_body_mesh.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = BOSS_COLORS[boss_index] if boss else Color("#58545d")
	material.emission_enabled = boss
	material.emission = Color("#3b1217") if boss else Color.BLACK
	_body_mesh.material_override = material
	_body_material = material
	add_child(_body_mesh)
	var rig = ModelRig.new()
	var region = clampi(int(floori(float(boss_floor - 1) / 5.0)), 0, REGION_MODELS.size() - 1)
	var model_path: String = BOSS_MODELS[clampi(boss_index, 0, BOSS_MODELS.size() - 1)] if boss else REGION_MODELS[region]
	if horde and not _zombie_model.is_empty():
		model_path = _zombie_model
	if rig.load_model(model_path, ENEMY_HEIGHT * size_scale):
		_rig = rig
		add_child(_rig)
		_body_mesh.visible = false
		if boss:
			_rig.set_glow(_rest_glow())
			if dragon:
				# Ash-gold scales the Tower's fire never blackened.
				_rig.apply_rot(Color(1.0, 0.86, 0.62), 0.6)
		elif horde:
			# Sickly grey-green rot over the borrowed monster model.
			_rig.apply_rot(_zombie_tint, 0.82)
	else:
		rig.free()
	if horde:
		material.albedo_color = Color("#5d6b4f")
	if dragon:
		_build_weak_point()


func configure_enemy(player_node, floor_number: int, is_boss: bool, boss_data: Dictionary = {}) -> void:
	player = player_node
	boss = is_boss
	boss_floor = floor_number
	boss_name = boss_data.get("name", "")
	boss_pattern = boss_data.get("attacks", "")
	weakness = boss_data.get("weakness", "")
	boss_index = int(floori(float(floor_number - 1) / 5.0)) if is_boss else -1
	var scale_factor = 1.0 + float(floor_number - 1) * 0.035
	maximum_health = (85.0 if boss else 48.0) * scale_factor
	attack_power = (17.0 if boss else 9.0) * scale_factor
	move_speed = 2.65 if boss else 3.3
	attack_range = 2.9 if boss else 1.9
	size_scale = 1.0
	_brain = null
	if boss:
		# Size, health and speed per boss (scripts/battle/BossMoves.gd).
		# A floor may name its own moveset (floor 20 uses Vharzul's).
		boss_index = clampi(int(boss_data.get("moveset", boss_index)), 0, BossMoves.boss_count() - 1)
		dragon = boss_index == BossMoves.DRAGON_INDEX
		var stats := BossMoves.boss_stats(boss_index)
		size_scale = float(stats["size"])
		maximum_health *= float(stats["health"])
		move_speed = float(stats["speed"])
		_brain = BossBrain.new(self, boss_index)
		attack_range = _brain.body_radius() + 2.0
	if boss:
		var state = PlayerData.get_state()
		var boss_index = int(floori(float(floor_number - 1) / 5.0))
		var journal: Dictionary = state.get("investigation_journal", {})
		var known_clues = 0
		for clue_stage in range(4):
			if journal.has("boss_%d_clue_%d" % [boss_index, clue_stage]):
				known_clues += 1
		maximum_health *= 1.0 - minf(0.25, known_clues * 0.055)
		attack_power *= 1.0 - minf(0.2, known_clues * 0.045)
		var allies = int(state.get("faction_relations", {}).get("wayfarer_covenant", 0))
		maximum_health *= 1.0 - minf(0.2, allies * 0.02)
		attack_power *= 1.0 - minf(0.15, allies * 0.015)
		# A known weakness (clue 2) opens longer punish windows.
		if journal.has("boss_%d_clue_2" % boss_index):
			_brain.recovery_mult = BossBrain.WEAKNESS_RECOVERY
		if dragon:
			dragonbane = PlayerData.has_dragonbane()
	health = maximum_health


# A Dead Tide zombie (scripts/systems/SpecialFloors.gd ZOMBIE_KINDS) scaled
# by the current escalation tier. Call before adding it to the tree.
func configure_zombie(player_node, floor_number: int, kind: String, health_mult: float = 1.0, speed_mult: float = 1.0) -> void:
	configure_enemy(player_node, floor_number, false)
	var spec: Dictionary = SpecialFloors.ZOMBIE_KINDS.get(kind, SpecialFloors.ZOMBIE_KINDS["shambler"])
	horde = true
	summoned = true
	alerted = true
	zombie_kind = kind if SpecialFloors.ZOMBIE_KINDS.has(kind) else "shambler"
	maximum_health *= float(spec["health"]) * health_mult
	attack_power *= float(spec["attack"])
	move_speed = float(spec["speed"]) * speed_mult
	size_scale = float(spec["size"])
	attack_range = 1.9 + (size_scale - 1.0) * 0.8
	telegraph_time = float(spec["windup"])
	light_armor = float(spec["armor"])
	_zombie_model = String(spec["model"])
	_zombie_tint = spec["tint"]
	health = maximum_health


func _physics_process(delta: float) -> void:
	if not _alive or not is_instance_valid(player) or player.health <= 0:
		return
	_burn_time = maxf(0.0, _burn_time - delta)
	_burn_tick -= delta
	if _burn_time > 0.0 and _burn_tick <= 0.0:
		_burn_tick = 0.5
		if not is_roaring() and not is_armored():
			_lose_health(2.0)
			if not _alive:
				return
	if _brain != null:
		_boss_physics(delta)
		return
	if _immobile_time > 0.0:
		# Frozen in place: timers, wind-ups and movement all wait.
		_immobile_time -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _immobile_time <= 0.0:
			_set_rig_frozen(false)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_stagger_time = maxf(0.0, _stagger_time - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	telegraph_timer = maxf(0.0, telegraph_timer - delta)
	var offset: Vector3 = player.global_position - global_position
	var flat := Vector3(offset.x, 0, offset.z)
	var distance = flat.length()
	if distance > 0.01:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	if horde:
		alerted = true   # the dead always know where the living are
	else:
		_update_alert(distance, delta)
	# Only an alerted enemy pursues; one that has lost sight keeps hunting
	# until its alert wears off.
	if not alerted:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	elif _stagger_time > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
	elif distance > attack_range * 0.8:
		velocity.x = flat.normalized().x * move_speed
		velocity.z = flat.normalized().z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
		if attack_timer <= 0.0 and telegraph_timer <= 0.0 and has_line_of_sight():
			# Every attack winds up visibly first so it can be read, dodged or
			# parried. The countdown runs in physics time, so it pauses with
			# the game and is cancelled by staggers and parries.
			telegraph_timer = telegraph_time
			attack_timer = 1.5 + telegraph_time - 0.45
			_set_windup_visual(true)
	if _winding_up:
		if _stagger_time > 0.0:
			_set_windup_visual(false)
		elif telegraph_timer <= 0.0:
			_perform_attack()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if _rig != null:
		var moving := Vector2(velocity.x, velocity.z).length() > 0.4
		_rig.set_locomotion("walk" if moving else "idle", move_speed / 3.0 if moving else 1.0)


# Bosses: the brain steers, turns and attacks; the agent applies gravity.
func _boss_physics(delta: float) -> void:
	var offset: Vector3 = player.global_position - global_position
	var distance := Vector2(offset.x, offset.z).length()
	_update_alert(distance, delta)
	_brain.physics_step(delta, alerted)
	if not _alive:
		return
	if _weak_marker != null:
		_weak_marker.visible = dragonbane and not _brain.airborne
		_weak_marker.position.y = ENEMY_HEIGHT * size_scale * 0.32 + _brain.lift
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if _rig != null:
		var speed := Vector2(velocity.x, velocity.z).length()
		var moving: bool = speed > 0.4 and _brain.state == BossBrain.State.IDLE
		# Big bodies take long, slow strides.
		_rig.set_locomotion("walk" if moving else "idle", clampf(speed / (1.4 * size_scale), 0.35, 1.6) if moving else 1.0)


func _update_alert(distance: float, delta: float) -> void:
	var aggro_range = 12.0 if player.has_equipped_effect("quiet_steps") else 34.0
	if player.is_crouching():
		aggro_range = minf(aggro_range, 8.0)
	# Ruined cover hides the player unless they are right next to the enemy.
	if distance <= aggro_range and (distance <= 3.0 or has_line_of_sight()):
		_alert_recovery_time = 8.0
		alerted = true
	else:
		_alert_recovery_time = maxf(0.0, _alert_recovery_time - delta)
		alerted = _alert_recovery_time > 0.0


func _set_windup_visual(active: bool) -> void:
	_winding_up = active
	if not active:
		telegraph_timer = 0.0
	_body_mesh.scale = Vector3(1.1, 1.05, 1.1) if active else Vector3.ONE
	if _rig != null:
		# The model swells, glows and starts its strike: the strike's peak
		# lines up with the end of the wind-up.
		_rig.scale = Vector3(1.1, 1.05, 1.1) if active else Vector3.ONE
		if active:
			_rig.set_glow(WINDUP_GLOW)
			_rig.play_action("heavy" if boss else "light", telegraph_timer * 2.0)
		elif boss:
			_rig.set_glow(BOSS_GLOW)
		else:
			_rig.clear_glow()
	_body_material.emission_enabled = active or boss
	if active:
		_body_material.emission = Color("#c8642a")
	else:
		_body_material.emission = Color("#3b1217") if boss else Color.BLACK


func has_line_of_sight() -> bool:
	if not is_instance_valid(player) or not is_inside_tree():
		return false
	var exclude: Array[RID] = [player.get_rid()]
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if is_instance_valid(enemy):
			exclude.append(enemy.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.2,
		player.global_position + Vector3.UP * 1.0
	)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# Regular enemies only; bosses attack through BossBrain.
func _perform_attack() -> void:
	if not _alive or not is_instance_valid(player):
		return
	_set_windup_visual(false)
	var distance = global_position.distance_to(player.global_position)
	SoundBank.play_at("enemy_swing", global_position, self)
	if not has_line_of_sight():
		return
	if distance <= attack_range + 0.5:
		player.receive_enemy_attack(attack_power, self)


func on_parried() -> void:
	if not _alive:
		return
	if _brain != null:
		_brain.on_parried()
		return
	_stagger_time = maxf(_stagger_time, 1.2)
	attack_timer = minf(attack_timer, 0.5)
	_set_windup_visual(false)
	if _rig != null:
		_rig.play_action("hit")


# info (optional, from the player): "posture" (posture damage), "critical"
# (a heavy hit on a staggered boss), "charged". Callers that pass only three
# arguments still work.
func take_hit(amount: float, heavy: bool, ignite: bool = false, info: Dictionary = {}) -> void:
	if not _alive:
		return
	if _brain != null and _brain.is_roaring():
		# Invulnerable during the phase-two roar.
		SoundBank.play_at("guard_block", global_position, self, 0.7)
		return
	if _brain != null and _brain.airborne:
		# Flying out of reach.
		SoundBank.play_at("swing_light", global_position, self, 0.6)
		deflected.emit(self, "airborne")
		return
	if is_armored():
		_deflect()
		return
	if dragon and dragonbane and is_weak_point_hit():
		# Dragonbane finds the seam in the scales.
		amount *= SpecialFloors.WEAK_POINT_MULT
		info = info.duplicate()
		info["posture"] = float(info.get("posture", BossBrain.HEAVY_POSTURE if heavy else BossBrain.LIGHT_POSTURE)) * SpecialFloors.WEAK_POINT_MULT
		info["weak_point"] = true
		SoundBank.play_at("parry", global_position, self, 1.3)
	if horde and not heavy and not info.get("charged", false):
		amount *= light_armor
		if light_armor < 1.0:
			SoundBank.play_at("guard_block", global_position, self, 1.2)
	var exposure_bonus = 1.0
	if boss and PlayerData.get_state()["investigation_journal"].has(
		"boss_%d_clue_2" % int(floori(float(boss_floor - 1) / 5.0))
	):
		exposure_bonus = 1.2
	var dealt := amount
	if _brain != null:
		dealt = _brain.modify_incoming(amount, heavy, info, maximum_health)
	if ignite:
		_burn_time = 3.0
		_burn_tick = 0.5
	if heavy and player.has_equipped_effect("ironwood_bow"):
		# Bosses are too big to flinch from an arrow: it wears posture down.
		if _brain != null:
			_brain.add_posture(BossBrain.IRONWOOD_POSTURE)
		else:
			_stagger_time = 0.8
	SoundBank.play_at("hit_enemy_heavy" if heavy or info.get("critical", false) else "hit_enemy", global_position, self)
	if is_inside_tree():
		Vfx.hit(get_parent(), _hit_point(), heavy, bool(info.get("critical", false)) or bool(info.get("weak_point", false)))
	_lose_health(dealt * exposure_bonus)
	if not _alive:
		return
	if _rig != null and _rig.has_method("play_hit_react"):
		# Flash and jolt only; it never interrupts a wind-up clip.
		_rig.play_hit_react(1.6 if heavy or info.get("critical", false) else 1.0)
	if _brain != null:
		if _rig != null and _brain.state in [BossBrain.State.IDLE, BossBrain.State.RECOVERY] and size_scale < 2.0:
			_rig.play_action("hit", 0.4)
	elif _rig != null and not _winding_up and light_armor >= 1.0:
		# A hit does not cancel a wind-up, so its telegraph stays readable.
		# Armoured brutes do not flinch.
		_rig.play_action("hit", 0.4)


# Removes health, starts the boss's phase two at half health (a phase-one
# boss cannot be taken below 40% so the roar always happens) and handles
# death.
func _lose_health(amount: float) -> void:
	if not _alive:
		return
	health = maxf(0.0, health - amount)
	if _brain != null and _brain.should_enter_phase_two(health, maximum_health):
		health = maxf(health, maximum_health * 0.4)
		_brain.begin_phase_two()
	if health <= 0.0:
		_die()


func _die() -> void:
	_alive = false
	if _brain != null:
		_brain.cleanup(true)
	_leave_corpse()
	defeated.emit(self)
	queue_free()


func is_staggered() -> bool:
	if _brain != null:
		return _brain.is_staggered()
	return _stagger_time > 0.0


func is_roaring() -> bool:
	return _brain != null and _brain.is_roaring()


# True while damage is ignored (the boss's phase-two roar).
func is_invulnerable() -> bool:
	return is_roaring() or is_airborne() or is_armored()


# Vharzul without Dragonbane, unless the Chain Rite holds it down.
func is_armored() -> bool:
	return dragon and not dragonbane and not is_chained()


func is_airborne() -> bool:
	return _brain != null and _brain.airborne


func is_chained() -> bool:
	return _brain != null and _brain.is_chained()


# Wind-up and damage multipliers (Chain Rite: full aggression, harder
# each cycle).
func set_aggression(windup_mult: float, damage_mult: float) -> void:
	if _brain != null:
		_brain.windup_mult = clampf(windup_mult, 0.3, 1.5)
		_brain.damage_mult = maxf(0.1, damage_mult)


# The Chain Rite drags the boss down for `seconds`. False if it cannot.
func chain_down(seconds: float) -> bool:
	if not _alive or _brain == null:
		return false
	return _brain.chain_down(seconds)


# Where Dragonbane bites deepest: the throat and belly just in front of the
# chest, or anywhere while the wyrm's head is down (staggered or chained).
func weak_point_position() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var reach: float = _brain.body_radius() if _brain != null else 0.5
	return global_position + forward * (reach + 0.9)


func is_weak_point_hit() -> bool:
	if _brain != null and (_brain.state == BossBrain.State.STAGGER):
		return true
	if not is_instance_valid(player):
		return false
	var point := weak_point_position()
	var offset: Vector3 = player.global_position - point
	offset.y = 0.0
	return offset.length() <= 2.6


# Steel rings off the scales: a clang, a burst of sparks and a HUD hint.
func _deflect() -> void:
	SoundBank.play_at("parry", global_position, self, 1.6)
	deflected.emit(self, "armored")
	if not is_inside_tree() or get_parent() == null or not is_instance_valid(player):
		return
	Vfx.deflect(get_parent(), _hit_point())
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	spark.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.85, 0.45, 0.95)
	spark.material_override = material
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(spark)
	var toward: Vector3 = player.global_position - global_position
	toward.y = 0.0
	var radius: float = _brain.body_radius() if _brain != null else 0.5
	spark.global_position = global_position + toward.normalized() * radius + Vector3.UP * 1.4
	var tween := spark.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3.ONE * 2.6, 0.25)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(spark.queue_free)


func _build_weak_point() -> void:
	_weak_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	_weak_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = WEAK_POINT_COLOR
	material.emission_enabled = true
	material.emission = WEAK_POINT_COLOR
	material.emission_energy_multiplier = 3.0
	_weak_marker.material_override = material
	_weak_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = _brain.body_radius() if _brain != null else 0.5
	_weak_marker.position = Vector3(0.0, ENEMY_HEIGHT * size_scale * 0.32, -(reach + 0.3))
	_weak_marker.visible = dragonbane
	add_child(_weak_marker)


func _rest_glow() -> Color:
	return DRAGON_GLOW if dragon else BOSS_GLOW


# Dead Tide zombies crumble when the tide ends: the death animation plays
# but no burst or reward follows.
func collapse() -> void:
	if not _alive:
		return
	zombie_kind = "collapsed"
	_die()


# Freezes the enemy in place. Bosses take 60% of the time and are then
# immune for 20 s. Returns false when it had no effect.
func apply_immobilize(seconds: float) -> bool:
	if not _alive or seconds <= 0.0:
		return false
	if _brain != null:
		return _brain.apply_immobilize(seconds)
	_immobile_time = maxf(_immobile_time, seconds)
	_set_rig_frozen(true)
	return true


func is_immobilized() -> bool:
	if _brain != null:
		return _brain.is_immobilized()
	return _immobile_time > 0.0


func _set_rig_frozen(frozen: bool) -> void:
	if _rig == null:
		return
	_rig.set_frozen(frozen)
	if frozen:
		_rig.set_glow(FREEZE_GLOW)
	elif _winding_up:
		_rig.set_glow(WINDUP_GLOW)
	else:
		_rig.clear_glow()


# Where the camera's lock-on frames the enemy: chest height.
func get_lock_point() -> Vector3:
	if boss:
		var raised: float = _brain.lift if _brain != null else 0.0
		return global_position + Vector3.UP * (ENEMY_HEIGHT * size_scale * 0.6 + raised)
	return global_position + Vector3.UP * 1.1


# Where a blow visibly lands: from the chest toward the attacker, at the
# body's surface. Purely visual.
func _hit_point() -> Vector3:
	var point := get_lock_point()
	if not is_instance_valid(player):
		return point
	var toward: Vector3 = player.global_position + Vector3.UP * 1.1 - point
	return point + toward.normalized() * minf(toward.length() * 0.5, 0.45 * size_scale)


func get_size_scale() -> float:
	return size_scale


# The enemy node is freed at once; its model is handed to the floor to play
# the death animation and then removes itself. Purely visual.
func _leave_corpse() -> void:
	SoundBank.play_at("boss_death" if boss else "enemy_death", global_position, self)
	if _rig == null or not is_inside_tree() or get_parent() == null:
		return
	var corpse = _rig
	_rig = null
	corpse.visible = true
	corpse.scale = Vector3.ONE
	corpse.set_frozen(false)
	corpse.set_action_speed(1.0)
	corpse.clear_glow()
	corpse.reparent(get_parent())
	corpse.process_mode = Node.PROCESS_MODE_PAUSABLE
	corpse.play_death(true)
