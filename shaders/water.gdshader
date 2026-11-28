// Sea surface: depth-based colour and clarity (reads the depth buffer), refraction of the sea
// floor, wind-driven waves, shoreline foam, sky reflections, plus grid lines and highlights.
// Used on a large subdivided plane at sea level (scripts/map/hex_map.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"
#include "res://shaders/include/hex_grid.gdshaderinc"
#include "res://shaders/include/sea_motion.gdshaderinc"

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
// River mouths (sea only): xy = where the river meets the sea, z = flow angle, w = width (m).
uniform vec4 mouths[32];
uniform int mouth_count = 0;
uniform vec3 plume_color : source_color = vec3(0.1, 0.42, 0.38);

// The river's outflow at a point: how much plume water is here (0..1) and how close to the
// plume's edge, where fresh water meets salt and foam lines collect (0..1).
vec3 river_plume(vec2 xz, float t) {
	float plume = 0.0;
	float shear = 0.0;
	float calm = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= mouth_count) {
			break;
		}
		vec4 m = mouths[i];
		vec2 d = vec2(cos(m.z), sin(m.z));
		vec2 rel = xz - m.xy;
		float along = dot(rel, d);
		float w = max(m.w, 2.0);
		// In the river's own mouth the current holds the surf back: no shore foam line where
		// the sea floods in over the river bed, and a soft water edge instead of a hard one.
		float mx = dot(rel, vec2(-d.y, d.x));
		float mlen = max(w * 4.0, 40.0);
		calm = max(calm, smoothstep(-mlen, -mlen * 0.6, along) * (1.0 - smoothstep(w * 1.0, w * 2.5, along))
			* (1.0 - smoothstep(w * 0.7 + 4.0, w * 1.4 + 10.0, abs(mx))));
		float len = 90.0 + w * 22.0;
		if (along < -w * 2.0 || along > len) {
			continue;
		}
		float across = dot(rel, vec2(-d.y, d.x));
		// The plume fans out and meanders slowly as it spreads.
		across += sin(along * 0.045 + t * 0.15 + float(i) * 1.7) * (w * 0.3 + along * 0.12);
		float spread = (w * 0.6 + max(along, 0.0) * 0.45) * (0.85 + 0.3 * env_noise(vec2(along * 0.03 + float(i) * 5.0, t * 0.03)));
		float reach = smoothstep(-w * 2.0, 0.0, along) * (1.0 - smoothstep(len * 0.35, len, along));
		plume = max(plume, exp(-pow(across / spread, 2.0)) * reach);
		float e = (abs(across) - spread * 0.9) / (spread * 0.12 + 1.0);
		shear = max(shear, exp(-e * e) * reach * (1.0 - smoothstep(len * 0.2, len * 0.75, along)));
	}
	return vec3(plume, shear, calm);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// River mouths are calm: the current holds the swell and surf back, so the water there
	// never heaves up over the banks.
	float still = 1.0 - (mouth_count > 0 ? river_plume(wp.xz, TIME).z : 0.0);
	float ground = use_terrain ? sea_ground(terrain_height, wp.xz, terrain_size, terrain_min, terrain_range) : 0.0;
	vec3 nrm;
	VERTEX += sea_offset(wp, use_terrain, ground, wave_height, swell, surf, surf_period, still, nrm);
	v_wave_n = nrm;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_edge = edge_alpha ? COLOR.a : 1.0;
}

void fragment() {
	vec3 rp = mouth_count > 0 ? river_plume(v_world_pos.xz, TIME) : vec3(0.0);
	// Small ripples from two scrolling normal maps, drifting with the wind.
	vec2 drift = wind_direction * wind_time * 0.012;
	vec2 uv1 = v_world_pos.xz * wave_scale - drift + TIME * vec2(0.0015, 0.0008);
	vec2 uv2 = v_world_pos.xz * wave_scale * 2.3 - drift * 1.7 - TIME * vec2(0.001, 0.002);
	vec3 n1 = texture(wave_normal, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal, uv2).xyz * 2.0 - 1.0;
	// A third, rotated layer and patchy strength (cat's-paws of wind) break up any tiling.
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec3 n3 = texture(wave_normal, rot * v_world_pos.xz * wave_scale * 0.6 + drift * 0.6 + TIME * vec2(-0.0007, 0.0011)).xyz * 2.0 - 1.0;
	float patch = 0.45 + 1.1 * env_noise(v_world_pos.xz * 0.006 - drift * 2.0 + vec2(TIME * 0.01, 0.0));
	vec2 ripple = (n1.xy + n2.xy + n3.xy * 0.8) * (0.2 + 0.45 * wind_strength) * patch;
	// River water is calmer than the sea it spreads over.
	ripple *= 1.0 - rp.x * 0.5;
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
	vec2 fq = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world_pos.xz;
	fq += vec2(env_noise(fq * 0.08), env_noise(fq * 0.08 + vec2(5.2, 1.3))) * 6.0;
	float foam_noise = env_noise(fq * 0.35 + drift * 8.0) * 0.6 + env_noise(mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * fq * 1.1 - drift * 5.0) * 0.4;
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
	foam *= 1.0 - rp.z * 0.9;
	// River plume: silty river water spreading over the sea, with foam lines along its edges.
	if (rp.x > 0.001 || rp.y > 0.001) {
		// Silty river water: greener-brown and murkier, in drifting patches.
		float silt = 0.75 + 0.5 * env_noise(v_world_pos.xz * 0.04 + vec2(TIME * 0.02, 0.0));
		// A gentle greener tint in the sea's own shallow colour, never a dark patch.
		col = mix(col, plume_color * silt, clamp(rp.x * 0.35, 0.0, 0.3));
		vec2 sq = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world_pos.xz;
		// Thin, broken lines of foam (not blobs) along the plume's edge.
		float streak = smoothstep(0.7, 0.88, env_noise(sq * vec2(0.5, 0.12) + vec2(TIME * 0.2, 0.0))) * rp.y;
		foam = max(foam, streak * 0.4);
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
	ALPHA = clamp(depth / mix(0.35, 1.6, rp.z), 0.0, 1.0) * v_edge;
	if (edge_alpha && ALPHA < 0.004) {
		discard;
	}
}
