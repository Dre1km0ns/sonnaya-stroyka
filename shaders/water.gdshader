shader_type spatial;
// v0.6: пиксельная вода — тайл water из атласа, медленно течёт.
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest;
uniform int tile = 10;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha = 0.72;

void fragment() {
	vec2 uv = UV + vec2(TIME * 0.12, TIME * 0.05);
	vec2 f = fract(uv);
	ivec2 px = clamp(ivec2(f * 16.0), ivec2(0), ivec2(15));
	px.x += tile * 16;
	vec4 c = texelFetch(atlas, px, 0);
	ALBEDO = c.rgb * tint;
	ALPHA = alpha;
	ROUGHNESS = 0.25;
	METALLIC = 0.05;
}
