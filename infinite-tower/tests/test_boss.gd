extends SceneTree

# Boss-combat tests (docs/BOSS_SYSTEM.md): attack shapes, posture/stagger/
# critical, phase two, immobilize, moveset data for all ten bosses, combos,
# summons. Run through tests/run_tests.sh (disposable project copy). Godot's
# assert() does not stop a headless run, so checks are counted explicitly
# and the exit code reports failures.

const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const BossBrain = preload("res://scripts/battle/BossBrain.gd")
const DT := 1.0 / 60.0
# Index 10 is Vharzul, the floor-20 dragon (tests/test_special_floors.gd).
const DESIGN_SIZES := [4.5, 3.0, 1.3, 4.0, 1.1, 5.0, 1.2, 2.0, 1.5, 4.0, 5.0]

# EnemyAgent uses the PlayerData autoload, which a preload would compile
# before autoloads exist, so it is loaded at run time.
var EnemyScript: GDScript
var _failures: Array[String] = []
var _checks := 0


# Stands in for PlayerController: records every attack it receives.
class FakePlayer extends CharacterBody3D:
	var health := 1000.0
	var maximum_health := 1000.0
	var hits: Array = []
	var invulnerable := false
	var shakes := 0

	func receive_enemy_attack(amount: float, source: Node, info: Dictionary = {}) -> bool:
		hits.append({"amount": amount, "source": source, "info": info, "dodged": invulnerable})
		return false

	func is_invulnerable() -> bool:
		return invulnerable

	func camera_shake(_strength: float) -> void:
		shakes += 1

	func has_equipped_effect(_id: String) -> bool:
		return false

	func is_crouching() -> bool:
		return false

	func is_guarding() -> bool:
		return false

	func landed_hits() -> int:
		var count := 0
		for hit in hits:
			if not hit["dodged"]:
				count += 1
		return count


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("FAIL: ", label)


func _run() -> void:
	EnemyScript = load("res://scripts/battle/EnemyAgent.gd")
	_test_shapes()
	_test_moveset_data()
	await _test_boss_agent_basics()
	await _test_posture_stagger_critical()
	await _test_parries()
	await _test_phase_transition()
	await _test_immobilize()
	await _test_combo_and_feint()
	await _test_hits_and_dodges()
	await _test_ring_shockwave()
	await _test_move_choice()
	await _test_summons()
	await _test_regular_enemy_unchanged()
	if _failures.is_empty():
		print("ALL BOSS TESTS PASSED (%d checks)." % _checks)
		quit(0)
	else:
		printerr("%d of %d boss checks FAILED." % [_failures.size(), _checks])
		quit(1)


# --- Helpers -----------------------------------------------------------------

func _make_player(position: Vector3 = Vector3.ZERO) -> FakePlayer:
	var player := FakePlayer.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	player.add_child(shape)
	root.add_child(player)
	player.global_position = position
	return player


# A boss at the origin facing -Z, with its own physics turned off so the
# brain can be stepped deterministically.
func _make_boss(boss_index: int, player: FakePlayer) -> Node:
	var boss = EnemyScript.new()
	boss.configure_enemy(player, boss_index * 5 + 5, true, {"name": "Test boss %d" % boss_index})
	root.add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector3.ZERO
	boss.rotation = Vector3.ZERO
	return boss


func _step(boss, seconds: float) -> void:
	var steps := int(round(seconds / DT))
	for i in range(steps):
		if not is_instance_valid(boss) or boss._brain == null:
			return
		boss._brain.physics_step(DT, true)


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _exposure(boss) -> float:
	var journal: Dictionary = root.get_node("PlayerData").get_state()["investigation_journal"]
	return 1.2 if journal.has("boss_%d_clue_2" % boss.boss_index) else 1.0


# --- Shapes ------------------------------------------------------------------------

func _test_shapes() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, -1)
	var cone := {"type": "cone", "radius": 5.0, "angle": 90.0}
	check(BossMoves.shape_contains(cone, o, f, Vector3(0, 0, -4)), "cone: point ahead inside")
	check(BossMoves.shape_contains(cone, o, f, Vector3(2, 0, -3)), "cone: point within 45 degrees inside")
	check(not BossMoves.shape_contains(cone, o, f, Vector3(4, 0, -1)), "cone: point at 76 degrees outside")
	check(not BossMoves.shape_contains(cone, o, f, Vector3(0, 0, 4)), "cone: point behind outside")
	check(not BossMoves.shape_contains(cone, o, f, Vector3(0, 0, -5.5)), "cone: point beyond radius outside")
	check(BossMoves.shape_contains(cone, o, f, Vector3(0, 0, -5.2), 0.35), "cone: body radius reaches the rim")
	var turned := Vector3(1, 0, 0)
	check(BossMoves.shape_contains(cone, o, turned, Vector3(4, 0, 0)), "cone follows the forward direction")
	check(not BossMoves.shape_contains(cone, o, turned, Vector3(0, 0, -4)), "turned cone misses the old front")

	var circle := {"type": "circle", "radius": 2.0, "offset": 3.0}
	check(BossMoves.shape_contains(circle, o, f, Vector3(0, 0, -3)), "circle: centre (offset ahead) inside")
	check(BossMoves.shape_contains(circle, o, f, Vector3(1.5, 0, -3)), "circle: near edge inside")
	check(not BossMoves.shape_contains(circle, o, f, Vector3(0, 0, 0)), "circle: boss position outside offset circle")
	check(not BossMoves.shape_contains(circle, o, f, Vector3(0, 0, -5.6)), "circle: beyond far edge outside")

	var ring := {"type": "ring", "width": 1.0}
	check(BossMoves.shape_contains(ring, o, f, Vector3(6, 0, 0), 0.0, 6.0), "ring: on the wave front inside")
	check(BossMoves.shape_contains(ring, o, f, Vector3(0, 0, 6.4), 0.0, 6.0), "ring: inside the band width")
	check(not BossMoves.shape_contains(ring, o, f, Vector3(3, 0, 0), 0.0, 6.0), "ring: inside the hole is safe")
	check(not BossMoves.shape_contains(ring, o, f, Vector3(8, 0, 0), 0.0, 6.0), "ring: outside the front is safe")

	var line := {"type": "line", "length": 10.0, "width": 2.0}
	check(BossMoves.shape_contains(line, o, f, Vector3(0.5, 0, -9)), "line: point on the path inside")
	check(not BossMoves.shape_contains(line, o, f, Vector3(1.6, 0, -5)), "line: point to the side outside")
	check(not BossMoves.shape_contains(line, o, f, Vector3(0, 0, -11)), "line: point past the end outside")
	check(not BossMoves.shape_contains(line, o, f, Vector3(0, 0, 1)), "line: point behind outside")
	var centred := {"type": "line", "length": 10.0, "width": 2.0, "offset": -5.0}
	check(BossMoves.shape_contains(centred, o, f, Vector3(0, 0, 4)), "centred lane covers both directions")

	var box := {"type": "box", "length": 3.0, "width": 8.0}
	check(BossMoves.shape_contains(box, o, f, Vector3(3.5, 0, -2)), "box: wide sweep inside")
	check(not BossMoves.shape_contains(box, o, f, Vector3(0, 0, -4)), "box: beyond depth outside")
	check(not BossMoves.shape_contains(box, o, f, Vector3(4.5, 0, -1)), "box: beyond width outside")
	check(BossBrain.player_in_shape(box, o, f, Vector3(0, 0.2, -2), 0.0), "box: grounded player is swept")
	check(not BossBrain.player_in_shape(box, o, f, Vector3(0, 1.0, -2), 0.0), "box: jumping player clears a low sweep")
	check(BossBrain.player_in_shape(cone, o, f, Vector3(0, 1.0, -2), 0.0), "jumping does not clear a cone")


# --- Data ----------------------------------------------------------------------------

func _test_moveset_data() -> void:
	check(BossMoves.boss_count() == 11, "ten guardians plus Vharzul")
	for index in range(BossMoves.boss_count()):
		var size := BossMoves.boss_size(index)
		check(is_equal_approx(size, DESIGN_SIZES[index]), "boss %d has the design size %.1f" % [index, DESIGN_SIZES[index]])
		check(size >= 1.1 and size <= 5.0, "boss %d size within 1.1-5x" % index)
		var raw := BossMoves.raw_moves(index)
		var moves := BossMoves.scaled_moves(index)
		var openers_p1 := 0
		var phase_two := 0
		for id in moves:
			var m: Dictionary = moves[id]
			var label := "boss %d %s" % [index, id]
			var windup := float(m["windup"])
			var kind := String(m["kind"])
			if bool(m.get("followup", false)):
				check(windup >= BossMoves.FOLLOWUP_RANGE.x and windup <= BossMoves.FOLLOWUP_RANGE.y, label + ": follow-up gap 0.3-0.55 s")
			elif bool(m.get("delayed", false)):
				check(windup >= BossMoves.DELAYED_RANGE.x and windup <= BossMoves.DELAYED_RANGE.y, label + ": delayed wind-up in range")
				var hold := float(m.get("hold", 0.0))
				check(hold >= 0.5 and hold <= 1.5, label + ": delayed hold 0.5-1.5 s")
			elif kind in ["stance", "evade"]:
				check(windup >= BossMoves.UTILITY_RANGE.x and windup <= BossMoves.UTILITY_RANGE.y, label + ": utility wind-up in range")
			else:
				check(windup >= BossMoves.WINDUP_RANGE.x and windup <= BossMoves.WINDUP_RANGE.y, label + ": wind-up 0.6-1.5 s")
			check(BossMoves.windup_for(m, 2) >= windup * 0.88 - 0.0001, label + ": phase two at most 12% faster")
			check(float(m["track_until"]) <= windup, label + ": tracking stops by the end of the wind-up")
			var active := float(m["active"])
			check(active >= BossMoves.ACTIVE_RANGE.x and active <= BossMoves.ACTIVE_RANGE.y, label + ": active window in range")
			var recovery := float(m["recovery"])
			check(recovery >= 0.2 and recovery <= BossMoves.RECOVERY_RANGE.y, label + ": recovery in range")
			if not m.has("next") and kind in ["melee", "slam", "charge"]:
				check(recovery >= 0.7, label + ": a committal finisher leaves a punish window")
			if m.has("next"):
				check(moves.has(m["next"]), label + ": follow-up exists")
				if moves.has(m["next"]):
					check(bool(moves[m["next"]].get("followup", false)), label + ": follow-up is marked as such")
			if m.has("feint_into"):
				check(moves.has(m["feint_into"]), label + ": feint target exists")
			if m["color"] == "red":
				var info := _info_for(m)
				check(info["unblockable"] and not info["parryable"], label + ": red attacks are unparryable and unblockable")
			else:
				check(_info_for(m)["parryable"], label + ": non-red attacks are parryable")
			if m.has("shape") and not bool(m["shape"].get("fixed", false)) and kind != "charge" and raw[id].has("shape"):
				for key in ["radius", "length", "width"]:
					if raw[id]["shape"].has(key):
						check(is_equal_approx(float(m["shape"][key]), float(raw[id]["shape"][key]) * size), label + ": %s scales with size" % key)
			if int(m["phase"]) >= 2:
				phase_two += 1
			elif not bool(m.get("followup", false)) and kind != "stance":
				openers_p1 += 1
		check(openers_p1 >= 3, "boss %d has at least three phase-one openers" % index)
		check(phase_two >= 1, "boss %d unlocks phase-two moves" % index)
		check(_longest_combo(moves) <= 4, "boss %d combos have at most 4 hits" % index)
	# Signature content from the design table.
	check(_has_kind(0, "slam") and _has_ring(0) and _has_kind(0, "charge"), "Cinder Warden: burst with shockwave, charge")
	check(_has_color(1, "red") and _has_kind(1, "hazard"), "Mother of Briars: red vine grab and root snares")
	check(_combo_length(2, "royal_1") == 3 and BossMoves.scaled_moves(2)["royal_3"]["color"] == "yellow", "Brass Regent: three-strike combo with a yellow finisher")
	check(_has_color(3, "red") and _has_kind(3, "projectile") and int(BossMoves.scaled_moves(3)["double_pulse"]["ring"]["count"]) == 2, "Drowned Cantor: red cone, bolts, double pulse")
	check(BossMoves.scaled_moves(4)["pounce"]["next"] == "pounce_slam" and BossMoves.scaled_moves(4)["pounce_slam"]["color"] == "yellow", "Pale Huntress: pounce into a yellow slam")
	check(_has_kind(5, "charge") and _has_kind(5, "hazard") and BossMoves.scaled_moves(5).has("stomp"), "Maw Below: burrow, darkness, stomp")
	check(_count_color(6, "yellow") >= 4 and _combo_length(6, "knight_1") == 4, "Hollow Knight: many yellow attacks and a four-hit combo")
	check(BossMoves.scaled_moves(7)["beam"]["color"] == "red" and BossMoves.scaled_moves(7)["beam"]["shape"]["type"] == "line", "Sepulchre Twin: red beam line")
	check(_has_kind(8, "summon") and _has_kind(8, "hazard") and _has_kind(8, "charge"), "Red Marshal: banner, artillery, charge")
	var sovereign := BossMoves.scaled_moves(9)
	var stances := {}
	for id in sovereign:
		if sovereign[id].has("stance"):
			stances[sovereign[id]["stance"]] = true
	check(stances.size() >= 5 and sovereign.has("stance_shift"), "Starless Sovereign mixes five stances")
	check(is_equal_approx(float(sovereign["ember_arc"]["shape"]["radius"]), 1.6 * 4.0), "borrowed moves rescale to the Sovereign's size")


func _info_for(m: Dictionary) -> Dictionary:
	var red: bool = m["color"] == "red"
	return {"unblockable": red, "parryable": not red}


func _has_kind(index: int, kind: String) -> bool:
	for m in BossMoves.scaled_moves(index).values():
		if m["kind"] == kind:
			return true
	return false


func _has_color(index: int, color: String) -> bool:
	return _count_color(index, color) > 0


func _count_color(index: int, color: String) -> int:
	var count := 0
	for m in BossMoves.scaled_moves(index).values():
		if m["color"] == color:
			count += 1
	return count


func _has_ring(index: int) -> bool:
	for m in BossMoves.scaled_moves(index).values():
		if m.has("ring"):
			return true
	return false


func _combo_length(index: int, start: String) -> int:
	var moves := BossMoves.scaled_moves(index)
	var length := 1
	var id := start
	while moves[id].has("next") and length < 10:
		id = moves[id]["next"]
		length += 1
	return length


func _longest_combo(moves: Dictionary) -> int:
	var longest := 1
	for id in moves:
		var length := 1
		var current: String = id
		while moves[current].has("next") and length < 10:
			current = moves[current]["next"]
			length += 1
		longest = maxi(longest, length)
	return longest


# --- Agent ---------------------------------------------------------------------------

func _test_boss_agent_basics() -> void:
	var player := _make_player(Vector3(0, 0, 30))
	for index in [0, 4, 5]:
		var boss = _make_boss(index, player)
		check(boss.boss and boss._brain != null, "boss %d has a brain" % index)
		check(is_equal_approx(boss.get_size_scale(), DESIGN_SIZES[index]), "boss %d reports its size" % index)
		var lock_height: float = boss.get_lock_point().y - boss.global_position.y
		check(absf(lock_height - 1.8 * DESIGN_SIZES[index] * 0.6) < 0.01, "boss %d lock point at chest height" % index)
		check(boss.phase == 1 and boss.posture == 0.0 and boss.posture_max > 0.0, "boss %d starts in phase one with empty posture" % index)
		var capsule: CapsuleShape3D = null
		for child in boss.get_children():
			if child is CollisionShape3D:
				capsule = child.shape
		check(capsule != null and capsule.height >= 1.8 * DESIGN_SIZES[index] * 0.8, "boss %d collision scales with size" % index)
		await _cleanup([boss])
	var regular = EnemyScript.new()
	regular.configure_enemy(player, 3, false)
	root.add_child(regular)
	check(regular.get_size_scale() == 1.0 and regular.phase == 1 and not regular.is_staggered(), "regular enemies report size 1 and phase 1")
	check(absf(regular.get_lock_point().y - regular.global_position.y - 1.1) < 0.01, "regular lock point at chest height")
	await _cleanup([regular, player])


func _test_posture_stagger_critical() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(2, player)
	var brain = boss._brain
	boss.take_hit(1.0, true, false, {"posture": 40.0})
	check(is_equal_approx(boss.posture, 40.0), "posture fills from the hit's posture value")
	boss.take_hit(1.0, false)
	check(is_equal_approx(boss.posture, 40.0 + BossBrain.LIGHT_POSTURE), "three-argument light hits add default posture")
	_step(boss, 1.5)
	check(is_equal_approx(boss.posture, 46.0), "posture holds for 2 s without gain")
	_step(boss, 1.0)
	check(boss.posture < 46.0, "posture drains after 2 s without gain")
	boss.posture = boss.posture_max - 5.0
	check(not boss.is_staggered(), "not staggered before the bar is full")
	boss.take_hit(1.0, true, false, {"posture": 10.0})
	check(boss.is_staggered(), "a full posture bar staggers the boss")
	check(brain._stagger_duration == BossBrain.STAGGER_TIME, "posture stagger lasts 3 s")
	var exposure := _exposure(boss)
	var before: float = boss.health
	boss.take_hit(10.0, false, false, {"posture": 6.0})
	check(absf((before - boss.health) - 10.0 * BossBrain.STAGGER_DAMAGE * exposure) < 0.01, "staggered boss takes x1.5 damage")
	before = boss.health
	boss.take_hit(5.0, true, false, {"posture": 12.0, "critical": true})
	var crit: float = before - boss.health
	check(crit >= boss.maximum_health * 0.10 - 0.01, "a critical hit deals at least 10%% of max health (%.1f of %.1f)" % [crit, boss.maximum_health])
	check(crit <= boss.maximum_health * BossBrain.CRITICAL_MAX_FRACTION * exposure + 0.01, "a critical hit is capped")
	check(not boss.is_staggered(), "a critical spends the stagger window")
	_step(boss, 0.6)
	check(brain.state == BossBrain.State.IDLE and boss.posture == 0.0, "stagger ends and posture resets")
	# A full 3 s stagger without a critical.
	boss.posture = boss.posture_max
	brain.add_posture(1.0)
	boss.posture = boss.posture_max
	boss.take_hit(1.0, true, false, {"posture": 50.0})
	check(boss.is_staggered(), "posture break again")
	_step(boss, 2.9)
	check(boss.is_staggered(), "still staggered at 2.9 s")
	_step(boss, 0.2)
	check(not boss.is_staggered(), "stagger over after 3 s")
	await _cleanup([boss, player])


func _test_parries() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(2, player)
	var brain = boss._brain
	brain.start_move("royal_3")
	check(brain.move["color"] == "yellow", "royal finisher is yellow")
	boss.on_parried()
	check(boss.is_staggered() and is_equal_approx(brain._stagger_duration, BossBrain.PARRY_STAGGER_TIME), "parrying a yellow attack staggers 1.5 s")
	check(is_equal_approx(boss.posture, BossBrain.PARRY_POSTURE), "a parry adds 30 posture")
	_step(boss, 1.6)
	check(not boss.is_staggered(), "yellow parry stagger ends")
	brain.start_move("royal_1")
	boss.on_parried()
	check(brain.state == BossBrain.State.STAGGER and not boss.is_staggered(), "parrying a normal attack interrupts without a critical window")
	_step(boss, 0.7)
	check(brain.state == BossBrain.State.IDLE, "normal parry flinch is short")
	await _cleanup([boss, player])


func _test_phase_transition() -> void:
	var player := _make_player(Vector3(0, 0, -3))
	var boss = _make_boss(0, player)
	var brain = boss._brain
	var windup_one := BossMoves.windup_for(brain.moves["stomp"], 1)
	brain.start_move("ground_burst")
	_step(boss, 2.2)
	check(brain.ring_count() > 0, "ground burst spawns a shockwave ring")
	boss.take_hit(boss.maximum_health * 0.45, false)
	check(boss.phase == 1, "still phase one above 50%")
	boss.take_hit(boss.maximum_health * 0.9, false)
	check(boss.phase == 2, "phase two at 50% health")
	check(boss.health >= boss.maximum_health * 0.4 - 0.01, "a phase-one boss cannot skip its roar")
	check(boss.is_roaring() and boss.is_invulnerable(), "the roar makes the boss invulnerable")
	check(brain.ring_count() == 0, "the roar clears active shockwaves")
	var during: float = boss.health
	boss.take_hit(50.0, true, false, {"posture": 50.0})
	check(boss.health == during and boss.posture == 0.0, "no damage or posture during the roar")
	check(not boss.apply_immobilize(2.5), "cannot immobilize during the roar")
	var hits_before := player.hits.size()
	_step(boss, 2.4)
	check(boss.is_roaring(), "roar lasts 2.5 s")
	check(player.hits.size() == hits_before, "the roar never hurts the player")
	_step(boss, 0.2)
	check(not boss.is_roaring() and brain.state == BossBrain.State.IDLE, "the fight resumes after the roar")
	check(absf(BossMoves.windup_for(brain.moves["stomp"], brain.phase) - windup_one * 0.88) < 0.001, "phase-two wind-ups are 12% faster")
	var unlocked := false
	for id in brain.moves:
		if int(brain.moves[id]["phase"]) == 2 and brain.is_move_available(id, 3.0) or (id == "charge" and brain.is_move_available(id, 15.0)):
			unlocked = true
	check(unlocked, "phase-two moves become available")
	brain.start_move("stomp")
	check(absf(brain._windup - windup_one * 0.88) < 0.001, "the brain uses the faster wind-up")
	await _cleanup([boss, player])


func _test_immobilize() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(3, player)
	var brain = boss._brain
	brain.start_move("resonant_cone")
	_step(boss, 0.3)
	var frozen_time: float = brain.state_time
	check(boss.apply_immobilize(2.5), "immobilize lands on a boss")
	check(boss.is_immobilized(), "boss is immobilized")
	_step(boss, 1.4)
	check(boss.is_immobilized(), "boss frozen for 60% of 2.5 s (still at 1.4 s)")
	check(brain.state == BossBrain.State.WINDUP and is_equal_approx(brain.state_time, frozen_time), "wind-up timer is frozen")
	_step(boss, 0.15)
	check(not boss.is_immobilized(), "boss freed after 1.5 s")
	check(not boss.apply_immobilize(2.5), "20 s immunity after an immobilize")
	_step(boss, 19.0)
	check(not boss.apply_immobilize(2.5), "still immune at 19 s")
	_step(boss, 1.2)
	check(boss.apply_immobilize(2.5), "immobilize works again after the immunity")
	var regular = EnemyScript.new()
	regular.configure_enemy(player, 1, false)
	root.add_child(regular)
	check(regular.apply_immobilize(2.5) and is_equal_approx(regular._immobile_time, 2.5), "regular enemies take the full duration")
	check(regular.apply_immobilize(1.0), "regular enemies have no immunity")
	await _cleanup([boss, regular, player])


func _test_combo_and_feint() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(6, player)
	var brain = boss._brain
	brain.start_move("knight_1")
	_step(boss, 4.0)
	var log: Array = brain.combo_log.slice(brain.combo_log.size() - 4)
	check(brain.combo_log.size() >= 4 and log == ["knight_1", "knight_2", "knight_3", "knight_4"], "four-hit combo plays in order (%s)" % str(brain.combo_log))
	check(brain.last_move_id == "knight_1", "a combo counts as one move for repeat avoidance")
	# Follow-up gaps are short; the finisher leaves a punish window.
	brain.combo_log.clear()
	brain.start_move("knight_1")
	var w1 := BossMoves.windup_for(brain.moves["knight_1"], 1) + float(brain.moves["knight_1"]["active"])
	_step(boss, w1 + 0.05)
	check(brain.current_move_id() == "knight_2", "second hit follows straight after the first")
	_step(boss, 3.0)
	check(brain.state == BossBrain.State.IDLE or brain.state == BossBrain.State.RECOVERY, "combo ends in recovery")
	# Feint: the wind-up turns into the real delayed swing without hitting.
	brain.combo_log.clear()
	player.global_position = Vector3(0, 0, -1.5)
	player.hits.clear()
	brain.start_move("feint_swing")
	_step(boss, float(brain.moves["feint_swing"]["windup"]) * 0.6)
	check(brain.current_move_id() == "delayed_swing", "the feint turns into the delayed swing")
	check(player.hits.is_empty(), "a feint never hits")
	await _cleanup([boss, player])


func _test_hits_and_dodges() -> void:
	var player := _make_player(Vector3(0, 0, -2.0))
	var boss = _make_boss(6, player)
	var brain = boss._brain
	brain.start_move("shield_bash")
	_step(boss, 1.2)
	check(player.landed_hits() == 1, "shield bash hits once")
	if not player.hits.is_empty():
		var info: Dictionary = player.hits[0]["info"]
		check(info.get("unblockable", false) and not info.get("parryable", true), "red bash is sent as unblockable and unparryable")
		check(player.hits[0]["amount"] > boss.attack_power, "red bash hits hard")
		check(info.get("knockback", Vector3.ZERO).length() > 0.0, "hits carry knockback")
	_step(boss, 2.0)
	player.hits.clear()
	brain.start_move("delayed_swing")
	_step(boss, 2.0)
	check(player.landed_hits() == 1 and player.hits[0]["info"].get("parryable", false) and player.hits[0]["info"].get("yellow", false), "yellow swing is parryable")
	_step(boss, 2.0)
	# Dodging: the hit is offered once (perfect dodge) but not consumed.
	player.hits.clear()
	player.invulnerable = true
	brain.start_move("knight_4")
	_step(boss, BossMoves.windup_for(brain.moves["knight_4"], 1) + 0.05)
	check(player.hits.size() == 1 and player.hits[0]["dodged"], "a dodged hit is reported once")
	player.invulnerable = false
	_step(boss, 0.1)
	check(player.landed_hits() == 1, "i-frames ending inside the active window still get hit")
	# Out of reach: no hit.
	_step(boss, 2.0)
	player.hits.clear()
	player.global_position = Vector3(0, 0, -12)
	brain.start_move("knight_1")
	_step(boss, 1.0)
	check(player.hits.is_empty(), "attacks miss a player out of reach")
	await _cleanup([boss, player])


func _test_ring_shockwave() -> void:
	var player := _make_player(Vector3(0, 0, -10))
	var boss = _make_boss(3, player)
	var brain = boss._brain
	brain.start_move("water_pulse")
	var windup := BossMoves.windup_for(brain.moves["water_pulse"], 1)
	_step(boss, windup + 0.1)
	check(player.landed_hits() == 0, "the pulse has not reached 10 m yet")
	var start := BossMoves.shape_reach(brain.moves["water_pulse"]["shape"])
	var reach_time := (10.0 - start - 1.1) / float(brain.moves["water_pulse"]["ring"]["speed"])
	_step(boss, maxf(0.0, reach_time - 0.2))
	check(player.landed_hits() == 0, "still clear just before the wave arrives")
	_step(boss, 0.5)
	check(player.landed_hits() == 1, "the expanding ring hits once at 10 m")
	_step(boss, 3.0)
	check(brain.ring_count() == 0, "the ring is removed at its maximum radius")
	await _cleanup([boss, player])


func _test_move_choice() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(2, player)
	var brain = boss._brain
	var repeated := 0
	var chosen := {}
	for i in range(200):
		var id: String = brain.choose_move(3.0)
		chosen[id] = true
		if id == brain.last_move_id:
			repeated += 1
		brain.last_move_id = id
		check(not bool(brain.moves[id].get("followup", false)), "only openers are chosen (%s)" % id)
		check(int(brain.moves[id]["phase"]) == 1, "phase-two moves stay locked in phase one (%s)" % id)
	check(repeated == 0, "the same move is never chosen twice in a row")
	check(chosen.size() >= 2, "several moves are used at melee range")
	check(brain.choose_move(10.0) == "shield_charge", "far away the Regent charges")
	check(brain.choose_move(40.0) == "", "out of every range the boss approaches instead")
	await _cleanup([boss])
	# Sovereign: stance moves only, then a stance shift.
	var sovereign = _make_boss(9, player)
	brain = sovereign._brain
	for i in range(BossMoves.STANCE_LENGTH):
		var id: String = brain.choose_move(6.0)
		check(id != "" and brain.moves[id].get("stance", "") == brain.stance, "Sovereign uses its current stance (%s)" % id)
		brain.start_move(id)
		brain._enter_idle(0.0)
	check(brain.choose_move(6.0) == "stance_shift", "Sovereign shifts stance after three attacks")
	var old_stance: String = brain.stance
	brain.start_move("stance_shift")
	_step(sovereign, 1.3)
	check(brain.stance != old_stance and brain.stance in BossMoves.SOVEREIGN_PHASE_ONE, "the stance changes to another phase-one stance")
	await _cleanup([sovereign, player])


func _test_summons() -> void:
	var player := _make_player(Vector3(0, 0, 40))
	var boss = _make_boss(8, player)
	var brain = boss._brain
	var defeated := []
	boss.defeated.connect(func(enemy): defeated.append(enemy))
	brain.start_move("banner_call")
	_step(boss, 1.6)
	check(brain.minions_alive() == 2, "banner call summons two soldiers")
	var minions: Array = brain._minions.duplicate()
	for minion in minions:
		check(minion.get_script() == EnemyScript and not minion.boss and minion.summoned, "summons are regular, flagged enemies")
		check(minion.get_parent() == boss.get_parent(), "summons join the floor's world node")
	check(brain.choose_move(5.0) != "banner_call", "no second banner call while soldiers live")
	# Killing the boss (through its roar) frees the soldiers and emits one
	# defeat for the floor.
	boss.take_hit(boss.maximum_health, false)
	_step(boss, 2.6)
	boss.take_hit(boss.maximum_health, false)
	check(defeated.size() == 1 and defeated[0] == boss, "boss death is reported once")
	await process_frame
	var alive := 0
	for minion in minions:
		if is_instance_valid(minion):
			alive += 1
	check(alive == 0, "summoned soldiers are freed with the boss")
	await _cleanup([player])


func _test_regular_enemy_unchanged() -> void:
	var player := _make_player(Vector3(0, 0, -1.2))
	var regular = EnemyScript.new()
	regular.configure_enemy(player, 1, false)
	root.add_child(regular)
	regular.global_position = Vector3.ZERO
	check(regular._brain == null, "regular enemies have no boss brain")
	await physics_frame
	await physics_frame
	await physics_frame
	check(regular._winding_up and regular.telegraph_timer > 0.35 and regular.telegraph_timer <= 0.45, "regular wind-up is still 0.45 s (%.3f)" % regular.telegraph_timer)
	await _cleanup([regular, player])
