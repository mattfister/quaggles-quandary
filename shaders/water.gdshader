shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
// Water: a clear blue body, paler at grazing angles, with soft streaks that
// drift across still water and race down falling water. With `fade_length`
// set, a curtain thins out toward its bottom: water lost to the void.

uniform vec3 body : source_color = vec3(0.05, 0.4, 0.72);
uniform vec3 foam : source_color = vec3(0.88, 0.97, 1.0);
uniform float falling = 0.0;
uniform float fade_length = 0.0;

varying vec3 lp;
varying vec3 wp;

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float streak;
	if (falling > 0.5) {
		streak = smoothstep(0.7, 0.95, sin(wp.x * 7.0 - wp.z * 5.0 + (wp.y + TIME * 2.5) * 3.0));
	} else {
		float wave = sin((wp.x + wp.z) * 3.0 + sin((wp.x - wp.z) * 2.2 + TIME * 0.9) * 1.4 + TIME * 1.1);
		streak = smoothstep(0.82, 0.97, wave);
	}
	ALBEDO = mix(body, foam, clamp(streak * 0.7 + fresnel * 0.5, 0.0, 1.0));
	float a = 0.68 + 0.22 * streak + 0.1 * fresnel;
	if (fade_length > 0.0) {
		a *= clamp(lp.y / fade_length + 0.5, 0.0, 1.0);
	}
	ALPHA = a;
}
