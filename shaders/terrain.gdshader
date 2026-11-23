shader_type spatial;
// v0.6: блоки из атласа 16x16 (texelFetch = чёткие пиксели без «просачивания»),
// UV — координаты в блоках (повтор внутри слитых граней), UV2.x — номер тайла, COLOR — тень/оттенок.
render_mode cull_back, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 tint = vec3(1.0); // v0.22.1: фиолетовый Сон
uniform float dream = 0.0;     // v0.22.1: 1 — блок Сна перекрашивается в фиолетовый по яркости
varying flat int v_tile;

void vertex() {
	v_tile = int(UV2.x + 0.5);
}

void fragment() {
	vec2 f = fract(UV);
	ivec2 px = clamp(ivec2(f * 16.0), ivec2(0), ivec2(15));
	px.x += v_tile * 16;
	vec4 c = texelFetch(atlas, px, 0);
	vec3 col = c.rgb * COLOR.rgb;
	if (dream > 0.5 && COLOR.a > 0.5) { // альфа вершины 0 — дрейф/рот: свои тайлы Сна
		float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
		vec3 purple = vec3(l) * tint * 1.35;
		col = mix(col, purple * (COLOR.rgb * 0.35 + 0.65), 0.8);
	} else if (dream < 0.5) {
		col *= tint;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
