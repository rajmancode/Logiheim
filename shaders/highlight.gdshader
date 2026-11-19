// Hover / selection overlay drawn just above a hex top (scripts/map/hex_map.gd).
// UV.x is 0 at the hex centre and 1 on its (noisy) outline: faint fill, bright rim.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.35);

void fragment() {
	float rim = smoothstep(0.78, 0.95, UV.x);
	ALBEDO = color;
	ALPHA = 0.16 + 0.7 * rim;
}
