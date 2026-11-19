extends CanvasLayer
## v0.20: панель обучения во Сне (новая игра начинается во Сне). Шаги — GameState.TUTORIAL.
## Шаг «полёт» засчитывается здесь: отлететь на 8 блоков по горизонтали или на 3 по высоте.

const UiTheme := preload("res://scripts/ui_theme.gd")
const FLY_DIST := 8.0
const FLY_RISE := 3.0

var panel: PanelContainer
var title: Label
var how: Label
var dots: Label
var _fly_from := Vector3.INF


func _ready() -> void:
	name = "DreamTutorial"
	process_mode = Node.PROCESS_MODE_ALWAYS # прятать панель и под паузой
	layer = 6
	add_to_group("dream_tutorial")
	panel = PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.offset_left = -300; panel.offset_right = 300; panel.offset_top = 64
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.24, 0.86); sb.border_color = Color(0.75, 0.6, 1.0, 0.9)
	sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	title = Label.new(); title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	box.add_child(title)
	how = Label.new(); how.add_theme_font_size_override("font_size", 15)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; how.custom_minimum_size = Vector2(576, 0)
	box.add_child(how)
	dots = Label.new(); dots.add_theme_font_size_override("font_size", 13)
	dots.add_theme_color_override("font_color", Color(0.78, 0.74, 0.92))
	box.add_child(dots)
	GameState.tutorial_changed.connect(refresh)
	GameState.world_changed.connect(func(_d: bool) -> void: _fly_from = Vector3.INF; refresh())
	refresh()


func refresh() -> void:
	var cur: Dictionary = GameState.tutorial_current()
	panel.visible = not cur.is_empty()
	if cur.is_empty(): return
	var n: int = GameState.TUTORIAL.size()
	var i: int = GameState.tutorial_index() + 1
	title.text = "Обучение во Сне · %d/%d — %s" % [i, n, cur.title]
	var text: String = cur.how
	if not GameState.is_dream() and cur.id != "wake":
		text = "Ты в Яви. Вернись во Сон: подойди к кровати в лагере и нажми E. Там продолжится шаг: " + cur.how
	how.text = text
	var marks := ""
	for t in GameState.TUTORIAL:
		marks += ("● " if GameState.tutorial_done.has(t.id) else "○ ")
	dots.text = marks + "  ·  F1 — пропустить обучение"


func menus_open() -> bool:
	return GameState.paused or GameState.inventory_open or GameState.craft_menu_open or GameState.storage_open \
		or GameState.transfer_ui_open or GameState.death_open or GameState.pillow_open \
		or not get_tree().get_nodes_in_group("modal_menu").is_empty()


func _process(_delta: float) -> void:
	if not GameState.tutorial_active:
		return
	panel.visible = not menus_open() and not GameState.tutorial_current().is_empty()
	if not panel.visible:
		return
	if Input.is_action_just_pressed("tutorial_skip"):
		GameState.skip_tutorial(); GameState.set_hint("Обучение пропущено. Цели — на панели слева.", false)
		return
	if not GameState.is_dream() or GameState.tutorial_done.has("fly"):
		return
	var pl := get_parent().get("player") as Node3D if get_parent() != null else null
	if pl == null: pl = get_tree().get_first_node_in_group("player") as Node3D
	if pl == null: return
	if _fly_from == Vector3.INF: _fly_from = pl.global_position; return
	var d := pl.global_position - _fly_from
	if Vector2(d.x, d.z).length() >= FLY_DIST or absf(d.y) >= FLY_RISE:
		GameState.tutorial_event("fly")
