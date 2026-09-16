// Ground: original terrain texture, sampled at two scales and blended by low-frequency
// noise so the 2048px tile doesn't read as an obvious grid from RTS height.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float tile_size = 24.0;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_a = world_pos.xz / tile_size;
	vec2 uv_b = world_pos.xz / (tile_size * 2.7) + vec2(0.37, 0.61);
	float n = texture(noise_tex, world_pos.xz / 180.0).r;
	vec3 a = texture(albedo_tex, uv_a).rgb;
	vec3 b = texture(albedo_tex, uv_b).rgb;
	vec3 v = texture(variation_tex, uv_a * 0.8).rgb;
	vec3 base = mix(a, b, smoothstep(0.3, 0.7, n));
	ALBEDO = mix(base, v, smoothstep(0.55, 0.9, n) * variation_strength);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
