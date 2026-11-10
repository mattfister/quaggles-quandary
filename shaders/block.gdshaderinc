// Bevelled block: soft dark edges, a highlight ring on top, shaded sides,
// a thin outline and banded toon light to match the quaggles.
// COLOR carries a per-instance tint (checkerboard shading). INSTANCE_CUSTOM
// says which sides (+x, -x, +z, -z, in the mesh's own axes) join a matching
// neighbour: no edge is drawn there, so runs of blocks read as one shape.

uniform vec3 size = vec3(1.0);
uniform vec3 top_color : source_color = vec3(1.0);
uniform vec3 side_color : source_color = vec3(0.6);
uniform float edge = 0.07;
uniform float streaks = 0.0;
uniform float outline = 1.0;
// The part of a full block's height this one covers, for side shading: a
// wall cut short under a floor tile, or the cap that tops it up again.
uniform vec2 shade_span = vec2(0.0, 1.0);
// Cracked tiles: above 0, the faces split into plates along dark cracks,
// laid out by `crack_seed` so no two tiles look alike.
uniform float cracks = 0.0;
uniform float crack_seed = 0.0;
uniform vec3 crack_color : source_color = vec3(0.29, 0.2, 0.15);
#ifdef FADE
uniform float fade : hint_range(0.0, 1.0) = 0.0;
#endif

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 tint;
varying vec4 joined;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	tint = COLOR.rgb;
	joined = INSTANCE_CUSTOM;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Voronoi plates: x is the distance to the nearest crack (cell border), y a
// random value per plate.
vec2 plates(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g + crack_seed) * 0.8 + 0.1 - f;
			float dd = dot(r, r);
			if (dd < md) {
				md = dd;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g + crack_seed) * 0.8 + 0.1 - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec2(md, hash2(n + mg + crack_seed + 7.3).x);
}

// Darkens `c` along cracks in face coordinates `uv`, shading each plate.
vec3 crack(vec3 c, vec2 uv) {
	vec2 v = plates(uv * 1.9);
	float aa = fwidth(v.x);
	c *= 0.9 + 0.16 * v.y;
	c *= mix(0.84, 1.0, smoothstep(0.0, 0.1, v.x));
	return mix(crack_color, c, smoothstep(0.018, 0.018 + aa * 1.5, v.x));
}

// How much of a pixel the outline covers, `line` pixels from the edge: a
// line 1.25 px wide, blended over a pixel's width with a box filter.
float outline_cover(float line) {
	return clamp(1.75 - line, 0.0, 1.0);
}

void fragment() {
	vec3 h = size * 0.5;
	vec3 d = h - abs(lp);
	// Distance to the nearest edge along x and z that is not joined.
	float ex = d.x + 10.0 * (lp.x > 0.0 ? joined.x : joined.y);
	float ez = d.z + 10.0 * (lp.z > 0.0 ? joined.z : joined.w);
	// Edge distances in pixels, for the outline (lp is smooth across a face,
	// unlike ex and ez, which jump where a joined side meets an open one).
	// The true screen gradient, not fwidth, whose sum of |dx| and |dy| thins
	// lines that run diagonally across the screen.
	vec3 px = sqrt(dFdx(lp) * dFdx(lp) + dFdy(lp) * dFdy(lp)) + 1e-6;
	float line;
	vec3 c;
	if (abs(ln.y) > 0.5) {
		float e = min(ex, ez);
		line = min(ex / px.x, ez / px.z);
		c = top_color * tint;
		if (cracks > 0.0) {
			c = crack(c, lp.xz);
		}
		c *= mix(0.74, 1.0, smoothstep(0.0, edge, e));
		c += 0.07 * (smoothstep(edge, edge + 0.01, e) - smoothstep(edge + 0.03, edge + 0.05, e));
		c += streaks * 0.16 * smoothstep(0.8, 1.0, sin((wp.x + wp.z * 0.6) * 5.0));
	} else {
		float ev = abs(ln.x) > 0.5 ? ez : ex;
		float up = mix(shade_span.x, shade_span.y, clamp((lp.y + h.y) / size.y, 0.0, 1.0));
		c = side_color * tint * mix(0.72, 1.0, up);
		c *= mix(0.86, 1.0, smoothstep(0.0, edge, ev));
		if (cracks > 0.0) {
			// The cracks run on over the edge and down the sides: the top's
			// pattern, folded down.
			float down = h.y - lp.y;
			vec2 uv = abs(ln.x) > 0.5 ? vec2(lp.x + sign(lp.x) * down, lp.z) : vec2(lp.x, lp.z + sign(lp.z) * down);
			c = crack(c, uv);
		}
		line = min(abs(ln.x) > 0.5 ? ez / px.z : ex / px.x, d.y / px.y);
	}
	c *= 1.0 - outline * 0.55 * outline_cover(line);
	ALBEDO = c;
#ifdef FADE
	ALPHA = 1.0 - fade;
#endif
}

void light() {
	float b = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float band = 0.18 + 0.27 * smoothstep(0.1, 0.16, b) + 0.2 * smoothstep(0.62, 0.68, b);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
}
