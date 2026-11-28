// A clan emblem (scripts/game/emblem.gd): the field in the clan's colour, divided by a pattern
// with the second colour, and the charge (a white silhouette from assets/emblems) set in the
// middle, counterchanged - in the second colour on the field, in the field colour on the second
// colour - with a dark keyline round it. uv 0..1 across the cloth or shield, y down.
//   pattern: 0 plain, 1 bordure, 2 per pale, 3 per fess, 4 chevron, 5 quarterly, 6 saltire,
//            7 pale, 8 bend
float emblem_metal(vec2 uv, int pattern) {
	if (pattern == 1) {
		return step(min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)), 0.085);
	} else if (pattern == 2) {
		return step(0.5, uv.x);
	} else if (pattern == 3) {
		return step(0.5, uv.y);
	} else if (pattern == 4) {
		return step(abs(uv.y - (0.86 - abs(uv.x - 0.5) * 0.8)), 0.1);
	} else if (pattern == 5) {
		return abs(step(0.5, uv.x) - step(0.5, uv.y));
	} else if (pattern == 6) {
		return max(step(abs(uv.x - uv.y), 0.09), step(abs(uv.x + uv.y - 1.0), 0.09));
	} else if (pattern == 7) {
		return step(abs(uv.x - 0.5), 0.13);
	} else if (pattern == 8) {
		return step(abs(uv.x - uv.y), 0.12);
	}
	return 0.0;
}

vec3 emblem_color(vec2 uv, sampler2D charge, vec3 field, vec3 metal, int pattern, float charge_scale) {
	float m = emblem_metal(uv, pattern);
	vec3 base = mix(field, metal, m);
	vec2 cuv = (uv - 0.5) / charge_scale + 0.5;
	float inside = step(0.0, cuv.x) * step(cuv.x, 1.0) * step(0.0, cuv.y) * step(cuv.y, 1.0);
	float c = texture(charge, cuv).a * inside;
	// A keyline: the charge grown a little, darker.
	float o = 0.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398;
		vec2 q = cuv + vec2(cos(a), sin(a)) * 0.022;
		o = max(o, texture(charge, q).a * step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0));
	}
	vec3 ccol = mix(metal, field, m);
	base = mix(base, base * 0.25, clamp(o - c, 0.0, 1.0) * 0.85);
	return mix(base, ccol, c);
}
