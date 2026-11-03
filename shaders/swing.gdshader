// A melee swing: a flat fan that sweeps open and fades. `progress` runs 0..1 per swing (script).
// UV.x = angle across the arc 0..1, UV.y = distance from the player 0..1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.85, 0.95, 1.0);
uniform float progress = 1.0;

void fragment() {
	// Revealed up to the leading edge, which crosses the arc in the first 70 % of the swing.
	float lead = progress * 1.45;
	float sweep = 1.0 - smoothstep(lead - 0.15, lead, UV.x);
	float edge = smoothstep(0.35, 1.0, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	float fade = 1.0 - progress;
	ALBEDO = tint;
	ALPHA = sweep * edge * fade * 0.9;
}
