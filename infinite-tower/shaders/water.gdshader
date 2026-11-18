shader_type spatial;
render_mode cull_disabled;
// Flood water: dark, glossy, with drifting ripples and a brighter rim at
// grazing angles.

uniform vec3 deep_color : source_color = vec3(0.05, 0.09, 0.11);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.26, 0.28);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_a = world_pos.xz * 0.06 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv_b = world_pos.xz * 0.11 - vec2(TIME * 0.017, -TIME * 0.021);
	float ripple = texture(noise_tex, uv_a).r * 0.5 + texture(noise_tex, uv_b).r * 0.5;
	NORMAL_MAP = vec3(0.5 + (ripple - 0.5) * 0.6, 0.5 + (ripple - 0.5) * 0.6, 1.0);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, fresnel);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = 0.88;
}
