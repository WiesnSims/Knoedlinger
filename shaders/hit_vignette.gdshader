shader_type canvas_item;
// 1.4.1 (C6): the red glow on the screen edge when the player is hit (HitFeedback). `strength` lights
// the whole edge, `dir` (screen space, length = how strong) adds a bright arc on the side the hit came
// from, `pulse` is the slow low-HP glow.

uniform vec4 tint : source_color = vec4(0.9, 0.22, 0.23, 1.0);
uniform float strength = 0.0;
uniform vec2 dir = vec2(0.0, 0.0);
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = max(abs(p.x), abs(p.y)) * 0.55 + length(p) * 0.45;
	float edge = smoothstep(0.72, 1.12, r);
	float side = 0.0;
	float pull = length(dir);
	if (pull > 0.01) {
		float facing = dot(normalize(p + vec2(0.0001)), dir / pull);
		side = smoothstep(0.6, 1.0, facing) * smoothstep(0.62, 1.08, r) * pull;
	}
	float a = edge * max(strength, pulse) + side * 0.8;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.7));
}
