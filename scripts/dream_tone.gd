extends Node
## v0.20: «тон Сна» — две бесшовные петли (спокойная и тревожная), микшируются по состоянию Сна:
## меньше осознанности и больше трещин — тревожнее. Звучит только во Сне, поверх музыки, тихо.

const CALM := "res://assets/audio/dream_tone_calm.wav"
const UNEASY := "res://assets/audio/dream_tone_uneasy.wav"
const BASE_DB := -20.0
const FADE := 1.5

var calm: AudioStreamPlayer
var uneasy: AudioStreamPlayer
var level := 0.0       # 0..1 общая громкость (плавно)
var unease := 0.0      # 0..1 доля тревожной петли (плавно)


func _ready() -> void:
	add_to_group("dream_tone")
	calm = _player(CALM, "Calm")
	uneasy = _player(UNEASY, "Uneasy")


func _player(path: String, nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.stream = load(path) as AudioStream
	p.bus = &"Music" if AudioServer.get_bus_index("Music") >= 0 else &"Master"
	p.volume_db = -80.0
	add_child(p)
	return p


static func target_unease(clarity: float, clarity_max: float, cracks: int) -> float:
	var low := 1.0 - clampf(clarity / maxf(clarity_max, 1.0), 0.0, 1.0)
	return clampf(low * 0.7 + minf(cracks, 8) / 8.0 * 0.6, 0.0, 1.0)


func _process(delta: float) -> void:
	var dream := GameState.is_dream()
	var want := 1.0 if dream else 0.0
	level = move_toward(level, want, delta / FADE)
	unease = move_toward(unease, target_unease(GameState.clarity, GameState.dream_clarity_max(), GameState.dream_cracks.size()), delta / 4.0)
	if level <= 0.001:
		if calm.playing: calm.stop(); uneasy.stop()
		return
	if not calm.playing: calm.play(); uneasy.play()
	calm.volume_db = BASE_DB + linear_to_db(maxf(level * (1.0 - unease), 0.0001))
	uneasy.volume_db = BASE_DB + linear_to_db(maxf(level * unease, 0.0001))
