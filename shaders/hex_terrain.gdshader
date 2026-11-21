// Soft-stepped terrain (scripts/map/terrain_surface.gd, terrain_mesh_builder.gd).
//
// Each vertex carries 8 terrain weights (COLOR = layers 0-3, UV = 4-5, UV2 = 6-7). Layers are
// photo-scanned PBR sets in texture arrays: albedo.a holds height (for height-based blending,
// so grass grows between stones instead of fading over them) and normal.ba hold AO/roughness.
// Flat ground is projected from above; steep ground uses triplanar mapping.
// Adds large-scale colour variation, grid lines/highlights, cloud shadows and wetness.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"
#include "res://shaders/include/hex_grid.gdshaderinc"

global uniform float flood;              // 0 dry .. 1 rivers in full flood (Atmosphere)
uniform float flood_rise = 4.4;          // metres the water climbs above river level in full flood
uniform sampler2D flood_ripples : hint_normal, filter_linear_mipmap, repeat_enable;

const int LAYERS = 8;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_size[8];          // metres covered by one texture repeat, per layer
uniform vec4 layer_tint[8];
uniform float blend_depth = 0.18;     // softness of height blending (texture height units)
uniform float normal_strength = 1.0;
uniform float macro_scale = 0.0035;   // large-scale colour variation, 1/metres
uniform float macro_strength = 0.22;
uniform float sea_level = 0.0;        // world y of the sea, for wet sand and the grid
uniform float grid_fade_start = 2500.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_w0;
varying vec4 v_w1;
varying vec2 v_flood;
varying float v_arable;
varying float v_volcanic;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_w0 = COLOR;
	v_w1 = vec4(UV, UV2);
	v_flood = CUSTOM0.xy;
	v_arable = CUSTOM0.z;
	v_volcanic = CUSTOM0.w;
}

// Samples one layer: planar from above on flat ground, triplanar on slopes.
// Returns albedo (rgb, a = height) and writes normal (xy -1..1, z = AO, w = roughness).
vec4 sample_layer(int i, vec3 p, vec3 tw, bool tri, out vec4 nrm) {
	float layer = float(i);
	float sc = 1.0 / layer_size[i];
	vec4 ay = texture(albedo_array, vec3(p.xz * sc, layer));
	vec4 ny = texture(normal_array, vec3(p.xz * sc, layer));
	vec4 alb = ay;
	nrm = ny;
	if (tri) {
		vec4 ax = texture(albedo_array, vec3(p.zy * sc, layer));
		vec4 az = texture(albedo_array, vec3(p.xy * sc, layer));
		vec4 nx = texture(normal_array, vec3(p.zy * sc, layer));
		vec4 nz = texture(normal_array, vec3(p.xy * sc, layer));
		alb = ax * tw.x + ay * tw.y + az * tw.z;
		nrm = nx * tw.x + ny * tw.y + nz * tw.z;
	}
	nrm.xy = nrm.xy * 2.0 - 1.0;
	return alb;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 p = v_world_pos;
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	bool tri = n.y < 0.9;

	float w[LAYERS] = float[](v_w0.x, v_w0.y, v_w0.z, v_w0.w, v_w1.x, v_w1.y, v_w1.z, v_w1.w);

	// Height blending: each layer's texture height raises its claim on the pixel.
	vec4 alb[LAYERS];
	vec4 nrm[LAYERS];
	float score[LAYERS];
	float best = -10.0;
	for (int i = 0; i < LAYERS; i++) {
		score[i] = -10.0;
		alb[i] = vec4(0.0);
		nrm[i] = vec4(0.0);
		if (w[i] > 0.01) {
			vec4 nr;
			alb[i] = sample_layer(i, p, tw, tri, nr);
			nrm[i] = nr;
			score[i] = w[i] + alb[i].a * 0.5;
			best = max(best, score[i]);
		}
	}
	vec3 albedo = vec3(0.0);
	vec2 nrm_xy = vec2(0.0);
	float ao = 0.0;
	float rough = 0.0;
	float total = 0.0;
	for (int i = 0; i < LAYERS; i++) {
		if (score[i] > -9.0) {
			float b = max(score[i] - (best - blend_depth), 0.0);
			albedo += alb[i].rgb * layer_tint[i].rgb * b;
			nrm_xy += nrm[i].xy * b;
			ao += nrm[i].z * b;
			rough += nrm[i].w * b;
			total += b;
		}
	}
	total = max(total, 1e-4);
	albedo /= total;
	nrm_xy /= total;
	ao /= total;
	rough /= total;

	// Volcanic ground: dark basalt. Steep faces show columnar jointing: tall prisms with dark
	// joints between them and the odd cross-crack, each column a slightly different shade.
	if (v_volcanic > 0.02) {
		float lum = dot(albedo, vec3(0.3, 0.55, 0.15));
		// (Linear albedo: basalt is genuinely dark, ~0.05.)
		vec3 basalt = vec3(0.048, 0.046, 0.045) * (0.6 + 1.4 * lum);
		if (n.y < 0.75) {
			vec2 tdir = normalize(vec2(-n.z, n.x) + vec2(1e-5));
			float u = dot(p.xz, tdir) / 1.5;
			float col = fract(u);
			float cell = floor(u);
			float joint = smoothstep(0.0, 0.07, col) * smoothstep(1.0, 0.93, col);
			float band = fract(p.y / (2.5 + env_hash(vec2(cell, 3.0)) * 3.5) + env_hash(vec2(cell, 7.0)));
			float crack = smoothstep(0.0, 0.035, band) * smoothstep(1.0, 0.965, band);
			float shade = 0.8 + 0.4 * env_hash(vec2(cell, 11.0));
			float steep = smoothstep(0.75, 0.45, n.y);
			basalt *= mix(1.0, mix(0.3, 1.0, joint * crack) * shade, steep);
			nrm_xy.x += (col - 0.5) * 0.9 * joint * steep;
		}
		float vb = smoothstep(0.0, 0.6, v_volcanic);
		albedo = mix(albedo, basalt, vb * 0.92);
		rough = mix(rough, 0.72, vb);
	}

	// Arable land: a patchwork of fields (ploughed furrows, young green crops, ripening
	// grain, fallow meadow) on rich dark soil, each field with its own furrow direction.
	if (v_arable > 0.02 && !tri) {
		vec2 fc = p.xz / 46.0;
		vec2 cell = floor(fc + vec2(env_noise(p.xz * 0.03), env_noise(p.zx * 0.03 + 5.0)) * 0.6);
		float r = env_hash(cell);
		float r2 = env_hash(cell + vec2(17.0, 3.0));
		float ang = r * 3.14159;
		vec2 dir = vec2(cos(ang), sin(ang));
		float furrow = 0.5 + 0.5 * sin(dot(p.xz, dir) * 6.2832 / 1.6);
		vec4 dn;
		vec3 soil = sample_layer(7, p, tw, false, dn).rgb * layer_tint[7].rgb * vec3(0.78, 0.7, 0.62);
		vec3 field;
		// Crops tint the real grass texture, so fields keep its detail instead of flat paint.
		if (r2 < 0.3) {
			field = soil * (0.7 + 0.45 * furrow);                                   // ploughed
		} else if (r2 < 0.55) {
			field = mix(soil, albedo * vec3(0.78, 1.05, 0.6), 0.35 + 0.45 * furrow); // young crop
		} else if (r2 < 0.75) {
			field = mix(soil, albedo * vec3(1.3, 1.08, 0.55), 0.4 + 0.4 * furrow);   // ripening grain
		} else {
			field = albedo * vec3(0.92, 1.08, 0.82);                               // fallow meadow
		}
		// Field margins stay grassy.
		vec2 fe = abs(fract(fc + vec2(env_noise(p.xz * 0.03), env_noise(p.zx * 0.03 + 5.0)) * 0.6) - 0.5);
		float margin = smoothstep(0.42, 0.48, max(fe.x, fe.y));
		float a = smoothstep(0.1, 0.6, v_arable) * (1.0 - margin) * 0.85;
		albedo = mix(albedo, field, a);
		rough = mix(rough, 0.95, a);
	}

	// Large-scale variation so tiling doesn't show from far away.
	float macro = env_fbm(p.xz * macro_scale);
	albedo *= 1.0 + (macro - 0.5) * 2.0 * macro_strength;

	// Wet sand along the waterline.
	float shore = 1.0 - smoothstep(sea_level, sea_level + 1.2, p.y);
	albedo *= 1.0 - 0.3 * shore;
	rough = mix(rough, 0.25, shore * 0.7);
	// Rain wetness.
	albedo *= 1.0 - 0.35 * wetness;
	rough = mix(rough, rough * 0.45, wetness);
	// Floodwater on floodplains: muddy, glossy and flat wherever the ground lies below the
	// rising water.
	float flooded = 0.0;
	vec2 ripple = vec2(0.0);
	if (flood > 0.001 && v_flood.x > 0.01) {
		float level = v_flood.y - 0.6 + flood * flood_rise;
		float d = level - p.y;
		flooded = smoothstep(0.0, 0.3, d) * smoothstep(0.02, 0.25, v_flood.x);
		if (flooded > 0.0) {
			vec2 fuv = p.xz * 0.02 - wind_direction * wind_time * 0.03;
			vec3 r1 = texture(flood_ripples, fuv).xyz * 2.0 - 1.0;
			vec3 r2 = texture(flood_ripples, fuv * 2.1 + vec2(0.3, 0.7)).xyz * 2.0 - 1.0;
			ripple = (r1.xy + r2.xy) * 0.15;
			// Silty brown floodwater; the ground shows through where it is still shallow.
			vec3 water = mix(vec3(0.46, 0.4, 0.27), vec3(0.3, 0.27, 0.18), smoothstep(0.0, 3.0, d));
			water = mix(albedo * 0.7, water, smoothstep(0.0, 0.5, d));
			albedo = mix(albedo, water, flooded);
			rough = mix(rough, 0.06, flooded);
			ao = mix(ao, 1.0, flooded);
		}
	}
	albedo *= cloud_shadow(p);

	// Grid on land only (the water surface draws its own), fading with distance.
	vec3 emission = vec3(0.0);
	if (p.y > sea_level - 0.3) {
		float fade = 1.0 - smoothstep(grid_fade_start, grid_fade_start * 2.0, length(p - CAMERA_POSITION_WORLD));
		emission = apply_hex_grid(albedo, p.xz, fade);
	}

	// Detail normal: tangent-space xy (GL convention) bent around the geometric normal.
	vec3 t = normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(1e-5));
	vec3 bt = cross(t, n);
	vec3 wn = normalize(n + (t * nrm_xy.x - bt * nrm_xy.y) * normal_strength);
	wn = normalize(mix(wn, normalize(vec3(ripple.x, 1.0, ripple.y)), flooded));

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	EMISSION = emission;
}
