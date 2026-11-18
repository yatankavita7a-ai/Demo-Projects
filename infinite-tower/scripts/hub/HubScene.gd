extends Node3D

# The Master's camp at the foot of the Tower: a walkable settlement where
# heroes live and work while you are away. Walk up to a building and press E
# to manage it. Offline gains are collected when you arrive.

const HeroDatabase = preload("res://data/HeroDatabase.gd")
const Hub = preload("res://scripts/systems/HubCatalog.gd")
const SkyIslandScript = preload("res://scripts/world/SkyIslandBuilder.gd")
const PlayerScript = preload("res://scripts/player/PlayerController.gd")
const InteractableScript = preload("res://scripts/systems/WorldInteractable.gd")
const SettingsScript = preload("res://scripts/ui/SettingsScreen.gd")
const SKY_SHADER = preload("res://shaders/sky.gdshader")
const CAMP_REGION := 2
const RARITY_COLORS := {
	1: Color("#9CA3AF"), 2: Color("#60A5FA"), 3: Color("#34D399"), 4: Color("#A78BFA"),
	5: Color("#FBBF24"), 6: Color("#F97316"), 7: Color("#F43F5E")
}
const PLAYER_SPAWN := Vector3(0, 1, 22)
const GATE_POSITION := Vector3(0, 0, -34)
const ARCHITECT_SPOT := Vector3(13, 0, 27)
const BUILDING_SPOTS := {
	"barracks": Vector3(-17, 0, -6),
	"training_grounds": Vector3(17, 0, -6),
	"quarry": Vector3(-20, 0, 14),
	"scout_hall": Vector3(20, 0, 14)
}

var region_builder
var player
var panel: PanelContainer
var materials_label: Label
var prompt_label: Label
var prompt_panel: PanelContainer
var notice_label: Label
var _camp_nodes: Array[Node] = []
var _notice_serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var report = PlayerData.hub_collect()
	_build_lighting()
	region_builder = SkyIslandScript.new()
	region_builder.improvements = PlayerData.get_hub()["buildings"]
	region_builder.name = "Region"
	add_child(region_builder)
	var reserved: Array = [PLAYER_SPAWN, GATE_POSITION, Vector3.ZERO, ARCHITECT_SPOT]
	for spot in BUILDING_SPOTS.values():
		reserved.append(spot)
	region_builder.build(CAMP_REGION, ("camp:%d" % int(PlayerData.get_state()["world_seed"])).hash(), reserved)
	_build_hud()
	_spawn_player()
	_rebuild_camp()
	_show_arrival_report(report)


func _process(_delta: float) -> void:
	if is_instance_valid(player):
		prompt_label.text = player.get_interaction_prompt()
		prompt_panel.visible = not prompt_label.text.is_empty()
	materials_label.text = "MATERIALS  %d" % int(PlayerData.get_hub()["materials"])


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		if panel.visible:
			_close_panel()
		else:
			_show_camp_menu()
		get_viewport().set_input_as_handled()


# --- World ---------------------------------------------------------------

func _build_lighting() -> void:
	var profile = region_builder_profile()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("top_color", profile["sky_top"])
	sky_material.set_shader_parameter("horizon_color", profile["sky_horizon"])
	sky_material.set_shader_parameter("ground_horizon", profile["ground_horizon"])
	sky_material.set_shader_parameter("ground_bottom", profile["ground_bottom"])
	sky_material.set_shader_parameter("sun_tint", profile["sun_color"])
	sky_material.set_shader_parameter("cloud_amount", 0.5)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = profile["ambient"]
	environment.ambient_light_energy = float(profile["ambient_energy"]) * 1.6
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.ssao_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = profile["fog_color"]
	environment.fog_density = float(profile["fog_density"]) * 0.28
	environment.fog_aerial_perspective = 0.55
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = profile["fog_density"]
	environment.volumetric_fog_albedo = profile["fog_color"]
	environment.volumetric_fog_length = 140.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(profile["sun_pitch"], profile["sun_yaw"], 0)
	sun.light_color = profile["sun_color"]
	sun.light_energy = profile["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)


func region_builder_profile() -> Dictionary:
	return SkyIslandScript.SKY_PROFILE


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.position = PLAYER_SPAWN
	var selected = GachaManager.get_hero_instance(str(PlayerData.get_state()["selected_hero_instance_id"]))
	var hero = _hero_record(selected.get("hero_id", "aurelia"))
	player.configure_hero(hero if not hero.is_empty() else HeroDatabase.get_heroes()[0])
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.add_child(region_builder.make_weather())


# Rebuilds buildings, the gate, the campfire and resident heroes from the
# saved camp state (after any build, upgrade or job change).
func _rebuild_camp() -> void:
	for node in _camp_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_camp_nodes.clear()
	var hub: Dictionary = PlayerData.get_hub()
	for building_id in BUILDING_SPOTS:
		_build_structure(building_id, int(hub["buildings"].get(building_id, 0)))
	_build_campfire()
	_build_gate()
	_build_architect_table()
	_place_residents(hub)


func _build_structure(building_id: String, level: int) -> void:
	var origin: Vector3 = BUILDING_SPOTS[building_id]
	var root := Node3D.new()
	add_child(root)
	# Face the plaza: the door (local -Z) looks toward the campfire.
	root.look_at_from_position(origin, Vector3(0, origin.y, 4), Vector3.UP)
	_camp_nodes.append(root)
	var stone = region_builder._make_scanned_material("castle_wall_slates", Color("#d8ccb8"), 0.4)
	var wood = region_builder._make_scanned_material("bark_brown_02", Color("#c8a882"), 0.7)
	# Timber huts at first; from level 2 the walls are rebuilt in white stone.
	var walls = wood if level < 2 else region_builder.white_stone()
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = Color("#7a5a36") if level < 2 else Color("#3d4a63")
	roof_material.roughness = 0.85
	if level <= 0:
		# Unbuilt: a marked foundation and a stack of timber.
		_add_box(root, Vector3(0, 0.15, 0), Vector3(8, 0.3, 6), stone, true)
		for index in range(4):
			_add_box(root, Vector3(-2.5 + index * 0.6, 0.55 + (index % 2) * 0.3, 2.2), Vector3(0.35, 0.35, 3.0), wood, false)
	else:
		var width = 7.0 + level
		var height = 3.0 + level * 0.8
		_add_box(root, Vector3(0, 0.3, 0), Vector3(width + 0.6, 0.6, 6.6), stone, true)
		_add_box(root, Vector3(0, 0.6 + height * 0.5, 0), Vector3(width, height, 6.0), walls, true)
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(width + 1.2, 2.2 + level * 0.3, 6.8)
		roof.mesh = prism
		roof.material_override = roof_material
		roof.position = Vector3(0, 0.6 + height + prism.size.y * 0.5, 0)
		root.add_child(roof)
		# Door facing the plaza, and one banner per level.
		var door := MeshInstance3D.new()
		var door_box := BoxMesh.new()
		door_box.size = Vector3(1.6, 2.4, 0.2)
		door.mesh = door_box
		door.material_override = wood
		door.position = Vector3(0, 1.8, -3.05)
		root.add_child(door)
		for banner_index in range(level):
			var banner := MeshInstance3D.new()
			var cloth := QuadMesh.new()
			cloth.size = Vector2(0.8, 1.8)
			banner.mesh = cloth
			var cloth_material := StandardMaterial3D.new()
			cloth_material.albedo_color = Color("#8a1f24")
			cloth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			banner.material_override = cloth_material
			banner.position = Vector3(-width * 0.5 + 1.0 + banner_index * 1.2, height - 0.2, -3.12)
			banner.rotation.y = PI
			root.add_child(banner)
	var sign := Label3D.new()
	var building_name: String = Hub.BUILDINGS[building_id]["name"]
	sign.text = building_name.to_upper() + ("" if level <= 0 else "\nLEVEL %d" % level) + ("\n(NOT BUILT)" if level <= 0 else "")
	sign.font_size = 56
	sign.outline_size = 12
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 6.5 + level, 0)
	sign.modulate = Color("#f4ead8")
	root.add_child(sign)
	var door_spot: Vector3 = origin + (Vector3(0, 0, 4) - origin).normalized() * 4.5
	_add_interactable("building", building_id, "Manage the " + building_name, door_spot)


func _build_campfire() -> void:
	var fire_root := Node3D.new()
	add_child(fire_root)
	_camp_nodes.append(fire_root)
	var stones = region_builder._make_scanned_material("rock_face", Color("#a09888"), 1.2)
	for index in range(8):
		var angle = TAU * index / 8.0
		var stone := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.4
		stone.mesh = sphere
		stone.material_override = stones
		stone.position = Vector3(cos(angle) * 1.1, 0.12, sin(angle) * 1.1)
		fire_root.add_child(stone)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.0, 0)
	light.light_color = Color("#ff9a4a")
	light.light_energy = 2.5
	light.omni_range = 12.0
	light.shadow_enabled = true
	fire_root.add_child(light)
	var flames := GPUParticles3D.new()
	flames.amount = 90
	flames.lifetime = 0.9
	flames.position = Vector3(0, 0.2, 0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.gravity = Vector3(0, 2.2, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color = Color(1.0, 0.55, 0.15)
	flames.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var flame_material := StandardMaterial3D.new()
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.vertex_color_use_as_albedo = true
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.albedo_texture = region_builder._soft_dot_texture()
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.5, 0.15)
	flame_material.emission_energy_multiplier = 4.0
	quad.material = flame_material
	flames.draw_pass_1 = quad
	fire_root.add_child(flames)


func _build_gate() -> void:
	var gate_root := Node3D.new()
	gate_root.position = GATE_POSITION
	add_child(gate_root)
	_camp_nodes.append(gate_root)
	var stone = region_builder._make_scanned_material("castle_wall_slates", Color("#bfb3a0"), 0.4)
	for side in [-1.0, 1.0]:
		_add_box(gate_root, Vector3(side * 2.4, 3.0, 0), Vector3(1.2, 6.0, 1.2), stone, true)
	_add_box(gate_root, Vector3(0, 6.4, 0), Vector3(6.2, 1.0, 1.4), stone, true)
	var sign := Label3D.new()
	sign.text = "THE TOWER"
	sign.font_size = 64
	sign.outline_size = 12
	sign.position = Vector3(0, 7.6, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate_root.add_child(sign)
	_add_interactable("gate", "tower", "Enter the Tower", GATE_POSITION + Vector3(0, 0, 2.0))


# Residents gather at the building of their job; resting heroes sit by the fire.
func _place_residents(hub: Dictionary) -> void:
	var counts := {}
	for instance_id in hub["residents"]:
		if hub["expeditions"].has(instance_id):
			continue
		var job: String = hub["residents"][instance_id]
		var anchor := Vector3.ZERO
		for building_id in Hub.BUILDINGS:
			if Hub.BUILDINGS[building_id]["job"] == job and job != "rest":
				anchor = BUILDING_SPOTS[building_id] + (Vector3(0, 0, 4) - BUILDING_SPOTS[building_id]).normalized() * 6.5
		var index = int(counts.get(job, 0))
		counts[job] = index + 1
		var angle = TAU * float(index) / 6.0 + 0.4
		var radius = 3.0 if job == "rest" else 1.8
		var spot = anchor + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		spot.y = region_builder.height_at(spot.x, spot.z)
		_place_hero_figure(instance_id, job, spot)


func _place_hero_figure(instance_id: String, job: String, spot: Vector3) -> void:
	var instance = GachaManager.get_hero_instance(instance_id)
	var hero = _hero_record(instance.get("hero_id", ""))
	var figure := Node3D.new()
	figure.position = spot
	add_child(figure)
	_camp_nodes.append(figure)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	body.mesh = capsule
	body.position.y = 0.85
	var material := StandardMaterial3D.new()
	material.albedo_color = RARITY_COLORS.get(int(hero.get("rarity", 1)), Color.WHITE).darkened(0.15)
	body.material_override = material
	figure.add_child(body)
	var label := Label3D.new()
	label.text = "%s  Lv %d\n%s" % [hero.get("name", "Hero"), int(instance.get("level", 1)), Hub.JOBS.get(job, {}).get("name", job)]
	label.font_size = 40
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.3
	figure.add_child(label)


func _add_box(parent: Node3D, center: Vector3, size: Vector3, material: Material, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = center
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)


func _add_interactable(kind: String, id: String, prompt: String, at: Vector3) -> void:
	var interactable = InteractableScript.new()
	interactable.interaction_kind = kind
	interactable.interaction_id = id
	interactable.prompt_text = prompt
	interactable.concealed = false
	interactable.position = Vector3(at.x, region_builder.height_at(at.x, at.z), at.z)
	interactable.activated.connect(_on_interact)
	add_child(interactable)
	_camp_nodes.append(interactable)


# A drafting table where sanctuary works are commissioned.
func _build_architect_table() -> void:
	var spot := ARCHITECT_SPOT
	var table_root := Node3D.new()
	table_root.position = spot
	add_child(table_root)
	_camp_nodes.append(table_root)
	var wood = region_builder._make_scanned_material("bark_brown_02", Color("#c8a882"), 0.9)
	_add_box(table_root, Vector3(0, 0.9, 0), Vector3(2.4, 0.15, 1.4), wood, true)
	for leg in [Vector3(-1.0, 0.45, -0.55), Vector3(1.0, 0.45, -0.55), Vector3(-1.0, 0.45, 0.55), Vector3(1.0, 0.45, 0.55)]:
		_add_box(table_root, leg, Vector3(0.15, 0.9, 0.15), wood, false)
	var plans := MeshInstance3D.new()
	var sheet := BoxMesh.new()
	sheet.size = Vector3(1.6, 0.02, 1.0)
	plans.mesh = sheet
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("#e8dcc0")
	plans.material_override = paper
	plans.position = Vector3(0, 0.99, 0)
	table_root.add_child(plans)
	var sign := Label3D.new()
	sign.text = "ARCHITECT'S TABLE"
	sign.font_size = 48
	sign.outline_size = 10
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 2.2, 0)
	table_root.add_child(sign)
	_add_interactable("architect", "works", "Plan sanctuary works", spot + Vector3(0, 0, 1.2))


func _show_works() -> void:
	var hub: Dictionary = PlayerData.get_hub()
	var highest = int(PlayerData.get_state()["highest_unlocked_floor"])
	var layout = _open_panel()
	layout.add_child(_caption("SANCTUARY WORKS", 26, Color("#f4ead8"), true))
	layout.add_child(_body("Rebuild the broken island into a sanctuary. Materials %d." % int(hub["materials"])))
	for improvement_id in Hub.IMPROVEMENTS:
		var spec: Dictionary = Hub.IMPROVEMENTS[improvement_id]
		var row := HBoxContainer.new()
		var info := _body("%s — %s" % [spec["name"], spec["description"]])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var button: Button
		if Hub.has_improvement(hub, improvement_id):
			button = _button("BUILT", func(): pass)
			button.disabled = true
		elif highest < int(spec["unlock_floor"]):
			button = _button("FLOOR %d" % int(spec["unlock_floor"]), func(): pass)
			button.disabled = true
		else:
			button = _button("BUILD · %d" % int(spec["cost"]), func():
				if PlayerData.hub_build_improvement(improvement_id) == "ok":
					get_tree().paused = false
					get_tree().reload_current_scene()
			)
			button.disabled = int(hub["materials"]) < int(spec["cost"])
		button.custom_minimum_size.x = 150
		row.add_child(button)
		layout.add_child(row)
	layout.add_child(_button("CLOSE  (ESC)", _close_panel))


func _on_interact(interactable) -> void:
	if interactable.interaction_kind == "architect":
		_show_works()
		return
	if interactable.interaction_kind == "gate":
		get_tree().change_scene_to_file("res://scenes/dungeon/TowerGame.tscn")
	else:
		_show_building(interactable.interaction_id)


# --- Interface -------------------------------------------------------------

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	materials_label = _caption("", 18, Color("#e3c48e"))
	materials_label.position = Vector2(24, 18)
	root.add_child(materials_label)
	notice_label = _caption("", 18, Color("#f3d6a0"))
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice_label.offset_top = 64
	notice_label.offset_left = 220
	notice_label.offset_right = -220
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice_label)
	prompt_panel = PanelContainer.new()
	prompt_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_panel.offset_top = -54
	prompt_panel.offset_bottom = -12
	prompt_panel.offset_left = 20
	prompt_panel.offset_right = -20
	prompt_panel.visible = false
	root.add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.07, 0.06, 0.97)
	panel_style.border_color = Color("#a8926a")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(560, 200)
	panel.visible = false
	center.add_child(panel)


func _show_arrival_report(report: Dictionary) -> void:
	var lines: Array[String] = []
	if float(report.get("hours", 0.0)) >= 0.1:
		lines.append("While you were away (%.1f h):" % float(report["hours"]))
		if int(report.get("materials", 0)) > 0:
			lines.append("+%d materials" % int(report["materials"]))
		for instance_id in report.get("levels", {}):
			var instance = GachaManager.get_hero_instance(instance_id)
			lines.append("%s trained to Lv %d" % [_hero_record(instance.get("hero_id", "")).get("name", "A hero"), int(report["levels"][instance_id])])
		for item in report.get("items", []):
			lines.append("A scout brought back %s" % item.get("name", "equipment"))
	_show_notice("\n".join(lines) if lines.size() > 1 else "Welcome back to camp. Esc for the camp menu.", 8.0)


func _show_notice(text: String, seconds: float = 4.0) -> void:
	notice_label.text = text
	_notice_serial += 1
	var serial = _notice_serial
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(notice_label) and serial == _notice_serial:
			notice_label.text = ""
	)


func _open_panel() -> VBoxContainer:
	for child in panel.get_children():
		child.queue_free()
	panel.visible = true
	notice_label.text = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(false)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	return layout


func _close_panel() -> void:
	panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_controls_enabled(true)


func _show_camp_menu() -> void:
	var layout = _open_panel()
	layout.add_child(_caption("THE CAMP", 26, Color("#f4ead8"), true))
	var hub = PlayerData.get_hub()
	layout.add_child(_body("Residents %d / %d   ·   Materials %d   ·   Rest bonus +%d%%" % [hub["residents"].size(), PlayerData.hub_capacity(), int(hub["materials"]), int(hub["rest_bonus"])]))
	layout.add_child(_button("ENTER THE TOWER", func(): get_tree().paused = false; get_tree().change_scene_to_file("res://scenes/dungeon/TowerGame.tscn")))
	layout.add_child(_button("SETTINGS & CONTROLS", _show_settings))
	layout.add_child(_button("RETURN TO MAIN MENU", func(): get_tree().paused = false; get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")))
	layout.add_child(_button("RESUME", _close_panel))


func _show_settings() -> void:
	for child in panel.get_children():
		child.queue_free()
	var settings = SettingsScript.new()
	settings.standalone = false
	settings.custom_minimum_size = Vector2(480, 520)
	settings.closed.connect(_show_camp_menu)
	panel.add_child(settings)


func _show_building(building_id: String) -> void:
	var hub: Dictionary = PlayerData.get_hub()
	var info: Dictionary = Hub.BUILDINGS[building_id]
	var level = int(hub["buildings"].get(building_id, 0))
	var layout = _open_panel()
	layout.add_child(_caption(info["name"].to_upper(), 26, Color("#f4ead8"), true))
	layout.add_child(_body("Level %d / %d   ·   Materials %d" % [level, Hub.MAX_BUILDING_LEVEL, int(hub["materials"])] if level > 0 else "Not built   ·   Materials %d" % int(hub["materials"])))
	layout.add_child(_body(info["description"]))
	var cost = Hub.upgrade_cost(building_id, level)
	if cost >= 0:
		var label = ("BUILD" if level <= 0 else "UPGRADE TO LEVEL %d" % (level + 1)) + "  ·  %d MATERIALS" % cost
		var upgrade = _button(label, func():
			if PlayerData.hub_upgrade(building_id):
				_rebuild_camp()
				_show_building(building_id)
		)
		upgrade.disabled = int(hub["materials"]) < cost
		layout.add_child(upgrade)
	if level > 0:
		match building_id:
			"barracks":
				_add_barracks_controls(layout, hub)
			"scout_hall":
				_add_scout_controls(layout, hub)
			_:
				_add_job_controls(layout, hub, info["job"], building_id)
	layout.add_child(_button("CLOSE  (ESC)", _close_panel))


func _add_barracks_controls(layout: VBoxContainer, hub: Dictionary) -> void:
	layout.add_child(_body("Residents %d / %d   ·   Rest bonus for your hero: +%d%% vitality" % [hub["residents"].size(), PlayerData.hub_capacity(), int(hub["rest_bonus"])]))
	for instance_id in hub["residents"]:
		var row := HBoxContainer.new()
		row.add_child(_body(_hero_line(instance_id, hub)))
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not hub["expeditions"].has(instance_id):
			row.add_child(_button("SEND AWAY", func():
				PlayerData.hub_remove_resident(instance_id)
				_rebuild_camp()
				_show_building("barracks")
			))
		layout.add_child(row)
	if hub["residents"].size() < PlayerData.hub_capacity():
		var picker := OptionButton.new()
		var choices: Array = []
		for instance in GachaManager.get_owned_hero_instances():
			if hub["residents"].has(instance["instance_id"]):
				continue
			var hero = _hero_record(instance["hero_id"])
			picker.add_item("%s  ·  %d★ %s  ·  Lv %d" % [hero.get("name", "?"), int(hero.get("rarity", 1)), hero.get("class", ""), int(instance["level"])])
			choices.append(instance["instance_id"])
		if choices.is_empty():
			layout.add_child(_body("Summon more heroes to invite them to camp."))
		else:
			var row := HBoxContainer.new()
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(picker)
			row.add_child(_button("INVITE", func():
				if picker.selected >= 0 and PlayerData.hub_add_resident(choices[picker.selected]):
					_rebuild_camp()
					_show_building("barracks")
			))
			layout.add_child(row)


func _add_job_controls(layout: VBoxContainer, hub: Dictionary, job: String, building_id: String) -> void:
	var job_name: String = Hub.JOBS[job]["name"]
	var suited: Array = Hub.JOBS[job]["classes"]
	layout.add_child(_body("Assign residents as %s.%s" % [job_name, ("  " + ", ".join(suited) + " work 25% faster.") if not suited.is_empty() else ""]))
	if hub["residents"].is_empty():
		layout.add_child(_body("No heroes live in camp yet. Invite some at the Barracks."))
	for instance_id in hub["residents"]:
		var row := HBoxContainer.new()
		row.add_child(_body(_hero_line(instance_id, hub)))
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if hub["expeditions"].has(instance_id):
			row.add_child(_body("On expedition"))
		elif hub["residents"][instance_id] == job:
			row.add_child(_button("STOP", func():
				PlayerData.hub_assign_job(instance_id, "rest")
				_rebuild_camp()
				_show_building(building_id)
			))
		else:
			row.add_child(_button("ASSIGN", func():
				PlayerData.hub_assign_job(instance_id, job)
				_rebuild_camp()
				_show_building(building_id)
			))
		layout.add_child(row)


func _add_scout_controls(layout: VBoxContainer, hub: Dictionary) -> void:
	layout.add_child(_body("Choose a resident and an expedition length. Assassins and Archers bring back more."))
	var now = int(Time.get_unix_time_from_system())
	for instance_id in hub["residents"]:
		var row := HBoxContainer.new()
		row.add_child(_body(_hero_line(instance_id, hub)))
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if hub["expeditions"].has(instance_id):
			var remaining = maxi(0, int(hub["expeditions"][instance_id]["ends"]) - now)
			row.add_child(_body("Back in %dh %02dm" % [remaining / 3600, (remaining % 3600) / 60] if remaining > 0 else "Returning, revisit camp"))
		else:
			for hours in Hub.EXPEDITION_HOURS:
				row.add_child(_button("%dH" % hours, func():
					PlayerData.hub_send_expedition(instance_id, hours)
					_rebuild_camp()
					_show_building("scout_hall")
				))
		layout.add_child(row)


func _hero_line(instance_id: String, hub: Dictionary) -> String:
	var instance = GachaManager.get_hero_instance(instance_id)
	var hero = _hero_record(instance.get("hero_id", ""))
	return "%s  ·  %s  ·  Lv %d  ·  %s" % [hero.get("name", "?"), hero.get("class", ""), int(instance.get("level", 1)), Hub.JOBS.get(hub["residents"][instance_id], {}).get("name", "")]


func _hero_record(hero_id: String) -> Dictionary:
	for hero in HeroDatabase.get_heroes():
		if hero["id"] == hero_id:
			return hero
	return {}


func _caption(text: String, size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Copperplate", "Optima", "Palatino", "Georgia", "serif"])
	system.font_weight = 700
	var font := FontVariation.new()
	font.base_font = system
	font.spacing_glyph = 2
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.85))
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 260
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	return button
