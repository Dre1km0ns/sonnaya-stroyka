extends Node3D
## v0.24: погода Яви — ясно / дождь / туман. Меняется каждые 4–9 минут Яви, плавно (≈8 с).
## Дождь: капли вокруг игрока, шум дождя, свет солнца тусклее. Туман: дальность тумана ×0.35.
## Во Сне погоды нет. Состояние в GameState.weather (сохраняется), множители — GameState.weather_fog_k / weather_rain_k.
const KINDS := ["clear", "rain", "fog"]
const NAMES := {"clear": "ясно", "rain": "дождь", "fog": "туман"}
const MIN_T := 240.0
const MAX_T := 540.0
const BLEND := 8.0
var _rain: CPUParticles3D
var _snd: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16, 0.5, 16)
	_rain.direction = Vector3(0.08, -1, 0.04)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0, -30, 0)
	_rain.initial_velocity_min = 14.0
	_rain.initial_velocity_max = 18.0
	_rain.local_coords = false
	var qm := BoxMesh.new(); qm.size = Vector3(0.025, 0.42, 0.025)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.7, 0.78, 0.95, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = m
	_rain.mesh = qm
	_rain.emitting = false
	_rain.visible = false
	add_child(_rain)
	_snd = AudioStreamPlayer.new()
	_snd.name = "RainSound"
	_snd.bus = "SFX"
	var st: AudioStream = load("res://assets/audio/sfx_rain_loop.ogg")
	if st is AudioStreamOggVorbis: (st as AudioStreamOggVorbis).loop = true
	_snd.stream = st
	_snd.volume_db = -60.0
	add_child(_snd)
	if GameState.weather_left <= 0.0:
		GameState.weather_left = _rng.randf_range(MIN_T, MAX_T)


func set_weather(kind: String, instant: bool = false) -> void:
	GameState.weather = kind if kind in KINDS else "clear"
	GameState.weather_left = _rng.randf_range(MIN_T, MAX_T)
	if instant:
		GameState.weather_rain_k = 1.0 if GameState.weather == "rain" else 0.0
		GameState.weather_fog_k = 1.0 if GameState.weather == "fog" else (0.25 if GameState.weather == "rain" else 0.0)
	GameState.weather_changed.emit(GameState.weather)


func _roll() -> String:
	var r := _rng.randf()
	if r < 0.55: return "clear"
	if r < 0.80: return "rain"
	return "fog"


func _process(delta: float) -> void:
	var dream := GameState.is_dream()
	if not dream and not GameState.ui_blocked():
		GameState.weather_left -= delta
		if GameState.weather_left <= 0.0:
			set_weather(_roll())
	var w := GameState.weather
	var rain_t := 1.0 if w == "rain" else 0.0
	var fog_t := 1.0 if w == "fog" else (0.25 if w == "rain" else 0.0)
	GameState.weather_rain_k = move_toward(GameState.weather_rain_k, rain_t, delta / BLEND)
	GameState.weather_fog_k = move_toward(GameState.weather_fog_k, fog_t, delta / BLEND)
	var rk := 0.0 if dream else GameState.weather_rain_k
	var cam := get_viewport().get_camera_3d()
	_rain.visible = rk > 0.02
	_rain.emitting = rk > 0.02
	if cam:
		_rain.global_position = cam.global_position + Vector3(0, 9, 0)
	if rk > 0.02:
		if not _snd.playing: _snd.play()
		_snd.volume_db = linear_to_db(maxf(0.0001, rk * 0.55))
	elif _snd.playing:
		_snd.stop()
