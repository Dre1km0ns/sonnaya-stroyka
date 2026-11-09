extends Control
## Тусклые силуэты будущей брони: только рисунок, никакой логики экипировки.
var kind := 0

func _draw() -> void:
	var points: PackedVector2Array
	match kind:
		0: # Шлем с вырезом для лица.
			points = PackedVector2Array([Vector2(13, 33), Vector2(13, 19), Vector2(19, 12), Vector2(33, 12), Vector2(39, 19), Vector2(39, 33), Vector2(31, 33), Vector2(31, 24), Vector2(21, 24), Vector2(21, 33)])
		1: # Нагрудник с плечами и горловиной.
			points = PackedVector2Array([Vector2(9, 20), Vector2(18, 12), Vector2(22, 17), Vector2(30, 17), Vector2(34, 12), Vector2(43, 20), Vector2(37, 28), Vector2(34, 25), Vector2(34, 40), Vector2(18, 40), Vector2(18, 25), Vector2(15, 28)])
		2: # Поножи, две штанины.
			points = PackedVector2Array([Vector2(16, 12), Vector2(36, 12), Vector2(38, 40), Vector2(28, 40), Vector2(26, 25), Vector2(24, 40), Vector2(14, 40)])
		_: # Два ботинка.
			draw_colored_polygon(PackedVector2Array([Vector2(14, 16), Vector2(23, 16), Vector2(23, 36), Vector2(9, 36), Vector2(9, 29), Vector2(14, 27)]), Color(0.65, 0.62, 0.72, 0.28))
			points = PackedVector2Array([Vector2(29, 16), Vector2(38, 16), Vector2(38, 27), Vector2(43, 29), Vector2(43, 36), Vector2(29, 36)])
	draw_colored_polygon(points, Color(0.65, 0.62, 0.72, 0.28))
