// The sea's motion, shared by the sea (shaders/water.gdshader) and what floats on it (the
// borders, shaders/border.gdshader), so a border drawn over the water rises and falls with
// the very waves under it. Needs environment.gdshaderinc (wind, env_noise) included first.

float waves(vec2 p, float t) {
	vec2 d1 = wind_direction;
	vec2 d2 = vec2(-wind_direction.y, wind_direction.x) * 0.7 + wind_direction * 0.7;
	return sin(dot(p, d1) * 0.045 + t * 0.45) * 0.6 + sin(dot(p, d2) * 0.07 + t * 0.6) * 0.4;
}

// One Gerstner wave: moves the surface up and sideways (towards the crest), so crests sharpen
// and troughs flatten like real swell. Adds to disp and to the normal's slope terms.
void gerstner(vec2 xz, vec2 dir, float len, float amp, float steep, float t, inout vec3 disp, inout vec3 nrm) {
	float k = 6.2832 / len;
	float c = sqrt(9.8 / k) * 0.5;
	float f = k * (dot(dir, xz) - c * t);
	float q = steep / (k * amp * 3.0 + 1e-4);
	disp.xz += q * amp * dir * cos(f);
	disp.y += amp * sin(f);
	nrm.xz -= dir * k * amp * cos(f);
	nrm.y -= q * k * amp * sin(f);
}

// The ground under the sea at xz from a terrain height map, over a ~12 m footprint so breaker
// lines follow the shore smoothly instead of every step of the terrain grid.
float sea_ground(sampler2D tex, vec2 xz, vec2 size, float tmin, float trange) {
	vec2 tuv = xz / size;
	if (tuv.x < 0.0 || tuv.y < 0.0 || tuv.x > 1.0 || tuv.y > 1.0) {
		return -100.0;
	}
	vec2 o = vec2(6.0) / size;
	float g = texture(tex, tuv).r * 2.0
		+ texture(tex, tuv + vec2(o.x, 0.0)).r + texture(tex, tuv - vec2(o.x, 0.0)).r
		+ texture(tex, tuv + vec2(0.0, o.y)).r + texture(tex, tuv - vec2(0.0, o.y)).r;
	return g / 6.0 * trange + tmin;
}

// How a point of the sea surface (wp, at sea level) moves: a gentle heave everywhere and, given
// the ground under it (`has_ground`), swell that grows offshore and breakers that lift as they
// reach the shallows. `still` 0..1 calms it (river mouths). Returns the offset; nrm the normal.
vec3 sea_offset(vec3 wp, bool has_ground, float ground, float wave_h, float swell_m, float surf_k, float surf_t, float still, out vec3 nrm) {
	float amp = wave_h * (0.4 + 1.2 * wind_strength);
	float base_y = waves(wp.xz, wind_time) * amp * still;
	vec3 off = vec3(0.0, base_y, 0.0);
	nrm = vec3(0.0, 1.0, 0.0);
	if (!has_ground) {
		return off;
	}
	float depth = wp.y - ground;
	float a = swell_m * (0.5 + 1.3 * wind_strength) * smoothstep(0.3, 6.0, depth);
	vec3 disp = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	vec2 d0 = wind_direction;
	vec2 s0 = vec2(-d0.y, d0.x);
	// Six swells from spread directions and lengths, each rising and fading in drifting
	// patches (wave groups) so the sea never shows a regular, repeating pattern.
	vec2 gp = wp.xz - d0 * TIME * 3.0;
	float g1 = 0.3 + 1.4 * env_noise(gp * 0.0035 + vec2(3.1, 7.2));
	float g2 = 0.3 + 1.4 * env_noise(gp * 0.005 + vec2(9.4, 1.3));
	float g3 = 0.3 + 1.4 * env_noise(gp * 0.008 + vec2(5.7, 4.6));
	gerstner(wp.xz, d0, 67.0, a * 0.75 * g1, 0.5, TIME, disp, n);
	gerstner(wp.xz, normalize(d0 + s0 * 0.42), 41.0, a * 0.5 * g2, 0.5, TIME, disp, n);
	gerstner(wp.xz, normalize(d0 - s0 * 0.58), 29.0, a * 0.35 * g3, 0.45, TIME, disp, n);
	gerstner(wp.xz, normalize(d0 + s0 * 1.1), 19.0, a * 0.2 * g1, 0.4, TIME * 1.07, disp, n);
	gerstner(wp.xz, normalize(d0 - s0 * 0.21), 13.0, a * 0.14 * g2, 0.4, TIME * 0.93, disp, n);
	gerstner(wp.xz, normalize(-d0 * 0.3 + s0), 9.0, a * 0.08 * g3, 0.35, TIME * 1.11, disp, n);
	// Breakers: the swell lifts as it reaches the shallows along the lines the surf foam
	// draws, then collapses onto the beach.
	if (surf_k > 0.0 && depth > -0.5 && depth < 7.0) {
		float ph = TIME / surf_t + env_noise(wp.xz * 0.004) * 0.8;
		for (int k = 0; k < 2; k++) {
			float c = fract(ph + float(k) * 0.5);
			float front = mix(5.0, -0.2, c * c * (3.0 - 2.0 * c));
			float bump = exp(-pow((depth - front) / 0.8, 2.0)) * (1.0 - smoothstep(0.6, 0.95, c));
			// Breakers come in uneven along the shore: bigger here, barely there.
			bump *= 0.3 + 1.3 * env_noise(wp.xz * 0.018 + vec2(float(k) * 3.7, TIME * 0.02));
			// No lift in the last metre of water: the 5 m sea mesh would ride up over the
			// sand in flat, straight-edged facets. The foam draws the swash there instead.
			disp.y += bump * 0.55 * surf_k * smoothstep(0.4, 1.8, depth);
		}
	}
	// No heave in the last metre and a half of water either, where it would ride up the beach.
	off.y -= base_y * (1.0 - smoothstep(0.2, 1.5, depth));
	off += disp * still;
	nrm = normalize(n);
	return off;
}
