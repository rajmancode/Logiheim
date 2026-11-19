// Drifting cloud layer: a large plane at cloud_height, shaped by the same noise that casts
// cloud shadows on the ground (environment.gdshaderinc). Lit by hand so colours follow the
// time of day; fades out near the camera so you can zoom through it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.55, 0.6, 0.68);
uniform float opacity = 0.85;
uniform float near_fade = 150.0;       // fully transparent closer than this
uniform float near_fade_end = 700.0;   // fully visible beyond this
uniform vec2 fade_center = vec2(1024.0);   // map centre (x, z)
uniform vec2 fade_radius = vec2(1800.0, 3600.0); // clouds thin out between these distances

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = cloud_density(v_world_pos.xz);
	// Denser cloud between here and the sun means this point is in the cloud's own shadow.
	vec2 to_sun = normalize(sun_direction.xz + vec2(1e-4));
	float d_sun = cloud_density(v_world_pos.xz + to_sun * 70.0);
	float lit = clamp(1.0 - (d_sun - d * 0.5) * 1.2, 0.25, 1.0);
	vec3 col = mix(shade_color, light_color, lit);

	float cam = distance(CAMERA_POSITION_WORLD, v_world_pos);
	float fade = smoothstep(near_fade, near_fade_end, cam);
	fade *= 1.0 - smoothstep(fade_radius.x, fade_radius.y, distance(v_world_pos.xz, fade_center));

	ALBEDO = col;
	ALPHA = clamp(d * opacity * fade, 0.0, 1.0);
}
