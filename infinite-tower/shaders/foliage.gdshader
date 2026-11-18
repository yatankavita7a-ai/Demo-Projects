shader_type spatial;
// Tree canopies: gentle wind sway that grows with height, noise-broken colour
// and soft light passing through the leaves.

uniform vec3 leaf_color : source_color = vec3(0.3, 0.4, 0.2);
uniform float sway = 0.12;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.17;
	float bend = max(VERTEX.y, 0.0) * sway;
	VERTEX.x += sin(TIME * 1.1 + phase) * bend * 0.12;
	VERTEX.z += cos(TIME * 0.9 + phase) * bend * 0.08;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, world_pos.xz * 0.4 + world_pos.y * 0.2).r;
	ALBEDO = leaf_color * (0.7 + n * 0.55);
	ROUGHNESS = 0.85;
	BACKLIGHT = leaf_color * 0.4;
}
