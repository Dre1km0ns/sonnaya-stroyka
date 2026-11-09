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


func _ready() -> void:
	load_settings()
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
	cfg.save(PATH)


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
