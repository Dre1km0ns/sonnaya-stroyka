extends PanelContainer
## v0.11: панель текущей цели (слева сверху). Одна рекомендация + ближайшая крупная веха,
## «угроза глубин» и подсказка Архива Снов. Обновляется по сигналам GameState и раз в 0.5 с.

const Objectives := preload("res://scripts/objectives.gd")

var _stage: Label
var _title: Label
var _how: Label
var _next: Label
var _threat: Label
var _threat_bar: ProgressBar
var _t := 0.0
var _last_id := "?"
var _flash := 0.0


func _ready() -> void:
	name = "ObjectivePanel"
	add_to_group("objective_panel")
	position = Vector2(10, 136)
	custom_minimum_size = Vector2(330, 0)
	size = Vector2(330, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.10, 0.72)
	st.border_color = Color(0.55, 0.6, 1.0, 0.55)
	st.border_width_left = 3
	st.set_corner_radius_all(6)
	st.set_content_margin_all(9)
	add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_stage = _mk(11, Color(0.7, 0.75, 1.0))
	_title = _mk(16, Color(1, 0.95, 0.75))
	_how = _mk(12, Color(0.88, 0.88, 0.92))
	_next = _mk(11, Color(0.7, 0.9, 0.75))
	_threat = _mk(12, Color(1.0, 0.6, 0.45))
	for l in [_stage, _title, _how, _next, _threat]:
		box.add_child(l)
	_threat_bar = ProgressBar.new()
	_threat_bar.custom_minimum_size = Vector2(300, 8)
	_threat_bar.show_percentage = false
	_threat_bar.max_value = 100
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.85, 0.3, 0.25)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.15, 0.1, 0.1, 0.8)
	_threat_bar.add_theme_stylebox_override("fill", fill)
	_threat_bar.add_theme_stylebox_override("background", bg)
	_threat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_threat_bar)
	GameState.objective_changed.connect(refresh)
	GameState.world_changed.connect(func(_d: bool) -> void: refresh())
	GameState.deep_threat_changed.connect(func(_v: float) -> void: refresh())
	GameState.milestone_done.connect(func(_id: String, _t2: String) -> void: _flash = 1.2)
	refresh()


func _mk(sz: int, col: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(312, 0)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	visible = not GameState.ui_blocked() and not GameState.transfer_ui_open
	_flash = maxf(0.0, _flash - delta)
	modulate = Color(1, 1, 1).lerp(Color(1.4, 1.4, 0.9), clampf(_flash, 0.0, 1.0))
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		refresh()


func refresh() -> void:
	if _title == null:
		return
	var cur: Dictionary = GameState.current_objective()
	var big: Dictionary = GameState.next_big_objective()
	var done := Objectives.done_count(GameState)
	_stage.text = "ЦЕЛЬ · этап %d · вех %d/%d" % [int(cur.get("stage", 0)), done, Objectives.LIST.size()]
	_title.text = ("★ " if cur.get("big", false) else "▸ ") + str(cur.get("title", ""))
	_how.text = str(cur.get("how", ""))
	_next.text = ("Дальше: ★ " + str(big.title)) if not big.is_empty() else ""
	_next.visible = _next.text != ""
	var show_threat := not GameState.is_dream() and GameState.deep_threat >= 25.0 and not GameState.boss_alive
	_threat.visible = show_threat
	_threat_bar.visible = show_threat
	if show_threat:
		_threat.text = "Угроза глубин %d%% — Мать блоков слышит раскопки" % int(GameState.deep_threat)
		_threat_bar.value = GameState.deep_threat
	if GameState.is_dream() and GameState.archive_unlocked():
		_next.visible = true
		_next.text += ("\n" if _next.text != "" else "") + "Архив Снов: B — сохранить, N — контур (%d/3)" % GameState.blueprints.size()
	if str(cur.get("id", "")) != _last_id:
		_last_id = str(cur.get("id", ""))
	reset_size()


func state() -> Dictionary:
	return {"title": _title.text, "how": _how.text, "next": _next.text, "threat_visible": _threat.visible}
