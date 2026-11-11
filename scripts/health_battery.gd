extends Control
## v0.11.1: индикатор здоровья «батарейка телефона» — скруглённый корпус, заливка по HP, число HP внутри.
## Заменяет сердечки и подпись «HP n/100».

var hp: int = 100
var max_hp: int = 100
var regen := false
var label: Label
var _flash := 0.0


func _ready() -> void:
	name = "HealthBattery"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.name = "HPText"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_right = -8.0  # не залезать на «пипку» батарейки
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	set_hp(hp, max_hp)


func set_hp(v: int, m: int) -> void:
	if v < hp: _flash = 0.35
	hp = clampi(v, 0, maxi(1, m))
	max_hp = maxi(1, m)
	label.text = str(hp)
	queue_redraw()


func fraction() -> float:
	return float(hp) / float(max_hp)


func fill_color() -> Color:
	var f := fraction()
	if f > 0.5: return Color(0.33, 0.85, 0.42)
	if f > 0.25: return Color(0.98, 0.78, 0.25)
	return Color(0.95, 0.3, 0.28)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


func _draw() -> void:
	var nub_w := 6.0
	var body := Rect2(Vector2.ZERO, Vector2(size.x - nub_w, size.y))
	var r := 6
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	bg.border_color = Color(0.92, 0.94, 0.98, 0.95)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(r)
	draw_style_box(bg, body)
	# «Пипка» батарейки справа.
	var nub := StyleBoxFlat.new()
	nub.bg_color = Color(0.92, 0.94, 0.98, 0.95)
	nub.corner_radius_top_right = 3
	nub.corner_radius_bottom_right = 3
	draw_style_box(nub, Rect2(Vector2(body.size.x, size.y * 0.3), Vector2(nub_w - 1.0, size.y * 0.4)))
	# Заливка по HP.
	var inner := body.grow(-4.0)
	var f := fraction()
	if f > 0.0:
		var fill := StyleBoxFlat.new()
		var c := fill_color()
		if _flash > 0.0: c = c.lerp(Color(1, 1, 1), _flash * 1.6)
		fill.bg_color = c
		fill.set_corner_radius_all(r - 3)
		draw_style_box(fill, Rect2(inner.position, Vector2(maxf(4.0, inner.size.x * f), inner.size.y)))
