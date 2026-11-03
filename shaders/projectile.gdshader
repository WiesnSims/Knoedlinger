// Bright unlit projectiles so they read in the crowd.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
}
