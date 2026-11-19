shader_type spatial;
// v0.21 c4: острова Сна — те же пиксельные текстуры атласа, что и у земли Сна (UV2.x — номер тайла),
// плюс оттенок палитры Сна и лёгкое свечение, чтобы острова читались в тумане.
render_mode cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 tint = vec3(1.0);
uniform float glow = 0.32;
varying flat int v_tile;

void vertex() {
	v_tile = int(UV2.x + 0.5);
}

void fragment() {
	vec2 f = fract(UV);
	ivec2 px = clamp(ivec2(f * 16.0), ivec2(0), ivec2(15));
	px.x += v_tile * 16;
	vec4 c = texelFetch(atlas, px, 0);
	ALBEDO = c.rgb * COLOR.rgb * tint;
	EMISSION = ALBEDO * glow;
	ROUGHNESS = 1.0;
}
