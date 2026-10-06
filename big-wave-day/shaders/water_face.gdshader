// Wave face water and whitewater. The mesh travels with the break so the pocket builds up down the
// line, but the water itself must not move with it: every pattern here is sampled from WORLD position,
// so the rider visibly slides over the surface while only the shape changes underneath.
// Vertex colour: r = foam on the outside of the surface, g = fold (the tube ceiling), b = lip tip,
// a = height fraction on the face (0 trough, 1 lip).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/water_common.gdshaderinc"

uniform vec2 foam_scroll = vec2(0.5, 0.35);   // whitewater churns faster
uniform float band_length = 5.0;        // alternating shade every N metres along the wave (debug aid)
uniform float band_shade = 1.0;
uniform vec3 tube_tint : source_color = vec3(0.4, 0.7, 0.72); // multiplier for water seen inside the barrel
uniform float interior_foam = 0.12;      // how much of the outside foam shows through on the tube ceiling
uniform float lip_streaks = 0.45;        // foam feathering down from the lip, 0 = off
uniform float lip_streak_start = 0.72;   // height fraction where streaks begin

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = wave_size_at(wp.x);
	// The face and the curl shrink with the wave. The trough row (y == 0) stays on the waterline.
	VERTEX.y *= s;
	VERTEX.z *= s;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 base_uv = water_uv(world_pos);
	float n = texture(noise_tex, base_uv + water_scroll * TIME).r;
	float shade = mix(noise_dark, 1.0, n);
	float band = mod(floor(world_pos.x / band_length), 2.0) < 0.5 ? 1.0 : band_shade;
	vec3 water = water_color(world_pos, shade * band, 1.0);

	// Chop: a world-anchored, slowly drifting height field bends the normal so the face catches light
	// in ripples instead of reading as one flat sheet.
	float chop = texture(noise_tex, base_uv * (chop_scale / noise_scale) + vec2(0.03, -0.11) * TIME).r
	           + 0.5 * texture(noise_tex, base_uv * (chop_scale * 2.3 / noise_scale) + vec2(-0.05, 0.07) * TIME).r;
	// Fade the bump with distance and at grazing angles, where screen-space slopes explode into speckle.
	float chop_fade = (1.0 - smoothstep(chop_near, chop_far, length(VERTEX))) * smoothstep(0.08, 0.35, abs(dot(NORMAL, VIEW)))
		* (1.0 - smoothstep(0.88, 0.97, COLOR.a));   // and not on the lip itself, where the surface folds over
	vec2 slope = clamp(vec2(dFdx(chop), dFdy(chop)), vec2(-0.04), vec2(0.04));   // bounded: no single pixel can flip the normal
	vec3 bumped = normalize(NORMAL - vec3(slope, 0.0) * chop_strength * 12.0 * chop_fade);

	float churn = texture(noise_tex, base_uv * 2.0 + foam_scroll * TIME).r;
	vec3 foam_col = vec3(1.0) * mix(0.78, 1.0, churn);
	float fold = clamp(COLOR.g, 0.0, 1.0);
	float tip = clamp(COLOR.b, 0.0, 1.0);
	float foam = clamp(COLOR.r, 0.0, 1.0);
	float h = COLOR.a;

	// Foam streaks feathering down from the lip: stretched along the face, world-anchored.
	float streak_n = texture(noise_tex, vec2(world_pos.x * 0.9, (world_pos.y - world_pos.z) * 0.06) * 0.5 + vec2(0.0, -0.02) * TIME).r;
	float streak = smoothstep(0.55, 0.95, streak_n) * smoothstep(lip_streak_start, 1.0, h) * lip_streaks;
	foam = max(foam, streak);

	if (FRONT_FACING) {
		// Inside the tube: glassy, darker, only the tip is white.
		water = mix(water, water * tube_tint, fold);
		foam = mix(foam, max(foam * interior_foam, tip), fold);
	}

	ALBEDO = mix(water, foam_col, foam);
	NORMAL = mix(bumped, NORMAL, foam);
	ROUGHNESS = mix(roughness_value, 0.9, foam);
	SPECULAR = mix(specular_value, 0.3, foam);
	// No manual normal flip: with cull_disabled Godot already flips NORMAL on back faces before this runs.
}
