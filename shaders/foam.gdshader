shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Churning white water where a waterfall lands: bubbles boiling up and
// bursting all over the patch, fading only right at its edges.

uniform vec3 color : source_color = vec3(0.93, 0.98, 1.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float blobs(vec2 p, float t) {
	return sin(p.x * 9.0 + t * 3.1 + sin(p.y * 7.0 - t * 2.3))
		* sin(p.y * 8.0 - t * 2.7 + sin(p.x * 6.0 + t * 1.9));
}

void fragment() {
	vec2 c = UV - 0.5;
	float edge = 1.0 - smoothstep(0.4, 0.5, max(abs(c.x), abs(c.y)));
	float b = blobs(wp.xz, TIME) * 0.5 + blobs(wp.xz * 1.7 + 3.0, TIME * 1.3) * 0.5;
	float foam = smoothstep(-0.25, 0.45, b);
	ALPHA = clamp(0.7 + 0.3 * foam, 0.0, 1.0) * edge;
	ALBEDO = mix(vec3(0.62, 0.86, 1.0), color, foam);
}
