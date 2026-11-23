extends Node3D
## v0.22: руки от первого лица — CC0-персонаж Kenney «Blocky Characters» (www.kenney.nl).
## Видна только правая рука модели; клипы модели: удар/добыча — attack-melee-right, поставить/использовать —
## interact-right, держать — holding-right. Ходьба, прыжок и сон — процедурно на той же руке
## (у модели нет клипов для вида от первого лица с поднятой рукой). Вида от третьего лица нет.

const MODEL := "res://assets/models/kenney_blocky/character-a.glb"
const SCALE := 0.34
## Плечо — за правым нижним углом кадра, рука смотрит вперёд-вверх-влево, кисть у рукояти инструмента.
const SHOULDER := Vector3(0.425, -0.415, -0.195)
const AIM := Vector3(18, 34, 0)
const OFFSET := Vector3(0.0, 0.0, 0.0)
const CLIPS := {
	"attack": ["attack-melee-right", 1.6, 0.3],   # клип, скорость, с какой доли начинать (рука уже в кадре)
	"break":  ["attack-melee-right", 1.9, 0.3],
	"place":  ["interact-right", 2.2, 0.25],
	"use":    ["interact-right", 1.6, 0.25],
	"drink":  ["interact-right", 0.9, 0.15],  # v0.23: зелье в кисти подносится ко рту
}
const BASE_CLIP := "holding-right"

var model: Node3D
var pivot: Node3D
var ap: AnimationPlayer
var last_action := ""
var actions_played: Dictionary = {}
var player: Node3D
var _walk_t := 0.0
var _jump := 0.0       # 0…1 — рука подлетает при прыжке
var _sleep := 0.0      # 0…1 — рука опускается из кадра, когда засыпаешь
var _sleep_target := 0.0
var _was_floor := true
var extra := Vector3.ZERO   # v0.23: отвод от стен (задаёт ViewModelRig)
var socket: Node3D          # v0.23: точка хвата в кисти правой руки — предмет в руке висит на ней
## v0.23: кисть — низ меша arm-right (AABB y −1…0.1, x −0.4…0) в его координатах.
const HAND_SOCKET := Vector3(-0.2, -0.88, 0.0)


func _ready() -> void:
	name = "FirstPersonArms"
	if not ResourceLoader.exists(MODEL):
		return
	pivot = Node3D.new(); pivot.name = "ShoulderPivot"; add_child(pivot)
	pivot.position = SHOULDER
	pivot.rotation_degrees = AIM
	model = (load(MODEL) as PackedScene).instantiate()
	pivot.add_child(model)
	model.rotation_degrees = Vector3(0, 180, 0)
	model.scale = Vector3.ONE * SCALE
	model.position = -Vector3(0.4, 1.8, 0.1) * SCALE   # плечо модели (торс 0.7 + рука 1.1) — в ноль пивота
	for part in ["leg-left", "leg-right", "head", "arm-left"]:
		var n := model.find_child(part, true, false) as MeshInstance3D
		if n: n.visible = false
	var torso := model.find_child("torso", true, false) as MeshInstance3D
	if torso: torso.mesh = null   # торс прячем, а рука-ребёнок остаётся видимой
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if GameState and not GameState.world_changed.is_connected(_on_world_changed):
		GameState.world_changed.connect(_on_world_changed)
	var arm_r := model.find_child("arm-right", true, false) as Node3D
	if arm_r:
		socket = Node3D.new(); socket.name = "HandSocket"; arm_r.add_child(socket)
		socket.position = HAND_SOCKET
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		ap.animation_finished.connect(func(_n: StringName) -> void: _play_base())
		_play_base()


func _on_world_changed(_is_dream: bool) -> void:
	## Засыпание/пробуждение: рука уходит вниз из кадра и возвращается.
	play_action("sleep")
	_sleep = 1.0
	if is_inside_tree():
		get_tree().create_timer(0.35).timeout.connect(func() -> void: if is_instance_valid(self): play_action("wake"))


func _play_base() -> void:
	if ap and ap.has_animation(BASE_CLIP):
		ap.play(BASE_CLIP, 0.12)
		ap.speed_scale = 1.0


func play_action(kind: String) -> bool:
	## kind: attack, break, place, use, jump, sleep, wake
	last_action = kind
	actions_played[kind] = int(actions_played.get(kind, 0)) + 1
	match kind:
		"jump":
			_jump = 1.0
			return true
		"sleep":
			_sleep_target = 1.0
			return true
		"wake":
			_sleep_target = 0.0
			return true
	if ap == null or not CLIPS.has(kind):
		return false
	var c: Array = CLIPS[kind]
	if not ap.has_animation(str(c[0])):
		return false
	ap.stop()
	ap.play(str(c[0]), 0.04)
	ap.seek(ap.get_animation(str(c[0])).length * float(c[2]), true)
	ap.speed_scale = float(c[1])
	return true


func current_clip() -> String:
	return str(ap.current_animation) if ap else ""


func _process(delta: float) -> void:
	if model == null:
		return
	var sway := Vector3.ZERO
	var rot := Vector3.ZERO
	if player and "velocity" in player:
		var v: Vector3 = player.get("velocity")
		var sp := Vector2(v.x, v.z).length()
		var flying := bool(player.get("flying")) if "flying" in player else false
		if sp > 0.5 and not flying:
			_walk_t += delta * sp * 1.5
			sway = Vector3(cos(_walk_t) * 0.018, absf(sin(_walk_t)) * 0.022, 0.0)
			rot = Vector3(sin(_walk_t) * 3.0, 0.0, cos(_walk_t) * 2.0)
		if player is CharacterBody3D and not flying:
			var on_floor := (player as CharacterBody3D).is_on_floor()
			if not on_floor and _was_floor and v.y > 1.0:
				play_action("jump")
			_was_floor = on_floor
	_jump = maxf(0.0, _jump - delta * 2.6)
	_sleep = move_toward(_sleep, _sleep_target, delta * 1.6)
	var j := sin(_jump * PI) * 0.06
	pivot.position = SHOULDER + sway + extra + Vector3(0, j - _sleep * 0.30, _sleep * 0.10)
	pivot.rotation_degrees = AIM + rot + Vector3(-_sleep * 40.0 + j * 60.0, 0, 0)
