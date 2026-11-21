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

// Texture-array indices (TerrainMaterial.TEXTURES).
const int T_SAND = 0;
const int T_DUNE = 1;
const int T_WET_SAND = 2;
const int T_PEBBLES = 3;
const int T_GRASS = 4;
const int T_MEADOW = 5;
const int T_SPARSE = 6;
const int T_MOSS = 7;
const int T_FOREST = 8;
const int T_LEAVES = 9;
const int T_NEEDLES = 10;
const int T_ROCK = 11;
const int T_CLIFF = 12;
const int T_MOSSY_ROCK = 13;
const int T_DARK_ROCK = 14;
const int T_SNOW = 15;
const int T_SNOW_ROCK = 16;
const int T_ICE = 17;
const int T_DIRT = 18;
const int T_MUD = 19;
const int T_SOIL = 20;
const int T_GRAVEL = 21;
const int T_ASH = 22;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_size[26];           // metres covered by one texture repeat, per texture
uniform vec4 layer_tint[8];
uniform vec4 tex_tint[26];            // per-texture colour correction (a = saturation)
uniform float blend_depth = 0.18;     // softness of height blending (texture height units)
uniform float normal_strength = 1.0;
uniform float macro_scale = 0.0035;   // large-scale colour variation, 1/metres
uniform float macro_strength = 0.22;
uniform float sea_level = 0.0;        // world y of the sea, for wet sand and the grid
uniform float relief = 300.0;         // metres from the sea to the highest ground
uniform float grid_fade_start = 2500.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_w0;
varying vec4 v_w1;
varying vec2 v_flood;
varying float v_arable;
varying float v_volcanic;
varying vec3 v_ctx;   // moisture, convexity, river bed

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_w0 = COLOR;
	v_w1 = vec4(UV, UV2);
	v_flood = CUSTOM0.xy;
	v_arable = CUSTOM0.z;
	v_volcanic = CUSTOM0.w;
	v_ctx = CUSTOM1.xyz;
}

// Samples one texture: planar from above on flat ground, triplanar on slopes.
// Returns albedo (rgb, a = height) and writes normal (xy -1..1, z = AO, w = roughness).
vec4 sample_tex(int i, vec3 p, vec3 tw, bool tri, out vec4 nrm) {
	float layer = float(i);
	float sc = 1.0 / tex_size[i];
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
	float l = dot(alb.rgb, vec3(0.3, 0.55, 0.15));
	alb.rgb = mix(vec3(l), alb.rgb, tex_tint[i].a) * tex_tint[i].rgb;
	return alb;
}

// Picks two textures from a terrain layer's family and how much of the second shows, from
// where the pixel is: height above the sea (hr), slope (0 flat .. 1 vertical), relative
// altitude, moisture, convexity, river bed, volcanic ground, farmland and two noises.
void pick(int cls, float hr, float slope, float alt, float moist, float convex, float river,
		float volc, float arable, float n1, float n2, out int a, out int b, out float t) {
	float c1 = 0.0;
	float c2 = 0.0;
	float c3 = 0.0;
	int b1 = 0;
	int b2 = 0;
	int b3 = 0;
	if (cls <= 1) {
		// Sea floor: sand with pebble beds near the shore and on rises.
		a = T_SAND;
		b1 = T_PEBBLES; c1 = smoothstep(0.5, 0.68, n1);
		b2 = T_WET_SAND; c2 = 0.5;
	} else if (cls == 2) {
		a = T_SAND;
		b1 = T_WET_SAND; c1 = 1.0 - smoothstep(0.3, 1.5, hr);
		b2 = T_PEBBLES;  c2 = smoothstep(0.58, 0.7, n1) * (1.0 - smoothstep(1.5, 5.0, hr)) + smoothstep(0.12, 0.3, slope) + smoothstep(0.75, 0.95, river) * 0.8;
		b3 = T_DUNE;     c3 = smoothstep(1.8, 4.0, hr) * smoothstep(0.38, 0.6, n2);
	} else if (cls == 3) {
		a = T_GRASS;
		b1 = T_MEADOW; c1 = max(smoothstep(0.35, 0.75, moist), smoothstep(0.6, 0.75, n2) * 0.7);
		b2 = T_SPARSE; c2 = max(smoothstep(0.2, 0.75, convex), smoothstep(0.66, 0.8, n1) * 0.5) * (1.0 - moist * 0.6);
		b3 = T_MOSS;   c3 = smoothstep(0.42, 0.7, alt) * smoothstep(0.4, 0.62, n2 + moist * 0.3);
	} else if (cls == 4) {
		a = T_FOREST;
		b1 = T_NEEDLES; c1 = smoothstep(0.12, 0.4, alt) * (0.7 + 0.3 * n1);
		b2 = T_LEAVES;  c2 = smoothstep(0.55, 0.72, n1) * (1.0 - smoothstep(0.15, 0.35, alt));
		b3 = T_MOSS;    c3 = smoothstep(0.5, 0.85, moist) * smoothstep(0.45, 0.6, n2);
	} else if (cls == 5) {
		a = T_ROCK;
		b1 = T_DARK_ROCK;  c1 = max(volc, smoothstep(0.55, 0.85, alt) * smoothstep(0.45, 0.62, n1));
		b2 = T_CLIFF;      c2 = smoothstep(0.5, 0.8, slope) * (0.55 + 0.45 * n2);
		b3 = T_MOSSY_ROCK; c3 = smoothstep(0.35, 0.75, moist) * (1.0 - smoothstep(0.3, 0.55, alt)) * smoothstep(0.42, 0.6, n2) * (1.0 - volc);
	} else if (cls == 6) {
		a = T_SNOW;
		b1 = T_SNOW_ROCK; c1 = smoothstep(0.22, 0.5, slope) + smoothstep(0.62, 0.76, n1) * 0.6;
		b2 = T_ICE;       c2 = smoothstep(0.8, 0.9, n2) * (1.0 - smoothstep(0.06, 0.15, slope)) * 0.8;
	} else {
		a = T_DIRT;
		b1 = T_MUD;    c1 = max(smoothstep(0.55, 0.9, moist), smoothstep(0.35, 0.7, river) * (1.0 - smoothstep(0.85, 1.0, river)));
		b2 = T_GRAVEL; c2 = max(smoothstep(0.2, 0.45, slope), smoothstep(0.85, 1.0, river) * smoothstep(0.35, 0.6, n2));
		b3 = T_ASH;    c3 = volc;
		if (arable > c3) {
			b3 = T_SOIL;
			c3 = arable;
		}
	}
	// The strongest alternative wins; its strength is how much of it shows.
	b = b1;
	t = c1;
	if (c2 > t) { b = b2; t = c2; }
	if (c3 > t) { b = b3; t = c3; }
	t = clamp(t, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 p = v_world_pos;
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	bool tri = n.y < 0.9;

	float w[LAYERS] = float[](v_w0.x, v_w0.y, v_w0.z, v_w0.w, v_w1.x, v_w1.y, v_w1.z, v_w1.w);
	float hr = p.y - sea_level;
	float slope = 1.0 - n.y;
	float alt = clamp(hr / max(relief, 1.0), 0.0, 1.0);
	float n1 = env_fbm(p.xz * 0.018);
	float n2 = env_noise(p.xz * 0.07 + vec2(13.0, 5.0));

	// Each layer: two textures from its family, blended; then height blending across layers.
	vec4 alb[LAYERS];
	vec4 nrm[LAYERS];
	float score[LAYERS];
	float best = -10.0;
	for (int i = 0; i < LAYERS; i++) {
		score[i] = -10.0;
		alb[i] = vec4(0.0);
		nrm[i] = vec4(0.0);
		if (w[i] > 0.01) {
			int ta;
			int tb;
			float t;
			pick(i, hr, slope, alt, v_ctx.x, v_ctx.y, v_ctx.z, v_volcanic, v_arable, n1, n2, ta, tb, t);
			vec4 nr;
			vec4 a = sample_tex(ta, p, tw, tri, nr);
			if (t > 0.03) {
				vec4 nr2;
				vec4 b2 = sample_tex(tb, p, tw, tri, nr2);
				// Height-aware mix, so the second texture fills in between the first's bumps.
				float m = smoothstep(0.0, 1.0, clamp(t * 1.6 - 0.3 + (b2.a - a.a) * 0.6, 0.0, 1.0));
				a = mix(a, b2, m);
				nr = mix(nr, nr2, m);
			}
			alb[i] = a;
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
		// The dark rock texture, darkened further (linear albedo: basalt is genuinely ~0.05).
		vec4 dn_b;
		vec3 dark = sample_tex(T_DARK_ROCK, p, tw, tri, dn_b).rgb;
		float lum = dot(dark, vec3(0.3, 0.55, 0.15));
		vec3 basalt = vec3(0.048, 0.046, 0.045) * (0.5 + 2.0 * lum);
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
		vec3 soil = sample_tex(T_SOIL, p, tw, false, dn).rgb;
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
