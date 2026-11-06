shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Goal beacon: a column of light fading out with height.

uniform vec3 color : source_color = vec3(0.3, 1.0, 0.5);
uniform float height = 1.0;

varying float up;

void vertex() {
	up = VERTEX.y / height + 0.5;
}

void fragment() {
	ALBEDO = color;
	ALPHA = pow(1.0 - up, 2.0) * 0.6 * (0.8 + 0.2 * sin(TIME * 3.0));
}
