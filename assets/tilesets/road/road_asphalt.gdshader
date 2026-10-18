shader_type canvas_item;
// Асфальт дорожного TileSet.
// Пиксели тайлов, помеченные альфой 254, заменяются бесшовной текстурой асфальта,
// которая лежит в мировых координатах: рисунок не повторяется по клеткам и не даёт швов
// между тайлами. Бордюр, лоток и прозрачные пиксели берутся из самого тайла как есть.

uniform sampler2D asphalt_texture : source_color, filter_nearest, repeat_enable;

varying vec2 world_pos;
varying vec4 vertex_color;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_color = COLOR;
}

void fragment() {
	vec4 tile = texture(TEXTURE, UV);
	if (abs(tile.a * 255.0 - 254.0) < 0.5) {
		vec2 size = vec2(textureSize(asphalt_texture, 0));
		COLOR = vec4(texture(asphalt_texture, world_pos / size).rgb, 1.0) * vertex_color;
	} else {
		COLOR = tile * vertex_color;
	}
}
