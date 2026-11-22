// River water (scripts/map/river_mesh_builder.gd).
//   UV.x across the river (0..1), UV.y metres along it.
//   UV2.x turbulence (0 calm .. 1 white water), UV2.y width in metres, COLOR.r speed / 6 m/s.
// Flow uses two-phase flow mapping: the ripple texture is pushed downstream at each point's
// own speed, and two copies half a cycle apart are cross-faded, so fast and slow water
// never smear the texture over time. Depth from the depth buffer gives clear, shallow edges
// that show the river bed, and colour deepens towards the middle.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2D flow_noise : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.17, 0.27, 0.2);
uniform vec3 deep_color : source_color = vec3(0.035, 0.095, 0.095);
uniform vec3 foam_color : source_color = vec3(0.9, 0.93, 0.94);
uniform float noise_scale = 0.06;     // ripple texture repeats per metre
uniform float cycle = 1.6;            // seconds per flow-map phase
uniform float clarity = 0.7;          // metres of water before the bed is half hidden

varying vec3 v_world_pos;
varying float v_speed;
varying float v_turb;
varying float v_width;
varying float v_fade;
varying float v_sea;
varying vec3 v_shape_n;
uniform vec3 sea_shallow : source_color = vec3(0.17, 0.22, 0.13);   // = the sea's river plume colour

// The water surface's own shape (metres up), from across (u 0..1) and along (metres):
// slightly crowned in the middle, with waves running downstream at the flow's speed and,
// in rapids, standing waves over the rocks. Zero at the banks so the edges stay put.
float surface_h(float u, float along, float w, float speed, float turb, float t) {
	float edge = sin(3.14159 * clamp(u, 0.0, 1.0));
	float crown = edge * clamp(w * 0.015, 0.01, 0.12);
	float a = (0.025 + 0.1 * turb) * clamp(w / 5.0, 0.4, 1.5);
	float x = u * w;
	float run = sin(along * 0.55 - t * (1.2 + speed * 0.9) + sin(x * 0.7) * 0.8) * 0.6
		+ sin(along * 1.35 + x * 0.9 - t * (2.0 + speed * 1.4)) * 0.3
		+ sin(along * 0.23 - x * 0.4 - t * 0.7) * 0.4;
	float stand = sin(along * 1.1) * sin(x * 1.3 + 1.7) * turb * 0.12 * clamp(w / 4.0, 0.3, 1.5);
	return crown + (run * a + stand) * edge;
}

void vertex() {
	v_speed = COLOR.r * 6.0;
	v_turb = UV2.x;
	v_width = UV2.y;
	v_fade = COLOR.g;
	v_sea = COLOR.b;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = surface_h(UV.x, UV.y, v_width, v_speed, v_turb, TIME);
	// Slope of the shape, for its lighting (across in metres per u, and along).
	float du = 0.5 / max(v_width, 0.5);
	float hu = surface_h(UV.x + du, UV.y, v_width, v_speed, v_turb, TIME);
	float hv = surface_h(UV.x, UV.y + 0.5, v_width, v_speed, v_turb, TIME);
	VERTEX.y += h;
	v_world_pos = wp + vec3(0.0, h, 0.0);
	// Tangent frame from the ribbon: across = UV.x direction is the vertex's side, roughly.
	vec3 nb = normalize(NORMAL);
	v_shape_n = normalize(vec3(-(hu - h) / 0.5, 1.0, -(hv - h) / 0.5));
	v_shape_n = normalize(nb + vec3(v_shape_n.x, 0.0, v_shape_n.z));
}

// Ripple normal (xy) and a foam-pattern value pushed `shift` metres downstream.
// `stretch` > 1 drags the pattern into streaks along the flow (fast, falling water).
vec3 flow_sample(vec2 base, float shift, float stretch) {
	vec2 uv = (base - vec2(0.0, shift)) * noise_scale * vec2(1.0, 1.0 / stretch);
	vec3 n1 = texture(flow_noise, uv).xyz * 2.0 - 1.0;
	vec3 n2 = texture(flow_noise, uv * 2.3 + vec2(0.37, 0.11)).xyz * 2.0 - 1.0;
	return vec3((n1.xy + n2.xy * 0.6), n1.x * 0.6 + n2.y * 0.4);
}

void fragment() {
	// Two phases half a cycle apart, each pushed downstream at this point's speed.
	float t = TIME / cycle;
	float ph0 = fract(t);
	float ph1 = fract(t + 0.5);
	float shift = v_speed * cycle;
	vec2 base = vec2(UV.x * v_width, UV.y);
	float stretch = 1.0 + 3.0 * v_turb;
	vec3 s0 = flow_sample(base, ph0 * shift, stretch);
	vec3 s1 = flow_sample(base + vec2(13.7, 7.1), ph1 * shift, stretch);
	float wgt = abs(ph0 - 0.5) * 2.0;
	vec3 s = mix(s0, s1, wgt);
	float rough_water = 0.25 + 0.75 * v_turb;
	vec2 ripple = s.xy * (0.15 + 0.35 * rough_water + 0.15 * wind_strength);

	// Depth under the surface from the depth buffer.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	vec3 bed = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float depth = max(v_world_pos.y - bed.y, 0.0);

	// Colour: the bed shows through shallow water, deeper water goes dark green-blue.
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 2.5, depth));
	vec2 refr = SCREEN_UV + ripple * 0.01 * clamp(depth, 0.0, 1.0);
	vec3 bed_col = textureLod(screen_texture, refr, 0.0).rgb;
	vec3 col = mix(water, bed_col * mix(vec3(1.0), shallow_color * 2.0, 0.4), exp(-depth / clarity));

	// White water: rapids and falls, plus a little along the banks; broken up by the flow.
	float bank = 1.0 - smoothstep(0.0, 0.18, min(UV.x, 1.0 - UV.x));
	// Foam covers more of the surface the rougher the water: streaks over dark water in
	// rapids (about half the surface at full turbulence), nothing on calm stretches.
	float pn = s.z * 0.5 + 0.5;
	float edge0 = 1.0 - 0.55 * v_turb;
	float foam = smoothstep(edge0, edge0 + 0.12, pn) * 0.85 * smoothstep(0.3, 0.6, v_turb);
	foam = max(foam, bank * 0.15 * v_turb * smoothstep(0.5, 0.7, pn));
	col = mix(col, foam_color, foam);
	// Meeting the sea: the river water takes on the sea's shallow green-blue.
	col = mix(col, mix(sea_shallow, bed_col, exp(-depth / 1.5) * 0.6), v_sea * 0.85);
	col *= cloud_shadow(v_world_pos);

	// Lit by the water's own shape (crown and waves) plus the small ripples.
	vec3 wn = normalize(v_shape_n + vec3(ripple.x, 0.0, ripple.y));
	ALBEDO = col;
	ROUGHNESS = mix(0.05, 0.6, foam);
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// Soft banks: fade out where the water gets very shallow.
	ALPHA = clamp(depth / 0.25, 0.0, 1.0) * smoothstep(0.0, 0.06, min(UV.x, 1.0 - UV.x)) + foam * 0.3;
	ALPHA = clamp(ALPHA, 0.0, 1.0) * v_fade;
}
