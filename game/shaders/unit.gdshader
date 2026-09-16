// Units and buildings: the skin's alpha channel is a player-colour mask (see docs/HANDOVER.md).
// Masked texels are near-black and their alpha gradient carries the garment's shading,
// so the player colour is added where alpha < 1.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D skin : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 player_color : source_color = vec3(0.12, 0.32, 0.85);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 tex = texture(skin, UV);
	ALBEDO = tex.rgb + player_color * (1.0 - tex.a);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
	RIM = rim_strength;
	RIM_TINT = 0.4;
}
