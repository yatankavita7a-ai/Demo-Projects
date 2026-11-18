extends Area3D
class_name WorldInteractable

signal activated(interactable: WorldInteractable)

@export var prompt_text := "Interact"
@export var interaction_kind := ""
@export var interaction_id := ""
@export var concealed := true

var discovered := false


func _ready() -> void:
	add_to_group("world_interactables")
	var trigger := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	trigger.shape = shape
	add_child(trigger)
	if concealed:
		for child in get_children():
			if child is VisualInstance3D:
				child.visible = false
	monitoring = false
	monitorable = false


func reveal() -> void:
	discovered = true
	for child in get_children():
		if child is VisualInstance3D:
			child.visible = true


func activate_for(actor: Node) -> void:
	activated.emit(self)
