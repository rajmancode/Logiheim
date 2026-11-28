// Villagers (assets/models/people, tools/blender/make_people.py): each vertex says what it is
// in its colour's red channel (region / 15) - skin, the outer garment, the underdress or
// shirt, trousers, leg wraps, shoes, belt, trim, hair, eye white, dark (pupils, brows), lips -
// and each person's colours come in per instance (Villager), so one material dresses them all.
// Cloth gets a fine weave and soft folds of light, skin a warm sheen, hair strands.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

instance uniform vec3 skin_col : source_color = vec3(0.86, 0.68, 0.56);
instance uniform vec3 hair_col : source_color = vec3(0.55, 0.38, 0.2);
instance uniform vec3 outer_col : source_color = vec3(0.4, 0.35, 0.28);
instance uniform vec3 under_col : source_color = vec3(0.85, 0.82, 0.72);
instance uniform vec3 legs_col : source_color = vec3(0.35, 0.3, 0.24);
instance uniform vec3 trim_col : source_color = vec3(0.6, 0.2, 0.15);

varying float v_region;
varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_region = COLOR.r * 15.0;
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int r = int(v_region + 0.5);
	vec3 col = outer_col;
	float rough = 0.92;
	float spec = 0.25;
	bool cloth = true;
	if (r == 0) { col = skin_col; cloth = false; rough = 0.6; spec = 0.4; }
	else if (r == 1) { col = outer_col; }
	else if (r == 2) { col = under_col; }
	else if (r == 3) { col = legs_col; }
	else if (r == 4) { col = vec3(0.45, 0.4, 0.33); }
	else if (r == 5) { col = vec3(0.22, 0.15, 0.09); cloth = false; rough = 0.7; }
	else if (r == 6) { col = vec3(0.28, 0.18, 0.1); cloth = false; rough = 0.6; }
	else if (r == 7) { col = trim_col; }
	else if (r == 8) { col = hair_col; cloth = false; rough = 0.7; }
	else if (r == 9) { col = vec3(0.92, 0.9, 0.86); cloth = false; rough = 0.3; spec = 0.6; }
	else if (r == 10) { col = vec3(0.07, 0.05, 0.04); cloth = false; rough = 0.3; }
	else if (r == 11) { col = skin_col * vec3(0.85, 0.55, 0.5); cloth = false; rough = 0.5; }
	if (cloth) {
		// A fine twill weave and soft unevenness in the wool.
		float weave = 0.93 + 0.07 * sin((v_local.x + v_local.y) * 420.0) * sin((v_local.z - v_local.y) * 410.0);
		col *= weave * (0.9 + 0.16 * env_noise(v_local.xy * 18.0 + v_local.z * 7.0));
		// Leg wraps: spiral bands.
		if (r == 4) {
			col *= 0.85 + 0.2 * step(0.5, fract(v_local.y * 28.0 + atan(v_local.x, v_local.z) * 0.6));
		}
	} else if (r == 8) {
		col *= 0.8 + 0.3 * env_noise(vec2(atan(v_local.x, v_local.z) * 30.0, v_local.y * 6.0));
	}
	col *= cloud_shadow(v_world);
	ALBEDO = col * (1.0 - 0.2 * wetness * float(cloth));
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (r == 0 || r == 11) {
		// A touch of light through the skin at the edges.
		BACKLIGHT = col * 0.15;
	}
}
