// Borders draped on the ground (scripts/map/border_ribbon.gd). UV.x runs across the ribbon from
// its outer edge (0) to its inner edge (1); UV2.x is where the border line itself lies across
// it, UV2.y the ribbon's width in metres; UV.y is metres along. COLOR is the region's colour.
//
// style 0, a settlement's land: a dark inked rim either side of a bright line in the owner's
//   colour, a glint running slowly along it, a stitched line a little inside, and a soft wash
//   of colour fading into the land.
// style 1, a resource deposit: a finer dashed line in the resource's colour with a dark
//   edge and a faint glow inward.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform int style = 0;
uniform float strength = 1.0;

varying float v_line;
varying float v_width;
varying vec3 v_world;

void vertex() {
	v_line = UV2.x;
	v_width = UV2.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance from the border line in metres: negative outside, positive inside.
	float m = (UV.x - v_line) * v_width;
	float along = UV.y;
	vec3 col = COLOR.rgb;
	vec3 ink = vec3(0.04, 0.03, 0.02);
	vec3 outc;
	float a;
	// Lines keep a readable width on screen: wider in metres the further away they are seen.
	float px = length(CAMERA_POSITION_WORLD - v_world) * 0.0016;
	if (style == 0) {
		float w = max(0.45, px * 1.6);
		float core = 1.0 - smoothstep(w * 0.55, w, abs(m));
		float rim = 1.0 - smoothstep(w * 1.3, w * 1.9, abs(m));
		float glint = pow(0.5 + 0.5 * sin(along * 0.05 - TIME * 1.2), 24.0);
		float sd = w * 2.6 + 0.6;
		float stitch_band = 1.0 - smoothstep(w * 0.18, w * 0.35, abs(m - sd));
		// Fixed spacings along the ground, so nothing crawls along the line as the camera zooms.
		float stitch = stitch_band * step(0.45, fract(along / 3.0));
		float reach = max(v_width * (1.0 - v_line) - w, 0.1);
		float wash = smoothstep(w, w * 2.0, m) * pow(clamp(1.0 - (m - w) / reach, 0.0, 1.0), 1.3) * 0.42;
		vec3 bright = mix(col * 1.2, vec3(1.0, 0.96, 0.85), 0.2 + 0.55 * glint);
		outc = mix(col, ink, rim);
		outc = mix(outc, bright, core);
		outc = mix(outc, mix(col, vec3(1.0), 0.4), stitch * (1.0 - rim));
		a = max(max(rim * 0.9, core), max(stitch * 0.85, wash));
	} else {
		float w = max(0.22, px * 0.9);
		float core = 1.0 - smoothstep(w * 0.5, w, abs(m));
		float rim = 1.0 - smoothstep(w * 1.4, w * 2.1, abs(m));
		float period = 6.0;
		float dash = smoothstep(0.0, 0.08, fract(along / period)) * smoothstep(0.72, 0.62, fract(along / period));
		float reach = max(v_width * (1.0 - v_line) - w, 0.1);
		float glow = smoothstep(w, w * 2.5, m) * pow(clamp(1.0 - (m - w) / reach, 0.0, 1.0), 2.0) * 0.3;
		outc = mix(col, ink, rim * 0.8);
		outc = mix(outc, col * 1.2 + 0.1, core * dash);
		a = max(rim * 0.6 * dash, max(core * dash, glow));
	}
	ALBEDO = outc;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
