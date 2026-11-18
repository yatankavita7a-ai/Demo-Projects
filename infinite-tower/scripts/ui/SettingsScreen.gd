extends Control
class_name SettingsScreen

# Settings and controls reference. Used as its own scene from the main menu
# (standalone) and embedded in the tower's pause menu, where "Back" returns
# to the pause screen instead of the main menu.

signal closed
# Emitted after a graphics option changes (already saved), so the tower can
# apply it at once.
signal graphics_changed(settings: Dictionary)

const GraphicsSettings = preload("res://scripts/systems/GraphicsSettings.gd")

const CONTROLS := [
	["Move", "W A S D"],
	["Look", "Mouse"],
	["Jump", "Space"],
	["Light attack", "Left mouse"],
	["Heavy attack", "Right mouse"],
	["Charged heavy (spends all Focus)", "Hold right mouse"],
	["Jump attack (plunging strike)", "Left / right mouse in the air"],
	["Dodge roll", "Shift + direction"],
	["Backstep", "Shift (no direction)"],
	["Sprint", "Hold Shift while moving"],
	["Spectral steed (summon / dismiss)", "R"],
	["Steed: double jump", "Space, then Space in the air"],
	["Steed: sidestep dash", "Shift (+ left / right)"],
	["Lock-on", "Middle mouse / Tab"],
	["Switch target", "Mouse wheel"],
	["Immobilize", "V"],
	["Parry (time it to the wind-up)", "F"],
	["Guard", "Q (hold)"],
	["Stealth / crouch", "Ctrl (hold)"],
	["Interact", "E"],
	["Equipment", "I"],
	["Investigation journal", "J"],
	["Pause, save & settings", "Esc"]
]

const CameraSettings = preload("res://scripts/player/CameraSettings.gd")

var standalone := true
var _graphics: Dictionary = {}
var camera_option: OptionButton


func _ready() -> void:
	if standalone:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var background := ColorRect.new()
		background.color = Color("#101020")
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.custom_minimum_size = Vector2(440, 0)
	center.add_child(layout)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28 if standalone else 22)
	title.add_theme_color_override("font_color", Color("#d8b4ff"))
	layout.add_child(title)
	var camera_row := HBoxContainer.new()
	var camera_label := Label.new()
	camera_label.text = "Camera"
	camera_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_row.add_child(camera_label)
	camera_option = OptionButton.new()
	camera_option.add_item("Close (shoulder)")
	camera_option.add_item("Classic")
	camera_option.select(0 if CameraSettings.is_close() else 1)
	camera_option.item_selected.connect(_on_camera_selected)
	camera_row.add_child(camera_option)
	layout.add_child(camera_row)
	var section := Label.new()
	section.text = "CONTROLS"
	section.add_theme_color_override("font_color", Color("#f3d6a0"))
	layout.add_child(section)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for row in CONTROLS:
		var action := Label.new()
		action.text = row[0]
		action.add_theme_font_size_override("font_size", 15)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(action)
		var key := Label.new()
		key.text = row[1]
		key.add_theme_font_size_override("font_size", 15)
		key.add_theme_color_override("font_color", Color("#c9c0e8"))
		grid.add_child(key)
	var tips := Label.new()
	tips.text = "Enemies glow before they strike: dodge or parry during the wind-up. Crouch out of sight to slip past patrols, and search for clues before each fifth-floor guardian."
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size = Vector2(440, 0)
	tips.add_theme_font_size_override("font_size", 13)
	layout.add_child(tips)
	var back := Button.new()
	back.text = "BACK TO MAIN MENU" if standalone else "BACK"
	back.custom_minimum_size.y = 44
	back.pressed.connect(_on_back)
	layout.add_child(back)
	# Embedded in the pause menu, the tower already adds click sounds.
	if standalone:
		add_child(preload("res://scripts/audio/ButtonClickHook.gd").new())


func _on_camera_selected(index: int) -> void:
	CameraSettings.set_mode(CameraSettings.CLOSE if index == 0 else CameraSettings.CLASSIC)


func _on_back() -> void:
	closed.emit()
	if standalone:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


# Global illumination, anti-aliasing and the film-grain overlay.
func _add_graphics_section(layout: VBoxContainer) -> void:
	_graphics = GraphicsSettings.load_settings()
	var section := Label.new()
	section.text = "GRAPHICS"
	section.add_theme_color_override("font_color", Color("#f3d6a0"))
	layout.add_child(section)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	layout.add_child(grid)
	_add_option(grid, "Global illumination", GraphicsSettings.GI_LABELS,
		GraphicsSettings.GI_LEVELS.find(_graphics["gi"]), func(index: int):
			_set_graphics("gi", GraphicsSettings.GI_LEVELS[index]))
	_add_option(grid, "Anti-aliasing", GraphicsSettings.AA_LABELS,
		GraphicsSettings.AA_MODES.find(_graphics["aa"]), func(index: int):
			_set_graphics("aa", GraphicsSettings.AA_MODES[index]))
	_add_option(grid, "Film grain & vignette", ["On", "Off"],
		0 if _graphics["grain"] else 1, func(index: int):
			_set_graphics("grain", index == 0))


func _add_option(grid: GridContainer, caption: String, labels: Array, selected: int, on_change: Callable) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var option := OptionButton.new()
	for text in labels:
		option.add_item(text)
	option.select(maxi(0, selected))
	option.custom_minimum_size = Vector2(210, 0)
	option.item_selected.connect(on_change)
	grid.add_child(option)


func _set_graphics(key: String, value) -> void:
	_graphics[key] = value
	GraphicsSettings.save_settings(_graphics)
	graphics_changed.emit(_graphics.duplicate())
