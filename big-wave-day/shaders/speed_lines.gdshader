// Full-screen speed lines: thin white rays streaming outward from the centre, only near the edges.
// `strength` 0..1 is driven by the surfer's speed.
shader_type canvas_item;

uniform float strength = 0.0;
uniform float rays = 70.0;
uniform float flow = 2.5;

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.78;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float seg = floor((a + 3.14159) * rays / 6.28318);
	float rnd = hash1(seg * 17.3);
	float rnd2 = hash1(seg * 31.7 + 7.0);
	float within = fract((a + 3.14159) * rays / 6.28318);
	float ray = 1.0 - smoothstep(0.0, 0.18 + 0.12 * rnd, abs(within - 0.5));
	float along = r * 2.5 - TIME * flow * (0.8 + rnd);
	float streak = smoothstep(0.55, 1.0, fract(along + rnd2));
	float edge = smoothstep(0.28, 0.85, r);
	float alpha = strength * edge * ray * streak * (0.35 + 0.65 * rnd);
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
