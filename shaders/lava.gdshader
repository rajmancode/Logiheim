// Molten lava pool in a volcano crater (scripts/map/volcano_maker.gd): slowly churning glowing
// rock with a dark cooling crust that cracks open, brightest in the cracks.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/environment.gdshaderinc"

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz * 0.08;
	float t = TIME * 0.05;
	float n1 = env_fbm(p + vec2(t, -t * 0.7));
	float n2 = env_fbm(p * 2.3 - vec2(t * 1.3, t * 0.4) + n1 * 1.5);
	float crust = smoothstep(0.45, 0.62, n2);
	float pulse = 0.85 + 0.15 * sin(TIME * 0.7 + n1 * 6.0);
	vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.8, 0.3), smoothstep(0.2, 0.0, n2));
	vec3 crust_col = vec3(0.08, 0.06, 0.05);
	ALBEDO = mix(hot * 0.4, crust_col, crust);
	EMISSION = hot * (1.0 - crust) * 4.5 * pulse;
	ROUGHNESS = mix(0.4, 0.95, crust);
}
