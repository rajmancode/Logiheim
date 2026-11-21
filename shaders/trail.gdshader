// Trails (scripts/map/road_network.gd): packed earth and gravel from the terrain texture set,
// two worn wheel ruts with a strip of grass between them, ragged soft edges that fade into the
// ground around. UV.x across the trail (0..1), UV.y metres along it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
const float T_DIRT = 18.0;
const float T_GRAVEL = 21.0;
const float T_GRASS = 4.0;
const float T_MUD = 19.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float x = UV.x;
	float rag = (env_noise(p * 0.7) - 0.5) * 0.1 + (env_noise(p * 2.5) - 0.5) * 0.05;
	float edge = smoothstep(0.0, 0.16, x + rag) * smoothstep(1.0, 0.84, x - rag);
	vec3 dirt = texture(albedo_array, vec3(p / 3.5, T_DIRT)).rgb;
	vec3 gravel = texture(albedo_array, vec3(p / 3.0, T_GRAVEL)).rgb;
	vec3 grass = texture(albedo_array, vec3(p / 4.0, T_GRASS)).rgb;
	vec3 mud = texture(albedo_array, vec3(p / 4.0, T_MUD)).rgb;
	float g = smoothstep(0.4, 0.7, env_noise(p * 0.15));
	vec3 col = mix(dirt, gravel, g);
	// Ruts: worn darker where the wheels and feet go, with grass between.
	float rut = exp(-pow((x - 0.3) / 0.07, 2.0)) + exp(-pow((x - 0.7) / 0.07, 2.0));
	float mid = exp(-pow((x - 0.5) / 0.08, 2.0)) * smoothstep(0.35, 0.6, env_noise(p * 0.3 + 4.0));
	col = mix(col, col * 0.72, rut * 0.6);
	col = mix(col, mix(col, mud, 0.6), rut * wetness);
	col = mix(col, grass, mid * 0.75);
	vec4 nt = texture(normal_array, vec3(p / 3.5, mix(T_DIRT, T_GRAVEL, step(0.5, g))));
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.3 * wetness);
	ALBEDO = col;
	ROUGHNESS = mix(nt.a, 0.35, wetness * rut);
	AO = nt.b;
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
