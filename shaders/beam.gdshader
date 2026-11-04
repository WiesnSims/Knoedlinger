// A soft golden light column over each Stempel (the Formular quest), visible across the village.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.35);

void fragment() {
	// UV.y runs along the column; fade toward the top and pulse gently.
	float fade = (1.0 - UV.y) * (0.75 + 0.25 * sin(TIME * 3.0 + UV.y * 12.0));
	ALBEDO = tint;
	ALPHA = clamp(fade * 0.35, 0.0, 1.0);
}
