shader_type sky;
// Painterly gradient sky with a glowing sun, drifting cloud bands and an
// optional star field for night regions.

uniform vec3 top_color : source_color = vec3(0.2, 0.3, 0.45);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.6, 0.4);
uniform vec3 ground_horizon : source_color = vec3(0.25, 0.2, 0.15);
uniform vec3 ground_bottom : source_color = vec3(0.05, 0.05, 0.05);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.8, 0.6);
uniform float star_amount = 0.0;
uniform float cloud_amount = 0.5;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color;
	if (dir.y >= 0.0) {
		float t = pow(clamp(dir.y, 0.0, 1.0), 0.45);
		color = mix(horizon_color, top_color, t);
		// Cloud bands: noise sampled on a dome projection.
		// Static clouds: reading TIME here would re-render the sky's radiance
		// map every frame.
		vec2 cloud_uv = dir.xz / max(dir.y + 0.15, 0.05) * 0.18;
		float clouds = texture(noise_tex, cloud_uv).r * 0.65 + texture(noise_tex, cloud_uv * 2.7).r * 0.35;
		clouds = smoothstep(0.5, 0.85, clouds) * cloud_amount * smoothstep(0.0, 0.25, dir.y);
		color = mix(color, mix(horizon_color, vec3(1.0), 0.25) * 0.9, clouds * 0.6);
		// Stars, hidden behind clouds and near the horizon.
		if (star_amount > 0.0) {
			vec3 cell = floor(dir * 260.0);
			float star = step(0.9975, hash(cell));
			color += vec3(star) * star_amount * (1.0 - clouds) * smoothstep(0.05, 0.4, dir.y);
		}
	} else {
		float t = pow(clamp(-dir.y, 0.0, 1.0), 0.5);
		color = mix(ground_horizon, ground_bottom, t);
	}
	// Sun glow and disc from the scene's main directional light.
	if (LIGHT0_ENABLED) {
		float sun = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		color += sun_tint * pow(sun, 8.0) * 0.35;
		color += sun_tint * pow(sun, 64.0) * 0.8;
		color += sun_tint * smoothstep(0.9993, 0.9997, sun) * 3.0;
	}
	COLOR = color;
}
