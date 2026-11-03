// A flat disc on the ground (MeshFactory.swing_fan over a full turn): a soft fill plus a bright
// band at the rim that fades with `progress` (0 = just fired, 1 = gone). Kuhglocke shockwaves
// grow the node while the band fades; the Watschn-Aura keeps a faint fill and pulses on every tick;
// a Wirtshaus door glows with it.
// UV.y = distance from the centre 0..1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.5);
uniform float progress = 1.0;
uniform float fill = 0.0;

void fragment() {
	float rim = smoothstep(0.6, 0.95, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y));
	float inside = smoothstep(0.0, 0.9, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y));
	ALBEDO = tint;
	ALPHA = clamp(rim * (1.0 - progress) * 0.85 + inside * fill, 0.0, 1.0);
}
