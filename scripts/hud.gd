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
var _heal_slot: Panel
var _heal_cd_label: Label
var _heal_cd_shade: ColorRect
var _bed_prompt: PanelContainer
var _bed_prompt_label: Label
var pillow_ui: Control
var death_menu: Control


func _ready() -> void:
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	$Root.add_child(menu)
	inv_label.visible = false
	_build_hotbar()
	_build_special_bar()
	_build_labels()
	_build_boss_bar()
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
	var death_script: GDScript = load("res://scripts/death_menu.gd")
	death_menu = death_script.new()
	$Root.add_child(death_menu)
	GameState.world_changed.connect(_on_world)
	GameState.inventory_changed.connect(_refresh_inv)
	GameState.clarity_changed.connect(_on_clarity)
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
	var root: Control = $Root
	_hp_wrap = HBoxContainer.new()
	_hp_wrap.name = "Hearts"
	_hp_wrap.anchor_left = 0.5
	_hp_wrap.anchor_right = 0.5
	_hp_wrap.anchor_top = 1.0
	_hp_wrap.anchor_bottom = 1.0
	var w := 9 * 52 + 8 * 4
	_hp_wrap.offset_left = -w / 2.0
	_hp_wrap.offset_right = -w / 2.0 + 240
	_hp_wrap.offset_top = -92.0
	_hp_wrap.offset_bottom = -70.0
	_hp_wrap.add_theme_constant_override("separation", 1)
	_hp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_wrap)
	for i in range(10):
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(22, 20)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_wrap.add_child(t)
		_hearts.append(t)


func _build_heal_indicator() -> void:
	## v0.7: «HP 74/100» + ячейка хилки1 (кол-во, клавиша, затемнение-кулдаун 15 с).
	var root: Control = $Root
	var w := 9 * 52 + 8 * 4
	_hp_text = Label.new()
	_hp_text.name = "HPText"
	_hp_text.anchor_left = 0.5
	_hp_text.anchor_right = 0.5
	_hp_text.anchor_top = 1.0
	_hp_text.anchor_bottom = 1.0
	_hp_text.offset_left = -w / 2.0 + 262
	_hp_text.offset_right = -w / 2.0 + 440
	_hp_text.grow_horizontal = Control.GROW_DIRECTION_END
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hp_text.offset_top = -94.0
	_hp_text.offset_bottom = -70.0
	_hp_text.add_theme_font_size_override("font_size", 15)
	_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hp_text.add_theme_constant_override("outline_size", 5)
	root.add_child(_hp_text)
	_heal_slot = SlotView.new()
	_heal_slot.name = "HealSlot"
	_heal_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heal_slot.anchor_left = 0.5
	_heal_slot.anchor_right = 0.5
	_heal_slot.anchor_top = 1.0
	_heal_slot.anchor_bottom = 1.0
	_heal_slot.offset_left = w / 2.0 + 14
	_heal_slot.offset_right = w / 2.0 + 66
	_heal_slot.offset_top = -62.0
	_heal_slot.offset_bottom = -10.0
	root.add_child(_heal_slot)
	_heal_cd_shade = ColorRect.new()
	_heal_cd_shade.color = Color(0, 0, 0, 0.6)
	_heal_cd_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heal_cd_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heal_slot.add_child(_heal_cd_shade)
	_heal_cd_label = Label.new()
	_heal_cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heal_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heal_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heal_cd_label.add_theme_font_size_override("font_size", 18)
	_heal_cd_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_heal_cd_label.add_theme_constant_override("outline_size", 6)
	_heal_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heal_slot.add_child(_heal_cd_label)


func _update_heal_indicator() -> void:
	if _heal_slot == null:
		return
	var dream := GameState.is_dream()
	_heal_slot.visible = not dream
	var slot: int = GameState.first_heal_slot()
	var id: String = GameState.get_slot(slot).get("id","heal1") if slot>=0 else "heal1"
	var n: int = GameState.count_item(id)
	_heal_slot.set_item(id, n, false, n >= GameState.INF_COUNT, true)
	_heal_slot.set_key_hint(_key("use_heal", "H"))
	var cd: float = float(GameState.heal_cd)
	_heal_cd_shade.visible = cd > 0.0
	_heal_cd_shade.anchor_top = 1.0 - clampf(cd / float(GameState.HEAL_COOLDOWN), 0.0, 1.0)
	_heal_cd_shade.offset_top = 0
	_heal_cd_label.text = ("%d" % int(ceil(cd))) if cd > 0.0 else ""
	var regen: float = GameState.regen_delay_left()
	var hp: int = GameState.player_hp
	var tail := ""
	if hp < GameState.PLAYER_MAX_HP and hp > 0:
		tail = "  реген %ds" % int(ceil(regen)) if regen > 0.0 else "  +1/с"
	_hp_text.text = "HP %d/%d%s" % [hp, GameState.PLAYER_MAX_HP, tail]
	_hp_text.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if hp <= 30 else Color(1, 1, 1))


func heal_indicator_state() -> Dictionary:
	return {"visible": _heal_slot != null and _heal_slot.visible, "cd_text": _heal_cd_label.text if _heal_cd_label else "",
		"hp_text": _hp_text.text if _hp_text else ""}


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
	var show := false
	if not GameState.is_dream() and not GameState.ui_blocked():
		for sw in get_tree().get_nodes_in_group("world_switcher"):
			if sw.has_method("aimed_bed") and sw.aimed_bed() != null:
				show = true
	_bed_prompt.visible = show
	if show:
		var n: int = GameState.pillow_count("heal1")
		_bed_prompt_label.text = "Вы хотите проверить, что находится под подушкой?\n[%s] Да   ·   [%s] Лечь спать (сон)%s" % [
			_key("pillow_check", "Y"), _key("interact", "E"), ("   · там что-то лежит (%d)" % n) if n > 0 else ""]


func bed_prompt_visible() -> bool:
	return _bed_prompt != null and _bed_prompt.visible


func _on_hp(hp: int, max_hp: int) -> void:
	var full: Texture2D = load("res://assets/icons/ui_heart_full.png")
	var half: Texture2D = load("res://assets/icons/ui_heart_half.png")
	var empty: Texture2D = load("res://assets/icons/ui_heart_empty.png")
	var per := float(max_hp) / float(_hearts.size())
	for i in range(_hearts.size()):
		var v := float(hp) - float(i) * per
		var t: TextureRect = _hearts[i]
		if v >= per * 0.75:
			t.texture = full
		elif v >= per * 0.25:
			t.texture = half
		else:
			t.texture = empty


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


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_t = 2.4


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
	_debug_label.text = "FPS %d   кадр %.1f мс\nсид %s%s\nчанков %d (+%d в очереди)\nузлов %d   draw calls %d\nсущностей %d" % [
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
		_debug_label.text+="\nXYZ %.2f / %.2f / %.2f\nНаправление %s (%.0f°)\nЧанк %d / %d" % [pos.x,pos.y,pos.z,names[posmod(roundi(facing/90),4)],facing,floori(pos.x/16),floori(pos.z/16)]

func set_debug(mode: String="toggle") -> bool:
	_debug_label.visible=not _debug_label.visible if mode=="toggle" else mode=="on"
	_update_debug();return _debug_label.visible

func _on_world(is_dream: bool) -> void:
	world_label.text = "СОН" if is_dream else "ЯВЬ"
	world_label.modulate = Color(0.75, 0.7, 1.0) if is_dream else Color(0.9, 0.8, 0.6)
	clarity_bar.visible = is_dream
	var cap := get_node_or_null("Root/ClarityCaption")
	if cap:
		cap.visible = is_dream
	# v0.7: у сна и яви разные инвентари — хотбар перерисовываем при смене мира.
	_refresh_inv()


func _on_clarity(value: float, max_value: float) -> void:
	clarity_bar.max_value = max_value
	clarity_bar.value = value


func _refresh_inv() -> void:
	_dev_badge.visible = GameState.dev_mode
	for i in range(_hotbar.size()):
		var d: Dictionary = GameState.get_slot(i)
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
	_debug_t += delta
	if _debug_label.visible and _debug_t > 0.25:
		_debug_t = 0.0
		_update_debug()
	if _boss_wrap == null:
		return
	var bosses: Array = get_tree().get_nodes_in_group("boss") if get_tree() else []
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
	var ph := int(live.get("phase")) if "phase" in live else 1
	var vuln := bool(live.call("is_vulnerable")) if live.has_method("is_vulnerable") else false
	var title := str(live.call("boss_title")) if live.has_method("boss_title") else "Мать блоков"
	var extra := "   — УЯЗВИМА!" if vuln else ""
	if live.has_method("boss_hint"):
		extra = str(live.call("boss_hint"))
	_boss_label.text = "%s · фаза %d   %d / %d%s" % [title, ph, hp, mx, extra]
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


