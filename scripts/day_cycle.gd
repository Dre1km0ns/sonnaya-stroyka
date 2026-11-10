extends Node
## v0.6: игровые сутки 24 реальные минуты: утро (3) → день (11) → вечер (3) → ночь (7).
## Солнце идёт по дуге с востока на запад, ночью — луна (тусклый голубой направленный свет) и звёзды.

const SkyShader := preload("res://shaders/sky.gdshader")

var time_of_day: float = 0.0
var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null
var _fill: OmniLight3D = null
var _env: Environment = null
var _sky_mat: ShaderMaterial = null
var _sky_t: float = 0.0

const SUN_MAX_ENERGY := 1.15
## v0.7: луна ярче — ночью без факелов видно силуэты мира.
const MOON_MAX_ENERGY := 0.47
var moon_energy := MOON_MAX_ENERGY
const MOON_COLOR := Color(0.62, 0.72, 1.0)

const DAY_TOP := Color(0.36, 0.58, 0.92)
const DAY_HORIZON := Color(0.72, 0.84, 0.96)
const DUSK_TOP := Color(0.32, 0.36, 0.62)
const DUSK_HORIZON := Color(0.98, 0.56, 0.34)
const NIGHT_TOP := Color(0.012, 0.018, 0.055)
const NIGHT_HORIZON := Color(0.05, 0.065, 0.13)
const DAY_AMBIENT := Color(0.66, 0.66, 0.64)
const NIGHT_AMBIENT := Color(0.30, 0.35, 0.52)
const NIGHT_AMBIENT_ENERGY := 0.62


func setup(sun: DirectionalLight3D, env: Environment, fill: OmniLight3D = null) -> void:
	_sun = sun
	_env = env
	_fill = fill
	add_to_group("day_cycle")
	moon_energy = GameState.moon_energy
	if GameState:
		time_of_day = float(GameState.day_time)
	if _sun and _sun.get_parent():
		_moon = DirectionalLight3D.new()
		_moon.name = "Moon"
		_moon.light_color = MOON_COLOR
		_moon.shadow_enabled = false
		_moon.light_energy = 0.0
		_sun.get_parent().add_child(_moon)
	if _env:
		var sky := Sky.new()
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = SkyShader
		sky.sky_material = _sky_mat
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		_env.sky = sky
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		_env.fog_sky_affect = 0.25
	apply_lighting()


func cycle_length() -> float:
	return GameState.DAY_CYCLE


func phase() -> String:
	return GameState.phase_at(time_of_day)


func is_night() -> bool:
	return phase() == "night"


func get_moon() -> DirectionalLight3D:
	return _moon


static func sun_angle(t: float) -> float:
	## 0..π — солнце над горизонтом (утро+день+вечер), π..2π — под горизонтом (ночь).
	var c: float = GameState.cycle_time(t)
	var daylight: float = GameState.PHASE_EVENING_END
	if c < daylight:
		return c / daylight * PI
	return PI + (c - daylight) / (GameState.DAY_CYCLE - daylight) * PI


static func dir_for_angle(a: float) -> Vector3:
	return Vector3(cos(a), sin(a) * 0.9, sin(a) * 0.42).normalized()


func sun_dir() -> Vector3:
	return dir_for_angle(sun_angle(time_of_day))


func moon_dir() -> Vector3:
	return -sun_dir()


func night_blend() -> float:
	## 0 — светло, 1 — глубокая ночь (по высоте солнца).
	return 1.0 - smoothstep(-0.12, 0.18, sun_dir().y)


func _process(delta: float) -> void:
	time_of_day += delta
	if GameState:
		GameState.day_time = time_of_day
		if GameState.has_method("notify_night_from_time"):
			GameState.notify_night_from_time()
		if GameState.is_dream():
			return
	_sky_t -= delta
	if _sky_t <= 0.0:
		_sky_t = 0.2
		apply_lighting()


func set_time(t: float) -> void:
	moon_energy = GameState.moon_energy
	time_of_day = t
	if GameState:
		GameState.day_time = t
		GameState.notify_night_from_time()
	apply_lighting()
	for h in get_tree().get_nodes_in_group("hud_phase"):
		h.call("_update_phase_label")


func apply_lighting() -> void:
	moon_energy = GameState.moon_energy
	var sd := sun_dir()
	var md := -sd
	var day_k := smoothstep(-0.10, 0.22, sd.y)          # солнце светит
	var moon_k := smoothstep(-0.05, 0.18, md.y)         # луна светит
	var warm := 0.0
	if sd.y > -0.15:
		warm = 1.0 - smoothstep(0.05, 0.42, sd.y)        # закат/рассвет
	var top := NIGHT_TOP.lerp(DAY_TOP.lerp(DUSK_TOP, warm * 0.8), day_k)
	var hor := NIGHT_HORIZON.lerp(DAY_HORIZON.lerp(DUSK_HORIZON, warm), day_k)
	if _env:
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT.lerp(Color(0.75, 0.62, 0.55), warm * 0.6), day_k)
		_env.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, 0.55, day_k)
		_env.fog_light_color = hor
		GameSettings.apply_distance_fog(_env)
		_env.glow_intensity = lerpf(0.4, 0.25, day_k)
		_env.background_color = hor
	if _sky_mat:
		_sky_mat.set_shader_parameter("top_color", Vector3(top.r, top.g, top.b))
		_sky_mat.set_shader_parameter("horizon_color", Vector3(hor.r, hor.g, hor.b))
		var gc := hor.darkened(0.45)
		_sky_mat.set_shader_parameter("ground_color", Vector3(gc.r, gc.g, gc.b))
		_sky_mat.set_shader_parameter("sun_dir", sd)
		_sky_mat.set_shader_parameter("moon_dir", md)
		var sc := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.55, 0.3), warm)
		_sky_mat.set_shader_parameter("sun_color", Vector3(sc.r, sc.g, sc.b))
		_sky_mat.set_shader_parameter("stars", 1.0 - day_k)
	if _sun:
		_sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.38), warm)
		_sun.light_energy = SUN_MAX_ENERGY * day_k
		_sun.visible = day_k > 0.01
		if sd.y > -0.3:
			_sun.global_transform = Transform3D(Basis.looking_at(-sd, Vector3.UP), _sun.global_position)
	if _moon:
		_moon.light_energy = moon_energy * moon_k
		_moon.visible = moon_k > 0.01
		if md.y > -0.3:
			_moon.global_transform = Transform3D(Basis.looking_at(-md, Vector3.UP), Vector3(0, 12, 0))
	if _fill:
		_fill.light_energy = lerpf(0.05, 0.35, day_k)
		_fill.light_color = Color(1.0, 0.85, 0.65).lerp(Color(0.35, 0.45, 0.7), 1.0 - day_k)
