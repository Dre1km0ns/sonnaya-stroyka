extends CanvasLayer
## v0.5: пауза по Esc — продолжить, настройки, сохранить, выйти в главное меню.

const UiTheme := preload("res://scripts/ui_theme.gd")

var _root: Control
var _settings: Control = null
var _status: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.make()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiTheme.title_label("Пауза", 32))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
	box.add_child(_status)
	_btn(box, "Продолжить", resume)
	_btn(box, "Настройки", _open_settings)
	_btn(box, "Сохранить", func() -> void:
		var ok := _save("manual")
		_status.text = "Сохранено." if ok else "Сохранение не удалось.")
	_btn(box, "Сохранить и выйти в меню", _quit_to_menu)


func _btn(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(cb)
	box.add_child(b)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	GameState.paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "Мир: %s   ·   сид %s%s" % [GameState.world_name if GameState.world_name != "" else "без сохранения",
		str(GameState.world_seed), "   ·   DEV" if GameState.dev_mode else ""]


func resume() -> void:
	if _settings and is_instance_valid(_settings):
		_settings.queue_free()
		_settings = null
	_root.visible = false
	GameState.paused = false
	get_tree().paused = false
	if not GameState.inventory_open and not GameState.craft_menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	var sm_script: GDScript = load("res://scripts/settings_menu.gd")
	_settings = sm_script.new()
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings.closed.connect(func() -> void: _settings = null)
	_root.add_child(_settings)


func _save(reason: String) -> bool:
	var saver := get_tree().current_scene.get_node_or_null("Systems/SaveSystem")
	if saver and saver.has_method("save_game"):
		return bool(saver.save_game(reason))
	return false


func _quit_to_menu() -> void:
	_save("quit-menu")
	get_tree().paused = false
	GameState.paused = false
	GameState.inventory_open = false
	GameState.craft_menu_open = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if GameState.console_open or GameState.transfer_ui_open: return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings != null and is_instance_valid(_settings):
		return
	if _root.visible:
		resume()
		get_viewport().set_input_as_handled()
		return
	if GameState.inventory_open or GameState.craft_menu_open:
		return
	open()
	get_viewport().set_input_as_handled()
