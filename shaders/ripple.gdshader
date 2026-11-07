shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Rings spreading out on the water around a swimmer. `strength` fades them
// in and out as the quaggle starts and stops swimming.

uniform float strength = 0.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 0.0;
	for (int k = 0; k < 3; k++) {
		float ph = fract(TIME * 0.55 + float(k) / 3.0);
		float radius = 0.3 + 0.65 * ph;
		a += smoothstep(0.06, 0.0, abs(r - radius)) * (1.0 - ph);
	}
	ALBEDO = vec3(0.92, 0.98, 1.0);
	ALPHA = clamp(a, 0.0, 1.0) * 0.75 * strength;
}
