// Shared environment state, driven by scripts/env/atmosphere.gd through global shader
// parameters (declared in project.godot under [shader_globals]).
// Terrain, rivers, trees and the cloud layer all read the same values, so cloud shadows
// line up with the clouds, and wind moves trees, water and clouds together.

global uniform vec2 wind_direction;       // unit vector in the xz plane
global uniform float wind_strength;       // 0 calm .. 1 storm
global uniform float wind_time;           // phase that runs faster in stronger wind
global uniform vec2 cloud_offset;         // how far the clouds have drifted, metres
global uniform float cloud_coverage;      // 0 clear .. 1 overcast
global uniform float cloud_height;        // world y of the cloud layer
global uniform float cloud_scale;         // noise frequency, 1/metres
global uniform float cloud_shadow_strength;
global uniform vec3 sun_direction;        // unit vector pointing towards the sun
global uniform float wetness;             // 0 dry .. 1 soaked (follows rain)

// Integer hash of a lattice point (p must hold whole numbers). Exact integer maths, so every
// cell sharing a corner gets the same value; float hashes break into seams on some GPUs.
float env_hash(vec2 p) {
	ivec2 i = ivec2(p);
	uint h = uint(i.x) * 1597334677u ^ uint(i.y) * 3812015801u;
	h ^= h >> 16u;
	h *= 2146121005u;
	h ^= h >> 15u;
	h *= 2221713035u;
	h ^= h >> 16u;
	return float(h) * (1.0 / 4294967295.0);
}

float env_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = env_hash(i);
	float b = env_hash(i + vec2(1.0, 0.0));
	float c = env_hash(i + vec2(0.0, 1.0));
	float d = env_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float env_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * env_noise(p);
		p = rot * p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v / 0.96875;
}

// Cloud density (0..1) at a point on the cloud layer.
float cloud_density(vec2 xz) {
	float n = env_fbm((xz - cloud_offset) * cloud_scale);
	float lo = 1.0 - cloud_coverage;
	return smoothstep(lo - 0.05, lo + 0.25, n);
}

// Light multiplier from cloud shadows at a world position (1 = full sun).
float cloud_shadow(vec3 world_pos) {
	vec3 l = sun_direction;
	if (l.y < 0.02) {
		return 1.0;
	}
	float t = max(cloud_height - world_pos.y, 0.0) / l.y;
	vec2 xz = world_pos.xz + l.xz * t;
	float fade = smoothstep(0.02, 0.2, l.y);
	return 1.0 - cloud_shadow_strength * cloud_density(xz) * fade;
}
