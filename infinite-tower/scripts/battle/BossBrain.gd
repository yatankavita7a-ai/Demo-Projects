extends RefCounted

# Boss behaviour (docs/BOSS_SYSTEM.md). Owned by a boss EnemyAgent, which
# calls physics_step() every physics frame and forwards hits, parries and
# immobilize to it. State machine:
#
#   IDLE (approach / circle)  -> choose a move: weighted, distance-aware,
#                                never the same opening move twice running
#   WINDUP   tracks the player until track_until, ground telegraph fills,
#            model anticipation and sound; yellow flash 0.3 s before a
#            parryable impact; delayed swings hold their pose; feints turn
#            into another move part-way
#   ACTIVE   hit test against the attack shape each frame (once per move);
#            lunges, charges along the locked line, slams spawn expanding
#            shockwave rings, projectiles, hazards, summons, stance shifts
#   RECOVERY punish window (longer when the weakness clue is known), or
#            straight into the next combo hit
#   STAGGER  posture broken (3 s, extra damage, critical hits) or parry
#   ROAR     phase-two transition at 50% health: 2.5 s, invulnerable,
#            harmless; unlocks phase-two moves, wind-ups x0.88
#
# Immobilize freezes everything here (timers included) for 60% of the
# requested time, followed by 20 s of immunity.
#
# Flying bosses (Vharzul): a "flight" move lifts the model and makes the
# boss untouchable; only "air" moves are used until AIR_ATTACKS have been
# made, then the "land" move glides over the player and slams down.
# chain_down() (the Chain Rite) pins the boss in a stagger without a
# critical window. windup_mult / damage_mult raise aggression.

const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const AttackIndicator = preload("res://scripts/battle/AttackIndicator.gd")
const BossProjectile = preload("res://scripts/battle/BossProjectile.gd")
const BossHazard = preload("res://scripts/battle/BossHazard.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const Vfx = preload("res://scripts/visual/Vfx.gd")

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, STAGGER, ROAR }

const STAGGER_TIME := 3.0
const PARRY_STAGGER_TIME := 1.5   # parrying a yellow attack
const PARRY_FLINCH_TIME := 0.6    # parrying a normal attack
const PARRY_POSTURE := 30.0
const LIGHT_POSTURE := 6.0        # used when a hit carries no posture info
const HEAVY_POSTURE := 12.0
const IRONWOOD_POSTURE := 10.0
const POSTURE_DRAIN_DELAY := 2.0
const POSTURE_DRAIN_RATE := 15.0
const STAGGER_DAMAGE := 1.5
const CRITICAL_MIN_FRACTION := 0.10
const CRITICAL_MAX_FRACTION := 0.20
const ROAR_TIME := 2.5
const PHASE_THRESHOLD := 0.5
const IMMOBILIZE_BOSS_FACTOR := 0.6
const IMMOBILIZE_IMMUNITY := 20.0
const YELLOW_FLASH := 0.3
const PLAYER_RADIUS := 0.35
const JUMP_CLEARANCE := 0.55      # low sweeps miss a player this far up
const LUNGE_TIME := 0.15
const WEAKNESS_RECOVERY := 1.25

const WINDUP_GLOW := Color(0.55, 0.2, 0.05)
const YELLOW_GLOW := Color(0.6, 0.5, 0.05)
const RED_GLOW := Color(0.6, 0.02, 0.02)
const STAGGER_GLOW := Color(0.35, 0.35, 0.4)
const FREEZE_GLOW := Color(0.15, 0.3, 0.6)
const ROAR_GLOW := Color(0.7, 0.08, 0.04)
const REST_GLOW := Color(0.22, 0.03, 0.05)

var agent   # owning EnemyAgent
var boss_index := 0
var size := 1.0
var moves: Dictionary = {}
var posture := 0.0
var posture_max := 100.0
var phase := 1
var state: int = State.IDLE
var state_time := 0.0
var move: Dictionary = {}
var last_move_id := ""
var combo_log: Array[String] = []   # every move started, in order (tests)
var stance := ""
var recovery_mult := 1.0
var turn_speed := TAU
var windup_mult := 1.0    # < 1 = faster wind-ups (Chain Rite aggression)
var damage_mult := 1.0
var airborne := false
var lift := 0.0           # metres the model is raised (flight)

var _idle_gap := 1.0
var _cooldowns := {}
var _windup := 1.0
var _track := 0.0
var _hit_landed := false
var _dodge_notified := false
var _forward := Vector3.FORWARD
var _indicator
var _effects: Array = []    # expanding shockwave rings
var _spawned: Array = []    # hazards and projectiles
var _minions: Array = []
var _stagger_duration := 0.0
var _crit_window := false
var _posture_idle := 0.0
var _immobile_left := 0.0
var _immobile_immunity := 0.0
var _stance_count := 0
var _anim_held := false
var _flash_done := false
var _rng := RandomNumberGenerator.new()
var _clock := 0.0   # boss-local seconds (pauses with the game and immobilize)
var _air_count := 0
var _chained := false
var _ground_layer := 1
var _sweep_yaw := 0.0
var _flame


func _init(owner_agent, index: int) -> void:
	agent = owner_agent
	boss_index = clampi(index, 0, BossMoves.boss_count() - 1)
	var stats := BossMoves.boss_stats(boss_index)
	size = float(stats["size"])
	posture_max = float(stats["posture_max"])
	moves = BossMoves.scaled_moves(boss_index)
	# Big bodies turn slowly (about 70 degrees a second at 3x and above).
	turn_speed = deg_to_rad(70.0 if size >= 3.0 else lerpf(320.0, 70.0, (size - 1.0) / 2.0))
	if boss_index == 9:
		stance = BossMoves.SOVEREIGN_PHASE_ONE[0]
	_ground_layer = int(agent.collision_layer) if agent is CollisionObject3D else 1
	_rng.randomize()


# --- Queries -----------------------------------------------------------------

func is_staggered() -> bool:
	return state == State.STAGGER and _crit_window


func is_roaring() -> bool:
	return state == State.ROAR


func is_immobilized() -> bool:
	return _immobile_left > 0.0


func is_chained() -> bool:
	return _chained and state == State.STAGGER


func is_airborne() -> bool:
	return airborne


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE


func current_move_id() -> String:
	return String(move.get("id", "")) if is_attacking() else ""


func body_radius() -> float:
	return minf(0.36 * size, 1.9)


func facing() -> Vector3:
	var basis: Basis = agent.global_transform.basis
	var f := -basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func minions_alive() -> int:
	var count := 0
	for minion in _minions:
		if is_instance_valid(minion) and minion.is_inside_tree():
			count += 1
	return count


# --- Main update ---------------------------------------------------------------

func physics_step(delta: float, alerted: bool) -> void:
	_immobile_immunity = maxf(0.0, _immobile_immunity - delta)
	if _immobile_left > 0.0:
		_immobile_left -= delta
		_stop()
		_update_effects(delta)
		if _immobile_left <= 0.0:
			_set_frozen(false)
		return
	_clock += delta
	_update_posture(delta)
	_update_effects(delta)
	_update_lift(delta)
	state_time += delta
	match state:
		State.ROAR:
			_stop()
			if state_time >= ROAR_TIME:
				_end_roar()
		State.STAGGER:
			_stop()
			if state_time >= _stagger_duration:
				_end_stagger()
		State.IDLE:
			_update_idle(delta, alerted)
		State.WINDUP:
			_update_windup(delta)
		State.ACTIVE:
			_update_active(delta)
		State.RECOVERY:
			_slow_down(delta)
			if state_time >= float(move.get("recovery", 0.5)) * recovery_mult:
				_enter_idle(_idle_gap_time())


func _update_idle(delta: float, alerted: bool) -> void:
	var player = agent.player
	if not alerted or not is_instance_valid(player):
		_slow_down(delta)
		return
	var flat: Vector3 = player.global_position - agent.global_position
	flat.y = 0.0
	var distance := flat.length()
	_turn_toward(player.global_position, delta)
	_idle_gap -= delta
	if _idle_gap <= 0.0:
		var choice := choose_move(distance)
		if choice != "":
			start_move(choice)
			return
	# Close in until the nearest melee option is in reach.
	if distance > _preferred_distance() and distance > 0.01:
		var dir := flat / distance
		var speed: float = agent.move_speed * (1.8 if airborne else 1.0)
		agent.velocity.x = dir.x * speed
		agent.velocity.z = dir.z * speed
	else:
		_slow_down(delta)


func _update_windup(delta: float) -> void:
	_slow_down(delta)
	if state_time < _track and is_instance_valid(agent.player):
		_turn_toward(agent.player.global_position, delta, 1.6 if size < 2.0 else 1.0)
		if bool(move.get("land", false)):
			# Glide over the player before dropping onto them.
			var to_player: Vector3 = agent.player.global_position - agent.global_position
			to_player.y = 0.0
			var glide := minf(to_player.length() / maxf(_track - state_time, 0.05), 16.0)
			if to_player.length() > 0.3:
				agent.velocity.x = to_player.normalized().x * glide
				agent.velocity.z = to_player.normalized().z * glide
	_forward = facing()
	var progress := state_time / maxf(_windup, 0.001)
	if _indicator != null:
		_indicator.set_progress(progress)
	# Delayed swings: the pose is held, then released just before impact.
	if bool(move.get("delayed", false)):
		var hold := float(move.get("hold", 0.5))
		if not _anim_held and state_time >= (_windup - hold) * 0.7 and state_time < _windup - 0.2:
			_anim_held = true
			_rig_call("set_action_speed", [0.05])
		elif _anim_held and state_time >= _windup - 0.2:
			_anim_held = false
			_rig_call("set_action_speed", [1.0])
	if move.has("feint_at") and state_time >= float(move["feint_at"]) * _windup / float(move["windup"]):
		var into := String(move.get("feint_into", ""))
		if moves.has(into):
			start_move(into)
			return
	if move["color"] == "yellow" and not _flash_done and _windup - state_time <= YELLOW_FLASH:
		_flash_done = true
		if _indicator != null:
			_indicator.set_kind("yellow")
		_rig_call("set_glow", [YELLOW_GLOW])
		SoundBank.play_at("gem", agent.global_position, agent, 1.35)
	if state_time >= _windup:
		_begin_active()


func _update_active(delta: float) -> void:
	var kind := String(move.get("kind", "melee"))
	var active := maxf(float(move.get("active", 0.2)), 0.05)
	match kind:
		"melee", "slam", "pulse":
			if move.has("sweep"):
				# The head swings the narrow breath cone across the marked arc.
				var t := clampf(state_time / active, 0.0, 1.0)
				var half := deg_to_rad(float(move["sweep"]) * 0.5)
				agent.rotation.y = _sweep_yaw + lerpf(half, -half, t)
				_forward = facing()
			var lunge := float(move.get("lunge", 0.0))
			if lunge > 0.0 and state_time <= LUNGE_TIME:
				agent.velocity.x = _forward.x * lunge / LUNGE_TIME
				agent.velocity.z = _forward.z * lunge / LUNGE_TIME
			else:
				_stop()
			if not _hit_landed and move.has("shape"):
				_try_hit(move["shape"], agent.global_position, _forward, move)
		"charge":
			var speed := float(move.get("charge", 8.0)) / active
			agent.velocity.x = _forward.x * speed
			agent.velocity.z = _forward.z * speed
			if not _hit_landed:
				var body := {"type": "circle", "radius": body_radius() + 0.5}
				_try_hit(body, agent.global_position, _forward, move)
		"evade":
			var back := float(move.get("charge", 4.0)) / active
			agent.velocity.x = -_forward.x * back
			agent.velocity.z = -_forward.z * back
		_:
			_stop()
	if state_time >= active:
		_end_active()


# --- Choosing and running moves ------------------------------------------------

# Picks the next opening move for the current distance, or "" to keep
# approaching. Follow-ups, locked phase-two moves, moves of other stances,
# moves on cooldown and (when there is any other option) the last move are
# skipped.
func choose_move(distance: float) -> String:
	if stance != "" and _stance_count >= BossMoves.STANCE_LENGTH and moves.has("stance_shift"):
		return "stance_shift"
	if airborne and _air_count >= BossMoves.AIR_ATTACKS:
		for id in moves:
			if bool(moves[id].get("land", false)) and int(moves[id]["phase"]) <= phase:
				return id
	var candidates: Array = []
	var repeat_only: Array = []
	for id in moves:
		if not is_move_available(id, distance):
			continue
		if id == last_move_id:
			repeat_only.append(id)
		else:
			candidates.append(id)
	if candidates.is_empty():
		candidates = repeat_only
	if candidates.is_empty():
		return ""
	var total := 0.0
	for id in candidates:
		total += float(moves[id].get("weight", 1.0))
	var roll := _rng.randf() * total
	for id in candidates:
		roll -= float(moves[id].get("weight", 1.0))
		if roll <= 0.0:
			return id
	return candidates[-1]


func is_move_available(id: String, distance: float) -> bool:
	var m: Dictionary = moves[id]
	if bool(m.get("followup", false)) or m.get("kind", "") == "stance":
		return false
	if int(m["phase"]) > phase:
		return false
	if bool(m.get("air", false)) != airborne:
		return false
	if bool(m.get("land", false)) and _air_count < BossMoves.AIR_ATTACKS:
		return false
	if stance != "" and String(m.get("stance", "")) != stance:
		return false
	if float(_cooldowns.get(id, -1.0)) > _clock:
		return false
	if m.get("kind", "") == "summon" and minions_alive() > 0:
		return false
	return distance >= float(m.get("min_range", 0.0)) and distance <= float(m["max_range"])


func start_move(id: String) -> void:
	_clear_indicator()
	_rig_call("set_action_speed", [1.0])
	move = moves[id]
	state = State.WINDUP
	state_time = 0.0
	_windup = BossMoves.windup_for(move, phase) * windup_mult
	_track = float(move.get("track_until", 0.0)) * _windup / float(move["windup"])
	_hit_landed = false
	_dodge_notified = false
	_flash_done = false
	_anim_held = false
	_forward = facing()
	if not bool(move.get("followup", false)):
		last_move_id = id
		if stance != "" and move.get("kind", "") != "stance":
			_stance_count += 1
	combo_log.append(id)
	if airborne and bool(move.get("air", false)) and not bool(move.get("land", false)):
		_air_count += 1
	if move.has("cooldown"):
		_cooldowns[id] = _clock + float(move["cooldown"])
	if move.has("shape") and move.get("kind", "") in ["melee", "slam", "pulse", "charge"]:
		_indicator = AttackIndicator.new()
		agent.add_child(_indicator)
		var marked: Dictionary = move["shape"]
		if move.has("sweep"):
			# Mark the whole arc the breath will sweep across.
			marked = marked.duplicate()
			marked["angle"] = minf(359.0, float(marked.get("angle", 30.0)) + float(move["sweep"]))
		_indicator.setup(marked, "red" if move["color"] == "red" else "normal")
	var anim := String(move.get("anim", "heavy"))
	var anim_time := (_windup - float(move.get("hold", 0.0))) * 1.7 if bool(move.get("delayed", false)) else _windup * 1.7
	if not _rig_call("play_action", [anim, anim_time]):
		_rig_call("play_action", ["heavy", anim_time])
	_rig_call("set_glow", [RED_GLOW if move["color"] == "red" else WINDUP_GLOW])
	var pitch := 1.0 / sqrt(size)
	match String(move.get("kind", "")):
		"hazard", "summon", "stance", "pulse":
			SoundBank.play_at("summon", agent.global_position, agent, 0.7 * pitch)
		_:
			if move["color"] == "red":
				# Unblockable attacks get their own warning sound.
				SoundBank.play_at("reveal_legend", agent.global_position, agent, 0.5)
			elif not bool(move.get("followup", false)):
				SoundBank.play_at("swing_heavy", agent.global_position, agent, 0.6 * pitch)


func _begin_active() -> void:
	state = State.ACTIVE
	state_time = 0.0
	_forward = facing()
	_rig_call("set_action_speed", [1.0])
	if _indicator != null:
		_indicator.set_progress(1.0)
		_indicator.set_strength(1.5)
		if move.get("kind", "") == "charge" or move.has("sweep"):
			# The marker stays where it was drawn while the boss runs along
			# it or swings its head across it.
			_indicator.top_level = true
	if move.has("sweep"):
		_sweep_yaw = agent.rotation.y
		var half := deg_to_rad(float(move["sweep"]) * 0.5)
		agent.rotation.y = _sweep_yaw + half
		_forward = facing()
		if agent.is_inside_tree():
			# The narrow cone of flame that actually burns, swinging with the head.
			_flame = AttackIndicator.new()
			agent.add_child(_flame)
			_flame.setup(move["shape"], "fire" if bool(move.get("fire", false)) else "red")
			_flame.set_progress(1.0)
			_flame.set_strength(2.2)
		SoundBank.play_at("summon", agent.global_position, agent, 0.4)
	var pitch := 1.0 / sqrt(size)
	match String(move.get("kind", "")):
		"melee":
			SoundBank.play_at("enemy_swing", agent.global_position, agent, 0.8 * pitch)
			if bool(move.get("heavy", false)):
				_shake(0.5)
		"slam", "pulse":
			SoundBank.play_at("hit_enemy_heavy", agent.global_position, agent, 0.55 * pitch)
			_shake(0.35 + 0.1 * size)
			_spawn_rings()
			var impact_at: Vector3 = agent.global_position
			if move.has("shape"):
				impact_at += _forward * float(move["shape"].get("offset", 0.0))
			Vfx.impact(_world(), impact_at, 0.8 + 0.4 * size)
		"charge":
			SoundBank.play_at("enemy_swing", agent.global_position, agent, 0.5 * pitch)
			if bool(move.get("burrow", false)):
				_rig_call("set_visible", [false])
			if bool(move.get("heavy", false)):
				_shake(0.3)
		"projectile":
			_spawn_projectiles()
		"hazard":
			_spawn_hazards()
		"summon":
			_spawn_minions(int(move.get("summon", {}).get("count", 2)))
		"stance":
			_shift_stance()
		"flight":
			set_airborne(true)
			SoundBank.play_at("dodge", agent.global_position, agent, 0.35)
			_shake(0.3)
	if bool(move.get("land", false)):
		set_airborne(false)
	if move.has("hazard") and move.get("kind", "") != "hazard":
		_spawn_hazards()


func _end_active() -> void:
	_clear_indicator()
	_rig_call("set_visible", [true])
	var next := String(move.get("next", ""))
	if next != "" and moves.has(next) and int(moves[next]["phase"]) <= phase \
			and _rng.randf() <= float(move.get("next_chance", 1.0)):
		start_move(next)
		return
	state = State.RECOVERY
	state_time = 0.0
	_rig_call("set_glow", [_rest_glow()])


func _enter_idle(gap: float) -> void:
	state = State.IDLE
	state_time = 0.0
	_idle_gap = gap
	_clear_indicator()
	_rig_call("set_glow", [_rest_glow()])


func _idle_gap_time() -> float:
	return (_rng.randf_range(0.4, 1.0) if phase >= 2 else _rng.randf_range(0.6, 1.3)) * windup_mult


func _preferred_distance() -> float:
	if airborne:
		return 10.0
	var best := 0.0
	for id in moves:
		var m: Dictionary = moves[id]
		if m.get("kind", "") in ["melee", "slam"] and not bool(m.get("followup", false)) \
				and int(m["phase"]) <= phase and (stance == "" or String(m.get("stance", "")) == stance):
			best = maxf(best, float(m["max_range"]))
	if best <= 0.0:
		best = 2.0 + body_radius()
	return best * 0.75


# --- Hits -----------------------------------------------------------------------

func attack_damage(m: Dictionary) -> float:
	return float(agent.attack_power) * float(m.get("damage", 1.0)) * damage_mult


func attack_info(m: Dictionary, origin: Vector3) -> Dictionary:
	var red: bool = m.get("color", "normal") == "red"
	var push: Vector3 = Vector3.ZERO
	if is_instance_valid(agent.player):
		push = agent.player.global_position - origin
	push.y = 0.0
	push = push.normalized() * (2.5 + size * 0.6) if push.length_squared() > 0.0001 else Vector3.ZERO
	return {"unblockable": red, "parryable": not red, "yellow": m.get("color", "") == "yellow",
		"knockback": push, "heavy": bool(m.get("heavy", false))}


# Tests the player against a shape this frame; delivers the hit once.
func _try_hit(shape: Dictionary, origin: Vector3, forward: Vector3, m: Dictionary) -> bool:
	var player = agent.player
	if not is_instance_valid(player) or float(player.health) <= 0.0:
		return false
	if not player_in_shape(shape, origin, forward, player.global_position, agent.global_position.y):
		return false
	var dodging: bool = player.has_method("is_invulnerable") and player.is_invulnerable()
	if dodging:
		# Let the player register the dodge once; keep testing afterwards.
		if not _dodge_notified:
			_dodge_notified = true
			BossMoves.deliver_attack(player, attack_damage(m), agent, attack_info(m, origin))
		return false
	_hit_landed = true
	BossMoves.deliver_attack(player, attack_damage(m), agent, attack_info(m, origin))
	if bool(m.get("heavy", false)) or m.get("color", "") == "red":
		_shake(0.45)
	return true


static func player_in_shape(shape: Dictionary, origin: Vector3, forward: Vector3, point: Vector3,
		ground_y: float, ring_radius: float = -1.0) -> bool:
	# A low sweep passes under a jumping player.
	if String(shape.get("type", "")) == "box" and point.y - ground_y > JUMP_CLEARANCE:
		return false
	return BossMoves.shape_contains(shape, origin, forward, point, PLAYER_RADIUS, ring_radius)


# --- Shockwave rings ---------------------------------------------------------------

func _spawn_rings() -> void:
	if not move.has("ring"):
		return
	var ring: Dictionary = move["ring"]
	var start := BossMoves.shape_reach(move.get("shape", {}))
	var centre: Vector3 = agent.global_position
	if move.has("shape"):
		centre += _forward * float(move["shape"].get("offset", 0.0))
	for index in range(int(ring.get("count", 1))):
		var effect := {
			"origin": centre, "radius": start, "max": float(ring.get("max", 12.0)),
			"width": float(ring.get("width", 1.5)), "speed": float(ring.get("speed", 8.0)),
			"delay": float(ring.get("interval", 0.0)) * index, "hit": false, "dodged": false,
			"move": move, "indicator": null,
		}
		_effects.append(effect)


func _update_effects(delta: float) -> void:
	for effect in _effects.duplicate():
		if effect["delay"] > 0.0:
			effect["delay"] -= delta
			continue
		if effect["indicator"] == null and agent.is_inside_tree() and agent.get_parent() != null:
			var indicator = AttackIndicator.new()
			agent.get_parent().add_child(indicator)
			indicator.setup({"type": "ring", "radius": effect["max"]}, "normal")
			indicator.global_position = effect["origin"] + Vector3.UP * AttackIndicator.GROUND_LIFT
			effect["indicator"] = indicator
			Vfx.shock_wave(agent.get_parent(), effect["origin"], effect["radius"], effect["max"], effect["speed"])
		effect["radius"] += effect["speed"] * delta
		var r: float = effect["radius"]
		var half: float = effect["width"] * 0.5
		if is_instance_valid(effect["indicator"]):
			effect["indicator"].set_ring(r - half, r + half)
		if not effect["hit"]:
			_try_ring_hit(effect)
		if r - half >= effect["max"]:
			if is_instance_valid(effect["indicator"]):
				effect["indicator"].queue_free()
			_effects.erase(effect)


func _try_ring_hit(effect: Dictionary) -> void:
	var player = agent.player
	if not is_instance_valid(player) or float(player.health) <= 0.0:
		return
	var shape := {"type": "ring", "width": effect["width"]}
	if not player_in_shape(shape, effect["origin"], Vector3.FORWARD, player.global_position,
			agent.global_position.y, effect["radius"]):
		return
	var m: Dictionary = effect["move"]
	var dodging: bool = player.has_method("is_invulnerable") and player.is_invulnerable()
	if dodging:
		if not effect["dodged"]:
			effect["dodged"] = true
			BossMoves.deliver_attack(player, attack_damage(m) * 0.8, agent, attack_info(m, effect["origin"]))
		return
	effect["hit"] = true
	BossMoves.deliver_attack(player, attack_damage(m) * 0.8, agent, attack_info(m, effect["origin"]))


func _clear_effects() -> void:
	for effect in _effects:
		if is_instance_valid(effect["indicator"]):
			effect["indicator"].queue_free()
	_effects.clear()


func ring_count() -> int:
	return _effects.size()


# --- Spawned objects --------------------------------------------------------------

func _world() -> Node:
	return agent.get_parent() if agent.is_inside_tree() else null


func _spawn_projectiles() -> void:
	var world := _world()
	var player = agent.player
	if world == null or not is_instance_valid(player):
		return
	var settings: Dictionary = move.get("projectile", {})
	var count := int(settings.get("count", 1))
	var spread := deg_to_rad(float(settings.get("spread", 0.0)))
	var start: Vector3 = agent.global_position + Vector3.UP * (BossMoves.PLAYER_HEIGHT * size * 0.55) \
		+ _forward * (body_radius() + 0.4)
	var aim: Vector3 = (player.global_position + Vector3.UP * 1.0) - start
	var amount := float(agent.attack_power) * float(settings.get("damage", 0.7)) * damage_mult
	for index in range(count):
		var t := 0.0 if count <= 1 else float(index) / float(count - 1) - 0.5
		var projectile = BossProjectile.new()
		projectile.setup(agent, player, start, aim.rotated(Vector3.UP, spread * t), settings, amount)
		if boss_index == 4:
			projectile.tint = Color(0.85, 0.95, 1.0)
		world.add_child(projectile)
		projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
		_spawned.append(projectile)
	SoundBank.play_at("swing_light", start, agent, 0.7)


func _spawn_hazards() -> void:
	var world := _world()
	var player = agent.player
	if world == null or not is_instance_valid(player):
		return
	var settings: Dictionary = move.get("hazard", {})
	var target: Vector3 = player.global_position
	var count := int(settings.get("count", 1))
	var spacing := float(settings.get("spacing", 3.0))
	var amount := float(agent.attack_power) * float(settings.get("damage", 0.5)) * damage_mult
	var to_target: Vector3 = target - agent.global_position
	to_target.y = 0.0
	var lane_dir := to_target.normalized() if to_target.length_squared() > 0.01 else _forward
	var right := Vector3(-lane_dir.z, 0.0, lane_dir.x)
	var placements: Array = []   # [position, forward]
	match String(settings.get("pattern", "at_target")):
		"at_target":
			placements.append([target, lane_dir])
			for index in range(1, count):
				var angle := _rng.randf() * TAU
				placements.append([target + Vector3(cos(angle), 0.0, sin(angle)) * spacing * _rng.randf_range(0.8, 1.3), lane_dir])
		"ring_around_target":
			var base_angle := _rng.randf() * TAU
			for index in range(count):
				var angle := base_angle + TAU * index / count
				placements.append([target + Vector3(cos(angle), 0.0, sin(angle)) * spacing, lane_dir])
		"along_cone":
			var shape: Dictionary = move.get("shape", {})
			var radius := float(shape.get("radius", 4.0))
			var half := deg_to_rad(float(shape.get("angle", 90.0)) * 0.4)
			for index in range(count):
				var t := 0.0 if count <= 1 else float(index) / float(count - 1) * 2.0 - 1.0
				var dir := _forward.rotated(Vector3.UP, half * t)
				placements.append([agent.global_position + dir * radius * 0.7, lane_dir])
		"lanes":
			for index in range(count):
				var offset := (float(index) - float(count - 1) * 0.5) * spacing
				placements.append([target + right * offset, lane_dir])
		"cross_lanes":
			placements.append([target, lane_dir])
			placements.append([target, right])
	for placement in placements:
		var hazard = BossHazard.new()
		hazard.setup(agent, player, settings, amount)
		world.add_child(hazard)
		hazard.process_mode = Node.PROCESS_MODE_PAUSABLE
		var position: Vector3 = placement[0]
		position.y = agent.global_position.y if absf(player.global_position.y - agent.global_position.y) < 1.5 else position.y
		var dir: Vector3 = placement[1]
		hazard.global_position = position
		hazard.look_at(position + dir, Vector3.UP)
		_spawned.append(hazard)


func _spawn_minions(count: int) -> void:
	var world := _world()
	if world == null:
		return
	var script: Script = agent.get_script()
	var right := Vector3(-_forward.z, 0.0, _forward.x)
	for index in range(count):
		var minion = script.new()
		minion.configure_enemy(agent.player, agent.boss_floor, false)
		minion.summoned = true
		var side := -1.0 if index % 2 == 0 else 1.0
		var spot: Vector3 = agent.global_position + right * side * (2.5 + body_radius()) + _forward * 1.5
		minion.position = spot + Vector3.UP * 0.5
		minion.process_mode = Node.PROCESS_MODE_PAUSABLE
		world.add_child(minion)
		_minions.append(minion)
	SoundBank.play_at("summon", agent.global_position, agent, 0.6)


func _shift_stance() -> void:
	var pool: Array = BossMoves.SOVEREIGN_PHASE_ONE.duplicate()
	if phase >= 2:
		pool.append_array(BossMoves.SOVEREIGN_PHASE_TWO)
	pool.erase(stance)
	if phase >= 2:
		# Phase two favours the new stances.
		for extra in BossMoves.SOVEREIGN_PHASE_TWO:
			if extra != stance:
				pool.append(extra)
	stance = pool[_rng.randi() % pool.size()]
	_stance_count = 0
	_rig_call("set_glow", [BossMoves.STANCE_GLOWS.get(stance, WINDUP_GLOW)])


# Frees everything this boss spawned (death or phase change). Minions are
# only freed on death.
func cleanup(include_minions: bool) -> void:
	_clear_indicator()
	_clear_effects()
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	if include_minions:
		for minion in _minions:
			if is_instance_valid(minion):
				minion.remove_from_group("tower_enemies")
				minion.queue_free()
		_minions.clear()


# --- Posture, stagger, parry ---------------------------------------------------------

# Damage after stagger and critical rules (the clue exposure bonus is
# applied by the agent afterwards). Also adds the hit's posture.
func modify_incoming(amount: float, heavy: bool, info: Dictionary, maximum_health: float) -> float:
	if state == State.ROAR:
		return 0.0
	var dealt := amount
	if is_staggered():
		dealt *= STAGGER_DAMAGE
		if bool(info.get("critical", false)):
			dealt = clampf(dealt, maximum_health * CRITICAL_MIN_FRACTION, maximum_health * CRITICAL_MAX_FRACTION)
			# A critical spends the stagger.
			_crit_window = false
			state_time = maxf(state_time, _stagger_duration - 0.5)
		return dealt
	add_posture(float(info.get("posture", HEAVY_POSTURE if heavy else LIGHT_POSTURE)))
	return dealt


func add_posture(amount: float) -> void:
	if amount <= 0.0 or state == State.ROAR or is_staggered() or is_chained():
		return
	posture = minf(posture_max, posture + amount)
	_posture_idle = 0.0
	if posture >= posture_max:
		enter_stagger(STAGGER_TIME, true)


func _update_posture(delta: float) -> void:
	if is_staggered():
		return
	_posture_idle += delta
	if _posture_idle >= POSTURE_DRAIN_DELAY:
		posture = maxf(0.0, posture - POSTURE_DRAIN_RATE * delta)


func on_parried() -> void:
	if state == State.ROAR:
		return
	var was_yellow: bool = is_attacking() and move.get("color", "") == "yellow"
	var was_attacking := is_attacking()
	add_posture(PARRY_POSTURE)
	if state == State.STAGGER:
		return   # posture broke
	if was_yellow:
		enter_stagger(PARRY_STAGGER_TIME, true)
	elif was_attacking:
		enter_stagger(PARRY_FLINCH_TIME, false)


func enter_stagger(seconds: float, critical_window: bool) -> void:
	_cancel_move()
	_chained = false
	if airborne:
		set_airborne(false)   # knocked out of the sky
	state = State.STAGGER
	state_time = 0.0
	_stagger_duration = seconds
	_crit_window = critical_window
	_rig_call("set_action_speed", [1.0])
	if not _rig_call("play_action", ["stagger", minf(seconds, 1.2)]):
		_rig_call("play_action", ["hit", minf(seconds, 1.0)])
	_rig_call("set_glow", [STAGGER_GLOW if critical_window else _rest_glow()])
	if critical_window:
		SoundBank.play_at("parry", agent.global_position, agent, 0.6)
		_shake(0.3)


func _end_stagger() -> void:
	if _crit_window or posture >= posture_max:
		posture = 0.0
	_crit_window = false
	_chained = false
	_enter_idle(0.35)


func _cancel_move() -> void:
	_clear_indicator()
	_rig_call("set_visible", [true])
	_rig_call("set_action_speed", [1.0])
	_anim_held = false
	_stop()


# --- Phases -------------------------------------------------------------------------

func should_enter_phase_two(health: float, maximum_health: float) -> bool:
	return phase == 1 and health <= maximum_health * PHASE_THRESHOLD


func begin_phase_two() -> void:
	phase = 2
	_cancel_move()
	cleanup(false)
	_chained = false
	posture = 0.0
	_crit_window = false
	_immobile_left = 0.0
	_set_frozen(false)
	state = State.ROAR
	state_time = 0.0
	if not _rig_call("play_action", ["roar", ROAR_TIME * 0.8]):
		_rig_call("play_action", ["heavy", ROAR_TIME * 0.8])
	_rig_call("set_glow", [ROAR_GLOW])
	SoundBank.play_at("summon", agent.global_position, agent, 0.45)
	SoundBank.play_at("boss_death", agent.global_position, agent, 1.3)
	_shake(0.8)


func _end_roar() -> void:
	if boss_index == 9:
		stance = BossMoves.SOVEREIGN_PHASE_TWO[_rng.randi() % BossMoves.SOVEREIGN_PHASE_TWO.size()]
		_stance_count = 0
	_enter_idle(0.5)


# --- Flight and chains -------------------------------------------------------------------

func set_airborne(flying: bool) -> void:
	airborne = flying
	_air_count = 0
	if agent is CollisionObject3D:
		# The player can walk beneath a flying boss.
		agent.collision_layer = 0 if flying else _ground_layer


# Height the model should be at: up while flying, dropping over the last
# part of a landing wind-up so it touches down on the impact.
func lift_target() -> float:
	if not airborne:
		return 0.0
	if state == State.WINDUP and bool(move.get("land", false)) and state_time > _track:
		return BossMoves.FLIGHT_HEIGHT * clampf(1.0 - (state_time - _track) / maxf(_windup - _track, 0.05), 0.0, 1.0)
	return BossMoves.FLIGHT_HEIGHT


func _update_lift(delta: float) -> void:
	var target := lift_target()
	var speed := 14.0 if target > lift else 30.0
	lift = move_toward(lift, target, speed * delta)
	var rig = agent.get("_rig")
	if rig != null and is_instance_valid(rig):
		rig.position.y = lift


# The Chain Rite drags the boss down: it is pinned for `seconds` with no
# critical window and no posture build-up. Returns false while roaring.
func chain_down(seconds: float) -> bool:
	if state == State.ROAR or seconds <= 0.0:
		return false
	_immobile_left = 0.0
	_set_frozen(false)
	if airborne:
		set_airborne(false)
	enter_stagger(seconds, false)
	_chained = true
	_rig_call("set_glow", [Color(0.35, 0.3, 0.1)])
	SoundBank.play_at("parry", agent.global_position, agent, 0.45)
	_shake(0.7)
	return true


# --- Immobilize ------------------------------------------------------------------------

# Bosses are frozen for 60% of the requested time, then immune for 20 s.
func apply_immobilize(seconds: float) -> bool:
	if state == State.ROAR or is_chained() or _immobile_immunity > 0.0 or _immobile_left > 0.0 or seconds <= 0.0:
		return false
	_immobile_left = seconds * IMMOBILIZE_BOSS_FACTOR
	_immobile_immunity = _immobile_left + IMMOBILIZE_IMMUNITY
	_stop()
	_set_frozen(true)
	return true


func immobilize_immunity_left() -> float:
	return _immobile_immunity


func _set_frozen(frozen: bool) -> void:
	_rig_call("set_frozen", [frozen])
	_rig_call("set_glow", [FREEZE_GLOW if frozen else _current_glow()])


func _current_glow() -> Color:
	if state == State.WINDUP:
		return RED_GLOW if move.get("color", "") == "red" else WINDUP_GLOW
	if state == State.STAGGER and _crit_window:
		return STAGGER_GLOW
	return _rest_glow()


func _rest_glow() -> Color:
	if stance != "":
		return BossMoves.STANCE_GLOWS.get(stance, REST_GLOW)
	return REST_GLOW


# --- Helpers ------------------------------------------------------------------------------

func _turn_toward(point: Vector3, delta: float, multiplier: float = 1.0) -> void:
	var offset: Vector3 = point - agent.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-offset.x, -offset.z)
	agent.rotation.y = rotate_toward(agent.rotation.y, target_yaw, turn_speed * multiplier * delta)


func _stop() -> void:
	agent.velocity.x = 0.0
	agent.velocity.z = 0.0


func _slow_down(delta: float) -> void:
	agent.velocity.x = move_toward(agent.velocity.x, 0.0, 16.0 * delta)
	agent.velocity.z = move_toward(agent.velocity.z, 0.0, 16.0 * delta)


func _clear_indicator() -> void:
	if _indicator != null and is_instance_valid(_indicator):
		_indicator.queue_free()
	_indicator = null
	if _flame != null and is_instance_valid(_flame):
		_flame.queue_free()
	_flame = null


func _shake(strength: float) -> void:
	var player = agent.player
	if not is_instance_valid(player) or not player.has_method("camera_shake"):
		return
	var distance: float = player.global_position.distance_to(agent.global_position)
	var amount := strength * clampf(1.0 - distance / (12.0 + size * 5.0), 0.0, 1.0)
	if amount > 0.04:
		player.camera_shake(amount)


func _rig_call(method: String, args: Array) -> bool:
	var rig = agent.get("_rig")
	if rig == null or not is_instance_valid(rig):
		return false
	if method == "set_visible":
		rig.visible = bool(args[0])
		return true
	if not rig.has_method(method):
		return false
	var result = rig.callv(method, args)
	return result if result is bool else true
