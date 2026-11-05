// A flame stream (WeaponData.Look.FLAME, the Obstler): a cone of flickering tongues that grows out
// of the player in the first fifth and fades at the end. `progress` runs 0..1 per burst (script).
// UV.x = angle across the cone 0..1, UV.y = distance from the player 0..1. Never Krampus red.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.75, 0.3);
uniform float progress = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// Tongues rush outward.
	float tongue = noise(vec2(UV.x * 7.0, UV.y * 5.0 - TIME * 9.0)) * 0.6
			+ noise(vec2(UV.x * 15.0, UV.y * 12.0 - TIME * 16.0)) * 0.4;
	float reach = smoothstep(0.0, 0.2, progress);
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	// Narrow at the nozzle, full width further out.
	float width = smoothstep(0.0, mix(0.9, 0.35, UV.y), across);
	float tip = 1.0 - smoothstep(0.5, 1.0, UV.y / max(reach, 0.01) + (1.0 - tongue) * 0.4);
	float nozzle = smoothstep(0.02, 0.12, UV.y);
	float heat = clamp(1.0 - UV.y * 1.3, 0.0, 1.0);
	// Deep orange at the tips and edges, bright yellow in the hot core near the nozzle.
	float core = heat * smoothstep(0.3, 0.9, across) * (0.6 + 0.4 * tongue);
	vec3 colour = mix(vec3(1.0, 0.36, 0.02), tint * vec3(1.0, 0.85, 0.5), smoothstep(0.2, 0.7, heat + tongue * 0.3));
	ALBEDO = mix(colour, vec3(1.0, 0.93, 0.5), clamp(core * 1.4, 0.0, 1.0));
	ALPHA = clamp(width * tip * nozzle * (0.85 + 0.6 * tongue), 0.0, 0.95) * (1.0 - smoothstep(0.65, 1.0, progress));
}
