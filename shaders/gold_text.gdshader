// Gilded lettering for titles (the "LOGIHEIM" on the loading screen and HUD): instead of one flat
// gold, the letters are shaded like beaten metal - bright pale gold along the top catching the
// light, a hard polished horizon across the middle, deep warm bronze below, rising to a reflected
// glow at the foot - with fine hammered grain, a thin bright bevel on the upper edges and a slow
// sheen sweeping across. The dark outline drawn by the font is left as it is.
shader_type canvas_item;

uniform float text_top = 0.0;      // label-space y of the top of the capitals
uniform float text_bottom = 64.0;  // label-space y of the baseline
uniform float text_width = 600.0;
uniform float sheen_speed = 0.25;

varying vec2 lp;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	// The font's dark outline (and its shadow) stays as drawn.
	if (lum > 0.25) {
		float t = clamp((lp.y - text_top) / max(text_bottom - text_top, 1.0), 0.0, 1.0);
		vec3 top = vec3(1.0, 0.97, 0.78);
		vec3 upper = vec3(1.0, 0.8, 0.32);
		vec3 lower = vec3(0.62, 0.36, 0.08);
		vec3 foot = vec3(0.92, 0.66, 0.28);
		vec3 g;
		if (t < 0.48) {
			g = mix(top, upper, smoothstep(0.0, 0.48, t));
		} else if (t < 0.56) {
			g = mix(upper, lower, smoothstep(0.48, 0.56, t));
		} else {
			g = mix(lower, foot, smoothstep(0.56, 1.0, t));
		}
		// Hammered grain: small dents catching the light differently.
		float dents = hash(floor(lp * 0.5)) * 0.6 + hash(floor(lp * 0.17)) * 0.4;
		g *= 0.9 + 0.2 * dents;
		// A bright bevel along the top of each stroke (where the glyph's coverage is just rising).
		g += vec3(0.25, 0.2, 0.1) * smoothstep(0.55, 0.95, 1.0 - t) * 0.25;
		// The sheen: a soft diagonal band of light sliding across now and then.
		float span = text_width * 2.2;
		float x = mod(TIME * sheen_speed * text_width, span) - text_width * 0.6;
		float band = exp(-pow((lp.x + lp.y * 0.5 - x) / (text_width * 0.05), 2.0));
		g += vec3(1.0, 0.95, 0.8) * band * 0.55;
		c.rgb = g;
	}
	COLOR = c;
}
