extends Node3D
## v0.5: главное меню с панорамой мира (камера медленно облетает сгенерированный мир),
## выбор мира, создание мира (имя, сид, мирный режим), настройки, выход.

const UiTheme := preload("res://scripts/ui_theme.gd")
const WorldStore := preload("res://scripts/world_store.gd")
const PANORAMA_SEED := 20260511

var _cam: Camera3D
var _focus: Node3D
var _chunks: Node3D
var _orbit_center := Vector3.ZERO
var _angle := 0.0
var _ui: Control
var _screens: Dictionary = {}
var _world_list: ItemList
var _worlds: Array = []
var _play_btn: Button
var _del_btn: Button
var _del_armed := false
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _tutorial: CheckButton
var _peaceful: CheckButton
var _difficulty: OptionButton
var _diff_info: Label
var _seed_info: Label
var _env: Environment
var _settings: Control = null


func _ready() -> void:
	get_tree().paused = false
	GameState.paused = false
	GameState.inventory_open = false
	GameState.craft_menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_panorama()
	_build_ui()
	_start_music()
	_show("main")
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.settings_changed.connect(func() -> void: gsets.apply_environment(_env))
	if "--shots08-menu" in OS.get_cmdline_user_args():
		call_deferred("_capture_v08_menu")
	if "--menu-shots" in OS.get_cmdline_user_args():
		call_deferred("_capture_shots")


# ------------------------------------------------------------- панорама

func _build_panorama() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.48, 0.72)
	mat.sky_horizon_color = Color(0.86, 0.74, 0.70)
	mat.ground_horizon_color = Color(0.78, 0.74, 0.76)
	mat.ground_bottom_color = Color(0.78, 0.74, 0.76)
	sky.sky_material = mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.62, 0.62, 0.66)
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.78, 0.74, 0.76)
	_env.fog_density = 0.011
	_env.fog_sky_affect = 0.3
	_env.glow_enabled = true
	_env.glow_intensity = 0.3
	we.environment = _env
	add_child(we)
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.apply_environment(_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_color = Color(1.0, 0.9, 0.8)
	sun.light_energy = 1.15
	sun.shadow_enabled = gsets == null or bool(gsets.shadows)
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	var cm_script: GDScript = load("res://scripts/chunk_manager.gd")
	_chunks = cm_script.new()
	_chunks.name = "PanoramaChunks"
	_chunks.panorama_mode = true
	_chunks.is_dream_layer = false
	_chunks.load_radius = 3
	_chunks.unload_radius = 4
	add_child(_chunks)
	_focus = Node3D.new()
	add_child(_focus)
	# Ищем ближайшую руину — облетаем её (холмы, озёра вокруг).
	_chunks.set("_seed", PANORAMA_SEED)
	var best := Vector2i(3, 2)
	var best_d := 999999
	for cx in range(-6, 7):
		for cz in range(-6, 7):
			var c := Vector2i(cx, cz)
			if maxi(absi(cx), absi(cz)) < 2:
				continue
			if _chunks.chunk_has_ruin(c) and c.length_squared() < best_d:
				best_d = c.length_squared()
				best = c
	_orbit_center = _chunks.chunk_origin(best) + Vector3(8, 0, 8)
	_focus.position = _orbit_center
	_chunks.setup(_focus, PANORAMA_SEED)
	_chunks.load_all_pending()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.current = true
	add_child(_cam)
	_update_cam()


func _update_cam() -> void:
	var r := 22.0
	var p := _orbit_center + Vector3(cos(_angle) * r, 11.0, sin(_angle) * r)
	_cam.position = p
	_cam.look_at(_orbit_center + Vector3(0, 1.0, 0), Vector3.UP)


func _process(delta: float) -> void:
	_angle += delta * 0.045
	_update_cam()


func _start_music() -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -10.0
	var stream: Resource = load("res://assets/audio/music.mp3")
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
		p.stream = stream
		add_child(p)
		p.play()


# ------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiTheme.make()
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.08, 0.25)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_screens["main"] = _build_main_screen()
	_screens["worlds"] = _build_worlds_screen()
	_screens["create"] = _build_create_screen()
	_screens["howto"] = _build_howto_screen()
	_screens["join"] = _build_join_screen()
	_screens["progress"] = _build_progress_screen()
	for k in _screens.keys():
		_ui.add_child(_screens[k])
	var ver := Label.new()
	ver.text = "Сонная стройка v0.24 · Godot 4.7"
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 14
	ver.offset_top = -32
	ver.offset_right = 400
	ver.offset_bottom = -8
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ver.add_theme_constant_override("outline_size", 4)
	_ui.add_child(ver)


func _screen_root() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build_main_screen() -> Control:
	var root := _screen_root()
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.0
	box.anchor_bottom = 1.0
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = 90
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var title := UiTheme.title_label("Сонная стройка", 64)
	box.add_child(title)
	var sub := UiTheme.title_label("строй во сне — забирай в явь", 20)
	sub.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 50)
	box.add_child(spacer)
	_main_btn(box, "Играть", _on_play)
	_main_btn(box, "Создать сетевую игру", _on_host_game)
	_main_btn(box, "Подключиться", func() -> void: _show("join"))
	_main_btn(box, "Прогресс", func() -> void:
		_refresh_progress()
		_show("progress"))
	_main_btn(box, "Как играть", func() -> void: _show("howto"))
	_main_btn(box, "Настройки", _open_settings)
	_main_btn(box, "Выход", func() -> void: GameSettings.safe_quit(0))
	return root


const HOWTO := """[b]Сон — главный мир.[/b] Новая игра начинается во Сне. Здесь ты летаешь, строишь из ничего и проектируешь. Явь — суровая проверка: туда твои проекты переносятся копией.

[color=#d8c8ff][b]Во Сне[/b][/color]
• ПКМ — блок, ЛКМ — снять, T — материал палитры. Дрейф бесплатен, но нестабилен.
• K, K — рамка; L — залить, Shift+L — очистить; X — зеркало; Z/U — отмена и возврат.
• M — испытание: фантомы осаждают постройку в рамке. Дыры и дрейф — слабые места, свет их сжигает.
• B — рамку в чертёж, N — выбрать, O — повернуть, P — вставить.
• R/Q — якорь: закреплённое при пробуждении (F) появится в Яви копией. Оригинал остаётся во Сне.

[color=#ffd98c][b]В Яви[/b][/color]
• ЛКМ — удар и добыча с любым предметом в руке, ПКМ — поставить блок или факел и использовать: дверь, Яйцо Анаконды. Q — выбросить предмет, Ctrl+Q — всю стопку.
• Добывай материалы: первый же блок даёт [i]отпечаток[/i] — во Сне этот материал станет бесконечным.
• Копия в Явь стоит 1 материал Яви за блок и не мутирует. Дрейф переносится бесплатно, но может мутировать.
• Осознанность копится в Яви. Её тратят якоря и большие операции.
• Если сломать материализованное, во Сне появится трещина. Кошмары грызут дрейф рядом, свет и маяк защищают.

[color=#a8f0b0][b]Цель[/b][/color] — проектировать во Сне то, что в Яви невозможно построить руками, испытывать и забирать в Явь. Боссы открывают сады Сна с новыми материалами.

Все клавиши — Настройки → Управление (раздел «Сон»)."""


func _build_howto_screen() -> Control:
	var pr := _panel_screen("Как играть", 760)
	var box: VBoxContainer = pr[1]
	var rt := RichTextLabel.new()
	rt.name = "HowtoText"
	rt.bbcode_enabled = true
	rt.text = HOWTO
	rt.fit_content = false
	rt.scroll_active = true
	rt.custom_minimum_size = Vector2(720, 420)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 17)
	box.add_child(rt)
	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func() -> void: _show("main"))
	box.add_child(back)
	return pr[0]


func _main_btn(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _panel_screen(title: String, min_w: float) -> Array:
	var root := _screen_root()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiTheme.title_label(title, 32))
	return [root, box]


func _build_worlds_screen() -> Control:
	var pr := _panel_screen("Выбор мира", 720)
	var box: VBoxContainer = pr[1]
	_world_list = ItemList.new()
	_world_list.custom_minimum_size = Vector2(0, 300)
	_world_list.item_activated.connect(func(_i: int) -> void: _play_selected())
	_world_list.item_selected.connect(func(_i: int) -> void:
		_del_armed = false
		_del_btn.text = "Удалить"
		_play_btn.disabled = false
		_del_btn.disabled = false)
	box.add_child(_world_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "Играть в выбранный мир"
	_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_btn.custom_minimum_size = Vector2(0, 48)
	_play_btn.pressed.connect(_play_selected)
	row.add_child(_play_btn)
	var create := Button.new()
	create.text = "Создать новый мир"
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.custom_minimum_size = Vector2(0, 48)
	create.pressed.connect(func() -> void: _show("create"))
	row.add_child(create)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	box.add_child(row2)
	_del_btn = Button.new()
	_del_btn.text = "Удалить"
	_del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_del_btn.custom_minimum_size = Vector2(0, 44)
	_del_btn.pressed.connect(_delete_selected)
	row2.add_child(_del_btn)
	var back := Button.new()
	back.text = "Назад"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func() -> void: _show("main"))
	row2.add_child(back)
	return pr[0]


func _build_create_screen() -> Control:
	var pr := _panel_screen("Создание мира", 640)
	var box: VBoxContainer = pr[1]
	var l1 := Label.new()
	l1.text = "Название мира"
	box.add_child(l1)
	_name_edit = LineEdit.new()
	_name_edit.text = "Новый мир"
	_name_edit.max_length = 40
	box.add_child(_name_edit)
	var l2 := Label.new()
	l2.text = "Сид для генератора мира"
	box.add_child(l2)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Оставь пустым — будет случайный"
	_seed_edit.max_length = 32
	_seed_edit.text_changed.connect(func(_t: String) -> void: _update_seed_info())
	box.add_child(_seed_edit)
	_seed_info = Label.new()
	_seed_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seed_info.add_theme_font_size_override("font_size", 14)
	_seed_info.add_theme_color_override("font_color", Color(0.78, 0.78, 0.86))
	box.add_child(_seed_info)
	_peaceful = CheckButton.new()
	_peaceful.text = "Мирный режим — без врагов"
	box.add_child(_peaceful)
	# v0.24: сложность выбирается при создании и хранится в мире.
	var drow := HBoxContainer.new(); drow.add_theme_constant_override("separation", 10)
	var dl := Label.new(); dl.text = "Сложность:"; drow.add_child(dl)
	_difficulty = OptionButton.new(); _difficulty.name = "Difficulty"
	_difficulty.add_item("Нормальный", 0); _difficulty.add_item("Эксперт", 1)
	_difficulty.item_selected.connect(func(_i: int) -> void: _update_diff_info())
	drow.add_child(_difficulty)
	box.add_child(drow)
	_diff_info = Label.new()
	_diff_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_info.add_theme_font_size_override("font_size", 14)
	_diff_info.add_theme_color_override("font_color", Color(0.78, 0.78, 0.86))
	box.add_child(_diff_info)
	_update_diff_info()
	_tutorial = CheckButton.new()
	_tutorial.text = "Пройти обучение во Сне — 7 шагов, около 3 минут"
	_tutorial.button_pressed = true
	box.add_child(_tutorial)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var ok := Button.new()
	ok.name = "CreateBtn"
	ok.text = "Создать мир"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.custom_minimum_size = Vector2(0, 50)
	ok.pressed.connect(_create_world)
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, 50)
	cancel.pressed.connect(func() -> void:
		if _worlds.is_empty():
			_show("main")
		else:
			_show("worlds"))
	row.add_child(cancel)
	_update_seed_info()
	return pr[0]


func _update_seed_info() -> void:
	var t := _seed_edit.text.strip_edges()
	if t == "":
		_seed_info.text = "Сид задаёт рельеф, холмы, озёра, руины, места и типы реагентов и мир сна. Один сид — один и тот же мир."
	elif t == str(GameState.DEV_SEED):
		_seed_info.text = "Сид разработчика: все ресурсы, предметы, якоря и маяки бесконечны, осознанность во сне не тратится."
		_seed_info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
		return
	elif t.is_valid_int():
		_seed_info.text = "Числовой сид: %s" % t
	else:
		_seed_info.text = "Текстовый сид → число %d." % GameState.seed_from_text(t)
	_seed_info.add_theme_color_override("font_color", Color(0.78, 0.78, 0.86))


func _show(screen: String) -> void:
	for k in _screens.keys():
		_screens[k].visible = k == screen
	if screen == "worlds":
		_refresh_worlds()
	if screen == "create":
		_name_edit.text = _unique_default_name()
		_seed_edit.text = ""
		_peaceful.button_pressed = false
		_difficulty.select(0)
		_update_diff_info()
		_update_seed_info()
		_name_edit.grab_focus()


func _unique_default_name() -> String:
	var names := {}
	for w in WorldStore.list_worlds():
		names[str(w.get("name", ""))] = true
	var base := "Новый мир"
	if not names.has(base):
		return base
	var n := 2
	while names.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func _refresh_worlds() -> void:
	_worlds = WorldStore.list_worlds()
	_world_list.clear()
	for w in _worlds:
		var dt := Time.get_datetime_dict_from_unix_time(int(float(w.get("last_played", 0))) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
		var when := "%02d.%02d %02d:%02d" % [int(dt.day), int(dt.month), int(dt.hour), int(dt.minute)]
		var tags := ""
		if bool(w.get("dev", false)):
			tags += " · DEV ∞"
		if bool(w.get("peaceful", false)):
			tags += " · мирный"
		if str(w.get("difficulty", "normal")) == "expert":
			tags += " · эксперт"
		_world_list.add_item("%s  —  сид %s%s  ·  %s" % [str(w.get("name", "?")), str(w.get("seed", "?")), tags, when])
	_del_armed = false
	_del_btn.text = "Удалить"
	if not _worlds.is_empty():
		_world_list.select(0)
	_play_btn.disabled = _worlds.is_empty()
	_del_btn.disabled = _worlds.is_empty()


# ---------------------------------------------------------------- v0.24: сеть
var _join_name: LineEdit
var _join_ip: LineEdit
var _join_status: Label
var _join_list: ItemList
var _join_found: Array = []
var _host_banner: Label


var _progress_box: VBoxContainer
var _progress_head: Label


func _build_progress_screen() -> Control:
	var pr := _panel_screen("Прогресс", 640)
	var box: VBoxContainer = pr[1]
	_progress_head = Label.new(); _progress_head.name = "ProgressHead"
	_progress_head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	box.add_child(_progress_head)
	_progress_box = VBoxContainer.new(); _progress_box.name = "ProgressList"
	_progress_box.add_theme_constant_override("separation", 6)
	box.add_child(_progress_box)
	var back := Button.new(); back.text = "Назад"; back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func() -> void: _show("main"))
	box.add_child(back)
	_refresh_progress()
	return pr[0]


func _refresh_progress() -> void:
	if _progress_box == null: return
	for c in _progress_box.get_children(): c.queue_free()
	var PS: GDScript = load("res://scripts/progress_store.gd")
	var done: Dictionary = PS.load_all()
	var n := 0
	for m in PS.LIST:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12)
		var mark := Label.new(); mark.custom_minimum_size = Vector2(30, 0)
		var ok := done.has(m[0])
		if ok: n += 1
		mark.text = "✔" if ok else "○"
		mark.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if ok else Color(0.5, 0.48, 0.58))
		row.add_child(mark)
		var t := Label.new(); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.text = "%s — %s" % [m[1], m[2]] + ("  · %s" % done[m[0]] if ok else "")
		t.add_theme_color_override("font_color", Color(0.95, 0.93, 0.98) if ok else Color(0.62, 0.6, 0.7))
		row.add_child(t)
		_progress_box.add_child(row)
	_progress_head.text = "Вехи: %d из %d — общие для всех миров." % [n, PS.LIST.size()]


func _on_host_game() -> void:
	## Хост выбирает или создаёт мир как обычно; сервер поднимается, когда мир загрузится.
	NetSession.leave()
	NetSession.want_host = true
	NetSession.player_name = _saved_name()
	_on_play()
	if _host_banner: _host_banner.visible = true


func _saved_name() -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://net.cfg")
	return str(cfg.get_value("net", "name", "Игрок"))


func _save_net(nm: String, ip: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "name", nm); cfg.set_value("net", "ip", ip)
	cfg.save("user://net.cfg")


func _build_join_screen() -> Control:
	var pr := _panel_screen("Подключиться к сетевой игре", 640)
	var box: VBoxContainer = pr[1]
	var cfg := ConfigFile.new(); cfg.load("user://net.cfg")
	var l1 := Label.new(); l1.text = "Твоё имя"; box.add_child(l1)
	_join_name = LineEdit.new(); _join_name.name = "JoinName"; _join_name.max_length = 20
	_join_name.text = str(cfg.get_value("net", "name", "Игрок")); box.add_child(_join_name)
	var l2 := Label.new(); l2.text = "IP-адрес хоста в локальной сети"; box.add_child(l2)
	_join_ip = LineEdit.new(); _join_ip.name = "JoinIp"; _join_ip.text = str(cfg.get_value("net", "ip", "127.0.0.1")); box.add_child(_join_ip)
	_join_list = ItemList.new(); _join_list.name = "LanList"; _join_list.custom_minimum_size = Vector2(0, 110)
	_join_list.item_selected.connect(func(i: int) -> void:
		if i < _join_found.size(): _join_ip.text = str(_join_found[i].ip))
	box.add_child(_join_list)
	_join_status = Label.new(); _join_status.name = "JoinStatus"
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.add_theme_color_override("font_color", Color(0.78, 0.78, 0.86))
	_join_status.text = "Хост жмёт «Создать сетевую игру» и выбирает мир. До 4 игроков, порт %d." % NetSession.PORT
	box.add_child(_join_status)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); box.add_child(row)
	var find := Button.new(); find.text = "Найти игры в сети"; find.size_flags_horizontal = Control.SIZE_EXPAND_FILL; find.custom_minimum_size = Vector2(0, 46)
	find.pressed.connect(func() -> void:
		_join_status.text = "Ищу игры в локальной сети…"
		NetSession.discover(1.5))
	row.add_child(find)
	var go := Button.new(); go.name = "JoinGo"; go.text = "Подключиться"; go.size_flags_horizontal = Control.SIZE_EXPAND_FILL; go.custom_minimum_size = Vector2(0, 46)
	go.pressed.connect(_do_join)
	row.add_child(go)
	var back := Button.new(); back.text = "Назад"; back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func() -> void:
		NetSession.leave()
		_show("main"))
	box.add_child(back)
	NetSession.lan_found.connect(func(list: Array) -> void:
		if not is_instance_valid(_join_list): return
		_join_found = list
		_join_list.clear()
		for g in list:
			_join_list.add_item("%s — мир «%s» · %s · игроков %d" % [g.host, g.world, g.ip, int(g.players)])
		_join_status.text = "Найдено игр: %d." % list.size() if not list.is_empty() else "Игр в сети не найдено. Введи IP хоста вручную.")
	NetSession.join_failed.connect(func(reason: String) -> void:
		if is_instance_valid(_join_status): _join_status.text = reason)
	NetSession.world_received.connect(func() -> void:
		if not is_inside_tree(): return
		_join_status.text = "Мир получен, загружаю…"
		NetSession.begin_client_world()
		_load_main("Загрузка сетевого мира…"))
	return pr[0]


func _do_join() -> void:
	var nm := _join_name.text.strip_edges()
	if nm == "": nm = "Игрок"
	_save_net(nm, _join_ip.text.strip_edges())
	NetSession.leave()
	NetSession.player_name = nm
	var err: String = NetSession.join(_join_ip.text)
	_join_status.text = err if err != "" else "Подключаюсь к %s…" % _join_ip.text.strip_edges()
	if err == "":
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if is_instance_valid(_join_status) and NetSession.is_client() and NetSession.pending_world.is_empty() and is_inside_tree():
				NetSession.leave()
				_join_status.text = "Хост не ответил. Проверь IP и что игра на хосте открыта.")


func _on_play() -> void:
	_worlds = WorldStore.list_worlds()
	if _worlds.is_empty():
		_show("create")
	else:
		_show("worlds")


func _selected_index() -> int:
	var sel := _world_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _play_selected() -> void:
	var i := _selected_index()
	if i < 0 or i >= _worlds.size():
		return
	_start_world(_worlds[i])


func _delete_selected() -> void:
	var i := _selected_index()
	if i < 0 or i >= _worlds.size():
		return
	if not _del_armed:
		_del_armed = true
		_del_btn.text = "Точно удалить «%s»?" % str(_worlds[i].get("name", ""))
		return
	WorldStore.delete_world(str(_worlds[i].get("folder", "")))
	_refresh_worlds()
	if _worlds.is_empty():
		_show("create")


func _update_diff_info() -> void:
	if _diff_info == null:
		return
	if _difficulty.selected == 1:
		_diff_info.text = "Эксперт: у всех мобов и боссов +75 % здоровья, они бьют больнее, бегают быстрее, раньше замечают и дольше преследуют."
	else:
		_diff_info.text = "Нормальный: задуманный баланс игры."


func _create_world() -> void:
	var stext := _seed_edit.text.strip_edges()
	var sv := GameState.seed_from_text(stext)
	var meta := WorldStore.create_world(_name_edit.text, stext, sv, _peaceful.button_pressed)
	meta["tutorial_enabled"] = _tutorial.button_pressed
	meta["difficulty"] = "expert" if _difficulty.selected == 1 else "normal"
	WorldStore.write_meta(str(meta["folder"]), meta)
	_start_world(meta)


func _start_world(meta: Dictionary) -> void:
	var folder := str(meta.get("folder", ""))
	GameState.begin_world(str(meta.get("name", "Мир")), folder, str(meta.get("seed_text", "")),
		WorldStore.meta_seed(meta), bool(meta.get("peaceful", false)))
	GameState.tutorial_enabled = bool(meta.get("tutorial_enabled", true))
	GameState.set_difficulty(str(meta.get("difficulty", "normal")))
	WorldStore.touch(folder)
	# v0.21 c2: первая генерация мира занимает 1–2 с — раньше всё это время висело замёрзшее меню.
	_load_main("Загрузка мира «%s»…" % str(meta.get("name", "Мир")))


var _load_bar: ProgressBar
var _load_stage: Label
const MAIN_SCENE := "res://scenes/main.tscn"


func _show_loading(text: String) -> void:
	var layer := CanvasLayer.new(); layer.name = "Loading"; layer.layer = 50; add_child(layer)
	var bg := ColorRect.new(); bg.color = Color(0.05, 0.04, 0.1, 0.94); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_CENTER); v.custom_minimum_size = Vector2(560, 0)
	v.position = Vector2(-280, -60); v.add_theme_constant_override("separation", 14)
	bg.add_child(v)
	var l := Label.new(); l.text = text; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30); l.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	v.add_child(l)
	# v0.24 (п.27): настоящая полоса загрузки — доля ресурсов сцены из ResourceLoader.
	_load_bar = ProgressBar.new(); _load_bar.name = "LoadBar"; _load_bar.min_value = 0; _load_bar.max_value = 100
	_load_bar.custom_minimum_size = Vector2(560, 26)
	v.add_child(_load_bar)
	_load_stage = Label.new(); _load_stage.name = "LoadStage"; _load_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_stage.add_theme_color_override("font_color", Color(0.7, 0.68, 0.85))
	_load_stage.text = "Готовлю ресурсы…"
	v.add_child(_load_stage)


var load_progress_seen: Array = []   # для smoke: какие доли видела полоса


func _load_main(text: String) -> void:
	_show_loading(text)
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":   # без окна (боты, проверки): фоновая загрузка там не продвигается — грузим сразу
		get_tree().change_scene_to_file(MAIN_SCENE)
		return
	if ResourceLoader.load_threaded_request(MAIN_SCENE, "", true) != OK:
		get_tree().change_scene_to_file(MAIN_SCENE)
		return
	var prog: Array = []
	while true:
		var st := ResourceLoader.load_threaded_get_status(MAIN_SCENE, prog)
		var k: float = float(prog[0]) if not prog.is_empty() else 0.0
		if st == ResourceLoader.THREAD_LOAD_LOADED: k = 1.0
		load_progress_seen.append(k)
		_load_bar.value = k * 90.0
		_load_stage.text = "Ресурсы мира: %d%%" % int(k * 100.0) if k < 1.0 else "Строю мир вокруг тебя…"
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		await get_tree().process_frame
	var ps := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	_load_bar.value = 95
	await get_tree().process_frame
	await get_tree().process_frame
	if ps: get_tree().change_scene_to_packed(ps)
	else: get_tree().change_scene_to_file(MAIN_SCENE)


func _open_settings() -> void:
	var sm_script: GDScript = load("res://scripts/settings_menu.gd")
	_settings = sm_script.new()
	_ui.add_child(_settings)


# ------------------------------------------------------------- скриншоты

func _snap(name: String) -> void:
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	img.save_png("/workspace/shots/%s" % name)
	print("SHOT saved ", name)


func _capture_shots() -> void:
	await get_tree().create_timer(1.0).timeout
	await _snap("v05_main_menu.png")
	_show("create")
	_seed_edit.text = "6767676767"
	_update_seed_info()
	await _snap("v05_world_create_dev.png")
	_seed_edit.text = "сонная деревня"
	_update_seed_info()
	await _snap("v05_world_create.png")
	var WS: GDScript = load("res://scripts/world_store.gd")
	var tmp_a: Dictionary = WS.create_world("Сонная деревня", "сонная деревня", GameState.seed_from_text("сонная деревня"), false)
	var tmp_b: Dictionary = WS.create_world("Разработка", "6767676767", GameState.DEV_SEED, true)
	_refresh_worlds()
	_show("worlds")
	await _snap("v05_world_select.png")
	WS.delete_world(str(tmp_a.get("folder", "")))
	WS.delete_world(str(tmp_b.get("folder", "")))
	_refresh_worlds()
	_show("main")
	_open_settings()
	await _snap("v05_settings.png")
	get_tree().quit(0)


func _capture_v08_menu() -> void:
	_show("create")
	await get_tree().create_timer(1.0).timeout
	await _snap("v08_tutorial_toggle.png")
	get_tree().quit(0)
