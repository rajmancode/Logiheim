// Settlement buildings (scripts/game/building_models.gd): vertex-coloured, with faces marked by
// vertex alpha ~0 painted in the owner's colour. Wood, turf, thatch and stone get grain from
// world-space noise so the flat colours read as material.
//
// Construction: everything above `build` x height is cut away, with a ragged line of fresh,
// pale timber glowing faintly at the cut - the building rises from the ground as it is raised.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/environment.gdshaderinc"

uniform vec3 team_color : source_color = vec3(0.8, 0.2, 0.2);
uniform float build = 1.0;
uniform float height = 8.0;
uniform float flash = 0.0;     // brief highlight (selected, just finished)

varying float v_y;
varying vec3 v_world;

void vertex() {
	v_y = VERTEX.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Rising from the ground while being built (the plinth below ground is always there).
	float cut = build * (height + 0.4);
	float jag = (env_noise(v_world.xz * 1.7) - 0.5) * 0.5;
	if (build < 1.0 && v_y > cut + jag) {
		discard;
	}
	// (The kit's colours are written in sRGB, like the rest of the palette.)
	vec3 col = COLOR.a < 0.25 ? team_color : pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// Material grain: fine streaks along the timber, lumpy turf and thatch, speckled stone.
	float g1 = env_noise(v_world.xz * vec2(0.6, 6.0) + v_world.y * 3.0);
	float g2 = env_noise(v_world.xz * 3.1 + vec2(v_world.y * 2.3, 0.0));
	float green = smoothstep(0.05, 0.12, col.g - col.r);
	col *= 0.86 + 0.24 * mix(g1, g2, 0.5 + 0.5 * green);
	// Fresh timber at the line where the building is going up.
	float fresh = (build < 1.0) ? smoothstep(0.6, 0.0, abs(v_y - cut - jag)) : 0.0;
	col = mix(col, vec3(0.86, 0.7, 0.45), fresh * 0.8);
	col *= cloud_shadow(v_world);
	ALBEDO = col * (1.0 - 0.25 * wetness);
	ROUGHNESS = mix(0.85, 0.55, wetness);
	EMISSION = vec3(1.0, 0.75, 0.4) * (fresh * 0.25 + flash * 0.35);
}
