shader_type sky;
// v0.6: небо с пиксельным солнцем и луной (квадратные, как в Minecraft), звёзды ночью.

uniform vec3 top_color : source_color = vec3(0.36, 0.58, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.30, 0.32, 0.36);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float sun_size = 0.075;
uniform float moon_size = 0.06;
uniform float stars = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 disc_coords(vec3 d, vec3 c) {
	vec3 right = normalize(cross(c, vec3(0.0, 1.0, 0.001)));
	vec3 up = cross(right, c);
	float k = dot(d, c);
	return vec2(dot(d, right), dot(d, up)) / max(k, 0.0001);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.2, h));
	// звёзды
	if (stars > 0.01 && h > 0.0) {
		vec2 g = floor(vec2(atan(d.x, d.z) * 160.0, asin(clamp(h, -1.0, 1.0)) * 160.0));
		float s = hash(g);
		if (s > 0.9965) {
			col += vec3(0.85, 0.88, 1.0) * stars * (s - 0.9965) / 0.0035 * smoothstep(0.0, 0.25, h);
		}
	}
	// солнце: ореол + квадратный диск
	float sd = dot(d, sun_dir);
	col += sun_color * pow(max(sd, 0.0), 48.0) * 0.45 * smoothstep(-0.1, 0.05, sun_dir.y);
	if (sd > 0.0) {
		vec2 p = disc_coords(d, sun_dir);
		if (max(abs(p.x), abs(p.y)) < sun_size) {
			col = mix(col, vec3(1.0, 0.97, 0.78) * 1.6, smoothstep(-0.12, 0.02, sun_dir.y + h * 0.0));
		}
	}
	// луна: квадрат с пиксельными кратерами
	float md = dot(d, moon_dir);
	col += vec3(0.5, 0.6, 0.9) * pow(max(md, 0.0), 90.0) * 0.25;
	if (md > 0.0) {
		vec2 p = disc_coords(d, moon_dir);
		if (max(abs(p.x), abs(p.y)) < moon_size) {
			vec2 px = floor((p / moon_size * 0.5 + 0.5) * 8.0);
			float cr = hash(px + vec2(3.0, 7.0));
			vec3 mc = vec3(0.86, 0.88, 0.95) * (cr > 0.72 ? 0.72 : 1.0);
			col = mix(col, mc * 1.25, 1.0);
		}
	}
	COLOR = col;
}
