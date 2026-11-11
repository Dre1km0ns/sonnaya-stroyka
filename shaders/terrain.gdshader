shader_type spatial;
// v0.6: блоки из атласа 16x16 (texelFetch = чёткие пиксели без «просачивания»),
// UV — координаты в блоках (повтор внутри слитых граней), UV2.x — номер тайла, COLOR — тень/оттенок.
render_mode cull_back, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
varying flat int v_tile;

void vertex() {
	v_tile = int(UV2.x + 0.5);
}

void fragment() {
	vec2 f = fract(UV);
	ivec2 px = clamp(ivec2(f * 16.0), ivec2(0), ivec2(15));
	px.x += v_tile * 16;
	vec4 c = texelFetch(atlas, px, 0);
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 0.95;
}
