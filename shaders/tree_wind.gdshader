// Trees that sway in the shared wind. Bending grows with height (squared), each tree has its
// own phase, and slow gusts roll across the map in the wind direction.
// Used by scripts/map/tree_scatter.gd on a MultiMesh; instance colour tints the leaves.
shader_type spatial;
render_mode world_vertex_coords, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform bool use_instance_color = true;
uniform float roughness = 0.9;
uniform float sway = 0.07;          // top deflection as a fraction of tree height, full wind

varying vec3 v_color;
varying vec3 v_world_pos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float tree_h = max(length(MODEL_MATRIX[1].xyz), 0.001);
	float h = max(VERTEX.y - origin.y, 0.0) / tree_h;

	float phase = dot(origin.xz, vec2(0.071, 0.053));
	vec2 gust_uv = origin.xz * 0.0035 - wind_direction * wind_time * 0.25;
	float gust = env_noise(gust_uv);
	float strength = wind_strength * (0.4 + 0.9 * gust) + 0.08;
	float wave = 0.65 + 0.35 * sin(wind_time * 2.3 + phase) + 0.15 * sin(wind_time * 4.1 + phase * 1.7);

	vec2 bend = wind_direction * strength * wave * sway * tree_h * h * h;
	// Small sideways flutter so trees don't all lean in perfect lockstep.
	bend += vec2(-wind_direction.y, wind_direction.x) * sin(wind_time * 3.3 + phase * 2.1) * 0.25 * strength * sway * tree_h * h * h;
	VERTEX.xz += bend;
	VERTEX.y -= dot(bend, bend) / (tree_h * 2.0);

	v_world_pos = VERTEX;
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 col = albedo * (use_instance_color ? v_color : vec3(1.0));
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = roughness * (1.0 - 0.4 * wetness);
}
