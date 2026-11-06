extends Node
## Цикл дня и ночи: 5 минут дня, затем ночь, плавный переход света.

const DAY_LENGTH := 300.0
const NIGHT_LENGTH := 300.0
const TRANSITION := 14.0

var time_of_day: float = 0.0
var _sun: DirectionalLight3D = null
var _fill: OmniLight3D = null
var _env: Environment = null

const DAY_BG := Color(0.55, 0.62, 0.7)
const NIGHT_BG := Color(0.07, 0.08, 0.16)
const DAY_AMBIENT := Color(0.7, 0.68, 0.62)
const NIGHT_AMBIENT := Color(0.18, 0.22, 0.38)
const DAY_FOG := Color(0.7, 0.65, 0.55)
const NIGHT_FOG := Color(0.08, 0.1, 0.18)
const DAY_SUN := Color(1.0, 0.95, 0.85)
const NIGHT_SUN := Color(0.35, 0.42, 0.7)


func setup(sun: DirectionalLight3D, env: Environment, fill: OmniLight3D = null) -> void:
	_sun = sun
	_env = env
	_fill = fill
	add_to_group("day_cycle")
	if GameState:
		time_of_day = float(GameState.day_time)
	apply_lighting()


func cycle_length() -> float:
	return DAY_LENGTH + NIGHT_LENGTH


func is_night() -> bool:
	return posmod_f(time_of_day, cycle_length()) >= DAY_LENGTH


func night_blend() -> float:
	var t := posmod_f(time_of_day, cycle_length())
	if t < DAY_LENGTH - TRANSITION:
		return 0.0
	if t < DAY_LENGTH:
		return smoothstep(0.0, 1.0, (t - (DAY_LENGTH - TRANSITION)) / TRANSITION)
	if t < cycle_length() - TRANSITION:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (t - (cycle_length() - TRANSITION)) / TRANSITION)


func posmod_f(value: float, length: float) -> float:
	if length <= 0.0:
		return 0.0
	var m := fmod(value, length)
	if m < 0.0:
		m += length
	return m


func _process(delta: float) -> void:
	time_of_day += delta
	if GameState:
		GameState.day_time = time_of_day
		if GameState.is_dream():
			return
	apply_lighting()


func apply_lighting() -> void:
	var k := night_blend()
	if _env:
		_env.background_color = DAY_BG.lerp(NIGHT_BG, k)
		_env.ambient_light_color = DAY_AMBIENT.lerp(NIGHT_AMBIENT, k)
		_env.ambient_light_energy = lerpf(0.55, 0.28, k)
		_env.fog_light_color = DAY_FOG.lerp(NIGHT_FOG, k)
		_env.fog_density = lerpf(0.002, 0.012, k)
		_env.glow_intensity = lerpf(0.25, 0.4, k)
	if _sun:
		_sun.light_color = DAY_SUN.lerp(NIGHT_SUN, k)
		_sun.light_energy = lerpf(1.1, 0.22, k)
		_sun.rotation_degrees = Vector3(-48.0 + k * 70.0, -35.0, 0.0)
	if _fill:
		_fill.light_energy = lerpf(0.4, 0.12, k)
		_fill.light_color = Color(1.0, 0.85, 0.65).lerp(Color(0.35, 0.45, 0.7), k)
