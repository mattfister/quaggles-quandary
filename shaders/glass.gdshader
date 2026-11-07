shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
// Window glass: nearly clear in the middle, a bright rim on edges that do not
// join another pane (INSTANCE_CUSTOM, as in block.gdshader), fresnel at
// grazing angles and a diagonal shine sweeping across.

uniform vec3 size = vec3(1.0);
uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);
uniform float rim = 0.07;

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec4 joined;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	joined = INSTANCE_CUSTOM;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Faces between two joined panes are inside the glass.
	if ((ln.x > 0.5 && joined.x > 0.5) || (ln.x < -0.5 && joined.y > 0.5)
			|| (ln.z > 0.5 && joined.z > 0.5) || (ln.z < -0.5 && joined.w > 0.5)) {
		discard;
	}
	vec3 d = size * 0.5 - abs(lp);
	float ex = d.x + 10.0 * (lp.x > 0.0 ? joined.x : joined.y);
	float ez = d.z + 10.0 * (lp.z > 0.0 ? joined.z : joined.w);
	float e = abs(ln.y) > 0.5 ? min(ex, ez) : min(abs(ln.x) > 0.5 ? ez : ex, d.y);
	float frame = 1.0 - smoothstep(rim * 0.6, rim, e);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float shine = smoothstep(0.86, 0.9, sin((wp.x - wp.z) * 1.6 + wp.y * 1.6 + TIME * 0.6));
	shine += 0.6 * smoothstep(0.93, 0.96, sin((wp.x - wp.z) * 1.6 + wp.y * 1.6 + TIME * 0.6 - 0.55));
	ALBEDO = mix(tint, vec3(1.0), clamp(frame * 0.85 + shine * 0.6, 0.0, 1.0));
	ALPHA = clamp(0.3 + 0.8 * frame + 0.3 * fresnel + 0.22 * shine, 0.0, 0.95);
}
