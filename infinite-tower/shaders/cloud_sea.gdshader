shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// A drifting sea of clouds far below the floating island.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 offset = vec2(0.0);
uniform float density = 0.7;
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 1.0);
uniform vec3 shade_color : source_color = vec3(0.78, 0.8, 0.95);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.0025 + offset + vec2(TIME * 0.003, TIME * 0.0015);
	float n = texture(noise_tex, uv).r * 0.6 + texture(noise_tex, uv * 2.9).r * 0.4;
	float cover = smoothstep(0.42 - density * 0.2, 0.75, n);
	float fade = 1.0 - smoothstep(350.0, 680.0, length(world_pos.xz));
	ALBEDO = mix(shade_color, cloud_color, smoothstep(0.5, 0.9, n));
	ALPHA = cover * fade;
}
