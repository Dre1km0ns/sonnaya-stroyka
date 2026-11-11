extends Control
## v0.6: переназначение управления. Клик по кнопке → «Нажми клавишу…» → следующая клавиша или кнопка мыши.
## Esc отменяет. Если клавиша занята другим действием — они меняются местами (сообщение внизу).
## Сохраняется в user://settings.cfg [keybinds], применяется при запуске (GameSettings.apply_bindings).

signal closed

const UiTheme := preload("res://scripts/ui_theme.gd")

var _buttons: Dictionary = {} # action -> Button
var _waiting: String = ""
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _gs() -> Node:
	return get_node("/root/GameSettings")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.07, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiTheme.title_label("Управление", 28))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for row in _gs().BINDABLE:
		var action: String = row[0]
		var l := Label.new()
		l.text = str(row[1])
		l.custom_minimum_size = Vector2(400, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := Button.new()
		b.name = "Bind_" + action
		b.custom_minimum_size = Vector2(200, 34)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_start_wait.bind(action))
		grid.add_child(b)
		_buttons[action] = b
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	_status.text = "Клик по кнопке — затем нажми клавишу или кнопку мыши. Esc — отмена. Пауза всегда на Esc."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	box.add_child(hb)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Сбросить по умолчанию"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		_gs().reset_bindings()
		_waiting = ""
		_status.text = "Управление сброшено по умолчанию."
		_refresh())
	hb.add_child(reset)
	var done := Button.new()
	done.name = "Done"
	done.text = "Готово"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(_close)
	hb.add_child(done)
	_refresh()


func _refresh() -> void:
	for a in _buttons.keys():
		var b: Button = _buttons[a]
		b.text = "Нажми…" if a == _waiting else _gs().key_label(a)


func _start_wait(action: String) -> void:
	_waiting = action
	_status.text = "«%s»: нажми новую клавишу или кнопку мыши (Esc — отмена)." % _gs().action_title(action)
	_refresh()


func capture(ev: InputEvent) -> bool:
	## Публично для тестов: применить событие к ожидающему действию.
	if _waiting == "":
		return false
	if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_waiting = ""
		_status.text = "Отменено."
		_refresh()
		return true
	var b: Dictionary = _gs().binding_from_event(ev)
	if b.is_empty():
		return false
	var action := _waiting
	_waiting = ""
	var other: String = _gs().rebind(action, b)
	if other != "":
		_status.text = "«%s» → %s. Конфликт: «%s» теперь на %s." % [
			_gs().action_title(action), _gs().key_label(action), _gs().action_title(other), _gs().key_label(other)]
	else:
		_status.text = "«%s» → %s." % [_gs().action_title(action), _gs().key_label(action)]
	_refresh()
	return true


func _input(event: InputEvent) -> void:
	if _waiting == "":
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN
	if not pressed:
		return
	if capture(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting == "" and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
