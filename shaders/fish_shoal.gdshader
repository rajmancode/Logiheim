// A shoal of fish under the surface: dark moving shapes, ripples and silver flashes.
// Drawn on a flat quad just above the water (scripts/map/resource_props.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

#include "res://shaders/include/environment.gdshaderinc"

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, length(uv));
	vec2 p = v_world_pos.xz * 0.35;
	// The school drifts in a slow circle.
	vec2 swim = vec2(sin(TIME * 0.3), cos(TIME * 0.27)) * 1.5;
	float body = smoothstep(0.62, 0.8, env_noise(p * 1.8 + swim) * 0.6 + env_noise(p * 4.0 - swim * 1.7) * 0.4);
	float rings = sin(length(uv) * 22.0 - TIME * 3.0) * 0.5 + 0.5;
	rings *= smoothstep(0.2, 0.9, env_noise(p * 0.8 + vec2(TIME * 0.2)));
	float flash = smoothstep(0.93, 0.99, env_noise(p * 6.0 + vec2(TIME * 1.3, -TIME)));
	vec3 col = mix(vec3(0.02, 0.06, 0.07), vec3(0.85, 0.92, 0.95), flash + rings * 0.25);
	ALBEDO = col;
	ALPHA = edge * clamp(body * 0.65 + rings * 0.2 + flash * 0.9, 0.0, 0.85);
}
