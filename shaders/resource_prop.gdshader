// Natural-resource props (assets/models/resources, placed by scripts/map/resource_props.gd).
// Colour comes from the baked vertex colours. "Glint" surfaces (gold, silver, gems, amber,
// tar) sparkle as the light and camera move. Whales bob in the swell.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform bool glint = false;
uniform bool bob = false;
uniform float roughness = 0.85;

varying vec3 v_world_pos;
varying vec3 v_color;

void vertex() {
	if (bob) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float ph = dot(o.xz, vec2(0.13, 0.07));
		VERTEX.y += (sin(TIME * 0.45 + ph) * 0.35 - 0.15) / max(length(MODEL_MATRIX[1].xyz), 0.001);
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 col = v_color * cloud_shadow(v_world_pos) * (1.0 - 0.25 * wetness);
	ALBEDO = col;
	ROUGHNESS = roughness * (1.0 - 0.4 * wetness);
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
