extends Node
## v0.5: настройки игры (user://settings.cfg). Автозагрузка GameSettings.

signal settings_changed

const PATH := "user://settings.cfg"

var master_volume: float = 0.9
var music_volume: float = 0.8
var sfx_volume: float = 0.9
var brightness: float = 1.0
var render_distance: int = 3      # радиус прогрузки мира в чанках (16×16)
var entity_distance: int = 3      # радиус симуляции/отрисовки сущностей в чанках
var shadows: bool = true
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false
var show_fps: bool = false
var fov: float = 75.0            # v0.24: угол обзора
var head_bob: bool = true        # v0.24: покачивание камеры при ходьбе
var camera_shake: bool = true    # v0.24: тряска камеры от ударов и босс-атак
var error_logger: Logger = null
var dream_start: bool = true    # v0.20: новый мир начинается во Сне с обучением

const RENDER_MIN := 2
const RENDER_MAX := 8
const ENTITY_MIN := 1
const ENTITY_MAX := 6


## v0.6: переназначаемое управление. [action, подпись, тип ("key"/"mouse"), код по умолчанию]
## v0.20: заголовки разделов в меню управления — раздел начинается с указанного действия.
const SECTIONS := {"move_forward": "Движение", "attack_break": "Действия и Явь", "dream_palette": "Сон — главный мир: проектирование, якоря, испытание", "toggle_debug": "Прочее", "hotbar_1": "Хотбар"}

const BINDABLE := [
	["move_forward", "Вперёд", "key", KEY_W],
	["move_back", "Назад", "key", KEY_S],
	["move_left", "Влево", "key", KEY_A],
	["move_right", "Вправо", "key", KEY_D],
	["jump", "Прыжок / вверх в полёте", "key", KEY_SPACE],
	["sprint", "Бег", "key", KEY_SHIFT],
	["fly_down", "Вниз в полёте", "key", KEY_CTRL],
	["toggle_fly", "Полёт во сне", "key", KEY_V],
	["attack_break", "Удар и сломать", "mouse", MOUSE_BUTTON_LEFT],
	["use_place", "Использовать и поставить", "mouse", MOUSE_BUTTON_RIGHT],
	["drop_item", "Выбросить предмет, с Ctrl — всю стопку", "key", KEY_Q],
	["interact", "Взаимодействие: кровать — сон, верстак, станок", "key", KEY_E],
	["open_inventory", "Инвентарь", "key", KEY_I],
	["use_heal", "Лечение: само выберет зелье", "key", KEY_H],
	["pillow_check", "Заглянуть под подушку у кровати", "key", KEY_Y],
	["dream_palette", "Сон: материал палитры, с Shift — назад", "key", KEY_T],
	["craft_nail", "Крафт во Сне", "key", KEY_C],
	["cycle_anchor", "Сменить якорь", "key", KEY_R],
	["anchor_place", "Поставить якорь", "key", KEY_Q],
	["place_beacon", "Поставить маяк", "key", KEY_G],
	["wake_up", "Проснуться", "key", KEY_F],
	["dream_frame", "Сон: угол рамки, с Shift — по блоку", "key", KEY_K],
	["dream_fill", "Сон: залить рамку, с Shift — очистить", "key", KEY_L],
	["dream_mirror", "Сон: зеркало X / Z / выкл", "key", KEY_X],
	["dream_undo", "Сон: отменить правку", "key", KEY_Z],
	["dream_redo", "Сон: вернуть правку", "key", KEY_U],
	["dream_trial", "Сон: испытание рамки фантомами", "key", KEY_M],
	["dream_offer", "Сон: исполнить просьбу Сна", "key", KEY_J],
	["blueprint_save", "Архив Снов: сохранить рамку в чертёж", "key", KEY_B],
	["blueprint_show", "Архив Снов: выбрать чертёж", "key", KEY_N],
	["blueprint_paste", "Сон: вставить чертёж у прицела", "key", KEY_P],
	["blueprint_rotate", "Сон: повернуть чертёж на 90°", "key", KEY_O],
	["tutorial_skip", "Пропустить обучение во Сне", "key", KEY_F1],
	["net_chat", "Чат сетевой игры", "key", KEY_ENTER],
	["toggle_debug", "Отладка / FPS", "key", KEY_F3],
	["quick_save", "Быстрое сохранение", "key", KEY_F5],
	["quick_load", "Быстрая загрузка", "key", KEY_F9],
	["sens_down", "Чувствительность −", "key", KEY_BRACKETLEFT],
	["sens_up", "Чувствительность +", "key", KEY_BRACKETRIGHT],
	["hotbar_1", "Слот 1", "key", KEY_1],
	["hotbar_2", "Слот 2", "key", KEY_2],
	["hotbar_3", "Слот 3", "key", KEY_3],
	["hotbar_4", "Слот 4", "key", KEY_4],
	["hotbar_5", "Слот 5", "key", KEY_5],
	["hotbar_6", "Слот 6", "key", KEY_6],
	["hotbar_7", "Слот 7", "key", KEY_7],
	["hotbar_8", "Слот 8", "key", KEY_8],
	["hotbar_9", "Слот 9", "key", KEY_9],
]
## Доп. клавиши по умолчанию (не переназначаются отдельно, сбрасываются при переназначении).
const EXTRA_DEFAULTS := {"open_inventory": [KEY_TAB]}
var bindings: Dictionary = {} # action -> {"type": "key"/"mouse", "code": int}


func _ready() -> void:
	error_logger = load("res://scripts/error_log.gd").new()
	OS.add_logger(error_logger)
	_init_bindings()
	load_settings()
	apply_bindings()
	apply_audio()
	apply_window()
	# v0.21: звуковые плееры, ещё играющие при выходе, держали 8 аудио-ресурсов
	# («resources still in use at exit»). Глушим и отвязываем поток при уходе из дерева.
	get_tree().node_added.connect(_track_audio)
	# Закрытие окна тоже идёт через safe_quit (сейв делает save_system по тому же уведомлению).
	get_tree().set_auto_accept_quit(false)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	brightness = clampf(float(cfg.get_value("video", "brightness", brightness)), 0.5, 1.6)
	render_distance = clampi(int(cfg.get_value("video", "render_distance", render_distance)), RENDER_MIN, RENDER_MAX)
	entity_distance = clampi(int(cfg.get_value("video", "entity_distance", entity_distance)), ENTITY_MIN, ENTITY_MAX)
	shadows = bool(cfg.get_value("video", "shadows", shadows))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	dream_start = bool(cfg.get_value("game", "dream_start", dream_start))
	mouse_sensitivity = clampf(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 4.0)
	fov = clampf(float(cfg.get_value("video", "fov", fov)), 60.0, 100.0)
	head_bob = bool(cfg.get_value("video", "head_bob", head_bob))
	camera_shake = bool(cfg.get_value("video", "camera_shake", camera_shake))
	if cfg.has_section("keybinds"):
		for row in BINDABLE:
			var a: String = row[0]
			if not cfg.has_section_key("keybinds", a):
				continue
			var v: Variant = cfg.get_value("keybinds", a, "")
			if typeof(v) == TYPE_STRING:
				var b := _parse_binding(str(v))
				if not b.is_empty():
					bindings[a] = b


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "render_distance", render_distance)
	cfg.set_value("video", "entity_distance", entity_distance)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("game", "dream_start", dream_start)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "head_bob", head_bob)
	cfg.set_value("video", "camera_shake", camera_shake)
	for row in BINDABLE:
		var a: String = row[0]
		if bindings.has(a):
			cfg.set_value("keybinds", a, _binding_str(bindings[a]))
	cfg.save(PATH)


# --- Переназначение клавиш ---

func _init_bindings() -> void:
	bindings = {}
	for row in BINDABLE:
		bindings[str(row[0])] = {"type": str(row[2]), "code": int(row[3])}


func default_binding(action: String) -> Dictionary:
	for row in BINDABLE:
		if str(row[0]) == action:
			return {"type": str(row[2]), "code": int(row[3])}
	return {}


func action_title(action: String) -> String:
	for row in BINDABLE:
		if str(row[0]) == action:
			return str(row[1])
	return action


static func _binding_str(b: Dictionary) -> String:
	return "%s:%d" % [str(b.get("type", "key")), int(b.get("code", 0))]


static func _parse_binding(v: String) -> Dictionary:
	var parts := v.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	var t := parts[0]
	if t != "key" and t != "mouse":
		return {}
	return {"type": t, "code": parts[1].to_int()}


static func make_event(b: Dictionary) -> InputEvent:
	if str(b.get("type", "key")) == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(b.get("code", 1)) as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(b.get("code", 0)) as Key
	return k


static func binding_from_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		var code: int = int(ke.physical_keycode) if int(ke.physical_keycode) != 0 else int(ke.keycode)
		return {"type": "key", "code": code}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "code": int((ev as InputEventMouseButton).button_index)}
	return {}


static func binding_label(b: Dictionary) -> String:
	if b.is_empty():
		return "—"
	var code := int(b.get("code", 0))
	if str(b.get("type", "key")) == "mouse":
		match code:
			MOUSE_BUTTON_LEFT:
				return "ЛКМ"
			MOUSE_BUTTON_RIGHT:
				return "ПКМ"
			MOUSE_BUTTON_MIDDLE:
				return "СКМ"
			MOUSE_BUTTON_XBUTTON1:
				return "Мышь 4"
			MOUSE_BUTTON_XBUTTON2:
				return "Мышь 5"
			_:
				return "Мышь %d" % code
	var s := OS.get_keycode_string(code as Key)
	return s if s != "" else "Клавиша %d" % code


func key_label(action: String) -> String:
	return binding_label(bindings.get(action, {}))


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)


func apply_bindings() -> void:
	for row in BINDABLE:
		var a: String = row[0]
		_ensure_action(a)
		InputMap.action_erase_events(a)
		var b: Dictionary = bindings.get(a, default_binding(a))
		InputMap.action_add_event(a, make_event(b))
		if EXTRA_DEFAULTS.has(a) and b == default_binding(a):
			for extra in EXTRA_DEFAULTS[a]:
				InputMap.action_add_event(a, make_event({"type": "key", "code": int(extra)}))


## v0.23: пары действий из разных миров, которым можно делить клавишу (Q: выбросить в Яви, якорь во Сне).
const SHARED_KEYS := [["drop_item", "anchor_place"]]


static func shares_key(a: String, b: String) -> bool:
	for pair in SHARED_KEYS:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


func find_conflict(action: String, b: Dictionary) -> String:
	for row in BINDABLE:
		var a: String = row[0]
		if a != action and bindings.get(a, {}) == b and not shares_key(a, action):
			return a
	return ""


func rebind(action: String, b: Dictionary) -> String:
	## Назначает b действию. Если b уже занята — действия меняются клавишами (swap). Возвращает имя
	## конфликтного действия ("" если конфликта не было).
	if b.is_empty() or not bindings.has(action):
		return ""
	var other := find_conflict(action, b)
	var old: Dictionary = bindings[action]
	bindings[action] = b
	if other != "":
		bindings[other] = old
	apply_bindings()
	save_settings()
	settings_changed.emit()
	return other


func reset_bindings() -> void:
	_init_bindings()
	apply_bindings()
	save_settings()
	settings_changed.emit()


func set_value(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			master_volume = clampf(float(value), 0.0, 1.0)
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
		"sfx_volume":
			sfx_volume = clampf(float(value), 0.0, 1.0)
		"brightness":
			brightness = clampf(float(value), 0.5, 1.6)
		"render_distance":
			render_distance = clampi(int(value), RENDER_MIN, RENDER_MAX)
		"entity_distance":
			entity_distance = clampi(int(value), ENTITY_MIN, ENTITY_MAX)
		"shadows":
			shadows = bool(value)
		"fullscreen":
			fullscreen = bool(value)
			apply_window()
		"show_fps":
			show_fps = bool(value)
		"dream_start":
			dream_start = bool(value)
		"mouse_sensitivity":
			mouse_sensitivity = clampf(float(value), 0.2, 4.0)
		"fov":
			fov = clampf(float(value), 60.0, 100.0)
		"head_bob":
			head_bob = bool(value)
		"camera_shake":
			camera_shake = bool(value)
	apply_audio()
	save_settings()
	settings_changed.emit()


func entity_distance_m() -> float:
	return float(entity_distance) * 16.0


func apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


func apply_environment(env: Environment) -> void:
	if env == null:
		return
	apply_distance_fog(env)
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0


func fog_end_distance() -> float:
	return maxf(12.0,render_distance*16.0-8.0)

func apply_distance_fog(env: Environment) -> void:
	if env == null: return
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	# v0.24: туман и дождь приближают туман (GameState.weather_fog_k 0…1)
	var wk := 0.0
	var gs := get_node_or_null("/root/GameState")
	if gs and not gs.is_dream(): wk = float(gs.weather_fog_k)
	env.fog_depth_begin = fog_end_distance()*0.35*lerpf(1.0, 0.15, wk)
	env.fog_depth_end = fog_end_distance()*lerpf(1.0, 0.35, wk)
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.8
	var camera := get_viewport().get_camera_3d()
	if camera: camera.far = fog_end_distance()+8.0


## v0.21: отслеживание аудио-плееров для чистого выхода (см. _ready).
func _track_audio(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		if not n.tree_exiting.is_connected(_release_audio):
			n.tree_exiting.connect(_release_audio.bind(n))


func _release_audio(n: Node) -> void:
	# В проекте плееры не переподвешиваются (remove_child/reparent нет), так что уход из дерева = удаление.
	if not is_instance_valid(n):
		return
	n.call(&"stop")
	n.set(&"stream", null)


var _quit_started := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		safe_quit(0)


## v0.21: чистый выход. Глушим все плееры, даём аудиосерверу пару кадров отпустить
## воспроизведения и только потом выходим — иначе «resources still in use at exit».
func error_log_path() -> String:
	return load("res://scripts/error_log.gd").global_path()


func safe_quit(code: int = 0) -> void:
	if _quit_started:
		return
	_quit_started = true
	var tree := get_tree()
	for n in tree.root.find_children("*", "AudioStreamPlayer", true, false) + tree.root.find_children("*", "AudioStreamPlayer3D", true, false) + tree.root.find_children("*", "AudioStreamPlayer2D", true, false):
		_release_audio(n)
	for i in range(3):
		await tree.process_frame
	await tree.create_timer(0.2, true, false, true).timeout
	tree.quit(code)
