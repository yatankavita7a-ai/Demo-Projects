extends CharacterBody3D
class_name PlayerController

signal health_changed(current: float, maximum: float)
signal defeated
signal perfect_dodge
signal focus_changed(value: int)

# Souls-like jog.
const MOVE_SPEED := 4.6
const GRAVITY := 22.0
const INTERACT_DISTANCE := 3.2
const CACHE_SENSE_DISTANCE := 12.0
const GUARD_STAMINA_DRAIN := 10.0
# Dodge roll: distance travelled, length and the invulnerable part of it.
const ROLL_DURATION := 0.6
const ROLL_DISTANCE := 2.8
const ROLL_IFRAME_START := 0.05
const ROLL_IFRAME_END := 0.40
const ROLL_STAMINA := 18.0
# A roll may cut short the last part of an attack's recovery.
const ROLL_CANCEL_FRACTION := 0.4
# A hit evaded within this long of the i-frames starting is a perfect dodge.
const PERFECT_DODGE_WINDOW := 0.15
const PERFECT_DODGE_TIME_SCALE := 0.35
const PERFECT_DODGE_REAL_SECONDS := 0.45
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 40.0
const STAMINA_REGEN_DELAY := 0.6
const FOCUS_MAX := 3
const LIGHT_HITS_PER_FOCUS := 3
const CHARGE_HOLD_SECONDS := 0.5
const LIGHT_POSTURE := 6.0
const HEAVY_POSTURE := 12.0
const CRITICAL_MULTIPLIER := 2.5
const IMMOBILIZE_COOLDOWN := 45.0
const IMMOBILIZE_SECONDS := 2.5
const IMMOBILIZE_RANGE := 12.0
const LOCK_RANGE := 30.0
# Lock breaks a little beyond the range it was acquired in.
const LOCK_BREAK_RANGE := 36.0
# Classic camera: centred, further back.
const CAMERA_ARM_LENGTH := 5.2
# Close camera (default): low over the right shoulder, hero on the left third.
const CLOSE_ARM_LENGTH := 3.5
const CLOSE_SHOULDER_OFFSET := 0.8
const CLOSE_PIVOT_HEIGHT := 1.5
const CameraSettings = preload("res://scripts/player/CameraSettings.gd")
const CAMERA_FOV := 72.0
const PIVOT_HEIGHT := 1.45
const ModelRig = preload("res://scripts/visual/ModelRig.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
# Hero class -> Quaternius RPG character model.
const CLASS_MODELS := {
	"Warrior": "res://assets/models/characters/Warrior.gltf",
	"Mage": "res://assets/models/characters/Wizard.gltf",
	"Archer": "res://assets/models/characters/Ranger.gltf",
	"Assassin": "res://assets/models/characters/Rogue.gltf",
	"Healer": "res://assets/models/characters/Cleric.gltf",
	"Tank": "res://assets/models/characters/Monk.gltf",
}
const MODEL_HEIGHT := 1.8
const FOOTSTEP_STRIDE := 2.1
const SpectralSteed = preload("res://scripts/player/SpectralSteed.gd")
const JUMP_VELOCITY := 7.0
# Sprint: keep holding the dodge key (after the roll it started) while moving.
const SPRINT_SPEED_MULTIPLIER := 1.5
# Strafing around a lock target gets a smaller bonus.
const SPRINT_LOCKED_MULTIPLIER := 1.25
const SPRINT_STAMINA_DRAIN := 12.0
# Backstep: dodge with no movement input. Short hop back, short i-frames.
const BACKSTEP_DURATION := 0.35
const BACKSTEP_DISTANCE := 1.3
const BACKSTEP_IFRAME_START := 0.04
const BACKSTEP_IFRAME_END := 0.20
const BACKSTEP_STAMINA := 10.0
# Jump attacks: an attack in the air drops into a plunging strike that lands
# as a small shockwave.
const JUMP_ATTACK_DAMAGE_MULTIPLIER := 1.4
const JUMP_ATTACK_POSTURE_BONUS := 10.0
const PLUNGE_FALL_SPEED := 12.0
const JUMP_ATTACK_RADIUS_LIGHT := 2.6
const JUMP_ATTACK_RADIUS_HEAVY := 3.4
# Spectral steed (summoned mount).
const MOUNT_SPEED := 12.0
const MOUNT_ACCELERATION := 11.0
const MOUNT_DECELERATION := 18.0
# Turn rate (radians per second) at full gallop and at a standstill: the
# faster the steed runs, the wider it turns.
const MOUNT_TURN_RATE := 2.6
const MOUNT_TURN_RATE_SLOW := 7.0
const MOUNT_JUMP_VELOCITY := 8.0
const MOUNT_DOUBLE_JUMP_VELOCITY := 7.5
const MOUNT_REACH_BONUS := 0.8
const STEED_DASH_DURATION := 0.3
const STEED_DASH_DISTANCE := 2.8
const STEED_DASH_IFRAME_START := 0.03
const STEED_DASH_IFRAME_END := 0.18
const STEED_DASH_STAMINA := 12.0
# A hit this big (share of maximum health), a heavy/unblockable hit or a
# strong knockback throws the rider off the steed.
const DISMOUNT_DAMAGE_FRACTION := 0.15
const DISMOUNT_KNOCKBACK := 5.0
const DISMOUNT_STAGGER := 0.6
const STEED_RECALL_COOLDOWN := 10.0
const STEED_RIDE_HEIGHT := 0.55
const MOUNT_CAMERA_ARM := 6.8
const MOUNT_PIVOT_LIFT := 0.6
const MOUNT_FOV := 76.0
const SPRINT_FOV_BONUS := 4.0
# Ground speed at which the hero's walk/run clips play at normal speed;
# playback scales with actual speed so the feet do not slide.
const WALK_CLIP_SPEED := 1.9
const RUN_CLIP_SPEED := 4.6
# Being hit: a big hit (heavy, unblockable or this share of maximum health)
# staggers the hero briefly and pushes them away from the attacker.
const BIG_HIT_FRACTION := 0.2
const BIG_HIT_STAGGER := 0.35
const BIG_HIT_PUSH := 4.0
# Dodge variants share one timer (_roll_elapsed) and the perfect-dodge rules.
const DODGE_KINDS := {
	"roll": {"duration": ROLL_DURATION, "distance": ROLL_DISTANCE,
		"iframe_start": ROLL_IFRAME_START, "iframe_end": ROLL_IFRAME_END, "stamina": ROLL_STAMINA},
	"backstep": {"duration": BACKSTEP_DURATION, "distance": BACKSTEP_DISTANCE,
		"iframe_start": BACKSTEP_IFRAME_START, "iframe_end": BACKSTEP_IFRAME_END, "stamina": BACKSTEP_STAMINA},
	"steed_dash": {"duration": STEED_DASH_DURATION, "distance": STEED_DASH_DISTANCE,
		"iframe_start": STEED_DASH_IFRAME_START, "iframe_end": STEED_DASH_IFRAME_END, "stamina": STEED_DASH_STAMINA},
}

var maximum_health := 140.0
var health := 140.0
var attack_power := 22.0
var defense := 8.0
var stamina := 100.0
var _camera_yaw := 0.0
var _camera_pitch := -0.16
var _attack_cooldown := 0.0
var _attack_cooldown_total := 0.0
# Seconds since the current roll began; negative when not rolling.
var _roll_elapsed := -1.0
var _roll_direction := Vector3.ZERO
var _perfect_dodge_used := false
var _stamina_regen_delay := 0.0
var _knockback := Vector3.ZERO
var focus := 0
var _light_chain := 0
# Heavy attacks fire on release: a quick press is a normal heavy, a hold of
# CHARGE_HOLD_SECONDS or more spends all Focus on a charged heavy.
var _heavy_held := false
var _heavy_hold_time := 0.0
var _charge_glow := false
var immobilize_cooldown := 0.0
var _lock_target: Node3D
var _lock_marker: MeshInstance3D
var _spring_arm: SpringArm3D
# Sideways arm to the shoulder point; the main arm hangs back from its end.
# Both are spring arms, so walls push the camera in instead of clipping.
var _shoulder_arm: SpringArm3D
var _shake_strength := 0.0
var _parry_window := 0.0
var _parry_cooldown := 0.0
var _cache_sense_time := 0.0
# Set when guard runs out of stamina; guard stays down until the key is
# released and stamina has partly recovered, so an empty guard cannot flicker.
var _guard_broken := false
var _equipped_effects: Array = []
var _controls_enabled := true
var _nearby_interactable
var _crouching := false
var _camera: Camera3D
var _pivot: Node3D
var _collision_shape: CollisionShape3D
var _body_mesh: MeshInstance3D
var _hero_class := "Warrior"
# Visual model; turns to face movement. The body itself does not rotate, so
# the camera (a child of the body) only follows the mouse.
var _rig
var _step_distance := 0.0
var _dodge_kind := "roll"
var _sprinting := false
# Set when a sprint empties stamina; sprint stays off until the key is let go.
var _sprint_exhausted := false
# True from a jump until landing; attacks in this state become jump attacks.
var _jump_airborne := false
var _plunge_active := false
var _plunge_heavy := false
var _air_jumps_used := 0
# Short loss of control after being thrown from the steed.
var _stagger_time := 0.0
var _mounted := false
var _steed
var _steed_heading := Vector3.FORWARD
var _steed_speed := 0.0
var steed_cooldown := 0.0
# Floors can forbid the steed; the hub never allows it.
var steed_allowed := true


func _ready() -> void:
	_ensure_input_actions()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.46
	capsule.height = 1.8
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = capsule
	_collision_shape.position.y = 0.9
	add_child(_collision_shape)
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.75
	_body_mesh.mesh = mesh
	_body_mesh.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#b1a7a3")
	material.metallic = 0.18
	_body_mesh.material_override = material
	add_child(_body_mesh)
	_build_model()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, _base_pivot_height(), 0)
	add_child(_pivot)
	_shoulder_arm = SpringArm3D.new()
	# A spring arm extends along its +Z; turned +90 degrees that is the
	# pivot's right.
	_shoulder_arm.rotation.y = PI / 2.0
	_shoulder_arm.spring_length = _shoulder_offset()
	_shoulder_arm.margin = 0.2
	_shoulder_arm.add_excluded_object(get_rid())
	_pivot.add_child(_shoulder_arm)
	_spring_arm = SpringArm3D.new()
	_spring_arm.rotation.y = -PI / 2.0
	_spring_arm.spring_length = base_arm_length()
	_spring_arm.margin = 0.2
	_spring_arm.add_excluded_object(get_rid())
	_shoulder_arm.add_child(_spring_arm)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = CAMERA_FOV
	_spring_arm.add_child(_camera)
	_build_lock_marker()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure_hero(hero: Dictionary) -> void:
	var health_ratio = health / maximum_health if maximum_health > 0.0 else 1.0
	maximum_health = max(80.0, float(hero.get("hp", 140)))
	health = clampf(maximum_health * health_ratio, 1.0, maximum_health)
	attack_power = max(12.0, float(hero.get("atk", 22)))
	defense = max(3.0, float(hero.get("def", 8)))
	_equipped_effects = hero.get("effects", []).duplicate()
	var hero_class = str(hero.get("class", _hero_class))
	if hero_class != _hero_class:
		_hero_class = hero_class
		if is_node_ready():
			_build_model()
	health_changed.emit(health, maximum_health)


# Replaces the placeholder capsule with the hero class's animated model. The
# capsule stays as a fallback if the model cannot be loaded.
func _build_model() -> void:
	if _rig != null:
		_rig.queue_free()
		_rig = null
	var rig = ModelRig.new()
	if rig.load_model(CLASS_MODELS.get(_hero_class, CLASS_MODELS["Warrior"]), MODEL_HEIGHT):
		_rig = rig
		add_child(_rig)
		_body_mesh.visible = false
		_apply_crouch_visual()
	else:
		rig.free()
		_body_mesh.visible = true


func has_equipped_effect(effect_id: String) -> bool:
	return effect_id in _equipped_effects


func is_guarding() -> bool:
	return _controls_enabled and not _guard_broken and not _mounted and _stagger_time <= 0.0 \
		and Input.is_action_pressed("guard") and stamina > 0.0


func is_crouching() -> bool:
	return _controls_enabled and not _mounted and Input.is_action_pressed("crouch")


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		_steed_speed = 0.0
		_sprinting = false
		_cancel_heavy_charge()


func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled:
		return
	# While locked on, the camera follows the target instead of the mouse.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_locked_on():
		_camera_yaw -= event.relative.x * 0.0025
		_camera_pitch = clamp(_camera_pitch - event.relative.y * 0.002, -0.85, 0.3)
		_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0)
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("dodge"):
		_on_dodge_pressed()
	if event.is_action_pressed("steed"):
		toggle_steed()
	if event.is_action_pressed("light_attack"):
		_attack(false)
	if event.is_action_pressed("heavy_attack"):
		# In the air a heavy press strikes at once (a plunging heavy).
		if _jump_airborne and not _mounted:
			_attack(true)
		else:
			_begin_heavy_charge()
	elif event.is_action_released("heavy_attack") and _heavy_held:
		_release_heavy_attack(_heavy_hold_time)
	if event.is_action_pressed("parry"):
		_start_parry()
	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
	if is_locked_on():
		if event.is_action_pressed("lock_next"):
			cycle_lock_target(1)
		elif event.is_action_pressed("lock_previous"):
			cycle_lock_target(-1)
	if event.is_action_pressed("immobilize"):
		cast_immobilize()


func _physics_process(delta: float) -> void:
	if not _controls_enabled:
		velocity = Vector3.ZERO
		_update_model(delta, Vector3.ZERO)
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _roll_elapsed >= 0.0:
		_roll_elapsed += delta
		if _roll_elapsed >= dodge_duration():
			_roll_elapsed = -1.0
	_stagger_time = maxf(0.0, _stagger_time - delta)
	steed_cooldown = maxf(0.0, steed_cooldown - delta)
	_parry_window = maxf(0.0, _parry_window - delta)
	_parry_cooldown = maxf(0.0, _parry_cooldown - delta)
	_cache_sense_time = maxf(0.0, _cache_sense_time - delta)
	immobilize_cooldown = maxf(0.0, immobilize_cooldown - delta)
	if _heavy_held:
		_heavy_hold_time += delta
		_update_charge_glow()
	_update_lock_target()
	if _guard_broken and not Input.is_action_pressed("guard") and stamina >= 20.0:
		_guard_broken = false
	_update_crouch_pose(is_crouching())
	var move_input := Vector2.ZERO
	if _stagger_time <= 0.0:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Camera-relative: while locked on, sideways input circles the target.
	var move_direction := Vector3(move_input.x, 0, move_input.y).rotated(Vector3.UP, _camera_yaw)
	_update_sprint(delta, move_input)
	_regenerate_stamina(delta)
	if _mounted:
		_steed_move(delta, move_direction)
	else:
		var move_speed := MOVE_SPEED
		if _crouching:
			move_speed *= 0.55
		if is_guarding():
			move_speed *= 0.45
			stamina = maxf(0.0, stamina - delta * GUARD_STAMINA_DRAIN)
			_stamina_regen_delay = STAMINA_REGEN_DELAY
			if stamina <= 0.0:
				_guard_broken = true
		if _sprinting:
			move_speed *= sprint_multiplier()
		if is_rolling():
			var dodge_speed := dodge_speed_at(_dodge_kind, _roll_elapsed)
			velocity.x = _roll_direction.x * dodge_speed
			velocity.z = _roll_direction.z * dodge_speed
		else:
			velocity.x = move_direction.x * move_speed
			velocity.z = move_direction.z * move_speed
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 30.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump"):
		_try_jump()
	move_and_slide()
	if is_on_floor() and velocity.y <= 0.01:
		_on_landed()
	_update_interactable()
	var facing_move := move_direction
	if is_rolling():
		facing_move = _roll_direction
	_update_model(delta, facing_move)


# Stamina recovers quickly, but only after a short pause since it was last
# spent, and never while guarding or sprinting.
func _regenerate_stamina(delta: float) -> void:
	_stamina_regen_delay = maxf(0.0, _stamina_regen_delay - delta)
	if is_guarding() or _sprinting or _stamina_regen_delay > 0.0:
		return
	var stamina_regeneration := STAMINA_REGEN
	if has_equipped_effect("mossmantle") and _is_near_cover():
		stamina_regeneration += 6.0
	stamina = minf(STAMINA_MAX, stamina + delta * stamina_regeneration)


func _spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_regen_delay = STAMINA_REGEN_DELAY


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_lock_marker()


# Turns the model toward movement, picks its looping animation and plays
# footsteps while walking on the ground.
func _update_model(delta: float, move_direction: Vector3) -> void:
	if _rig == null or health <= 0.0:
		return
	var face_direction := move_direction
	if _mounted:
		# The rider faces where the steed runs.
		face_direction = _steed_heading
	elif is_rolling() and _dodge_kind == "backstep":
		# A backstep keeps facing forward.
		face_direction = -_roll_direction
	elif is_locked_on() and not is_rolling():
		# Locked on, the hero keeps facing the target while strafing.
		face_direction = _lock_target.global_position - global_position
		face_direction.y = 0.0
	if face_direction.length_squared() > 0.01:
		var target_yaw := atan2(-face_direction.x, -face_direction.z)
		_rig.rotation.y = lerp_angle(_rig.rotation.y, target_yaw, minf(1.0, delta * 14.0))
	var horizontal := Vector2(velocity.x, velocity.z).length()
	_rig.position.y = lerpf(_rig.position.y, STEED_RIDE_HEIGHT if _mounted else 0.0, minf(1.0, delta * 12.0))
	if _mounted and is_instance_valid(_steed):
		_steed.rotation.y = _rig.rotation.y
		_steed.set_gait(horizontal, delta)
	var state := "idle"
	var speed := 1.0
	if _mounted:
		state = "idle"
	elif is_guarding():
		state = "guard"
	elif horizontal > 0.3:
		var running := not _crouching and horizontal > 3.0
		state = "run" if running else "walk"
		# Playback follows ground speed (quantised so it is not re-set
		# every frame) so the feet do not slide.
		var reference := RUN_CLIP_SPEED if running else WALK_CLIP_SPEED
		speed = snappedf(clampf(horizontal / reference, 0.5, 1.8), 0.05)
	_rig.set_locomotion(state, speed)
	# Procedural lean where the packs have no clip: forward while sprinting,
	# tucked in a jump, diving in a plunge.
	var lean := 0.0
	if _mounted:
		lean = 0.0
	elif _plunge_active:
		lean = -0.35
	elif _jump_airborne:
		lean = -0.12
	elif _sprinting:
		lean = -0.14
	_rig.set_lean(lean)
	if is_on_floor() and horizontal > 0.5 and not is_rolling():
		_step_distance += horizontal * delta
		var stride := FOOTSTEP_STRIDE * (0.7 if _crouching else 1.0) * (1.6 if _mounted else 1.0)
		if _step_distance >= stride:
			_step_distance = 0.0
			SoundBank.play_at("footstep", global_position, self, 0.7 if _mounted else (0.85 if _crouching else 1.0))


# --- Dodge roll ---------------------------------------------------------------

# True during any dodge: roll, backstep or the steed's sidestep dash.
func is_rolling() -> bool:
	return _roll_elapsed >= 0.0 and _roll_elapsed < dodge_duration()


func get_dodge_kind() -> String:
	return _dodge_kind if is_rolling() else ""


func dodge_duration() -> float:
	return float(DODGE_KINDS[_dodge_kind]["duration"])


func is_invulnerable() -> bool:
	var kind: Dictionary = DODGE_KINDS[_dodge_kind]
	return _roll_elapsed >= float(kind["iframe_start"]) and _roll_elapsed <= float(kind["iframe_end"])


# Speed falls linearly from twice the average to zero, covering ROLL_DISTANCE.
static func roll_speed_at(elapsed: float) -> float:
	return dodge_speed_at("roll", elapsed)


# Same profile for every dodge kind, covering that kind's distance.
static func dodge_speed_at(kind_name: String, elapsed: float) -> float:
	var kind: Dictionary = DODGE_KINDS.get(kind_name, DODGE_KINDS["roll"])
	var duration := float(kind["duration"])
	var average := float(kind["distance"]) / duration
	return maxf(0.0, 2.0 * average * (1.0 - elapsed / duration))


func can_roll(kind_name: String = "roll") -> bool:
	if is_rolling() or _stagger_time > 0.0 or _plunge_active:
		return false
	if stamina < float(DODGE_KINDS[kind_name]["stamina"]):
		return false
	# Only the last part of an attack's recovery can be cancelled.
	return _attack_cooldown <= _attack_cooldown_total * ROLL_CANCEL_FRACTION + 0.0001


# The dodge key: on the steed a sidestep dash, standing still a backstep,
# otherwise a roll toward the movement input.
func _on_dodge_pressed() -> bool:
	if _mounted:
		return _start_dodge("steed_dash")
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move_input.length_squared() <= 0.01:
		return _start_dodge("backstep")
	return _start_dodge("roll")


func _start_dodge(kind_name: String = "roll") -> bool:
	if not can_roll(kind_name):
		return false
	_spend_stamina(float(DODGE_KINDS[kind_name]["stamina"]))
	_attack_cooldown = 0.0
	_cancel_heavy_charge()
	_dodge_kind = kind_name
	_roll_elapsed = 0.0
	_perfect_dodge_used = false
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	match kind_name:
		"backstep":
			_roll_direction = -_facing_direction()
			if _rig != null:
				# No backstep clip: a quick lean back.
				_rig.kick_lean(0.3, BACKSTEP_DURATION)
			SoundBank.play_at("dodge", global_position, self, 1.2)
			return true
		"steed_dash":
			var right := _steed_heading.cross(Vector3.UP).normalized()
			var wanted := Vector3(move_input.x, 0, move_input.y).rotated(Vector3.UP, _camera_yaw)
			_roll_direction = -right if wanted.dot(right) < -0.2 else right
			SoundBank.play_at("dodge", global_position, self, 0.8)
			return true
	if move_input.length_squared() > 0.01:
		_roll_direction = Vector3(move_input.x, 0, move_input.y).normalized().rotated(Vector3.UP, _camera_yaw)
	else:
		_roll_direction = _facing_direction(false)
	if _rig != null:
		_rig.rotation.y = atan2(-_roll_direction.x, -_roll_direction.z)
		if not _rig.play_action("roll", ROLL_DURATION):
			# Models without a roll clip dive forward instead.
			_rig.kick_lean(-0.7, ROLL_DURATION)
	SoundBank.play_at("dodge", global_position, self)
	return true


# Where the hero faces: toward the lock target if asked and locked on, else
# the model's facing, else the camera's.
func _facing_direction(use_lock: bool = true) -> Vector3:
	if use_lock and is_locked_on():
		var to_target := _lock_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			return to_target.normalized()
	if _rig != null:
		return Vector3(-sin(_rig.rotation.y), 0, -cos(_rig.rotation.y))
	return _camera_forward()


# --- Sprint ---------------------------------------------------------------------

func is_sprinting() -> bool:
	return _sprinting


func sprint_multiplier() -> float:
	return SPRINT_LOCKED_MULTIPLIER if is_locked_on() else SPRINT_SPEED_MULTIPLIER


func can_sprint(move_input: Vector2) -> bool:
	return _controls_enabled and Input.is_action_pressed("dodge") and not _sprint_exhausted \
		and stamina > 0.0 and move_input.length_squared() > 0.01 and not is_rolling() \
		and not _mounted and not is_guarding() and not _crouching and _stagger_time <= 0.0 \
		and not _plunge_active


# Drains stamina while sprinting and blocks its regeneration; an empty bar
# ends the sprint until the key is released.
func _update_sprint(delta: float, move_input: Vector2) -> void:
	if _sprint_exhausted and not Input.is_action_pressed("dodge"):
		_sprint_exhausted = false
	_sprinting = can_sprint(move_input)
	if not _sprinting:
		return
	stamina = maxf(0.0, stamina - delta * SPRINT_STAMINA_DRAIN)
	_stamina_regen_delay = STAMINA_REGEN_DELAY
	if stamina <= 0.0:
		_sprint_exhausted = true


# Called whenever an attack is avoided by the roll's i-frames.
func _on_attack_evaded() -> void:
	# A hit avoided during a dodge's invulnerable frames reveals caches with
	# the Glassward.
	if has_equipped_effect("glassward"):
		_cache_sense_time = 6.0
	var iframe_start := float(DODGE_KINDS[_dodge_kind]["iframe_start"])
	if _perfect_dodge_used or _roll_elapsed - iframe_start > PERFECT_DODGE_WINDOW:
		return
	_perfect_dodge_used = true
	add_focus(1)
	if _rig != null:
		_rig.spawn_afterimage()
	apply_time_scale(PERFECT_DODGE_TIME_SCALE, PERFECT_DODGE_REAL_SECONDS)
	SoundBank.play_at("reveal_epic", global_position, self)
	if _rig != null:
		_rig.set_glow(Color(0.35, 0.55, 0.9))
		get_tree().create_timer(PERFECT_DODGE_REAL_SECONDS, false, false, true).timeout.connect(_clear_rig_glow)
	perfect_dodge.emit()


func _clear_rig_glow() -> void:
	if _rig != null and not _charge_glow:
		_rig.clear_glow()


# --- Focus and attacks ----------------------------------------------------------

func add_focus(amount: int) -> void:
	var updated := clampi(focus + amount, 0, FOCUS_MAX)
	if updated != focus:
		focus = updated
		focus_changed.emit(focus)


func _start_parry() -> void:
	if _parry_cooldown > 0.0 or stamina < 16.0 or _mounted or _stagger_time > 0.0:
		return
	_spend_stamina(8.0)
	_parry_window = 0.24
	_parry_cooldown = 0.7


func _begin_heavy_charge() -> void:
	if _attack_cooldown > 0.0 or is_rolling() or _stagger_time > 0.0 or _plunge_active:
		return
	_heavy_held = true
	_heavy_hold_time = 0.0


func _cancel_heavy_charge() -> void:
	_heavy_held = false
	_heavy_hold_time = 0.0
	if _charge_glow:
		_charge_glow = false
		if _rig != null:
			_rig.clear_glow()


func is_charge_ready() -> bool:
	return _heavy_held and _heavy_hold_time >= CHARGE_HOLD_SECONDS and focus >= 1


func _update_charge_glow() -> void:
	if is_charge_ready() and not _charge_glow:
		_charge_glow = true
		if _rig != null:
			_rig.set_glow(Color(0.85, 0.6, 0.15))
		SoundBank.play_at("swing_light", global_position, self, 0.6)


# Releasing heavy attack: held long enough with Focus, it spends all of it.
func _release_heavy_attack(held_seconds: float) -> int:
	var spend := focus if held_seconds >= CHARGE_HOLD_SECONDS and focus >= 1 else 0
	_cancel_heavy_charge()
	return _attack(true, spend)


func charged_damage(focus_spent: int) -> float:
	return attack_power * (2.0 + 1.0 * focus_spent)


static func charged_posture(focus_spent: int) -> float:
	return 25.0 + 20.0 * focus_spent


# Swings at every enemy in front within reach and returns how many were hit.
# `focus_spent` > 0 makes it a charged heavy that consumes that much Focus.
func _attack(heavy: bool, focus_spent: int = 0) -> int:
	if _attack_cooldown > 0.0 or is_rolling() or _stagger_time > 0.0 or _plunge_active:
		return 0
	if _jump_airborne and not _mounted:
		return _start_jump_attack(heavy)
	var charged := heavy and focus_spent > 0
	var cost := 26.0 if heavy else 12.0
	if heavy and has_equipped_effect("embersong"):
		cost += 10.0
	if stamina < cost:
		return 0
	_spend_stamina(cost)
	if charged:
		focus_spent = mini(focus_spent, focus)
		add_focus(-focus_spent)
	_attack_cooldown = 0.8 if charged else (0.62 if heavy else 0.36)
	_attack_cooldown_total = _attack_cooldown
	var facing := _camera_forward()
	var min_dot := 0.25
	var reach := attack_reach(heavy) + (1.5 if charged else 0.0)
	if is_locked_on():
		var to_target := _lock_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			facing = to_target.normalized()
	elif _mounted:
		# From the saddle the swing goes to the side the camera looks at.
		facing = mounted_swing_side()
		min_dot = -0.1
	if _mounted:
		reach += MOUNT_REACH_BONUS
	if _rig != null:
		# Swing toward where the hit lands.
		_rig.rotation.y = atan2(-facing.x, -facing.z)
		_rig.play_action("heavy" if heavy else "light", 0.85 if charged else (0.75 if heavy else 0.5))
	SoundBank.play_at("swing_heavy" if heavy else "swing_light", global_position, self, 0.8 if charged else 1.0)
	var damage = charged_damage(focus_spent) if charged else attack_power * (1.75 if heavy else 1.0)
	var posture = charged_posture(focus_spent) if charged else (HEAVY_POSTURE if heavy else LIGHT_POSTURE)
	_spawn_swing_trail(facing, reach, heavy, charged)
	var result := _strike(facing, min_dot, reach, damage, posture, heavy, charged)
	var hits: int = result["hits"]
	_after_strike(hits, heavy, charged or bool(result["critical"]))
	return hits


# Steed attacks: the side (left or right of the steed's heading) the camera
# faces.
func mounted_swing_side() -> Vector3:
	var right := _steed_heading.cross(Vector3.UP).normalized()
	return right if _camera_forward().dot(right) >= 0.0 else -right


# Hits every enemy within `reach` whose direction has at least `min_dot`
# with `facing` (a zero `facing` hits all around). Returns hits and whether
# any was a critical.
func _strike(facing: Vector3, min_dot: float, reach: float, damage: float, posture: float,
		heavy: bool, charged: bool, extra_info: Dictionary = {}) -> Dictionary:
	var hits := 0
	var critical_hit := false
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var offset: Vector3 = enemy.global_position - global_position
		var flat_offset := Vector3(offset.x, 0, offset.z)
		# Big bodies can be struck from further away.
		var target_reach := reach + _target_radius(enemy)
		if flat_offset.length() > target_reach:
			continue
		if facing != Vector3.ZERO and flat_offset.length() > 0.01 and facing.dot(flat_offset.normalized()) < min_dot:
			continue
		if not _can_hit_through(enemy):
			continue
		var info := {"posture": posture, "charged": charged}
		info.merge(extra_info)
		var amount: float = damage
		if (heavy or charged) and enemy.has_method("is_staggered") and enemy.is_staggered():
			info["critical"] = true
			amount *= CRITICAL_MULTIPLIER
			critical_hit = true
		_deliver_hit(enemy, amount, heavy, heavy and has_equipped_effect("embersong"), info)
		hits += 1
	return {"hits": hits, "critical": critical_hit}


# Focus from light chains, hit-stop and shake after a swing resolves.
func _after_strike(hits: int, heavy: bool, big: bool) -> void:
	if not heavy:
		# Every third consecutive light hit that connects earns Focus.
		if hits > 0:
			_light_chain += 1
			if _light_chain >= LIGHT_HITS_PER_FOCUS:
				_light_chain = 0
				add_focus(1)
		else:
			_light_chain = 0
	if hits > 0:
		if big:
			hit_stop(0.12)
			camera_shake(0.6)
		else:
			hit_stop(0.08 if heavy else 0.05)
			if heavy:
				camera_shake(0.25)


# --- Jumping, jump attacks ------------------------------------------------------

func is_airborne_from_jump() -> bool:
	return _jump_airborne


func is_plunging() -> bool:
	return _plunge_active


# Jump from the ground; on the steed a second jump in mid-air.
func _try_jump() -> bool:
	if not _controls_enabled or _stagger_time > 0.0 or is_rolling() or _plunge_active:
		return false
	if is_on_floor():
		velocity.y = MOUNT_JUMP_VELOCITY if _mounted else JUMP_VELOCITY
		_jump_airborne = true
		_air_jumps_used = 0
		return true
	if _mounted and _air_jumps_used < 1:
		velocity.y = MOUNT_DOUBLE_JUMP_VELOCITY
		_jump_airborne = true
		_air_jumps_used += 1
		_spawn_shockwave(global_position, 1.4, Color(0.55, 0.85, 1.0, 0.8), 0.35)
		SoundBank.play_at("dodge", global_position, self, 0.65)
		return true
	return false


# An attack in the air: costs the normal stamina now, strikes on landing.
func _start_jump_attack(heavy: bool) -> int:
	var cost := 26.0 if heavy else 12.0
	if heavy and has_equipped_effect("embersong"):
		cost += 10.0
	if stamina < cost:
		return 0
	_spend_stamina(cost)
	_cancel_heavy_charge()
	_plunge_active = true
	_plunge_heavy = heavy
	velocity.y = minf(velocity.y, -PLUNGE_FALL_SPEED)
	_spawn_swing_trail(_facing_direction(), 2.0, heavy, false, true)
	if _rig != null:
		_rig.play_action("heavy" if heavy else "light", 0.45 if heavy else 0.35)
	SoundBank.play_at("swing_heavy" if heavy else "swing_light", global_position, self, 0.85)
	return 0


static func jump_attack_damage(power: float, heavy: bool) -> float:
	return power * (1.75 if heavy else 1.0) * JUMP_ATTACK_DAMAGE_MULTIPLIER


static func jump_attack_posture(heavy: bool) -> float:
	return (HEAVY_POSTURE if heavy else LIGHT_POSTURE) + JUMP_ATTACK_POSTURE_BONUS


func _on_landed() -> void:
	_air_jumps_used = 0
	if _plunge_active:
		_land_jump_attack()
	_jump_airborne = false


# The plunge lands: a shockwave hits every enemy around the landing spot.
func _land_jump_attack() -> int:
	if not _plunge_active:
		return 0
	_plunge_active = false
	_jump_airborne = false
	var heavy := _plunge_heavy
	var radius := JUMP_ATTACK_RADIUS_HEAVY if heavy else JUMP_ATTACK_RADIUS_LIGHT
	var result := _strike(Vector3.ZERO, -2.0, radius, jump_attack_damage(attack_power, heavy),
		jump_attack_posture(heavy), heavy, false, {"jump_attack": true})
	var hits: int = result["hits"]
	_attack_cooldown = 0.6 if heavy else 0.4
	_attack_cooldown_total = _attack_cooldown
	_spawn_shockwave(global_position, radius, Color(0.85, 0.75, 0.55, 0.85), 0.45)
	SoundBank.play_at("guard_block", global_position, self, 0.6 if heavy else 0.8)
	camera_shake(0.45 if heavy else 0.25)
	_after_strike(hits, heavy, bool(result["critical"]))
	return hits


# Expanding dust/ghost ring on the ground (landings, double jumps, summons).
func _spawn_shockwave(at: Vector3, radius: float, color: Color, seconds: float) -> void:
	if not is_inside_tree():
		return
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.08
	ring.scale = Vector3(radius * 0.25, 0.4, radius * 0.25)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.15, radius), seconds)
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.chain().tween_callback(ring.queue_free)


# Short bright ribbon sweeping through the swing's arc (weapon trail),
# golden for charged heavies. `overhead` sweeps vertically (plunges).
func _spawn_swing_trail(facing: Vector3, reach: float, heavy: bool, charged: bool, overhead: bool = false) -> void:
	if not is_inside_tree() or facing.length_squared() < 0.01:
		return
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return
	var color := Color(1.0, 0.78, 0.3, 0.95) if charged else (Color(1.0, 0.92, 0.8, 0.85) if heavy else Color(0.9, 0.95, 1.0, 0.75))
	var radius := clampf(reach * 0.75, 1.2, 3.2)
	var arc := deg_to_rad(150.0 if heavy else 110.0)
	var steps := 14
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(steps + 1):
		var t := float(index) / steps
		var angle := lerpf(-arc * 0.5, arc * 0.5, t)
		var direction := Vector3(sin(angle), 0.0, -cos(angle))
		var inner := direction * radius * 0.35
		var outer := direction * radius
		if overhead:
			# Vertical arc in front: the fan turned onto the forward/up plane.
			inner = Vector3(0.0, -inner.x, inner.z)
			outer = Vector3(0.0, -outer.x, outer.z)
		# Brightest at the leading edge, fading toward the start of the swing.
		tool.set_color(Color(color.r, color.g, color.b, 0.0))
		tool.add_vertex(inner)
		tool.set_color(Color(color.r, color.g, color.b, color.a * t))
		tool.add_vertex(outer)
	var trail := MeshInstance3D.new()
	trail.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	trail.material_override = material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(trail)
	var lift := (1.0 if overhead else 1.1) + (STEED_RIDE_HEIGHT if _mounted else 0.0)
	trail.global_position = global_position + Vector3.UP * lift
	# Tilted into a diagonal slash so it reads from the camera behind.
	trail.global_rotation = Vector3(0.0 if overhead else -0.35, atan2(-facing.x, -facing.z), 0.0 if overhead else 0.75)
	var tween := trail.create_tween()
	# Holds its brightness, then fades out quickly.
	tween.tween_property(material, "albedo_color:a", 0.0, 0.26 if charged else 0.2).from(1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(trail.queue_free)


# --- Spectral steed ---------------------------------------------------------------

func is_mounted() -> bool:
	return _mounted


func is_stunned() -> bool:
	return _stagger_time > 0.0


func get_steed_speed() -> float:
	return _steed_speed


func get_steed_heading() -> Vector3:
	return _steed_heading


func can_summon_steed() -> bool:
	return steed_allowed and not _is_in_hub() and steed_cooldown <= 0.0 and health > 0.0 \
		and _controls_enabled and not is_rolling() and _stagger_time <= 0.0 and not _plunge_active \
		and _attack_cooldown <= 0.0


func toggle_steed() -> bool:
	if _mounted:
		dismount()
		return true
	return summon_steed()


func summon_steed() -> bool:
	if _mounted or not can_summon_steed():
		return false
	_mounted = true
	_cancel_heavy_charge()
	_sprinting = false
	_steed_heading = _facing_direction(false)
	_steed_speed = Vector2(velocity.x, velocity.z).length()
	_update_crouch_pose(false)
	_steed = SpectralSteed.new()
	add_child(_steed)
	_steed.rotation.y = atan2(-_steed_heading.x, -_steed_heading.z)
	_steed.appear()
	_spawn_shockwave(global_position, 1.8, Color(0.55, 0.85, 1.0, 0.8), 0.4)
	SoundBank.play_at("reveal_epic", global_position, self, 1.3)
	return true


# Voluntary dismount keeps no cooldown; `thrown` (a big hit) staggers the
# rider and keeps the steed away for STEED_RECALL_COOLDOWN.
func dismount(thrown: bool = false) -> void:
	if not _mounted:
		return
	_mounted = false
	_steed_speed = 0.0
	if is_instance_valid(_steed):
		_steed.vanish()
	_steed = null
	if _dodge_kind == "steed_dash" and is_rolling():
		_roll_elapsed = -1.0
	if thrown:
		_stagger_time = DISMOUNT_STAGGER
		steed_cooldown = STEED_RECALL_COOLDOWN
		_cancel_heavy_charge()
		if _rig != null and health > 0.0:
			_rig.play_action("hit", DISMOUNT_STAGGER)


func _steed_move(delta: float, move_direction: Vector3) -> void:
	if move_direction.length_squared() > 0.01:
		var desired := move_direction.normalized()
		var pace := clampf(_steed_speed / MOUNT_SPEED, 0.0, 1.0)
		var turn_rate := lerpf(MOUNT_TURN_RATE_SLOW, MOUNT_TURN_RATE, pace)
		_steed_heading = turn_toward(_steed_heading, desired, turn_rate * delta)
		# Asked to go the other way, the steed reins in while it turns.
		var target := MOUNT_SPEED * clampf(_steed_heading.dot(desired), 0.3, 1.0)
		var rate := MOUNT_ACCELERATION if target > _steed_speed else MOUNT_DECELERATION
		_steed_speed = move_toward(_steed_speed, target, rate * delta)
	else:
		_steed_speed = move_toward(_steed_speed, 0.0, MOUNT_DECELERATION * delta)
	velocity.x = _steed_heading.x * _steed_speed
	velocity.z = _steed_heading.z * _steed_speed
	if is_rolling() and _dodge_kind == "steed_dash":
		var dash := dodge_speed_at("steed_dash", _roll_elapsed)
		velocity.x += _roll_direction.x * dash
		velocity.z += _roll_direction.z * dash


# Rotates `from` toward `to` on the ground plane by at most `max_angle`.
static func turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var from_yaw := atan2(from.x, from.z)
	var to_yaw := atan2(to.x, to.z)
	var step := clampf(wrapf(to_yaw - from_yaw, -PI, PI), -max_angle, max_angle)
	var yaw := from_yaw + step
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _is_in_hub() -> bool:
	var node: Node = get_parent()
	while node != null:
		var script = node.get_script()
		if script is Script and String(script.resource_path).begins_with("res://scripts/hub/"):
			return true
		node = node.get_parent()
	return false


# Big hits throw the rider: a share of maximum health, a heavy or
# unblockable attack, or a strong knockback.
func _check_dismount(amount: float, info: Dictionary) -> void:
	if not _mounted or health <= 0.0:
		return
	var push = info.get("knockback", Vector3.ZERO)
	var strong_push: bool = push is Vector3 and Vector2(push.x, push.z).length() >= DISMOUNT_KNOCKBACK
	if amount >= maximum_health * DISMOUNT_DAMAGE_FRACTION or bool(info.get("heavy", false)) \
			or bool(info.get("unblockable", false)) or strong_push:
		dismount(true)


# Calls take_hit with the info dictionary when the enemy accepts it.
static func _deliver_hit(enemy: Object, amount: float, heavy: bool, ignite: bool, info: Dictionary) -> void:
	var take_hit := Callable(enemy, "take_hit")
	if take_hit.get_argument_count() >= 4:
		enemy.take_hit(amount, heavy, ignite, info)
	else:
		enemy.take_hit(amount, heavy, ignite)


func _target_radius(enemy: Node) -> float:
	if enemy.has_method("get_size_scale"):
		return maxf(0.0, (float(enemy.get_size_scale()) - 1.0) * 0.45)
	return 0.0


func _camera_forward() -> Vector3:
	return Vector3(-sin(_camera_yaw), 0, -cos(_camera_yaw))


# The Ironwood Bow turns heavy attacks into a ranged shot.
func attack_reach(heavy: bool) -> float:
	if heavy and has_equipped_effect("ironwood_bow"):
		return 7.0
	return 3.2 if heavy else 2.5


func _can_hit_through(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.2,
		target.global_position + Vector3.UP * 1.0
	)
	# Only terrain blocks attacks; other enemies do not shield the target.
	var exclude: Array[RID] = [get_rid()]
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if is_instance_valid(enemy) and enemy is CollisionObject3D:
			exclude.append(enemy.get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func is_sensing_caches() -> bool:
	return _cache_sense_time > 0.0


# --- Immobilize -------------------------------------------------------------------

# Freezes the lock target (or the nearest enemy in front) briefly.
func cast_immobilize() -> bool:
	if immobilize_cooldown > 0.0 or health <= 0.0:
		return false
	var target: Node3D = _lock_target if is_locked_on() else _find_target(IMMOBILIZE_RANGE, 0.3)
	if target == null or not target.has_method("apply_immobilize"):
		SoundBank.play_at("swing_light", global_position, self, 0.5)
		return false
	target.apply_immobilize(IMMOBILIZE_SECONDS)
	immobilize_cooldown = IMMOBILIZE_COOLDOWN
	SoundBank.play_at("reveal_legend", target.global_position, self)
	_spawn_immobilize_flash(target)
	return true


func _spawn_immobilize_flash(target: Node3D) -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return
	var flash := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.05
	flash.mesh = ring
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.82, 0.4, 0.9)
	flash.material_override = material
	host.add_child(flash)
	var radius := 1.0 + _target_radius(target)
	flash.global_position = _lock_point(target) - Vector3.UP * 0.4
	flash.scale = Vector3.ONE * radius * 0.4
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * radius * 1.8, 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(flash.queue_free)


# --- Lock-on -----------------------------------------------------------------------

func is_locked_on() -> bool:
	return _is_valid_target(_lock_target)


func get_lock_target() -> Node3D:
	return _lock_target if is_locked_on() else null


func toggle_lock_on() -> void:
	if is_locked_on():
		release_lock()
	else:
		_lock_target = _find_target(LOCK_RANGE, 0.2)


func release_lock() -> void:
	_lock_target = null


func _is_valid_target(node) -> bool:
	if not is_instance_valid(node) or not node is Node3D or not node.is_inside_tree():
		return false
	if not node.is_in_group("tower_enemies"):
		return false
	if "health" in node and float(node.health) <= 0.0:
		return false
	return true


# Nearest living enemy within `max_distance` whose direction from the camera's
# facing has a dot product of at least `min_dot`.
func _find_target(max_distance: float, min_dot: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_distance
	var facing := _camera_forward()
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if not _is_valid_target(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > best_distance:
			continue
		if distance > 0.01 and facing.dot(offset / distance) < min_dot:
			continue
		best = enemy
		best_distance = distance
	return best


# Switches to the next target to the right (1) or left (-1) of the camera.
func cycle_lock_target(direction: int) -> void:
	if not is_locked_on():
		return
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if _is_valid_target(enemy) and global_position.distance_to(enemy.global_position) <= LOCK_RANGE:
			candidates.append(enemy)
	if candidates.size() < 2:
		return
	candidates.sort_custom(func(a, b): return _bearing_to(a) < _bearing_to(b))
	var index := candidates.find(_lock_target)
	_lock_target = candidates[posmod(index + direction, candidates.size())]


# Angle of a node relative to the camera's facing; positive is to the right.
func _bearing_to(node: Node3D) -> float:
	var offset := node.global_position - global_position
	var yaw_to := atan2(-offset.x, -offset.z)
	return -wrapf(yaw_to - _camera_yaw, -PI, PI)


func _update_lock_target() -> void:
	if _lock_target == null:
		return
	if not _is_valid_target(_lock_target) or global_position.distance_to(_lock_target.global_position) > LOCK_BREAK_RANGE:
		release_lock()


func _lock_point(target: Node3D) -> Vector3:
	if target.has_method("get_lock_point"):
		return target.get_lock_point()
	return target.global_position + Vector3.UP * 1.2


func _target_size(target: Node3D) -> float:
	if target != null and target.has_method("get_size_scale"):
		return float(target.get_size_scale())
	return 1.0


# Camera distance, shoulder offset and pivot height for the chosen mode.
func base_arm_length() -> float:
	return CLOSE_ARM_LENGTH if CameraSettings.is_close() else CAMERA_ARM_LENGTH


func _shoulder_offset() -> float:
	return CLOSE_SHOULDER_OFFSET if CameraSettings.is_close() else 0.0


func _base_pivot_height() -> float:
	return CLOSE_PIVOT_HEIGHT if CameraSettings.is_close() else PIVOT_HEIGHT


func _update_camera(delta: float) -> void:
	if _pivot == null or _camera == null:
		return
	var weight := minf(1.0, delta * 6.0)
	var arm_length := base_arm_length()
	var shoulder := _shoulder_offset()
	var pivot_lift := 0.0
	var fov := CAMERA_FOV
	if is_locked_on():
		var size := _target_size(_lock_target)
		if size > 2.5:
			# Big bosses: pull back and up so the whole body stays in view.
			var t := clampf((size - 2.5) / 2.5, 0.0, 1.0)
			arm_length = lerpf(6.6, 9.0, t)
			# Wukong-style framing: higher and wider, nearly centred.
			shoulder = minf(shoulder, lerpf(0.35, 0.15, t))
			pivot_lift = lerpf(0.6, 1.4, t)
			fov = lerpf(76.0, 80.0, t)
		var to_point := _lock_point(_lock_target) - _pivot.global_position
		var flat := Vector2(to_point.x, to_point.z).length()
		if flat > 0.3:
			var target_yaw := atan2(-to_point.x, -to_point.z)
			_camera_yaw = lerp_angle(_camera_yaw, target_yaw, minf(1.0, delta * 8.0))
			var target_pitch := clampf(atan2(to_point.y, flat) - 0.18, -0.7, 0.4)
			_camera_pitch = lerpf(_camera_pitch, target_pitch, minf(1.0, delta * 5.0))
		_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0)
	if _mounted:
		# Riding: pull back and up a little to see the ground ahead.
		arm_length = maxf(arm_length, MOUNT_CAMERA_ARM)
		pivot_lift = maxf(pivot_lift, MOUNT_PIVOT_LIFT)
		fov = maxf(fov, MOUNT_FOV)
	elif _sprinting:
		fov += SPRINT_FOV_BONUS
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, arm_length, weight)
	_shoulder_arm.spring_length = lerpf(_shoulder_arm.spring_length, shoulder, weight)
	_camera.fov = lerpf(_camera.fov, fov, weight)
	var base_height := 1.08 if _crouching else _base_pivot_height()
	_pivot.position.y = lerpf(_pivot.position.y, base_height + pivot_lift, weight)
	# Camera shake: a random offset that decays quickly.
	if _shake_strength > 0.001:
		_shake_strength = maxf(0.0, _shake_strength - delta * 2.5)
		var amount := _shake_strength * _shake_strength * 0.35
		_camera.h_offset = randf_range(-amount, amount)
		_camera.v_offset = randf_range(-amount, amount)
	elif _camera.h_offset != 0.0 or _camera.v_offset != 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


func _build_lock_marker() -> void:
	_lock_marker = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	_lock_marker.mesh = quad
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.5, 0.62, 0.8])
	gradient.colors = PackedColorArray([
		Color(1, 0.95, 0.8, 1), Color(1, 0.75, 0.35, 1), Color(0.9, 0.35, 0.15, 0.0),
		Color(1, 0.7, 0.3, 0.9), Color(1, 0.6, 0.2, 0.0)
	])
	dot.gradient = gradient
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.fixed_size = true
	material.no_depth_test = true
	material.render_priority = 10
	material.albedo_texture = dot
	_lock_marker.material_override = material
	_lock_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lock_marker.top_level = true
	_lock_marker.visible = false
	add_child(_lock_marker)


func _update_lock_marker() -> void:
	if _lock_marker == null:
		return
	_lock_marker.visible = is_locked_on()
	if _lock_marker.visible:
		_lock_marker.global_position = _lock_point(_lock_target)


# --- Game feel ---------------------------------------------------------------------

# Active slow-downs: token -> scale. The slowest active one wins, and each is
# removed by a real-time timer owned by the SceneTree, so the time scale is
# restored even if the player is freed, the scene changes or the game pauses.
static var _time_scale_effects := {}
static var _time_scale_serial := 0


static func apply_time_scale(time_scale: float, real_seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or real_seconds <= 0.0:
		return
	_time_scale_serial += 1
	var token := _time_scale_serial
	_time_scale_effects[token] = clampf(time_scale, 0.01, 1.0)
	_refresh_time_scale()
	tree.create_timer(real_seconds, true, false, true).timeout.connect(func():
		_time_scale_effects.erase(token)
		_refresh_time_scale()
	)


static func _refresh_time_scale() -> void:
	var slowest := 1.0
	for value in _time_scale_effects.values():
		slowest = minf(slowest, value)
	Engine.time_scale = slowest


# A short freeze on impact. Public so the boss side can use it too.
func hit_stop(seconds: float) -> void:
	apply_time_scale(0.05, clampf(seconds, 0.0, 0.3))


func camera_shake(strength: float) -> void:
	_shake_strength = clampf(maxf(_shake_strength, strength), 0.0, 1.5)


# --- Taking damage -----------------------------------------------------------------

func take_damage(amount: float, guardable: bool = true) -> void:
	if health <= 0.0:
		return
	if is_invulnerable():
		_on_attack_evaded()
		return
	var guarding := guardable and is_guarding()
	var reduction = 0.62 if guarding else 0.0
	var final_damage = maxf(1.0, amount * (1.0 - reduction) - defense * 0.12)
	if guarding:
		var block_cost = 0.6 if has_equipped_effect("thorn_circlet") else 0.45
		_spend_stamina(amount * block_cost)
		if stamina <= 0.0:
			_guard_broken = true
		if has_equipped_effect("thorn_circlet"):
			health = minf(maximum_health, health + final_damage * 0.08)
	health = maxf(0.0, health - final_damage)
	if health <= 0.0:
		dismount()
	else:
		_check_dismount(amount, {})
	# Taking damage breaks the light-hit chain that builds Focus.
	_light_chain = 0
	_cancel_heavy_charge()
	SoundBank.play_at("guard_block" if guarding else "hit_player", global_position, self)
	if _rig != null:
		if health <= 0.0:
			# The defeat screen pauses the game; let the fall still play out.
			_rig.process_mode = Node.PROCESS_MODE_ALWAYS
			_rig.play_death()
		elif guarding:
			_rig.kick_lean(0.08, 0.15)
		else:
			_rig.play_hit_react(1.0, true)
	health_changed.emit(health, maximum_health)
	if health <= 0.0:
		release_lock()
		SoundBank.play_ui("player_death")
		defeated.emit()


# info (all optional): "unblockable" (guard and parry do nothing),
# "parryable" (default true), "knockback" (Vector3 push). Returns true only
# when the attack was parried.
func receive_enemy_attack(amount: float, source: Node, info: Dictionary = {}) -> bool:
	if health <= 0.0:
		return false
	if is_invulnerable():
		_on_attack_evaded()
		return false
	var unblockable := bool(info.get("unblockable", false))
	var parryable := bool(info.get("parryable", true)) and not unblockable
	if parryable and _parry_window > 0.0 and stamina >= 8.0 and source is Node3D:
		var incoming: Vector3 = source.global_position - global_position
		incoming.y = 0.0
		if incoming.length_squared() > 0.01 and _camera_forward().dot(incoming.normalized()) >= 0.25:
			_parry_window = 0.0
			_spend_stamina(8.0)
			if source.has_method("on_parried"):
				source.on_parried()
			SoundBank.play_at("parry", global_position, self)
			hit_stop(0.1)
			camera_shake(0.3)
			return true
	var guarded := not unblockable and is_guarding()
	var was_mounted := _mounted
	take_damage(amount, not unblockable)
	_check_dismount(amount, info)
	var push = info.get("knockback", Vector3.ZERO)
	if push is Vector3 and push.length_squared() > 0.0001:
		_knockback = Vector3(push.x, 0.0, push.z) * (0.4 if guarded else 1.0)
		if push.y > 0.0 and not guarded:
			velocity.y = maxf(velocity.y, push.y)
	elif is_big_hit(amount, info) and not guarded and source is Node3D:
		var away: Vector3 = global_position - source.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			_knockback = away.normalized() * BIG_HIT_PUSH
	if not guarded and not was_mounted and health > 0.0 and is_big_hit(amount, info):
		# Big boss hits: a stronger flinch and a short stagger.
		_stagger_time = maxf(_stagger_time, BIG_HIT_STAGGER)
		_cancel_heavy_charge()
		if _rig != null:
			_rig.play_hit_react(2.0, true)
		camera_shake(0.35)
	return false


func is_big_hit(amount: float, info: Dictionary) -> bool:
	return bool(info.get("heavy", false)) or bool(info.get("unblockable", false)) \
		or amount >= maximum_health * BIG_HIT_FRACTION


func heal(amount: float) -> void:
	health = minf(maximum_health, health + amount)
	health_changed.emit(health, maximum_health)


func _update_interactable() -> void:
	var closest
	var closest_distance := CACHE_SENSE_DISTANCE if is_sensing_caches() else INTERACT_DISTANCE
	for node in get_tree().get_nodes_in_group("world_interactables"):
		if not is_instance_valid(node):
			continue
		var distance = global_position.distance_to(node.global_position)
		if node.interaction_kind != "equipment" and distance > INTERACT_DISTANCE:
			continue
		if distance <= closest_distance:
			closest = node
			closest_distance = distance
	if is_instance_valid(_nearby_interactable) and _nearby_interactable != closest:
		_nearby_interactable.discovered = false
		if _nearby_interactable.concealed:
			for child in _nearby_interactable.get_children():
				if child is VisualInstance3D:
					child.visible = false
	_nearby_interactable = closest
	if is_instance_valid(closest):
		closest.reveal()


func _update_crouch_pose(crouching: bool) -> void:
	if _crouching == crouching:
		return
	_crouching = crouching
	var capsule: CapsuleShape3D = _collision_shape.shape
	capsule.height = 1.2 if crouching else 1.8
	_collision_shape.position.y = 0.6 if crouching else 0.9
	_body_mesh.scale.y = 0.72 if crouching else 1.0
	_body_mesh.position.y = 0.66 if crouching else 0.9
	_pivot.position.y = 1.08 if crouching else _base_pivot_height()
	_apply_crouch_visual()


# The character pack has no crouch clip, so crouching squats the model
# (shorter and a little wider) and slows its walk.
func _apply_crouch_visual() -> void:
	if _rig != null:
		_rig.scale = Vector3(1.08, 0.72, 1.08) if _crouching else Vector3.ONE


func _try_interact() -> void:
	if is_instance_valid(_nearby_interactable):
		_nearby_interactable.activate_for(self)


func get_interaction_prompt() -> String:
	if is_instance_valid(_nearby_interactable):
		return "E — " + _nearby_interactable.prompt_text
	if steed_cooldown > 0.0 and steed_allowed:
		return "The spectral steed is gathering itself (%d s)." % ceili(steed_cooldown)
	if has_equipped_effect("broken_compass") or has_equipped_effect("echo_lantern"):
		for node in get_tree().get_nodes_in_group("world_interactables"):
			if is_instance_valid(node) and node.interaction_kind == "equipment" and global_position.distance_to(node.global_position) < 24.0:
				return "A hidden cache stirs nearby."
	# Controls live in Settings (Esc); the play screen shows prompts only.
	return ""


func _is_near_cover() -> bool:
	for cover in get_tree().get_nodes_in_group("world_cover"):
		if is_instance_valid(cover) and global_position.distance_to(cover.global_position) <= 8.0:
			return true
	return false


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("interact", KEY_E)
	_add_key_action("dodge", KEY_SHIFT)
	_add_key_action("guard", KEY_Q)
	_add_key_action("crouch", KEY_CTRL)
	_add_key_action("parry", KEY_F)
	_add_mouse_action("light_attack", MOUSE_BUTTON_LEFT)
	_add_mouse_action("heavy_attack", MOUSE_BUTTON_RIGHT)
	_add_mouse_action("lock_on", MOUSE_BUTTON_MIDDLE)
	_add_key_action("lock_on", KEY_TAB)
	_add_mouse_action("lock_next", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse_action("lock_previous", MOUSE_BUTTON_WHEEL_UP)
	_add_key_action("immobilize", KEY_V)
	_add_key_action("steed", KEY_R)


func _add_key_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)


func _add_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)
