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

const RENDER_MIN := 2
const RENDER_MAX := 8
const ENTITY_MIN := 1
const ENTITY_MAX := 6


## v0.6: переназначаемое управление. [action, подпись, тип ("key"/"mouse"), код по умолчанию]
const BINDABLE := [
	["move_forward", "Вперёд", "key", KEY_W],
	["move_back", "Назад", "key", KEY_S],
	["move_left", "Влево", "key", KEY_A],
	["move_right", "Вправо", "key", KEY_D],
	["jump", "Прыжок / вверх (полёт)", "key", KEY_SPACE],
	["sprint", "Бег", "key", KEY_SHIFT],
	["fly_down", "Вниз (полёт)", "key", KEY_CTRL],
	["place_block", "Удар / поставить / использовать", "mouse", MOUSE_BUTTON_LEFT],
	["remove_block", "Снять блок / копать", "mouse", MOUSE_BUTTON_RIGHT],
	["interact", "Взаимодействие (кровать, подбор, верстак)", "key", KEY_E],
	["open_inventory", "Инвентарь", "key", KEY_I],
	["craft_nail", "Крафт (во сне)", "key", KEY_C],
	["cycle_anchor", "Сменить якорь", "key", KEY_R],
	["anchor_place", "Поставить якорь", "key", KEY_Q],
	["place_beacon", "Поставить маяк", "key", KEY_G],
	["wake_up", "Проснуться", "key", KEY_F],
	["toggle_fly", "Полёт во сне", "key", KEY_V],
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
	_init_bindings()
	load_settings()
	apply_bindings()
	apply_audio()
	apply_window()


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
	mouse_sensitivity = clampf(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 4.0)
	if cfg.has_section("keybinds"):
		for row in BINDABLE:
			var a: String = row[0]
			var v: Variant = cfg.get_value("keybinds", a, null)
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
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
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


func find_conflict(action: String, b: Dictionary) -> String:
	for row in BINDABLE:
		var a: String = row[0]
		if a != action and bindings.get(a, {}) == b:
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
		"mouse_sensitivity":
			mouse_sensitivity = clampf(float(value), 0.2, 4.0)
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
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
