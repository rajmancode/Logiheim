// Stepped hex terrain: triplanar texture arrays (one layer per terrain type), whiteout
// normal blending, macro variation against tiling, soil-to-rock cliff walls with fake AO,
// animated water, grid lines and hover/selection highlights.
// Vertex data comes from scripts/map/hex_mesh_builder.gd.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int TERRAIN_COUNT = 8;
const float ROCK_LAYER = 5.0;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 terrain_tint[8];
uniform float terrain_roughness[8];

uniform float texture_scale = 0.07;   // texture repeats per metre
uniform float macro_scale = 0.011;    // second, larger sampling to break up tiling
uniform float macro_strength = 0.35;
uniform float normal_strength = 1.0;

uniform bool show_grid = true;
uniform float grid_width = 0.05;
uniform float grid_strength = 0.4;

uniform float wall_soil_depth = 3.0;  // metres of soil before cliffs turn to rock
uniform float wall_ao_depth = 40.0;
uniform float wall_ao_strength = 0.5;

uniform sampler2D water_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 water_deep_color = vec3(0.008, 0.045, 0.085);
uniform vec3 water_shallow_color = vec3(0.02, 0.16, 0.18);
uniform float water_wave_scale = 0.006;
uniform float water_wave_strength = 0.35;

uniform vec4 hover_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec3 hover_cell = vec3(0.0, 0.0, -1.0);   // centre x, centre z, size (<= 0 disables)
uniform float hover_y = 0.0;
uniform vec4 select_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec3 select_cell = vec3(0.0, 0.0, -1.0);
uniform float select_y = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_terrain;
varying float v_wall;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_terrain = UV2.x;
	v_wall = UV2.y;
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec3 sample_albedo(vec3 p, vec3 w, float layer) {
	return texture(albedo_array, vec3(p.zy, layer)).rgb * w.x
		+ texture(albedo_array, vec3(p.xz, layer)).rgb * w.y
		+ texture(albedo_array, vec3(p.xy, layer)).rgb * w.z;
}

// Triplanar normal mapping with whiteout blending (Ben Golus).
vec3 sample_normal(vec3 p, vec3 n, vec3 w, float layer) {
	vec3 tx = texture(normal_array, vec3(p.zy, layer)).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_array, vec3(p.xz, layer)).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_array, vec3(p.xy, layer)).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength;
	ty.xy *= normal_strength;
	tz.xy *= normal_strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

// 0 outside the hex, a faint fill inside and a bright rim near the edge.
float hex_highlight(vec2 p, vec3 cell) {
	if (cell.z <= 0.0) {
		return 0.0;
	}
	vec2 d = abs(p - cell.xy);
	float v = max(d.x, 0.5 * d.x + 0.8660254 * d.y) / (0.8660254 * cell.z);
	float inside = 1.0 - step(1.0, v);
	return inside * (smoothstep(0.78, 0.94, v) * 0.85 + 0.15);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 w = triplanar_weights(n);
	float layer = floor(v_terrain + 0.5);
	int ti = clamp(int(layer), 0, TERRAIN_COUNT - 1);
	bool is_wall = v_wall > 0.5;
	vec3 p = v_world_pos * texture_scale;

	vec3 albedo;
	vec3 wn;
	float rough = terrain_roughness[ti];

	if (ti <= 1 && !is_wall) {
		// Water surface: two scrolling normal layers.
		vec2 uv1 = v_world_pos.xz * water_wave_scale + TIME * vec2(0.012, 0.007);
		vec2 uv2 = v_world_pos.xz * water_wave_scale * 1.9 - TIME * vec2(0.009, 0.014);
		vec3 n1 = texture(water_normal, uv1).xyz * 2.0 - 1.0;
		vec3 n2 = texture(water_normal, uv2).xyz * 2.0 - 1.0;
		vec2 slope = (n1.xy + n2.xy) * water_wave_strength;
		wn = normalize(vec3(slope.x, 1.0, slope.y));
		albedo = ti == 0 ? water_deep_color : water_shallow_color;
		rough = terrain_roughness[ti];
	} else {
		vec3 base = sample_albedo(p, w, layer);
		vec3 macro = sample_albedo(v_world_pos * macro_scale, w, layer);
		base = mix(base, macro, macro_strength) * terrain_tint[ti].rgb;
		wn = sample_normal(p, n, w, layer);
		if (is_wall) {
			// Soil under the lip, rock further down, darker towards the bottom.
			float rock_mix = smoothstep(wall_soil_depth, wall_soil_depth * 2.5, UV.y);
			vec3 rock = sample_albedo(p, w, ROCK_LAYER) * terrain_tint[5].rgb;
			base = mix(base, rock, rock_mix);
			wn = normalize(mix(wn, sample_normal(p, n, w, ROCK_LAYER), rock_mix));
			rough = mix(rough, terrain_roughness[5], rock_mix);
			base *= 1.0 - wall_ao_strength * smoothstep(0.0, wall_ao_depth, UV.y);
			base *= 1.0 + 0.12 * (1.0 - smoothstep(0.0, 0.8, UV.y));
		}
		albedo = base;
	}

	vec3 emission = vec3(0.0);
	if (!is_wall) {
		if (show_grid) {
			float e = smoothstep(1.0 - grid_width, 1.0, UV.x);
			albedo *= 1.0 - e * grid_strength;
		}
		float h = hex_highlight(v_world_pos.xz, hover_cell) * (1.0 - step(0.05, abs(v_world_pos.y - hover_y)));
		float s = hex_highlight(v_world_pos.xz, select_cell) * (1.0 - step(0.05, abs(v_world_pos.y - select_y)));
		albedo = mix(albedo, hover_color.rgb, h * 0.3);
		albedo = mix(albedo, select_color.rgb, s * 0.3);
		emission = hover_color.rgb * h * 0.5 + select_color.rgb * s * 0.5;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	EMISSION = emission;
}
