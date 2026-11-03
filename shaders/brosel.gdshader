// Brösel: small crumbs that bob and spin in the vertex shader, so lying Brösel cost no CPU.
// Per instance: COLOR = crumb colour, INSTANCE_CUSTOM.x = phase, .y = 1 while flying to a Knödl.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float spin_speed = 1.6;
uniform float bob_speed = 3.0;
uniform float bob_height = 0.06;

varying float sparkle;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float flying = INSTANCE_CUSTOM.y;
	float a = TIME * spin_speed * (1.0 + flying * 4.0) + phase;
	float c = cos(a);
	float s = sin(a);
	vec3 v = VERTEX;
	v.xz = vec2(c * v.x - s * v.z, s * v.x + c * v.z);
	VERTEX = v;
	// The bob is in world units, after the instance scale.
	VERTEX.y += sin(TIME * bob_speed + phase) * bob_height / max(length(MODEL_MATRIX[1].xyz), 0.001) * (1.0 - flying);
	sparkle = pow(max(sin(TIME * 2.3 + phase * 3.0), 0.0), 12.0);
}

void fragment() {
	vec3 color = srgb_to_linear(COLOR.rgb);
	ALBEDO = color;
	ROUGHNESS = 1.0;
	EMISSION = color * (0.18 + sparkle * 0.6);
}
