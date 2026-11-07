shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Water: a clear blue body, paler at grazing angles. Still water (pools,
// streams) has wavy streaks drifting across it and is only seen from outside;
// falling water is a two-sided sheet whose streaks race along at `scroll`
// (down if positive, up if negative). A waterfall shows only between `front`
// (how far it has poured) and `cut_top` (how far it has drained), and thins
// out below `fade_from` over `fade_length`: water lost to the void.

uniform vec3 body : source_color = vec3(0.05, 0.4, 0.72);
uniform vec3 foam : source_color = vec3(0.88, 0.97, 1.0);
uniform float still = 1.0;
uniform float scroll = 0.0;
uniform float cut_top = 100000.0;
uniform float front = -100000.0;
uniform float fade_from = -100000.0;
uniform float fade_length = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (still > 0.5 && !FRONT_FACING) {
		discard;
	}
	if (wp.y > cut_top || wp.y < front) {
		discard;
	}
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float streak;
	if (scroll != 0.0) {
		streak = smoothstep(0.7, 0.95, sin(wp.x * 7.0 - wp.z * 5.0 + (wp.y + TIME * scroll) * 3.0));
	} else {
		float wave = sin((wp.x + wp.z) * 3.0 + sin((wp.x - wp.z) * 2.2 + TIME * 0.9) * 1.4 + TIME * 1.1);
		streak = smoothstep(0.82, 0.97, wave);
	}
	ALBEDO = mix(body, foam, clamp(streak * 0.7 + fresnel * 0.5, 0.0, 1.0));
	float a = 0.68 + 0.22 * streak + 0.1 * fresnel;
	if (fade_length > 0.0) {
		a *= clamp(1.0 - (fade_from - wp.y) / fade_length, 0.0, 1.0);
	}
	ALPHA = a;
}
