
extends Control

var message_label: Label

func _ready():
	create_main_menu()
	add_child(preload("res://scripts/audio/ButtonClickHook.gd").new())


func create_main_menu():

	# Background
	var background = ColorRect.new()
	background.color = Color("#101020")
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	add_child(background)

	# Main layout
	var layout = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	layout.add_theme_constant_override("separation", 25)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(layout)

	# Game title
	var title = Label.new()
	title.text = "INFINITE TOWER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override(
		"font_color", Color("#d8b4ff")
	)
	layout.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "The Tower Awaits You"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	layout.add_child(subtitle)

	# Buttons
	add_menu_button(layout, "START ADVENTURE", "Start Adventure")
	add_menu_button(layout, "HERO COLLECTION", "Hero Collection")
	add_menu_button(layout, "SUMMON HEROES", "Summon Heroes")
	add_menu_button(layout, "SHOP", "Shop")
	add_menu_button(layout, "CAMP", "Camp")
	add_menu_button(layout, "TOWER", "Tower")
	add_menu_button(layout, "SETTINGS", "Settings")

	# Message
	message_label = Label.new()
	var load_warning = GachaManager.get_load_warning()
	message_label.text = load_warning if not load_warning.is_empty() else "Welcome, Master."
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(message_label)


func add_menu_button(parent, button_text, action):

	var button = Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 65)
	button.add_theme_font_size_override("font_size", 19)

	button.pressed.connect(
		func():
			show_message(action)
	)

	parent.add_child(button)


func show_message(action):
	if action == "Summon Heroes":
		get_tree().change_scene_to_file("res://scenes/gacha/Summon.tscn")

	elif action == "Hero Collection":
		get_tree().change_scene_to_file("res://scenes/heroes/HeroCollection.tscn")

	elif action == "Camp":
		get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")

	elif action == "Shop":
		get_tree().change_scene_to_file("res://scenes/shop/Shop.tscn")

	elif action == "Settings":
		get_tree().change_scene_to_file("res://scenes/settings/Settings.tscn")

	elif action == "Start Adventure" or action == "Tower":
		get_tree().change_scene_to_file("res://scenes/dungeon/TowerGame.tscn")

	else:
		message_label.text = action + " - Coming Soon!"
