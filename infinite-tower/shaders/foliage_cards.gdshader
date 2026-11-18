shader_type spatial;
render_mode cull_disabled;
// Leaf-card canopies: each card is cut out by a cellular "leaf cluster"
// pattern (alpha scissor) and faded toward its edges, so many overlapping
// cards read as a soft, broken canopy instead of a solid blob. Normals point
// out from the canopy centre for rounded lighting; COLOR.r carries how deep
// a card sits inside the canopy, darkening the interior.

uniform vec3 leaf_color : source_color = vec3(0.35, 0.4, 0.2);
uniform sampler2D leaf_mask : filter_linear_mipmap, repeat_enable;
uniform float sway = 0.1;

varying float depth_shade;

void vertex() {
	depth_shade = COLOR.r;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.17;
	float bend = max(VERTEX.y - 2.0, 0.0) * sway;
	VERTEX.x += sin(TIME * 1.3 + phase + VERTEX.y) * bend * 0.1;
	VERTEX.z += cos(TIME * 1.1 + phase) * bend * 0.07;
}

void fragment() {
	// cull_disabled flips back-face normals; undo that so every card keeps
	// the outward canopy normal and is lit from outside.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float cells = texture(leaf_mask, UV).r;
	float edge = length(UV2 - vec2(0.5)) * 2.0;
	float mask = cells - edge * 0.55;
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.32;
	float variation = texture(leaf_mask, UV * 0.37 + 0.5).r;
	vec3 color = leaf_color * (0.55 + variation * 0.6);
	color *= mix(0.45, 1.0, depth_shade);
	ALBEDO = color;
	ROUGHNESS = 0.8;
	BACKLIGHT = leaf_color * 0.5;
}
