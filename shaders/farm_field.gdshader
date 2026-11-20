// Farm fields draped over the terrain: furrowed strips of barley, rye and flax in different
// stages (green to ripe gold), rippling in the wind. UV.x across the furrows (metres),
// UV.y along them; COLOR = the field's crop colour.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

varying vec3 v_world_pos;
varying vec3 v_crop;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_crop = COLOR.rgb;
}

void fragment() {
	float furrow = 0.5 + 0.5 * sin(UV.x * TAU / 1.2);
	// Wind waves rolling over the crop.
	float wave = env_noise(v_world_pos.xz * 0.06 - wind_direction * wind_time * 1.5);
	float sheen = smoothstep(0.55, 0.9, wave) * (0.2 + 0.5 * wind_strength);
	vec3 col = v_crop * (0.72 + 0.28 * furrow);
	col = mix(col, col * 1.35 + vec3(0.05), sheen);
	col *= 0.9 + 0.2 * env_noise(v_world_pos.xz * 0.4);
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = v_crop * 0.25;
}
