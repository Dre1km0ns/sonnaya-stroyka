extends PanelContainer
## Только контекст: маленькая карточка слева, не над предметами и не в центре прицела.
var text_label: Label
var _last := ""
var _timer := 0.0
var _tween: Tween
func _ready() -> void:
	position = Vector2(10,330)
	custom_minimum_size = Vector2(260,70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05,0.04,0.09,0.7)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	add_theme_stylebox_override("panel",st)
	text_label = Label.new()
	text_label.custom_minimum_size.x = 240
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size",13)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	visible = false
func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0:
		return
	_timer = 0.2
	var text := ""
	# v0.22.1: подсказки Яви и шпаргалка Сна убраны — остаётся только помощь в строительстве во Сне.
	var pl = get_tree().get_first_node_in_group("player")
	if GameState.is_dream() and pl and pl.has_method("get_look_ray") and not GameState.ui_blocked():
		var aim: Dictionary = pl.get_look_ray()
		var col = aim.get("collider")
		if col and col.has_meta("voxel_cell"):
			var c: Vector3i = col.get_meta("voxel_cell")
			var id: String = str(GameState.dream_blocks.get(c, {}).get("kind", ""))
			if id != "":
				text = GameState.block_display_name(id) + "\nПКМ — поставить рядом · ЛКМ — снять"
	_place_below_objectives()
	if text == _last:
		return
	_last = text
	visible = text != ""
	text_label.text = text
	if visible:
		if _tween:
			_tween.kill()
		position.x = -280
		_place_below_objectives()
		_tween = create_tween()
		_tween.tween_property(self,"position:x",10.0,0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _place_below_objectives() -> void:
	## v0.21: карточка контекста встаёт под панель целей — панели больше не наезжают друг на друга.
	var y := 136.0
	var op := get_tree().get_first_node_in_group("objective_panel") as Control
	if op and op.visible:
		y = op.position.y + op.size.y + 8.0
	position.y = y
