shader_type canvas_item;
// Light film grain and vignette over the 3D view (below the HUD). It only
// multiplies what is already on screen, so it needs no screen copy and costs
// almost nothing.
render_mode blend_mul, unshaded;

uniform float grain = 0.06;
uniform float vignette = 0.32;
uniform float vignette_softness = 0.55;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 centered = UV - 0.5;
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float edge = smoothstep(0.75 - vignette_softness, 0.95, length(centered) * 1.25);
	float frame = floor(TIME * 24.0);
	float noise = hash(FRAGCOORD.xy + frame * 13.7);
	float value = (1.0 - edge * vignette) * (1.0 - grain * noise);
	COLOR = vec4(vec3(value), 1.0);
}
