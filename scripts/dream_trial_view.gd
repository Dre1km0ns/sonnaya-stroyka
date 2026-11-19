extends Node3D
## v0.19: показ испытания — фантомы (по шкале времени симуляции) и прогрызенные блоки дрейфа.
## Сон не меняется: всё это только картинка поверх. Скорость: 30 тиков симуляции в секунду.

const TPS := 30.0
var _ph: MultiMeshInstance3D
var _br: MultiMeshInstance3D
var _core: MeshInstance3D
var _res: Dictionary = {}
var _t := 0.0
var playing := false
var shown_phantoms := 0
var shown_broken := 0
var _sfx_cd := 0.0
var _ended := false
var sounds: Array = [] # v0.20: журнал звуков показа (для смоука)
const Sfx := preload("res://scripts/sfx.gd")


func _ready() -> void:
	name = "DreamTrialView"
	add_to_group("dream_trial_view")
	_ph = _mm(CapsuleMesh.new(), Color(0.12, 0.05, 0.2, 0.75), Color(0.5, 0.2, 0.9))
	(_ph.multimesh.mesh as CapsuleMesh).radius = 0.3; (_ph.multimesh.mesh as CapsuleMesh).height = 1.7
	_br = _mm(BoxMesh.new(), Color(1.0, 0.15, 0.1, 0.45), Color(1.0, 0.2, 0.1))
	(_br.multimesh.mesh as BoxMesh).size = Vector3.ONE * 1.06
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
	_core.mesh = sm
	var cm := StandardMaterial3D.new(); cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; cm.albedo_color = Color(1.0, 0.9, 0.4)
	_core.material_override = cm
	_core.visible = false
	add_child(_core)
	GameState.trial_finished.connect(play)
	GameState.world_changed.connect(func(_d: bool) -> void: stop())


func _mm(mesh: Mesh, col: Color, emi: Color) -> MultiMeshInstance3D:
	var m := MultiMeshInstance3D.new()
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh
	m.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true; mat.emission = emi; mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func play(r: Dictionary) -> void:
	_res = r; _t = 0.0; playing = true; _ended = false; sounds = []; shown_phantoms = 0; shown_broken = 0
	_sound("trial_start", -10.0)
	_core.visible = true
	_core.position = Vector3(r.core) + Vector3(0.5, 0.6, 0.5)
	show_tick(0)


func stop() -> void:
	playing = false; _res = {}
	_ph.multimesh.instance_count = 0; _br.multimesh.instance_count = 0; _core.visible = false
	shown_phantoms = 0; shown_broken = 0


func show_tick(tick: int) -> void:
	if _res.is_empty(): return
	var tl: Array = _res.timeline
	if tl.is_empty(): return
	var fr: Array = tl[clampi(tick, 0, tl.size() - 1)]
	var y: float = float(_res.y0)
	_ph.multimesh.instance_count = fr.size()
	for i in range(fr.size()):
		var p: Vector2i = fr[i]
		_ph.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x + 0.5, y + 0.85, p.y + 0.5)))
	var cells: Array = []
	for i in range(_res.broken.size()):
		if int(_res.broken_t[i]) <= tick: cells.append(_res.broken[i])
	_br.multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		_br.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i]) + Vector3(0.5, 0.5, 0.5)))
	if playing and _sfx_cd <= 0.0:
		if fr.size() < shown_phantoms: _sound("trial_burn", -16.0); _sfx_cd = 0.12
		elif cells.size() > shown_broken: _sound("trial_breach", -12.0); _sfx_cd = 0.12
	shown_phantoms = fr.size(); shown_broken = cells.size()


func _process(delta: float) -> void:
	if not playing: return
	_t += delta * TPS
	_sfx_cd -= delta
	var tick := int(_t)
	show_tick(tick)
	if not _ended and tick >= _res.timeline.size():
		_ended = true
		_sound("trial_held" if bool(_res.get("held", false)) else "trial_fail", -9.0)
	if tick >= _res.timeline.size() + int(TPS * 3.0):
		stop()   # три секунды после конца — убираем


func _sound(kind: String, db: float) -> void:
	sounds.append(kind)
	Sfx.play(kind, self, db)
