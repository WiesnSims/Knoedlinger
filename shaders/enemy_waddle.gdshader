// Fodder animation in the vertex shader (CLAUDE.md): waddle, bob and squash, no skeletons.
// Per instance: INSTANCE_CUSTOM.x = phase (radians), .y = hit flash 0..1, .z = 1 for flyers,
// .w = status bits (1 frozen: ice blue and still, 2 burning: orange glow; EnemyManager.STATUS_*).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float waddle_speed = 9.0;
uniform float waddle_angle = 0.12;
uniform float bob_height = 0.06;
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 frozen_color : source_color = vec3(0.6, 0.85, 1.0);
uniform vec3 burning_color : source_color = vec3(1.0, 0.55, 0.15);
// Debugging only: 1 shows the vertex colour unlit, 2 the normal, 3 the instance custom data.
uniform int debug_view = 0;
// See-through (ChaseCamera, like shaders/world_props.gdshader): enemies between the camera and the
// player are dithered in a circle around the player, and anything right at the lens fades out.
uniform vec2 focus_uv = vec2(0.5);
uniform float focus_depth = 0.0;
uniform float cut_radius = 0.0;
uniform float aspect = 1.7778;
uniform float near_fade = 2.5;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.x + i.y * 4]) + 0.5) / 16.0;
}

varying float flash;
varying float frozen;
varying float burning;
varying vec3 debug_custom;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float bits = INSTANCE_CUSTOM.w;
	frozen = mod(bits, 2.0) > 0.5 ? 1.0 : 0.0;
	burning = bits > 1.5 ? 1.0 : 0.0;
	// A frozen enemy stands still: no waddle.
	float t = (TIME * waddle_speed) * (1.0 - frozen) + phase;
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
	vec3 base = srgb_to_linear(COLOR.rgb);
	base = mix(base, frozen_color, frozen * 0.6);
	base = mix(base, burning_color, burning * (0.35 + 0.15 * sin(TIME * 14.0)));
	ALBEDO = mix(base, flash_color, flash);
	EMISSION = burning_color * burning * 0.25;
	ROUGHNESS = 1.0;
	float depth = -VERTEX.z;
	float hide = 1.0 - clamp((depth - 0.5) / near_fade, 0.0, 1.0);
	if (cut_radius > 0.0 && depth < focus_depth - 1.0) {
		float d = length((SCREEN_UV - focus_uv) * vec2(aspect, 1.0));
		hide = max(hide, smoothstep(cut_radius, cut_radius * 0.55, d) * 0.7);
	}
	if (bayer4(FRAGCOORD.xy) < hide) {
		discard;
	}
	if (debug_view == 1) { ALBEDO = vec3(0.0); EMISSION = COLOR.rgb; }
	if (debug_view == 2) { ALBEDO = vec3(0.0); EMISSION = NORMAL * 0.5 + 0.5; }
	if (debug_view == 3) { ALBEDO = vec3(0.0); EMISSION = vec3(fract(debug_custom.x), debug_custom.y, debug_custom.z); }
}
