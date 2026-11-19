// Flowing river ribbons from scripts/map/river_mesh_builder.gd.
// UV.x runs across the river (0..1), UV.y along it in metres, so scrolling UV.y moves the
// water downstream. UV2.x = 1 on waterfalls, UV2.y = river width in metres.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform sampler2D flow_noise : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 river_color : source_color = vec3(0.10, 0.27, 0.30);
uniform vec3 river_edge_color : source_color = vec3(0.24, 0.38, 0.33);
uniform vec3 foam_color : source_color = vec3(0.88, 0.92, 0.94);
uniform float flow_speed = 3.0;        // metres per second
uniform float fall_speed = 9.0;
uniform float noise_scale = 0.05;      // noise repeats per metre
uniform float ripple_strength = 0.35;

varying float v_fall;
varying float v_width;
varying vec3 v_world_pos;

void vertex() {
	v_fall = UV2.x;
	v_width = UV2.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float speed = mix(flow_speed, fall_speed, v_fall) * (0.8 + 0.4 * wind_strength);
	vec2 base = vec2(UV.x * v_width, UV.y);
	vec2 uv1 = base * noise_scale - vec2(0.0, TIME * speed * noise_scale);
	vec2 uv2 = base * noise_scale * 1.9 + vec2(0.37, 0.11) - vec2(0.0, TIME * speed * noise_scale * 1.35);
	vec3 n1 = texture(flow_noise, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(flow_noise, uv2).xyz * 2.0 - 1.0;

	// Foam along the banks and all over waterfalls, broken up by the moving noise.
	float bank = 1.0 - smoothstep(0.0, 0.22, min(UV.x, 1.0 - UV.x));
	float churn = smoothstep(0.15, 0.6, n1.x * 0.5 + n2.y * 0.5 + 0.35);
	float foam = clamp(max(bank * 0.35, v_fall * 0.8) * churn, 0.0, 1.0);

	vec3 water = mix(river_color, river_edge_color, bank * 0.6);
	vec3 albedo = mix(water, foam_color, foam);
	albedo *= cloud_shadow(v_world_pos);

	vec2 ripple = (n1.xy + n2.xy) * ripple_strength * (1.0 - v_fall * 0.5);
	vec3 rn = normalize(NORMAL + (VIEW_MATRIX * vec4(ripple.x, 0.0, ripple.y, 0.0)).xyz);

	ALBEDO = albedo;
	ROUGHNESS = mix(0.06, 0.55, foam);
	SPECULAR = 0.6;
	NORMAL = rn;
}
