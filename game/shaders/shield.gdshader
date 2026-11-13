shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
// Energy shield bubble: transparent centre, bright cyan fresnel rim with a gentle pulse.

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - clamp(ndv, 0.0, 1.0), 2.2);
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0 + VERTEX.y * 4.0);
	ALBEDO = vec3(0.25, 0.82, 1.0) * (0.06 + rim * 1.45) * pulse;
	ALPHA = 1.0;
}
