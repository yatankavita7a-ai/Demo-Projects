extends SceneTree

# Movement pass checks: sprint, backstep, jump and jump attacks, and the
# spectral steed (summon rules, inertia, double jump, sidestep dash, side
# swings, being thrown off, camera). Run through tests/run_tests.sh.

const PlayerControllerScript = preload("res://scripts/player/PlayerController.gd")
const SettingsScreenScript = preload("res://scripts/ui/SettingsScreen.gd")
const DT := 1.0 / 60.0

const DUMMY_SOURCE := """
extends CharacterBody3D
var health := 100.0
var hits: Array = []
var staggered := false
func take_hit(amount: float, heavy: bool, ignite: bool = false, info: Dictionary = {}) -> void:
	hits.append({"amount": amount, "heavy": heavy, "info": info})
func is_staggered() -> bool:
	return staggered
"""

var _failures: Array[String] = []
var _checks := 0
var _dummy_script: GDScript


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("FAIL: ", label)


func _run() -> void:
	_dummy_script = GDScript.new()
	_dummy_script.source_code = DUMMY_SOURCE
	_dummy_script.reload()
	await _test_sprint()
	await _test_sprint_exhaustion_and_rules()
	await _test_backstep()
	await _test_jump_on_floor()
	await _test_jump_attacks()
	await _test_steed_summon_rules()
	await _test_steed_movement()
	await _test_steed_jump_and_dash()
	await _test_steed_attacks_and_lock()
	await _test_steed_dismount()
	await _test_hit_reactions()
	await _test_camera_modes()
	await _test_animation_layer()
	_test_settings_controls()
	await create_timer(0.8, true, false, true).timeout
	Engine.time_scale = 1.0
	for action in ["dodge", "move_forward", "move_right", "guard", "jump"]:
		Input.action_release(action)
	_dummy_script = null
	if _failures.is_empty():
		print("PASSED: %d movement checks" % _checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d movement checks" % [_failures.size(), _checks])
		quit(1)


func _make_player():
	var player = PlayerControllerScript.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3.ZERO
	player._camera_yaw = 0.0
	player.health = player.maximum_health
	player.stamina = 100.0
	return player


func _make_enemy(position: Vector3) -> CharacterBody3D:
	var enemy: CharacterBody3D = _dummy_script.new()
	enemy.add_to_group("tower_enemies")
	root.add_child(enemy)
	enemy.global_position = position
	return enemy


# A large static floor whose top is at y = 0.
func _make_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	root.add_child(body)
	return body


# Lets the physics server register the floor, then steps until grounded.
func _settle_on_floor(player) -> void:
	for attempt in range(30):
		await physics_frame
		player._physics_process(DT)
		if player.is_on_floor():
			return


# Visual effects (afterimages, trails) parented to the root; sounds are
# ignored because headless audio players may linger.
func _effect_count() -> int:
	var count := 0
	for child in root.get_children():
		if child is MeshInstance3D or (child is Node3D and not child.find_children("*", "MeshInstance3D", true, false).is_empty() and not child is CharacterBody3D):
			count += 1
	return count


func _horizontal_speed(player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _cleanup(nodes: Array) -> void:
	for action in ["dodge", "move_forward", "move_right", "guard", "jump"]:
		Input.action_release(action)
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	Engine.time_scale = 1.0


func _test_sprint() -> void:
	var player = _make_player()
	Input.action_press("move_forward")
	player._physics_process(DT)
	check(absf(_horizontal_speed(player) - 4.6) < 0.05, "jogging speed is 4.6 without sprint")
	Input.action_press("dodge")
	for frame in range(60):
		player._physics_process(DT)
	check(player.is_sprinting(), "holding dodge while moving sprints")
	check(absf(_horizontal_speed(player) - 4.6 * 1.5) < 0.05, "sprint is 1.5x speed (got %.2f)" % _horizontal_speed(player))
	check(absf(player.stamina - 88.0) < 0.5, "sprint drains about 12 stamina per second (got %.2f)" % player.stamina)
	var before: float = player.stamina
	player._regenerate_stamina(1.0)
	check(player.stamina == before, "no stamina regeneration while sprinting")
	# Locked on: smaller bonus.
	var enemy := _make_enemy(Vector3(0, 0, -20))
	player.toggle_lock_on()
	player._physics_process(DT)
	check(player.is_locked_on() and absf(_horizontal_speed(player) - 4.6 * 1.25) < 0.05, "locked-on sprint uses the reduced 1.25x bonus")
	player.release_lock()
	# Releasing the key ends the sprint; regeneration resumes after the delay.
	Input.action_release("dodge")
	player._physics_process(DT)
	check(not player.is_sprinting() and absf(_horizontal_speed(player) - 4.6) < 0.05, "releasing dodge stops sprinting")
	before = player.stamina
	for frame in range(60):
		player._physics_process(DT)
	check(player.stamina > before + 10.0, "stamina regenerates once the sprint ends")
	# Sprint widens the camera a little and returns.
	Input.action_press("dodge")
	player._physics_process(DT)
	for frame in range(90):
		player._update_camera(DT)
	check(player._camera.fov > PlayerControllerScript.CAMERA_FOV + 3.0, "sprinting widens the view")
	await _cleanup([player, enemy])


func _test_sprint_exhaustion_and_rules() -> void:
	var player = _make_player()
	Input.action_press("move_forward")
	Input.action_press("dodge")
	player.stamina = 1.0
	for frame in range(10):
		player._physics_process(DT)
	check(player.stamina == 0.0 and not player.is_sprinting(), "sprint stops when stamina runs out")
	player.stamina = 50.0
	player._physics_process(DT)
	check(not player.is_sprinting(), "an exhausted sprint waits for the key to be released")
	Input.action_release("dodge")
	player._physics_process(DT)
	Input.action_press("dodge")
	player._physics_process(DT)
	check(player.is_sprinting(), "sprint resumes after releasing and pressing again")
	Input.action_press("guard")
	player._physics_process(DT)
	check(not player.is_sprinting(), "no sprinting while guarding")
	Input.action_release("guard")
	# Standing still while holding dodge is not a sprint.
	Input.action_release("move_forward")
	player._physics_process(DT)
	check(not player.is_sprinting(), "holding dodge without moving does not sprint")
	# During a roll there is no sprint.
	Input.action_press("move_forward")
	player._start_dodge()
	player._physics_process(DT)
	check(not player.is_sprinting(), "no sprint during a roll")
	await _cleanup([player])


func _test_backstep() -> void:
	var player = _make_player()
	check(player._on_dodge_pressed(), "dodge without movement input starts a dodge")
	check(player.get_dodge_kind() == "backstep", "no movement input means a backstep")
	check(is_equal_approx(player.stamina, 90.0), "backstep costs 10 stamina")
	var first := -1.0
	var last := -1.0
	var elapsed := 0.0
	# Distance from velocity x DT: the reported physics delta can differ in a
	# headless script run, so positions are not used for distances.
	var moved := Vector3.ZERO
	while player.is_rolling() and elapsed < 2.0:
		player._physics_process(DT)
		moved += Vector3(player.velocity.x, 0, player.velocity.z) * DT
		elapsed += DT
		if player.is_invulnerable():
			if first < 0.0:
				first = elapsed
			last = elapsed
	check(absf(first - 0.04) <= DT + 0.001, "backstep i-frames begin at 0.04 s (got %.3f)" % first)
	check(absf(last - 0.20) <= DT + 0.001, "backstep i-frames end at 0.20 s (got %.3f)" % last)
	check(absf(elapsed - 0.35) <= DT + 0.001, "backstep lasts about 0.35 s (got %.3f)" % elapsed)
	check(absf(Vector2(moved.x, moved.z).length() - 1.3) < 0.2, "backstep covers about 1.3 m (got %.2f)" % Vector2(moved.x, moved.z).length())
	check(moved.z > 0.9, "backstep moves away from the facing direction")
	check(absf(wrapf(player._rig.rotation.y, -PI, PI)) < 0.2, "the hero keeps facing forward during a backstep")
	# Perfect dodge works on a backstep too.
	var attacker := Node3D.new()
	root.add_child(attacker)
	attacker.global_position = Vector3(0, 0, -2)
	var perfect := [0]
	player.perfect_dodge.connect(func(): perfect[0] += 1)
	player._on_dodge_pressed()
	player._roll_elapsed = 0.1
	var full: float = player.health
	player.receive_enemy_attack(30.0, attacker)
	check(player.health == full and perfect[0] == 1 and player.focus == 1, "an early backstep evasion is a perfect dodge")
	await create_timer(0.6, true, false, true).timeout
	# With movement input, it is still a roll.
	player._roll_elapsed = -1.0
	player.stamina = 100.0
	Input.action_press("move_right")
	player._on_dodge_pressed()
	check(player.get_dodge_kind() == "roll" and is_equal_approx(player.stamina, 82.0), "dodge with movement input is still an 18-stamina roll")
	player._roll_elapsed = -1.0
	player.stamina = 9.0
	Input.action_release("move_right")
	check(not player._on_dodge_pressed(), "backstep needs 10 stamina")
	await _cleanup([player, attacker])


func _test_jump_on_floor() -> void:
	var ground := _make_floor()
	var player = _make_player()
	player.global_position = Vector3(0, 0.05, 0)
	await _settle_on_floor(player)
	check(player.is_on_floor(), "the player stands on the test floor")
	check(player._try_jump(), "jump works on the floor")
	check(is_equal_approx(player.velocity.y, 7.0), "jump keeps its 7 m/s launch")
	var airborne_high := 0.0
	var peak := 0.0
	var frames := 0
	while frames < 120:
		player._physics_process(DT)
		frames += 1
		peak = maxf(peak, player.global_position.y)
		if player.global_position.y > 0.55:
			airborne_high += DT
		if player.is_on_floor() and frames > 3:
			break
	check(peak > 1.0 and peak < 1.25, "jump apex stays about 1.1 m (got %.2f)" % peak)
	check(airborne_high > 0.3, "the hero spends %.2f s above low-sweep height" % airborne_high)
	check(player.is_on_floor() and not player.is_airborne_from_jump(), "the jump ends on landing")
	await _cleanup([player, ground])


func _test_jump_attacks() -> void:
	var ground := _make_floor()
	var player = _make_player()
	var enemy := _make_enemy(Vector3(1.5, 0, 1.0))
	player.global_position = Vector3(0, 0.05, 0)
	await _settle_on_floor(player)
	player._try_jump()
	for frame in range(10):
		player._physics_process(DT)
	check(player.is_airborne_from_jump(), "the hero is airborne after jumping")
	check(player._attack(false) == 0 and player.is_plunging(), "a light attack in the air starts a plunge")
	check(is_equal_approx(player.stamina, 88.0), "a light jump attack costs 12 stamina")
	check(player.velocity.y <= -PlayerControllerScript.PLUNGE_FALL_SPEED + 0.01, "the plunge drives the hero down")
	var frames := 0
	while player.is_plunging() and frames < 120:
		player._physics_process(DT)
		frames += 1
	check(not player.is_plunging() and enemy.hits.size() == 1, "the plunge lands and hits a nearby enemy (even behind)")
	if enemy.hits.size() == 1:
		check(is_equal_approx(enemy.hits[0]["amount"], player.attack_power * 1.4), "light jump attack deals x1.4 damage")
		check(is_equal_approx(float(enemy.hits[0]["info"]["posture"]), 16.0), "light jump attack deals 6 + 10 posture")
		check(enemy.hits[0]["info"].get("jump_attack", false) == true, "the hit is flagged as a jump attack")
	check(player._attack_cooldown > 0.0, "landing a jump attack has recovery")
	# Heavy plunge (driven directly) and criticals on staggered targets.
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	player._jump_airborne = true
	player._attack(true)
	check(player.is_plunging() and is_equal_approx(player.stamina, 74.0), "a heavy jump attack costs 26 stamina")
	check(player._land_jump_attack() == 1, "the heavy plunge connects")
	check(is_equal_approx(enemy.hits[-1]["amount"], player.attack_power * 1.75 * 1.4), "heavy jump attack deals 1.75 x 1.4")
	check(is_equal_approx(float(enemy.hits[-1]["info"]["posture"]), 22.0), "heavy jump attack deals 12 + 10 posture")
	enemy.staggered = true
	player._attack_cooldown = 0.0
	player._jump_airborne = true
	player._attack(true)
	player._land_jump_attack()
	check(enemy.hits[-1]["info"].get("critical", false) == true, "a heavy plunge on a staggered enemy is a critical")
	# Out of the shockwave radius nothing is hit.
	enemy.global_position = Vector3(0, 0, 4.0)
	var count: int = enemy.hits.size()
	player._attack_cooldown = 0.0
	player._jump_airborne = true
	player._attack(false)
	player._land_jump_attack()
	check(enemy.hits.size() == count, "a light plunge does not reach 4 m")
	# On the ground attacks are unchanged.
	player._attack_cooldown = 0.0
	enemy.global_position = Vector3(0, 0, -1.5)
	enemy.staggered = false
	player._attack(false)
	check(is_equal_approx(enemy.hits[-1]["amount"], player.attack_power), "ground light attacks keep normal damage")
	await _cleanup([player, enemy, ground])


func _test_steed_summon_rules() -> void:
	var player = _make_player()
	check(player.summon_steed() and player.is_mounted(), "the steed can be summoned")
	check(is_instance_valid(player._steed), "a steed body appears")
	check(not player.is_crouching(), "no crouching while mounted")
	Input.action_press("guard")
	check(not player.is_guarding(), "no guarding while mounted")
	Input.action_release("guard")
	check(player.toggle_steed() and not player.is_mounted(), "the steed key dismisses it")
	check(player.steed_cooldown == 0.0 and player.summon_steed(), "a voluntary dismount has no cooldown")
	player.dismount()
	player.steed_allowed = false
	check(not player.summon_steed(), "floors can forbid the steed")
	player.steed_allowed = true
	await _cleanup([player])
	# Never in the hub.
	var hub_script := GDScript.new()
	hub_script.source_code = "extends Node3D\n"
	hub_script.reload()
	hub_script.resource_path = "res://scripts/hub/TestHub.gd"
	var hub := Node3D.new()
	hub.set_script(hub_script)
	root.add_child(hub)
	var hub_player = PlayerControllerScript.new()
	hub.add_child(hub_player)
	hub_player.set_physics_process(false)
	hub_player.set_process(false)
	check(not hub_player.summon_steed(), "the steed cannot be summoned in the hub")
	await _cleanup([hub])


func _test_steed_movement() -> void:
	var player = _make_player()
	player.summon_steed()
	Input.action_press("move_forward")
	for frame in range(12):
		player._physics_process(DT)
	check(player.get_steed_speed() < 4.0, "the steed builds speed gradually (inertia)")
	for frame in range(120):
		player._physics_process(DT)
	check(absf(player.get_steed_speed() - 12.0) < 0.1, "the steed reaches 12 m/s (got %.2f)" % player.get_steed_speed())
	check(absf(_horizontal_speed(player) - 12.0) < 0.1, "mounted movement uses the steed speed")
	# Turning at full gallop is limited.
	Input.action_release("move_forward")
	Input.action_press("move_right")
	var before: Vector3 = player.get_steed_heading()
	for frame in range(6):
		player._physics_process(DT)
	var turned := before.angle_to(player.get_steed_heading())
	check(turned > 0.1 and turned < 0.45, "a galloping steed turns gradually (%.2f rad in 0.1 s)" % turned)
	Input.action_release("move_right")
	for frame in range(90):
		player._physics_process(DT)
	check(player.get_steed_speed() < 0.5, "the steed slows to a stop without input")
	# Camera pulls back while riding.
	for frame in range(120):
		player._update_camera(DT)
	check(player._spring_arm.spring_length > 6.5, "the camera pulls back while mounted")
	player.dismount()
	for frame in range(180):
		player._update_camera(DT)
	check(absf(player._spring_arm.spring_length - player.base_arm_length()) < 0.1, "the camera returns after dismounting")
	await _cleanup([player])


func _test_steed_jump_and_dash() -> void:
	var ground := _make_floor()
	var player = _make_player()
	player.global_position = Vector3(0, 0.05, 0)
	await _settle_on_floor(player)
	player.summon_steed()
	check(player._try_jump() and is_equal_approx(player.velocity.y, 8.0), "the steed jumps higher (8 m/s)")
	for frame in range(15):
		player._physics_process(DT)
	check(not player.is_on_floor(), "the steed is airborne")
	check(player._try_jump() and is_equal_approx(player.velocity.y, 7.5), "the steed double jumps in mid-air")
	check(not player._try_jump(), "only one jump in mid-air")
	var frames := 0
	while not player.is_on_floor() and frames < 200:
		player._physics_process(DT)
		frames += 1
	check(player.is_on_floor() and player._air_jumps_used == 0, "landing restores the double jump")
	# Dodge on the steed: a sidestep dash, not a roll.
	player.stamina = 100.0
	player._steed_speed = 0.0
	check(player._on_dodge_pressed() and player.get_dodge_kind() == "steed_dash", "dodge while mounted is a sidestep dash")
	check(is_equal_approx(player.stamina, 88.0), "the sidestep dash costs 12 stamina")
	player._roll_elapsed = 0.1
	check(player.is_invulnerable(), "the dash has brief i-frames")
	player._roll_elapsed = 0.0
	var moved := Vector3.ZERO
	while player.is_rolling() and frames < 400:
		player._physics_process(DT)
		moved += Vector3(player.velocity.x, 0, player.velocity.z) * DT
		frames += 1
	check(moved.x > 2.3 and absf(moved.z) < 0.5, "the dash sidesteps to the right by about 2.8 m (got %.2f)" % moved.x)
	check(player.is_mounted(), "the dash keeps the rider mounted")
	await _cleanup([player, ground])


func _test_steed_attacks_and_lock() -> void:
	var player = _make_player()
	var left := _make_enemy(Vector3(-2.5, 0, 0))
	var right := _make_enemy(Vector3(2.5, 0, 0))
	player.summon_steed()
	player._steed_heading = Vector3(0, 0, -1)
	player._camera_yaw = PI / 2.0  # camera looks to -X (left)
	check(player._attack(false) == 1 and left.hits.size() == 1 and right.hits.is_empty(), "mounted swing hits the side the camera faces (left)")
	player._attack_cooldown = 0.0
	player._camera_yaw = -PI / 2.0
	check(player._attack(true) == 1 and right.hits.size() == 1, "mounted heavy hits the right when the camera looks right")
	check(is_equal_approx(right.hits[0]["amount"], player.attack_power * 1.75), "mounted heavy keeps heavy damage")
	# Lock-on still works mounted and aims the swing.
	player._attack_cooldown = 0.0
	player._camera_yaw = 0.0
	right.global_position = Vector3(0, 0, -3)
	player.toggle_lock_on()
	check(player.get_lock_target() == right, "lock-on works while mounted")
	player._attack(false)
	check(right.hits.size() == 2, "a locked-on mounted swing hits the target")
	# No jump attacks from the saddle: an airborne mounted swing is immediate.
	player._attack_cooldown = 0.0
	player._jump_airborne = true
	player._attack(false)
	check(not player.is_plunging() and right.hits.size() == 3, "mounted attacks in the air swing at once")
	await _cleanup([player, left, right])


func _test_steed_dismount() -> void:
	var player = _make_player()
	var attacker := Node3D.new()
	root.add_child(attacker)
	attacker.global_position = Vector3(0, 0, -2)
	player.summon_steed()
	player.receive_enemy_attack(5.0, attacker)
	check(player.is_mounted(), "a light hit does not dismount")
	player.receive_enemy_attack(10.0, attacker, {"heavy": true})
	check(not player.is_mounted(), "a heavy hit throws the rider off")
	check(player.is_stunned(), "being thrown staggers the rider")
	check(is_equal_approx(player.steed_cooldown, 10.0), "the steed cannot return for 10 s")
	check(not player.summon_steed(), "no resummon during the cooldown")
	check(player.get_interaction_prompt().contains("steed"), "the prompt explains the steed cooldown")
	check(player._attack(false) == 0 and not player._on_dodge_pressed(), "no attacks or dodges while staggered")
	for frame in range(40):
		player._physics_process(DT)
	check(not player.is_stunned(), "the stagger is short")
	for frame in range(600):
		player._physics_process(DT)
	check(player.steed_cooldown == 0.0 and player.summon_steed(), "the steed returns after the cooldown")
	# A big share of maximum health also dismounts.
	player.receive_enemy_attack(player.maximum_health * 0.2, attacker)
	check(not player.is_mounted(), "a hit of 20% maximum health throws the rider")
	player.steed_cooldown = 0.0
	player._stagger_time = 0.0
	player.summon_steed()
	player.receive_enemy_attack(5.0, attacker, {"knockback": Vector3(7, 0, 0)})
	check(not player.is_mounted(), "a strong knockback throws the rider")
	# Evaded hits never dismount.
	player.steed_cooldown = 0.0
	player._stagger_time = 0.0
	player.summon_steed()
	player.stamina = 100.0
	player._on_dodge_pressed()
	player._roll_elapsed = 0.1
	player.receive_enemy_attack(80.0, attacker, {"heavy": true})
	check(player.is_mounted(), "a hit evaded by the dash does not dismount")
	await _cleanup([player, attacker])


func _test_settings_controls() -> void:
	var labels: Array = []
	for row in SettingsScreenScript.CONTROLS:
		labels.append(String(row[0]))
	for wanted in ["Sprint", "Backstep", "Jump attack (plunging strike)", "Spectral steed (summon / dismiss)",
			"Steed: double jump", "Steed: sidestep dash"]:
		check(wanted in labels, "Settings lists '%s'" % wanted)
	check(InputMap.has_action("steed"), "the steed input action is registered")


func _test_hit_reactions() -> void:
	var player = _make_player()
	var attacker := Node3D.new()
	root.add_child(attacker)
	attacker.global_position = Vector3(0, 0, -2)
	player.receive_enemy_attack(8.0, attacker)
	check(not player.is_stunned(), "a small hit does not stagger")
	check(player._rig._animations.current_animation == "RecieveHit", "a hit plays the hit-react clip")
	check(player._rig._flash_left > 0.0, "a hit flashes the hero")
	player.receive_enemy_attack(12.0, attacker, {"heavy": true})
	check(player.is_stunned(), "a heavy boss hit staggers the hero")
	check(player._knockback.z > 3.0, "a heavy hit pushes the hero away from the attacker")
	check(player._attack(false) == 0, "no attacking during the big-hit stagger")
	player._stagger_time = 0.0
	player._knockback = Vector3.ZERO
	Input.action_press("guard")
	player.receive_enemy_attack(12.0, attacker, {"heavy": true})
	check(not player.is_stunned() and player._knockback == Vector3.ZERO, "a guarded heavy hit neither staggers nor pushes")
	Input.action_release("guard")
	player.receive_enemy_attack(player.maximum_health * 0.25, attacker)
	check(player.is_stunned(), "a hit of a quarter of maximum health staggers")
	# Perfect dodge leaves an afterimage; swings leave a trail.
	player._stagger_time = 0.0
	player.stamina = 100.0
	# Let effects from earlier tests finish first.
	await create_timer(1.0, true, false, true).timeout
	var before := _effect_count()
	player._start_dodge()
	player._roll_elapsed = 0.1
	player.receive_enemy_attack(10.0, attacker)
	check(_effect_count() > before, "a perfect dodge leaves an afterimage")
	# The perfect dodge's slow motion stretches the fade in real time.
	await create_timer(1.5, true, false, true).timeout
	check(_effect_count() == before, "the afterimage fades away")
	player._roll_elapsed = -1.0
	player._attack_cooldown = 0.0
	before = _effect_count()
	player._attack(false)
	check(_effect_count() == before + 1, "a swing leaves a weapon trail")
	await create_timer(0.4, true, false, true).timeout
	check(_effect_count() == before, "the trail fades quickly")
	await _cleanup([player, attacker])


func _test_camera_modes() -> void:
	var CameraSettings = load("res://scripts/player/CameraSettings.gd")
	check(CameraSettings.get_mode() == "close", "the close shoulder camera is the default")
	var player = _make_player()
	for frame in range(180):
		player._update_camera(DT)
	check(absf(player._spring_arm.spring_length - 3.5) < 0.05, "close camera sits 3.5 m back")
	check(absf(player._shoulder_arm.spring_length - 0.8) < 0.05, "close camera is offset 0.8 m over the right shoulder")
	for frame in range(3):
		await physics_frame
	var right: Vector3 = player._pivot.global_transform.basis.x
	var offset: Vector3 = player._camera.global_position - player._pivot.global_position
	check(offset.dot(right) > 0.6, "the camera sits to the right of the pivot")
	# Big boss lock-on: pulled back, higher and nearly centred.
	var boss := _make_enemy(Vector3(0, 0, -12))
	boss.set("size_scale", 4.5)
	boss.set_script(null)
	var big_script := GDScript.new()
	big_script.source_code = "extends CharacterBody3D\nvar health := 100.0\nfunc get_size_scale() -> float:\n\treturn 4.5\n"
	big_script.reload()
	boss.set_script(big_script)
	boss.add_to_group("tower_enemies")
	player.toggle_lock_on()
	for frame in range(180):
		player._update_camera(DT)
	check(player._spring_arm.spring_length > 8.0 and player._shoulder_arm.spring_length < 0.3, "big-boss lock-on frames wide and near centre")
	player.release_lock()
	CameraSettings.set_mode("classic")
	for frame in range(180):
		player._update_camera(DT)
	check(absf(player._spring_arm.spring_length - 5.2) < 0.05 and player._shoulder_arm.spring_length < 0.05, "classic camera is centred 5.2 m back")
	CameraSettings.set_mode("close")
	await _cleanup([player, boss])


func _test_animation_layer() -> void:
	var player = _make_player()
	var rig = player._rig
	Input.action_press("move_forward")
	for frame in range(20):
		player._physics_process(DT)
	check(rig._animations.current_animation == "Run", "jogging plays the run clip")
	check(absf(rig._animations.get_playing_speed() - 1.0) < 0.06, "jog plays the run clip at normal speed")
	for frame in range(15):
		await process_frame
	var position_before: float = rig._animations.current_animation_position
	Input.action_press("dodge")
	for frame in range(20):
		player._physics_process(DT)
		rig._process(DT)
	check(absf(rig._animations.get_playing_speed() - 1.5) < 0.06, "sprint speeds the run clip up 1.5x")
	check(position_before > 0.05 and rig._animations.current_animation_position >= position_before - 0.001, "changing pace does not restart the run clip")
	for frame in range(20):
		rig._process(DT)
	check(rig.get_lean() < -0.08, "sprinting leans the body forward")
	Input.action_release("dodge")
	Input.action_release("move_forward")
	rig.set_lean(0.0)
	rig.play_hit_react(1.0)
	for frame in range(3):
		rig._process(DT)
	check(rig.get_lean() > 0.03, "play_hit_react jolts the body back")
	check(rig.has_method("play_hit_react"), "ModelRig exposes play_hit_react for enemies and bosses")
	await _cleanup([player])
