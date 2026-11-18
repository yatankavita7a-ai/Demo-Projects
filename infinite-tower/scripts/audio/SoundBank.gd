extends RefCounted

# One-shot sound effects (Kenney CC0 packs, see assets/CREDITS.md).
# Use through a preload, e.g.
#   const SoundBank = preload("res://scripts/audio/SoundBank.gd")
#   SoundBank.play_at("hit_enemy", global_position, self)   # world, positional
#   SoundBank.play_ui("click")                              # interface
# Every player frees itself when its sound has finished.

const RPG := "res://assets/audio/kenney/rpg/"
const IMPACT := "res://assets/audio/kenney/impact/"
const UI := "res://assets/audio/kenney/interface/"

# name: [files, volume_db, pitch]. A random file is picked each time and the
# pitch is varied slightly so repeated sounds do not feel mechanical.
const SOUNDS := {
	"footstep": [[RPG + "footstep00.ogg", RPG + "footstep01.ogg", RPG + "footstep02.ogg", RPG + "footstep03.ogg", RPG + "footstep04.ogg", RPG + "footstep05.ogg", RPG + "footstep06.ogg", RPG + "footstep07.ogg", RPG + "footstep08.ogg", RPG + "footstep09.ogg"], -17.0, 1.0],
	"swing_light": [[RPG + "drawKnife1.ogg", RPG + "drawKnife2.ogg", RPG + "drawKnife3.ogg"], -9.0, 1.15],
	"swing_heavy": [[RPG + "knifeSlice.ogg", RPG + "knifeSlice2.ogg"], -6.0, 0.8],
	"enemy_swing": [[RPG + "knifeSlice.ogg", RPG + "knifeSlice2.ogg"], -9.0, 0.65],
	"dodge": [[RPG + "cloth1.ogg", RPG + "cloth2.ogg", RPG + "cloth3.ogg", RPG + "cloth4.ogg"], -6.0, 1.1],
	"hit_enemy": [[IMPACT + "impactPunch_medium_000.ogg", IMPACT + "impactPunch_medium_001.ogg", IMPACT + "impactPunch_medium_002.ogg", IMPACT + "impactPunch_medium_003.ogg", IMPACT + "impactPunch_medium_004.ogg"], -4.0, 1.0],
	"hit_enemy_heavy": [[IMPACT + "impactPunch_heavy_000.ogg", IMPACT + "impactPunch_heavy_001.ogg", IMPACT + "impactPunch_heavy_002.ogg", IMPACT + "impactPunch_heavy_003.ogg", IMPACT + "impactPunch_heavy_004.ogg"], -2.0, 0.95],
	"hit_player": [[IMPACT + "impactSoft_heavy_000.ogg", IMPACT + "impactSoft_heavy_001.ogg", IMPACT + "impactSoft_heavy_002.ogg", IMPACT + "impactSoft_heavy_003.ogg", IMPACT + "impactSoft_heavy_004.ogg"], -2.0, 0.9],
	"parry": [[IMPACT + "impactMetal_heavy_000.ogg", IMPACT + "impactMetal_heavy_001.ogg", IMPACT + "impactMetal_heavy_002.ogg", IMPACT + "impactMetal_heavy_003.ogg", IMPACT + "impactMetal_heavy_004.ogg"], -2.0, 1.1],
	"guard_block": [[IMPACT + "impactWood_heavy_000.ogg", IMPACT + "impactWood_heavy_001.ogg", IMPACT + "impactWood_heavy_002.ogg", IMPACT + "impactWood_heavy_003.ogg", IMPACT + "impactWood_heavy_004.ogg"], -3.0, 0.85],
	"enemy_death": [[IMPACT + "impactSoft_medium_000.ogg", IMPACT + "impactSoft_medium_001.ogg", IMPACT + "impactSoft_medium_002.ogg", IMPACT + "impactSoft_medium_003.ogg", IMPACT + "impactSoft_medium_004.ogg"], -3.0, 0.7],
	"boss_death": [[IMPACT + "impactBell_heavy_000.ogg", IMPACT + "impactBell_heavy_001.ogg", IMPACT + "impactBell_heavy_002.ogg"], -3.0, 0.6],
	"player_death": [[IMPACT + "impactBell_heavy_003.ogg", IMPACT + "impactBell_heavy_004.ogg"], -5.0, 0.55],
	"clue": [[RPG + "bookOpen.ogg", RPG + "bookFlip1.ogg", RPG + "bookFlip2.ogg", RPG + "bookFlip3.ogg"], -5.0, 1.0],
	"cache": [[RPG + "metalLatch.ogg", RPG + "doorOpen_1.ogg", RPG + "doorOpen_2.ogg"], -5.0, 1.0],
	"gem": [[UI + "glass_001.ogg", UI + "glass_002.ogg", UI + "glass_003.ogg", UI + "glass_004.ogg"], -6.0, 1.1],
	"coins": [[RPG + "handleCoins.ogg", RPG + "handleCoins2.ogg"], -4.0, 1.0],
	"floor_complete": [[IMPACT + "impactBell_heavy_000.ogg", IMPACT + "impactBell_heavy_001.ogg"], -6.0, 1.0],
	"confirm": [[UI + "confirmation_001.ogg", UI + "confirmation_002.ogg"], -6.0, 1.0],
	"fanfare": [[UI + "confirmation_004.ogg"], -4.0, 1.0],
	"error": [[UI + "error_004.ogg", UI + "error_006.ogg"], -8.0, 1.0],
	"click": [[UI + "click_001.ogg", UI + "click_002.ogg", UI + "click_003.ogg"], -9.0, 1.0],
	"summon": [[UI + "maximize_006.ogg", UI + "maximize_008.ogg"], -5.0, 0.9],
	"card_flip": [[RPG + "bookFlip1.ogg", RPG + "bookFlip2.ogg", RPG + "bookFlip3.ogg"], -7.0, 1.2],
	"reveal_common": [[UI + "tick_001.ogg", UI + "tick_002.ogg"], -8.0, 1.0],
	"reveal_rare": [[UI + "select_004.ogg", UI + "select_006.ogg"], -6.0, 1.0],
	"reveal_epic": [[UI + "glass_005.ogg", UI + "glass_006.ogg"], -4.0, 1.0],
	"reveal_legend": [[IMPACT + "impactBell_heavy_002.ogg"], -4.0, 1.15],
}


# Plays a non-positional interface sound. It is parented to the scene tree
# root and keeps playing while the game is paused and across scene changes.
static func play_ui(sound: String, pitch_scale: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not SOUNDS.has(sound):
		return
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if not _prepare(player, sound, pitch_scale):
		player.free()
		return
	tree.root.add_child(player)
	player.play()
	_free_when_done(player, true)


# Plays a positional sound in the world at a point. `context` is any node in
# the scene; the player is added to the current scene (or the context's
# parent) so it outlives nodes that are freed right away, such as enemies.
static func play_at(sound: String, position: Vector3, context: Node, pitch_scale: float = 1.0) -> void:
	if not is_instance_valid(context) or not context.is_inside_tree() or not SOUNDS.has(sound):
		return
	var host: Node = context.get_tree().current_scene
	if host == null:
		host = context.get_parent() if context.get_parent() != null else context.get_tree().root
	var player := AudioStreamPlayer3D.new()
	player.unit_size = 7.0
	player.max_distance = 45.0
	if not _prepare(player, sound, pitch_scale):
		player.free()
		return
	host.add_child(player)
	player.global_position = position
	player.play()
	_free_when_done(player, false)


static func _prepare(player: Node, sound: String, pitch_scale: float) -> bool:
	var entry: Array = SOUNDS[sound]
	var files: Array = entry[0]
	var stream := load(files[randi() % files.size()]) as AudioStream
	if stream == null:
		return false
	player.stream = stream
	player.volume_db = entry[1]
	player.pitch_scale = maxf(0.1, entry[2] * pitch_scale * randf_range(0.93, 1.07))
	return true


# Freed by a timer rather than the `finished` signal so players are also
# cleaned up when no audio device is available (headless runs).
static func _free_when_done(player: Node, process_always: bool) -> void:
	var length := 1.0
	if player.stream != null:
		length = player.stream.get_length() / player.pitch_scale
	var timer := player.get_tree().create_timer(length + 0.2, process_always)
	# Capture a weak reference: a lambda that captures a node freed early
	# (for example by a floor reload) logs an error when the timer fires.
	var handle: WeakRef = weakref(player)
	timer.timeout.connect(func():
		var node = handle.get_ref()
		if node != null:
			node.queue_free()
	)
