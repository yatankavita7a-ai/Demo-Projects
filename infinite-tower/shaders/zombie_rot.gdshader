shader_type spatial;

// Dead Tide zombies (floor 10): the borrowed monster's own texture,
// desaturated and tinted a sickly grey-green. Used by ModelRig.apply_rot().

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 rot_tint : source_color = vec4(0.75, 0.9, 0.6, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec4 colour = base_color;
	if (has_texture) {
		colour *= texture(albedo_tex, UV);
	}
	float grey = dot(colour.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(colour.rgb, vec3(grey) * rot_tint.rgb, amount);
	ROUGHNESS = 0.92;
}
