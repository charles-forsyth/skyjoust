shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
// Inverted-hull outline for the generated riders (readability against the bright sky).
uniform vec4 color : source_color = vec4(0.08, 0.04, 0.08, 1.0);
uniform float width = 0.025;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = color.rgb;
}
