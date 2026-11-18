extends MeshInstance3D

# Ground telegraph decal for a boss attack: a box volume whose shader
# projects a cone, circle, ring, line or box onto the ground inside it
# (following slopes) and fills it over the wind-up.
# Colour code (docs/BOSS_SYSTEM.md): orange = normal, yellow flash shortly
# before a parryable impact, red = unblockable. Lingering hazards use a tint.
# Purely visual: hit tests use BossMoves.shape_contains with the same shape.

const SHADER = preload("res://shaders/attack_indicator.gdshader")
const SHAPE_IDS := {"cone": 0, "circle": 1, "ring": 2, "line": 3, "box": 4}
const COLORS := {
	"normal": Color(1.0, 0.45, 0.08),
	"yellow": Color(1.0, 0.88, 0.12),
	"red": Color(0.95, 0.07, 0.05),
	"fire": Color(1.0, 0.32, 0.04),
	"root": Color(0.45, 0.78, 0.2),
	"dark": Color(0.42, 0.12, 0.62),
	"frost": Color(0.6, 0.85, 1.0),
	"water": Color(0.2, 0.62, 1.0),
	"stagger": Color(1.0, 1.0, 1.0),
	"poison": Color(0.55, 0.85, 0.1),
	"chain": Color(0.95, 0.8, 0.45),
}
const GROUND_LIFT := 0.0
const BOX_HEIGHT := 5.0  # projects onto ground up to 2.5 m above or below

var shape: Dictionary = {}
var kind := "normal"
var _material: ShaderMaterial


# Builds the plane for `shape_data` (see BossMoves) in the parent's local
# frame: the attacker stands at the origin facing -Z.
func setup(shape_data: Dictionary, color_kind: String = "normal") -> void:
	shape = shape_data
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	var type := String(shape.get("type", "circle"))
	var offset := float(shape.get("offset", 0.0))
	var size := Vector2.ONE
	var centre := Vector3.ZERO
	match type:
		"cone", "circle", "ring":
			var radius := maxf(0.1, float(shape.get("radius", 1.0)))
			size = Vector2(radius * 2.0, radius * 2.0)
			centre = Vector3(0.0, 0.0, -offset if type == "circle" else 0.0)
			_material.set_shader_parameter("radius", radius)
		_:
			var length := maxf(0.1, float(shape.get("length", 1.0)))
			size = Vector2(maxf(0.1, float(shape.get("width", 1.0))), length)
			centre = Vector3(0.0, 0.0, -(offset + length * 0.5))
	box.size = Vector3(size.x, BOX_HEIGHT, size.y)
	mesh = box
	# Generous bounds so the volume is not culled while the camera is inside.
	extra_cull_margin = 2.0
	position = centre + Vector3.UP * GROUND_LIFT
	_material.set_shader_parameter("shape_type", SHAPE_IDS.get(type, 1))
	_material.set_shader_parameter("plane_size", size)
	_material.set_shader_parameter("box_height", BOX_HEIGHT)
	_material.set_shader_parameter("half_angle", deg_to_rad(float(shape.get("angle", 90.0)) * 0.5))
	_material.set_shader_parameter("edge_width", clampf(maxf(size.x, size.y) * 0.02, 0.08, 0.3))
	set_kind(color_kind)
	set_progress(0.0)


func set_progress(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func set_kind(color_kind: String) -> void:
	kind = color_kind
	if _material != null:
		_material.set_shader_parameter("tint", COLORS.get(color_kind, COLORS["normal"]))


func set_strength(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("strength", maxf(0.0, value))


# Ring shockwave: the bright band between inner and outer (metres).
func set_ring(inner: float, outer: float) -> void:
	if _material != null:
		_material.set_shader_parameter("ring_inner", maxf(0.0, inner))
		_material.set_shader_parameter("ring_outer", maxf(0.0, outer))
