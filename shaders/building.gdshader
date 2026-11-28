// Settlement buildings and people (scripts/game/building_models.gd). Each face says what it is
// made of (UV.x, from its colour): timber, thatch, turf, stone, iron, the owner's cloth or
// plain. Each is drawn its own way from the model's local position, so the flat colours read
// as real stuff:
//   timber - upright boards with dark seams, each board its own shade, grain running along it;
//            beams and posts get grain along their length;
//   thatch - overlapping courses of straw, each lighter at its top, with fibres running
//            down the slope and a dark shadow line under each course;
//   turf   - lumpy grass with darker hollows, the odd yellow tuft and a little moss;
//   stone  - laid courses of irregular blocks with mortar between;
//   iron   - dark, slightly metallic; cloth - woven, in the owner's colour;
//   shingles - overlapping wooden shingles with rounded feet, weathered, a little moss.
//
// Construction: everything above `build` x height is cut away, with a ragged line of fresh,
// pale timber glowing faintly at the cut - the building rises from the ground as it is raised.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 team_color : source_color = vec3(0.8, 0.2, 0.2);
uniform float build = 1.0;
uniform float height = 8.0;
uniform float flash = 0.0;     // brief highlight (selected, just finished)
uniform bool people = false;   // people: cloth, skin and hair, not boards and thatch

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_lnormal;
varying float v_mat;

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_local = VERTEX;
	v_lnormal = NORMAL;
	v_mat = UV.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Rising from the ground while being built (the plinth below ground is always there).
	float cut = build * (height + 0.4);
	float jag = (env_noise(v_world.xz * 1.7) - 0.5) * 0.5;
	if (build < 1.0 && v_local.y > cut + jag) {
		discard;
	}
	// (The kit's colours are written in sRGB, like the rest of the palette.)
	vec3 col = COLOR.a < 0.25 ? team_color : pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	vec3 n = normalize(v_lnormal);
	// The coordinate across a wall (along it horizontally) and up it.
	float across = abs(n.x) > abs(n.z) ? v_local.z : v_local.x;
	float up = v_local.y;
	int mat = int(v_mat + 0.5);
	if (people && mat != 4 && mat != 5) {
		mat = 8;
	}
	float rough = 0.85;
	float metal = 0.0;
	float ao = 1.0;
	if (mat == 0) {
		if (abs(n.y) < 0.6) {
			// Boards: 26 cm wide, dark seams, each its own shade, grain along it.
			float bw = 0.26;
			float f = fract(across / bw);
			float board = floor(across / bw);
			float seam = smoothstep(0.0, 0.07, f) * smoothstep(1.0, 0.93, f);
			float grain = env_noise(vec2(across * 24.0, up * 1.3 + board * 7.0));
			col *= mix(0.45, 1.0, seam) * (0.82 + 0.3 * hash1(vec2(board, 3.0))) * (0.86 + 0.22 * grain);
			ao = mix(0.6, 1.0, seam);
		} else {
			float grain = env_noise(vec2(v_local.x * 18.0, v_local.z * 2.0));
			col *= 0.85 + 0.25 * grain;
		}
	} else if (mat == 1) {
		// Thatch: courses 30 cm deep, lighter at the top of each, fibres down the slope.
		float course = up / 0.3 + env_noise(vec2(across * 0.8, 0.0)) * 0.4;
		float f = fract(course);
		float fibre = env_noise(vec2(across * 38.0 + floor(course) * 11.0, up * 4.0));
		col *= (0.62 + 0.45 * f) * (0.8 + 0.35 * fibre);
		col *= 1.0 - 0.35 * smoothstep(0.12, 0.0, f);
		ao = 0.75 + 0.25 * f;
		rough = 0.95;
	} else if (mat == 2) {
		// Turf: lumpy grass, darker hollows, yellow tufts, a little moss.
		float lump = env_noise(v_local.xz * 1.6 + vec2(up * 0.7, 0.0));
		float fine = env_noise(v_local.xz * 9.0 + vec2(0.0, up * 3.0));
		col *= 0.7 + 0.5 * lump * (0.7 + 0.3 * fine);
		col = mix(col, col * vec3(1.35, 1.2, 0.55), smoothstep(0.72, 0.9, fine) * 0.6);
		col = mix(col, vec3(0.06, 0.09, 0.03), smoothstep(0.35, 0.15, lump) * 0.4);
		rough = 1.0;
	} else if (mat == 3) {
		// Stone: courses 40 cm high of blocks 50-90 cm long, mortar between.
		float row = floor(up / 0.4);
		float u = across + hash1(vec2(row, 1.0)) * 0.7;
		float bl = 0.5 + 0.4 * hash1(vec2(row, 5.0));
		float block = floor(u / bl);
		vec2 f = vec2(fract(u / bl), fract(up / 0.4));
		float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(1.0, 0.94, f.x) * smoothstep(0.0, 0.08, f.y) * smoothstep(1.0, 0.92, f.y);
		if (abs(n.y) > 0.6) {
			mortar = 1.0;
		}
		col *= (0.8 + 0.35 * hash1(vec2(block, row))) * mix(0.55, 1.0, mortar) * (0.88 + 0.2 * env_noise(v_local.xz * 6.0 + up));
		ao = mix(0.55, 1.0, mortar);
	} else if (mat == 4) {
		metal = 0.6;
		rough = 0.45;
	} else if (mat == 7) {
		// Shingles: rows 28 cm deep, each shingle 24 cm wide with a rounded foot, rows staggered;
		// each its own shade of weathered grey-brown, dark in the gaps and under the row above,
		// moss in the damp patches.
		float row = floor(up / 0.28);
		float u = across / 0.24 + 0.5 * mod(row, 2.0);
		float cell = floor(u);
		vec2 f = vec2(fract(u), fract(up / 0.28));
		float side = abs(f.x - 0.5) * 2.0;
		float foot = smoothstep(0.0, 0.22, f.y - 0.22 * side * side);
		float gap = smoothstep(0.0, 0.07, f.x) * smoothstep(1.0, 0.93, f.x);
		float tone = 0.72 + 0.4 * hash1(vec2(cell, row));
		col = vec3(dot(col, vec3(0.33))) * vec3(1.08, 0.9, 0.7);
		col *= tone * mix(0.45, 1.0, foot * gap) * (1.0 - 0.3 * smoothstep(0.75, 1.0, f.y));
		col *= 0.9 + 0.18 * env_noise(vec2(across * 30.0, up * 3.0 + cell));
		float moss = smoothstep(0.62, 0.85, env_noise(v_local.xz * 0.35 + vec2(up * 0.2, 3.0)));
		col = mix(col, vec3(0.16, 0.2, 0.07), moss * 0.55 * foot);
		ao = mix(0.55, 1.0, foot * gap);
		rough = 0.9;
	} else if (mat == 8) {
		// People: soft wool and linen, a faint weave and fold shading.
		col *= 0.92 + 0.1 * env_noise(v_local.xz * 40.0 + vec2(v_local.y * 40.0));
		rough = 0.95;
	} else if (mat == 5) {
		// Woven cloth.
		float weave = 0.9 + 0.1 * sin(v_local.x * 90.0) * sin(v_local.y * 90.0);
		col *= weave;
		rough = 0.9;
	}
	// Fresh timber at the line where the building is going up.
	float fresh = (build < 1.0) ? smoothstep(0.6, 0.0, abs(v_local.y - cut - jag)) : 0.0;
	col = mix(col, vec3(0.86, 0.7, 0.45), fresh * 0.8);
	col *= cloud_shadow(v_world);
	ALBEDO = col * (1.0 - 0.25 * wetness);
	ROUGHNESS = mix(rough, 0.5, wetness);
	METALLIC = metal;
	AO = ao;
	EMISSION = vec3(1.0, 0.75, 0.4) * (fresh * 0.25 + flash * 0.35);
}
