extends Control
## Меню крафта: осыпь / верстак во сне / инструменты у верстака в яви.

var _open: bool = false
var _at_workbench: bool = false
var _panel: VBoxContainer
var _title: Label


func _ready() -> void:
	add_to_group("craft_menu")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func is_open() -> bool:
	return _open


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230.0
	panel.offset_right = 230.0
	panel.offset_top = -220.0
	panel.offset_bottom = 220.0
	add_child(panel)
	_panel = VBoxContainer.new()
	_panel.name = "List"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 16
	_panel.offset_right = -16
	_panel.offset_top = 12
	_panel.offset_bottom = -12
	_panel.add_theme_constant_override("separation", 8)
	panel.add_child(_panel)
	_title = Label.new()
	_title.text = "Крафт"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_title)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "C / Esc — закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	_panel.add_child(hint)


func open_general() -> void:
	_at_workbench = false
	_show()


func open_workbench() -> void:
	_at_workbench = true
	_show()


func toggle() -> void:
	if _open:
		close()
	else:
		open_general()


func close() -> void:
	_open = false
	_at_workbench = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameState:
		GameState.craft_menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show() -> void:
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if GameState:
		GameState.craft_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func _rebuild() -> void:
	for ch in _panel.get_children():
		if ch is Button:
			ch.queue_free()
	_title.text = "Верстак: инструменты" if _at_workbench else "Крафт"
	var ctx := {"is_dream": GameState.is_dream(), "at_workbench": _at_workbench}
	var recipes: Array = GameState.get_visible_recipes(ctx)
	if recipes.is_empty():
		var empty := Label.new()
		empty.text = "Нет доступных рецептов."
		_panel.add_child(empty)
		return
	for rec in recipes:
		var btn := Button.new()
		btn.text = GameState.recipe_label(rec)
		btn.disabled = not GameState.can_afford_recipe(rec)
		var rid := str(rec.get("id", ""))
		btn.pressed.connect(_craft.bind(rid))
		_panel.add_child(btn)


func _craft(rid: String) -> void:
	var ctx := {"is_dream": GameState.is_dream(), "at_workbench": _at_workbench}
	if GameState.craft_recipe(rid, ctx):
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("craft_nail"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
