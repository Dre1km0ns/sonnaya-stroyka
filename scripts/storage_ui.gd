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
	if not catcher:
		_set_lid(true)
		Sfx.play("chest_open", get_tree().root if is_inside_tree() else null)
	_refresh()

func close() -> void:
	GameState.modal_closed_frame = Engine.get_process_frames()
	var was_open := _open
	_open = false
	visible = false
	GameState.storage_open = false
	if was_open and not catcher:
		_set_lid(false)
		Sfx.play("chest_close", get_tree().root if is_inside_tree() else null)
	if not GameState.paused and not GameState.inventory_open and not GameState.pillow_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

const Sfx := preload("res://scripts/sfx.gd")
var lid_open_calls := 0

func _set_lid(on: bool) -> void:
	## Анимация крышки у визуала сундука текущего мира.
	if not is_inside_tree():
		return
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if bool(vox.get("is_dream_layer")) == GameState.is_dream() and vox.has_method("set_chest_open"):
			if vox.set_chest_open(cell, on):
				lid_open_calls += 1

func _take(i: int, button: int, shift: bool) -> void:
	## ЛКМ — весь стак, ПКМ — половина, Shift+ЛКМ — все стаки этого предмета.
	var slots := GameState.storage_slots(cell, GameState.is_dream(), catcher)
	var d: Dictionary = slots[i]
	var id := str(d.get("id", ""))
	if id == "":
		return
	var ok := false
	if shift and button == MOUSE_BUTTON_LEFT:
		ok = GameState.storage_take_all(cell, id, catcher) > 0
	elif button == MOUSE_BUTTON_RIGHT:
		ok = GameState.storage_take(cell, i, catcher, maxi(1, int(ceil(int(d.get("count", 0)) / 2.0))))
	else:
		ok = GameState.storage_take(cell, i, catcher)
	_flash(_store_views[i], ok)
	_refresh()

func _deposit(i: int, button: int, shift: bool) -> void:
	var d := GameState.get_slot(i)
	var id := str(d.get("id", ""))
	if id == "":
		return
	var moved := 0
	if shift and button == MOUSE_BUTTON_LEFT:
		moved = GameState.storage_deposit_all(cell, id, catcher)
	elif button == MOUSE_BUTTON_RIGHT:
		moved = GameState.storage_deposit(cell, i, catcher, maxi(1, int(ceil(int(d.get("count", 0)) / 2.0))))
	else:
		moved = GameState.storage_deposit(cell, i, catcher)
	if moved <= 0 and not catcher:
		GameState.set_hint("Сундук полон.", false)
	_flash(_inv_views[i], moved > 0)
	_refresh()

func _flash(v: Control, ok: bool) -> void:
	if v == null or not is_inside_tree():
		return
	v.modulate = Color(1.5, 1.5, 1.0) if ok else Color(1.6, 0.6, 0.6)
	var tw := v.create_tween()
	tw.tween_property(v, "modulate", Color(1, 1, 1), 0.25)

func _refresh() -> void:
	if not _open:
		return
	var slots := GameState.storage_slots(cell, GameState.is_dream(), catcher)
	var used := 0
	for sl in slots:
		if str(sl.get("id", "")) != "": used += 1
	_title.text = "Ловец идей — тумбочка" if catcher else ("Сундук %s · занято %d/27" % ["Сна" if GameState.is_dream() else "Яви", used])
	_hint.text = "Сверху — сундук, снизу — твой инвентарь. ЛКМ — весь стак · ПКМ — половина · Shift+ЛКМ — все такие предметы. Esc / Y — закрыть."
	if not catcher and GameState.is_dream():
		_hint.text += "\nСундук Сна: закрепи его якорем — при пробуждении содержимое перенесётся в Явь. Иначе вещи вернутся в инвентарь Сна."
	if catcher:
		_hint.text = ("Сон: только забрать блоки в инвентарь сна." if GameState.is_dream() else "Явь: положи стопку от %d блоков одного типа — Сон станет длиннее навсегда (один раз на тип)." % GameState.IDEA_THRESHOLD) + " Бонус сна: +%d с из %d" % [int(GameState.dream_bonus_seconds), int(GameState.IDEA_BONUS_CAP)]
	for i in range(27):
		var d: Dictionary = slots[i]
		_store_views[i].set_item(str(d.get("id", "")), int(d.get("count", 0)))
		_store_views[i].set_durability(int(d.get("durability", GameState.tool_max(str(d.get("id", ""))))), GameState.tool_max(str(d.get("id", ""))))
	for i in range(36):
		var d := GameState.get_slot(i)
		_inv_views[i].set_item(str(d.get("id", "")), int(d.get("count", 0)))
		_inv_views[i].set_durability(int(d.get("durability", GameState.tool_max(str(d.get("id", ""))))), GameState.tool_max(str(d.get("id", ""))))

func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pillow_check")):
		close()
		get_viewport().set_input_as_handled()
