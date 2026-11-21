// Sea surface: depth-based colour and clarity (reads the depth buffer), refraction of the sea
// floor, wind-driven waves, shoreline foam, sky reflections, plus grid lines and highlights.
// Used on a large subdivided plane at sea level (scripts/map/hex_map.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"
#include "res://shaders/include/hex_grid.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.48, 0.46);
uniform vec3 deep_color : source_color = vec3(0.012, 0.075, 0.13);
uniform float clarity = 4.0;          // metres until the floor is half hidden
uniform float colour_depth = 18.0;    // metres until the water is fully deep-coloured
uniform float foam_width = 2.2;       // metres of foam at the shoreline
uniform float wave_height = 0.35;
uniform float wave_scale = 0.012;
uniform float grid_fade_start = 2500.0;

varying vec3 v_world_pos;
varying float v_edge;
varying vec3 v_wave_n;
// Sea only: the terrain's height map, so waves know how deep the water is under them.
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform vec2 terrain_size = vec2(2048.0);
uniform float terrain_min = -40.0;
uniform float terrain_range = 300.0;
uniform bool use_terrain = false;
uniform float swell = 0.55;        // metres of open-sea swell (more in wind)
uniform bool edge_alpha = false;   // lakes: COLOR.a fades the water out at open mesh edges
uniform float surf = 1.0;          // breakers rolling onto the shore (sea only)
uniform float surf_period = 8.0;   // seconds between sets of breakers

float waves(vec2 p, float t) {
	vec2 d1 = wind_direction;
	vec2 d2 = vec2(-wind_direction.y, wind_direction.x) * 0.7 + wind_direction * 0.7;
	return sin(dot(p, d1) * 0.045 + t * 0.45) * 0.6 + sin(dot(p, d2) * 0.07 + t * 0.6) * 0.4;
}

// One Gerstner wave: moves the surface up and sideways (towards the crest), so crests sharpen
// and troughs flatten like real swell. Adds to disp and to the normal's slope terms.
void gerstner(vec2 xz, vec2 dir, float len, float amp, float steep, float t, inout vec3 disp, inout vec3 nrm) {
	float k = 6.2832 / len;
	float c = sqrt(9.8 / k) * 0.5;
	float f = k * (dot(dir, xz) - c * t);
	float q = steep / (k * amp * 3.0 + 1e-4);
	disp.xz += q * amp * dir * cos(f);
	disp.y += amp * sin(f);
	nrm.xz -= dir * k * amp * cos(f);
	nrm.y -= q * k * amp * sin(f);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = wave_height * (0.4 + 1.2 * wind_strength);
	VERTEX.y += waves(wp.xz, wind_time) * amp;
	v_wave_n = vec3(0.0, 1.0, 0.0);
	if (use_terrain) {
		// Depth from the terrain height map: waves calm right at the shore and grow offshore.
		vec2 tuv = wp.xz / terrain_size;
		float ground = (tuv.x < 0.0 || tuv.y < 0.0 || tuv.x > 1.0 || tuv.y > 1.0) ? -100.0
			: texture(terrain_height, tuv).r * terrain_range + terrain_min;
		float depth = wp.y - ground;
		float a = swell * (0.5 + 1.3 * wind_strength) * smoothstep(0.3, 6.0, depth);
		vec3 disp = vec3(0.0);
		vec3 nrm = vec3(0.0, 1.0, 0.0);
		vec2 d0 = wind_direction;
		gerstner(wp.xz, d0, 62.0, a, 0.55, TIME, disp, nrm);
		gerstner(wp.xz, normalize(d0 + vec2(-d0.y, d0.x) * 0.45), 37.0, a * 0.55, 0.5, TIME, disp, nrm);
		gerstner(wp.xz, normalize(d0 - vec2(-d0.y, d0.x) * 0.6), 21.0, a * 0.3, 0.45, TIME, disp, nrm);
		// Breakers: the swell lifts as it reaches the shallows along the lines the surf foam
		// draws, then collapses onto the beach.
		if (surf > 0.0 && depth > -0.5 && depth < 7.0) {
			float ph = TIME / surf_period + env_noise(wp.xz * 0.004) * 0.8;
			for (int k = 0; k < 2; k++) {
				float c = fract(ph + float(k) * 0.5);
				float front = mix(5.0, -0.2, c * c * (3.0 - 2.0 * c));
				float bump = exp(-pow((depth - front) / 0.8, 2.0)) * (1.0 - smoothstep(0.6, 0.95, c));
				disp.y += bump * 0.55 * surf;
			}
		}
		VERTEX += disp;
		v_wave_n = normalize(nrm);
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_edge = edge_alpha ? COLOR.a : 1.0;
}

void fragment() {
	// Small ripples from two scrolling normal maps, drifting with the wind.
	vec2 drift = wind_direction * wind_time * 0.012;
	vec2 uv1 = v_world_pos.xz * wave_scale - drift + TIME * vec2(0.0015, 0.0008);
	vec2 uv2 = v_world_pos.xz * wave_scale * 2.3 - drift * 1.7 - TIME * vec2(0.001, 0.002);
	vec3 n1 = texture(wave_normal, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal, uv2).xyz * 2.0 - 1.0;
	vec2 ripple = (n1.xy + n2.xy) * (0.25 + 0.5 * wind_strength);
	vec3 wn = normalize(vec3(ripple.x, 1.0, ripple.y) + vec3(v_wave_n.x, 0.0, v_wave_n.z) * 1.6);

	// Water depth below this pixel, from the depth buffer.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float depth = max(v_world_pos.y - floor_world.y, 0.0);
	float view_depth = max(length(floor_world - CAMERA_POSITION_WORLD) - length(v_world_pos - CAMERA_POSITION_WORLD), 0.0);

	// Refracted sea floor, absorbed with depth.
	vec2 refr_uv = SCREEN_UV + ripple * 0.012 * clamp(depth * 0.25, 0.0, 1.0);
	vec3 floor_col = textureLod(screen_texture, refr_uv, 0.0).rgb;
	float see = exp(-view_depth / clarity);
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, colour_depth, depth));
	vec3 col = mix(water, floor_col * mix(vec3(1.0), shallow_color * 2.2, 0.35), see);

	// Shoreline foam that laps in and out, plus whitecaps in strong wind.
	float lap = 0.5 + 0.5 * sin(TIME * 0.7 - depth * 2.5);
	float foam_noise = env_noise(v_world_pos.xz * 0.35 + drift * 8.0) * 0.6 + env_noise(v_world_pos.xz * 1.1 - drift * 5.0) * 0.4;
	float shore = 1.0 - smoothstep(0.0, foam_width * (0.6 + 0.6 * lap), depth);
	float caps = smoothstep(0.78, 0.95, foam_noise) * smoothstep(0.55, 1.0, wind_strength);
	float foam = clamp(shore * smoothstep(0.3, 0.7, foam_noise + shore * 0.3) + caps * 0.6, 0.0, 1.0);
	// Breakers: lines of swell come in from ~5 m depth, steepen and whiten as the water shoals,
	// break at the shore and run up as a sheet of foam that drains away. Two staggered sets,
	// the timing drifting along the coast so the whole shore doesn't break at once.
	if (surf > 0.0 && depth < 7.0) {
		float ph = TIME / surf_period + env_noise(v_world_pos.xz * 0.004) * 0.8;
		float breakers = 0.0;
		float swash = 0.0;
		for (int k = 0; k < 2; k++) {
			float c = fract(ph + float(k) * 0.5);
			float front = mix(5.0, -0.2, c * c * (3.0 - 2.0 * c));
			float w = 0.18 + 0.55 * c;
			float line = exp(-pow((depth - front) / w, 2.0));
			float whiten = smoothstep(0.3, 0.75, c);
			float crest = smoothstep(0.25, 0.65, env_noise(v_world_pos.xz * 0.12 + vec2(float(k) * 7.0, TIME * 0.04)));
			breakers += line * mix(0.2, 1.0, whiten) * mix(0.5, 1.0, crest);
			// After breaking: foam sheet over the shallowest water, fading as it drains.
			float drain = smoothstep(0.75, 0.85, c) * (1.0 - smoothstep(0.85, 1.0, c));
			swash += drain * (1.0 - smoothstep(0.0, 0.8, depth)) * smoothstep(0.3, 0.7, foam_noise);
		}
		float surf_foam = clamp(breakers + swash, 0.0, 1.0) * surf * smoothstep(7.0, 2.0, depth);
		foam = max(foam, surf_foam);
		// The face of a breaker catches the light a little.
		col *= 1.0 + 0.15 * breakers * surf;
	}
	col = mix(col, vec3(0.92, 0.95, 0.96), foam);

	col *= cloud_shadow(v_world_pos);
	float fade = 1.0 - smoothstep(grid_fade_start, grid_fade_start * 2.0, length(v_world_pos - CAMERA_POSITION_WORLD));
	vec3 emission = apply_hex_grid(col, v_world_pos.xz, fade * 0.6);

	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.55;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	EMISSION = emission;
	// Soft edge where the water meets the shore.
	ALPHA = clamp(depth / 0.35, 0.0, 1.0) * v_edge;
}
