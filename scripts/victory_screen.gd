extends Control
## v0.24: экран победы после Бургера Смерти + титры. «Продолжить играть» — мир остаётся, «В главное меню» — с сохранением.
signal continue_pressed
signal exit_pressed

const DELAY := 4.0
const CREDITS := [
	["Сонная стройка", ""],
	["Идея, геймдизайн, тестирование", "Димон Войнов"],
	["Код, текстуры, звуки (синтез)", "Grok Bot"],
	["Музыка Бургера Смерти", "из коллекции Димона Войнова"],
	["Модели персонажей", "Kenney — Blocky Characters (CC0)"],
	["Движок", "Godot Engine 4.7"],
	["Отдельное спасибо", "Антону t2x2 за роль клоуна"],
	["", "Спасибо, что играешь!"],
]

var _open := false
var _stats: Label
var _credits: VBoxContainer
var _scroll_t := 0.0
var _wait := -1.0


func _ready() -> void:
	add_to_group("victory_screen")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	if not GameState.victory.is_connected(_on_victory):
		GameState.victory.connect(_on_victory)


func is_open() -> bool:
	return _open


func _on_victory() -> void:
	_wait = DELAY


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.03, 0.12, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(620, 0)
	center.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = "Победа!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Бургер Смерти повержен. Антон t2x2 снял клоунский нос."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 20)
	box.add_child(sub)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_theme_font_size_override("font_size", 16)
	_stats.add_theme_color_override("font_color", Color(0.8, 0.8, 0.92))
	box.add_child(_stats)
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(620, 230)
	box.add_child(clip)
	_credits = VBoxContainer.new()
	_credits.name = "Credits"
	_credits.add_theme_constant_override("separation", 8)
	_credits.size = Vector2(620, 0)
	clip.add_child(_credits)
	for c in CREDITS:
		if str(c[0]) != "":
			var a := Label.new(); a.text = str(c[0]); a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			a.add_theme_font_size_override("font_size", 15); a.add_theme_color_override("font_color", Color(0.65, 0.6, 0.85))
			a.custom_minimum_size.x = 620
			_credits.add_child(a)
		if str(c[1]) != "":
			var b := Label.new(); b.text = str(c[1]); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_font_size_override("font_size", 22)
			b.custom_minimum_size.x = 620
			_credits.add_child(b)
		var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 10); _credits.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var cont := Button.new(); cont.name = "Continue"; cont.text = "Продолжить играть"; cont.custom_minimum_size = Vector2(240, 46)
	cont.pressed.connect(func() -> void: close(); continue_pressed.emit())
	row.add_child(cont)
	var ex := Button.new(); ex.name = "Exit"; ex.text = "В главное меню"; ex.custom_minimum_size = Vector2(240, 46)
	ex.pressed.connect(func() -> void: close(); exit_pressed.emit())
	row.add_child(ex)


func stats_text() -> String:
	var s: Dictionary = GameState.v024_stats
	return "Сложность: %s · побед над Бургером: %d\nДобыто блоков: %d · выпущено стрел: %d · ящерок побеждено: %d" % [
		GameState.difficulty_name(), GameState.burger_kills, int(s.get("blocks_mined", 0)), int(s.get("arrows_shot", 0)), GameState.lizards_killed]


func open() -> void:
	_open = true
	visible = true
	_wait = -1.0
	_scroll_t = 0.0
	_stats.text = stats_text()
	_credits.position.y = 230.0
	GameState.victory_seen = true
	GameState.victory_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sfx := load("res://scripts/sfx.gd")
	sfx.play("victory", get_tree().root, -2.0)
	if not get_meta("smoke", false) and not (get_tree().current_scene and get_tree().current_scene.has_meta("smoke")):
		get_tree().paused = true


func close() -> void:
	_open = false
	visible = false
	GameState.victory_open = false
	GameState.modal_closed_frame = Engine.get_process_frames()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and not GameState.death_open:
			open()
		return
	if not _open:
		return
	_scroll_t += delta
	var h := maxf(_credits.get_combined_minimum_size().y, 200.0)
	_credits.position.y = 230.0 - fmod(_scroll_t * 28.0, h + 230.0)
