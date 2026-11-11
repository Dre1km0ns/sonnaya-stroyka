extends RefCounted
## v0.5: общая тема меню (кнопки, панели, поля, слайдеры).

static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var btn := _box(Color(0.20, 0.19, 0.26, 0.92), Color(0.42, 0.38, 0.52), 2, 6)
	var btn_h := _box(Color(0.30, 0.27, 0.40, 0.96), Color(1.0, 0.82, 0.55), 2, 6)
	var btn_p := _box(Color(0.14, 0.13, 0.18, 0.96), Color(1.0, 0.82, 0.55), 2, 6)
	var btn_d := _box(Color(0.14, 0.14, 0.16, 0.7), Color(0.25, 0.25, 0.28), 2, 6)
	for st in ["normal", "focus"]:
		t.set_stylebox(st, "Button", btn if st == "normal" else btn_h)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_color("font_color", "Button", Color(0.95, 0.93, 0.98))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.6))
	t.set_font_size("font_size", "Button", 20)
	var panel := _box(Color(0.10, 0.09, 0.14, 0.88), Color(0.40, 0.36, 0.50), 2, 10)
	panel.content_margin_left = 26
	panel.content_margin_right = 26
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	t.set_stylebox("panel", "PanelContainer", panel)
	var le := _box(Color(0.06, 0.06, 0.09, 0.95), Color(0.40, 0.36, 0.50), 2, 4)
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 6
	le.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le)
	var le_f := le.duplicate() as StyleBoxFlat
	le_f.border_color = Color(1.0, 0.82, 0.55)
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.6, 0.66))
	t.set_font_size("font_size", "Label", 18)
	var grab := _box(Color(1.0, 0.82, 0.55), Color(1.0, 0.9, 0.7), 1, 4)
	var slider := _box(Color(0.06, 0.06, 0.09, 0.95), Color(0.4, 0.36, 0.5), 1, 4)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var item_sel := _box(Color(0.30, 0.27, 0.40, 0.96), Color(1.0, 0.82, 0.55), 1, 4)
	t.set_stylebox("panel", "ItemList", _box(Color(0.06, 0.06, 0.09, 0.9), Color(0.40, 0.36, 0.50), 2, 6))
	t.set_stylebox("selected", "ItemList", item_sel)
	t.set_stylebox("selected_focus", "ItemList", item_sel)
	t.set_font_size("font_size", "ItemList", 18)
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func title_label(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.78))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.18))
	l.add_theme_constant_override("outline_size", 8)
	return l
