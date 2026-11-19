// Grass clumps (scripts/map/grass_field.gd): blades bend with the shared wind and gusts,
// colour varies across the field and from root to tip, and the field fades out with distance.
// UV.y is 0 at the root and 1 at the tip.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.13, 0.19, 0.06);
uniform vec3 tip_color : source_color = vec3(0.47, 0.55, 0.24);
uniform vec3 dry_color : source_color = vec3(0.58, 0.55, 0.3);
uniform float sway = 0.35;

varying vec3 v_world_pos;
varying float v_h;
varying float v_var;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = UV.y;
	float gust = env_noise(origin.xz * 0.05 - wind_direction * wind_time * 0.6);
	float strength = 0.15 + wind_strength * (0.5 + 0.9 * gust);
	float wave = sin(wind_time * 3.0 + dot(origin.xz, vec2(0.37, 0.29))) * 0.3 + 0.7;
	vec3 wv = vec3(wind_direction.x, 0.0, wind_direction.y) * strength * wave * sway * h * h;
	// Bend in world space, converted back into the instance's local space.
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * wv);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_h = h;
	v_var = env_noise(origin.xz * 0.03);
	// Soft, mostly upward normals so the field shades like a canopy, not like cards.
	NORMAL = normalize(mix(NORMAL, (inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0)), 0.7));
}

void fragment() {
	vec3 tip = mix(tip_color, dry_color, smoothstep(0.55, 0.85, v_var) * 0.6);
	vec3 col = mix(root_color, tip, smoothstep(0.0, 1.0, v_h));
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * v_h;
	AO = mix(0.45, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.5;
}
