// Map props (houses, tents, trees): vertex colours, plus see-through. ChaseCamera sets where the
// player is on screen; anything between the camera and the player is dithered away in a circle
// around them, and anything right in front of the lens fades out, so a wall never hides the player
// and the camera never shows the inside of a house (docs/DECISIONS.md, M3).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Screen position of the player (0..1), their distance from the camera, the cut-out radius in
// screen heights, and the viewport's width / height.
uniform vec2 focus_uv = vec2(0.5);
uniform float focus_depth = 0.0;
uniform float cut_radius = 0.0;
uniform float aspect = 1.7778;
// Fragments closer to the lens than this fade out.
uniform float near_fade = 1.4;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[index]) + 0.5) / 16.0;
}

void fragment() {
	// Vertex colours are stored linear already (MapBuilder / FlatMeshBuilder).
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	float depth = -VERTEX.z;
	float threshold = bayer4(FRAGCOORD.xy);
	float hide = 1.0 - clamp(depth / near_fade, 0.0, 1.0);
	if (cut_radius > 0.0 && depth < focus_depth - 1.2) {
		float d = length((SCREEN_UV - focus_uv) * vec2(aspect, 1.0));
		hide = max(hide, smoothstep(cut_radius, cut_radius * 0.55, d) * 0.85);
	}
	if (threshold < hide) {
		discard;
	}
}
