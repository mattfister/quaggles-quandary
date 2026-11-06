shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
// Fractal clouds in the spirit of the original procedurally generated skybox.

uniform vec3 sky_top : source_color = vec3(0.184, 0.435, 0.839);
uniform vec3 sky_horizon : source_color = vec3(0.769, 0.894, 1.0);
uniform vec3 sky_below : source_color = vec3(0.42, 0.67, 0.93);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.8, 0.96);
uniform float seed = 0.0;

const vec3 SUN = vec3(0.37, 0.74, 0.59); // direction toward the sun

varying vec3 dir;

void vertex() {
	dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fractal_cloud(vec3 p) {
	float amp = 0.5;
	float total = 0.0;
	for (int i = 0; i < 5; i++) {
		total += amp * noise(p);
		p = p * 2.03 + 17.1;
		amp *= 0.5;
	}
	return total;
}

// Cloud thickness in a direction: wispy fractal detail, gathered into banks
// by a slow mask so there is clear sky between them.
float density(vec3 p) {
	vec3 warp = vec3(noise(p * 1.3 + 7.0), noise(p * 1.3 + 19.0), noise(p * 1.3 + 31.0)) - 0.5;
	float banks = noise(p * 0.55 + seed);
	return fractal_cloud(p + warp * 0.7) * 0.8 + banks * 0.4;
}

void fragment() {
	vec3 d = normalize(dir);
	// Above the horizon: blue sky. Below (most of what the camera sees): a
	// lighter haze.
	vec3 base = mix(sky_horizon, sky_top, smoothstep(0.0, 0.8, d.y));
	base = mix(base, sky_below, smoothstep(0.0, -0.7, d.y));

	vec3 p = d * 2.4 + vec3(TIME * 0.012, 0.0, TIME * 0.007);
	float n = density(p);
	float toward_sun = density(p + SUN * 0.12);
	float cover = smoothstep(0.52, 0.78, n);
	// Sides facing away from the sun pick up a soft blue shadow.
	float light = clamp(0.75 + (n - toward_sun) * 5.0, 0.0, 1.0);
	vec3 cloud = mix(cloud_shade, cloud_color, light);
	ALBEDO = mix(base, cloud, cover * 0.92);
}
