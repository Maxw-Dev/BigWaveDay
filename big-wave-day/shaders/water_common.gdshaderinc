// Shared by the wave face and the open ocean, so the two are one continuous body of water:
// same colour model, same world-anchored noise, same ripples. Change water here, not in either shader.

uniform vec4 base_color : source_color = vec4(0.15, 0.45, 0.75, 1.0);   // lifted water: the face and right in front of it
uniform vec4 ocean_color : source_color = vec4(0.05, 0.22, 0.42, 1.0);  // open, deep water
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float noise_scale = 0.1;        // world metres -> texture tiles (0.1 = one tile per 10 m)
uniform float noise_dark = 0.72;        // darkest the water noise gets (1 = no noise)
uniform vec2 water_scroll = vec2(0.0, -0.06); // pattern drift per second
uniform float roughness_value = 0.18;
uniform float specular_value = 0.7;
uniform float chop_scale = 0.14;         // world metres -> chop tiles; smaller = bigger ripples (0.14 = ~7 m tiles)
uniform float chop_strength = 0.22;      // how much the chop bends the normal; keep subtle or it reads as static
uniform float chop_near = 12.0;          // chop at full strength closer than this (metres from the camera)...
uniform float chop_far = 45.0;           // ...and gone beyond this, so distant water does not sparkle into noise

// Wave size: amplitude (the wave dying over time) times a taper toward end_u (the wave line running out).
// Must match Wave.size_at() in wave.gd, which the surfer and camera use.
uniform float amplitude = 1.0;
uniform float end_u = 1000000.0;
uniform float taper_len = 150.0;
uniform float wave_dir = 1.0;
uniform float min_size = 0.04;

// Shallows around the home island and where the wave runs out: turquoise, see-through, seabed visible below.
uniform vec3 shallow_center = vec3(0.0, 0.0, 1000000.0);
uniform vec2 shallow_radius = vec2(110.0, 115.0);
uniform vec4 shallow_color : source_color = vec4(0.15, 0.64, 0.7, 1.0);
uniform float shallow_alpha = 0.5;       // opacity of the water at the heart of the shallows

float wave_size_at(float world_x) {
	float taper = 1.0 - smoothstep(end_u - taper_len, end_u, world_x * wave_dir);
	return max(amplitude * taper, min_size);
}

float shallow_mask(vec3 wp) {
	vec2 d = (wp.xz - shallow_center.xz) / shallow_radius;
	return 1.0 - smoothstep(0.55, 1.0, length(d));
}

vec2 water_uv(vec3 wp) {
	// x runs along the wave; y - z runs up the face and continues across the flat water.
	return vec2(wp.x, wp.y - wp.z) * noise_scale;
}

vec3 water_color(vec3 wp, float shade, float on_face) {
	// Lifted water is lighter, the open ocean is deep; both fade toward deep as the wave dies.
	float near_wave = 1.0 - smoothstep(4.0, 30.0, abs(wp.z));
	float light = max(on_face, near_wave) * wave_size_at(wp.x);
	vec3 c = mix(ocean_color.rgb, base_color.rgb, light) * shade;
	return mix(c, shallow_color.rgb * mix(0.88, 1.06, shade), shallow_mask(wp) * (1.0 - on_face * 0.4));
}
