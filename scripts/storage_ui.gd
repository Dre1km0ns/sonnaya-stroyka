extends Control
## Сундук / Ловец идей. Атомарные переносы без перетаскиваемого стека.
const SlotView := preload("res://scripts/slot_view.gd")
var cell := Vector3i.ZERO
var catcher := false
var _open := false
var _store_views: Array = []
var _inv_views: Array = []
var _title: Label
var _hint: Label

func _ready() -> void:
	add_to_group("storage_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.14, 0.22)
	style.border_color = Color(0.52, 0.42, 0.68)
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	var store := GridContainer.new()
	store.columns = 9
	box.add_child(store)
	for i in range(27):
		var v := SlotView.new()
		v.set_slot_size(42)
		v.index = i
		v.slot_clicked.connect(_take)
		store.add_child(v)
		_store_views.append(v)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.custom_minimum_size.x = 430
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	var inv := GridContainer.new()
	inv.columns = 9
	box.add_child(inv)
	for i in range(36):
		var v := SlotView.new()
		v.set_slot_size(42)
		v.index = i
		v.slot_clicked.connect(_deposit)
		inv.add_child(v)
		_inv_views.append(v)
	var close_btn := Button.new()
	close_btn.text = "Закрыть (Esc / Y)"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	GameState.inventory_changed.connect(_refresh)
	GameState.world_changed.connect(func(_d: bool) -> void: close())

func open(at: Vector3i, is_catcher: bool) -> void:
	cell = at
	catcher = is_catcher
	_open = true
	visible = true
	GameState.storage_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	GameState.modal_closed_frame = Engine.get_process_frames()
	_open = false
	visible = false
	GameState.storage_open = false
	if not GameState.paused and not GameState.inventory_open and not GameState.pillow_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _take(i: int, _button: int, _shift: bool) -> void:
	GameState.storage_take(cell, i, catcher)
	_refresh()

func _deposit(i: int, _button: int, _shift: bool) -> void:
	GameState.storage_deposit(cell, i, catcher)
	_refresh()

func _refresh() -> void:
	if not _open:
		return
	_title.text = "Ловец идей — тумбочка" if catcher else "Сундук"
	_hint.text = "Верхние ячейки — забрать. Нижние — положить весь стек. Esc / Y — закрыть."
	if catcher:
		_hint.text = ("Сон: только забрать блоки в инвентарь сна." if GameState.is_dream() else "Явь: только положить блоки. Ровно 100: бонус один раз на тип.") + " Бонус сна: +%d с" % GameState.dream_bonus_seconds
	var slots := GameState.storage_slots(cell)
	for i in range(27):
		var d: Dictionary = slots[i]
		_store_views[i].set_item(str(d.get("id", "")), int(d.get("count", 0)))
	for i in range(36):
		var d := GameState.get_slot(i)
		_inv_views[i].set_item(str(d.get("id", "")), int(d.get("count", 0)))
		_inv_views[i].set_durability(int(d.get("durability", GameState.tool_max(str(d.get("id", ""))))), GameState.tool_max(str(d.get("id", ""))))

func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pillow_check")):
		close()
		get_viewport().set_input_as_handled()
