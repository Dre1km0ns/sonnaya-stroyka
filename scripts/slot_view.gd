extends Panel
## v0.5: ячейка инвентаря/хотбара: иконка предмета + количество в правом верхнем углу.

const ItemDB := preload("res://scripts/item_db.gd")

signal slot_clicked(index: int, button: int, shift: bool)

var index: int = -1
var _icon: TextureRect
var _count: Label
var _key: Label
var _style_normal: StyleBoxFlat
var _style_sel: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _selected := false
var _hover := false
var item_id: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(52, 52)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style_normal = _make_style(Color(0.10, 0.10, 0.13, 0.82), Color(0.32, 0.30, 0.36, 1.0), 2)
	_style_sel = _make_style(Color(0.20, 0.17, 0.10, 0.92), Color(1.0, 0.86, 0.45, 1.0), 3)
	_style_hover = _make_style(Color(0.18, 0.18, 0.24, 0.9), Color(0.6, 0.6, 0.7, 1.0), 2)
	add_theme_stylebox_override("panel", _style_normal)
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 5
	_icon.offset_top = 5
	_icon.offset_right = -5
	_icon.offset_bottom = -5
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_icon)
	_count = Label.new()
	_count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_count.offset_left = -40
	_count.offset_right = -3
	_count.offset_top = 0
	_count.offset_bottom = 20
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 15)
	_count.add_theme_color_override("font_color", Color(1, 1, 1))
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_count.add_theme_constant_override("outline_size", 5)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_key = Label.new()
	_key.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_key.offset_left = 4
	_key.offset_top = -17
	_key.offset_right = 20
	_key.offset_bottom = -1
	_key.add_theme_font_size_override("font_size", 11)
	_key.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.7))
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.visible = false
	add_child(_key)
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_restyle())


func _make_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	return sb


func set_slot_size(px: int) -> void:
	custom_minimum_size = Vector2(px, px)


func set_key_hint(text: String) -> void:
	_key.text = text
	_key.visible = text != ""


func set_item(id: String, count: int, selected: bool = false, infinite: bool = false, always_show_count: bool = false) -> void:
	item_id = id
	_selected = selected
	if id == "":
		_icon.texture = null
		_count.text = ""
		tooltip_text = ""
	else:
		_icon.texture = ItemDB.icon(id)
		if infinite:
			_count.text = "∞"
		elif count > 1 or always_show_count:
			_count.text = str(count)
		else:
			_count.text = ""
		tooltip_text = ItemDB.display_name(id)
	_icon.modulate = Color(1, 1, 1, 1) if (count > 0 or infinite or not always_show_count) else Color(1, 1, 1, 0.35)
	_restyle()


func _restyle() -> void:
	if _selected:
		add_theme_stylebox_override("panel", _style_sel)
	elif _hover and mouse_filter == Control.MOUSE_FILTER_STOP:
		add_theme_stylebox_override("panel", _style_hover)
	else:
		add_theme_stylebox_override("panel", _style_normal)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			slot_clicked.emit(index, event.button_index, event.shift_pressed)
			accept_event()


var _durability := -1
var _durability_max := 0
func set_durability(value: int, maximum: int) -> void:
	_durability = value
	_durability_max = maximum
	queue_redraw()

func _draw() -> void:
	if _durability_max > 0:
		var ratio := clampf(float(_durability) / _durability_max, 0.0, 1.0)
		draw_rect(Rect2(5, size.y - 7, size.x - 10, 4), Color(0.04, 0.04, 0.04))
		draw_rect(Rect2(5, size.y - 7, (size.x - 10) * ratio, 4), Color(1.0 - ratio, ratio, 0.15))
