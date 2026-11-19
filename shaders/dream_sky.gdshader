shader_type sky;
// v0.21: небо Сна — градиент сада, медленные полосы сияния, густые звёзды и большая «луна снов» с кольцом.

uniform vec3 top_color : source_color = vec3(0.10, 0.07, 0.24);
uniform vec3 horizon_color : source_color = vec3(0.50, 0.40, 0.72);
uniform vec3 aurora_color : source_color = vec3(0.55, 0.95, 0.85);
uniform vec3 moon_color : source_color = vec3(1.0, 0.86, 0.98);
uniform vec3 moon_dir = vec3(0.45, 0.42, -0.79);
uniform float unease = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.05, 0.6, h));
	col = mix(col, horizon_color * 0.8, smoothstep(0.0, -0.25, h));
	float az = atan(d.x, d.z);
	// полосы сияния: две волны, медленно плывут
	if (h > 0.02) {
		float band = 0.0;
		for (int i = 0; i < 2; i++) {
			float fi = float(i);
			float y0 = 0.28 + 0.14 * fi + 0.06 * sin(az * (2.0 + fi) + TIME * 0.05 * (1.0 + fi));
			float w = 0.05 + 0.03 * noise(vec2(az * 3.0 + TIME * 0.03, fi * 7.0));
			band += smoothstep(w, 0.0, abs(h - y0)) * (0.55 + 0.45 * noise(vec2(az * 9.0 - TIME * 0.08, fi * 3.0)));
		}
		vec3 ac = mix(aurora_color, vec3(1.0, 0.45, 0.5), unease);
		col += ac * band * 0.32 * smoothstep(0.02, 0.2, h);
	}
	// звёзды: мелкие и редкие крупные, мерцают
	if (h > -0.02) {
		vec2 g = floor(vec2(az * 220.0, asin(clamp(h, -1.0, 1.0)) * 220.0));
		float s = hash(g);
		if (s > 0.993) {
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * hash(g + 5.0)) + s * 40.0);
			col += vec3(0.9, 0.85, 1.0) * (s - 0.993) / 0.007 * tw * smoothstep(-0.02, 0.2, h);
		}
	}
	// луна снов: мягкий диск, кольцо и ореол
	float md = dot(d, normalize(moon_dir));
	col += moon_color * pow(max(md, 0.0), 24.0) * 0.35;
	float ang = acos(clamp(md, -1.0, 1.0));
	col = mix(col, moon_color * 1.15, smoothstep(0.105, 0.095, ang));
	col += moon_color * smoothstep(0.012, 0.0, abs(ang - 0.17)) * 0.35;
	COLOR = col;
}
