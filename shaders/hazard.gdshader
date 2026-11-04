// Enemy attack marks in Krampus red (GAME-DESIGN.md: one danger colour, nothing friendly uses it).
// Per instance: INSTANCE_CUSTOM.x = fill progress 0..1, .y = 0 circle / 1 line, .z = hit flash,
// .w = line length / width. A circle fills from the middle out, a line from its start to its end.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 danger : source_color = vec3(0.86, 0.08, 0.06);

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float progress = custom.x;
	float flash = custom.z;
	float rim;
	float fill;
	if (custom.y < 0.5) {
		float d = length(p);
		if (d > 1.0) {
			discard;
		}
		rim = smoothstep(0.84, 0.95, d);
		fill = 1.0 - smoothstep(progress - 0.03, progress, d);
	} else {
		float aspect = max(custom.w, 1.0);
		rim = max(smoothstep(0.8, 0.95, abs(p.x)), smoothstep(1.0 - 0.2 / aspect, 1.0 - 0.05 / aspect, abs(p.y)));
		fill = 1.0 - smoothstep(progress - 0.02, progress, UV.y);
	}
	float alpha = 0.16 + rim * 0.62 + fill * 0.34 + flash * 0.5;
	// Pulses faster as the hit comes closer.
	alpha *= 0.85 + 0.15 * sin(TIME * (8.0 + progress * 16.0));
	ALBEDO = mix(danger, vec3(1.0, 0.85, 0.8), flash * 0.6);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
