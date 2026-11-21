// Boulders from assets/models/vegetation/rock_*.glb (tools/blender/rock_shapes.py): photo-scanned
// rock (terrain texture array, rock layer) projected triplanar in world space with its normal
// map, crevices darkened from the vertex-colour AO, lichen spots and moss on upward faces.
// INSTANCE_CUSTOM.a = basalt (0..1): near the volcano boulders turn to dark, fine-grained,
// bare basalt.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_layer = 7.0;       // moss
// Rock textures a boulder can be: granite, cliff, mossy, dark slate (TerrainMaterial.TEXTURES).
const float ROCKS[4] = float[](11.0, 12.0, 13.0, 14.0);
uniform float texture_metres = 3.0;
uniform float moss_amount = 0.4;
uniform vec3 basalt_color = vec3(0.05, 0.048, 0.047);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_ao;
varying float v_basalt;
varying float v_kind;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_ao = COLOR.r;
	v_basalt = INSTANCE_CUSTOM.a;
	// Each boulder its own kind of rock, from where it stands.
	v_kind = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 tri(sampler2DArray tex, vec3 p, vec3 w, float layer) {
	return texture(tex, vec3(p.zy, layer)) * w.x + texture(tex, vec3(p.xz, layer)) * w.y + texture(tex, vec3(p.xy, layer)) * w.z;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = v_world_pos / texture_metres;
	float rock_layer = v_basalt > 0.5 ? 14.0 : ROCKS[int(v_kind * 3.999)];
	vec4 rock = tri(albedo_array, p, w, rock_layer);
	vec4 rn = tri(normal_array, p, w, rock_layer);
	// Second, larger scale breaks up repetition.
	vec4 rock2 = tri(albedo_array, p * 0.37 + 0.31, w, rock_layer);
	vec3 albedo = rock.rgb * mix(0.85, 1.15, rock2.a);
	// Basalt: dark, fine-grained, barely any moss.
	float bas = clamp(v_basalt, 0.0, 1.0);
	float lum = dot(rock.rgb, vec3(0.3, 0.55, 0.15));
	albedo = mix(albedo, basalt_color * (0.7 + 0.8 * lum), bas);
	// Lichen spots (pale grey-green and rusty orange) on exposed faces.
	float lich = smoothstep(0.72, 0.8, env_noise(v_world_pos.xz * 2.3 + v_world_pos.y * 1.7));
	vec3 lich_col = mix(vec3(0.62, 0.64, 0.52), vec3(0.62, 0.4, 0.18), step(0.5, env_noise(v_world_pos.xz * 0.7)));
	albedo = mix(albedo, lich_col, lich * 0.55 * (1.0 - bas) * smoothstep(0.0, 0.6, n.y + 0.3));
	vec4 moss = tri(albedo_array, p * 1.6, w, moss_layer);
	float moss_mask = smoothstep(0.45, 0.85, n.y + (env_noise(v_world_pos.xz * 0.6) - 0.5) * 0.6) * moss_amount * (1.0 - bas);
	moss_mask = clamp(moss_mask + (moss.a - rock.a) * 0.4 * moss_mask, 0.0, 1.0);
	albedo = mix(albedo, moss.rgb * vec3(0.8, 0.9, 0.7), moss_mask);
	// Crevices: strong darkening from the baked cavity AO.
	albedo *= mix(0.35, 1.0, smoothstep(0.15, 0.85, v_ao)) * cloud_shadow(v_world_pos) * (1.0 - 0.3 * wetness);
	ALBEDO = albedo;
	// Texture relief bent around the surface normal.
	vec2 nxy = rn.xy * 2.0 - 1.0;
	vec3 t = normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(1e-5));
	vec3 bt = cross(t, n);
	vec3 wn = normalize(n + (t * nxy.x - bt * nxy.y) * 1.2);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(mix(rn.a, 0.7, bas), 0.9, moss_mask) * (1.0 - 0.4 * wetness);
	AO = rn.b * mix(0.6, 1.0, v_ao);
	AO_LIGHT_AFFECT = 0.5;
}
