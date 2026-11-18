extends Node3D

# Ground hazard placed by a boss: root snares and arrow rain (one eruption
# after a telegraph), artillery and beam lanes (one strike), fire, briar and
# darkness pools (tick damage while standing inside). It always telegraphs
# first with a filling ground marker. Spawned into the floor's world node;
# it frees itself when done or when its boss is gone.

const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const AttackIndicator = preload("res://scripts/battle/AttackIndicator.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const BURST_TIME := 0.25
const PLAYER_RADIUS := 0.3

var source        # EnemyAgent
var target        # player
var shape: Dictionary = {}
var arm_time := 1.0
var duration := 0.0   # 0 = a single eruption; otherwise lingering seconds
var tick := 0.5
var damage := 10.0
var color := "normal"
var tint := "fire"
var _time := 0.0
var _tick_left := 0.0
var _burst_done := false
var _hit := false
var _indicator


func setup(from_agent, player_node, settings: Dictionary, amount: float) -> void:
	source = from_agent
	target = player_node
	shape = (settings.get("shape", {"type": "circle", "radius": 2.0}) as Dictionary).duplicate()
	# Lanes are centred on their position.
	if String(shape.get("type", "")) in ["line", "box"]:
		shape["offset"] = -float(shape.get("length", 1.0)) * 0.5
	arm_time = float(settings.get("arm", arm_time))
	duration = float(settings.get("duration", duration))
	tick = maxf(0.1, float(settings.get("tick", tick)))
	color = String(settings.get("color", "normal"))
	tint = String(settings.get("tint", "fire"))
	damage = amount


func _ready() -> void:
	_indicator = AttackIndicator.new()
	add_child(_indicator)
	_indicator.setup(shape, color)


func is_armed() -> bool:
	return _time >= arm_time


func _physics_process(delta: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		queue_free()
		return
	_time += delta
	if _time < arm_time:
		_indicator.set_progress(_time / arm_time)
		return
	var since := _time - arm_time
	if duration <= 0.0:
		# Single eruption.
		if not _burst_done:
			_burst_done = true
			_indicator.set_progress(1.0)
			_indicator.set_strength(1.8)
			SoundBank.play_at("hit_enemy_heavy", global_position, self, 0.6)
			_shake(0.35)
		if not _hit and since <= BURST_TIME:
			_try_hit()
		_indicator.set_strength(maxf(0.0, 1.8 * (1.0 - since / (BURST_TIME + 0.35))))
		if since >= BURST_TIME + 0.35:
			queue_free()
		return
	# Lingering pool.
	if not _burst_done:
		_burst_done = true
		_indicator.set_kind(tint)
		_indicator.set_progress(1.0)
		_tick_left = 0.0
	_indicator.set_strength(0.85 + 0.25 * sin(_time * 6.0))
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick
		_try_hit()
	if since >= duration:
		queue_free()


func _try_hit() -> void:
	if not is_instance_valid(target) or source.is_roaring():
		return
	if target.get("health") != null and float(target.health) <= 0.0:
		return
	var forward := -global_transform.basis.z
	if not BossMoves.shape_contains(shape, global_position, forward, target.global_position, PLAYER_RADIUS):
		return
	var info := {"parryable": false, "unblockable": color == "red"}
	BossMoves.deliver_attack(target, damage, self, info)
	if not (target.has_method("is_invulnerable") and target.is_invulnerable()):
		_hit = true


func _shake(strength: float) -> void:
	if is_instance_valid(target) and target.has_method("camera_shake"):
		var distance := global_position.distance_to(target.global_position)
		var amount := strength * clampf(1.0 - distance / 25.0, 0.0, 1.0)
		if amount > 0.05:
			target.camera_shake(amount)
