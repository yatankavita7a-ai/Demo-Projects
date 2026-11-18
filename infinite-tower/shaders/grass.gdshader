shader_type spatial;
render_mode cull_disabled;
// Grass blades drawn with a MultiMesh. Tips sway in gusting wind; colour runs
// from the base to a lighter, sun-caught tip.

uniform vec3 base_color : source_color = vec3(0.2, 0.3, 0.1);
uniform vec3 tip_color : source_color = vec3(0.7, 0.6, 0.3);
uniform float wind_strength = 0.35;
uniform vec2 wind_direction = vec2(1.0, 0.4);

varying float blade_height;
varying float blade_variation;
varying float wave_light;

void vertex() {
	blade_height = UV.y;
	vec2 root = MODEL_MATRIX[3].xz;
	blade_variation = fract(sin(dot(root, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Blades shrink into the ground with distance, so the edge of the drawn
	// grass is a soft fade rather than a visible line.
	float fade = 1.0 - smoothstep(42.0, 68.0, length(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz));
	VERTEX.y *= fade;
	// Rolling wind waves: broad bands travel across the field along the wind,
	// with smaller flutter on top. Bent blades catch more light (wave_light),
	// so gusts read as bright ripples sweeping through the grass.
	vec2 wind = normalize(wind_direction);
	float along = dot(world.xz, wind);
	float wave = sin(along * 0.18 - TIME * 2.2) * 0.5 + 0.5;
	wave = pow(wave, 3.0);
	float flutter = sin(TIME * 3.3 + world.x * 0.7 + world.z * 0.4) * 0.15;
	float gust = 0.25 + wave * 0.9 + flutter;
	wave_light = wave;
	vec2 sway = wind * gust * wind_strength * UV.y * UV.y;
	VERTEX.xz += (inverse(mat3(MODEL_MATRIX)) * vec3(sway.x, 0.0, sway.y)).xz;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 tip = mix(tip_color, base_color * 1.2, blade_variation * 0.55);
	ALBEDO = mix(base_color * 0.45, tip, blade_height) * (0.85 + blade_variation * 0.3);
	ALBEDO *= 1.0 + wave_light * blade_height * 0.35;
	ROUGHNESS = 0.9;
	BACKLIGHT = tip_color * 0.35 * blade_height;
}
