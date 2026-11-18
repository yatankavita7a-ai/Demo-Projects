extends Node3D

# A boss projectile (water bolt, arrow). Flies in a straight line toward
# where the player was when it was fired; it does not home. Parrying it
# deflects (destroys) it. Spawned by BossBrain into the floor's world node,
# so the floor's _clear_world frees it with everything else.

const BossMoves = preload("res://scripts/battle/BossMoves.gd")
const LIFETIME := 3.5
const PLAYER_RADIUS := 0.4

var source       # EnemyAgent that fired it
var target       # player
var direction := Vector3.FORWARD
var speed := 14.0
var radius := 0.5
var damage := 10.0
var tint := Color(0.4, 0.75, 1.0)
var _life := LIFETIME
var _evaded := false


func setup(from_agent, player_node, start: Vector3, aim_direction: Vector3, settings: Dictionary, amount: float) -> void:
	source = from_agent
	target = player_node
	direction = aim_direction.normalized()
	speed = float(settings.get("speed", speed))
	radius = float(settings.get("radius", radius))
	damage = amount
	position = start


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stretched along the flight path so it reads as a streak.
	mesh.scale = Vector3(0.7, 0.7, 1.8)
	add_child(mesh)
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(source) or source.is_roaring():
		queue_free()
		return
	var step := direction * speed * delta
	var from := global_position
	var to := from + step
	if _blocked(from, to):
		queue_free()
		return
	global_position = to
	if is_instance_valid(target):
		var chest: Vector3 = target.global_position + Vector3.UP * 1.0
		if _segment_distance(from, to, chest) <= radius + PLAYER_RADIUS:
			var info := {"parryable": true, "unblockable": false, "knockback": Vector3(direction.x, 0.0, direction.z) * 2.5}
			# A dodge's i-frames let it pass straight through.
			var dodging: bool = target.has_method("is_invulnerable") and target.is_invulnerable()
			if dodging and _evaded:
				return
			BossMoves.deliver_attack(target, damage, self, info)
			if dodging:
				_evaded = true
			else:
				queue_free()


# Called by the player on a successful parry: the bolt is deflected.
func on_parried() -> void:
	queue_free()


func _blocked(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	if is_instance_valid(target) and target is CollisionObject3D:
		exclude.append(target.get_rid())
	for enemy in get_tree().get_nodes_in_group("tower_enemies"):
		if enemy is CollisionObject3D:
			exclude.append(enemy.get_rid())
	query.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (a + ab * t).distance_to(p)
