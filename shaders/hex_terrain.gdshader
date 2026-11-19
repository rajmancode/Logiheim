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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_w0 = COLOR;
	v_w1 = vec4(UV, UV2);
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

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	EMISSION = emission;
}
