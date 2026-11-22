// Trails (scripts/map/road_network.gd): the surface follows the ground the trail runs over.
//   - open land: packed earth and gravel, two worn wheel ruts with a strip of grass between;
//   - sand (beaches, dunes): a pale sand track, ruts soft and shallow, no grass;
//   - rock: a paved way of set stones with dark joints;
//   - bog and wet ground: a corduroy road of logs laid across, mud showing between them;
//   - forest: dark earth strewn with needles and roots;
//   - snow: packed snow with grey ruts.
// Ragged soft edges fade into the ground around. UV.x across the trail (0..1), UV.y metres
// along it; COLOR = (sand, rock, bog, forest), UV2 = (snow, moisture), smoothed along the trail.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float trail_width = 3.5;
const float T_SAND = 0.0;
const float T_PEBBLES = 3.0;
const float T_GRASS = 4.0;
const float T_NEEDLES = 10.0;
const float T_ROCK = 11.0;
const float T_SNOW = 15.0;
const float T_DIRT = 18.0;
const float T_MUD = 19.0;
const float T_GRAVEL = 21.0;
const float T_ROOTS = 32.0;

varying vec3 v_world_pos;
varying vec4 v_ground;
varying float v_snow;
varying float v_damp;

float hash2(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ground = COLOR;
	v_snow = UV2.x;
	v_damp = UV2.y;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float x = UV.x;
	float along = UV.y;
	float rag = (env_noise(p * 0.7) - 0.5) * 0.1 + (env_noise(p * 2.5) - 0.5) * 0.05;
	float edge = smoothstep(0.0, 0.16, x + rag) * smoothstep(1.0, 0.84, x - rag);
	float rut = exp(-pow((x - 0.3) / 0.07, 2.0)) + exp(-pow((x - 0.7) / 0.07, 2.0));
	float mid = exp(-pow((x - 0.5) / 0.08, 2.0)) * smoothstep(0.35, 0.6, env_noise(p * 0.3 + 4.0));
	// Patchy transitions: one surface gives way to the next in tongues, not in a straight line.
	float wob = (env_noise(p * 0.12 + vec2(5.0, 1.0)) - 0.5) * 0.35;

	// Open land: packed earth and gravel with ruts and a grass strip.
	vec3 dirt = texture(albedo_array, vec3(p / 3.5, T_DIRT)).rgb;
	vec3 gravel = texture(albedo_array, vec3(p / 3.0, T_GRAVEL)).rgb;
	vec3 grass = texture(albedo_array, vec3(p / 4.0, T_GRASS)).rgb;
	vec3 mud = texture(albedo_array, vec3(p / 4.0, T_MUD)).rgb;
	float g = smoothstep(0.4, 0.7, env_noise(p * 0.15));
	vec3 col = mix(dirt, gravel, g);
	col = mix(col, col * 0.72, rut * 0.6);
	col = mix(col, grass, mid * 0.75);
	float rough = texture(normal_array, vec3(p / 3.5, mix(T_DIRT, T_GRAVEL, step(0.5, g)))).a;
	float ao = 1.0;

	// Forest: darker earth under the trees, needles and roots across it.
	float forest = smoothstep(0.35, 0.75, v_ground.a + wob);
	if (forest > 0.001) {
		vec3 needles = texture(albedo_array, vec3(p / 3.0, T_NEEDLES)).rgb;
		vec3 roots = texture(albedo_array, vec3(p / 3.5, T_ROOTS)).rgb;
		vec3 fcol = mix(dirt * 0.8, needles, 0.35 + 0.35 * (1.0 - rut));
		fcol = mix(fcol, roots, smoothstep(0.55, 0.8, env_noise(p * 0.6 + 2.0)) * 0.6);
		col = mix(col, fcol, forest);
	}

	// Sand: a pale track, the ruts just soft hollows, no grass.
	float sand = smoothstep(0.35, 0.75, v_ground.r + wob);
	if (sand > 0.001) {
		vec3 scol = texture(albedo_array, vec3(p / 4.0, T_SAND)).rgb;
		vec3 pebbles = texture(albedo_array, vec3(p / 3.0, T_PEBBLES)).rgb;
		scol = mix(scol, pebbles, smoothstep(0.6, 0.85, env_noise(p * 0.2 + 7.0)) * 0.4);
		scol = mix(scol, scol * 0.86, rut * 0.5);
		col = mix(col, scol, sand);
		rough = mix(rough, 0.9, sand);
	}

	// Rock: a paved way of set stones, rows staggered, joints dark.
	float rock = smoothstep(0.35, 0.75, v_ground.g + wob);
	if (rock > 0.001) {
		vec2 sp = vec2(x * trail_width / 0.62, along / 0.55);
		float row = floor(sp.y);
		sp.x += hash2(vec2(row, 3.0)) * 0.7 + mod(row, 2.0) * 0.5;
		vec2 cell = floor(sp);
		vec2 f = fract(sp);
		float joint = smoothstep(0.0, 0.09, f.x) * smoothstep(1.0, 0.91, f.x) * smoothstep(0.0, 0.11, f.y) * smoothstep(1.0, 0.89, f.y);
		vec3 stone = texture(albedo_array, vec3(p / 2.5, T_ROCK)).rgb;
		stone *= 0.75 + 0.45 * hash2(cell);
		// Worn smooth and darker where the wheels go.
		stone = mix(stone, stone * 0.85, rut * 0.4);
		vec3 rcol = mix(mud * 0.5, stone, joint);
		col = mix(col, rcol, rock);
		rough = mix(rough, mix(0.95, 0.6, joint), rock);
		ao = mix(ao, mix(0.55, 1.0, joint), rock);
	}

	// Bog and wet ground: logs laid side by side across the trail, mud between them.
	float wet = smoothstep(0.5, 0.8, v_ground.b + wob * 0.5);
	if (wet > 0.001) {
		float lp = along / 0.34;
		float li = floor(lp);
		float lf = fract(lp);
		float log_prof = sqrt(max(1.0 - pow((lf - 0.5) / 0.46, 2.0), 0.0));
		float jag = hash2(vec2(li, 1.0));
		// Log ends stick out unevenly; each log its own shade and grain.
		float len = smoothstep(0.02 + jag * 0.06, 0.08 + jag * 0.06, x) * smoothstep(0.98 - jag * 0.05, 0.92 - jag * 0.05, x);
		vec3 wood = vec3(0.37, 0.26, 0.16) * (0.75 + 0.4 * hash2(vec2(li, 7.0)));
		wood *= 0.8 + 0.25 * env_noise(vec2(x * trail_width * 3.0, li * 5.0));
		wood *= 0.55 + 0.45 * log_prof;
		float on_log = step(0.15, log_prof) * len;
		vec3 wcol = mix(mud * 0.7, wood, on_log);
		col = mix(col, wcol, wet);
		rough = mix(rough, mix(0.3, 0.8, on_log), wet);
		ao = mix(ao, mix(0.5, 1.0, log_prof), wet);
	} else {
		// Merely damp ground: mud in the ruts.
		col = mix(col, mix(col, mud, 0.6), rut * smoothstep(0.4, 0.8, max(v_damp, v_ground.b * 2.0)) * 0.8);
	}

	// Snow: packed white with grey ruts.
	float snow = smoothstep(0.35, 0.75, v_snow + wob);
	if (snow > 0.001) {
		vec3 scol = texture(albedo_array, vec3(p / 4.0, T_SNOW)).rgb;
		scol = mix(scol, scol * vec3(0.72, 0.74, 0.78), rut * 0.7);
		col = mix(col, scol, snow);
		rough = mix(rough, 0.55, snow);
	}

	col = mix(col, mix(col, mud, 0.6), rut * wetness * (1.0 - snow));
	col *= cloud_shadow(v_world_pos) * (1.0 - 0.3 * wetness);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wetness * rut);
	AO = ao;
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
