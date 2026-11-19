// Hex grid lines and hover/selection highlights, computed per pixel.
// Matches scripts/map/border_noise.gd exactly: a point belongs to the hex at
// p + offset(p), where offset is integer-hash value noise. Needs environment.gdshaderinc first.

uniform float grid_hex_size = 20.0;
uniform vec2 grid_origin = vec2(0.0);       // world xz of axial (0, 0)
uniform float grid_noise_amp = 0.0;         // metres
uniform float grid_noise_freq = 0.05;       // 1/metres
uniform bool show_grid = true;
uniform float grid_line_width = 0.035;      // fraction of the hex size
uniform float grid_strength = 0.28;
uniform vec4 hover_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec3 hover_cell = vec3(0.0, 0.0, 0.0);   // q, r, enabled (1)
uniform vec4 select_color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec3 select_cell = vec3(0.0, 0.0, 0.0);

vec2 grid_offset(vec2 p) {
	if (grid_noise_amp <= 0.0) {
		return vec2(0.0);
	}
	vec2 q = p * grid_noise_freq;
	vec2 o = vec2(env_noise(q + vec2(13.7, 4.1)), env_noise(q + vec2(-7.3, 21.9)));
	vec2 q2 = q * 2.3;
	o += vec2(env_noise(q2 + vec2(3.1, -9.4)), env_noise(q2 + vec2(17.2, 5.6))) * 0.35;
	return (o / 1.35 * 2.0 - 1.0) * grid_noise_amp;
}

// Returns (q, r, v): the axial cell and v = 0 at its centre .. 1 on its border.
vec3 hex_cell(vec2 world_xz) {
	vec2 p = world_xz + grid_offset(world_xz) - grid_origin;
	float qf = (0.57735027 * p.x - p.y / 3.0) / grid_hex_size;
	float rf = (0.66666667 * p.y) / grid_hex_size;
	float sf = -qf - rf;
	float q = round(qf);
	float r = round(rf);
	float s = round(sf);
	float dq = abs(q - qf);
	float dr = abs(r - rf);
	float ds = abs(s - sf);
	if (dq > dr && dq > ds) {
		q = -r - s;
	} else if (dr > ds) {
		r = -q - s;
	}
	vec2 c = vec2(grid_hex_size * 1.7320508 * (q + r * 0.5), grid_hex_size * 1.5 * r);
	vec2 d = abs(p - c);
	float v = max(d.x, 0.5 * d.x + 0.8660254 * d.y) / (0.8660254 * grid_hex_size);
	return vec3(q, r, v);
}

// Applies grid lines and highlights to a colour. Returns the emission to add.
vec3 apply_hex_grid(inout vec3 albedo, vec2 world_xz, float grid_fade) {
	vec3 cell = hex_cell(world_xz);
	float aa = max(fwidth(cell.z), 1e-4);
	if (show_grid) {
		float line = smoothstep(1.0 - grid_line_width - aa, 1.0 - grid_line_width + aa, cell.z);
		albedo *= 1.0 - line * grid_strength * grid_fade;
	}
	vec3 emission = vec3(0.0);
	if (hover_cell.z > 0.5 && all(equal(cell.xy, hover_cell.xy))) {
		float rim = smoothstep(0.8, 0.95, cell.z);
		albedo = mix(albedo, hover_color.rgb, 0.18 + 0.5 * rim);
		emission += hover_color.rgb * (0.08 + 0.4 * rim);
	}
	if (select_cell.z > 0.5 && all(equal(cell.xy, select_cell.xy))) {
		float rim = smoothstep(0.8, 0.95, cell.z);
		albedo = mix(albedo, select_color.rgb, 0.18 + 0.5 * rim);
		emission += select_color.rgb * (0.08 + 0.4 * rim);
	}
	return emission;
}
