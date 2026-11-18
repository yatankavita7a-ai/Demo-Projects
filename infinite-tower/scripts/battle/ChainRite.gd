extends Node3D

# Floor 20 without Dragonbane: the Chain Rite (docs/BOSS_SYSTEM.md).
# Four Tower chains bind Vharzul to pillars around the arena. Standing in a
# pillar's circle for RITE_CHANNEL seconds lights it (progress drains away
# while the player is outside). Meanwhile the wyrm attacks at full
# aggression. When all four are lit the chains drag it down for RITE_STUN
# seconds, the only time its scales can be cut. Then it breaks free, the
# pillars go dark, and every cycle it attacks faster and harder.

signal pillar_lit(index: int)
signal bound(cycle: int)
signal broke_free(cycle: int)

const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const AttackIndicator = preload("res://scripts/battle/AttackIndicator.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const PILLAR_HEIGHT := 7.0
const DARK_STONE := Color("#4a4640")
const LIT_STONE := Color("#d9b46a")

var dragon        # EnemyAgent (Vharzul)
var player
var cycle := 0
var progress: Array = []
var lit: Array = []
var positions: Array = []
var ground_height: Callable

var _was_chained := false
var _circles: Array = []
var _lights: Array = []
var _stones: Array = []
var _chains: Array = []


func setup(dragon_agent, player_node) -> void:
	dragon = dragon_agent
	player = player_node
	positions = SpecialFloors.rite_pillar_positions()
	progress.resize(positions.size())
	progress.fill(0.0)
	lit.resize(positions.size())
	lit.fill(false)
	_apply_difficulty()


func _ready() -> void:
	for index in range(positions.size()):
		var spot: Vector3 = positions[index]
		if ground_height.is_valid():
			spot.y = float(ground_height.call(spot.x, spot.z))
		positions[index] = spot
		_build_pillar(index, spot)


func lit_count() -> int:
	return lit.count(true)


func is_binding() -> bool:
	return is_instance_valid(dragon) and dragon.is_chained()


# HUD line, e.g. "CHAINS 2/4" or "CHAINED  6s".
func status_text() -> String:
	if is_binding():
		return "CHAINED  %ds" % ceili(_chain_left())
	return "CHAINS %d/%d" % [lit_count(), positions.size()]


func _chain_left() -> float:
	if not is_binding():
		return 0.0
	var brain = dragon._brain
	return maxf(0.0, float(brain._stagger_duration) - float(brain.state_time))


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not is_instance_valid(dragon) or not is_instance_valid(player):
		return
	var chained: bool = dragon.is_chained()
	if _was_chained and not chained:
		_break_free()
	_was_chained = chained
	if not chained and float(player.health) > 0.0:
		_channel(delta)
		if lit_count() == positions.size() and dragon.chain_down(SpecialFloors.RITE_STUN):
			_was_chained = true
			bound.emit(cycle)
	_update_visuals()


func _channel(delta: float) -> void:
	for index in range(positions.size()):
		if lit[index]:
			continue
		var spot: Vector3 = positions[index]
		var offset: Vector3 = player.global_position - spot
		offset.y = 0.0
		if offset.length() <= SpecialFloors.RITE_CIRCLE:
			progress[index] = float(progress[index]) + delta
			if float(progress[index]) >= SpecialFloors.RITE_CHANNEL:
				progress[index] = SpecialFloors.RITE_CHANNEL
				lit[index] = true
				SoundBank.play_at("reveal_legend", spot, self, 0.8)
				pillar_lit.emit(index)
		else:
			progress[index] = maxf(0.0, float(progress[index]) - SpecialFloors.RITE_DECAY * delta)


func _break_free() -> void:
	cycle += 1
	progress.fill(0.0)
	lit.fill(false)
	_apply_difficulty()
	if is_instance_valid(dragon):
		SoundBank.play_at("boss_death", dragon.global_position, self, 0.8)
	if is_instance_valid(player) and player.has_method("camera_shake"):
		player.camera_shake(0.6)
	broke_free.emit(cycle)


func _apply_difficulty() -> void:
	if is_instance_valid(dragon) and dragon.has_method("set_aggression"):
		dragon.set_aggression(SpecialFloors.rite_windup_mult(cycle), SpecialFloors.rite_damage_mult(cycle))


# --- Visuals --------------------------------------------------------------------

func _build_pillar(index: int, spot: Vector3) -> void:
	var stone := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.7
	column.bottom_radius = 0.95
	column.height = PILLAR_HEIGHT
	stone.mesh = column
	var material := StandardMaterial3D.new()
	material.albedo_color = DARK_STONE
	material.emission_enabled = true
	material.emission = Color.BLACK
	stone.material_override = material
	add_child(stone)
	stone.position = spot + Vector3.UP * PILLAR_HEIGHT * 0.5
	_stones.append(material)
	var circle = AttackIndicator.new()
	add_child(circle)
	circle.setup({"type": "circle", "radius": SpecialFloors.RITE_CIRCLE}, "chain")
	circle.position = spot
	_circles.append(circle)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.4)
	light.omni_range = 9.0
	light.light_energy = 0.0
	add_child(light)
	light.position = spot + Vector3.UP * (PILLAR_HEIGHT + 0.5)
	_lights.append(light)
	var chain := MeshInstance3D.new()
	var link := BoxMesh.new()
	link.size = Vector3(0.18, 0.18, 1.0)
	chain.mesh = link
	var chain_material := StandardMaterial3D.new()
	chain_material.albedo_color = Color("#6d665c")
	chain_material.metallic = 0.8
	chain_material.roughness = 0.4
	chain_material.emission_enabled = true
	chain_material.emission = Color.BLACK
	chain.material_override = chain_material
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chain)
	_chains.append(chain)


func _update_visuals() -> void:
	if _circles.is_empty():
		return
	var binding := is_binding()
	var anchor: Vector3 = dragon.get_lock_point() if is_instance_valid(dragon) else Vector3.ZERO
	for index in range(positions.size()):
		var fraction := float(progress[index]) / SpecialFloors.RITE_CHANNEL
		var glowing: bool = lit[index] or binding
		_circles[index].set_progress(1.0 if glowing else fraction)
		_circles[index].set_strength(1.8 if glowing else 1.0 + fraction)
		_lights[index].light_energy = 3.0 if glowing else fraction * 1.5
		_stones[index].emission = LIT_STONE * (0.8 if glowing else fraction * 0.4)
		# A chain runs from each pillar's crown to the wyrm; it glows when lit.
		var chain: MeshInstance3D = _chains[index]
		var from: Vector3 = positions[index] + Vector3.UP * PILLAR_HEIGHT
		var to: Vector3 = anchor if not binding else dragon.global_position + Vector3.UP * 1.0
		var length := from.distance_to(to)
		if length < 0.1:
			chain.visible = false
			continue
		chain.visible = true
		chain.global_position = (from + to) * 0.5
		chain.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
		chain.scale = Vector3(1.0, 1.0, length)
		var chain_material: StandardMaterial3D = chain.material_override
		chain_material.emission = LIT_STONE * (1.5 if glowing else 0.0)
