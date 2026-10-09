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
uniform float lump_foam = 0.25;          // metres of surface lumps on the whitewater (never ridden)
uniform float lump_lip = 0.22;           // metres of lumps on the folding lip and the back of the wave
uniform float lump_scale = 0.3;          // world metres -> lump tiles (0.3 = one lump every ~3 m)
uniform vec3 deep_tint : source_color = vec3(0.7, 0.82, 0.95); // the base of the face, darker and bluer than the top
uniform float deep_height = 0.55;        // height fraction where the base colour has faded out
uniform vec3 lip_glow_color : source_color = vec3(0.3, 0.95, 0.8); // sunlight through the thin top of the wave
uniform float lip_glow = 0.6;            // strength of that glow, 0 = off
uniform float foam_glow = 0.3;           // whitewater lights itself a little, so it stays white in shadow instead of going grey
uniform float lip_glow_start = 0.6;      // height fraction where the glow begins

varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = wave_size_at(wp.x);
	// The face and the curl shrink with the wave. The trough row (y == 0) stays on the waterline.
	VERTEX.y *= s;
	VERTEX.z *= s;
	// Lumps along the normal, world-anchored and slowly churning: on the whitewater, the folding lip and the
	// back of the wave. The ridden face (h <= 1, little foam) stays exactly where the sim thinks it is.
	float on_foam = smoothstep(0.7, 1.0, COLOR.r);
	float on_lip = smoothstep(1.05, 1.3, COLOR.a + COLOR.g * 0.5) * COLOR.g;   // the curl: g marks it, a saturates at 1
	float on_back = (COLOR.g < 0.001 && COLOR.r < 0.7 && VERTEX.z < -0.5) ? 1.0 : 0.0;   // back strip: no fold flag, behind the face
	float amp = max(lump_foam * on_foam, lump_lip * max(on_lip, on_back));
	if (amp > 0.0) {
		vec3 wp2 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float ln = texture(noise_tex, wp2.xz * lump_scale * noise_scale * 10.0 + vec2(0.05, 0.08) * TIME).r
		         + 0.5 * texture(noise_tex, wp2.xy * lump_scale * noise_scale * 23.0 + vec2(-0.07, 0.04) * TIME).r - 0.75;
		VERTEX += NORMAL * ln * amp * s;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 base_uv = water_uv(world_pos);
	float n = texture(noise_tex, base_uv + water_scroll * TIME).r;
	float shade = mix(noise_dark, 1.0, n);
	float band = mod(floor(world_pos.x / band_length), 2.0) < 0.5 ? 1.0 : band_shade;
	vec3 water = water_color(world_pos, shade * band, 1.0);
	// Deep, darker water at the base of the face; the top is thin and lit through.
	water *= mix(deep_tint, vec3(1.0), smoothstep(0.0, deep_height, COLOR.a));

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
	float churn_fine = texture(noise_tex, base_uv * 7.0 + foam_scroll * 1.7 * TIME).r;   // boils inside the pile
	vec3 foam_col = vec3(1.0) * mix(0.78, 1.0, churn) * mix(0.8, 1.0, churn_fine);
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

	// Sunlight through the top of the wave: a turquoise glow that strengthens toward the lip, on the lip
	// tongue, and at grazing angles where the water is seen edge-on and thin.
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float thin = max(smoothstep(lip_glow_start, 1.0, h), fold * 0.8);
	float glow = lip_glow * thin * (0.45 + 0.55 * rim) * (1.0 - foam);
	ALBEDO = mix(water, foam_col, foam);
	EMISSION = lip_glow_color * glow + foam_col * foam * foam_glow;
	NORMAL = mix(bumped, NORMAL, foam);
	ROUGHNESS = mix(roughness_value, 0.9, foam);
	SPECULAR = mix(specular_value, 0.3, foam);
	// No manual normal flip: with cull_disabled Godot already flips NORMAL on back faces before this runs.
}
