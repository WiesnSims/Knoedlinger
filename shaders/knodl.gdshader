// The Knödl, the hero object: soft dough with breadcrumb patches and parsley flecks that roll
// with the ball (object space), a gentle jiggle when it eats or hits, and a dithered fade while it
// is right in front of the camera or hides the player. No textures, no transparency sorting.
shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform vec3 dough_color : source_color = vec3(0.8, 0.66, 0.44);
uniform vec3 crumb_color : source_color = vec3(0.7, 0.5, 0.28);
uniform vec3 fleck_color : source_color = vec3(0.3, 0.52, 0.2);
// 0..1, set from the script on hits and when it eats; dies away there.
uniform float wobble = 0.0;
// 1 = solid; lower dithers pixels away (set from the script).
uniform float fade = 1.0;
// Crumbs per unit of the unit sphere; the script raises it as the Knödl grows so crumbs keep their size.
uniform float crumb_scale = 3.5;

varying vec3 object_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	object_pos = VERTEX;
	// One soft band running over the ball: it stays round, it only jiggles.
	float w = wobble * 0.045 * sin(TIME * 21.0 + VERTEX.y * 2.2);
	VERTEX *= 1.0 + w;
}

void fragment() {
	if (fade < 0.999) {
		// Interleaved gradient noise: a stable per-pixel threshold.
		float threshold = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (threshold > fade) {
			discard;
		}
	}
	vec3 p = object_pos * crumb_scale;
	float coarse = noise(p);
	float fine = noise(p * 2.7 + 11.0);
	// Bread cubes: soft patches, a little darker, with fine grain on top.
	float crumbs = smoothstep(0.5, 0.72, coarse * 0.65 + fine * 0.45);
	vec3 color = mix(dough_color, crumb_color, crumbs * 0.8);
	color *= 0.92 + fine * 0.12;
	float fleck = step(0.86, noise(p * 3.9 + 37.0));
	color = mix(color, fleck_color, fleck * 0.85);
	ALBEDO = color;
	ROUGHNESS = mix(0.7, 0.95, crumbs);
	SPECULAR = 0.2;
	// Soft dough: a little light wraps around the edge.
	RIM = 0.15;
	RIM_TINT = 0.6;
}
