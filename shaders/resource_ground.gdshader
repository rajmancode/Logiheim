// Ground tint under natural-resource deposits (built by ResourceProps.build_ground).
// COLOR.rgb = the resource's tint, COLOR.a = strength (fades at the deposit's outer edge).
// Mottled with noise so it reads as soil, scree or stubble rather than a painted hex.
shader_type spatial;
render_mode blend_mul, depth_draw_never, cull_back, unshaded, fog_disabled;

#include "res://shaders/include/environment.gdshaderinc"

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A tint multiplied over the terrain, so the ground keeps all its own texture and relief:
	// the colour is normalised (hue only, no darkening of its own) and applied in irregular
	// blotches that also break up the hex edges of the deposit.
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world_pos.xz;
	float big = env_fbm(q * 0.04 + vec2(env_noise(q * 0.02) * 3.0));
	float fine = env_noise(q * 0.45);
	float blot = smoothstep(0.25, 0.8, big * 0.85 + fine * 0.25);
	float lum = max(dot(COLOR.rgb, vec3(0.3, 0.55, 0.15)), 0.05);
	vec3 hue = clamp(COLOR.rgb / lum * 0.92, vec3(0.45), vec3(1.6));
	float k = COLOR.a * (0.25 + 0.5 * blot);
	ALBEDO = mix(vec3(1.0), hue, clamp(k, 0.0, 0.75));
}
