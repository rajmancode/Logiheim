// A clan emblem on a shield, for the interface (the emblem editor, the top bar): a heater
// shield with a gold rim, a little shading, the emblem painted on it.
shader_type canvas_item;

#include "res://shaders/include/emblem.gdshaderinc"

uniform sampler2D charge : source_color, filter_linear_mipmap;
uniform vec3 field : source_color = vec3(0.8, 0.2, 0.15);
uniform vec3 metal : source_color = vec3(0.95, 0.85, 0.5);
uniform int pattern = 0;

// Signed distance-ish to the shield's edge: < 0 inside.
float shield(vec2 p) {
	float x = abs(p.x - 0.5);
	if (p.y < 0.5) {
		return max(x - 0.44, 0.04 - p.y);
	}
	float t = (p.y - 0.5) / 0.46;
	float half_w = 0.44 * sqrt(max(1.0 - t * t, 0.0));
	return max(x - half_w, p.y - 0.96);
}

void fragment() {
	vec2 p = UV;
	float d = shield(p);
	if (d > 0.012) {
		COLOR = vec4(0.0);
	} else {
		vec2 inner = vec2((p.x - 0.06) / 0.88, (p.y - 0.04) / 0.92);
		vec3 col = emblem_color(clamp(inner, 0.0, 1.0), charge, field, metal, pattern, 0.62);
		// Light from the upper left, darker towards the bottom.
		col *= 1.08 - 0.3 * p.y + 0.1 * (0.5 - p.x);
		float rim = smoothstep(-0.05, -0.03, d);
		col = mix(col, vec3(0.86, 0.68, 0.32), rim);
		col = mix(col, vec3(0.1, 0.06, 0.03), smoothstep(-0.004, 0.012, d));
		COLOR = vec4(col, 1.0 - smoothstep(0.004, 0.012, d));
	}
}
