// Natural-resource props (assets/models/resources, placed by scripts/map/resource_props.gd).
// Base colour comes from the baked vertex colours; surface detail from the terrain's PBR
// texture set (scripts/map/terrain_material.gd), chosen per pixel by what the colour looks
// like: grey = stone (rock texture), sandy = sand, earthy = soil, brown = wood (procedural
// grain), everything else gets the rock texture's relief only. Mapped triplanar in world space
// so it fits any prop at any size. "Glint" surfaces (gold, silver, gems, amber, tar) sparkle as
// the light and camera move. Whales bob in the swell.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform bool glint = false;
uniform bool bob = false;
uniform float roughness = 0.85;
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_metres = 2.5;   // metres per texture repeat on props
uniform float detail = 1.0;           // 0 = flat vertex colours

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_color;

void vertex() {
	if (bob) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float ph = dot(o.xz, vec2(0.13, 0.07));
		VERTEX.y += (sin(TIME * 0.45 + ph) * 0.35 - 0.15) / max(length(MODEL_MATRIX[1].xyz), 0.001);
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR.rgb;
}

// Triplanar sample of one terrain layer: albedo (rgb) and tangent normal xy (-1..1) + AO in z.
vec3 tri_albedo(float layer, vec3 p, vec3 tw) {
	return texture(albedo_array, vec3(p.zy, layer)).rgb * tw.x
		+ texture(albedo_array, vec3(p.xz, layer)).rgb * tw.y
		+ texture(albedo_array, vec3(p.xy, layer)).rgb * tw.z;
}

vec3 tri_normal(float layer, vec3 p, vec3 tw) {
	vec4 nx = texture(normal_array, vec3(p.zy, layer));
	vec4 ny = texture(normal_array, vec3(p.xz, layer));
	vec4 nz = texture(normal_array, vec3(p.xy, layer));
	vec4 n = nx * tw.x + ny * tw.y + nz * tw.z;
	return vec3(n.xy * 2.0 - 1.0, n.z);
}

// Average colour of a layer (its smallest mip), so textures add detail without shifting hue.
vec3 layer_mean(float layer) {
	return max(textureLod(albedo_array, vec3(0.5, 0.5, layer), 12.0).rgb, vec3(0.05));
}

// Wood grain: fibres along the dominant axis of each triplanar plane, with growth rings.
float wood(vec3 p, vec3 tw) {
	vec2 q[3] = vec2[](p.zy, p.xz, p.xy);
	float g = 0.0;
	for (int k = 0; k < 3; k++) {
		vec2 u = q[k] * 4.0;
		float warp = env_noise(vec2(u.x * 0.6, u.y * 6.0)) * 3.0;
		float rings = 0.5 + 0.5 * sin(u.y * 9.0 + warp * 2.0);
		float fibre = env_noise(vec2(u.x * 0.4, u.y * 28.0));
		g += (0.62 + 0.25 * rings + 0.18 * fibre) * (k == 0 ? tw.x : (k == 1 ? tw.y : tw.z));
	}
	return g;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	vec3 p = v_world_pos / texture_metres;
	vec3 c = v_color;

	// What is this surface made of? (from its painted colour)
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 1e-3);
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float warm = smoothstep(0.0, 0.12, c.r - c.b);
	float stone = 1.0 - smoothstep(0.1, 0.25, sat);
	float woody = warm * smoothstep(0.2, 0.35, sat) * (1.0 - smoothstep(0.32, 0.5, lum)) * (1.0 - stone);
	float sandy = warm * smoothstep(0.45, 0.6, lum) * (1.0 - stone) * (1.0 - woody);
	float earthy = clamp(warm * (1.0 - stone) - woody - sandy, 0.0, 1.0);

	vec3 rock_a = tri_albedo(5.0, p, tw) / layer_mean(5.0);
	vec3 rock_n = tri_normal(5.0, p, tw);
	vec3 mod_col = rock_a;
	vec3 nrm = rock_n;
	if (sandy > 0.01) {
		mod_col = mix(mod_col, tri_albedo(2.0, p * 2.0, tw) / layer_mean(2.0), sandy);
		nrm = mix(nrm, tri_normal(2.0, p * 2.0, tw), sandy);
	}
	if (earthy > 0.01) {
		mod_col = mix(mod_col, tri_albedo(7.0, p * 1.5, tw) / layer_mean(7.0), earthy);
		nrm = mix(nrm, tri_normal(7.0, p * 1.5, tw), earthy);
	}
	if (woody > 0.01) {
		mod_col = mix(mod_col, vec3(wood(v_world_pos, tw)), woody);
		nrm.xy *= 1.0 - woody * 0.7;
	}
	// Coloured details (ore streaks, plants, glints) keep their colour but get the relief.
	float textured = clamp(stone + sandy + earthy + woody, 0.25, 1.0) * detail;
	vec3 col = c * mix(vec3(1.0), clamp(mod_col, vec3(0.4), vec3(1.7)), textured);
	col *= mix(1.0, nrm.z, 0.6 * detail);

	// Bend the normal by the texture relief.
	vec3 t = normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(1e-5));
	vec3 bt = cross(t, n);
	vec3 wn = normalize(n + (t * nrm.x - bt * nrm.y) * detail);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	col *= cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = roughness * (1.0 - 0.4 * wetness) * mix(1.0, 0.92, woody);
	if (glint) {
		// Tiny facets catching the sun: high-frequency noise that shifts with the view.
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
		float s = env_noise(v_world_pos.xz * 9.0 + vdir.xz * 6.0 + vec2(TIME * 0.15));
		float spark = smoothstep(0.82, 0.97, s) * max(sun_direction.y, 0.0);
		ROUGHNESS = 0.15;
		METALLIC = 0.6;
		SPECULAR = 0.8;
		EMISSION = col * spark * 3.0;
	}
}
