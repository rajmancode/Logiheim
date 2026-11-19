// Boulders from assets/models/vegetation/rock_*.glb: photo-scanned rock (terrain texture
// array, rock layer) projected triplanar in world space, moss on upward faces, vertex-colour AO.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_layer = 5.0;
uniform float moss_layer = 4.0;
uniform float texture_metres = 5.0;
uniform float moss_amount = 0.45;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_ao;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_ao = COLOR.r;
}

vec4 tri(sampler2DArray tex, vec3 p, vec3 w, float layer) {
	return texture(tex, vec3(p.zy, layer)) * w.x + texture(tex, vec3(p.xz, layer)) * w.y + texture(tex, vec3(p.xy, layer)) * w.z;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = v_world_pos / texture_metres;
	vec4 rock = tri(albedo_array, p, w, rock_layer);
	vec4 rn = tri(normal_array, p, w, rock_layer);
	vec4 moss = tri(albedo_array, p * 1.6, w, moss_layer);
	float moss_mask = smoothstep(0.45, 0.85, n.y + (env_noise(v_world_pos.xz * 0.6) - 0.5) * 0.6) * moss_amount;
	moss_mask = clamp(moss_mask + (moss.a - rock.a) * 0.4 * moss_mask, 0.0, 1.0);
	vec3 albedo = mix(rock.rgb, moss.rgb * vec3(0.8, 0.9, 0.7), moss_mask);
	albedo *= mix(0.55, 1.0, v_ao) * cloud_shadow(v_world_pos) * (1.0 - 0.3 * wetness);
	ALBEDO = albedo;
	ROUGHNESS = mix(rn.a, 0.9, moss_mask) * (1.0 - 0.4 * wetness);
	AO = rn.b;
	AO_LIGHT_AFFECT = 0.4;
}
