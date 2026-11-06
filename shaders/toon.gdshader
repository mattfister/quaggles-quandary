shader_type spatial;
// After the original toon.frag: four brightness bands and a dark rim.

uniform vec3 albedo : source_color = vec3(1.0);
uniform float burn : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = mix(albedo, vec3(0.03), burn);
	if (dot(normalize(NORMAL), normalize(VIEW)) < 0.26) {
		c *= 0.22;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float brightness = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
	float band = 0.55;
	if (brightness > 0.75) {
		band = 1.0;
	} else if (brightness > 0.5) {
		band = 0.85;
	} else if (brightness > 0.25) {
		band = 0.7;
	}
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
}
