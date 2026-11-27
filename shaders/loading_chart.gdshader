// Loading screen (scripts/ui/loading_screen.gd): the map being built, drawn as an old sea chart
// from its own heightmap - ink-washed sea hatched along the coast, parchment land shaded by
// height with contour lines, an inked coastline - with ink layers drawn over it as the build
// learns more (rivers and forests, then trails and landmarks).
//
// Each new page burns through the old one: fire catches at a few points and eats outwards in
// ragged tongues, leaving a charred rim with a glowing ember line and sparks drifting up, and
// the new chart lies underneath. At the end the whole screen burns away to show the world.
shader_type canvas_item;

uniform sampler2D base_chart : filter_linear, repeat_disable;   // r = height 0..1, g = water 0/1
uniform sampler2D over_old : filter_linear, repeat_disable;     // ink layer on the old page
uniform sampler2D over_new : filter_linear, repeat_disable;     // ink layer on the new page
uniform float old_base = 0.0;     // 1: the old page shows the chart (0: blank parchment)
uniform float new_base = 0.0;
uniform float burn = 1.0;         // 0..1: the new page burning through the old
uniform vec2 burn_seed = vec2(0.0);
uniform float away = 0.0;         // 0..1: the whole screen burning away at the end
uniform float aspect = 1.0;       // chart width / height
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec3 parchment : source_color = vec3(0.86, 0.79, 0.64);
uniform vec3 ink : source_color = vec3(0.13, 0.09, 0.06);
uniform vec3 sea_ink : source_color = vec3(0.16, 0.27, 0.33);
uniform vec3 ember : source_color = vec3(1.0, 0.55, 0.15);

// (A sine-free hash: stays smooth at large coordinates.)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// The chart page: parchment, with the heightmap drawn on it if `with_base`, and ink over it.
vec3 page(vec2 cuv, vec2 px, float with_base, vec4 ov, float paper) {
	vec3 col = parchment * (0.82 + 0.25 * paper);
	if (with_base > 0.5) {
		vec4 c = texture(base_chart, cuv);
		float h = c.r;
		float wet = c.g;
		vec2 texel = 1.0 / vec2(textureSize(base_chart, 0));
		float wn = texture(base_chart, cuv + vec2(texel.x, 0.0)).g + texture(base_chart, cuv - vec2(texel.x, 0.0)).g
			+ texture(base_chart, cuv + vec2(0.0, texel.y)).g + texture(base_chart, cuv - vec2(0.0, texel.y)).g;
		// On the coast: water with land beside it, or land with water beside it.
		float coast = wet > 0.5 ? step(wn, 3.5) : step(0.5, wn);
		vec3 drawn;
		if (wet > 0.5) {
			float near = smoothstep(0.0, 4.0, wn);
			drawn = mix(parchment * 0.9, sea_ink, 0.35 + 0.25 * (1.0 - h));
			float hatch = step(0.75, fract((cuv.x + cuv.y * 0.6) * 260.0)) * (0.25 + 0.5 * near);
			drawn = mix(drawn, sea_ink * 0.7, hatch * 0.35);
		} else {
			drawn = mix(parchment * 1.02, parchment * vec3(0.72, 0.66, 0.52), smoothstep(0.1, 0.9, h));
			drawn = mix(drawn, vec3(0.45, 0.5, 0.33), smoothstep(0.15, 0.45, h) * (1.0 - smoothstep(0.55, 0.8, h)) * 0.25);
			float band = fract(h * 22.0);
			float line = 1.0 - smoothstep(0.0, 0.08, min(band, 1.0 - band));
			drawn = mix(drawn, ink, line * 0.35);
		}
		drawn = mix(drawn, ink, coast * 0.85);
		col = drawn * (0.86 + 0.2 * paper);
	}
	col = mix(col, ov.rgb, ov.a);
	return col;
}

// How far the fire has to travel to reach a point (0 at the ignition points), ragged.
float burn_field(vec2 q, vec2 seed) {
	float d = 10.0;
	for (int k = 0; k < 3; k++) {
		vec2 c = vec2(0.5) + vec2(sin(seed.x * 3.1 + float(k) * 2.1), cos(seed.y * 2.7 + float(k) * 1.7)) * vec2(0.35, 0.3);
		d = min(d, length(q - c));
	}
	return d + (fbm(q * 5.0 + seed) - 0.5) * 0.35;
}

// Charred rim, ember line and sparks at a burn front.
vec4 fire(float f, float front, vec2 q, float t) {
	float behind = front - f;            // > 0: already burnt through
	float charred = smoothstep(0.05, 0.0, abs(behind - 0.02)) * step(0.0, behind);
	float glow = exp(-pow(behind / 0.008, 2.0));
	vec2 cell = floor(q * 90.0 + vec2(0.0, t * 6.0));
	float spark = step(0.985, hash(cell)) * exp(-pow((behind - 0.01) / 0.03, 2.0));
	float flick = 0.7 + 0.3 * sin(t * 9.0 + f * 60.0);
	return vec4(ember * (glow * 1.6 * flick + spark * 2.0), charred);
}

void fragment() {
	vec2 px = UV * screen_size;
	float ch = screen_size.y * 0.66;
	float cw = ch * aspect;
	if (cw > screen_size.x * 0.86) {
		cw = screen_size.x * 0.86;
		ch = cw / aspect;
	}
	vec2 org = (screen_size - vec2(cw, ch)) * 0.5 - vec2(0.0, screen_size.y * 0.02);
	vec2 cuv = (px - org) / vec2(cw, ch);
	vec2 drift = vec2(TIME * 0.004, TIME * 0.002);
	float paper = fbm(px * 0.004 + drift) * 0.6 + fbm(px * 0.03) * 0.4;
	vec3 col = parchment * (0.82 + 0.25 * paper);
	col *= 1.0 - smoothstep(0.62, 0.8, fbm(px * 0.002 + 3.0)) * 0.18;

	bool inside = all(greaterThanEqual(cuv, vec2(0.0))) && all(lessThanEqual(cuv, vec2(1.0)));
	if (inside) {
		vec3 a = page(cuv, px, old_base, texture(over_old, cuv), paper);
		vec3 b = page(cuv, px, new_base, texture(over_new, cuv), paper);
		vec2 q = cuv * vec2(aspect, 1.0) / max(aspect, 1.0);
		float f = burn_field(q, burn_seed);
		float front = burn * 1.5;
		col = f < front ? b : a;
		if (burn > 0.0 && burn < 1.0) {
			vec4 fx = fire(f, front, q, TIME);
			col = mix(col, vec3(0.08, 0.05, 0.03), fx.a * 0.85);
			col += fx.rgb;
		}
		// A double ruled frame round the chart.
		vec2 fd = min(cuv, 1.0 - cuv) * vec2(cw, ch);
		float fr = min(fd.x, fd.y);
		col = mix(col, ink, (1.0 - smoothstep(1.0, 2.5, fr)) * 0.9);
		col = mix(col, ink, (1.0 - smoothstep(0.6, 1.6, abs(fr - 7.0))) * 0.6);
	} else {
		vec2 cc = (px - screen_size * 0.5) / screen_size.y;
		float ang = atan(cc.y, cc.x);
		float rays = 1.0 - smoothstep(0.0, 0.004, abs(sin(ang * 16.0)) * length(cc));
		col = mix(col, ink, rays * 0.08);
	}
	vec2 v = UV - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	float alpha = 1.0;
	// The end: the whole sheet burns away from the chart outwards, showing the world.
	if (away > 0.0) {
		vec2 q = (px - screen_size * 0.5) / screen_size.y;
		float f = length(q) * 1.1 + (fbm(q * 4.0 + burn_seed) - 0.5) * 0.4;
		float front = away * 1.6;
		if (f < front - 0.06) {
			alpha = 0.0;
		} else {
			vec4 fx = fire(f, front, q + 0.5, TIME);
			col = mix(col, vec3(0.08, 0.05, 0.03), fx.a * 0.9);
			col += fx.rgb;
			alpha = smoothstep(front - 0.06, front - 0.035, f);
		}
	}
	COLOR = vec4(col, alpha);
}
