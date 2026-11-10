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
	for k in _screens.keys():
		_ui.add_child(_screens[k])
	var ver := Label.new()
	ver.text = "Сонная стройка v0.9 · Godot 4.7"
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
	_main_btn(box, "Настройки", _open_settings)
	_main_btn(box, "Выход", func() -> void: get_tree().quit())
	return root


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
	_peaceful.text = "Мирный режим (враги не появляются)"
	box.add_child(_peaceful)
	_tutorial = CheckButton.new()
	_tutorial.text = "Пройти обучение?"
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
		_seed_info.text = "Сид разработчика: все ресурсы, предметы, якоря и маяки бесконечны (∞), ясность во сне не тратится."
		_seed_info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
		return
	elif t.is_valid_int():
		_seed_info.text = "Числовой сид: %s" % t
	else:
		_seed_info.text = "Текстовый сид → число %d (хеш строки)." % GameState.seed_from_text(t)
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
		_world_list.add_item("%s  —  сид %s%s  ·  %s" % [str(w.get("name", "?")), str(w.get("seed", "?")), tags, when])
	_del_armed = false
	_del_btn.text = "Удалить"
	if not _worlds.is_empty():
		_world_list.select(0)
	_play_btn.disabled = _worlds.is_empty()
	_del_btn.disabled = _worlds.is_empty()


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


func _create_world() -> void:
	var stext := _seed_edit.text.strip_edges()
	var sv := GameState.seed_from_text(stext)
	var meta := WorldStore.create_world(_name_edit.text, stext, sv, _peaceful.button_pressed)
	meta["tutorial_enabled"] = _tutorial.button_pressed
	WorldStore.write_meta(str(meta["folder"]), meta)
	_start_world(meta)


func _start_world(meta: Dictionary) -> void:
	var folder := str(meta.get("folder", ""))
	GameState.begin_world(str(meta.get("name", "Мир")), folder, str(meta.get("seed_text", "")),
		WorldStore.meta_seed(meta), bool(meta.get("peaceful", false)))
	GameState.tutorial_enabled = bool(meta.get("tutorial_enabled", true))
	WorldStore.touch(folder)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


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
