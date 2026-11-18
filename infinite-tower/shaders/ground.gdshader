shader_type spatial;
// Terrain built from photo-scanned surfaces.
// - Primary/secondary ground blend along the textures' own detail (a
//   height-lerp), so transitions follow soil and stones instead of a smear.
// - Rock is projected onto steep slopes from three axes (triplanar).
// - Two sampling scales, mixed more strongly with distance, hide tiling.
// - Vertex COLOR.r carries a cavity term: hollows darken like real ground.
// - Wet regions darken and gloss their low ground; in rain, flat hollows
//   hold mirror-like puddles stippled with expanding raindrop ripples.
// - Optional lava seams glow in low ground.

uniform sampler2D primary_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D primary_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D primary_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D secondary_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D secondary_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform float texture_scale = 0.22;
uniform float hill_height = 5.0;
uniform float lava_strength = 0.0;
uniform float wetness = 0.0;
uniform float puddle_amount = 0.0; // 0..1 how much flat ground holds water
uniform float rain_amount = 0.0;   // 0..1 raindrop ripples and overall sheen
uniform sampler2D puddle_mask : filter_linear, repeat_disable; // 1 m/pixel over the terrain
uniform float terrain_half_size = 75.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float cavity;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cavity = COLOR.r;
}

vec2 rotate_uv(vec2 uv) {
	return mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.17);
}

vec2 hash22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// Raindrop rings: each cell of a grid holds one drop on its own clock; the
// ring expands and fades. Returns a tangent-space normal offset.
vec2 ripples(vec2 p, float time) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 offset_sum = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash22(cell + o);
			float phase = fract(time * 0.9 + h.x * 13.0);
			vec2 d = local - (o + h);
			float dist = length(d);
			float radius = phase * 0.75;
			float band = smoothstep(0.12, 0.0, abs(dist - radius));
			float wave = sin((dist - radius) * 40.0) * band * (1.0 - phase) * (1.0 - phase);
			offset_sum += d / max(dist, 0.001) * wave;
		}
	}
	return offset_sum;
}

void fragment() {
	float distance_to_camera = length(CAMERA_POSITION_WORLD - world_pos);
	float far = smoothstep(18.0, 70.0, distance_to_camera);
	vec2 uv = world_pos.xz * texture_scale;
	vec2 uv_far = rotate_uv(uv);
	float broad = texture(noise_tex, world_pos.xz * 0.018).r;
	float detail = texture(noise_tex, world_pos.xz * 0.21).r;
	float macro = texture(noise_tex, world_pos.xz * 0.006).r;
	float tiling_mix = clamp(smoothstep(0.35, 0.65, texture(noise_tex, world_pos.xz * 0.04).r) * 0.55 + far * 0.45, 0.0, 1.0);

	vec3 primary = mix(texture(primary_albedo, uv).rgb, texture(primary_albedo, uv_far).rgb, tiling_mix);
	vec3 secondary = mix(texture(secondary_albedo, uv * 0.8).rgb, texture(secondary_albedo, uv_far * 0.8).rgb, tiling_mix);
	vec3 primary_n = mix(texture(primary_normal, uv).rgb, texture(primary_normal, uv_far).rgb, tiling_mix);
	vec3 secondary_n = mix(texture(secondary_normal, uv * 0.8).rgb, texture(secondary_normal, uv_far * 0.8).rgb, tiling_mix);
	float primary_roughness = mix(texture(primary_rough, uv).r, texture(primary_rough, uv_far).r, tiling_mix);

	// Height-lerp: the brighter (raised) parts of each texture win near the
	// boundary, so one surface breaks through the other along its detail.
	float blend_target = broad + world_pos.y / max(hill_height, 0.1) * 0.25;
	float primary_height = dot(primary, vec3(0.333));
	float secondary_height = dot(secondary, vec3(0.333));
	float secondary_mask = smoothstep(-0.08, 0.08, (blend_target - 0.55) + (secondary_height - primary_height) * 0.6);
	vec3 ground = mix(primary, secondary, secondary_mask);
	vec3 ground_n = mix(primary_n, secondary_n, secondary_mask);
	float ground_rough = mix(primary_roughness, 0.9, secondary_mask);

	// Rock on slopes, projected from each axis so it does not stretch.
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= (blend.x + blend.y + blend.z);
	float rock_scale = texture_scale * 0.6;
	vec2 rock_uv_x = world_pos.zy * rock_scale;
	vec2 rock_uv_y = world_pos.xz * rock_scale;
	vec2 rock_uv_z = world_pos.xy * rock_scale;
	vec3 rock = texture(rock_albedo, rock_uv_x).rgb * blend.x
		+ texture(rock_albedo, rock_uv_y).rgb * blend.y
		+ texture(rock_albedo, rock_uv_z).rgb * blend.z;
	vec3 rock_n = texture(rock_normal, rock_uv_x).rgb * blend.x
		+ texture(rock_normal, rock_uv_y).rgb * blend.y
		+ texture(rock_normal, rock_uv_z).rgb * blend.z;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_height = dot(rock, vec3(0.333));
	float rock_mask = smoothstep(-0.06, 0.06, slope - 0.3 + (detail - 0.5) * 0.15 + (rock_height - 0.4) * 0.3);

	vec3 color = mix(ground * tint, rock * rock_tint, rock_mask);
	// Large-scale variation in tone, like patches of drier and richer soil.
	color *= 0.86 + (macro - 0.5) * 0.35 + (broad - 0.5) * 0.15;
	// Hollows collect shadow and debris.
	color *= mix(0.62, 1.0, cavity);
	float roughness = mix(ground_rough, 0.85, rock_mask);
	// Wet low ground: darker and glossier. Rain wets everything a little.
	float wet = wetness * (1.0 - smoothstep(0.2, 1.6, world_pos.y)) * (1.0 - rock_mask * 0.5);
	wet = max(wet, rain_amount * 0.55 * (1.0 - rock_mask * 0.4));
	color *= 1.0 - wet * 0.45;
	roughness = mix(roughness, 0.25, wet);
	vec3 normal_map = mix(ground_n, rock_n, rock_mask);
	float normal_depth = mix(1.3, 0.6, far);

	// Puddles: the baked mask (flat, low ground) broken up by fine noise,
	// hollows and the texture's own height, so stones break the surface.
	if (puddle_amount > 0.0) {
		float hollow = 1.0 - cavity;
		float mask = texture(puddle_mask, (world_pos.xz + terrain_half_size) / (terrain_half_size * 2.0)).r;
		float flat_ground = smoothstep(0.9, 0.98, world_normal.y) * (1.0 - rock_mask);
		float pool = mask * 1.3 + (detail - 0.5) * 0.5 + hollow * 0.6 - dot(ground, vec3(0.333)) * 0.5;
		float puddle = smoothstep(0.55, 0.7, pool) * flat_ground;
		// A damp, darker rim just outside each puddle.
		float rim = smoothstep(0.3, 0.55, pool) * flat_ground;
		color *= 1.0 - rim * 0.25;
		roughness = mix(roughness, 0.18, rim);
		color = mix(color, color * 0.32, puddle);
		roughness = mix(roughness, 0.02, puddle);
		vec3 water_n = vec3(0.5, 0.5, 1.0);
		if (rain_amount > 0.0 && far < 0.99) {
			vec2 ring = ripples(world_pos.xz * 1.6, TIME) + ripples(world_pos.xz * 2.3 + 7.7, TIME * 1.13) * 0.7;
			water_n.xy += ring * 0.22 * rain_amount * (1.0 - far);
		}
		normal_map = mix(normal_map, water_n, puddle);
		normal_depth = mix(normal_depth, 1.0, puddle);
		SPECULAR = mix(0.5, 0.6, puddle);
	}

	ALBEDO = color;
	NORMAL_MAP = normal_map;
	// Fine normal detail fades with distance to avoid shimmer.
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = roughness;
	if (lava_strength > 0.0) {
		float seam = 1.0 - smoothstep(0.0, 0.012, abs(broad - 0.5));
		seam *= smoothstep(0.45, 0.6, detail);
		float low = 1.0 - smoothstep(0.3, 1.2, world_pos.y);
		float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + world_pos.x * 0.2);
		EMISSION = vec3(1.0, 0.32, 0.06) * seam * low * lava_strength * pulse * 2.2;
	}
}
