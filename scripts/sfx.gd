extends RefCounted
## v0.7: простые позиционные SFX (рыки боссов, гул земли). Звуки CC0 — см. assets/LICENSE.txt.

const MOTHER_ROAR := "res://assets/audio/mother_roar.ogg"
const MOTHER_GROWL := "res://assets/audio/mother_growl.ogg"
const ANACONDA_ROAR := "res://assets/audio/anaconda_roar.ogg"
const ANACONDA_RUMBLE := "res://assets/audio/anaconda_rumble.ogg"

## Журнал для смоук-теста: [путь, время].
static var played: Array = []


static func play3d(host: Node3D, path: String, volume_db: float = 0.0, max_distance: float = 70.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	played.append(path)
	if played.size() > 64:
		played.remove_at(0)
	if host == null or not host.is_inside_tree():
		return null
	var stream: AudioStream = _stream(path)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 12.0
	p.pitch_scale = pitch
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	host.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


static func count(path: String) -> int:
	var n := 0
	for p in played:
		if p == path:
			n += 1
	return n

static func play(kind: String, host: Node) -> void:
	var path := "res://assets/audio/sfx_" + kind + ".ogg"
	played.append(path)
	if played.size() > 64:
		played.remove_at(0)
	if host == null or not host.is_inside_tree() or not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _stream(path)
	p.volume_db = -12.0
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

static func _stream(path: String) -> AudioStream:
	# Short effects use predecoded PCM: no OggPacketSequencePlayback survives scene teardown.
	# Keep original CC0 source files and journal IDs for save/tests/attribution.
	var pcm:=path.get_basename()+".wav"
	return load(pcm if ResourceLoader.exists(pcm) else path) as AudioStream if ResourceLoader.exists(path) else null
