extends Control
## v0.5: инвентарь как в Minecraft — 27 слотов + 9 хотбара. Открывается I или Tab.
## ЛКМ — взять/положить/поменять стак, ПКМ — взять половину / положить один, Shift+ЛКМ — перенос хотбар↔рюкзак.

const SlotView := preload("res://scripts/slot_view.gd")
const ItemDB := preload("res://scripts/item_db.gd")

var _open := false
var _slots: Array = []
var _held: Dictionary = {}
var _held_from: int = -1
var _held_view: Control
var _title: Label
var _specials: Array = []


func _ready() -> void:
	add_to_group("inventory_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	GameState.inventory_changed.connect(_refresh)


func is_open() -> bool:
	return _open


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.15, 0.19, 0.97)
	sb.border_color = Color(0.45, 0.42, 0.5)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.text = "Инвентарь"
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	_slots.resize(GameState.ITEM_SLOT_COUNT)
	for i in range(GameState.HOTBAR_SIZE, GameState.ITEM_SLOT_COUNT):
		grid.add_child(_make_slot(i))
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	left.add_child(sep)
	var hot := HBoxContainer.new()
	hot.add_theme_constant_override("separation", 4)
	left.add_child(hot)
	for i in range(GameState.HOTBAR_SIZE):
		var s := _make_slot(i)
		s.set_key_hint(str(i + 1))
		hot.add_child(s)
	# Справа — особые предметы (только просмотр + выбор якоря кликом).
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	var cap := Label.new()
	cap.text = "Якоря / маяки"
	cap.add_theme_font_size_override("font_size", 13)
	right.add_child(cap)
	for sp in ItemDB.SPECIAL:
		var sv: Panel = SlotView.new()
		sv.index = int(sp["anchor"])
		sv.slot_clicked.connect(_on_special_clicked)
		right.add_child(sv)
		_specials.append([sv, str(sp["id"])])
	var help := Label.new()
	help.text = "ЛКМ — взять/положить   ПКМ — половина/один   Shift+ЛКМ — перенос   I / Tab / Esc — закрыть"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	box.add_child(help)
	_held_view = SlotView.new()
	_held_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_view.visible = false
	_held_view.z_index = 10
	_held_view.self_modulate = Color(1, 1, 1, 0)
	add_child(_held_view)


func _make_slot(i: int) -> Panel:
	var s: Panel = SlotView.new()
	s.index = i
	s.slot_clicked.connect(_on_slot_clicked)
	_slots[i] = s
	return s


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	GameState.inventory_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _held.is_empty():
		_return_held()
	_open = false
	visible = false
	GameState.inventory_open = false
	if not GameState.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_held() -> void:
	var id := str(_held.get("id", ""))
	var cnt := int(_held.get("count", 0))
	_held = {}
	_held_view.visible = false
	if id == "" or cnt <= 0:
		return
	if _held_from >= 0 and str(GameState.get_slot(_held_from).get("id", "")) == "":
		GameState.set_slot(_held_from, {"id": id, "count": cnt})
		return
	var added: int = GameState.add_item_count(id, cnt)
	if added < cnt:
		GameState.block_stash[id] = int(GameState.block_stash.get(id, 0)) + cnt - added


func _on_slot_clicked(i: int, button: int, shift: bool) -> void:
	var slot: Dictionary = GameState.get_slot(i).duplicate()
	var sid := str(slot.get("id", ""))
	var scount := int(slot.get("count", 0))
	if shift and button == MOUSE_BUTTON_LEFT and _held.is_empty():
		GameState.quick_move(i)
		return
	if button == MOUSE_BUTTON_LEFT:
		if _held.is_empty():
			if sid == "":
				return
			_held = slot
			_held_from = i
			GameState.set_slot(i, {})
		else:
			var hid := str(_held["id"])
			if sid == "":
				GameState.set_slot(i, _held)
				_held = {}
			elif sid == hid:
				var cap := ItemDB.max_stack(hid)
				var room := cap - scount
				var put := mini(room, int(_held["count"]))
				slot["count"] = scount + put
				GameState.set_slot(i, slot)
				_held["count"] = int(_held["count"]) - put
				if int(_held["count"]) <= 0:
					_held = {}
			else:
				GameState.set_slot(i, _held)
				_held = slot
				_held_from = i
	elif button == MOUSE_BUTTON_RIGHT:
		if _held.is_empty():
			if sid == "" or scount <= 0:
				return
			var take := int(ceil(scount / 2.0))
			_held = {"id": sid, "name": slot.get("name", sid), "count": take}
			_held_from = i
			slot["count"] = scount - take
			GameState.set_slot(i, slot)
		else:
			var hid2 := str(_held["id"])
			if sid == "" or (sid == hid2 and scount < ItemDB.max_stack(hid2)):
				GameState.set_slot(i, {"id": hid2, "count": scount + 1 if sid == hid2 else 1})
				_held["count"] = int(_held["count"]) - 1
				if int(_held["count"]) <= 0:
					_held = {}
	_refresh()


func _on_special_clicked(anchor_index: int, _button: int, _shift: bool) -> void:
	if anchor_index >= 0:
		GameState.select_anchor(anchor_index as GameState.AnchorType)


func _refresh() -> void:
	if not visible:
		return
	_title.text = "Инвентарь" + ("   [DEV-сид: всё бесконечно]" if GameState.dev_mode else "")
	for i in range(_slots.size()):
		var s = _slots[i]
		if s == null:
			continue
		var d: Dictionary = GameState.get_slot(i)
		var id := str(d.get("id", ""))
		s.set_item(id, int(d.get("count", 0)), i == GameState.selected_slot, GameState.is_infinite_slot(i))
	for pair in _specials:
		var sv = pair[0]
		var sid: String = pair[1]
		var cnt: int = GameState.special_display_count(sid)
		var sel: bool = sv.index >= 0 and sv.index == int(GameState.selected_anchor)
		sv.set_item(sid, cnt, sel, cnt >= GameState.INF_COUNT, true)
	if _held.is_empty():
		_held_view.visible = false
	else:
		_held_view.visible = true
		_held_view.set_item(str(_held["id"]), int(_held["count"]), false, GameState.dev_mode)


func _process(_delta: float) -> void:
	if _held_view.visible:
		_held_view.position = get_local_mouse_position() - Vector2(26, 26)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.paused or GameState.craft_menu_open:
		return
	if event.is_action_pressed("open_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
