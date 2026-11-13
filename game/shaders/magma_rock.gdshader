shader_type spatial;
// Dark basalt with glowing cracks, for the lava troll hand.
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float n = noise(lp * 4.0) * 0.6 + noise(lp * 9.0) * 0.4;
	float crack = 1.0 - smoothstep(0.0, 0.07, abs(n - 0.5));
	ALBEDO = mix(vec3(0.05, 0.03, 0.03), vec3(0.12, 0.06, 0.05), n);
	ROUGHNESS = 0.9;
	EMISSION = vec3(1.0, 0.38, 0.05) * crack * 3.5 + vec3(0.6, 0.15, 0.02) * (1.0 - smoothstep(-1.6, 0.2, lp.y)) * 1.5;
}
