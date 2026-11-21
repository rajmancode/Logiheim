// Trees and bushes (assets/models/vegetation, scattered by scripts/map/vegetation.gd).
// They sway in the shared wind: bending grows with height, each tree has its own phase, and
// gusts roll across the map. Vertex colour = AO baked in Blender; INSTANCE_CUSTOM.rgb tints
// the leaves per tree. Leaves let some light through (BACKLIGHT) like real foliage.
shader_type spatial;
render_mode world_vertex_coords, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform bool is_leaves = true;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bark_layer = 24.0;
uniform float bark_scale = 0.9;       // bark repeats per metre
uniform float roughness = 0.85;
uniform float sway = 0.035;          // top deflection as a fraction of tree height, full wind
uniform vec3 translucency : source_color = vec3(0.22, 0.28, 0.08);

varying vec3 v_tint;
varying float v_ao;
varying vec3 v_world_pos;
varying float v_h;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float tree_h = max(length(MODEL_MATRIX[1].xyz), 0.001);
	float h = clamp((VERTEX.y - origin.y) / tree_h, 0.0, 1.3);

	float phase = dot(origin.xz, vec2(0.071, 0.053));
	vec2 gust_uv = origin.xz * 0.0035 - wind_direction * wind_time * 0.25;
	float gust = env_noise(gust_uv);
	float strength = wind_strength * (0.4 + 0.9 * gust) + 0.08;
	float wave = 0.65 + 0.35 * sin(wind_time * 1.7 + phase) + 0.12 * sin(wind_time * 3.9 + phase * 1.7);
	vec2 bend = wind_direction * strength * wave * sway * tree_h * h * h;
	bend += vec2(-wind_direction.y, wind_direction.x) * sin(wind_time * 2.9 + phase * 2.1) * 0.25 * strength * sway * tree_h * h * h;
	// Leaves flutter a little on top of the trunk sway.
	if (is_leaves) {
		float flutter = sin(wind_time * 9.0 + dot(VERTEX, vec3(1.7, 2.3, 1.9))) * 0.012 * strength * tree_h;
		bend += vec2(flutter, -flutter) * h;
	}
	VERTEX.xz += bend;
	VERTEX.y -= dot(bend, bend) / (tree_h * 2.0);

	v_world_pos = VERTEX;
	v_ao = COLOR.r;
	v_tint = INSTANCE_CUSTOM.rgb;
	v_h = h;
}

void fragment() {
	vec3 col = albedo;
	if (is_leaves) {
		col *= v_tint;
		// Slight colour noise across the crown so it doesn't look like one flat colour.
		col *= 0.85 + 0.3 * env_noise(v_world_pos.xz * 0.9 + v_world_pos.y);
		BACKLIGHT = translucency * v_ao;
	}
	if (!is_leaves) {
		// Bark: triplanar in world space (the sway is small).
		vec3 q = v_world_pos * bark_scale;
		vec3 bn = abs(normalize(cross(dFdx(v_world_pos), dFdy(v_world_pos))));
		bn = pow(bn, vec3(4.0));
		bn /= bn.x + bn.y + bn.z;
		vec3 bark = texture(albedo_array, vec3(q.zy, bark_layer)).rgb * bn.x
			+ texture(albedo_array, vec3(q.xz, bark_layer)).rgb * bn.y
			+ texture(albedo_array, vec3(q.xy, bark_layer)).rgb * bn.z;
		col = mix(col, bark, 0.85);
	}
	col *= mix(0.35, 1.05, v_ao);
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = roughness * (1.0 - 0.4 * wetness);
	SPECULAR = is_leaves ? 0.3 : 0.2;
}
