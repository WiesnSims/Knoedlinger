// Fodder animation in the vertex shader (CLAUDE.md): waddle, bob and squash, no skeletons.
// Per instance: INSTANCE_CUSTOM.x = phase (radians), .y = hit flash 0..1, .z = 1 for flyers.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float waddle_speed = 9.0;
uniform float waddle_angle = 0.12;
uniform float bob_height = 0.06;
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);
// Debugging only: 1 shows the vertex colour unlit, 2 the normal, 3 the instance custom data.
uniform int debug_view = 0;

varying float flash;
varying vec3 debug_custom;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float t = TIME * waddle_speed + phase;
	float flyer = INSTANCE_CUSTOM.z;
	// Walkers rock side to side around their feet; flyers bob up and down faster.
	float angle = sin(t) * waddle_angle * (1.0 - flyer);
	float c = cos(angle);
	float s = sin(angle);
	vec3 v = VERTEX;
	v.xy = vec2(c * v.x - s * v.y, s * v.x + c * v.y);
	float bob = abs(sin(t)) * bob_height * (1.0 - flyer) + sin(t * 2.0) * 0.15 * flyer;
	v.y += bob;
	float squash = 1.0 + sin(t * 2.0) * 0.04;
	v.y *= squash;
	v.xz /= sqrt(squash);
	VERTEX = v;
	flash = INSTANCE_CUSTOM.y;
	debug_custom = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	// Vertex colours are authored in sRGB; lighting works in linear.
	ALBEDO = mix(srgb_to_linear(COLOR.rgb), flash_color, flash);
	ROUGHNESS = 1.0;
	if (debug_view == 1) { ALBEDO = vec3(0.0); EMISSION = COLOR.rgb; }
	if (debug_view == 2) { ALBEDO = vec3(0.0); EMISSION = NORMAL * 0.5 + 0.5; }
	if (debug_view == 3) { ALBEDO = vec3(0.0); EMISSION = vec3(fract(debug_custom.x), debug_custom.y, debug_custom.z); }
}
