extends Node3D

# Visual body for a character or monster: loads an animated glTF model
# (Quaternius CC0 packs, see assets/CREDITS.md), sizes it to a target height
# and plays animation "states". Each state lists the clip names used by the
# different packs, so one table serves heroes and every monster family.
# Purely visual: gameplay never reads anything from here.

const STATE_ANIMATIONS := {
	"idle": ["Idle", "Flying_Idle"],
	"walk": ["Walk", "Fast_Flying", "Run"],
	"run": ["Run", "Run_Weapon", "Fast_Flying", "Walk"],
	"guard": ["Idle_Attacking", "Attacking_Idle", "Idle_Weapon", "Idle", "Flying_Idle"],
	"light": ["Sword_Attack", "Dagger_Attack", "Staff_Attack", "Attack", "Punch", "Bite_Front", "Headbutt"],
	"heavy": ["Sword_Attack2", "Dagger_Attack2", "Spell1", "Attack2", "Bow_Shoot", "Weapon", "Punch", "Bite_Front", "Headbutt"],
	"roll": ["Roll"],
	"hit": ["RecieveHit", "HitReact", "HitRecieve"],
	"death": ["Death"],
	# Boss wind-ups (each archetype gets its own anticipation pose).
	"swipe": ["Punch", "Weapon", "Headbutt", "Bite_Front", "Sword_Attack", "Attack"],
	"slam": ["Jump", "Weapon", "Headbutt", "Bite_Front", "Punch", "Attack2"],
	"crouch": ["Duck", "Jump_Idle", "Headbutt", "Bite_Front", "Punch"],
	"roar": ["Wave", "Yes", "No", "Dance", "Jump"],
	"stagger": ["HitReact", "RecieveHit", "HitRecieve", "Duck"],
}
const LOOPING_STATES := ["idle", "walk", "run", "guard"]
const ROT_SHADER = preload("res://shaders/zombie_rot.gdshader")
const BLEND := 0.15

var _model: Node3D
var _animations: AnimationPlayer
var _locomotion := "idle"
var _locomotion_speed := 1.0
var _action_left := 0.0
var _dead := false
var _free_after := -1.0
var _overlay: StandardMaterial3D
var _action_speed := 1.0
var _frozen := false
# Procedural pose layer (pitch of the whole body, radians; positive leans
# back): a held lean (sprint, jump tuck) plus a decaying kick (flinches,
# backsteps). Used where the model packs have no clip.
var _lean_hold := 0.0
var _lean_kick := 0.0
var _lean_kick_decay := 0.0
var _lean := 0.0
var _glow_on := false
var _flash: StandardMaterial3D
var _flash_left := 0.0


# Loads the model and scales it so its top sits at `height` metres. Returns
# false (and shows nothing) when the model cannot be loaded.
func load_model(path: String, height: float) -> bool:
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	_model = scene.instantiate() as Node3D
	if _model == null:
		return false
	# glTF characters face +Z; game bodies face -Z.
	_model.rotation.y = PI
	add_child(_model)
	var top := _model_top()
	if top > 0.01:
		_model.scale = Vector3.ONE * (height / top)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animations = players[0]
		for state in LOOPING_STATES:
			var clip := _clip_for(state)
			if not clip.is_empty():
				_animations.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play(_locomotion, _locomotion_speed)
	return true


func is_dead() -> bool:
	return _dead


func has_state(state: String) -> bool:
	return not _clip_for(state).is_empty()


# Looping movement state (idle, walk, run, guard). Waits for a one-shot
# action to finish before taking over.
func set_locomotion(state: String, speed: float = 1.0) -> void:
	var state_changed := state != _locomotion
	var speed_changed := not is_equal_approx(speed, _locomotion_speed)
	_locomotion = state
	_locomotion_speed = speed
	if _action_left > 0.0 or _dead:
		return
	if state_changed:
		_play(state, speed)
	elif speed_changed and _animations != null:
		# Same loop, new pace: change the playback speed without restarting
		# the clip (callers scale speed with movement every frame).
		var clip := _clip_for(state)
		if not clip.is_empty() and _animations.current_animation == clip:
			_animations.play(clip, BLEND, speed)
		elif not clip.is_empty():
			_play_clip(clip, speed)


# One-shot action (light, heavy, roll, hit). With a duration the clip is
# sped up or slowed to fit it. Returns false if the model lacks the clip.
func play_action(state: String, duration: float = 0.0) -> bool:
	if _dead or _animations == null:
		return false
	var clip := _clip_for(state)
	if clip.is_empty():
		return false
	var length := _animations.get_animation(clip).length
	var speed := 1.0
	if duration > 0.0 and length > 0.0:
		speed = clampf(length / duration, 0.5, 4.0)
	_play_clip(clip, speed)
	_action_left = length / speed
	return true


# Plays the death clip and holds its last pose. With free_after the rig
# removes itself a moment after the clip ends (used for enemy corpses).
func play_death(free_after: bool = false) -> void:
	if _dead:
		return
	_dead = true
	var length := 1.0
	var clip := _clip_for("death")
	if _animations != null and not clip.is_empty():
		_play_clip(clip, 1.0)
		length = _animations.get_animation(clip).length
	if free_after:
		_free_after = length + 0.8


# Additive glow over the whole model (wind-up telegraph, boss aura).
func set_glow(color: Color) -> void:
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_overlay.cull_mode = BaseMaterial3D.CULL_BACK
	_overlay.albedo_color = color
	_glow_on = true
	if _flash_left > 0.0:
		return
	for mesh in _meshes():
		mesh.material_overlay = _overlay


# Slows or speeds every clip (a boss holding a delayed swing uses ~0.05).
func set_action_speed(multiplier: float) -> void:
	_action_speed = maxf(0.0, multiplier)
	_apply_speed()


# Freezes the pose (Immobilize) without losing the current action.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	_apply_speed()


func _effective_speed() -> float:
	return 0.0 if _frozen else _action_speed


func _apply_speed() -> void:
	if _animations != null:
		_animations.speed_scale = _effective_speed()


# Desaturates the model and tints it (Dead Tide zombies). The glow overlay
# still works on top.
func apply_rot(tint: Color, amount: float = 0.8) -> void:
	for mesh: MeshInstance3D in _meshes():
		if mesh.mesh == null:
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface)
			var rot := ShaderMaterial.new()
			rot.shader = ROT_SHADER
			if original is BaseMaterial3D:
				rot.set_shader_parameter("base_color", original.albedo_color)
				if original.albedo_texture != null:
					rot.set_shader_parameter("albedo_tex", original.albedo_texture)
					rot.set_shader_parameter("has_texture", true)
			rot.set_shader_parameter("rot_tint", tint)
			rot.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))
			mesh.set_surface_override_material(surface, rot)


func clear_glow() -> void:
	_glow_on = false
	if _flash_left > 0.0:
		return
	for mesh in _meshes():
		mesh.material_overlay = null


# Visible flinch when struck: a short white flash and a jolt backwards that
# never interrupts the current clip (so wind-up telegraphs stay readable).
# With `interrupt` the "hit" clip also plays. Strength ~1 for a normal hit,
# up to ~2 for a heavy one. Bosses and enemies can call this from take_hit.
func play_hit_react(strength: float = 1.0, interrupt: bool = false) -> void:
	if _dead:
		return
	strength = clampf(strength, 0.2, 2.5)
	kick_lean(0.16 * strength, 0.12 + 0.08 * strength)
	_start_flash(0.1 + 0.03 * strength)
	if interrupt:
		play_action("hit", 0.3 + 0.15 * strength)


# Held body lean (radians, positive = back), eased toward each frame.
func set_lean(amount: float) -> void:
	_lean_hold = amount


# A lean impulse that decays to nothing over `seconds`.
func kick_lean(amount: float, seconds: float) -> void:
	_lean_kick = amount
	_lean_kick_decay = absf(amount) / maxf(seconds, 0.01)


# A frozen, glowing copy of the current pose left behind where the body
# stands (perfect-dodge afterimage). It fades out over `seconds`.
func spawn_afterimage(color: Color = Color(0.92, 0.96, 1.0, 0.5), seconds: float = 0.4) -> Node3D:
	if _model == null or not is_inside_tree():
		return null
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var ghost := _model.duplicate() as Node3D
	host.add_child(ghost)
	ghost.global_transform = _model.global_transform
	var players := ghost.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty() and _animations != null and not _animations.current_animation.is_empty():
		var copy: AnimationPlayer = players[0]
		copy.play(_animations.current_animation)
		copy.seek(_animations.current_animation_position, true)
		copy.pause()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.material_overlay = null
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := ghost.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(ghost.queue_free)
	return ghost


func get_lean() -> float:
	return _lean


func _start_flash(seconds: float) -> void:
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash.albedo_color = Color(0.4, 0.37, 0.33)
	_flash_left = seconds
	for mesh in _meshes():
		mesh.material_overlay = _flash


func _end_flash() -> void:
	_flash_left = 0.0
	var restore: Material = _overlay if _glow_on else null
	for mesh in _meshes():
		mesh.material_overlay = restore


func _update_procedural(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_end_flash()
	_lean_kick = move_toward(_lean_kick, 0.0, _lean_kick_decay * delta)
	var target := _lean_hold + _lean_kick
	_lean = lerpf(_lean, target, minf(1.0, delta * 18.0))
	rotation.x = _lean


func _process(delta: float) -> void:
	if not _dead:
		_update_procedural(delta)
	if _free_after >= 0.0:
		_free_after -= delta
		if _free_after < 0.0:
			queue_free()
		return
	if _action_left > 0.0:
		_action_left -= delta * _effective_speed()
		if _action_left <= 0.0 and not _dead:
			_play(_locomotion, _locomotion_speed)


func _play(state: String, speed: float) -> void:
	var clip := _clip_for(state)
	if not clip.is_empty():
		_play_clip(clip, speed)


func _play_clip(clip: String, speed: float) -> void:
	if _animations == null:
		return
	_animations.play(clip, BLEND, speed)
	# play() does not restart a clip that is already running (repeat attacks).
	_animations.seek(0.0, true)


func _clip_for(state: String) -> String:
	if _animations == null:
		return ""
	for clip in STATE_ANIMATIONS.get(state, []):
		if _animations.has_animation(clip):
			return clip
	return ""


func _meshes() -> Array:
	if _model == null:
		return []
	return _model.find_children("*", "MeshInstance3D", true, false)


# Highest point of the model's meshes in rig space (rest pose).
func _model_top() -> float:
	var top := 0.0
	for mesh: MeshInstance3D in _meshes():
		var to_rig := Transform3D.IDENTITY
		var node: Node = mesh
		while node != null and node != self:
			if node is Node3D:
				to_rig = (node as Node3D).transform * to_rig
			node = node.get_parent()
		var box: AABB = to_rig * mesh.get_aabb()
		top = maxf(top, box.end.y)
	return top
