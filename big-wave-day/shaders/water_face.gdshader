// Wave face water and whitewater. The mesh travels with the break so the pocket builds up down the
// line, but the water itself must not move with it: every pattern here is sampled from WORLD position,
// so the rider visibly slides over the surface while only the shape changes underneath.
// Vertex colour: r = foam on the outside of the surface, g = fold (the tube ceiling), b = lip tip,
// a = height fraction on the face (0 trough, 1 lip).
shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.15, 0.45, 0.75, 1.0);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float noise_scale = 0.1;        // world metres -> texture tiles (0.1 = one tile per 10 m)
uniform float noise_dark = 0.72;        // darkest the water noise gets (1 = no noise)
uniform vec2 water_scroll = vec2(0.0, -0.06); // pattern drift per second: water draws up the face
uniform vec2 foam_scroll = vec2(0.5, 0.35);   // whitewater churns faster
uniform float band_length = 5.0;        // alternating shade every N metres along the wave (debug aid)
uniform float band_shade = 1.0;
uniform float roughness_value = 0.18;
uniform float specular_value = 0.7;
uniform vec3 tube_tint : source_color = vec3(0.4, 0.7, 0.72); // multiplier for water seen inside the barrel
uniform float interior_foam = 0.12;      // how much of the outside foam shows through on the tube ceiling
uniform float chop_scale = 0.14;         // world metres -> chop tiles; smaller = bigger ripples (0.14 = ~7 m tiles)
uniform float chop_strength = 0.22;      // how much the chop bends the normal; keep subtle or it reads as static
uniform float chop_near = 12.0;          // chop at full strength closer than this (metres from the camera)...
uniform float chop_far = 45.0;           // ...and gone beyond this, so distant water does not sparkle into noise
uniform float lip_streaks = 0.45;        // foam feathering down from the lip, 0 = off
uniform float lip_streak_start = 0.72;   // height fraction where streaks begin

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// x runs along the wave; y - z runs up the face (the face rises in +y and -z), and stays continuous on the flats.
	vec2 base_uv = vec2(world_pos.x, world_pos.y - world_pos.z) * noise_scale;
	float n = texture(noise_tex, base_uv + water_scroll * TIME).r;
	float shade = mix(noise_dark, 1.0, n);
	float band = mod(floor(world_pos.x / band_length), 2.0) < 0.5 ? 1.0 : band_shade;
	vec3 water = base_color.rgb * shade * band;

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
