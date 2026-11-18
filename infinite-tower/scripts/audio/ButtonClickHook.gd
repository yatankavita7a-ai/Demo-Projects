extends Node

# Adds a click sound to every button under the node it is attached to,
# including buttons created later (menus here are rebuilt in code).
# Usage: add_child(ButtonClickHook.new())

const SoundBank = preload("res://scripts/audio/SoundBank.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hook_tree(get_parent())
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and get_parent() != null and get_parent().is_ancestor_of(node):
		_hook(node)


func _hook_tree(root: Node) -> void:
	if root == null:
		return
	for button in root.find_children("*", "BaseButton", true, false):
		_hook(button)


func _hook(button: BaseButton) -> void:
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)


func _play_click() -> void:
	SoundBank.play_ui("click")
