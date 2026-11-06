shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Force field: same colour cycle as the original drawForceField.

uniform vec3 tint : source_color = vec3(1.0);
uniform float cycle = 1.0;

void fragment() {
	float t = TIME * 3.0;
	vec3 pulse = vec3(0.5 + 0.5 * cos(t), 0.1, 0.5 + 0.5 * sin(t));
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bands = 0.5 + 0.5 * sin(world.y * 18.0 - TIME * 4.0);
	ALBEDO = mix(tint, pulse, cycle) * (0.8 + 0.6 * bands);
	ALPHA = 0.3 + 0.25 * bands;
}
