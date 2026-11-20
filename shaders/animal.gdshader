// Animals (assets/models/animals, built by tools/blender/make_animals.py).
// Colour is the painted coat in the vertex colours, tinted per animal (INSTANCE_CUSTOM.rgb).
// UV2 holds animation weights: x = how much a vertex follows the head, y = tail weight (for
// the whale: position along the body). Each animal runs its own little routine from a
// per-instance phase: lower the head and graze (with chewing), raise it, look around; tails
// swish; whales swim with a slow body wave. Pivots come from animals.json.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 neck_pivot = vec3(0.5, 0.6, 0.0);
uniform vec3 tail_pivot = vec3(-0.6, 0.6, 0.0);
uniform float head_down = 1.1;     // radians the head drops to graze (negative = raises)
uniform float tail_swish = 0.35;
uniform int mode = 0;              // 0 land animal, 1 whale
uniform float body_length = 1.0;

varying vec3 v_world_pos;
varying vec3 v_color;

vec3 rot_z(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

vec3 rot_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 200.0;
	float t = TIME + phase;
	float hw = UV2.x;
	float tw = UV2.y;
	if (mode == 1) {
		// Whale: a slow wave runs down the body, strongest at the flukes.
		float wave = sin(t * 0.7 - tw * 3.2) * 0.45 * tw * tw;
		VERTEX.y += wave;
	} else {
		// Routine: graze (head down, chewing) most of the time, now and then look up and around.
		float cycle = sin(t * 0.19) * 0.6 + sin(t * 0.47 + 1.3) * 0.4;
		float graze = smoothstep(-0.25, 0.25, cycle);
		float look = sin(t * 0.33) * (1.0 - graze) * 0.6;
		if (hw > 0.0) {
			float a = -graze * head_down * hw + sin(t * 4.5) * 0.04 * graze * hw;
			vec3 p = VERTEX - neck_pivot;
			p = rot_z(p, a);
			p = rot_y(p, look * hw);
			VERTEX = neck_pivot + p;
			NORMAL = rot_y(rot_z(NORMAL, a), look * hw);
		}
		if (tw > 0.0) {
			float swish = (sin(t * 2.1) + 0.5 * sin(t * 5.3)) * tail_swish * tw;
			vec3 p = rot_y(VERTEX - tail_pivot, swish);
			VERTEX = tail_pivot + p;
		}
		// Breathing.
		VERTEX += NORMAL * sin(t * 1.7) * 0.004 * body_length * (1.0 - hw) * (1.0 - tw);
	}
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR.rgb * INSTANCE_CUSTOM.rgb;
}

void fragment() {
	// Fine fur variation so coats aren't flat colour.
	float fur = 0.9 + 0.2 * env_noise(v_world_pos.xz * 40.0 + v_world_pos.y * 30.0);
	vec3 col = v_color * fur * cloud_shadow(v_world_pos) * (1.0 - 0.3 * wetness);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.4, wetness);
	SPECULAR = 0.3;
	// Soft sheen at grazing angles, like light catching fur.
	RIM = 0.35;
	RIM_TINT = 0.6;
}
