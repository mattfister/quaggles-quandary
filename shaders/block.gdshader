shader_type spatial;
// Bevelled block: soft dark edges, a highlight ring on top, shaded sides.
// COLOR carries a per-instance tint (checkerboard shading).

uniform vec3 size = vec3(1.0);
uniform vec3 top_color : source_color = vec3(1.0);
uniform vec3 side_color : source_color = vec3(0.6);
uniform float edge = 0.07;
uniform float roughness = 0.9;
uniform float streaks = 0.0;
// The part of a full block's height this one covers, for side shading: a
// wall cut short under a floor tile, or the cap that tops it up again.
uniform vec2 shade_span = vec2(0.0, 1.0);
uniform sampler2D detail : source_color, hint_default_white;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 tint;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	tint = COLOR.rgb;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 h = size * 0.5;
	vec3 d = h - abs(lp);
	vec3 c;
	if (abs(ln.y) > 0.5) {
		float e = min(d.x, d.z);
		c = top_color * tint * texture(detail, lp.xz / size.xz + 0.5).rgb;
		c *= mix(0.74, 1.0, smoothstep(0.0, edge, e));
		c += 0.07 * (smoothstep(edge, edge + 0.01, e) - smoothstep(edge + 0.03, edge + 0.05, e));
		c += streaks * 0.16 * smoothstep(0.8, 1.0, sin((wp.x + wp.z * 0.6) * 5.0));
	} else {
		float e = abs(ln.x) > 0.5 ? d.z : d.x;
		float up = mix(shade_span.x, shade_span.y, clamp((lp.y + h.y) / size.y, 0.0, 1.0));
		c = side_color * tint * mix(0.72, 1.0, up);
		c *= mix(0.86, 1.0, smoothstep(0.0, edge, e));
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
