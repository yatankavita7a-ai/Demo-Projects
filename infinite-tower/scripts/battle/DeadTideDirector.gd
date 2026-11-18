extends Node3D

# Floor 10, The Dead Tide (docs/BOSS_SYSTEM.md, scripts/systems/
# SpecialFloors.gd). No guardian: the player must survive an endless horde
# for TIDE_DURATION seconds of real gameplay time. Zombies spawn in groups
# from beyond the edge of the player's view, escalate every tier, and come
# as brute packs at the surges. A hard cap keeps the live count bounded;
# zombies that fall far behind or get stuck are quietly recycled.
#
# The director is a pausable world node, so a paused game stops the clock.
# Slow motion (perfect dodges, hit-stop) does not: elapsed time is measured
# in real seconds. It also stands in as the "source" of bloated zombies'
# poison pools (BossHazard needs a living source that is not roaring).

signal survived
signal surge(index: int)
signal tier_changed(tier: int)

const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const BossHazard = preload("res://scripts/battle/BossHazard.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")

var player
var floor_number := SpecialFloors.DEAD_TIDE_FLOOR
var elapsed := 0.0
var kills := 0
var known_clues := 0
var allies := 0
var finished := false
# Returns the ground height at (x, z); without it zombies spawn at the
# player's height.
var ground_height: Callable
# Where new zombies are added (the floor's root); defaults to the parent.
var world: Node

var _zombies: Array = []
var _spawn_left := 1.5
var _surges_done := 0
var _tier := 0
var _rng := RandomNumberGenerator.new()
var _last_positions := {}   # zombie instance id -> [position, seconds still]


func setup(player_node, clues: int = 0, ally_count: int = 0) -> void:
	player = player_node
	known_clues = maxi(clues, 0)
	allies = maxi(ally_count, 0)
	_rng.randomize()


func is_roaring() -> bool:
	return false


func time_left() -> float:
	return maxf(0.0, SpecialFloors.TIDE_DURATION - elapsed)


func current_settings() -> Dictionary:
	return SpecialFloors.tide_settings(elapsed, known_clues, allies)


func live_count() -> int:
	_prune()
	return _zombies.size()


func zombies() -> Array:
	_prune()
	return _zombies.duplicate()


func _physics_process(delta: float) -> void:
	# Real seconds: undo the engine's slow-motion scaling.
	step(delta / maxf(Engine.time_scale, 0.01))


# Advances the tide by `seconds` of gameplay time.
func step(seconds: float) -> void:
	if finished or not is_instance_valid(player) or float(player.health) <= 0.0:
		return
	elapsed += maxf(0.0, seconds)
	_check_tier()
	_check_surges()
	if elapsed >= SpecialFloors.TIDE_DURATION:
		_finish()
		return
	_spawn_left -= seconds
	if _spawn_left <= 0.0:
		var settings := current_settings()
		_spawn_left = float(settings["interval"])
		var group: Vector2i = settings["group"]
		var count := _rng.randi_range(group.x, group.y)
		_spawn_group(count, settings)
	_recycle_stragglers(seconds)


# Debug / test hook: jump the clock forward. Surges and tiers passed on the
# way still happen; reaching the end clears the floor.
func fast_forward(seconds: float) -> void:
	step(maxf(0.0, seconds))


func _check_tier() -> void:
	var tier := SpecialFloors.tide_tier_index(elapsed)
	if tier != _tier:
		_tier = tier
		tier_changed.emit(tier)
		if is_instance_valid(player):
			SoundBank.play_at("summon", player.global_position, self, 0.5)


func _check_surges() -> void:
	while _surges_done < SpecialFloors.TIDE_SURGES.size() and elapsed >= float(SpecialFloors.TIDE_SURGES[_surges_done]):
		var index := _surges_done
		_surges_done += 1
		var settings := current_settings()
		# A brute pack with an escort, all from one direction.
		var angle := _behind_angle()
		var brutes: int = SpecialFloors.TIDE_SURGE_BRUTES[mini(index, SpecialFloors.TIDE_SURGE_BRUTES.size() - 1)]
		for i in range(brutes):
			_spawn_one("brute", settings, angle + _rng.randf_range(-0.25, 0.25))
		for i in range(SpecialFloors.TIDE_SURGE_ESCORT):
			_spawn_one("shambler", settings, angle + _rng.randf_range(-0.45, 0.45))
		if is_instance_valid(player):
			SoundBank.play_at("boss_death", player.global_position, self, 0.5)
			SoundBank.play_at("summon", player.global_position, self, 0.4)
			if player.has_method("camera_shake"):
				player.camera_shake(0.35)
		surge.emit(index)


func _finish() -> void:
	finished = true
	elapsed = SpecialFloors.TIDE_DURATION
	for zombie in zombies():
		if zombie.defeated.is_connected(_on_zombie_defeated):
			zombie.defeated.disconnect(_on_zombie_defeated)
		zombie.collapse()
	_zombies.clear()
	survived.emit()


# A group arrives together from one direction, like a wave breaking.
func _spawn_group(count: int, settings: Dictionary) -> void:
	var angle := _behind_angle()
	for i in range(count):
		if live_count() >= mini(int(settings["cap"]), SpecialFloors.TIDE_HARD_CAP):
			return
		_spawn_one(_pick_kind(settings["weights"]), settings, angle + _rng.randf_range(-0.35, 0.35))


func _pick_kind(weights: Dictionary) -> String:
	var total := 0.0
	for kind in weights:
		total += float(weights[kind])
	var roll := _rng.randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll <= 0.0 and float(weights[kind]) > 0.0:
			return kind
	return "shambler"


# An angle (around the player, world XZ) behind the camera, so new zombies
# appear out of view.
func _behind_angle() -> float:
	var forward := Vector3.FORWARD
	if is_instance_valid(player) and player.has_method("_camera_forward"):
		forward = player._camera_forward()
	var back := -forward
	return atan2(back.z, back.x) + _rng.randf_range(-1.6, 1.6)


func _spawn_one(kind: String, settings: Dictionary, angle: float) -> Node:
	if live_count() >= SpecialFloors.TIDE_HARD_CAP or not is_instance_valid(player):
		return null
	var host: Node = world if is_instance_valid(world) else get_parent()
	if host == null:
		return null
	var radius := _rng.randf_range(SpecialFloors.TIDE_SPAWN_RADIUS.x, SpecialFloors.TIDE_SPAWN_RADIUS.y)
	var origin: Vector3 = player.global_position
	var spot := origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var limit := SpecialFloors.TIDE_PLAY_LIMIT
	spot.x = clampf(spot.x, -limit, limit)
	spot.z = clampf(spot.z, -limit, limit)
	spot.y = (float(ground_height.call(spot.x, spot.z)) if ground_height.is_valid() else origin.y) + 0.4
	var script: Script = load("res://scripts/battle/EnemyAgent.gd")
	var zombie = script.new()
	zombie.configure_zombie(player, floor_number, kind, float(settings["health"]), float(settings["speed"]))
	zombie.position = spot
	zombie.defeated.connect(_on_zombie_defeated)
	host.add_child(zombie)
	zombie.process_mode = Node.PROCESS_MODE_PAUSABLE
	_zombies.append(zombie)
	return zombie


func _on_zombie_defeated(zombie) -> void:
	_zombies.erase(zombie)
	if zombie.zombie_kind == "collapsed":
		return
	kills += 1
	if zombie.zombie_kind == "bloated":
		_burst(zombie.global_position, float(zombie.attack_power))


# A bloated zombie bursts into a lingering poison pool.
func _burst(at: Vector3, attack_power: float) -> Node:
	var host: Node = world if is_instance_valid(world) else get_parent()
	if host == null or not is_instance_valid(player):
		return null
	var hazard = BossHazard.new()
	hazard.setup(self, player, SpecialFloors.BLOAT_POOL, attack_power * SpecialFloors.BLOAT_POOL_DAMAGE)
	host.add_child(hazard)
	hazard.process_mode = Node.PROCESS_MODE_PAUSABLE
	hazard.global_position = at
	SoundBank.play_at("enemy_death", at, self, 0.5)
	return hazard


# Zombies far behind the player, fallen out of the world, or stuck behind
# terrain for a while are removed so the cap goes to ones that can fight.
func _recycle_stragglers(seconds: float) -> void:
	if not is_instance_valid(player):
		return
	for zombie in zombies():
		var key: int = zombie.get_instance_id()
		var here: Vector3 = zombie.global_position
		var distance: float = Vector2(here.x - player.global_position.x, here.z - player.global_position.z).length()
		var record: Array = _last_positions.get(key, [here, 0.0])
		if here.distance_to(record[0]) > 1.0:
			record = [here, 0.0]
		else:
			record[1] = float(record[1]) + seconds
		_last_positions[key] = record
		var stuck: bool = float(record[1]) >= SpecialFloors.TIDE_STUCK_SECONDS and distance > 8.0
		if distance > SpecialFloors.TIDE_DESPAWN_DISTANCE or here.y < -20.0 or stuck:
			_remove(zombie)


func _remove(zombie) -> void:
	_zombies.erase(zombie)
	_last_positions.erase(zombie.get_instance_id())
	if zombie.defeated.is_connected(_on_zombie_defeated):
		zombie.defeated.disconnect(_on_zombie_defeated)
	zombie.remove_from_group("tower_enemies")
	zombie.queue_free()


func _prune() -> void:
	for zombie in _zombies.duplicate():
		if not is_instance_valid(zombie) or zombie.is_queued_for_deletion():
			_zombies.erase(zombie)
