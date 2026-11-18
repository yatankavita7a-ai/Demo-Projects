shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// A faint hexagonal barrier: glowing cell edges, brightest at grazing angles,
// with a slow shimmer travelling across it.

uniform vec3 edge_color : source_color = vec3(0.85, 0.6, 1.0);
uniform float cell_scale = 18.0;

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

float hex_edge(vec2 p) {
	p *= cell_scale;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float d = max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
	return smoothstep(0.43, 0.5, d);
}

void fragment() {
	vec2 sphere_uv = vec2(atan(local_dir.z, local_dir.x) / 6.2831, local_dir.y * 0.5);
	float edges = hex_edge(sphere_uv * vec2(2.0, 1.0));
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float shimmer = 0.5 + 0.5 * sin(local_dir.y * 9.0 - TIME * 0.8 + local_dir.x * 4.0);
	float alpha = edges * (0.08 + fresnel * 0.5) * (0.6 + 0.4 * shimmer);
	ALBEDO = edge_color * alpha * 1.6;
	ALPHA = alpha;
}
