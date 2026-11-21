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
uniform bool edge_alpha = false;   // lakes: COLOR.a fades the water out at open mesh edges

float waves(vec2 p, float t) {
	vec2 d1 = wind_direction;
	vec2 d2 = vec2(-wind_direction.y, wind_direction.x) * 0.7 + wind_direction * 0.7;
	return sin(dot(p, d1) * 0.045 + t * 1.3) * 0.6 + sin(dot(p, d2) * 0.07 + t * 1.9) * 0.4;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = wave_height * (0.4 + 1.2 * wind_strength);
	VERTEX.y += waves(wp.xz, wind_time) * amp;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_edge = edge_alpha ? COLOR.a : 1.0;
}

void fragment() {
	// Small ripples from two scrolling normal maps, drifting with the wind.
	vec2 drift = wind_direction * wind_time * 0.04;
	vec2 uv1 = v_world_pos.xz * wave_scale - drift + TIME * vec2(0.004, 0.002);
	vec2 uv2 = v_world_pos.xz * wave_scale * 2.3 - drift * 1.7 - TIME * vec2(0.003, 0.006);
	vec3 n1 = texture(wave_normal, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal, uv2).xyz * 2.0 - 1.0;
	vec2 ripple = (n1.xy + n2.xy) * (0.25 + 0.5 * wind_strength);
	vec3 wn = normalize(vec3(ripple.x, 1.0, ripple.y));

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
	float lap = 0.5 + 0.5 * sin(TIME * 1.4 - depth * 2.5);
	float foam_noise = env_noise(v_world_pos.xz * 0.35 + drift * 8.0) * 0.6 + env_noise(v_world_pos.xz * 1.1 - drift * 5.0) * 0.4;
	float shore = 1.0 - smoothstep(0.0, foam_width * (0.6 + 0.6 * lap), depth);
	float caps = smoothstep(0.78, 0.95, foam_noise) * smoothstep(0.55, 1.0, wind_strength);
	float foam = clamp(shore * smoothstep(0.3, 0.7, foam_noise + shore * 0.3) + caps * 0.6, 0.0, 1.0);
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
