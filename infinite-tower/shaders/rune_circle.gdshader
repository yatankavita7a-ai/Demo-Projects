shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;
// Concentric glowing rune rings, slowly turning, drawn on a flat quad.

uniform vec3 glow_color : source_color = vec3(0.45, 0.85, 1.0);
uniform float intensity = 1.6;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rings = smoothstep(0.02, 0.0, abs(r - 0.92)) + smoothstep(0.015, 0.0, abs(r - 0.78))
		+ smoothstep(0.012, 0.0, abs(r - 0.45));
	// Rune ticks between the two outer rings rotate with time.
	float ticks = step(0.5, fract((a + TIME * 0.15) * 12.0 / 6.2831)) * step(0.8, r) * step(r, 0.9);
	float glyphs = smoothstep(0.04, 0.0, abs(fract((a - TIME * 0.1) * 6.0 / 6.2831) - 0.5) - 0.42) * step(0.5, r) * step(r, 0.74) * 0.6;
	float star = smoothstep(0.02, 0.0, abs(abs(p.x) + abs(p.y) - 0.42)) * step(r, 0.45);
	float mask = (rings + ticks * 0.7 + glyphs + star) * step(r, 1.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 1.5);
	ALBEDO = glow_color * mask * intensity * pulse;
	ALPHA = clamp(mask, 0.0, 1.0);
}
