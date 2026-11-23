extends CanvasLayer
## HUD v0.12: хотбар 9 слотов, полоса HP слева снизу
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
var _core_bar: ProgressBar          # v0.15: сколько урона ещё влезет в открытое ядро
var combat_feedback: Control
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
## v0.6
var _chat_box: VBoxContainer
var _chat: Array = [] # [[Label, age]]
const CHAT_LIFETIME := 8.0
const CHAT_MAX := 8
var _hearts: Array = []
var _hp_wrap: Control
var _phase_label: Label
var _phase_t := 0.0
var _anchor_cap: Label
var _vuln_label: Label
var _last_chat_text := ""
var _last_chat_time := -100.0
var _time := 0.0
## v0.7
var _hp_text: Label
var _heal_text: Label
var objective_panel: Control
var _bed_prompt: PanelContainer
var _bed_prompt_label: Label
var pillow_ui: Control
var death_menu: Control
var victory_screen: Control


func _ready() -> void:
	add_to_group("hud") # v0.21 c2: для консоли (hudfocus) и смоука
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	$Root.add_child(menu)
	inv_label.visible = false
	_style_clarity()
	_build_hotbar()
	_build_special_bar()
	_build_labels()
	_build_boss_bar()
	combat_feedback = load("res://scripts/combat_feedback.gd").new()   # v0.15: хит-маркер + дуга урона
	$Root.add_child(combat_feedback)
	_build_chat()
	_build_hearts()
	_build_phase_label()
	GameState.chat_message.connect(add_chat)
	GameState.day_phase_changed.connect(func(_p: String) -> void: _update_phase_label())
	GameState.player_hp_changed.connect(_on_hp)
	_on_hp(GameState.player_hp, GameState.PLAYER_MAX_HP)
	var inv_script: GDScript = load("res://scripts/inventory_ui.gd")
	inventory = inv_script.new()
	$Root.add_child(inventory)
	_build_heal_indicator()
	_build_bed_prompt()
	var pil_script: GDScript = load("res://scripts/pillow_ui.gd")
	pillow_ui = pil_script.new()
	$Root.add_child(pillow_ui)
	var storage: Control = load("res://scripts/storage_ui.gd").new()
	$Root.add_child(storage)
	var context: Control = load("res://scripts/context_hints.gd").new()
	$Root.add_child(context)
	objective_panel = load("res://scripts/objective_panel.gd").new()
	$Root.add_child(objective_panel)
	GameState.unlock_announced.connect(func(t: String) -> void: show_toast(t, 5.0))
	var death_script: GDScript = load("res://scripts/death_menu.gd")
	death_menu = death_script.new()
	$Root.add_child(death_menu)
	victory_screen = load("res://scripts/victory_screen.gd").new()
	$Root.add_child(victory_screen)
	GameState.world_changed.connect(_on_world)
	GameState.inventory_changed.connect(_refresh_inv)
	GameState.clarity_changed.connect(_on_clarity)
	GameState.anchor_selected.connect(func(_t: int) -> void: _on_clarity(GameState.clarity, GameState.dream_clarity_max()))
	GameState.hint_changed.connect(_on_hint)
	GameState.toast.connect(show_toast)
	_on_world(GameState.is_dream())
	_refresh_inv()
	_on_clarity(GameState.clarity, GameState.dream_clarity_max())
	if hint_label:
		hint_label.visible = false
		hint_label.text = ""
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		_debug_label.visible = false
		gsets.settings_changed.connect(func() -> void:
			_debug_t = 1.0
			_refresh_key_hints())
	_refresh_key_hints()


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
	_anchor_cap = cap
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


func _key(action: String, fallback: String) -> String:
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets and gsets.has_method("key_label"):
		return str(gsets.key_label(action))
	return fallback


func _refresh_key_hints() -> void:
	if _anchor_cap:
		_anchor_cap.text = "%s ⟳" % _key("cycle_anchor", "R")
	for i in range(_hotbar.size()):
		_hotbar[i].set_key_hint(_key("hotbar_%d" % (i + 1), str(i + 1)))
	for pair in _specials:
		if str(pair[1]) == "beacon":
			pair[0].set_key_hint(_key("place_beacon", "G"))


# --- v0.6: чат/журнал сообщений внизу слева (сообщения гаснут через ~8 с) ---

func _build_chat() -> void:
	var root: Control = $Root
	_chat_box = VBoxContainer.new()
	_chat_box.name = "ChatLog"
	_chat_box.anchor_left = 0.0
	_chat_box.anchor_right = 0.0
	_chat_box.anchor_top = 1.0
	_chat_box.anchor_bottom = 1.0
	_chat_box.offset_left = 14
	_chat_box.offset_right = 470
	_chat_box.offset_top = -300
	_chat_box.offset_bottom = -84
	_chat_box.alignment = BoxContainer.ALIGNMENT_END
	_chat_box.add_theme_constant_override("separation", 2)
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_box)


func add_chat(text: String, color: Color = Color(1, 1, 1)) -> void:
	if text.begins_with("Сон. ЛКМ"): return
	if text.strip_edges() == "":
		return
	if text == _last_chat_text and _time - _last_chat_time < 4.0:
		return
	_last_chat_text = text
	_last_chat_time = _time
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(450, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.38)
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", bg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_box.add_child(l)
	_chat.append([l, 0.0])
	while _chat.size() > CHAT_MAX:
		var old: Label = _chat[0][0]
		_chat.remove_at(0)
		old.queue_free()


func chat_lines() -> Array:
	var out: Array = []
	for e in _chat:
		out.append((e[0] as Label).text)
	return out


func _tick_chat(delta: float) -> void:
	var i := 0
	while i < _chat.size():
		var e: Array = _chat[i]
		e[1] = float(e[1]) + delta
		var l: Label = e[0]
		var age: float = e[1]
		l.modulate.a = clampf((CHAT_LIFETIME - age) / 1.2, 0.0, 1.0)
		if age >= CHAT_LIFETIME:
			l.queue_free()
			_chat.remove_at(i)
			continue
		i += 1


# --- v0.6: HP игрока сердечками над хотбаром ---

func _build_hearts() -> void:
	## v0.12: горизонтальная полоса слева снизу, «текущее / максимум», след урона.
	var root: Control = $Root
	_hp_wrap = load("res://scripts/health_battery.gd").new()
	_hp_wrap.anchor_left = 0.0
	_hp_wrap.anchor_right = 0.0
	_hp_wrap.anchor_top = 1.0
	_hp_wrap.anchor_bottom = 1.0
	_hp_wrap.offset_left = 16.0
	_hp_wrap.offset_right = 16.0 + 240.0
	_hp_wrap.offset_top = -52.0
	_hp_wrap.offset_bottom = -18.0
	root.add_child(_hp_wrap)
	_build_stamina_bar(root)


var _stamina_bar: ProgressBar


func _build_stamina_bar(root: Control) -> void:
	## v0.22.1: полоска стамины прямо над HP.
	_stamina_bar = ProgressBar.new()
	_stamina_bar.name = "StaminaBar"
	_stamina_bar.anchor_top = 1.0; _stamina_bar.anchor_bottom = 1.0
	_stamina_bar.offset_left = 16.0; _stamina_bar.offset_right = 16.0 + 240.0
	_stamina_bar.offset_top = -62.0; _stamina_bar.offset_bottom = -55.0
	_stamina_bar.min_value = 0.0; _stamina_bar.max_value = 1.0; _stamina_bar.step = 0.0
	_stamina_bar.show_percentage = false
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.06, 0.06, 0.08, 0.75); bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color(0.98, 0.82, 0.3); fg.set_corner_radius_all(3)
	_stamina_bar.add_theme_stylebox_override("background", bg)
	_stamina_bar.add_theme_stylebox_override("fill", fg)
	root.add_child(_stamina_bar)
	_stamina_bar.visible = not GameState.is_dream()
	GameState.stamina_changed.connect(_on_stamina)
	_on_stamina(GameState.stamina, GameState.stamina_tired)


func _on_stamina(v: float, tired: bool) -> void:
	if _stamina_bar == null: return
	_stamina_bar.value = v
	var fg := _stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fg: fg.bg_color = Color(0.85, 0.35, 0.25) if tired else Color(0.98, 0.82, 0.3)


func _build_heal_indicator() -> void:
	## v0.11.1: подписи «HP n/100» и «H ▸ хилка…» убраны; число HP — внутри батарейки.
	_hp_text = _hp_wrap.label if _hp_wrap else null
	_heal_text = null


func _update_heal_indicator() -> void:
	if _hp_wrap == null:
		return
	_hp_wrap.set_hp(GameState.player_hp, GameState.PLAYER_MAX_HP)


func heal_indicator_state() -> Dictionary:
	return {"visible": _hp_wrap != null and _hp_wrap.visible, "slot": find_child("HealSlot", true, false) != null, "cd_text": "",
		"hp_text": _hp_text.text if _hp_text else "", "heal_text": "", "battery": _hp_wrap != null and _hp_wrap.name == "HealthBattery",
		"hearts": find_child("Hearts", true, false) != null,
		"current": GameState.player_hp, "max": GameState.PLAYER_MAX_HP,
		"bottom_left": _hp_wrap != null and is_equal_approx(_hp_wrap.anchor_left, 0.0)}


func _build_bed_prompt() -> void:
	## v0.7: наведение на кровать в яви → вопрос «под подушкой».
	var root: Control = $Root
	_bed_prompt = PanelContainer.new()
	_bed_prompt.name = "BedPrompt"
	_bed_prompt.anchor_left = 0.5
	_bed_prompt.anchor_right = 0.5
	_bed_prompt.anchor_top = 0.5
	_bed_prompt.anchor_bottom = 0.5
	_bed_prompt.offset_left = -230
	_bed_prompt.offset_right = 230
	_bed_prompt.offset_top = 40
	_bed_prompt.offset_bottom = 120
	_bed_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.16, 0.88)
	sb.border_color = Color(0.85, 0.7, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_bed_prompt.add_theme_stylebox_override("panel", sb)
	_bed_prompt_label = Label.new()
	_bed_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bed_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bed_prompt_label.add_theme_font_size_override("font_size", 16)
	_bed_prompt.add_child(_bed_prompt_label)
	_bed_prompt.visible = false
	root.add_child(_bed_prompt)


func _update_bed_prompt() -> void:
	if _bed_prompt == null:
		return
	# v0.22: у кровати нет окна выбора: Y — под подушку, E — в Сон.
	_bed_prompt.visible = false


func bed_prompt_visible() -> bool:
	return _bed_prompt != null and _bed_prompt.visible


func _on_hp(hp: int, max_hp: int) -> void:
	if _hp_wrap: _hp_wrap.set_hp(hp, max_hp)


# --- v0.6: фаза суток и часы ---

func _build_phase_label() -> void:
	add_to_group("hud_phase")
	var root: Control = $Root
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.position = Vector2(24, 58)
	_phase_label.add_theme_font_size_override("font_size", 17)
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_phase_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_phase_label)
	_update_phase_label()


func _update_phase_label() -> void:
	if _phase_label == null:
		return
	var ph: String = GameState.day_phase()
	var name: String = str(GameState.PHASE_NAMES.get(ph, ph))
	var icon := "☾" if ph == "night" else "☀"
	_phase_label.text = "%s %s · %s" % [icon, name, GameState.clock_text(GameState.day_time)]
	var cols := {"morning": Color(1.0, 0.82, 0.6), "day": Color(1.0, 0.95, 0.7), "evening": Color(1.0, 0.6, 0.45), "night": Color(0.65, 0.75, 1.0)}
	_phase_label.add_theme_color_override("font_color", cols.get(ph, Color.WHITE))
	_phase_label.visible = not GameState.is_dream()


func _build_labels() -> void:
	var root: Control = $Root
	_name_label = _mk_center_label(-120,18)
	root.add_child(_name_label)
	_toast_label = _mk_center_label(-150,20)
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


func show_toast(text: String, seconds: float = 2.4) -> void:
	_toast_label.text = text
	_toast_t = seconds


func _tick_fades(delta: float) -> void:
	_name_t = maxf(0.0, _name_t - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	_name_label.modulate.a = 0.0 if GameState.ui_blocked() else clampf(_name_t / 0.5, 0.0, 1.0)
	_toast_label.modulate.a = 0.0 if GameState.ui_blocked() else clampf(_toast_t / 0.6, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.console_open: return
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
	_debug_label.text = "FPS %d   кадр %.1f мс\nсид %s%s\nчанков %d · в очереди %d\nузлов %d   draw calls %d\nсущностей %d" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		str(GameState.world_seed), "  (DEV)" if GameState.dev_mode else "",
		chunks, pending,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		get_tree().get_nodes_in_group("enemy").size(),
	]

	var player:=get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var pos:=player.global_position
		var facing:=fposmod(rad_to_deg(player.rotation.y),360.0)
		var names: Array[String]=["Север −Z","Запад −X","Юг +Z","Восток +X"]
		_debug_label.text+="\nXYZ %.2f / %.2f / %.2f\nНаправление %s %.0f°\nЧанк %d / %d" % [pos.x,pos.y,pos.z,names[posmod(roundi(facing/90),4)],facing,floori(pos.x/16),floori(pos.z/16)]

func set_debug(mode: String="toggle") -> bool:
	_debug_label.visible=not _debug_label.visible if mode=="toggle" else mode=="on"
	_update_debug();return _debug_label.visible

func _on_world(is_dream: bool) -> void:
	if _stamina_bar: _stamina_bar.visible = not is_dream
	world_label.text = "СОН" if is_dream else "ЯВЬ"
	world_label.modulate = Color(0.75, 0.7, 1.0) if is_dream else Color(0.9, 0.8, 0.6)
	# v0.21: обводка и тень — заголовок читается и на светлом небе Яви.
	world_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 1.0))
	world_label.add_theme_constant_override("outline_size", 8)
	world_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	world_label.add_theme_constant_override("shadow_offset_x", 2)
	world_label.add_theme_constant_override("shadow_offset_y", 2)
	clarity_bar.visible = is_dream
	var cap := get_node_or_null("Root/ClarityCaption")
	if cap:
		cap.visible = is_dream
	# v0.7: у сна и яви разные инвентари — хотбар перерисовываем при смене мира.
	_refresh_inv()


func _style_clarity() -> void:
	## v0.21: у полосы осознанности не было заливки (серый прямоугольник при 100/100).
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.68, 0.55, 1.0); fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.08, 0.06, 0.14, 0.85); bg.set_corner_radius_all(4)
	bg.border_color = Color(0.45, 0.4, 0.7, 0.9); bg.set_border_width_all(1)
	clarity_bar.add_theme_stylebox_override("fill", fill)
	clarity_bar.add_theme_stylebox_override("background", bg)
	clarity_bar.offset_bottom = clarity_bar.offset_top + 14
	var cap := get_node_or_null("Root/ClarityCaption") as Label
	if cap:
		cap.offset_top = 82; cap.offset_right = 330; cap.offset_bottom = 120
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF # подложка по размеру текста (reset_size после смены текста)
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		cap.add_theme_constant_override("outline_size", 3)
		# v0.21 c2: подложка — на фоне светлых островов Сна подпись читалась плохо.
		var cbg := StyleBoxFlat.new(); cbg.bg_color = Color(0.06, 0.04, 0.12, 0.72); cbg.set_corner_radius_all(4)
		cbg.content_margin_left = 6; cbg.content_margin_right = 6; cbg.content_margin_top = 2; cbg.content_margin_bottom = 3
		cap.add_theme_stylebox_override("normal", cbg)
		cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _on_clarity(value: float, max_value: float) -> void:
	clarity_bar.max_value = max_value
	clarity_bar.value = value
	# v0.11→v0.16: подпись полосы осознанности.
	var cap := get_node_or_null("Root/ClarityCaption") as Label
	if cap:
		# v0.16: осознанность — ресурс, а не таймер. Подпись: запас, цена якоря, материал палитры и его запас в Яви.
		var cost: Dictionary = GameState.anchor_cost(int(GameState.selected_anchor))
		var mat: String = GameState.dream_material
		if tutorial_hides_wake_tools():
			# v0.21 c2: до шага «якорь» цена якоря и палитра — лишний шум.
			cap.text = "Осознанность %d/%d" % [int(value), int(max_value)]
		else:
			cap.text = "Осознанность %d/%d · %s −%d\nT: %s%s" % [int(value), int(max_value), ["гвоздь","клин","якорь3"][int(GameState.selected_anchor)], int(cost.clarity), GameState.block_display_name(mat), GameState.palette_stock_text(mat)]
		cap.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if value < float(cost.clarity) else Color(0.85, 0.85, 1.0))
		cap.reset_size()


## v0.21 c2: пока обучение не дошло до якоря, колонка Гвоздь/Клин/Якорь3/Маяк и цена якоря скрыты.
func tutorial_hides_wake_tools() -> bool:
	return GameState.tutorial_focus() and not (GameState.tutorial_step_id() in ["anchor", "wake"])


var _focus_t := 0.0
var _focus_last := -1

func _update_tutorial_focus(delta: float) -> void:
	_focus_t -= delta
	if _focus_t > 0.0:
		return
	_focus_t = 0.2
	var hide := tutorial_hides_wake_tools()
	var bar := get_node_or_null("Root/SpecialBar") as Control
	if bar:
		bar.visible = not hide
	if int(hide) != _focus_last:
		_focus_last = int(hide)
		_on_clarity(clarity_bar.value, clarity_bar.max_value)


func _refresh_inv() -> void:
	_dev_badge.visible = GameState.dev_mode
	for i in range(_hotbar.size()):
		var d: Dictionary = GameState.get_slot(i)
		if GameState.palette_slot_active(i):
			# v0.22: честный хотбар Сна — в слоте 1 виден текущий материал палитры, ставится бесконечно
			_hotbar[i].set_item(GameState.dream_palette_kind(), 0, i == GameState.selected_slot, true)
			_hotbar[i].set_durability(0, 0)
			continue
		_hotbar[i].set_item(str(d.get("id", "")), int(d.get("count", 0)), i == GameState.selected_slot, GameState.is_infinite_slot(i))
		_hotbar[i].set_durability(int(d.get("durability", GameState.tool_max(str(d.get("id", ""))))), GameState.tool_max(str(d.get("id", ""))))
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
	_boss_bar.max_value = 500
	_boss_bar.value = 500
	_boss_bar.show_percentage = false
	_boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar.offset_top = 24
	_boss_bar.offset_bottom = 48
	_boss_bar.custom_minimum_size = Vector2(0, 24)
	_style_boss_bar(_boss_bar)
	_boss_wrap.add_child(_boss_bar)
	for frac in [0.33, 0.66]:
		var mark := ColorRect.new()
		mark.color = Color(1, 1, 1, 0.75)
		mark.anchor_left = frac
		mark.anchor_right = frac
		mark.offset_left = -1
		mark.offset_right = 1
		mark.offset_top = 0
		mark.offset_bottom = 24
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_bar.add_child(mark)
	_core_bar = ProgressBar.new()
	_core_bar.name = "CoreWindowBar"
	_core_bar.max_value = 1.0
	_core_bar.step = 0.0
	_core_bar.value = 1.0
	_core_bar.show_percentage = false
	_core_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_core_bar.offset_top = 50
	_core_bar.offset_bottom = 58
	_core_bar.custom_minimum_size = Vector2(0, 8)
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.1, 0.08, 0.05, 0.75)
	var cfill := StyleBoxFlat.new()
	cfill.bg_color = Color(1.0, 0.78, 0.25)
	_core_bar.add_theme_stylebox_override("background", cbg)
	_core_bar.add_theme_stylebox_override("fill", cfill)
	_core_bar.visible = false
	_boss_wrap.add_child(_core_bar)


func _process(delta: float) -> void:
	_time += delta
	_tick_fades(delta)
	_tick_chat(delta)
	_phase_t -= delta
	if _phase_t <= 0.0:
		_phase_t = 0.5
		_update_phase_label()
	_update_heal_indicator()
	_update_bed_prompt()
	_update_tutorial_focus(delta)
	_debug_t += delta
	if _debug_label.visible and _debug_t > 0.25:
		_debug_t = 0.0
		_update_debug()
	if _boss_wrap == null:
		return
	var bosses: Array = get_tree().get_nodes_in_group("boss") if get_tree() else []
	var live: Node = null
	for b in bosses:
		if is_instance_valid(b) and b.get("hp") != null and int(b.get("hp")) > 0:
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
	var win := float(live.call("core_window_left")) if live.has_method("core_window_left") else -1.0
	if _core_bar:
		_core_bar.visible = win >= 0.0
		if win >= 0.0:
			_core_bar.value = win
	var vuln := bool(live.call("is_vulnerable")) if live.has_method("is_vulnerable") else false
	var title := str(live.call("boss_title")) if live.has_method("boss_title") else "Мать блоков"
	_boss_label.text = "%s %d/%d" % [title, hp, mx]  # v0.22.1: только название и HP
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if vuln else Color(1, 1, 1))


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


