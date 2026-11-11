extends Control
## Центрированное модальное меню крафта: список, стоимость, доступность, выбор и кнопка.

var _open: bool = false
var _at_workbench: bool = false
var _at_lathe: bool = false
var _station_id := ""
var _upgraded := false
var _selected: int = 0
var _recipes: Array = []
var _title: Label
var _list: VBoxContainer
var _status: Label
var _craft_btn: Button
var _rows: Array[Button] = []


func _ready() -> void:
	add_to_group("craft_menu")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	_build()


func is_open() -> bool:
	return _open


func is_centered_modal() -> bool:
	return has_node("Center") and has_node("Center/Panel")


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(700, 460)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_title = Label.new()
	_title.text = "Крафт"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	box.add_child(_title)
	var sub := Label.new()
	sub.name = "Sub"
	sub.text = "Выбери рецепт и нажми «Создать»"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	box.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "RecipeList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_craft_btn = Button.new()
	_craft_btn.text = "Создать"
	_craft_btn.custom_minimum_size = Vector2(0, 40)
	_craft_btn.pressed.connect(_craft_selected)
	box.add_child(_craft_btn)
	var hint := Label.new()
	hint.text = "1–9 выбрать   Enter создать   C / Esc закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)


func open_general() -> void:
	_station_id = ""
	_at_workbench = false
	_at_lathe = false
	_show()


func open_workbench() -> void:
	_station_id = ""
	_at_workbench = true
	_at_lathe = false
	_show()


func open_lathe() -> void:
	## v0.7: Станок — свой список рецептов (без верстачных).
	_at_workbench = false
	_station_id = ""
	_at_lathe = true
	_show()


func station() -> String:
	return "lathe" if _at_lathe else ("workbench" if _at_workbench else "")


func visible_recipe_ids() -> Array:
	var out: Array = []
	for r in _recipes:
		out.append(str(r.get("id", "")))
	return out


func _ctx() -> Dictionary:
	return {"station": _station_id, "upgraded": _upgraded, "is_dream": GameState.is_dream(), "at_workbench": _at_workbench, "at_lathe": _at_lathe}


func toggle() -> void:
	if _open:
		close()
	else:
		open_general()


func close() -> void:
	_open = false
	_station_id = ""
	_at_workbench = false
	_at_lathe = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameState:
		GameState.craft_menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show() -> void:
	_open = true
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	if GameState:
		GameState.craft_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_selected = 0
	_rebuild()


func _rebuild() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	_rows.clear()
	_title.text = "Станок" if _at_lathe else ("Верстак" if _at_workbench else "Крафт")
	if _station_id != "":
		_title.text = "Лесопилка" if _station_id == "sawmill" else "Алхимический стол"
	var ctx := _ctx()
	_recipes = GameState.get_visible_recipes(ctx)
	if _recipes.is_empty():
		_status.text = "Нет доступных рецептов."
		_craft_btn.disabled = true
		return
	_selected = clampi(_selected, 0, _recipes.size() - 1)
	for i in range(_recipes.size()):
		var rec: Dictionary = _recipes[i]
		var can := GameState.can_afford_recipe(rec)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = i == _selected
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var mark := "можно" if can else "не хватает"
		btn.text = "%d. %s  —  %s  [%s]" % [i + 1, str(rec.get("name", "?")), GameState.recipe_cost_text(rec), mark]
		btn.disabled = false
		btn.modulate = Color.WHITE if can else Color(1, 1, 1, 0.55)
		btn.pressed.connect(_select.bind(i))
		_list.add_child(btn)
		_rows.append(btn)
	_refresh_status()


func _select(i: int) -> void:
	_selected = clampi(i, 0, maxi(_recipes.size() - 1, 0))
	for r in range(_rows.size()):
		_rows[r].set_pressed_no_signal(r == _selected)
	_refresh_status()


func _refresh_status() -> void:
	if _recipes.is_empty():
		_craft_btn.disabled = true
		return
	var rec: Dictionary = _recipes[_selected]
	var can := GameState.can_afford_recipe(rec)
	_status.text = "Выбрано: %s (%s)" % [str(rec.get("name", "?")), "хватит ресурсов" if can else "мало ресурсов"]
	_craft_btn.disabled = not can
	_craft_btn.text = "Создать: %s" % str(rec.get("name", "?"))


func _craft_selected() -> void:
	if _recipes.is_empty():
		return
	var rec: Dictionary = _recipes[_selected]
	var ctx := _ctx()
	if GameState.craft_recipe(str(rec.get("id", "")), ctx):
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.console_open: return
	if GameState.paused or GameState.inventory_open:
		return
	if event.is_action_pressed("craft_nail"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP:
			_select(_selected - 1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_select(_selected + 1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_craft_selected()
			get_viewport().set_input_as_handled()


func open_station(id: String, upgraded: bool = false) -> void:
	_at_workbench = false
	_at_lathe = false
	_station_id = id
	_upgraded = upgraded
	_show()
