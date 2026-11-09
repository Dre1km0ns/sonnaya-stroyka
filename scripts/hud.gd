extends CanvasLayer
## HUD v0.5: хотбар 9 слотов с иконками (количество — справа сверху), вертикальная полоса
## якорей/маяков справа, инвентарь 9+27 (I / Tab), всплывашки, дев-бейдж, F3 — отладка.

const SlotView := preload("res://scripts/slot_view.gd")
const ItemDB := preload("res://scripts/item_db.gd")

@onready var world_label: Label = $Root/WorldLabel
@onready var clarity_bar: ProgressBar = $Root/ClarityBar
@onready var inv_label: Label = $Root/InvLabel
@onready var hint_label: Label = $Root/HintLabel
@onready var crosshair: Label = $Root/Crosshair

var _hotbar: Array = []
var _specials: Array = []
var _boss_wrap: Control
var _boss_bar: ProgressBar
var _boss_label: Label
var _name_label: Label
var _name_t := 0.0
var _toast_label: Label
var _toast_t := 0.0
var _dev_badge: Label
var _debug_label: Label
var _debug_t := 0.0
var _last_sel := -1
var inventory: Control


func _ready() -> void:
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	$Root.add_child(menu)
	inv_label.visible = false
	_build_hotbar()
	_build_special_bar()
	_build_labels()
	_build_boss_bar()
	var inv_script: GDScript = load("res://scripts/inventory_ui.gd")
	inventory = inv_script.new()
	$Root.add_child(inventory)
	GameState.world_changed.connect(_on_world)
	GameState.inventory_changed.connect(_refresh_inv)
	GameState.clarity_changed.connect(_on_clarity)
	GameState.hint_changed.connect(_on_hint)
	GameState.toast.connect(show_toast)
	_on_world(GameState.is_dream())
	_refresh_inv()
	_on_clarity(GameState.clarity, GameState.CLARITY_MAX)
	if hint_label:
		hint_label.visible = false
		hint_label.text = ""
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		_debug_label.visible = bool(gsets.show_fps)
		gsets.settings_changed.connect(func() -> void:
			_debug_label.visible = bool(gsets.show_fps)
			_debug_t = 1.0)


func _build_hotbar() -> void:
	var root: Control = $Root
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	var w := 9 * 52 + 8 * 4
	bar.offset_left = -w / 2.0
	bar.offset_right = w / 2.0
	bar.offset_top = -66.0
	bar.offset_bottom = -14.0
	bar.add_theme_constant_override("separation", 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for i in range(GameState.HOTBAR_SIZE):
		var s: Panel = SlotView.new()
		s.index = i
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.set_key_hint(str(i + 1))
		bar.add_child(s)
		_hotbar.append(s)


func _build_special_bar() -> void:
	## Вертикальная полоса справа: Гвоздь / Клин / Якорь3 / Маяк. Отдельно от инвентаря.
	var root: Control = $Root
	var col := VBoxContainer.new()
	col.name = "SpecialBar"
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	var h := 4 * 52 + 3 * 4 + 22
	col.offset_left = -70.0
	col.offset_right = -14.0
	col.offset_top = -h / 2.0
	col.offset_bottom = h / 2.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var cap := Label.new()
	cap.text = "R ⟳"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cap.add_theme_constant_override("outline_size", 4)
	col.add_child(cap)
	for sp in ItemDB.SPECIAL:
		var s: Panel = SlotView.new()
		s.index = int(sp["anchor"])
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.set_key_hint("G" if str(sp["id"]) == "beacon" else "")
		col.add_child(s)
		_specials.append([s, str(sp["id"])])


func _build_labels() -> void:
	var root: Control = $Root
	_name_label = _mk_center_label(-96, 18)
	root.add_child(_name_label)
	_toast_label = _mk_center_label(-124, 20)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	root.add_child(_toast_label)
	_dev_badge = Label.new()
	_dev_badge.text = "DEV-СИД 6767676767 · ресурсы ∞"
	_dev_badge.position = Vector2(24, 116)
	_dev_badge.add_theme_font_size_override("font_size", 15)
	_dev_badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	_dev_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_dev_badge.add_theme_constant_override("outline_size", 4)
	root.add_child(_dev_badge)
	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_label.offset_left = -420
	_debug_label.offset_right = -14
	_debug_label.offset_top = 10
	_debug_label.offset_bottom = 120
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug_label.visible = false
	root.add_child(_debug_label)


func _mk_center_label(top: float, size: int) -> Label:
	var l := Label.new()
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = top
	l.offset_bottom = top + 26
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	return l


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_t = 2.4


func _tick_fades(delta: float) -> void:
	_name_t = maxf(0.0, _name_t - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	_name_label.modulate.a = clampf(_name_t / 0.5, 0.0, 1.0)
	_toast_label.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
		get_viewport().set_input_as_handled()


func _update_debug() -> void:
	var chunks := 0
	var pending := 0
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")) == GameState.is_dream() and cm.has_method("get_loaded_count"):
			chunks = cm.get_loaded_count()
			pending = cm.get_pending_count()
	_debug_label.text = "FPS %d   кадр %.1f мс\nсид %s%s\nчанков %d (+%d в очереди)\nузлов %d   draw calls %d\nсущностей %d" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		str(GameState.world_seed), "  (DEV)" if GameState.dev_mode else "",
		chunks, pending,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		get_tree().get_nodes_in_group("enemy").size(),
	]


func _on_world(is_dream: bool) -> void:
	world_label.text = "СОН" if is_dream else "ЯВЬ"
	world_label.modulate = Color(0.75, 0.7, 1.0) if is_dream else Color(0.9, 0.8, 0.6)
	clarity_bar.visible = is_dream
	var cap := get_node_or_null("Root/ClarityCaption")
	if cap:
		cap.visible = is_dream


func _on_clarity(value: float, max_value: float) -> void:
	clarity_bar.max_value = max_value
	clarity_bar.value = value


func _refresh_inv() -> void:
	_dev_badge.visible = GameState.dev_mode
	for i in range(_hotbar.size()):
		var d: Dictionary = GameState.get_slot(i)
		_hotbar[i].set_item(str(d.get("id", "")), int(d.get("count", 0)), i == GameState.selected_slot, GameState.is_infinite_slot(i))
	for pair in _specials:
		var sv = pair[0]
		var sid: String = pair[1]
		var cnt: int = GameState.special_display_count(sid)
		sv.set_item(sid, cnt, sv.index >= 0 and sv.index == int(GameState.selected_anchor), cnt >= GameState.INF_COUNT, true)
	if GameState.selected_slot != _last_sel:
		_last_sel = GameState.selected_slot
		var sel: Dictionary = GameState.get_slot(GameState.selected_slot)
		var sid2 := str(sel.get("id", ""))
		if sid2 != "":
			_name_label.text = ItemDB.display_name(sid2, str(sel.get("name", sid2)))
			_name_t = 1.8


func _on_hint(_text: String) -> void:
	if hint_label:
		hint_label.visible = false
		hint_label.text = ""


func _build_boss_bar() -> void:
	var root: Control = $Root
	_boss_wrap = Control.new()
	_boss_wrap.name = "BossBarWrap"
	_boss_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_wrap.offset_left = 180
	_boss_wrap.offset_right = -180
	_boss_wrap.offset_top = 14
	_boss_wrap.offset_bottom = 70
	_boss_wrap.visible = false
	root.add_child(_boss_wrap)
	_boss_label = Label.new()
	_boss_label.text = "Мать блоков"
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_label.offset_bottom = 22
	_boss_label.add_theme_font_size_override("font_size", 18)
	_boss_wrap.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.max_value = 1000
	_boss_bar.value = 1000
	_boss_bar.show_percentage = false
	_boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar.offset_top = 24
	_boss_bar.offset_bottom = 48
	_boss_bar.custom_minimum_size = Vector2(0, 24)
	_style_boss_bar(_boss_bar)
	_boss_wrap.add_child(_boss_bar)


func _process(delta: float) -> void:
	_tick_fades(delta)
	_debug_t += delta
	if _debug_label.visible and _debug_t > 0.25:
		_debug_t = 0.0
		_update_debug()
	if _boss_wrap == null:
		return
	var bosses: Array = get_tree().get_nodes_in_group("block_mother") if get_tree() else []
	var live: Node = null
	for b in bosses:
		if is_instance_valid(b) and int(b.get("hp")) > 0:
			live = b
			break
	if live == null:
		_boss_wrap.visible = false
		return
	_boss_wrap.visible = true
	var hp: int = int(live.get("hp"))
	var mx: int = int(live.get("max_hp"))
	_boss_bar.max_value = mx
	_boss_bar.value = hp
	_boss_label.text = "Мать блоков   %d / %d" % [hp, mx]


func _style_boss_bar(bar: ProgressBar) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.90, 0.09, 0.11, 1.0)
	fill.set_corner_radius_all(4)
	fill.content_margin_left = 2
	fill.content_margin_right = 2
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.04, 0.05, 0.94)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("fg", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("bg", bg)
	bar.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.modulate = Color.WHITE


func boss_bar_fill_is_red() -> bool:
	if _boss_bar == null:
		return false
	var sb: StyleBox = _boss_bar.get_theme_stylebox("fill")
	if sb == null or not (sb is StyleBoxFlat):
		return false
	var c: Color = (sb as StyleBoxFlat).bg_color
	return c.r >= 0.75 and c.g <= 0.25 and c.b <= 0.25


