// The open ocean around the wave. Same water as the face (see water_common.gdshaderinc), so there is no
// seam where they meet. Transparent so the shallows can show the seabed; drawn before other transparent
// things (render_priority set from wave.gd) so spray and wake always sit on top of it.
shader_type spatial;
render_mode blend_mix, cull_back;

#include "res://shaders/water_common.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 base_uv = water_uv(world_pos);
	float n = texture(noise_tex, base_uv + water_scroll * TIME).r;
	float shade = mix(noise_dark, 1.0, n);
	float sh = shallow_mask(world_pos);

	float chop = texture(noise_tex, base_uv * (chop_scale / noise_scale) + vec2(0.03, -0.11) * TIME).r
	           + 0.5 * texture(noise_tex, base_uv * (chop_scale * 2.3 / noise_scale) + vec2(-0.05, 0.07) * TIME).r;
	float chop_fade = (1.0 - smoothstep(chop_near, chop_far, length(VERTEX))) * smoothstep(0.08, 0.35, abs(dot(NORMAL, VIEW)));
	vec2 slope = clamp(vec2(dFdx(chop), dFdy(chop)), vec2(-0.04), vec2(0.04));

	ALBEDO = water_color(world_pos, shade, 0.0);
	NORMAL = normalize(NORMAL - vec3(slope, 0.0) * chop_strength * 12.0 * chop_fade);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	ALPHA = mix(1.0, shallow_alpha, sh);
}
