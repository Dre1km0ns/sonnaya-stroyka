extends PanelContainer
## Только контекст: маленькая карточка слева, не над предметами и не в центре прицела.
var text_label: Label
var _last := ""
var _timer := 0.0
var _tween: Tween
func _ready() -> void:
	position = Vector2(10,155)
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
	var pl = get_tree().get_first_node_in_group("player")
	if pl and pl.has_method("get_look_ray") and not GameState.ui_blocked():
		var aim: Dictionary = pl.get_look_ray()
		var col = aim.get("collider")
		if col:
			if col.is_in_group("bed"):
				text = "Кровать\nE — сон и точка возрождения\nY — проверить под подушкой"
			elif col.is_in_group("reagent"):
				text = "Реагент\nПодойди ближе — автоподбор. E — взять."
			elif col.has_meta("voxel_cell"):
				var c: Vector3i = col.get_meta("voxel_cell")
				var src := GameState.dream_blocks if GameState.is_dream() else GameState.wake_blocks
				var id: String = src.get(c,GameState.wake_blocks.get(c,{})).get("kind", "")
				text = GameState.block_display_name(id)
				if id in ["workbench","lathe","sawmill","alchemy","idea_catcher","chest"]:
					text += "\nE — открыть"
				elif id == "door":
					text += "\nПКМ — открыть / закрыть"
				else:
					text += "\nУдерживай ЛКМ с киркой — добыча"
			elif col.has_meta("terrain_chunk"):
				text = "Добыча\nУдерживай ЛКМ с киркой. Каменная кирка быстрее деревянной."
		if text == "" and GameState.tutorial_enabled:
			var step := GameState.tutorial_step
			if GameState.is_dream():
				GameState.tutorial_step = maxi(2,step)
				text = "Сон\nЛКМ — строить. Q — заякорить.\nF — проснуться. Незаякоренное исчезнет."
			elif step < 2:
				text = "Первые шаги\nСобери реагенты и найди кровать.\nE — уснуть. I — инвентарь."
			elif GameState.dream_exit_count < 2:
				text = "Пробуждение\nЗаякоренное перенесено в явь.\nC во сне — крафт верстака и станций."
			else:
				GameState.tutorial_step = 3
	if text == _last:
		return
	_last = text
	visible = text != ""
	text_label.text = text
	if visible:
		if _tween:
			_tween.kill()
		position.x = -280
		_tween = create_tween()
		_tween.tween_property(self,"position:x",10.0,0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
