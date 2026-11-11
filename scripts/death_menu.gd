extends Control
## v0.7: меню смерти — «Возродиться» (у последней кровати) и «Выйти из мира» (с сохранением).

signal respawn_pressed
signal exit_pressed

var _open := false
var _info: Label


func _ready() -> void:
	add_to_group("death_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func is_open() -> bool:
	return _open


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.35, 0.02, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = "Вы погибли"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.8))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 16)
	box.add_child(_info)
	var b1 := Button.new()
	b1.name = "Respawn"
	b1.text = "Возродиться"
	b1.custom_minimum_size = Vector2(0, 46)
	b1.pressed.connect(func() -> void: respawn_pressed.emit())
	box.add_child(b1)
	var b2 := Button.new()
	b2.name = "Exit"
	b2.text = "Выйти из мира (сохранить)"
	b2.custom_minimum_size = Vector2(0, 46)
	b2.pressed.connect(func() -> void: exit_pressed.emit())
	box.add_child(b2)


func open(info: String) -> void:
	_open = true
	visible = true
	_info.text = info
	GameState.death_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	visible = false
	GameState.death_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
