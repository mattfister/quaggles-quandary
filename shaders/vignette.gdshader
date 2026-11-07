shader_type canvas_item;
// Darkens the screen's edges toward a deep blue to frame the level.

uniform vec3 color : source_color = vec3(0.08, 0.18, 0.42);
uniform float strength = 0.4;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(0.35, 0.95, length(p));
	COLOR = vec4(color, v * strength);
}
