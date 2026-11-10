shader_type spatial;
render_mode unshaded;
// Molten fire, a flat sheet lying on its tile. Edges that do not join more
// fire (`joined`: +x, -x, +z, -z in the mesh's own axes, as in
// block.gdshaderinc) cool to a dark crust with a thin outline, the way ice and
// floor tiles are edged.

uniform vec3 size = vec3(1.0, 0.0, 1.0);
uniform vec4 joined = vec4(0.0);
uniform float edge = 0.11;
uniform vec3 crust : source_color = vec3(0.36, 0.07, 0.03);

varying vec3 wp;
varying vec3 lp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX;
}

void fragment() {
	float n = sin(wp.x * 7.0 + TIME * 1.3) * sin(wp.z * 6.0 - TIME) + sin((wp.x + wp.z) * 4.0 + TIME * 0.7);
	n = n * 0.25 + 0.5;
	vec3 c = mix(vec3(0.78, 0.12, 0.03), vec3(1.0, 0.72, 0.18), smoothstep(0.3, 0.8, n));

	vec3 d = size * 0.5 - abs(lp);
	float ex = d.x + 10.0 * (lp.x > 0.0 ? joined.x : joined.y);
	float ez = d.z + 10.0 * (lp.z > 0.0 ? joined.z : joined.w);
	vec3 px = sqrt(dFdx(lp) * dFdx(lp) + dFdy(lp) * dFdy(lp)) + 1e-6;
	// A wobbly crust line, so the edge looks cooled rather than ruled.
	float wobble = 0.015 * sin((wp.x - wp.z) * 23.0) * sin((wp.x + wp.z) * 17.0 + TIME * 0.4);
	c = mix(crust, c, smoothstep(0.0, edge, min(ex, ez) + wobble));
	float line = min(ex / px.x, ez / px.z);
	c *= 1.0 - 0.6 * clamp(1.75 - line, 0.0, 1.0);
	ALBEDO = c;
}
