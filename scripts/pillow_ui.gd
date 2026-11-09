extends Control
## v0.7: «Под подушкой» — окно как сундук в Minecraft (27 ячеек), только ЗАБИРАТЬ.
## Хилки, скрафченные во сне, появляются здесь у любой кровати в яви (хранилище общее).

const SlotView := preload("res://scripts/slot_view.gd")

var _open := false
var _slots: Array = []
var _title: Label
var _hint: Label


func _ready() -> void:
	add_to_group("pillow_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	GameState.pillow_changed.connect(_refresh)
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
	sb.bg_color = Color(0.30, 0.22, 0.14, 0.97)
	sb.border_color = Color(0.62, 0.46, 0.28)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
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
	_title.text = "Под подушкой"
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in range(GameState.PILLOW_SIZE):
		var s: Panel = SlotView.new()
		s.index = i
		s.slot_clicked.connect(_on_click)
		grid.add_child(s)
		_slots.append(s)
	_hint = Label.new()
	_hint.text = "ЛКМ — забрать в инвентарь яви   ·   положить сюда нельзя   ·   Esc / Y — закрыть"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	box.add_child(_hint)


func open() -> void:
	if GameState.is_dream():
		return
	_open = true
	visible = true
	GameState.pillow_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_open = false
	visible = false
	GameState.pillow_open = false
	if not GameState.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func take(i: int) -> bool:
	var ok := GameState.take_from_pillow(i)
	_refresh()
	return ok


func _on_click(i: int, _button: int, _shift: bool) -> void:
	take(i)


func _refresh() -> void:
	if not visible:
		return
	var n := 0
	for i in range(_slots.size()):
		var d: Dictionary = GameState.pillow[i] if i < GameState.pillow.size() else {}
		var id := str(d.get("id", ""))
		_slots[i].set_item(id, int(d.get("count", 0)))
		if id != "":
			n += int(d.get("count", 0))
	_title.text = "Под подушкой" + ("  — пусто (крафт хилок во сне: 50 осыпи)" if n == 0 else "")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pillow_check"):
		close()
		get_viewport().set_input_as_handled()
