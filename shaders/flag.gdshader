// A clan flag flying from a pole (BuildingView): cloth that ripples in the wind, more towards
// its free end, with a swallow-tail cut; the clan's emblem painted on both faces (shaders/
// include/emblem.gdshaderinc), the right way round from either side. UV.x runs from the pole
// (0) to the tail (1), UV.y top to bottom. Gently lit by firelight at night.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/include/environment.gdshaderinc"
#include "res://shaders/include/emblem.gdshaderinc"

uniform sampler2D charge : source_color, filter_linear_mipmap;
uniform vec3 field : source_color = vec3(0.8, 0.2, 0.15);
uniform vec3 metal : source_color = vec3(0.95, 0.85, 0.5);
uniform int pattern = 0;
uniform float phase = 0.0;

void vertex() {
	float x = UV.x;
	float t = TIME * (2.5 + 3.5 * wind_strength) + phase;
	float amp = (0.08 + 0.25 * wind_strength) * x;
	float w = sin(x * 7.0 - t) + 0.4 * sin(x * 13.0 - t * 1.7 + UV.y * 2.0);
	VERTEX.z += w * amp;
	VERTEX.y -= x * x * 0.12 * (1.0 - wind_strength);
	float dw = cos(x * 7.0 - t) * 7.0 * amp;
	NORMAL = normalize(vec3(-dw * 0.3, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	// Swallow-tail: a notch cut into the free end.
	if (uv.x > 0.8 && abs(uv.y - 0.5) < (uv.x - 0.8) * 1.4) {
		discard;
	}
	if (!FRONT_FACING) {
		uv.x = 1.0 - uv.x;
	}
	vec2 euv = vec2((uv.x - 0.04) / 0.86, uv.y);
	vec3 col = emblem_color(clamp(euv, 0.0, 1.0), charge, field, metal, pattern, 0.78);
	// A darker hem where it is sewn to the pole.
	col *= mix(0.6, 1.0, smoothstep(0.0, 0.05, UV.x));
	float weave = 0.93 + 0.07 * sin(UV.x * 400.0) * sin(UV.y * 300.0);
	ALBEDO = col * weave;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.35;
}
