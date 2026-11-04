// A soft light column: golden over each Stempel (the Formular quest), visible across the village,
// short and in its rarity colour over each chest. The colour is the instance colour (sRGB).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	// UV.y runs along the column; fade toward the top and pulse gently.
	float fade = (1.0 - UV.y) * (0.75 + 0.25 * sin(TIME * 3.0 + UV.y * 12.0));
	ALBEDO = COLOR.rgb * COLOR.rgb;
	ALPHA = clamp(fade * 0.35, 0.0, 1.0);
}
