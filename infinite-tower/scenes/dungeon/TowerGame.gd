extends Node3D

const HeroDatabase = preload("res://data/HeroDatabase.gd")
const InteractableScript = preload("res://scripts/systems/WorldInteractable.gd")
const EnemyScript = preload("res://scripts/battle/EnemyAgent.gd")
const PlayerScript = preload("res://scripts/player/PlayerController.gd")
const TowerProgressionCatalog = preload("res://scripts/systems/TowerCatalog.gd")
const RegionBuilderScript = preload("res://scripts/world/RegionBuilder.gd")
const SKY_SHADER = preload("res://shaders/sky.gdshader")
const SettingsScript = preload("res://scripts/ui/SettingsScreen.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const ButtonClickHook = preload("res://scripts/audio/ButtonClickHook.gd")
const SpecialFloors = preload("res://scripts/systems/SpecialFloors.gd")
const DeadTideScript = preload("res://scripts/battle/DeadTideDirector.gd")
const ChainRiteScript = preload("res://scripts/battle/ChainRite.gd")
const GraphicsSettings = preload("res://scripts/systems/GraphicsSettings.gd")
const Vfx = preload("res://scripts/visual/Vfx.gd")
const RegionGrade = preload("res://scripts/visual/RegionGrade.gd")
const FILM_GRAIN_SHADER = preload("res://shaders/film_grain.gdshader")
const PLAYER_SPAWN := Vector3(0, 1, 26)
const BOSS_SPAWN := Vector3(0, 1, -18)
const CACHE_POSITION := Vector3(27, 0, -25)
const CLUE_POSITION := Vector3(-22, 0.05, -18)
const WAYFARER_POSITION := Vector3(30, 0, 14)
const EXIT_POSITION := Vector3(0, 0, -66)

var floor_number := 1
var floor_data: Dictionary = {}
var player
var vitality_bar: ProgressBar
var stamina_bar: ProgressBar
var vitality_value: Label
var stamina_value: Label
var focus_pips: Array = []
var immobilize_bar: ProgressBar
var immobilize_value: Label
var boss_hud: Control
var boss_name_label: Label
var boss_health_bar: ProgressBar
var boss_posture_bar: ProgressBar
var floor_title: Label
var region_title: Label
var _title_card: VBoxContainer
var _title_tween: Tween
var _notice_serial := 0
# Extra vitality (percent) from resting in the camp, for this whole visit.
var _rest_bonus := 0
var prompt_label: Label
var prompt_panel: PanelContainer
var notice_label: Label
var panel: PanelContainer
var world_environment: WorldEnvironment
var sunlight: DirectionalLight3D
var sky_material: ShaderMaterial
var region_builder
var _enemies_remaining := 0
var _floor_finished := false
# Refreshed on save changes rather than deep-copying the save every frame.
var _rares_found_cache := 0
# Gems earned by this visit's first clear, shown on the completion panel.
var _last_clear_reward := 0
# Special floors (scripts/systems/SpecialFloors.gd).
var _tide                      # DeadTideDirector on floor 10
var _rite                      # ChainRite on floor 20 without Dragonbane
var _dragon                    # Vharzul
var _choice_pending := false   # floor 20 entrance choice is on screen
var _rite_accepted_floor := 0  # retries skip the choice once it was made
var _deflect_notice_ms := -100000
var lore_title: Label
var tide_timer_label: Label
var tide_bar: ProgressBar
# Graphics: saved options, the region's grade, lock-on depth of field, the
# grain overlay, and read-only observations of the player that drive the
# landing, wading, struck and spell effects (the player script is untouched).
var _graphics: Dictionary = {}
var _grade: Dictionary = {}
var _camera_attributes: CameraAttributesPractical
var _post_rect: ColorRect
var _dof_amount := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _last_health := -1.0
var _last_immobilize := 0.0
var _wade_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ButtonClickHook.new())
	_graphics = GraphicsSettings.load_settings()
	get_tree().node_added.connect(_on_node_added)
	_build_lighting()
	_build_hud()
	PlayerData.state_changed.connect(_refresh_rares_found)
	_rest_bonus = PlayerData.consume_rest_bonus()
	var state = PlayerData.get_state()
	load_floor(int(state.get("current_floor", 1)))
	if _rest_bonus > 0:
		_show_notice("Well rested: +%d%% vitality this climb" % _rest_bonus)
	else:
		_show_notice("Esc — pause, settings & controls")


func _process(delta: float) -> void:
	_update_depth_of_field(delta)
	if is_instance_valid(player) and is_instance_valid(prompt_label):
		if not get_tree().paused:
			_observe_player_vfx(delta)
		prompt_label.text = player.get_interaction_prompt()
		prompt_panel.visible = not prompt_label.text.is_empty() and not panel.visible
		vitality_bar.max_value = player.maximum_health
		vitality_bar.value = player.health
		stamina_bar.value = player.stamina
		vitality_value.text = "%d / %d" % [ceili(player.health), int(player.maximum_health)]
		stamina_value.text = "%d / %d" % [floori(player.stamina), int(stamina_bar.max_value)]
		_update_combat_hud()
	elif is_instance_valid(boss_hud):
		boss_hud.visible = false


# Focus pips, the Immobilize cooldown and the guardian's bars.
func _update_combat_hud() -> void:
	var charged: bool = player.is_charge_ready()
	for index in range(focus_pips.size()):
		var pip: Panel = focus_pips[index]
		var lit: bool = index < int(player.focus)
		pip.modulate = Color(1, 1, 1, 1) if lit else Color(1, 1, 1, 0.28)
		if lit and charged:
			# Pulse while a charged heavy is ready to release.
			pip.modulate = Color(1.4, 1.2, 0.8, 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 120.0)))
	var cooldown: float = player.immobilize_cooldown
	immobilize_bar.value = immobilize_bar.max_value - cooldown
	immobilize_value.text = "READY" if cooldown <= 0.0 else "%ds" % ceili(cooldown)
	# Overlays (the floor 20 choice, pause, journal) and the floor title card
	# take the screen: the guardian bar waits until they are gone.
	var hud_blocked: bool = panel.visible or _choice_pending or _title_card.modulate.a > 0.02
	if is_instance_valid(_tide) and not _tide.finished:
		_update_tide_hud()
		boss_hud.visible = not hud_blocked
		return
	tide_timer_label.visible = false
	tide_bar.visible = false
	var guardian = _living_boss()
	boss_hud.visible = guardian != null and not hud_blocked
	if guardian == null:
		return
	boss_health_bar.visible = true
	boss_name_label.text = str(guardian.boss_name).to_upper()
	if is_instance_valid(_rite) and guardian == _dragon:
		boss_name_label.text += "   ·   " + _rite.status_text()
	boss_health_bar.max_value = maxf(1.0, float(guardian.maximum_health))
	boss_health_bar.value = float(guardian.health)
	var has_posture: bool = "posture" in guardian and "posture_max" in guardian and float(guardian.posture_max) > 0.0
	boss_posture_bar.visible = has_posture
	if has_posture:
		boss_posture_bar.max_value = float(guardian.posture_max)
		boss_posture_bar.value = float(guardian.posture)


# Floor 10: the boss area shows the survival countdown instead.
func _update_tide_hud() -> void:
	boss_hud.visible = true
	boss_health_bar.visible = false
	boss_posture_bar.visible = false
	tide_timer_label.visible = true
	tide_bar.visible = true
	boss_name_label.text = "SURVIVE THE DEAD TIDE   ·   FELLED %d" % _tide.kills
	tide_timer_label.text = SpecialFloors.format_clock(_tide.time_left())
	tide_bar.max_value = SpecialFloors.TIDE_DURATION
	tide_bar.value = _tide.time_left()


func _living_boss():
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if is_instance_valid(enemy) and "boss" in enemy and enemy.boss and float(enemy.health) > 0.0:
			return enemy
	return null


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		if _choice_pending:
			# The floor 20 entrance choice must be answered.
			get_viewport().set_input_as_handled()
			return
		if panel.visible:
			if is_instance_valid(player) and player.health > 0.0:
				_close_overlay()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_J and not panel.visible:
		_show_journal()
	elif key_event.keycode == KEY_I and not panel.visible:
		_show_inventory()
	elif key_event.keycode == KEY_F9 and OS.is_debug_build() and is_instance_valid(_tide) and not panel.visible:
		# Debug builds only: skip a minute of the Dead Tide.
		_tide.fast_forward(60.0)
		_show_notice("[debug] Dead Tide +1:00 — %s left" % SpecialFloors.format_clock(_tide.time_left()))


func load_floor(requested_floor: int) -> bool:
	if requested_floor < 1 or requested_floor > TowerProgressionCatalog.FLOOR_LIMIT:
		_show_notice("The tower's first chapter ends at Floor 50.")
		return false
	var current_state = PlayerData.get_state()
	if requested_floor > int(current_state.get("highest_unlocked_floor", 1)):
		_show_notice("That floor has not been unlocked yet.")
		return false
	if not PlayerData.enter_floor(requested_floor):
		_show_notice("Progress could not be saved. The floor was not entered.")
		return false
	floor_number = requested_floor
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_data = TowerProgressionCatalog.get_floor(floor_number)
	_floor_finished = floor_number in PlayerData.get_state()["completed_floors"]
	_last_clear_reward = 0
	_clear_world()
	_build_region()
	_spawn_player()
	_spawn_floor_content()
	_update_hud_title()
	_refresh_rares_found()
	if _floor_finished:
		call_deferred("_show_completion_panel")
	return true


func _refresh_rares_found() -> void:
	_rares_found_cache = LootDirector.interval_rares_found(floor_number)


func _clear_world() -> void:
	for child in get_children():
		if child is WorldEnvironment or child is DirectionalLight3D or child is CanvasLayer:
			continue
		# Old nodes may run one more physics step before being freed; cut
		# their signals so they cannot complete or fail the new floor.
		if child is EnemyAgent and child.defeated.is_connected(_on_enemy_defeated):
			child.defeated.disconnect(_on_enemy_defeated)
		if child == player:
			if player.defeated.is_connected(_on_player_defeated):
				player.defeated.disconnect(_on_player_defeated)
			player.set_controls_enabled(false)
		child.remove_from_group("tower_enemies")
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.queue_free()
	_enemies_remaining = 0
	_tide = null
	_rite = null
	_dragon = null
	_choice_pending = false


func _build_lighting() -> void:
	world_environment = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.08
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.6
	environment.ssil_enabled = true
	# Depth fog hazes distant mountains and landmarks (aerial perspective);
	# volumetric fog adds light shafts and atmosphere near the player.
	environment.fog_enabled = true
	environment.fog_aerial_perspective = 0.55
	environment.fog_sky_affect = 0.25
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_length = 140.0
	environment.volumetric_fog_sky_affect = 0.35
	# Forward scattering: haze glows toward the sun and shafts read clearly.
	environment.volumetric_fog_anisotropy = 0.7
	environment.volumetric_fog_temporal_reprojection_enabled = true
	# Grade (contrast, saturation, split-tone LUT) is set per region.
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.05
	world_environment.environment = environment
	# Far depth of field, faded in while locked on to frame the target.
	_camera_attributes = CameraAttributesPractical.new()
	_camera_attributes.dof_blur_far_enabled = false
	_camera_attributes.dof_blur_far_transition = 14.0
	_camera_attributes.dof_blur_amount = 0.0
	world_environment.camera_attributes = _camera_attributes
	add_child(world_environment)
	sunlight = DirectionalLight3D.new()
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 120.0
	sunlight.light_volumetric_fog_energy = 1.6
	add_child(sunlight)
	# Film grain and vignette: a multiply overlay under the HUD.
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	_post_rect = ColorRect.new()
	_post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_material := ShaderMaterial.new()
	post_material.shader = FILM_GRAIN_SHADER
	_post_rect.material = post_material
	post_layer.add_child(_post_rect)
	_apply_graphics(_graphics)


# Applies saved graphics options (also live, from the pause menu settings).
func _apply_graphics(settings: Dictionary) -> void:
	_graphics = settings
	GraphicsSettings.apply_viewport(get_viewport(), settings)
	var environment := world_environment.environment
	GraphicsSettings.apply_environment(environment, settings)
	# Reflections make rain puddles read as water; worth it on Low only there.
	var rainy: bool = region_builder != null and String(region_builder.profile.get("weather", "")) == "rain"
	environment.ssr_enabled = settings["gi"] == "high" or (settings["gi"] == "low" and rainy)
	environment.ssr_max_steps = 48
	environment.ssr_fade_in = 0.2
	Vfx.intensity = 0.6 if settings["gi"] == "off" else 1.0
	_post_rect.visible = bool(settings.get("grain", true))


# Sky, sun, fog and grading follow the floor's region profile.
func _apply_region_lighting(profile: Dictionary) -> void:
	var environment := world_environment.environment
	sky_material.set_shader_parameter("top_color", profile["sky_top"])
	sky_material.set_shader_parameter("horizon_color", profile["sky_horizon"])
	sky_material.set_shader_parameter("ground_horizon", profile["ground_horizon"])
	sky_material.set_shader_parameter("ground_bottom", profile["ground_bottom"])
	sky_material.set_shader_parameter("sun_tint", profile["sun_color"])
	sky_material.set_shader_parameter("star_amount", 1.0 if profile["stars"] else 0.0)
	sky_material.set_shader_parameter("cloud_amount", 0.15 if profile["stars"] else 0.6)
	sky_material.set_shader_parameter("noise_tex", region_builder.get_noise_texture())
	environment.ambient_light_color = profile["ambient"]
	environment.ambient_light_energy = float(profile["ambient_energy"]) * 1.6
	_grade = RegionGrade.get_grade(int(floor_data.get("region_index", 0)))
	var haze := float(_grade["fog"])
	environment.fog_light_color = profile["fog_color"]
	environment.fog_density = float(profile["fog_density"]) * 0.28 * minf(haze, 1.8)
	environment.volumetric_fog_density = float(profile["fog_density"]) * haze
	environment.volumetric_fog_albedo = profile["fog_color"]
	environment.volumetric_fog_emission = profile["fog_emission"]
	environment.adjustment_saturation = _grade["sat"]
	environment.adjustment_contrast = _grade["contrast"]
	environment.adjustment_brightness = _grade["bright"]
	environment.adjustment_color_correction = RegionGrade.make_lut(_grade)
	sunlight.rotation_degrees = Vector3(profile["sun_pitch"], profile["sun_yaw"], 0)
	sunlight.light_color = profile["sun_color"]
	sunlight.light_energy = profile["sun_energy"]
	sunlight.light_volumetric_fog_energy = _grade["shafts"]
	Vfx.region_material = _grade["impact"]
	_add_ground_mist(profile)
	_add_arena_flames()
	_apply_graphics(_graphics)


# Low mist pooled over the ground: a fog volume that thins with height.
func _add_ground_mist(profile: Dictionary) -> void:
	if float(_grade.get("mist", 0.0)) <= 0.0:
		return
	var mist := FogVolume.new()
	mist.name = "Ground Mist"
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist.size = Vector3(150, 6, 150)
	mist.position = Vector3(0, 0.6, 0)
	var material := FogMaterial.new()
	material.density = _grade["mist"]
	material.albedo = Color(profile["fog_color"]).lightened(0.2)
	material.height_falloff = 0.5
	material.edge_fade = 0.4
	mist.material = material
	region_builder.add_child(mist)


# Fire regions: flames lick the guardian arena's rim (purely visual).
func _add_arena_flames() -> void:
	if not _grade.get("flames", false) or not floor_data.get("boss_floor", false):
		return
	for index in range(10):
		var angle := TAU * index / 10.0 + 0.3
		var spot := BOSS_SPAWN + Vector3(cos(angle), 0.0, sin(angle)) * 24.0
		spot.y = region_builder.height_at(spot.x, spot.z)
		var flame := Vfx.make_edge_flame()
		flame.position = spot
		flame.rotation.y = -angle
		region_builder.add_child(flame)
		if index % 2 == 0:
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.5, 0.18)
			glow.light_energy = 2.0
			glow.omni_range = 7.0
			glow.position = spot + Vector3.UP * 0.8
			region_builder.add_child(glow)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	# A compact cluster in the bottom-left corner: thin stacked bars, each
	# with a small caption and "current / max", then the Focus pips.
	var bars := VBoxContainer.new()
	bars.anchor_top = 1.0
	bars.anchor_bottom = 1.0
	bars.offset_left = 30
	bars.offset_top = -28
	bars.offset_bottom = -28
	bars.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bars.add_theme_constant_override("separation", 3)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)
	vitality_bar = _add_hud_bar(bars, "VITALITY", Color("#b3343a"), Vector2(280, 5))
	vitality_value = vitality_bar.get_meta("value_label")
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	bars.add_child(gap)
	stamina_bar = _add_hud_bar(bars, "STAMINA", Color("#c9a24a"), Vector2(200, 3))
	stamina_value = stamina_bar.get_meta("value_label")
	stamina_bar.max_value = 100.0
	_build_combat_hud(root, bars)
	# Floor title card: shown once when a floor is entered, then fades away.
	_title_card = VBoxContainer.new()
	_title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title_card.position = Vector2(-300, 64)
	_title_card.custom_minimum_size = Vector2(600, 0)
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_card.modulate.a = 0.0
	root.add_child(_title_card)
	floor_title = Label.new()
	floor_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_title.add_theme_font_override("font", _inscription_font(6))
	floor_title.add_theme_font_size_override("font_size", 40)
	floor_title.add_theme_color_override("font_color", Color("#f4ead8"))
	floor_title.add_theme_constant_override("outline_size", 8)
	floor_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	floor_title.add_theme_constant_override("shadow_offset_y", 3)
	_title_card.add_child(floor_title)
	region_title = Label.new()
	region_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_title.add_theme_font_override("font", _inscription_font(3))
	region_title.add_theme_font_size_override("font_size", 19)
	region_title.add_theme_constant_override("outline_size", 6)
	region_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	region_title.add_theme_constant_override("shadow_offset_y", 2)
	_title_card.add_child(region_title)
	# One line of lore for the special guardians: why they are here.
	lore_title = Label.new()
	lore_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_title.custom_minimum_size = Vector2(600, 0)
	lore_title.add_theme_font_override("font", _inscription_font(1))
	lore_title.add_theme_font_size_override("font_size", 15)
	lore_title.add_theme_color_override("font_color", Color("#e8dcc4"))
	lore_title.add_theme_constant_override("outline_size", 5)
	lore_title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.85))
	_title_card.add_child(lore_title)
	# Interaction prompt: a small centred plate above the guardian bar.
	var bottom := PanelContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -280
	bottom.offset_right = 280
	bottom.offset_top = -176
	bottom.offset_bottom = -140
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_stylebox_override("panel", _plate_style(0.6))
	root.add_child(bottom)
	prompt_panel = bottom
	bottom.visible = false
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_override("font", _inscription_font(1, 500))
	prompt_label.add_theme_font_size_override("font_size", 15)
	prompt_label.add_theme_color_override("font_color", Color("#efe4cc"))
	bottom.add_child(prompt_label)
	# Centred band across the top: long clue texts wrap instead of running
	# off-screen, and stay clear of the floor title card below.
	notice_label = Label.new()
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice_label.offset_top = 22
	notice_label.offset_left = 220
	notice_label.offset_right = -220
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.add_theme_color_override("font_color", Color("#f3d6a0"))
	notice_label.add_theme_font_override("font", _inscription_font(1))
	notice_label.add_theme_font_size_override("font_size", 18)
	notice_label.add_theme_constant_override("outline_size", 5)
	notice_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.8))
	root.add_child(notice_label)
	# Overlays (pause, settings, journal, results) stay centred at any size.
	var overlay_center := CenterContainer.new()
	overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay_center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 200)
	panel.visible = false
	panel.theme = _overlay_theme()
	overlay_center.add_child(panel)


func _build_region() -> void:
	region_builder = RegionBuilderScript.new()
	region_builder.name = "Region"
	add_child(region_builder)
	var seed_text = "region:%d:%d" % [PlayerData.get_state()["world_seed"], floor_number]
	region_builder.build(int(floor_data["region_index"]), seed_text.hash(), _reserved_points())
	_apply_region_lighting(region_builder.profile)


# Spots where the player, enemies, caches, clues, allies and the exit appear.
func _reserved_points() -> Array:
	var points: Array = [
		PLAYER_SPAWN, BOSS_SPAWN, CACHE_POSITION, CLUE_POSITION,
		WAYFARER_POSITION, EXIT_POSITION
	]
	var count = _regular_enemy_count()
	for index in range(count):
		points.append(_regular_enemy_position(index, count))
	if floor_number == SpecialFloors.DRAGON_FLOOR:
		points.append_array(SpecialFloors.rite_pillar_positions())
	if not _pieces_here().is_empty():
		points.append(SpecialFloors.PIECE_POSITION)
	return points


# Dragonbane pieces hidden on this floor in this world (floors 16-19).
func _pieces_here() -> Array:
	return SpecialFloors.pieces_on_floor(floor_number, int(PlayerData.get_state().get("world_seed", 0)))


func _regular_enemy_count() -> int:
	return 2 + floori(float(floor_number - 1) / 12.0)


func _regular_enemy_position(index: int, count: int) -> Vector3:
	var angle = TAU * float(index) / float(count)
	return Vector3(cos(angle) * 20.0, 1, -12 + sin(angle) * 20.0)


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.position = PLAYER_SPAWN
	var hero = _selected_hero_data()
	var bonuses = _equipped_bonuses()
	hero["hp"] = int((int(hero.get("hp", 140)) + bonuses["defense"] * 7) * (1.0 + _rest_bonus / 100.0))
	hero["atk"] = int(hero.get("atk", 22)) + bonuses["attack"]
	hero["def"] = int(hero.get("def", 8)) + bonuses["defense"]
	hero["effects"] = bonuses["effects"]
	player.configure_hero(hero)
	player.health_changed.connect(_on_player_health_changed)
	player.defeated.connect(_on_player_defeated)
	_add_world_node(player)
	player.add_child(region_builder.make_weather())
	var ambient := Vfx.make_ambient(String(_grade.get("ambient", "")))
	if ambient != null:
		player.add_child(ambient)
	_last_health = -1.0
	_last_immobilize = 0.0
	_was_on_floor = true
	_fall_speed = 0.0


func _selected_hero_data() -> Dictionary:
	var selected_id = PlayerData.get_state().get("selected_hero_instance_id", "")
	var owned_instances = GachaManager.get_owned_hero_instances()
	if selected_id.is_empty() and not owned_instances.is_empty():
		selected_id = owned_instances[0].get("instance_id", "")
	var selected_instance = GachaManager.get_hero_instance(selected_id)
	var hero_id = selected_instance.get("hero_id", "aurelia")
	var base: Dictionary = HeroDatabase.get_heroes()[0]
	for hero in HeroDatabase.get_heroes():
		if hero["id"] == hero_id:
			base = hero
	# Each level earned (for example by training in the camp) adds 3% to the
	# hero's core stats.
	var hero := base.duplicate(true)
	var level_scale = 1.0 + 0.03 * float(maxi(int(selected_instance.get("level", 1)), 1) - 1)
	for stat in ["hp", "atk", "def"]:
		hero[stat] = int(round(float(hero.get(stat, 0)) * level_scale))
	return hero


func _equipped_bonuses() -> Dictionary:
	var result = {"attack": 0, "defense": 0, "effects": []}
	var state = PlayerData.get_state()
	var equipped: Dictionary = state.get("equipped", {})
	var inventory: Array = state.get("inventory", [])
	for item in inventory:
		if item.get("instance_id", "") in equipped.values():
			result["attack"] += int(item.get("attack", 0))
			result["defense"] += int(item.get("defense", 0))
			result["effects"].append(item.get("id", ""))
	return result


func _spawn_floor_content() -> void:
	var special := String(floor_data.get("special", ""))
	if special == "dead_tide" and not _floor_finished:
		_start_dead_tide()
	elif special == "dragon" and not _floor_finished:
		_dragon = _spawn_enemy(BOSS_SPAWN, true, floor_data["boss"])
		_start_dragon_floor()
	elif floor_data["boss_floor"] and not _floor_finished:
		_spawn_enemy(BOSS_SPAWN, true, floor_data["boss"])
	elif not floor_data["boss_floor"]:
		if not _floor_finished:
			var count = _regular_enemy_count()
			for index in range(count):
				_spawn_enemy(_regular_enemy_position(index, count), false)
		_add_clue_site()
		if int(floor_data["clue_stage"]) == 3:
			_add_wayfarer_npc()
		_add_dragonbane_pieces()
	_add_hidden_equipment_site()
	_add_exit_portal()


func _spawn_enemy(position: Vector3, is_boss: bool, boss_data: Dictionary = {}) -> EnemyAgent:
	var enemy: EnemyAgent = EnemyScript.new()
	enemy.position = position
	enemy.configure_enemy(player, floor_number, is_boss, boss_data)
	enemy.defeated.connect(_on_enemy_defeated)
	_add_world_node(enemy)
	_enemies_remaining += 1
	return enemy


# --- Floor 10: The Dead Tide ------------------------------------------------------

func _start_dead_tide() -> void:
	var state = PlayerData.get_state()
	var journal: Dictionary = state["investigation_journal"]
	var region := int(floor_data["region_index"])
	var clues := 0
	for stage in range(4):
		if journal.has("boss_%d_clue_%d" % [region, stage]):
			clues += 1
	var allies := int(state["faction_relations"].get("wayfarer_covenant", 0))
	_tide = DeadTideScript.new()
	_tide.name = "DeadTide"
	_tide.setup(player, clues, allies)
	_tide.floor_number = floor_number
	_tide.world = self
	_tide.ground_height = region_builder.height_at
	_tide.survived.connect(_on_tide_survived)
	_tide.surge.connect(func(_index: int):
		_show_notice("A brute pack breaks through the trees!")
	)
	_tide.tier_changed.connect(func(tier: int):
		_show_notice("The tide swells. (%d / %d)" % [tier + 1, SpecialFloors.TIDE_TIERS.size()])
	)
	_add_world_node(_tide)
	if clues + allies > 0:
		_show_notice("What you learned thins the tide: fewer of the dead find you.")


func _on_tide_survived() -> void:
	SoundBank.play_ui("fanfare")
	_show_notice("The Dead Tide recedes into the canopy. You endured.")
	_complete_floor()


# --- Floor 20: Vharzul and Dragonbane ------------------------------------------------

func _start_dragon_floor() -> void:
	if not is_instance_valid(_dragon):
		return
	_dragon.deflected.connect(_on_dragon_deflected)
	if PlayerData.has_dragonbane():
		_show_notice("Dragonbane hums in your hand. Strike the glowing seam beneath its throat.")
	elif _rite_accepted_floor == floor_number:
		_start_chain_rite()
	else:
		call_deferred("_show_dragon_choice")


func _show_dragon_choice() -> void:
	if not is_instance_valid(_dragon) or not is_instance_valid(player):
		return
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	_choice_pending = true
	# The title card would show through the panel.
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_card.modulate.a = 0.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var title := Label.new()
	title.text = SpecialFloors.DRAGON_NAME.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var warning := Label.new()
	warning.text = SpecialFloors.DRAGON_WARNING
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(440, 0)
	warning.add_theme_color_override("font_color", Color("#f3d6a0"))
	layout.add_child(warning)
	var hints := Label.new()
	hints.text = _piece_hint_text()
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hints.custom_minimum_size = Vector2(440, 0)
	layout.add_child(hints)
	if PlayerData.can_forge_dragonbane():
		var forge := Button.new()
		forge.text = "FORGE DRAGONBANE AND FIGHT"
		forge.pressed.connect(func():
			if PlayerData.forge_dragonbane():
				_choice_pending = false
				_dragon.dragonbane = true
				SoundBank.play_ui("fanfare")
				_close_overlay()
				_show_notice("Dragonbane is forged. Strike the glowing seam beneath its throat.")
		)
		layout.add_child(forge)
	var target := _first_missing_piece_floor()
	var retreat := Button.new()
	retreat.text = "RETURN TO FLOOR %d AND SEEK THE PIECES" % target
	retreat.pressed.connect(_retreat_from_dragon.bind(target))
	layout.add_child(retreat)
	var rite := Button.new()
	rite.text = "BEGIN THE CHAIN RITE  (VERY HARD)"
	rite.tooltip_text = "Light four chain pillars while Vharzul attacks to drag it down for a few seconds."
	rite.pressed.connect(_accept_chain_rite)
	layout.add_child(rite)
	var explain := Label.new()
	explain.text = "Chain Rite: stand in each pillar's circle until it lights. When all four burn, the chains drag Vharzul down and its scales can be cut, briefly. It breaks free angrier every time."
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.custom_minimum_size = Vector2(440, 0)
	explain.add_theme_font_size_override("font_size", 13)
	layout.add_child(explain)


func _piece_hint_text() -> String:
	var lines: Array = []
	var seed_value := int(PlayerData.get_state().get("world_seed", 0))
	for piece_id in SpecialFloors.DRAGONBANE_PIECES:
		var found: bool = PlayerData.has_dragonbane_piece(piece_id)
		var hint := String(SpecialFloors.PIECES[piece_id]["hint"]).get_slice(" - ", 1)
		lines.append("%s %s — floor %d%s" % [
			"[found]" if found else "[  ]", SpecialFloors.piece_name(piece_id),
			SpecialFloors.piece_floor(piece_id, seed_value),
			"" if found else ": " + hint
		])
	return "\n".join(PackedStringArray(lines))


# The lowest floor still hiding a piece (floor 19 if all are found but the
# blade is not forged yet, so the forge can be reached from the inventory).
func _first_missing_piece_floor() -> int:
	var seed_value := int(PlayerData.get_state().get("world_seed", 0))
	var best := SpecialFloors.DRAGON_FLOOR - 1
	for piece_id in SpecialFloors.DRAGONBANE_PIECES:
		if not PlayerData.has_dragonbane_piece(piece_id):
			best = mini(best, SpecialFloors.piece_floor(piece_id, seed_value))
	return best


func _retreat_from_dragon(target: int) -> void:
	_choice_pending = false
	if load_floor(target):
		panel.visible = false
	else:
		_choice_pending = true


func _accept_chain_rite() -> void:
	_choice_pending = false
	_rite_accepted_floor = floor_number
	_close_overlay()
	_start_chain_rite()
	_show_notice("Light the four chain pillars. Vharzul will not let you.")


func _start_chain_rite() -> void:
	if not is_instance_valid(_dragon) or is_instance_valid(_rite) or _dragon.dragonbane:
		return
	_rite = ChainRiteScript.new()
	_rite.name = "ChainRite"
	_rite.setup(_dragon, player)
	_rite.ground_height = region_builder.height_at
	_rite.bound.connect(func(_cycle: int):
		_show_notice("The chains drag Vharzul down! Strike now!")
	)
	_rite.broke_free.connect(func(cycle: int):
		_show_notice("Vharzul tears free, angrier. The pillars go dark. (Binding %d)" % (cycle + 1))
	)
	_add_world_node(_rite)


func _on_dragon_deflected(_enemy, reason: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _deflect_notice_ms < 5000:
		return
	_deflect_notice_ms = now
	if reason == "airborne":
		_show_notice("Vharzul is out of reach in the sky. Wait for it to land.")
	elif is_instance_valid(_rite):
		_show_notice("No effect — the scales turn your blade. Light the chain pillars to drag it down.")
	else:
		_show_notice("No effect — Vharzul's scales turn every blade. Forge Dragonbane from the pieces on floors 16-19.")


# --- Dragonbane pieces (floors 16-19) -------------------------------------------------

func _add_dragonbane_pieces() -> void:
	for piece_id in _pieces_here():
		if PlayerData.has_dragonbane_piece(piece_id):
			continue
		var shrine = InteractableScript.new()
		shrine.name = "Dragonbane Shrine"
		shrine.interaction_kind = "dragonbane"
		shrine.interaction_id = piece_id
		shrine.prompt_text = "Take the %s" % SpecialFloors.piece_name(piece_id)
		shrine.position = SpecialFloors.PIECE_POSITION
		shrine.concealed = false
		var plinth := MeshInstance3D.new()
		var base := CylinderMesh.new()
		base.top_radius = 0.7
		base.bottom_radius = 0.9
		base.height = 1.0
		plinth.mesh = base
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#5b5149")
		plinth.material_override = stone
		plinth.position.y = 0.5
		shrine.add_child(plinth)
		var relic := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.45, 0.8, 0.2)
		relic.mesh = prism
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("#ffb45a")
		glow.emission_enabled = true
		glow.emission = Color("#ff8a2a")
		glow.emission_energy_multiplier = 2.5
		relic.material_override = glow
		relic.position.y = 1.5
		shrine.add_child(relic)
		var light := OmniLight3D.new()
		light.light_color = Color("#ff9a40")
		light.omni_range = 8.0
		light.light_energy = 2.0
		light.position.y = 1.8
		shrine.add_child(light)
		shrine.activated.connect(_on_interactable_activated)
		_add_world_node(shrine)
		_show_notice("Something old and draconic hums to the west.")

func _add_clue_site() -> void:
	var clue_stage = int(floor_data["clue_stage"])
	var boss_index = int(floor_data["region_index"])
	var clue_id = "boss_%d_clue_%d" % [boss_index, clue_stage]
	if PlayerData.get_state()["investigation_journal"].has(clue_id):
		return
	var interactable = InteractableScript.new()
	interactable.name = "Weathered Investigation Marker"
	interactable.interaction_kind = "clue"
	interactable.interaction_id = clue_id
	interactable.prompt_text = "Investigate the weathered marker"
	interactable.position = CLUE_POSITION
	interactable.concealed = false
	var visual := MeshInstance3D.new()
	var stone := CylinderMesh.new()
	stone.top_radius = 0.8
	stone.bottom_radius = 1.05
	stone.height = 1.25
	visual.mesh = stone
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#716254")
	visual.material_override = material
	visual.position.y = 0.65
	interactable.add_child(visual)
	interactable.activated.connect(_on_interactable_activated)
	_add_world_node(interactable)


func _add_hidden_equipment_site() -> void:
	var record = LootDirector.generate_hidden_equipment(floor_number, "hidden_cache_a")
	if record.is_empty() or record.get("collected", false):
		return
	var item: Dictionary = record["item"]
	var interactable = InteractableScript.new()
	interactable.name = "Concealed Equipment Cache"
	interactable.interaction_kind = "equipment"
	interactable.interaction_id = "hidden_cache_a"
	interactable.prompt_text = "Search the concealed cache"
	interactable.position = CACHE_POSITION
	interactable.concealed = true
	var box := MeshInstance3D.new()
	var chest := BoxMesh.new()
	chest.size = Vector3(1.45, 0.9, 0.9)
	box.mesh = chest
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#aa8650") if item["rarity"] == "rare" else Color("#554743")
	box.material_override = material
	box.position.y = 0.48
	interactable.add_child(box)
	interactable.activated.connect(_on_interactable_activated)
	_add_world_node(interactable)


func _add_wayfarer_npc() -> void:
	var quest_id = "wayfarer_aid_%d" % floor_data["region_index"]
	if PlayerData.get_state()["quests"].get(quest_id, "") == "complete":
		return
	var npc = InteractableScript.new()
	npc.name = "Wayfarer Ally"
	npc.interaction_kind = "wayfarer"
	npc.interaction_id = quest_id
	npc.prompt_text = "Speak with the stranded wayfarer"
	npc.position = WAYFARER_POSITION
	npc.concealed = false
	var visual := MeshInstance3D.new()
	var shape := CapsuleMesh.new()
	shape.radius = 0.4
	shape.height = 1.65
	visual.mesh = shape
	visual.position.y = 0.82
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#78918b")
	visual.material_override = material
	npc.add_child(visual)
	npc.activated.connect(_on_interactable_activated)
	_add_world_node(npc)


func _add_exit_portal() -> void:
	var exit = InteractableScript.new()
	exit.name = "Tower Passage"
	exit.interaction_kind = "exit"
	exit.interaction_id = str(floor_number)
	exit.prompt_text = "Enter the next passage"
	exit.position = EXIT_POSITION
	exit.concealed = false
	for offset in [-1.25, 1.25]:
		var post := MeshInstance3D.new()
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.45, 4.5, 0.45)
		post.mesh = pillar
		post.position = Vector3(offset, 2.25, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#94816d")
		post.material_override = material
		exit.add_child(post)
	var lintel := MeshInstance3D.new()
	var arch := BoxMesh.new()
	arch.size = Vector3(3.0, 0.5, 0.6)
	lintel.mesh = arch
	lintel.position.y = 4.4
	var lintel_material := StandardMaterial3D.new()
	lintel_material.albedo_color = Color("#94816d")
	lintel.material_override = lintel_material
	exit.add_child(lintel)
	exit.activated.connect(_on_interactable_activated)
	_add_world_node(exit)


func _on_interactable_activated(interactable) -> void:
	match interactable.interaction_kind:
		"clue":
			var clue = floor_data["clue"]
			var entry = {
				"floor": floor_number,
				"stage": floor_data["clue_stage"],
				"region": floor_data["region"],
				"text": clue
			}
			if PlayerData.record_discovery(interactable.interaction_id, entry):
				var clue_reward = PlayerData.last_gem_reward
				SoundBank.play_ui("clue")
				if clue_reward > 0:
					SoundBank.play_ui("gem")
				_show_notice(clue + ("\n+%d gems" % clue_reward if clue_reward > 0 else ""))
				interactable.queue_free()
			else:
				_show_notice("The discovery could not be recorded.")
		"equipment":
			if LootDirector.collect_hidden_equipment(floor_number, interactable.interaction_id):
				var record = PlayerData.get_state()["floor_loot"].get(
					"%d:%s" % [floor_number, interactable.interaction_id], {}
				)
				var item: Dictionary = record.get("item", {})
				SoundBank.play_ui("cache")
				SoundBank.play_ui("coins")
				_show_notice("Found %s · %s" % [item.get("name", "equipment"), item.get("rarity", "common")])
				interactable.queue_free()
			else:
				_show_notice("This cache has already been searched.")
		"wayfarer":
			var state = PlayerData.get_state()
			var quests: Dictionary = state["quests"]
			if quests.get(interactable.interaction_id, "") == "complete":
				_show_notice("The wayfarer has already joined your cause.")
				return
			quests[interactable.interaction_id] = "complete"
			state["quests"] = quests
			var relations: Dictionary = state["faction_relations"]
			relations["wayfarer_covenant"] = int(relations.get("wayfarer_covenant", 0)) + 1
			state["faction_relations"] = relations
			if PlayerData.replace_state(state):
				player.heal(30.0)
				SoundBank.play_ui("confirm")
				_show_notice("The Wayfarer Covenant joins your ascent and shares supplies.")
				interactable.queue_free()
			else:
				_show_notice("The agreement could not be saved.")
		"dragonbane":
			var piece_id: String = interactable.interaction_id
			if PlayerData.collect_dragonbane_piece(piece_id):
				var owned: int = PlayerData.dragonbane_pieces().size()
				SoundBank.play_ui("reveal_legend")
				var text := "Found the %s (%d / 3)." % [SpecialFloors.piece_name(piece_id), owned]
				if PlayerData.can_forge_dragonbane():
					text += " All pieces found: forge Dragonbane from the inventory (I)."
				_show_notice(text)
				interactable.queue_free()
			else:
				_show_notice("The piece could not be saved.")
		"exit":
			if String(floor_data.get("special", "")) == "dead_tide" and not _floor_finished:
				_show_notice("Survive the Dead Tide to open the passage.")
			elif floor_data["boss_floor"] and not _floor_finished:
				_show_notice("Defeat the floor guardian to open the passage.")
			elif not _floor_finished:
				_complete_floor()
			else:
				_show_completion_panel()


func _on_enemy_defeated(enemy: EnemyAgent) -> void:
	_enemies_remaining = maxi(0, _enemies_remaining - 1)
	if enemy.boss:
		_show_notice("%s has fallen." % enemy.boss_name)
		_complete_floor()


func _complete_floor() -> void:
	if _floor_finished:
		_show_completion_panel()
		return
	if _enemies_remaining > 0 and not _can_use_stealth_exit():
		_show_notice("Defeat the remaining enemies before leaving this floor.")
		return
	if not PlayerData.complete_floor(floor_number):
		_show_notice("Progress could not be saved; this floor remains active.")
		return
	_floor_finished = true
	_last_clear_reward = PlayerData.last_gem_reward
	SoundBank.play_ui("floor_complete")
	SoundBank.play_ui("fanfare")
	if _last_clear_reward > 0:
		SoundBank.play_ui("gem")
	_show_completion_panel()


func _can_use_stealth_exit() -> bool:
	var enemies_alerted := false
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if is_instance_valid(enemy) and enemy.boss_floor == floor_number and enemy.alerted:
			enemies_alerted = true
			break
	return TowerProgressionCatalog.can_stealth_exit(
		floor_data.get("boss_floor", false),
		player.is_crouching(),
		enemies_alerted
	)


func _show_completion_panel() -> void:
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	if floor_number == TowerProgressionCatalog.FLOOR_LIMIT:
		title.text = "THE TOWER REMEMBERS"
	else:
		title.text = "FLOOR %d COMPLETE" % floor_number
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var summary := Label.new()
	summary.text = (
		"The Starless Sovereign is gone and the drain has stopped. Your world can breathe again, for now."
		if floor_number == TowerProgressionCatalog.FLOOR_LIMIT
		else "The passage to Floor %d is open." % mini(floor_number + 1, TowerProgressionCatalog.FLOOR_LIMIT)
	)
	if _last_clear_reward > 0:
		summary.text += "\nFirst clear reward: +%d gems" % _last_clear_reward
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(summary)
	var button := Button.new()
	button.text = "RETURN TO MAIN MENU" if floor_number == TowerProgressionCatalog.FLOOR_LIMIT else "ASCEND TO FLOOR %d" % (floor_number + 1)
	button.pressed.connect(_on_completion_button)
	layout.add_child(button)
	# Finishing a floor must not strand its unsearched caches or clues.
	var explore := Button.new()
	explore.text = "KEEP EXPLORING  (ESC)"
	explore.pressed.connect(_close_overlay)
	layout.add_child(explore)


func _on_completion_button() -> void:
	if floor_number == TowerProgressionCatalog.FLOOR_LIMIT:
		var state = PlayerData.get_state()
		state["ending_seen"] = true
		PlayerData.replace_state(state)
		_return_to_main_menu()
		return
	# Keep the panel up if the floor fails to load, so the player can retry.
	if load_floor(floor_number + 1):
		panel.visible = false


func _on_player_defeated() -> void:
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "THE TOWER CLAIMS ANOTHER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var retry := Button.new()
	retry.text = "RETRY FLOOR %d" % floor_number
	retry.pressed.connect(func():
		if load_floor(floor_number):
			panel.visible = false
	)
	layout.add_child(retry)
	var menu := Button.new()
	menu.text = "RETURN TO MAIN MENU"
	menu.pressed.connect(_return_to_main_menu)
	layout.add_child(menu)


func _on_player_health_changed(_current: float, _maximum: float) -> void:
	pass


func _show_notice(text: String) -> void:
	notice_label.text = text
	# Only the newest notice's timer may clear the text, so a quick second
	# notice gets its full four seconds.
	_notice_serial += 1
	var serial = _notice_serial
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func():
		if is_instance_valid(notice_label) and serial == _notice_serial:
			notice_label.text = ""
	)


# Bold engraved capitals, like an inscription carved into the Tower. Uses a
# font already installed on the system (Copperplate on macOS), falling back
# to other classical faces and finally the system serif.
func _inscription_font(letter_spacing: int, weight: int = 700) -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Copperplate", "Optima", "Palatino", "Georgia", "serif"])
	system.font_weight = weight
	var font := FontVariation.new()
	font.base_font = system
	font.spacing_glyph = letter_spacing
	return font


func _add_hud_bar(parent: Control, caption: String, fill_color: Color, bar_size: Vector2) -> ProgressBar:
	# Caption on the left, "current / max" on the right, spanning the bar.
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(bar_size.x, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(row)
	var label := _hud_caption(caption, fill_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _hud_caption("", fill_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var bar := _make_bar(fill_color, bar_size)
	parent.add_child(bar)
	bar.set_meta("value_label", value)
	return bar


func _make_bar(fill_color: Color, bar_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = bar_size
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Thin and clean: a hairline frame just outside the bar over a dark,
	# translucent track; the fill drains inside it.
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.025, 0.025, 0.6)
	back.border_color = Color(0.85, 0.78, 0.62, 0.55)
	back.set_border_width_all(1)
	back.set_expand_margin_all(1.5)
	back.shadow_color = Color(0, 0, 0, 0.45)
	back.shadow_size = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


# Focus pips and the Immobilize cooldown under the stamina bar, and the
# guardian's name, vitality and posture at the bottom centre.
func _build_combat_hud(root: Control, bars: VBoxContainer) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	bars.add_child(gap)
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 7)
	focus_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(focus_row)
	var focus_color := Color("#6fa8dc")
	var focus_caption := _hud_caption("FOCUS", focus_color)
	focus_caption.custom_minimum_size = Vector2(66, 0)
	focus_row.add_child(focus_caption)
	for index in range(3):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = focus_color
		style.border_color = Color(0.85, 0.78, 0.62, 0.7)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.shadow_color = Color(0, 0, 0, 0.6)
		style.shadow_size = 2
		pip.add_theme_stylebox_override("panel", style)
		focus_row.add_child(pip)
		focus_pips.append(pip)
	# Spell slot in the bottom-right corner: a round plate with the key,
	# its cooldown bar and state underneath.
	var spell_color := Color("#d9b45a")
	var slot := VBoxContainer.new()
	slot.anchor_left = 1.0
	slot.anchor_right = 1.0
	slot.anchor_top = 1.0
	slot.anchor_bottom = 1.0
	slot.offset_left = -130
	slot.offset_right = -30
	slot.offset_top = -28
	slot.offset_bottom = -28
	slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.add_theme_constant_override("separation", 4)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slot)
	var emblem := Panel.new()
	emblem.custom_minimum_size = Vector2(46, 46)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emblem_style := StyleBoxFlat.new()
	emblem_style.bg_color = Color(0.05, 0.04, 0.03, 0.55)
	emblem_style.border_color = Color(0.85, 0.72, 0.45, 0.75)
	emblem_style.set_border_width_all(1)
	emblem_style.set_corner_radius_all(23)
	emblem.add_theme_stylebox_override("panel", emblem_style)
	slot.add_child(emblem)
	var key := _hud_caption("V", spell_color)
	key.add_theme_font_size_override("font_size", 18)
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem.add_child(key)
	immobilize_bar = _make_bar(spell_color, Vector2(70, 2))
	immobilize_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	immobilize_bar.max_value = PlayerScript.IMMOBILIZE_COOLDOWN
	slot.add_child(immobilize_bar)
	var spell_caption := _hud_caption("IMMOBILIZE", spell_color)
	spell_caption.add_theme_font_size_override("font_size", 11)
	spell_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_child(spell_caption)
	immobilize_value = _hud_caption("READY", spell_color)
	immobilize_value.add_theme_font_size_override("font_size", 11)
	immobilize_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_child(immobilize_value)
	# Guardian bar: long and thin at the bottom centre, name above it.
	boss_hud = CenterContainer.new()
	boss_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	boss_hud.offset_top = -118
	boss_hud.offset_bottom = -44
	boss_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_hud.visible = false
	root.add_child(boss_hud)
	var boss_layout := VBoxContainer.new()
	boss_layout.add_theme_constant_override("separation", 5)
	boss_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_hud.add_child(boss_layout)
	boss_name_label = Label.new()
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Clipped so a long status line never widens the bar's layout.
	boss_name_label.clip_text = true
	boss_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	boss_name_label.add_theme_font_override("font", _inscription_font(2))
	boss_name_label.add_theme_font_size_override("font_size", 16)
	boss_name_label.add_theme_color_override("font_color", Color("#f4ead8"))
	boss_name_label.add_theme_constant_override("outline_size", 6)
	boss_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.9))
	boss_layout.add_child(boss_name_label)
	# Ornate end caps (gold diamonds) either side of the bar.
	var boss_row := HBoxContainer.new()
	boss_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boss_row.add_theme_constant_override("separation", 6)
	boss_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_layout.add_child(boss_row)
	boss_row.add_child(_end_cap())
	boss_health_bar = _make_bar(Color("#9e2a2b"), Vector2(600, 5))
	boss_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	boss_row.add_child(boss_health_bar)
	boss_row.add_child(_end_cap())
	boss_posture_bar = _make_bar(Color("#e0a33a"), Vector2(440, 2))
	boss_posture_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boss_posture_bar.visible = false
	boss_layout.add_child(boss_posture_bar)
	# Floor 10: a big countdown and a draining bar under the title.
	tide_timer_label = Label.new()
	tide_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tide_timer_label.add_theme_font_override("font", _inscription_font(4))
	tide_timer_label.add_theme_font_size_override("font_size", 34)
	tide_timer_label.add_theme_color_override("font_color", Color("#cfe3b0"))
	tide_timer_label.add_theme_constant_override("outline_size", 8)
	tide_timer_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.02, 0.9))
	tide_timer_label.visible = false
	boss_layout.add_child(tide_timer_label)
	tide_bar = _make_bar(Color("#7d9a4a"), Vector2(600, 4))
	tide_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tide_bar.visible = false
	boss_layout.add_child(tide_bar)


func _hud_caption(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _inscription_font(2))
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", tint.lightened(0.55))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.85))
	return label


# A small gold diamond capping each end of the guardian bar.
func _end_cap() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(12, 12)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var diamond := Panel.new()
	diamond.size = Vector2(8, 8)
	diamond.position = Vector2(2, 2)
	diamond.pivot_offset = Vector2(4, 4)
	diamond.rotation = PI * 0.25
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	style.border_color = Color("#d9bf86")
	style.set_border_width_all(1)
	diamond.add_theme_stylebox_override("panel", style)
	holder.add_child(diamond)
	return holder


# Dark translucent plate with a hairline gold edge (prompt, overlays).
func _plate_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.035, 0.03, alpha)
	style.border_color = Color(0.85, 0.74, 0.5, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style


# One engraved typeface across the overlays (pause, journal, choices).
func _overlay_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _inscription_font(1, 500)
	theme.default_font_size = 15
	var plate := _plate_style(0.9)
	plate.set_content_margin_all(22)
	theme.set_stylebox("panel", "PanelContainer", plate)
	return theme


func _update_hud_title() -> void:
	floor_title.text = "FLOOR %d" % floor_number
	var subtitle: String = floor_data.get("region", "Tower")
	var special := String(floor_data.get("special", ""))
	if special == "dead_tide":
		subtitle += "  ·  The Dead Tide"
	elif special == "dragon":
		subtitle += "  ·  " + SpecialFloors.DRAGON_NAME
	elif floor_data.get("boss_floor", false):
		subtitle += "  ·  Guardian's Chamber"
	region_title.text = subtitle
	lore_title.text = String(floor_data.get("boss", {}).get("lore", "")) if special != "" else ""
	# Colour the card from the region: its light for the name, its sky's
	# darkest tone for the outlines.
	var region_profile: Dictionary = region_builder.profile if region_builder else {}
	var accent: Color = Color(region_profile.get("sun_color", Color("#e3c48e"))).lightened(0.2)
	var shade: Color = Color(region_profile.get("sky_top", Color.BLACK)).darkened(0.6)
	shade.a = 0.9
	region_title.add_theme_color_override("font_color", accent)
	region_title.add_theme_color_override("font_outline_color", shade)
	floor_title.add_theme_color_override("font_outline_color", shade)
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_card.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_title_card, "modulate:a", 1.0, 0.7)
	_title_tween.tween_interval(4.2 if not lore_title.text.is_empty() else 2.4)
	_title_tween.tween_property(_title_card, "modulate:a", 0.0, 0.9)


func _show_journal() -> void:
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "INVESTIGATION JOURNAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var journal: Dictionary = PlayerData.get_state()["investigation_journal"]
	if journal.is_empty():
		var empty := Label.new()
		empty.text = "No clues recorded. Look for weathered markers as you explore."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		layout.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(400, 220)
		layout.add_child(scroll)
		var entries := VBoxContainer.new()
		scroll.add_child(entries)
		var keys: Array = journal.keys()
		keys.sort()
		for key in keys:
			var entry: Dictionary = journal[key]
			var note := Label.new()
			note.text = "Floor %d — %s\n%s" % [entry.get("floor", 0), entry.get("region", "Tower"), entry.get("text", "")]
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entries.add_child(note)
	var close := Button.new()
	close.text = "CLOSE  (ESC)"
	close.pressed.connect(_close_overlay)
	layout.add_child(close)


func _show_pause_menu() -> void:
	if not is_instance_valid(player) or player.health <= 0.0:
		return
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var save_button := Button.new()
	save_button.text = "SAVE GAME"
	save_button.pressed.connect(_manual_save.bind(save_button))
	layout.add_child(save_button)
	var settings_button := Button.new()
	settings_button.text = "SETTINGS & CONTROLS"
	settings_button.pressed.connect(_show_settings)
	layout.add_child(settings_button)
	if floor_number == SpecialFloors.DRAGON_FLOOR and not _floor_finished:
		var retreat_button := Button.new()
		retreat_button.text = "RETREAT TO FLOOR %d" % (floor_number - 1)
		retreat_button.pressed.connect(func():
			if load_floor(floor_number - 1):
				panel.visible = false
		)
		layout.add_child(retreat_button)
	var resume_button := Button.new()
	resume_button.text = "RESUME"
	resume_button.pressed.connect(_close_overlay)
	layout.add_child(resume_button)
	var menu_button := Button.new()
	menu_button.text = "RETURN TO MAIN MENU"
	menu_button.pressed.connect(_return_to_main_menu)
	layout.add_child(menu_button)


func _show_settings() -> void:
	for child in panel.get_children():
		child.queue_free()
	var settings = SettingsScript.new()
	settings.standalone = false
	settings.custom_minimum_size = Vector2(480, 520)
	settings.closed.connect(_show_pause_menu)
	settings.graphics_changed.connect(_apply_graphics)
	panel.add_child(settings)


func _manual_save(save_button: Button) -> void:
	if PlayerData.save_now():
		save_button.text = "GAME SAVED"
	else:
		save_button.text = "SAVE FAILED"


func _show_inventory() -> void:
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "FOUND EQUIPMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var interval_start = TowerProgressionCatalog.rare_interval_start(floor_number)
	var rare_line := Label.new()
	rare_line.text = "Rare finds, floors %d–%d: %d / 2" % [interval_start, interval_start + 9, _rares_found_cache]
	rare_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rare_line.add_theme_color_override("font_color", Color("#e3c48e"))
	layout.add_child(rare_line)
	_add_dragonbane_section(layout)
	var inventory: Array = PlayerData.get_state()["inventory"]
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "No equipment found yet. Search beyond the obvious paths."
		layout.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(420, 220)
		layout.add_child(scroll)
		var entries := VBoxContainer.new()
		scroll.add_child(entries)
		var equipped: Dictionary = PlayerData.get_state()["equipped"]
		for item in inventory:
			var slot = item.get("slot", "relic")
			var is_equipped = equipped.get(slot, "") == item.get("instance_id", "")
			var button := Button.new()
			button.text = "%s  ·  %s  ·  ATK %d DEF %d%s\n%s" % [
				item.get("name", "Unknown gear"),
				item.get("rarity", "common").capitalize(),
				int(item.get("attack", 0)),
				int(item.get("defense", 0)),
				"  ·  EQUIPPED" if is_equipped else "",
				item.get("effect", "")
			]
			button.custom_minimum_size.y = 64
			button.pressed.connect(_equip_from_inventory.bind(item.get("instance_id", "")))
			entries.add_child(button)
	var close := Button.new()
	close.text = "CLOSE  (ESC)"
	close.pressed.connect(_close_overlay)
	layout.add_child(close)


# Dragonbane: the pieces found so far, where the rest are hidden, and the
# forge button once all three are owned.
func _add_dragonbane_section(layout: VBoxContainer) -> void:
	var state = PlayerData.get_state()
	var record: Dictionary = state["dragonbane"]
	if int(state["highest_unlocked_floor"]) < 16 and record["pieces"].is_empty():
		return
	var heading := Label.new()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", Color("#ffb45a"))
	layout.add_child(heading)
	if bool(record["forged"]):
		heading.text = "DRAGONBANE — FORGED. Vharzul's scales will part for it."
		return
	heading.text = "DRAGONBANE PIECES  %d / 3" % record["pieces"].size()
	var hints := Label.new()
	hints.text = _piece_hint_text()
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hints.custom_minimum_size = Vector2(420, 0)
	hints.add_theme_font_size_override("font_size", 13)
	layout.add_child(hints)
	var forge := Button.new()
	forge.text = "FORGE DRAGONBANE"
	forge.disabled = not PlayerData.can_forge_dragonbane()
	forge.tooltip_text = "Needs all three pieces."
	forge.pressed.connect(_forge_dragonbane)
	layout.add_child(forge)


func _forge_dragonbane() -> void:
	if PlayerData.forge_dragonbane():
		SoundBank.play_ui("fanfare")
		_show_notice("Dragonbane is forged. Vharzul's scales will part for it.")
		if is_instance_valid(_dragon):
			_dragon.dragonbane = true
	else:
		_show_notice("Dragonbane could not be forged.")
	_show_inventory()


func _equip_from_inventory(instance_id: String) -> void:
	if LootDirector.equip_item(instance_id):
		var hero = _selected_hero_data()
		var bonuses = _equipped_bonuses()
		hero["hp"] = int((int(hero.get("hp", 140)) + bonuses["defense"] * 7) * (1.0 + _rest_bonus / 100.0))
		hero["atk"] = int(hero.get("atk", 22)) + bonuses["attack"]
		hero["def"] = int(hero.get("def", 8)) + bonuses["defense"]
		hero["effects"] = bonuses["effects"]
		player.configure_hero(hero)
		_show_notice("Equipment saved and applied.")
		_show_inventory()
	else:
		_show_notice("Could not equip this item.")


func _close_overlay() -> void:
	panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(player) and player.health > 0.0:
		player.set_controls_enabled(true)


# The scene root processes while paused so its overlays keep handling input.
# Gameplay nodes would inherit that mode, so mark them pausable explicitly.
func _add_world_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


# --- Graphics helpers ------------------------------------------------------------

# Moving characters must not be baked into SDFGI (they would leave stale
# light and shadow behind), so their meshes are excluded as they appear.
func _on_node_added(node: Node) -> void:
	if not node is GeometryInstance3D:
		return
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is CharacterBody3D:
			(node as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			return
		parent = parent.get_parent()


# Locked on: everything well behind the target softens, framing the fight.
func _update_depth_of_field(delta: float) -> void:
	if _camera_attributes == null:
		return
	var target: Node3D = null
	if is_instance_valid(player) and player.has_method("get_lock_target"):
		target = player.get_lock_target()
	var camera := get_viewport().get_camera_3d()
	var wanted := 0.0
	if is_instance_valid(target) and camera != null:
		wanted = 1.0
		var focus := camera.global_position.distance_to(target.global_position)
		_camera_attributes.dof_blur_far_distance = focus + 6.0
	_dof_amount = move_toward(_dof_amount, wanted, delta * 2.5)
	_camera_attributes.dof_blur_far_enabled = _dof_amount > 0.01
	_camera_attributes.dof_blur_amount = 0.07 * _dof_amount


# Landing dust or splashes, wading splashes, a spray when the hero is struck
# and a golden wave when Immobilize is cast. Reads the player only.
func _observe_player_vfx(delta: float) -> void:
	var feet: Vector3 = player.global_position
	var water_level = region_builder.profile.get("water_level") if region_builder else null
	var in_water: bool = water_level != null and feet.y < float(water_level) + 0.35
	var on_floor: bool = player.is_on_floor()
	if not on_floor:
		_fall_speed = minf(_fall_speed, player.velocity.y)
	elif not _was_on_floor:
		if _fall_speed < -7.0:
			Vfx.landing(self, feet, in_water)
		_fall_speed = 0.0
	_was_on_floor = on_floor
	if in_water and on_floor and Vector2(player.velocity.x, player.velocity.z).length() > 2.0:
		_wade_time -= delta
		if _wade_time <= 0.0:
			_wade_time = 0.3
			Vfx.splash(self, Vector3(feet.x, float(water_level), feet.z), 0.3)
	var health := float(player.health)
	if _last_health >= 0.0 and health < _last_health - 0.5:
		Vfx.player_struck(self, feet + Vector3.UP * 1.2)
	_last_health = health
	var cooldown := float(player.immobilize_cooldown)
	if cooldown > _last_immobilize + 1.0:
		Vfx.magic_wave(self, feet, 9.0)
	_last_immobilize = cooldown
