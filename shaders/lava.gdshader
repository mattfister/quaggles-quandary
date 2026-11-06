shader_type spatial;
render_mode unshaded;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = sin(wp.x * 7.0 + TIME * 1.3) * sin(wp.z * 6.0 - TIME) + sin((wp.x + wp.z) * 4.0 + TIME * 0.7);
	n = n * 0.25 + 0.5;
	ALBEDO = mix(vec3(0.78, 0.12, 0.03), vec3(1.0, 0.72, 0.18), smoothstep(0.3, 0.8, n));
}
