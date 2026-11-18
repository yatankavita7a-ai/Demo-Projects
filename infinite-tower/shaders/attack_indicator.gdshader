shader_type spatial;
// Ground telegraph for boss attacks (scripts/battle/AttackIndicator.gd).
// The shape is cut out in the fragment shader.
// shape_type: 0 cone, 1 circle, 2 ring, 3 line, 4 box.
// Projected onto whatever opaque surface lies inside a box volume (terrain,
// slopes, steps), using the depth buffer like a deferred decal.
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform int shape_type = 1;
uniform vec2 plane_size = vec2(4.0, 4.0);   // metres (x: width, y: depth)
uniform float box_height = 4.0;
uniform float radius = 2.0;
uniform float half_angle = 0.785;           // cone half-width, radians
uniform float ring_inner = 0.0;             // ring band, metres from centre
uniform float ring_outer = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float strength = 1.0;               // overall opacity
uniform float edge_width = 0.12;            // outline, metres

void fragment() {
	// Rebuild the surface position behind this pixel (Forward+ reverse-Z).
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 local = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	if (abs(local.y) > box_height * 0.5 || abs(local.x) > plane_size.x * 0.5 + 0.01 || abs(local.z) > plane_size.y * 0.5 + 0.01) {
		discard;
	}
	// Only mark ground-like surfaces, not the sides of bodies standing in it.
	vec3 normal = normalize(cross(dFdy(world), dFdx(world)));
	float upward = smoothstep(0.35, 0.6, abs(normal.y));
	// Local plane coordinates in metres; -y points forward (away from the
	// attacker), matching Godot's -Z forward.
	vec2 p = local.xz;
	float inside = 0.0;
	float edge = 0.0;
	float fill = 0.0;
	float e = edge_width;
	if (shape_type == 0 || shape_type == 1 || shape_type == 2) {
		float d = length(p);
		if (shape_type == 0) {
			float ang = acos(clamp(dot(normalize(p + vec2(0.0, -0.0001)), vec2(0.0, -1.0)), -1.0, 1.0));
			inside = step(d, radius) * step(ang, half_angle);
			float arc_edge = step(radius - e, d);
			float side_edge = step(d * sin(abs(ang - half_angle)), e) * step(ang, half_angle + 0.02);
			edge = inside * max(arc_edge, side_edge);
			fill = inside * step(d, radius * progress);
		} else if (shape_type == 1) {
			inside = step(d, radius);
			edge = inside * step(radius - e, d);
			fill = inside * step(d, radius * progress);
		} else {
			// Ring: a faint disc and outer edge plus the bright travelling band.
			inside = step(d, radius) * 0.15;
			edge = step(d, radius) * step(radius - e, d) * 0.6;
			fill = step(ring_inner, d) * step(d, ring_outer) * step(0.001, ring_outer);
		}
	} else {
		// Line / box: the plane is the rectangle; it fills from the attacker
		// (y = +depth/2) toward the far end.
		vec2 half_size = plane_size * 0.5;
		inside = step(abs(p.x), half_size.x) * step(abs(p.y), half_size.y);
		float ex = step(half_size.x - e, abs(p.x));
		float ey = step(half_size.y - e, abs(p.y));
		edge = inside * max(ex, ey);
		float along = (half_size.y - p.y) / max(plane_size.y, 0.001);
		fill = inside * step(along, progress);
		if (shape_type == 4) {
			// Low sweep: chevron stripes hint "jump or roll".
			float stripes = step(0.5, fract((p.y + abs(p.x) * 0.5) * 0.8));
			fill *= 0.75 + 0.25 * stripes;
		}
	}
	if (inside + fill < 0.001) {
		discard;
	}
	float a = inside * 0.16 + fill * 0.38 + edge * 0.55;
	ALBEDO = tint.rgb * (1.0 + edge * 0.6);
	ALPHA = clamp(a * strength * tint.a * upward, 0.0, 1.0);
}
