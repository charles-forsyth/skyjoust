shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec3 tint = vec3(1.0);
uniform vec3 haze : source_color = vec3(1.0, 0.62, 0.36);
// Stylized lava: dark crust plates drifting over a hot red-orange melt with white-hot seams.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.6 + TIME * 1.3) * 0.12;
}

void fragment() {
	vec2 p = UV * vec2(24.0, 4.0);
	float n = fbm(p + vec2(TIME * 0.10, TIME * 0.04));
	float n2 = fbm(p * 1.9 - vec2(TIME * 0.07, 0.0) + n * 1.5);
	float plates = smoothstep(0.40, 0.52, n);          // dark cooled crust covers most of it
	float seam = 1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5));
	vec3 melt = mix(vec3(0.62, 0.05, 0.02), vec3(0.85, 0.22, 0.03), n2);
	vec3 crust = vec3(0.09, 0.025, 0.02);
	vec3 c = mix(melt, crust, plates * 0.92);
	c += vec3(0.95, 0.42, 0.06) * seam * (1.0 - plates * 0.5);
	c *= 0.9 + 0.1 * sin(TIME * 2.0 + p.x * 0.7);
	c *= tint;
	ALBEDO = c;
	// atmospheric fade: far lava melts into the warm horizon haze, then goes transparent
	float dist = length(VERTEX);
	float f = smoothstep(32.0, 62.0, dist);
	ALBEDO = mix(c, haze, f);
	ALPHA = 1.0 - smoothstep(55.0, 70.0, dist);
}
