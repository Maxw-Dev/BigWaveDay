// Wave face water and whitewater. The mesh travels with the break so the pocket builds up down the
// line, but the water itself must not move with it: every pattern here is sampled from WORLD position,
// so the rider visibly slides over the surface while only the shape changes underneath.
// Vertex colour: r = foam on the outside of the surface, g = fold (the tube ceiling), b = lip tip.
// The tube's interior (front faces of the fold) stays glassy and dark so lip, tube and whitewater read apart.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.15, 0.45, 0.75, 1.0);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear;
uniform float noise_scale = 0.1;        // world metres -> texture tiles (0.1 = one tile per 10 m)
uniform float noise_dark = 0.72;        // darkest the water noise gets (1 = no noise)
uniform vec2 water_scroll = vec2(0.0, -0.06); // pattern drift per second: water draws up the face
uniform vec2 foam_scroll = vec2(0.5, 0.35);   // whitewater churns faster
uniform float band_length = 5.0;        // alternating shade every N metres along the wave
uniform float band_shade = 0.85;
uniform float roughness_value = 0.18;
uniform float specular_value = 0.7;
uniform vec3 tube_tint : source_color = vec3(0.4, 0.7, 0.72); // multiplier for water seen inside the barrel
uniform float interior_foam = 0.12;      // how much of the outside foam shows through on the tube ceiling

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

	float churn = texture(noise_tex, base_uv * 2.0 + foam_scroll * TIME).r;
	vec3 foam_col = vec3(1.0) * mix(0.78, 1.0, churn);
	float fold = clamp(COLOR.g, 0.0, 1.0);
	float tip = clamp(COLOR.b, 0.0, 1.0);
	float foam = clamp(COLOR.r, 0.0, 1.0);
	if (FRONT_FACING) {
		// Inside the tube: glassy, darker, only the tip is white.
		water = mix(water, water * tube_tint, fold);
		foam = mix(foam, max(foam * interior_foam, tip), fold);
	}

	ALBEDO = mix(water, foam_col, foam);
	ROUGHNESS = mix(roughness_value, 0.9, foam);
	SPECULAR = mix(specular_value, 0.3, foam);
	// No manual normal flip: with cull_disabled Godot already flips NORMAL on back faces before this runs.
}
