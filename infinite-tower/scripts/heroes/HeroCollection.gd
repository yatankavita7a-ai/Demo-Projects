
extends Control

const HeroDatabase = preload("res://data/HeroDatabase.gd")

var all_heroes: Array = []
var grid: GridContainer
var stats_label: Label
var rarity_filter: OptionButton
var view_filter: OptionButton
var class_filter: OptionButton
var sort_filter: OptionButton
var search_field: LineEdit
var select_button: Button
var selected_instance_id := ""
var selected_profile: Dictionary = {}


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	all_heroes = HeroDatabase.get_heroes()

	print("HEROES LOADED: ", all_heroes.size())

	create_screen()
	display_heroes()


func create_screen():
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 15)
	margin.add_child(layout)

	var title = Label.new()
	title.text = "HERO COLLECTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#d8b4ff"))
	layout.add_child(title)

	rarity_filter = OptionButton.new()
	rarity_filter.add_item("All Heroes", 0)

	for stars in range(1, 8):
		rarity_filter.add_item(str(stars) + " Star", stars)

	rarity_filter.item_selected.connect(display_heroes)
	layout.add_child(rarity_filter)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	layout.add_child(filters)
	view_filter = OptionButton.new()
	view_filter.add_item("Complete Catalog", 0)
	view_filter.add_item("Owned Copies", 1)
	view_filter.item_selected.connect(display_heroes)
	filters.add_child(view_filter)
	class_filter = OptionButton.new()
	class_filter.add_item("All Classes", 0)
	for hero_class in ["Warrior", "Mage", "Archer", "Assassin", "Healer", "Tank"]:
		class_filter.add_item(hero_class)
	class_filter.item_selected.connect(display_heroes)
	filters.add_child(class_filter)
	sort_filter = OptionButton.new()
	for sort_name in ["Name", "Rarity", "Class", "Ownership"]:
		sort_filter.add_item("Sort: " + sort_name)
	sort_filter.item_selected.connect(display_heroes)
	filters.add_child(sort_filter)
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search heroes"
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_changed.connect(display_heroes)
	filters.add_child(search_field)

	var middle = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(middle)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(scroll)

	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var stats_panel = PanelContainer.new()
	stats_panel.custom_minimum_size = Vector2(230, 0)
	middle.add_child(stats_panel)
	var profile_layout := VBoxContainer.new()
	profile_layout.add_theme_constant_override("separation", 12)
	stats_panel.add_child(profile_layout)

	stats_label = Label.new()
	stats_label.text = "Select a hero to view stats."
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_layout.add_child(stats_label)
	select_button = Button.new()
	select_button.text = "USE IN TOWER"
	select_button.visible = false
	select_button.pressed.connect(_select_hero_for_tower)
	profile_layout.add_child(select_button)

	var back_button = Button.new()
	back_button.text = "BACK TO MAIN MENU"
	back_button.custom_minimum_size = Vector2(0, 50)
	back_button.pressed.connect(go_back)
	layout.add_child(back_button)


func display_heroes(_index = 0):
	selected_instance_id = ""
	selected_profile = {}
	select_button.visible = false
	for child in grid.get_children():
		child.queue_free()

	var candidates: Array = []
	var owned_counts = GachaManager.get_owned_counts()
	if view_filter.get_selected_id() == 1:
		for instance in GachaManager.get_owned_hero_instances():
			var hero = _find_catalog_hero(instance["hero_id"])
			if hero.is_empty():
				hero = {"id": instance["hero_id"], "name": "Unknown Legacy Hero", "class": "Unknown", "rarity": 1, "hp": 0, "atk": 0, "def": 0, "spd": 0}
			hero["instance"] = instance
			hero["owned_count"] = int(owned_counts.get(instance["hero_id"], 0))
			candidates.append(hero)
	else:
		for hero in all_heroes:
			var catalog_entry = hero.duplicate(true)
			catalog_entry["owned_count"] = int(owned_counts.get(hero["id"], 0))
			candidates.append(catalog_entry)

	var selected_rarity = rarity_filter.get_selected_id()
	var selected_class = class_filter.get_item_text(class_filter.selected) if class_filter.selected > 0 else ""
	var search = search_field.text.strip_edges().to_lower()
	var filtered: Array = []
	for hero in candidates:
		if selected_rarity != 0 and hero["rarity"] != selected_rarity:
			continue
		if not selected_class.is_empty() and hero["class"] != selected_class:
			continue
		if not search.is_empty() and not hero["name"].to_lower().contains(search):
			continue
		filtered.append(hero)
	filtered.sort_custom(_sort_heroes)
	stats_label.text = "Owned copies: %d\nCatalog heroes: %d" % [
		GachaManager.get_owned_hero_instances().size(), all_heroes.size()
	]
	if filtered.is_empty():
		var empty := Label.new()
		empty.text = "No heroes match these filters."
		grid.add_child(empty)
		return
	for hero in filtered:
		var button = Button.new()
		button.custom_minimum_size = Vector2(140, 85)
		if hero.has("instance"):
			button.text = "%s\n%d★ · Lv %d" % [hero["name"], hero["rarity"], hero["instance"].get("level", 1)]
		else:
			button.text = "%s\n%d★ · Owned %d" % [hero["name"], hero["rarity"], hero["owned_count"]]

		button.pressed.connect(show_details.bind(hero))
		grid.add_child(button)


func _find_catalog_hero(hero_id: String) -> Dictionary:
	for hero in all_heroes:
		if hero["id"] == hero_id:
			return hero.duplicate(true)
	return {}


func _sort_heroes(left: Dictionary, right: Dictionary) -> bool:
	match sort_filter.selected:
		1:
			if left["rarity"] != right["rarity"]:
				return left["rarity"] > right["rarity"]
		2:
			if left["class"] != right["class"]:
				return left["class"] < right["class"]
		3:
			if left["owned_count"] != right["owned_count"]:
				return left["owned_count"] > right["owned_count"]
	return left["name"].to_lower() < right["name"].to_lower()


func show_details(hero):
	selected_profile = hero.duplicate(true)
	selected_instance_id = ""
	select_button.visible = false
	var profile_text = (
		hero["name"] +
		"\nClass: " + hero["class"] +
		"\nRarity: " + str(hero["rarity"]) + "★" +
		"\n\nHP: " + str(hero["hp"]) +
		"\nATK: " + str(hero["atk"]) +
		"\nDEF: " + str(hero["def"]) +
		"\nSPD: " + str(hero["spd"])
	)
	if hero.has("instance"):
		var instance: Dictionary = hero["instance"]
		var instance_id: String = instance["instance_id"]
		var active_instance_id = PlayerData.get_state().get("selected_hero_instance_id", "")
		profile_text += (
			"\n\nInstance: " + instance_id +
			"\nLevel: " + str(instance.get("level", 1)) +
			"\nXP: " + str(instance.get("xp", 0))
		)
		if not _find_catalog_hero(instance["hero_id"]).is_empty():
			selected_instance_id = instance_id
			select_button.visible = true
			select_button.text = "ACTIVE FOR TOWER" if active_instance_id == instance_id else "USE IN TOWER"
	else:
		profile_text += "\n\nOwned copies: " + str(hero.get("owned_count", 0))
	stats_label.text = profile_text


func _select_hero_for_tower() -> void:
	if selected_instance_id.is_empty() or GachaManager.get_hero_instance(selected_instance_id).is_empty():
		stats_label.text += "\n\nThis hero copy is no longer available."
		return
	var state = PlayerData.get_state()
	state["selected_hero_instance_id"] = selected_instance_id
	if PlayerData.replace_state(state):
		show_details(selected_profile)
	else:
		stats_label.text += "\n\nSelection could not be saved."


func go_back():
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
