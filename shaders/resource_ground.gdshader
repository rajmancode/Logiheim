// Ground tint under natural-resource deposits (built by ResourceProps.build_ground).
// COLOR.rgb = the resource's tint, COLOR.a = strength (fades at the deposit's outer edge).
// Mottled with noise so it reads as soil, scree or stubble rather than a painted hex.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float big = env_fbm(v_world_pos.xz * 0.05);
	float fine = env_noise(v_world_pos.xz * 0.6);
	float blot = smoothstep(0.15, 0.85, big * 0.85 + fine * 0.25);
	vec3 col = COLOR.rgb * (0.8 + 0.35 * fine);
	ALBEDO = col * cloud_shadow(v_world_pos) * (1.0 - 0.2 * wetness);
	ROUGHNESS = 0.9 - 0.4 * wetness;
	ALPHA = COLOR.a * (0.45 + 0.55 * blot);
}
