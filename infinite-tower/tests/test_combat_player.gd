extends SceneTree

# Player-side combat checks: dodge roll, perfect dodge, Focus, charged heavy,
# unblockable attacks, stamina regeneration, lock-on and Immobilize.
# Run through tests/run_tests.sh (a disposable project copy). Godot's assert()
# does not stop a headless run, so checks are recorded and the exit code is
# non-zero on any failure.

const PlayerControllerScript = preload("res://scripts/player/PlayerController.gd")
const DT := 1.0 / 60.0

const DUMMY_SOURCE := """
extends CharacterBody3D
var health := 100.0
var maximum_health := 100.0
var hits: Array = []
var staggered := false
var immobilized := 0.0
var parried := 0
var size_scale := 1.0
func take_hit(amount: float, heavy: bool, ignite: bool = false, info: Dictionary = {}) -> void:
	hits.append({"amount": amount, "heavy": heavy, "ignite": ignite, "info": info})
func is_staggered() -> bool:
	return staggered
func apply_immobilize(seconds: float) -> void:
	immobilized = seconds
func on_parried() -> void:
	parried += 1
func get_size_scale() -> float:
	return size_scale
"""

# An enemy whose take_hit still has the old three-argument signature.
const LEGACY_SOURCE := """
extends CharacterBody3D
var health := 100.0
var hits := 0
func take_hit(amount: float, heavy: bool, ignite: bool = false) -> void:
	hits += 1
"""

var _failures: Array[String] = []
var _checks := 0
var _dummy_script: GDScript
var _legacy_script: GDScript


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
	_legacy_script = GDScript.new()
	_legacy_script.source_code = LEGACY_SOURCE
	_legacy_script.reload()
	await _test_roll_iframes()
	await _test_roll_rules()
	await _test_perfect_dodge()
	await _test_focus_and_light_chain()
	await _test_charged_heavy()
	await _test_critical_and_legacy_hits()
	await _test_unblockable_and_knockback()
	await _test_stamina_regeneration()
	await _test_lock_on()
	await _test_immobilize()
	await _test_hit_stop()
	# Let effect tweens and real-time timers finish before quitting.
	await create_timer(0.8, true, false, true).timeout
	Engine.time_scale = 1.0
	_dummy_script = null
	_legacy_script = null
	if _failures.is_empty():
		print("PASSED: %d combat checks" % _checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d combat checks" % [_failures.size(), _checks])
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


func _make_enemy(position: Vector3, legacy: bool = false) -> CharacterBody3D:
	var enemy: CharacterBody3D = (_legacy_script if legacy else _dummy_script).new()
	enemy.add_to_group("tower_enemies")
	root.add_child(enemy)
	enemy.global_position = position
	return enemy


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	Engine.time_scale = 1.0


func _test_roll_iframes() -> void:
	var player = _make_player()
	check(player._start_dodge(), "roll starts with full stamina")
	check(is_equal_approx(player.stamina, 100.0 - PlayerControllerScript.ROLL_STAMINA), "roll costs 18 stamina")
	check(not player.is_invulnerable(), "no i-frames at the very start of a roll")
	var first_invulnerable := -1.0
	var last_invulnerable := -1.0
	var elapsed := 0.0
	var start: Vector3 = player.global_position
	while player.is_rolling() and elapsed < 2.0:
		player._physics_process(DT)
		elapsed += DT
		if player.is_invulnerable():
			if first_invulnerable < 0.0:
				first_invulnerable = elapsed
			last_invulnerable = elapsed
	check(absf(first_invulnerable - 0.05) <= DT + 0.001, "i-frames begin at 0.05 s (got %.3f)" % first_invulnerable)
	check(absf(last_invulnerable - 0.40) <= DT + 0.001, "i-frames end at 0.40 s (got %.3f)" % last_invulnerable)
	check(absf(elapsed - 0.6) <= DT + 0.001, "roll lasts about 0.6 s (got %.3f)" % elapsed)
	var travelled := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	var roll_distance := PlayerControllerScript.ROLL_DISTANCE
	check(absf(travelled - roll_distance) < 0.35, "roll covers about %.1f m (got %.2f)" % [roll_distance, travelled])
	check(not player.is_invulnerable() and not player.is_rolling(), "roll ends cleanly")
	await _cleanup([player])


func _test_roll_rules() -> void:
	var player = _make_player()
	player.stamina = 10.0
	check(not player._start_dodge(), "roll needs 18 stamina")
	player.stamina = 100.0
	player._attack_cooldown_total = 0.62
	player._attack_cooldown = 0.5
	check(not player._start_dodge(), "early attack recovery cannot be rolled out of")
	player._attack_cooldown = 0.62 * 0.4
	check(player._start_dodge(), "the last 40% of attack recovery can be cancelled")
	check(player._attack_cooldown == 0.0, "rolling clears the attack recovery")
	check(not player._start_dodge(), "cannot roll again mid-roll")
	await _cleanup([player])


func _test_perfect_dodge() -> void:
	var player = _make_player()
	var attacker := Node3D.new()
	root.add_child(attacker)
	attacker.global_position = Vector3(0, 0, -2)
	var counts := {"perfect": 0, "focus": []}
	player.perfect_dodge.connect(func(): counts["perfect"] += 1)
	player.focus_changed.connect(func(value): counts["focus"].append(value))
	var full: float = player.health
	player._start_dodge()
	player._roll_elapsed = 0.12
	check(player.is_invulnerable(), "roll is invulnerable at 0.12 s")
	check(not player.receive_enemy_attack(30.0, attacker), "an evaded attack is not a parry")
	check(player.health == full, "an attack during i-frames deals no damage")
	check(counts["perfect"] == 1, "early evasion triggers a perfect dodge")
	check(player.focus == 1 and counts["focus"] == [1], "a perfect dodge grants 1 Focus")
	check(absf(Engine.time_scale - PlayerControllerScript.PERFECT_DODGE_TIME_SCALE) < 0.001, "perfect dodge slows time to 0.35")
	player.receive_enemy_attack(30.0, attacker)
	check(player.focus == 1 and counts["perfect"] == 1, "one perfect dodge per roll")
	await create_timer(0.6, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale is restored after the slow motion")
	# Late in the i-frames: evaded, but not perfect.
	player._roll_elapsed = -1.0
	player._start_dodge()
	player._roll_elapsed = 0.3
	player.take_damage(30.0)
	check(player.health == full, "take_damage also respects i-frames")
	check(counts["perfect"] == 1 and player.focus == 1, "late evasion is not a perfect dodge")
	# Before the i-frames begin the hit lands.
	player._roll_elapsed = -1.0
	player._start_dodge()
	player._roll_elapsed = 0.02
	player.receive_enemy_attack(30.0, attacker)
	check(player.health < full, "a hit before the i-frames lands")
	# Glassward still senses caches on any evaded hit. (The hit above was
	# big enough to stagger; clear it so the next roll can start.)
	player._stagger_time = 0.0
	player._equipped_effects = ["glassward"]
	player._roll_elapsed = -1.0
	player._start_dodge()
	player._roll_elapsed = 0.35
	player.receive_enemy_attack(30.0, attacker)
	check(player.is_sensing_caches(), "Glassward cache sense still triggers on evasion")
	await _cleanup([player, attacker])


func _test_focus_and_light_chain() -> void:
	var player = _make_player()
	var emitted: Array = []
	player.focus_changed.connect(func(value): emitted.append(value))
	player.add_focus(5)
	check(player.focus == 3, "Focus is capped at 3")
	player.add_focus(1)
	check(emitted == [3], "focus_changed fires only when the value changes")
	player.add_focus(-3)
	var enemy := _make_enemy(Vector3(0, 0, -1.5))
	for swing in range(3):
		player._attack_cooldown = 0.0
		player.stamina = 100.0
		check(player._attack(false) == 1, "light swing %d connects" % (swing + 1))
	check(player.focus == 1, "three connecting light hits earn 1 Focus")
	check(is_equal_approx(float(enemy.hits[0]["info"]["posture"]), PlayerControllerScript.LIGHT_POSTURE), "light hits deal 6 posture")
	check(enemy.hits[0]["info"]["charged"] == false, "light hits are not charged")
	# Two hits, then taking damage breaks the chain.
	for swing in range(2):
		player._attack_cooldown = 0.0
		player._attack(false)
	player.take_damage(10.0)
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	player._attack(false)
	check(player.focus == 1, "taking damage resets the light-hit chain")
	# A whiff also breaks the chain.
	player._light_chain = 2
	enemy.global_position = Vector3(0, 0, 10)
	player._attack_cooldown = 0.0
	check(player._attack(false) == 0, "a distant enemy is not hit")
	check(player._light_chain == 0, "a missed light attack breaks the chain")
	await _cleanup([player, enemy])


func _test_charged_heavy() -> void:
	var player = _make_player()
	var enemy := _make_enemy(Vector3(0, 0, -2))
	player.focus = 2
	check(player._release_heavy_attack(0.2) == 1, "a quick heavy press attacks")
	check(player.focus == 2, "a quick heavy press spends no Focus")
	var normal: Dictionary = enemy.hits[-1]
	check(is_equal_approx(normal["amount"], player.attack_power * 1.75), "normal heavy damage unchanged")
	check(is_equal_approx(float(normal["info"]["posture"]), PlayerControllerScript.HEAVY_POSTURE), "normal heavy deals 12 posture")
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	player._begin_heavy_charge()
	player._heavy_hold_time = 0.6
	check(player.is_charge_ready(), "holding heavy for 0.5 s with Focus readies a charge")
	check(player._release_heavy_attack(player._heavy_hold_time) == 1, "the charged heavy connects")
	check(player.focus == 0, "a charged heavy spends all Focus")
	var charged: Dictionary = enemy.hits[-1]
	check(charged["info"]["charged"] == true, "charged heavy is flagged as charged")
	check(is_equal_approx(charged["amount"], player.attack_power * 4.0), "2 Focus: damage is attack x (2 + 2)")
	check(is_equal_approx(float(charged["info"]["posture"]), 65.0), "2 Focus: posture is 25 + 40")
	check(not player._heavy_held and not player.is_charge_ready(), "releasing ends the charge")
	# Longer reach on the charged heavy.
	enemy.global_position = Vector3(0, 0, -4.4)
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	check(player._release_heavy_attack(0.1) == 0, "a normal heavy cannot reach 4.4 m")
	player.focus = 3
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	check(player._release_heavy_attack(0.8) == 1, "a charged heavy reaches 4.4 m")
	check(is_equal_approx(enemy.hits[-1]["amount"], player.attack_power * 5.0), "3 Focus: damage is attack x 5")
	# A long hold with no Focus is just a normal heavy.
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	enemy.global_position = Vector3(0, 0, -2)
	player._release_heavy_attack(1.0)
	check(enemy.hits[-1]["info"]["charged"] == false, "holding without Focus gives a normal heavy")
	await _cleanup([player, enemy])


func _test_critical_and_legacy_hits() -> void:
	var player = _make_player()
	var enemy := _make_enemy(Vector3(0, 0, -2))
	enemy.staggered = true
	player._attack(false)
	check(not enemy.hits[-1]["info"].has("critical"), "light hits on a staggered enemy are not criticals")
	player._attack_cooldown = 0.0
	player._attack(true)
	check(enemy.hits[-1]["info"].get("critical", false) == true, "a heavy on a staggered enemy is a critical")
	check(is_equal_approx(enemy.hits[-1]["amount"], player.attack_power * 1.75 * 2.5), "criticals deal x2.5 damage")
	enemy.free()
	await process_frame
	var legacy := _make_enemy(Vector3(0, 0, -2), true)
	player._attack_cooldown = 0.0
	player.stamina = 100.0
	player._attack(true)
	check(legacy.hits == 1, "enemies with the old take_hit signature are still hit")
	await _cleanup([player, legacy])


func _test_unblockable_and_knockback() -> void:
	var player = _make_player()
	var attacker := _make_enemy(Vector3(0, 0, -1.5))
	attacker.remove_from_group("tower_enemies")
	Input.action_press("guard")
	check(player.is_guarding(), "guard is up for the unblockable test")
	var before: float = player.health
	player.receive_enemy_attack(40.0, attacker)
	var guarded_loss: float = before - player.health
	check(guarded_loss < 20.0, "a normal hit is reduced by guard")
	before = player.health
	var stamina_before: float = player.stamina
	player.receive_enemy_attack(40.0, attacker, {"unblockable": true})
	check(before - player.health > 30.0, "an unblockable hit ignores guard")
	check(player.stamina == stamina_before, "an unblockable hit costs no block stamina")
	Input.action_release("guard")
	player._parry_window = 0.24
	before = player.health
	check(not player.receive_enemy_attack(30.0, attacker, {"unblockable": true}), "an unblockable hit cannot be parried")
	check(player.health < before and attacker.parried == 0, "the unblockable hit lands through the parry window")
	player._parry_window = 0.24
	check(not player.receive_enemy_attack(30.0, attacker, {"parryable": false}), "parryable=false cannot be parried")
	player._parry_window = 0.24
	check(player.receive_enemy_attack(30.0, attacker, {"parryable": true}), "a parryable frontal hit is parried")
	check(attacker.parried == 1, "on_parried is called on a parry")
	await create_timer(0.3, true, false, true).timeout
	player.receive_enemy_attack(10.0, attacker, {"knockback": Vector3(6, 0, 0)})
	check(is_equal_approx(player._knockback.x, 6.0), "knockback pushes the player")
	player._knockback = Vector3.ZERO
	player._stagger_time = 0.0
	player._start_dodge()
	player._roll_elapsed = 0.3
	player.receive_enemy_attack(10.0, attacker, {"knockback": Vector3(6, 0, 0)})
	check(player._knockback == Vector3.ZERO, "no knockback during i-frames")
	await _cleanup([player, attacker])


func _test_stamina_regeneration() -> void:
	var player = _make_player()
	player.stamina = 60.0
	player._spend_stamina(10.0)
	for frame in range(30):
		player._regenerate_stamina(DT)
	check(is_equal_approx(player.stamina, 50.0), "no stamina regeneration within 0.6 s of spending")
	for frame in range(6):
		player._regenerate_stamina(DT)
	for frame in range(15):
		player._regenerate_stamina(DT)
	check(absf(player.stamina - 60.0) < 1.0, "stamina then regenerates at 40 per second (got %.2f)" % player.stamina)
	Input.action_press("guard")
	var guarded: float = player.stamina
	player._stamina_regen_delay = 0.0
	player._regenerate_stamina(0.5)
	check(player.stamina == guarded, "no stamina regeneration while guarding")
	Input.action_release("guard")
	for frame in range(120):
		player._regenerate_stamina(DT)
	check(player.stamina == 100.0, "stamina caps at 100")
	await _cleanup([player])


func _test_lock_on() -> void:
	var player = _make_player()
	var front := _make_enemy(Vector3(0, 0, -10))
	var front_far := _make_enemy(Vector3(-3, 0, -20))
	var behind := _make_enemy(Vector3(-1, 0, 5))
	var right := _make_enemy(Vector3(8, 0, -8))
	var dead := _make_enemy(Vector3(0, 0, -4))
	dead.health = 0.0
	var distant := _make_enemy(Vector3(0, 0, -45))
	var outsider := Node3D.new()
	root.add_child(outsider)
	outsider.global_position = Vector3(0, 0, -2)
	player.toggle_lock_on()
	check(player.get_lock_target() == front, "lock-on picks the nearest living enemy in front")
	player.cycle_lock_target(1)
	check(player.get_lock_target() == right, "wheel switches to the next target to the right")
	player.cycle_lock_target(-1)
	check(player.get_lock_target() == front, "wheel switches back to the left")
	player.cycle_lock_target(-1)
	check(player.get_lock_target() == front_far, "switching never picks dead or distant enemies")
	player.toggle_lock_on()
	check(not player.is_locked_on(), "toggling again releases the lock")
	player.toggle_lock_on()
	front.health = 0.0
	player._update_lock_target()
	check(not player.is_locked_on(), "lock releases when the target dies")
	front.health = 100.0
	player.toggle_lock_on()
	check(player.get_lock_target() == front, "lock reacquired")
	front.global_position = Vector3(0, 0, -40)
	player._update_lock_target()
	check(not player.is_locked_on(), "lock releases when the target leaves range")
	# Only enemies behind: nothing to lock onto.
	for node in [front, front_far, right]:
		node.remove_from_group("tower_enemies")
	player.toggle_lock_on()
	check(not player.is_locked_on(), "enemies behind the camera are not locked")
	# Camera follows the target; big targets pull it back and widen the view.
	right.add_to_group("tower_enemies")
	right.size_scale = 4.5
	player.toggle_lock_on()
	check(player.get_lock_target() == right, "lock onto the big target")
	for frame in range(120):
		player._update_camera(DT)
	var expected_yaw := atan2(-8.0, 8.0)
	check(absf(wrapf(player._camera_yaw - expected_yaw, -PI, PI)) < 0.15, "camera yaw turns to face the target")
	check(player._spring_arm.spring_length > 8.0, "the camera pulls back for a big target")
	check(player._camera.fov > 75.0, "the view widens for a big target")
	player._update_lock_marker()
	check(player._lock_marker.visible, "a lock-on marker is shown on the target")
	player.release_lock()
	for frame in range(180):
		player._update_camera(DT)
	player._update_lock_marker()
	check(absf(player._spring_arm.spring_length - player.base_arm_length()) < 0.1, "the camera returns after the lock ends")
	check(not player._lock_marker.visible, "the marker hides without a target")
	await _cleanup([player, front, front_far, behind, right, dead, distant, outsider])


func _test_immobilize() -> void:
	var player = _make_player()
	check(not player.cast_immobilize(), "Immobilize needs a target")
	check(player.immobilize_cooldown == 0.0, "a failed cast starts no cooldown")
	var enemy := _make_enemy(Vector3(1, 0, -8))
	check(player.cast_immobilize(), "Immobilize hits the nearest enemy in front within 12 m")
	check(is_equal_approx(enemy.immobilized, 2.5), "apply_immobilize receives 2.5 s")
	check(is_equal_approx(player.immobilize_cooldown, 45.0), "Immobilize has a 45 s cooldown")
	enemy.immobilized = 0.0
	check(not player.cast_immobilize() and enemy.immobilized == 0.0, "Immobilize cannot be recast on cooldown")
	player.immobilize_cooldown = 0.0
	enemy.global_position = Vector3(0, 0, -20)
	check(not player.cast_immobilize(), "unlocked Immobilize is limited to 12 m")
	player.toggle_lock_on()
	check(player.cast_immobilize() and is_equal_approx(enemy.immobilized, 2.5), "Immobilize reaches the lock target")
	await _cleanup([player, enemy])


func _test_hit_stop() -> void:
	var player = _make_player()
	player.hit_stop(0.08)
	check(Engine.time_scale < 0.2, "hit-stop dips the time scale")
	await create_timer(0.2, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop restores the time scale")
	# A short hit-stop inside a longer slow motion keeps the slow motion.
	PlayerControllerScript.apply_time_scale(0.35, 0.5)
	player.hit_stop(0.05)
	await create_timer(0.15, true, false, true).timeout
	check(absf(Engine.time_scale - 0.35) < 0.001, "slow motion survives a shorter hit-stop")
	await create_timer(0.5, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "all slow-downs end")
	player.camera_shake(0.8)
	check(player._shake_strength > 0.7, "camera_shake sets a shake strength")
	for frame in range(60):
		player._update_camera(DT)
	check(player._shake_strength == 0.0 and player._camera.h_offset == 0.0, "camera shake decays to rest")
	await _cleanup([player])
