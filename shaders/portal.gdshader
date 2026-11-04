// The gate's swirl: a turning spiral in the gate's colour, brighter when open. Not red (red is
// only for enemy attacks).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.4, 0.35, 0.5);
uniform float energy = 0.4;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 1.4);
	float r = length(p);
	float a = atan(p.y, p.x);
	float spiral = sin(a * 3.0 + r * 14.0 - TIME * 3.0 * (0.4 + energy));
	float glow = smoothstep(0.75, 0.0, r);
	vec3 color = tint * (0.55 + 0.45 * spiral) + vec3(1.0) * glow * energy * 0.35;
	ALBEDO = color;
	ALPHA = clamp((0.55 + 0.35 * spiral) * smoothstep(0.78, 0.6, r) + glow * 0.3, 0.0, 0.95);
}
