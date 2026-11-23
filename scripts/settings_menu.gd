extends Control
## v0.5: окно настроек (звук, яркость, прогрузка мира, сущности, тени, мышь). Общее для главного меню и паузы.

signal closed

const UiTheme := preload("res://scripts/ui_theme.gd")

var _rows: Dictionary = {}


func _ready() -> void:
	add_to_group("modal_menu") # v0.20: панель обучения прячется под меню
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _gs() -> Node:
	return get_node("/root/GameSettings")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.72) # v0.21: плотнее — меню паузы не просвечивает
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var solid := StyleBoxFlat.new() # v0.21: непрозрачная панель настроек
	solid.bg_color = Color(0.10, 0.09, 0.14, 1.0); solid.border_color = Color(0.40, 0.36, 0.50)
	solid.set_border_width_all(2); solid.set_corner_radius_all(10)
	solid.content_margin_left = 26; solid.content_margin_right = 26; solid.content_margin_top = 20; solid.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", solid)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiTheme.title_label("Настройки", 30))
	var g := _gs()
	_add_slider(box, "master_volume", "Общая громкость", 0, 100, 5, g.master_volume * 100.0, "%d%%", 0.01)
	_add_slider(box, "music_volume", "Музыка", 0, 100, 5, g.music_volume * 100.0, "%d%%", 0.01)
	_add_slider(box, "sfx_volume", "Звуки", 0, 100, 5, g.sfx_volume * 100.0, "%d%%", 0.01)
	_add_slider(box, "brightness", "Яркость", 50, 160, 5, g.brightness * 100.0, "%d%%", 0.01)
	_add_slider(box, "render_distance", "Прогрузка мира", g.RENDER_MIN, g.RENDER_MAX, 1, g.render_distance, "%d чанк.", 1.0)
	_add_slider(box, "entity_distance", "Дальность сущностей", g.ENTITY_MIN, g.ENTITY_MAX, 1, g.entity_distance, "%d чанк.", 1.0)
	_add_slider(box, "mouse_sensitivity", "Чувствительность мыши", 20, 400, 10, g.mouse_sensitivity * 100.0, "%d%%", 0.01)
	_add_slider(box, "fov", "Угол обзора", 60, 100, 1, g.fov, "%d°", 1.0)
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 18); box.add_child(r1)
	_add_check(r1, "shadows", "Тени от солнца", g.shadows)
	_add_check(r1, "fullscreen", "Полный экран", g.fullscreen)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 18); box.add_child(r2)
	_add_check(r2, "head_bob", "Покачивание камеры", g.head_bob)
	_add_check(r2, "camera_shake", "Тряска от ударов", g.camera_shake)
	_add_check(box, "dream_start", "Новый мир начинается во Сне — главном мире", g.dream_start)
	var note := Label.new()
	note.text = "1 чанк = 16×16 блоков. Меньше прогрузка/сущностей — больше FPS."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	box.add_child(note)
	var log_l := Label.new()
	log_l.name = "ErrorLog"
	log_l.text = "Журнал ошибок: " + str(g.error_log_path())
	log_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	log_l.add_theme_font_size_override("font_size", 12)
	log_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	box.add_child(log_l)
	var keys := Button.new()
	keys.name = "Keybinds"
	keys.text = "Управление и клавиши…"
	keys.custom_minimum_size = Vector2(0, 42)
	keys.pressed.connect(_open_keybinds)
	box.add_child(keys)
	var done := Button.new()
	done.name = "Done"
	done.text = "Готово"
	done.custom_minimum_size = Vector2(0, 46)
	done.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	box.add_child(done)


func _add_slider(box: VBoxContainer, key: String, label: String, mn: float, mx: float, step: float, value: float, fmt: String, scale: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(230, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(90, 0)
	v.text = fmt % int(round(value))
	row.add_child(v)
	s.value_changed.connect(func(nv: float) -> void:
		v.text = fmt % int(round(nv))
		_gs().set_value(key, nv * scale))
	_rows[key] = s


func _add_check(box: BoxContainer, key: String, label: String, on: bool) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = on
	c.toggled.connect(func(v: bool) -> void:
		_gs().set_value(key, v))
	box.add_child(c)
	_rows[key] = c


var _keybinds: Control = null


func _open_keybinds() -> void:
	var kb_script: GDScript = load("res://scripts/keybind_menu.gd")
	_keybinds = kb_script.new()
	_keybinds.process_mode = Node.PROCESS_MODE_ALWAYS
	_keybinds.closed.connect(func() -> void: _keybinds = null)
	add_child(_keybinds)


func _unhandled_input(event: InputEvent) -> void:
	if _keybinds != null and is_instance_valid(_keybinds):
		return
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
