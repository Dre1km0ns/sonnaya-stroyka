extends Node
## Фоновая музыка: Явь / Сон / босс, с кроссфейдом.

const VOL_DB := -8.0
const SILENT_DB := -48.0
const FADE_SEC := 0.85
const PATH_WAKE := "res://assets/audio/music.mp3"
const PATH_DREAM := "res://assets/audio/dream_ost.mp3"
const PATH_BOSS := "res://assets/audio/boss_ost.mp3"
const PATH_ANACONDA := "res://assets/audio/anaconda_ost.mp3"
## v0.7: если живы оба босса — играет тема Анаконды (ночной бой под землёй, она редкая и опаснее);
## Мать блоков возвращает свою тему, как только Анаконда уйдёт или умрёт.
const POLL_SEC := 0.5
var _poll_t: float = 0.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _cur: AudioStreamPlayer
var _fade_t: float = 1.0
var _fading: bool = false
var _from: AudioStreamPlayer
var _to: AudioStreamPlayer
var _want: String = "wake"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_a = _make_player("MusicA")
	_b = _make_player("MusicB")
	_cur = _a
	if GameState.has_signal("world_changed") and not GameState.world_changed.is_connected(_on_world):
		GameState.world_changed.connect(_on_world)
	if GameState.has_signal("boss_changed") and not GameState.boss_changed.is_connected(_on_boss):
		GameState.boss_changed.connect(_on_boss)
	_want = _desired()
	_play_immediate(_want)


func _make_player(nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.bus = "Music"
	p.volume_db = VOL_DB
	add_child(p)
	return p


func _load_stream(path: String) -> AudioStream:
	var stream: Resource = load(path)
	if stream == null:
		push_warning("music missing: %s" % path)
		return null
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream as AudioStream


func anaconda_active() -> bool:
	if not is_inside_tree():
		return false
	for a in get_tree().get_nodes_in_group("anaconda"):
		if is_instance_valid(a) and not a.is_queued_for_deletion():
			if a.has_method("is_fight_active") and not a.is_fight_active():
				continue
			return true
	return false


func current_key() -> String:
	return _want


func _desired() -> String:
	if GameState != null and not GameState.is_dream() and anaconda_active():
		return "anaconda"
	if GameState != null and bool(GameState.get("boss_alive")):
		return "boss"
	if GameState != null and GameState.is_dream():
		return "dream"
	return "wake"


func _path_for(key: String) -> String:
	if key == "anaconda":
		return PATH_ANACONDA
	if key == "boss":
		return PATH_BOSS
	if key == "dream":
		return PATH_DREAM
	return PATH_WAKE


func _on_world(_is_dream: bool) -> void:
	crossfade_to(_desired())


func _on_boss(_alive: bool) -> void:
	crossfade_to(_desired())


func _play_immediate(key: String) -> void:
	var stream: AudioStream = _load_stream(_path_for(key))
	if stream == null:
		return
	_cur.stream = stream
	_cur.volume_db = VOL_DB
	_cur.play()
	_want = key


func crossfade_to(key: String) -> void:
	if key == _want and _cur.playing:
		return
	var stream: AudioStream = _load_stream(_path_for(key))
	if stream == null:
		return
	var nxt: AudioStreamPlayer = _b if _cur == _a else _a
	nxt.stream = stream
	nxt.volume_db = SILENT_DB
	nxt.play()
	_from = _cur
	_to = nxt
	_cur = nxt
	_want = key
	_fade_t = 0.0
	_fading = true


func _process(delta: float) -> void:
	# Опрос: Анаконда может появиться, когда Мать уже жива (boss_changed тогда не срабатывает).
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_SEC
		var want := _desired()
		if want != _want:
			crossfade_to(want)
	if not _fading:
		return
	_fade_t = minf(1.0, _fade_t + delta / FADE_SEC)
	var k: float = _fade_t
	if _from:
		_from.volume_db = lerpf(VOL_DB, SILENT_DB, k)
	if _to:
		_to.volume_db = lerpf(SILENT_DB, VOL_DB, k)
	if k >= 1.0:
		_fading = false
		if _from and _from != _cur:
			_from.stop()
			_from.volume_db = SILENT_DB
