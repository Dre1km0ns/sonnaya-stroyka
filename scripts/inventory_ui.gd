extends Control
## v0.5: инвентарь как в Minecraft — 27 слотов + 9 хотбара. Открывается I или Tab.
## ЛКМ — взять/положить/поменять стак, ПКМ — взять половину / положить один, Shift+ЛКМ — перенос хотбар↔рюкзак.

const SlotView := preload("res://scripts/slot_view.gd")
const ArmorPlaceholder := preload("res://scripts/armor_placeholder.gd")
const ItemDB := preload("res://scripts/item_db.gd")

var _open := false
var _slots: Array = []
var _held: Dictionary = {}
var _held_from: int = -1
var _held_view: Control
var _title: Label
var _specials: Array = []
var _pouch: Array = []
var _armor_views: Array = []
var _armor_caption: Label


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
	# Якоря остаются рабочими: горизонтально под хотбаром в обоих мирах.
	var special_box := VBoxContainer.new()
	special_box.name = "AnchorsRow"
	special_box.add_theme_constant_override("separation", 4)
	left.add_child(special_box)
	var cap := Label.new()
	cap.text = "Якоря / маяки"
	cap.add_theme_font_size_override("font_size", 13)
	special_box.add_child(cap)
	var special_row := HBoxContainer.new()
	special_row.add_theme_constant_override("separation", 6)
	special_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	special_box.add_child(special_row)
	for sp in ItemDB.SPECIAL:
		var sv: Panel = SlotView.new()
		sv.index = int(sp["anchor"])
		sv.custom_minimum_size = Vector2(117, 92)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.set_meta("standing_figure", true)
		sv._icon.offset_left = 18
		sv._icon.offset_right = -18
		sv._icon.offset_top = 6
		sv._icon.offset_bottom = -6
		sv.slot_clicked.connect(_on_special_clicked)
		special_row.add_child(sv)
		_specials.append([sv, str(sp["id"])])
	# v0.11.1: никаких текстовых подсказок в инвентаре (по просьбе игрока).
	# Броня и кошель.
	var right := VBoxContainer.new()
	right.name = "ArmorAndPouch"
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	var armor_cap := Label.new()
	armor_cap.text = "Броня"
	_armor_caption = armor_cap
	armor_cap.add_theme_font_size_override("font_size", 13)
	right.add_child(armor_cap)
	for ai in range(4):
		var armor_name: String = GameState.ArmorRules.NAMES[ai]
		var armor_row := HBoxContainer.new()
		armor_row.add_theme_constant_override("separation", 8)
		right.add_child(armor_row)
		var empty_slot: Panel = SlotView.new()
		empty_slot.name = "ArmorSlot" + str(armor_row.get_index())
		empty_slot.index = ai
		empty_slot.slot_clicked.connect(_on_armor_clicked)
		armor_row.add_child(empty_slot)
		var silhouette := ArmorPlaceholder.new()
		silhouette.kind = ai
		silhouette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_slot.add_child(silhouette)
		_armor_views.append([empty_slot,silhouette])
		var armor_label := Label.new()
		armor_label.text = armor_name
		armor_label.add_theme_font_size_override("font_size", 13)
		armor_row.add_child(armor_label)
	var pouch_gap := Control.new()
	pouch_gap.custom_minimum_size.y = 8
	right.add_child(pouch_gap)
	var pcap := Label.new()
	pcap.text = "Кошель (общий)"
	pcap.add_theme_font_size_override("font_size", 13)
	right.add_child(pcap)
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 4)
	pgrid.add_theme_constant_override("v_separation", 4)
	right.add_child(pgrid)
	for pid in ["reagent1", "reagent2", "reagent3", "dust"]:
		var pv: Panel = SlotView.new()
		pv.mouse_filter = Control.MOUSE_FILTER_PASS
		pgrid.add_child(pv)
		_pouch.append([pv, pid])
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
	var payload := _held.duplicate(true)
	var id := str(_held.get("id", ""))
	var cnt := int(_held.get("count", 0))
	_held = {}
	_held_view.visible = false
	if id == "" or cnt <= 0:
		return
	if _held_from >= 0 and str(GameState.get_slot(_held_from).get("id", "")) == "":
		GameState.set_slot(_held_from, payload)
		return
	for i in range(GameState.ITEM_SLOT_COUNT):
		if GameState.get_slot(i).get("id", "") == "":
			GameState.set_slot(i,payload)
			return
	var ai := GameState.ArmorRules.slot(id)
	if ai>=0 and GameState.armor[ai].is_empty():
		GameState.armor[ai] = payload
		GameState.inventory_changed.emit()
		return
	# Taking equipped armour creates an equipment vacancy rather than an inventory vacancy.
	# If it was swapped with an inventory tool, restore the armour there first (no lost durability).
	for part in range(4):
		if not GameState.armor[part].is_empty(): continue
		for j in range(GameState.ITEM_SLOT_COUNT):
			var candidate: Dictionary = GameState.get_slot(j)
			if GameState.ArmorRules.slot(candidate.get("id",""))==part:
				GameState.armor[part] = candidate.duplicate(true)
				GameState.set_slot(j,payload)
				return
	var added: int = GameState.add_item_count(id, cnt)
	if added < cnt:
		GameState.block_stash[id] = int(GameState.block_stash.get(id, 0)) + cnt - added


func _on_slot_clicked(i: int, button: int, shift: bool) -> void:
	var slot: Dictionary = GameState.get_slot(i).duplicate()
	var sid := str(slot.get("id", ""))
	var scount := int(slot.get("count", 0))
	if shift and button == MOUSE_BUTTON_LEFT and _held.is_empty():
		if GameState.equip_armor_from_slot(i): return
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
			_held = slot.duplicate(true)
			_held["count"] = take
			_held_from = i
			slot["count"] = scount - take
			GameState.set_slot(i, slot)
		else:
			var hid2 := str(_held["id"])
			if sid == "" or (sid == hid2 and scount < ItemDB.max_stack(hid2)):
				var one := _held.duplicate(true)
				one["count"] = scount + 1 if sid == hid2 else 1
				GameState.set_slot(i, one)
				_held["count"] = int(_held["count"]) - 1
				if int(_held["count"]) <= 0:
					_held = {}
	_refresh()


func _on_special_clicked(anchor_index: int, _button: int, _shift: bool) -> void:
	if anchor_index >= 0:
		GameState.select_anchor(anchor_index as GameState.AnchorType)


func _refresh() -> void:

	if _armor_caption: _armor_caption.text = "Броня • %d защиты" % GameState.armor_points()
	if not visible:
		return
	_title.text = ("Инвентарь сна" if GameState.is_dream() else "Инвентарь яви") 
	for i in range(4):
		var d: Dictionary = GameState.armor[i]
		var id: String = d.get("id","")
		_armor_views[i][0].set_item(id,1 if id!="" else 0,false,false)
		_armor_views[i][0].set_durability(d.get("durability",GameState.tool_max(id)),GameState.tool_max(id))
		_armor_views[i][1].visible = id==""
	for pp in _pouch:
		var pcnt: int = GameState.count_item(str(pp[1]))
		pp[0].set_item(str(pp[1]), pcnt, false, pcnt >= GameState.INF_COUNT, true)
	for i in range(_slots.size()):
		var s = _slots[i]
		if s == null:
			continue
		var d: Dictionary = GameState.get_slot(i)
		var id := str(d.get("id", ""))
		s.set_item(id, int(d.get("count", 0)), i == GameState.selected_slot, GameState.is_infinite_slot(i))
		s.set_durability(int(d.get("durability", GameState.tool_max(id))), GameState.tool_max(id))
	for pair in _specials:
		var sv = pair[0]
		var sid: String = pair[1]
		var cnt: int = GameState.special_display_count(sid)
		var sel: bool = sv.index >= 0 and sv.index == int(GameState.selected_anchor)
		sv.set_item(sid, cnt, sel, cnt >= GameState.INF_COUNT, true)
		sv._icon.texture = load("res://assets/icons/standing_%s.png" % sid)
	if _held.is_empty():
		_held_view.visible = false
	else:
		_held_view.visible = true
		_held_view.set_item(str(_held["id"]), int(_held["count"]), false, GameState.dev_mode)


func _process(_delta: float) -> void:
	if _held_view.visible:
		_held_view.position = get_local_mouse_position() - Vector2(26, 26)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.console_open: return
	if GameState.paused or GameState.craft_menu_open:
		return
	if event.is_action_pressed("open_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_armor_clicked(i: int,_button: int,_shift: bool) -> void:
	if not _held.is_empty() and GameState.ArmorRules.slot(_held.get("id",""))!=i: return
	var old: Dictionary = GameState.armor[i].duplicate(true)
	GameState.armor[i] = _held.duplicate(true)
	_held = old
	_held_from = -1
	GameState.inventory_changed.emit()
	_refresh()
