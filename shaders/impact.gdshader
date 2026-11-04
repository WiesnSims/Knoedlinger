// Impacts of DROP, MINE and CHAIN weapons (WeaponVfx), many per MultiMesh in one draw call: a flat
// disc (MeshFactory.swing_fan) with a bright rim that fades, or a thin stretched box for a chain
// bolt. Per instance: COLOR = tint (sRGB), INSTANCE_CUSTOM.x = progress 0..1 (1 = gone),
// INSTANCE_CUSTOM.y = 1 for a bolt (lit evenly), 0 for a disc. UV.y = distance from the centre 0..1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

varying float progress;
varying float bolt;

void vertex() {
	progress = INSTANCE_CUSTOM.x;
	bolt = INSTANCE_CUSTOM.y;
}

void fragment() {
	float rim = smoothstep(0.5, 0.92, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	float inside = (1.0 - smoothstep(0.9, 1.0, UV.y)) * 0.25;
	float shape = mix(rim + inside, 1.0, bolt);
	ALBEDO = COLOR.rgb * COLOR.rgb;
	ALPHA = clamp(shape * (1.0 - progress), 0.0, 1.0);
}
