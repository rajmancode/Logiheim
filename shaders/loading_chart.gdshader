// Loading screen (scripts/ui/loading_screen.gd): the map being built, drawn as an old sea chart
// from its own heightmap - ink-washed sea with hatching along the coast, parchment land shaded
// by height with contour lines, a dark ink coastline - revealed from the middle outwards as the
// build progresses, the edge of the reveal glowing like a burning line. Undrawn parchment
// around it, with a slow drift and a vignette.
shader_type canvas_item;

uniform sampler2D chart : filter_linear, repeat_disable;   // r = height 0..1, g = water 0/1
uniform float progress = 0.0;
uniform float aspect = 1.0;       // chart width / height
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec3 parchment : source_color = vec3(0.86, 0.79, 0.64);
uniform vec3 ink : source_color = vec3(0.13, 0.09, 0.06);
uniform vec3 sea_ink : source_color = vec3(0.16, 0.27, 0.33);
uniform vec3 ember : source_color = vec3(1.0, 0.62, 0.2);

// (A sine-free hash: stays smooth at large coordinates, no blocky cells.)
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

void fragment() {
	vec2 px = UV * screen_size;
	// The chart fills most of the screen's height, centred, keeping its own shape.
	float ch = screen_size.y * 0.66;
	float cw = ch * aspect;
	if (cw > screen_size.x * 0.86) {
		cw = screen_size.x * 0.86;
		ch = cw / aspect;
	}
	vec2 org = (screen_size - vec2(cw, ch)) * 0.5 - vec2(0.0, screen_size.y * 0.02);
	vec2 cuv = (px - org) / vec2(cw, ch);
	// Slow drift of the paper.
	vec2 drift = vec2(TIME * 0.004, TIME * 0.002);
	float paper = fbm(px * 0.004 + drift) * 0.6 + fbm(px * 0.03) * 0.4;
	vec3 col = parchment * (0.82 + 0.25 * paper);
	// Stains and foxing.
	col *= 1.0 - smoothstep(0.62, 0.8, fbm(px * 0.002 + 3.0)) * 0.18;

	bool inside = all(greaterThanEqual(cuv, vec2(0.0))) && all(lessThanEqual(cuv, vec2(1.0)));
	if (inside) {
		vec4 c = texture(chart, cuv);
		float h = c.r;
		float wet = c.g;
		vec2 texel = 1.0 / vec2(textureSize(chart, 0));
		float wn = texture(chart, cuv + vec2(texel.x, 0.0)).g + texture(chart, cuv - vec2(texel.x, 0.0)).g
			+ texture(chart, cuv + vec2(0.0, texel.y)).g + texture(chart, cuv - vec2(0.0, texel.y)).g;
		// On the coast: water with land beside it, or land with water beside it.
		float coast = wet > 0.5 ? step(wn, 3.5) : step(0.5, wn);
		vec3 drawn;
		if (wet > 0.5) {
			// Sea: ink wash, darker offshore, hatching that follows the coast.
			float near = smoothstep(0.0, 4.0, wn);
			drawn = mix(parchment * 0.9, sea_ink, 0.35 + 0.25 * (1.0 - h));
			float hatch = step(0.75, fract((cuv.x + cuv.y * 0.6) * 260.0)) * (0.25 + 0.5 * near);
			drawn = mix(drawn, sea_ink * 0.7, hatch * 0.35);
		} else {
			// Land: parchment shaded by height, with contour lines.
			drawn = mix(parchment * 1.02, parchment * vec3(0.72, 0.66, 0.52), smoothstep(0.1, 0.9, h));
			drawn = mix(drawn, vec3(0.45, 0.5, 0.33), smoothstep(0.15, 0.45, h) * (1.0 - smoothstep(0.55, 0.8, h)) * 0.25);
			float band = fract(h * 22.0);
			float line = 1.0 - smoothstep(0.0, 0.08, min(band, 1.0 - band));
			drawn = mix(drawn, ink, line * 0.35);
		}
		drawn = mix(drawn, ink, clamp(coast, 0.0, 1.0) * 0.85);
		drawn *= 0.86 + 0.2 * paper;
		// Reveal: from the middle outwards with a ragged, burning edge.
		vec2 d = (cuv - 0.5) * vec2(aspect, 1.0);
		float r = length(d) / (0.5 * length(vec2(aspect, 1.0)));
		float edge = progress * 1.15 - 0.05 + (fbm(cuv * 6.0 + TIME * 0.05) - 0.5) * 0.18;
		float shown = smoothstep(edge, edge - 0.03, r);
		col = mix(col, drawn, shown);
		float glow = exp(-pow((r - edge) / 0.012, 2.0)) * step(0.001, progress) * step(progress, 0.999);
		col += ember * glow * (0.6 + 0.4 * sin(TIME * 6.0 + r * 40.0));
		// A double ruled frame round the chart.
		vec2 fd = min(cuv, 1.0 - cuv) * vec2(cw, ch);
		float fr = min(fd.x, fd.y);
		col = mix(col, ink, (1.0 - smoothstep(1.0, 2.5, fr)) * 0.9);
		col = mix(col, ink, (1.0 - smoothstep(0.6, 1.6, abs(fr - 7.0))) * 0.6);
	} else {
		// Faint compass-rose lines across the paper outside the chart.
		vec2 cc = (px - screen_size * 0.5) / screen_size.y;
		float ang = atan(cc.y, cc.x);
		float rays = 1.0 - smoothstep(0.0, 0.004, abs(sin(ang * 16.0)) * length(cc));
		col = mix(col, ink, rays * 0.08);
	}
	// Vignette.
	vec2 v = UV - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	COLOR = vec4(col, 1.0);
}
