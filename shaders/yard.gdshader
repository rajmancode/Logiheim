// The ground of a building's plot (scripts/game/settlement_ground.gd): worn by feet and carts,
// and made of what suits the place it stands in:
//   - open land: trampled earth with gravel, scattered straw and wood chips, grass surviving in
//     tufts towards the edge;
//   - forest: dark earth, needles, wood chips and roots;
//   - sand (shore, dunes): sand with pebbles and shell grit, a few boards laid down;
//   - rock: flagstones fitted together, moss in the joints;
//   - bog and wet ground: a floor of split planks laid over the mud;
//   - snow: packed snow with dirt trodden through it.
// UV.x is the distance from the middle of the plot (0) to its edge (1), where it frays into the
// ground round it. COLOR = (sand, rock, bog, forest), UV2 = (snow, moisture), at the plot.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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

varying vec3 v_world;
varying vec4 v_ground;
varying vec2 v_more;

float hash2(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

// Distance to the nearest of a jittered grid of points (for flagstones): x nearest, y second.
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g), hash2(i + g + 17.3)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d1, d2);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ground = COLOR;
	v_more = UV2;
}

void fragment() {
	vec2 p = v_world.xz;
	float r = UV.x;
	float rag = (env_noise(p * 0.45) - 0.5) * 0.35 + (env_noise(p * 1.8) - 0.5) * 0.12;
	float edge = smoothstep(1.0, 0.72, r + rag);
	float wob = (env_noise(p * 0.1 + vec2(5.0, 1.0)) - 0.5) * 0.3;

	// Open land: packed earth, gravel, straw and chips; grass hanging on near the edge.
	vec3 dirt = texture(albedo_array, vec3(p / 3.5, T_DIRT)).rgb;
	vec3 gravel = texture(albedo_array, vec3(p / 3.0, T_GRAVEL)).rgb;
	vec3 grass = texture(albedo_array, vec3(p / 4.0, T_GRASS)).rgb;
	vec3 mud = texture(albedo_array, vec3(p / 4.0, T_MUD)).rgb;
	vec3 col = mix(dirt, gravel, smoothstep(0.45, 0.75, env_noise(p * 0.18)) * 0.7);
	float straw = smoothstep(0.7, 0.85, env_noise(p * 2.2 + 3.0)) * smoothstep(0.5, 0.2, r);
	col = mix(col, vec3(0.62, 0.52, 0.3), straw * 0.5);
	float tufts = smoothstep(0.55, 0.75, env_noise(p * 0.7)) * smoothstep(0.45, 0.85, r);
	col = mix(col, grass, tufts * 0.8);
	float rough = 0.95;
	float ao = 1.0;

	float forest = smoothstep(0.35, 0.75, v_ground.a + wob);
	if (forest > 0.001) {
		vec3 needles = texture(albedo_array, vec3(p / 3.0, T_NEEDLES)).rgb;
		vec3 roots = texture(albedo_array, vec3(p / 3.5, T_ROOTS)).rgb;
		vec3 fcol = mix(dirt * 0.8, needles, 0.45);
		fcol = mix(fcol, roots, smoothstep(0.6, 0.85, env_noise(p * 0.5 + 2.0)) * 0.6);
		fcol = mix(fcol, vec3(0.7, 0.55, 0.36), smoothstep(0.75, 0.9, env_noise(p * 3.0)) * 0.5);
		col = mix(col, fcol, forest);
	}

	float sand = smoothstep(0.35, 0.75, v_ground.r + wob);
	if (sand > 0.001) {
		vec3 scol = texture(albedo_array, vec3(p / 4.0, T_SAND)).rgb;
		vec3 pebbles = texture(albedo_array, vec3(p / 3.0, T_PEBBLES)).rgb;
		scol = mix(scol, pebbles, smoothstep(0.55, 0.8, env_noise(p * 0.25 + 7.0)) * 0.5);
		col = mix(col, scol, sand);
	}

	// Rock: flagstones fitted together, moss and dark earth in the joints.
	float rock = smoothstep(0.3, 0.7, v_ground.g + wob);
	if (rock > 0.001) {
		vec2 c = cells(p / 1.1);
		float joint = smoothstep(0.02, 0.09, c.y - c.x);
		vec3 stone = texture(albedo_array, vec3(p / 2.5, T_ROCK)).rgb;
		stone *= 0.75 + 0.45 * hash2(floor(p / 1.1 + c.x));
		vec3 rcol = mix(mix(mud * 0.5, vec3(0.16, 0.22, 0.08), 0.5), stone, joint);
		col = mix(col, rcol, rock * smoothstep(0.95, 0.7, r + rag));
		rough = mix(rough, mix(0.95, 0.7, joint), rock);
		ao = mix(ao, mix(0.55, 1.0, joint), rock);
	}

	// Bog and wet ground: split planks laid side by side over the mud.
	float wet = smoothstep(0.45, 0.75, v_ground.b + wob * 0.5);
	if (wet > 0.001) {
		float lp = p.x / 0.32;
		float li = floor(lp);
		float lf = fract(lp);
		float seam = smoothstep(0.0, 0.1, lf) * smoothstep(1.0, 0.9, lf);
		vec3 wood = vec3(0.42, 0.31, 0.2) * (0.7 + 0.45 * hash2(vec2(li, 7.0)));
		wood *= 0.8 + 0.25 * env_noise(vec2(li * 3.0, p.y * 6.0));
		float plank_end = smoothstep(0.0, 0.04, fract(p.y / 2.4 + hash2(vec2(li, 2.0))));
		vec3 wcol = mix(mud * 0.6, wood, seam * plank_end);
		float on = smoothstep(0.9, 0.75, r + rag * 0.5);
		col = mix(col, mix(mud * 0.8, wcol, on), wet);
		ao = mix(ao, mix(0.55, 1.0, seam), wet * on);
	} else {
		col = mix(col, mud, smoothstep(0.5, 0.85, v_more.y) * 0.35 * smoothstep(0.7, 0.85, env_noise(p * 0.4)));
	}

	float snow = smoothstep(0.35, 0.75, v_more.x + wob);
	if (snow > 0.001) {
		vec3 scol = texture(albedo_array, vec3(p / 4.0, T_SNOW)).rgb;
		scol = mix(scol, dirt * 0.8, smoothstep(0.55, 0.8, env_noise(p * 0.6)) * 0.45 * smoothstep(0.7, 0.2, r));
		col = mix(col, scol, snow);
		rough = mix(rough, 0.55, snow);
	}

	// Worn darker in the middle, where most feet go.
	col *= 0.86 + 0.14 * smoothstep(0.0, 0.6, r);
	col = mix(col, mix(col, mud, 0.5), wetness * 0.6);
	col *= cloud_shadow(v_world) * (1.0 - 0.3 * wetness);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wetness);
	AO = ao;
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
