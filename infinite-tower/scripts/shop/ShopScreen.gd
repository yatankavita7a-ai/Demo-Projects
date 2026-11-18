extends Control

# The Quartermaster: spend gems on equipment. Items unlock by highest floor
# reached and have purchase limits; bought gear goes to the inventory, where
# it can be equipped in the tower (I).

const Shop = preload("res://scripts/systems/ShopCatalog.gd")
const Equipment = preload("res://scripts/systems/EquipmentCatalog.gd")
const SoundBank = preload("res://scripts/audio/SoundBank.gd")
const RARITY_COLORS := {"common": Color("#c9c2b4"), "unusual": Color("#7fb3e0"), "rare": Color("#e3b04a")}

var balance_label: Label
var message_label: Label
var list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("#14110f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "THE QUARTERMASTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _inscription_font(5))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f4ead8"))
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Arms and relics traded for gems. New stock arrives as you climb."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#bfb3a0"))
	layout.add_child(subtitle)
	balance_label = Label.new()
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_label.add_theme_font_override("font", _inscription_font(2))
	balance_label.add_theme_font_size_override("font_size", 18)
	balance_label.add_theme_color_override("font_color", Color("#e3c48e"))
	layout.add_child(balance_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color("#f3d6a0"))
	layout.add_child(message_label)
	var back := Button.new()
	back.text = "RETURN TO MAIN MENU"
	back.custom_minimum_size.y = 46
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))
	layout.add_child(back)
	GachaManager.currency_changed.connect(_refresh)
	_refresh()
	add_child(preload("res://scripts/audio/ButtonClickHook.gd").new())


func _refresh() -> void:
	if not is_instance_valid(list):
		return
	balance_label.text = "GEMS  %d" % GachaManager.get_gem_balance()
	for child in list.get_children():
		child.queue_free()
	for entry in Shop.STOCK:
		list.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> PanelContainer:
	var item = Equipment.get_item(entry["item"])
	var status = PlayerData.shop_item_status(entry["item"])
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.09, 0.08, 0.95)
	style.border_color = Color("#5a4a3a") if status != "ok" else Color("#a8926a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	row.add_child(columns)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s   ·   %s %s" % [item["name"], item["rarity"].capitalize(), item["slot"]]
	name_label.add_theme_font_override("font", _inscription_font(1))
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", RARITY_COLORS.get(item["rarity"], Color.WHITE))
	info.add_child(name_label)
	var stats := []
	if int(item["attack"]) > 0:
		stats.append("+%d attack" % int(item["attack"]))
	if int(item["defense"]) > 0:
		stats.append("+%d defense" % int(item["defense"]))
	var detail := Label.new()
	detail.text = "%s  —  %s" % [", ".join(stats), item["effect"]]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color("#bfb3a0"))
	info.add_child(detail)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(210, 44)
	match status:
		"ok":
			buy.text = "BUY  ·  %d GEMS" % int(entry["price"])
			buy.pressed.connect(_buy.bind(entry["item"]))
		"locked":
			buy.text = "UNLOCKS AT FLOOR %d" % int(entry["unlock_floor"])
			buy.disabled = true
		"sold_out":
			buy.text = "SOLD OUT"
			buy.disabled = true
		"gems":
			buy.text = "%d GEMS  ·  NOT ENOUGH" % int(entry["price"])
			buy.disabled = true
		_:
			buy.text = "UNAVAILABLE"
			buy.disabled = true
	columns.add_child(buy)
	return row


func _buy(item_id: String) -> void:
	var result = PlayerData.buy_shop_item(item_id)
	var item = Equipment.get_item(item_id)
	match result:
		"ok":
			SoundBank.play_ui("coins")
			SoundBank.play_ui("confirm")
			message_label.text = "%s added to your equipment. Equip it in the tower with I." % item.get("name", "Item")
		"gems":
			SoundBank.play_ui("error")
			message_label.text = "You need more gems for that."
		_:
			SoundBank.play_ui("error")
			message_label.text = "The purchase could not be completed."
	# currency_changed already refreshed the list after a successful purchase.
	if result != "ok":
		_refresh()


func _inscription_font(letter_spacing: int) -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Copperplate", "Optima", "Palatino", "Georgia", "serif"])
	system.font_weight = 700
	var font := FontVariation.new()
	font.base_font = system
	font.spacing_glyph = letter_spacing
	return font
