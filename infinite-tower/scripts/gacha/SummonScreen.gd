extends Control

# Star-tier colours agreed for the collection and summon effects.
const RARITY_COLORS := {
	1: Color("#9CA3AF"), 2: Color("#60A5FA"), 3: Color("#34D399"), 4: Color("#A78BFA"),
	5: Color("#FBBF24"), 6: Color("#F97316"), 7: Color("#F43F5E")
}
const REVEAL_INTERVAL := 0.35
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const CARD_SIZE := Vector2(120, 96)

var balance_label: Label
var result_label: Label
var card_grid: GridContainer
var skip_button: Button
var _summon_buttons: Array[Button] = []
var _pending_reveals: Array = []
var _reveal_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "SUMMON THE REMNANTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#d8b4ff"))
	layout.add_child(title)
	balance_label = Label.new()
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(balance_label)
	# Smaller summons unlock as the player climbs the tower; prices rise too.
	for count in [10, 5, 2]:
		var button := Button.new()
		button.custom_minimum_size.y = 56
		var cost = GachaManager.summon_cost(count)
		if GachaManager.is_summon_size_unlocked(count):
			button.text = "SUMMON %d  ·  %s GEMS" % [count, _format_gems(cost)]
			button.pressed.connect(_summon.bind(count))
			_summon_buttons.append(button)
		else:
			button.text = "SUMMON %d  ·  UNLOCKS AT FLOOR %d" % [
				count, GachaManager.SUMMON_SIZE_UNLOCK_FLOORS[count]
			]
			button.disabled = true
		layout.add_child(button)
	card_grid = GridContainer.new()
	card_grid.columns = 5
	card_grid.add_theme_constant_override("h_separation", 10)
	card_grid.add_theme_constant_override("v_separation", 10)
	card_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(card_grid)
	skip_button = Button.new()
	skip_button.text = "REVEAL ALL"
	skip_button.visible = false
	skip_button.pressed.connect(_reveal_all)
	layout.add_child(skip_button)
	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(result_label)
	var back := Button.new()
	back.text = "RETURN TO MAIN MENU"
	back.custom_minimum_size.y = 48
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))
	layout.add_child(back)
	GachaManager.currency_changed.connect(_update_balance)
	GachaManager.heroes_changed.connect(_update_balance)
	_update_balance()
	add_child(preload("res://scripts/audio/ButtonClickHook.gd").new())


func _summon(count: int) -> void:
	_show_results(GachaManager.summon(count))


func _format_gems(amount: int) -> String:
	var text = str(amount)
	return text.substr(0, text.length() - 3) + "," + text.substr(text.length() - 3) if amount >= 1000 else text


func _show_results(results: Array) -> void:
	if results.is_empty():
		SoundBank.play_ui("error")
		if not GachaManager.is_save_writable():
			result_label.text = "Summoning is disabled because your save file could not be loaded."
		else:
			result_label.text = "No summon was completed. You may not have enough gems."
		return
	result_label.text = ""
	_clear_cards()
	# Every hero starts face down; nothing about it is shown until it flips.
	_pending_reveals.clear()
	for hero in results:
		# The grid lays out a fixed-size holder; the card inside it is free to
		# scale during the flip without the grid resetting it.
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE
		card_grid.add_child(holder)
		var card = _make_hidden_card()
		holder.add_child(card)
		_pending_reveals.append({"card": card, "hero": hero})
	_set_summoning(true)
	SoundBank.play_ui("summon")
	_reveal_tween = create_tween()
	for index in range(_pending_reveals.size()):
		_reveal_tween.tween_interval(REVEAL_INTERVAL)
		_reveal_tween.tween_callback(_reveal_next)
	_reveal_tween.tween_callback(_set_summoning.bind(false))


func _make_hidden_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE * 0.5
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1c1a2e")
	style.border_color = Color("#4a4470")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Face"
	label.text = "?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("#8a84b0"))
	card.add_child(label)
	return card


func _reveal_next() -> void:
	if _pending_reveals.is_empty():
		return
	var entry: Dictionary = _pending_reveals.pop_front()
	var card: PanelContainer = entry["card"]
	if not is_instance_valid(card):
		return
	var hero: Dictionary = entry["hero"]
	SoundBank.play_ui("card_flip")
	var flip := create_tween()
	flip.tween_property(card, "scale:x", 0.0, 0.1)
	flip.tween_callback(_show_card_face.bind(card, hero))
	flip.tween_callback(_play_reveal_sound.bind(int(hero.get("rarity", 1))))
	flip.tween_property(card, "scale:x", 1.0, 0.12)


func _show_card_face(card: PanelContainer, hero: Dictionary) -> void:
	var rarity = int(hero.get("rarity", 1))
	var color: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.7)
	style.border_color = color
	style.set_border_width_all(3 if rarity >= 5 else 2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	var label: Label = card.get_node("Face")
	label.text = "%s\n%d★ · %s" % [hero.get("name", "?"), rarity, hero.get("class", "")]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color.lightened(0.35))


# Higher rarities sound grander; 5 stars and up also ring a fanfare.
func _play_reveal_sound(rarity: int) -> void:
	if rarity >= 5:
		SoundBank.play_ui("reveal_legend", 1.0 + 0.08 * float(rarity - 5))
		SoundBank.play_ui("fanfare")
	elif rarity == 4:
		SoundBank.play_ui("reveal_epic")
	elif rarity == 3:
		SoundBank.play_ui("reveal_rare")
	else:
		SoundBank.play_ui("reveal_common", 0.9 + 0.1 * float(rarity))


func _reveal_all() -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	var best_rarity := 0
	while not _pending_reveals.is_empty():
		var entry: Dictionary = _pending_reveals.pop_front()
		if is_instance_valid(entry["card"]):
			_show_card_face(entry["card"], entry["hero"])
			best_rarity = maxi(best_rarity, int(entry["hero"].get("rarity", 1)))
	if best_rarity > 0:
		SoundBank.play_ui("card_flip")
		_play_reveal_sound(best_rarity)
	_set_summoning(false)


func _set_summoning(active: bool) -> void:
	for button in _summon_buttons:
		button.disabled = active
	skip_button.visible = active
	if not active:
		_update_balance()


func _clear_cards() -> void:
	for child in card_grid.get_children():
		child.queue_free()


func _update_balance() -> void:
	if is_instance_valid(balance_label):
		balance_label.text = "GEMS  %d  ·  OWNED HEROES  %d" % [
			GachaManager.get_gem_balance(),
			GachaManager.get_owned_hero_instances().size()
		]
