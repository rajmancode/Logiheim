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
// River mouths (sea only): xy = where the river meets the sea, z = flow angle, w = width (m).
uniform vec4 mouths[32];
uniform int mouth_count = 0;
uniform vec3 plume_color : source_color = vec3(0.1, 0.21, 0.16);

// The river's outflow at a point: how much plume water is here (0..1) and how close to the
// plume's edge, where fresh water meets salt and foam lines collect (0..1).
vec2 river_plume(vec2 xz, float t) {
	float plume = 0.0;
	float shear = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= mouth_count) {
			break;
		}
		vec4 m = mouths[i];
		vec2 d = vec2(cos(m.z), sin(m.z));
		vec2 rel = xz - m.xy;
		float along = dot(rel, d);
		float w = max(m.w, 2.0);
		float len = 50.0 + w * 14.0;
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
	return vec2(plume, shear);
}

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
		// Sampled over a ~12 m footprint so breaker lines follow the shore smoothly instead of
		// picking up every step of the terrain grid (no jagged surf).
		float ground = -100.0;
		vec2 tuv = wp.xz / terrain_size;
		if (tuv.x >= 0.0 && tuv.y >= 0.0 && tuv.x <= 1.0 && tuv.y <= 1.0) {
			vec2 o = vec2(6.0) / terrain_size;
			float g = texture(terrain_height, tuv).r * 2.0
				+ texture(terrain_height, tuv + vec2(o.x, 0.0)).r + texture(terrain_height, tuv - vec2(o.x, 0.0)).r
				+ texture(terrain_height, tuv + vec2(0.0, o.y)).r + texture(terrain_height, tuv - vec2(0.0, o.y)).r;
			ground = g / 6.0 * terrain_range + terrain_min;
		}
		float depth = wp.y - ground;
		float a = swell * (0.5 + 1.3 * wind_strength) * smoothstep(0.3, 6.0, depth);
		vec3 disp = vec3(0.0);
		vec3 nrm = vec3(0.0, 1.0, 0.0);
		vec2 d0 = wind_direction;
		vec2 s0 = vec2(-d0.y, d0.x);
		// Six swells from spread directions and lengths, each rising and fading in drifting
		// patches (wave groups) so the sea never shows a regular, repeating pattern.
		vec2 gp = wp.xz - d0 * TIME * 3.0;
		float g1 = 0.3 + 1.4 * env_noise(gp * 0.0035 + vec2(3.1, 7.2));
		float g2 = 0.3 + 1.4 * env_noise(gp * 0.005 + vec2(9.4, 1.3));
		float g3 = 0.3 + 1.4 * env_noise(gp * 0.008 + vec2(5.7, 4.6));
		gerstner(wp.xz, d0, 67.0, a * 0.75 * g1, 0.5, TIME, disp, nrm);
		gerstner(wp.xz, normalize(d0 + s0 * 0.42), 41.0, a * 0.5 * g2, 0.5, TIME, disp, nrm);
		gerstner(wp.xz, normalize(d0 - s0 * 0.58), 29.0, a * 0.35 * g3, 0.45, TIME, disp, nrm);
		gerstner(wp.xz, normalize(d0 + s0 * 1.1), 19.0, a * 0.2 * g1, 0.4, TIME * 1.07, disp, nrm);
		gerstner(wp.xz, normalize(d0 - s0 * 0.21), 13.0, a * 0.14 * g2, 0.4, TIME * 0.93, disp, nrm);
		gerstner(wp.xz, normalize(-d0 * 0.3 + s0), 9.0, a * 0.08 * g3, 0.35, TIME * 1.11, disp, nrm);
		// Breakers: the swell lifts as it reaches the shallows along the lines the surf foam
		// draws, then collapses onto the beach.
		if (surf > 0.0 && depth > -0.5 && depth < 7.0) {
			float ph = TIME / surf_period + env_noise(wp.xz * 0.004) * 0.8;
			for (int k = 0; k < 2; k++) {
				float c = fract(ph + float(k) * 0.5);
				float front = mix(5.0, -0.2, c * c * (3.0 - 2.0 * c));
				float bump = exp(-pow((depth - front) / 0.8, 2.0)) * (1.0 - smoothstep(0.6, 0.95, c));
				// Breakers come in uneven along the shore: bigger here, barely there.
				bump *= 0.3 + 1.3 * env_noise(wp.xz * 0.018 + vec2(float(k) * 3.7, TIME * 0.02));
				// No lift in the last metre of water: the 5 m sea mesh would ride up over the
				// sand in flat, straight-edged facets. The foam draws the swash there instead.
				disp.y += bump * 0.55 * surf * smoothstep(0.4, 1.8, depth);
			}
		}
		VERTEX += disp;
		v_wave_n = normalize(nrm);
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_edge = edge_alpha ? COLOR.a : 1.0;
}

void fragment() {
	vec2 rp = mouth_count > 0 ? river_plume(v_world_pos.xz, TIME) : vec2(0.0);
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
	// River plume: silty river water spreading over the sea, with foam lines along its edges.
	if (rp.x > 0.001 || rp.y > 0.001) {
		col = mix(col, plume_color * (0.85 + 0.3 * env_noise(v_world_pos.xz * 0.06)), rp.x * 0.65);
		vec2 sq = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * v_world_pos.xz;
		float streak = smoothstep(0.55, 0.8, env_noise(sq * 0.22 + vec2(TIME * 0.2, 0.0))) * rp.y;
		foam = max(foam, streak * 0.75);
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
