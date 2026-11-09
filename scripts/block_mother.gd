extends CharacterBody3D
## v0.6 — «Мать блоков»: эволюция архетипа Короля Слизня с блочной идентичностью.
## Дизайн-док: docs/boss_mother_of_blocks.md. Состояния:
##   SPAWN → IDLE ⇄ WINDUP → AIR → (LAND) → STAGGER → IDLE …
##   IDLE → TRANSITION (66% / 33%) → STAGGER(окно 2 с)
##   IDLE → SCATTER → MARKER → (REASSEMBLE) → STAGGER   (телепорт-пересборка)
##   IDLE → RAIN_WINDUP → RAIN → STAGGER                 (фаза 3: кирпичный дождь)
##   * → DEAD / LEAVING
const _Vis := preload("res://scripts/enemy_visuals.gd")
const _Nav := preload("res://scripts/enemy_navigation.gd")
const BlockTex := preload("res://scripts/block_tex.gd")
const Sfx := preload("res://scripts/sfx.gd")
## v0.7 пассивка: +5 HP за каждый блок, который она сама сломала в бою (прыжком). Сама блоки не ищет.
const HEAL_PER_BLOCK := 5
var healed_from_blocks: int = 0

enum S { SPAWN, IDLE, WINDUP, AIR, STAGGER, TRANSITION, SCATTER, MARKER, RAIN_WINDUP, RAIN, DEAD, LEAVING }
const STATE_NAMES := ["SPAWN", "IDLE", "WINDUP", "AIR", "STAGGER", "TRANSITION", "SCATTER", "MARKER", "RAIN_WINDUP", "RAIN", "DEAD", "LEAVING"]

# --- числовая база (см. дизайн-док, раздел 3) ---
const MAX_HP := 500
const P2_AT := 330           # 66%
const P3_AT := 165           # 33%
const MODEL_PATH := "res://assets/models/greenblob.glb"
const MODEL_HEIGHT := 3.0
const HIT_RADIUS := 1.3
const BODY_HEIGHT := 2.6
const SPAWN_TIME := 1.6
const WINDUP := [0.6, 0.5, 0.45]        # по фазам (телеграф прыжка ≥0.45 с + тень весь полёт)
const STAGGER := [1.2, 1.0, 0.8]        # окно уязвимости после приземления
const JUMP_Y := [7.0, 7.4, 7.8]         # вертикальная скорость: полёт ≈1.43 / 1.51 / 1.59 с
const JUMP_H_MAX := 8.5                 # макс. горизонтальная скорость прыжка, м/с
const SLAM_RADIUS := 3.0
const SLAM_DAMAGE := 30
const CONTACT_DAMAGE := 5
const CONTACT_CD := 1.0
const WAVE_DAMAGE := 12
const WAVE_SPEED := 7.0
const WAVE_START := 3.0
const WAVE_END := 10.0
const WAVE_HEIGHT := 0.55
const TP_RANGE := 14.0                  # дальше — пересборка рядом с игроком
const TP_HEIGHT := 2.5
const TP_CD := [12.0, 9.0, 9.0]
const SCATTER_TIME := 0.8
const MARKER_TIME := 1.2
const REASSEMBLE_RADIUS := 2.6
const REASSEMBLE_DAMAGE := 25
const REASSEMBLE_STAGGER := 1.5
const TRANSITION_TIME := 1.6
const TRANSITION_WINDOW := 2.0
const ROAR_PUSH_RADIUS := 4.0
const RAIN_CD := 9.0
const RAIN_WINDUP := 0.6
const RAIN_BRICKS := 8
const RAIN_SPREAD := 1.6                # кирпичи падают в течение 1.6 с
const BRICK_SHADOW := 1.0               # тень-телеграф каждого кирпича
const BRICK_DAMAGE := 12
const BRICK_RADIUS := 0.9
const RAIN_STAGGER := 1.2
const VULN_MULT := 1.5
const MINION_SPAWN := [2, 2, 3]
const MINION_CAP := [4, 5, 6]
const MINION_HARD_CAP := 6
const MINION_CHANCE := 0.3
const MINION_PITY := 3                  # 3 приземления без детей → гарантированно
const MINION_LOCKOUT := 2               # после спавна 2 приземления без спавна
const LEASH_DIST := 40.0
const LEASH_TIME := 6.0
const REWARD_R3 := 3
const REWARD_R2 := 2

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var hit_radius: float = HIT_RADIUS
var phase: int = 1
var state: int = S.SPAWN
var frozen: bool = false
var attack_log: Dictionary = {"slam": 0, "slam_hit": 0, "shockwave": 0, "wave_hit": 0, "teleport": 0, "reassemble_hit": 0,
	"brick_rain": 0, "brick": 0, "brick_hit": 0, "minion_spawn": 0, "minions": 0, "transition": 0, "contact": 0}
var state_log: Array = []
var damage_dealt: int = 0

var _t: float = 0.0
var _stagger_len: float = 1.0
var _contact_cd: float = 0.0
var _tp_cd: float = 6.0
var _rain_cd: float = 3.0
var _landings_since_spawn: int = 0
var _lockout: int = 0
var _pending_transition: int = 0
var _leash_t: float = 0.0
var _air_t: float = 0.0
var _target: Vector3 = Vector3.ZERO
var _marker_pos: Vector3 = Vector3.ZERO
var _no_progress: int = 0
var _last_dist: float = 999.0
var _bricks: Array = [] # [{node, shadow, pos, t, hit}]
var _waves: Array = []  # [{node, r, center, hit}]
var _shadow: MeshInstance3D = null
var _marker: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()


static func try_spawn_from_mine(host: Node3D, cell: Vector3i) -> Node:
	## Совместимость: решение о спавне теперь в GameState.on_block_mined() (бросок на следующий блок).
	if host == null or host.get_tree() == null:
		return null
	if GameState != null and bool(GameState.get("boss_alive")):
		return null
	if not GameState.on_block_mined():
		return null
	return spawn_near(host, cell)


const ARENA_CLEAR_RADIUS := 11.0


static func spawn_near(host: Node3D, cell: Vector3i) -> Node:
	if host == null or host.get_tree() == null:
		return null
	if host.get_tree().get_nodes_in_group("block_mother").size() > 0:
		return null
	var pos := Vector3(float(cell.x) + 4.5, 0.15, float(cell.z) + 2.0)
	for cm in host.get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("walk_height_at") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			pos.y = float(cm.call("walk_height_at", int(pos.x), int(pos.z))) + 0.15
			break
	for cm2 in host.get_tree().get_nodes_in_group("chunk_manager"):
		if cm2.has_method("absorb_trees_near") and not bool(cm2.get("is_dream_layer")):
			var eaten := int(cm2.call("absorb_trees_near", pos, ARENA_CLEAR_RADIUS))
			if eaten > 0:
				GameState.chat("Мать блоков втягивает в себя деревья вокруг (%d) — арена расчищена." % eaten)
	var script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = script.new()
	boss.position = pos
	host.add_child(boss)
	return boss


func _ready() -> void:
	_rng.randomize()
	add_to_group("block_mother")
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 16
	collision_mask = 1 | 4
	_Vis.attach_model(self, MODEL_PATH, MODEL_HEIGHT)
	_Vis.attach_hp_bar(self, MODEL_HEIGHT + 0.4)
	var hpbar := get_node_or_null("HPBar") as Node3D
	if hpbar:
		hpbar.scale = Vector3(2.2, 2.2, 2.2)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = HIT_RADIUS
	shape.height = BODY_HEIGHT
	col.shape = shape
	col.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	add_child(col)
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(true)
	if GameState.has_signal("world_changed"):
		GameState.world_changed.connect(_on_world)
	_on_world(GameState.is_dream())
	_Vis.update_hp_bar(self, hp, max_hp)
	_enter(S.SPAWN)
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.set_meta("base_scale", model.scale)
		model.scale *= 0.2
		var tw := create_tween()
		tw.tween_property(model, "scale", model.scale * 5.0, SPAWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	GameState.chat("Мать блоков собирается из камня! Беги из-под прыжков, бей в окна «УЯЗВИМА».", Color(1.0, 0.45, 0.4))
	roar(true)


func _on_world(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream
	set_physics_process(not is_dream)


# ---------------------------------------------------------------- урон по боссу

func hit_center() -> Vector3:
	return global_position + Vector3(0, BODY_HEIGHT * 0.5, 0)


func is_vulnerable() -> bool:
	return state == S.STAGGER and _t < _stagger_len


func is_invulnerable() -> bool:
	return state in [S.SPAWN, S.TRANSITION, S.SCATTER, S.MARKER, S.DEAD, S.LEAVING]


func take_damage(amount: int) -> void:
	if state == S.DEAD or state == S.LEAVING or is_invulnerable():
		return
	var dmg := amount
	if is_vulnerable():
		dmg = int(round(float(amount) * VULN_MULT))
	var floor_hp := 0
	if phase == 1:
		floor_hp = P2_AT
	elif phase == 2:
		floor_hp = P3_AT
	hp = maxi(floor_hp, hp - dmg)
	damage_dealt += dmg
	_Vis.update_hp_bar(self, hp, max_hp)
	_flash()
	if phase == 1 and hp <= P2_AT:
		_pending_transition = 2
	elif phase == 2 and hp <= P3_AT:
		_pending_transition = 3
	if hp <= 0:
		_die()
		return
	# Переход фаз прерывает «окно» сразу (на земле), в воздухе — после приземления.
	if _pending_transition > 0 and state in [S.IDLE, S.STAGGER, S.WINDUP, S.RAIN_WINDUP]:
		_start_transition()


func heal_from_blocks(blocks: int) -> int:
	## Пассивка: лечится, только пока бой идёт; не выше max_hp и не выше порога текущей фазы
	## (чтобы лечением не «откатывать» уже пройденный переход).
	if blocks <= 0 or state == S.DEAD or state == S.LEAVING:
		return 0
	var cap := max_hp
	if phase == 2:
		cap = P2_AT
	elif phase == 3:
		cap = P3_AT
	var before := hp
	hp = mini(cap, hp + HEAL_PER_BLOCK * blocks)
	var got := hp - before
	if got > 0:
		healed_from_blocks += got
		_Vis.update_hp_bar(self, hp, max_hp)
	return got


func roar(loud: bool = true) -> void:
	Sfx.play3d(self, Sfx.MOTHER_ROAR if loud else Sfx.MOTHER_GROWL, 2.0 if loud else -2.0, 80.0, _rng.randf_range(0.92, 1.05))


func _flash() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	model.set_meta("base_scale", base)
	if state in [S.WINDUP, S.AIR, S.SPAWN]:
		return
	model.scale = base * Vector3(1.08, 0.92, 1.08)
	var tw := create_tween()
	tw.tween_property(model, "scale", base, 0.12)


# ---------------------------------------------------------------- машина состояний

func _enter(s: int) -> void:
	state = s
	_t = 0.0
	state_log.append([STATE_NAMES[s], phase, hp])
	if state_log.size() > 400:
		state_log.remove_at(0)


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D


func _physics_process(delta: float) -> void:
	if frozen or state == S.DEAD or state == S.LEAVING:
		return
	_t += delta
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_tp_cd = maxf(0.0, _tp_cd - delta)
	_rain_cd = maxf(0.0, _rain_cd - delta)
	var player := _player()
	_tick_bricks(delta, player)
	_tick_waves(delta, player)
	if player == null:
		return
	var to_p := player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	# Поводок: игрок убежал далеко — Мать уходит без награды.
	if flat.length() > LEASH_DIST:
		_leash_t += delta
		if _leash_t > LEASH_TIME:
			leave("Мать блоков потеряла тебя из виду и ушла под землю.")
			return
	else:
		_leash_t = 0.0
	match state:
		S.SPAWN:
			_ground_move(delta)
			if _t >= SPAWN_TIME:
				_enter(S.IDLE)
		S.IDLE:
			_ground_move(delta)
			_face(flat, delta)
			_decide(player, flat)
		S.WINDUP:
			_ground_move(delta)
			_face(flat, delta)
			if _t >= float(WINDUP[phase - 1]):
				_jump(player)
		S.AIR:
			_air_t += delta
			velocity.y -= _gravity * delta
			move_and_slide()
			_update_shadow()
			if is_on_floor() and _air_t > 0.15:
				_land(player)
			elif _air_t > 4.0:
				_land(player)
		S.STAGGER:
			_ground_move(delta)
			if _t >= _stagger_len:
				_enter(S.IDLE)
		S.TRANSITION:
			_ground_move(delta)
			if _t >= TRANSITION_TIME:
				_stagger_len = TRANSITION_WINDOW
				_set_crack_glow(true)
				_enter(S.STAGGER)
				_Vis.play_state(self, "idle", true)
		S.SCATTER:
			if _t >= SCATTER_TIME:
				_show_marker(player)
				_enter(S.MARKER)
		S.MARKER:
			if _t >= MARKER_TIME:
				_reassemble(player)
		S.RAIN_WINDUP:
			_ground_move(delta)
			if _t >= RAIN_WINDUP:
				_start_rain(player)
				_enter(S.RAIN)
		S.RAIN:
			_ground_move(delta)
			if _t >= RAIN_SPREAD + BRICK_SHADOW:
				_stagger_len = RAIN_STAGGER
				_set_crack_glow(true)
				_enter(S.STAGGER)
	# Касание: только когда она стоит (не в полёте и не рассыпана).
	if state in [S.IDLE, S.WINDUP, S.STAGGER, S.RAIN, S.RAIN_WINDUP] and _contact_cd <= 0.0:
		if flat.length() <= HIT_RADIUS + 0.55 and absf(to_p.y) < BODY_HEIGHT:
			_hurt(player, CONTACT_DAMAGE, "касание", 7.0)
			attack_log["contact"] += 1
			_contact_cd = CONTACT_CD
	if state != S.STAGGER:
		_set_crack_glow(false)


func _ground_move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	move_and_slide()


func _face(flat: Vector3, delta: float) -> void:
	if flat.length() > 0.1:
		_Nav.face_dir(self, flat, delta, 6.0)


func _decide(player: CharacterBody3D, flat: Vector3) -> void:
	## Приоритеты мувмент-ИИ (док, раздел 6):
	## 1) отложенный переход фазы; 2) пересборка рядом с игроком, если далеко/высоко/застряла;
	## 3) фаза 3: кирпичный дождь по КД; 4) иначе — прыжок-слэм.
	if _pending_transition > 0:
		_start_transition()
		return
	var dy := player.global_position.y - global_position.y
	var far := flat.length() > TP_RANGE or absf(dy) > TP_HEIGHT or _no_progress >= 3
	if far and _tp_cd <= 0.0:
		_start_scatter()
		return
	if phase >= 3 and _rain_cd <= 0.0 and flat.length() < TP_RANGE:
		_rain_cd = RAIN_CD
		_enter(S.RAIN_WINDUP)
		roar(true)
		_Vis.play_state(self, "attack", true)
		_squash(Vector3(1.0, 1.25, 1.0), RAIN_WINDUP)
		return
	_enter(S.WINDUP)
	_Vis.play_state(self, "idle", true)
	_squash(Vector3(1.22, 0.7, 1.22), float(WINDUP[phase - 1]))


func _squash(k: Vector3, time: float) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	model.set_meta("base_scale", base)
	var tw := create_tween()
	tw.tween_property(model, "scale", base * k, time * 0.85).set_trans(Tween.TRANS_SINE)


func _unsquash(time: float = 0.15) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	var tw := create_tween()
	tw.tween_property(model, "scale", base, time)


# ---------------------------------------------------------------- прыжок-слэм

func predicted_landing(player: CharacterBody3D) -> Vector3:
	var target := player.global_position
	if phase >= 3:
		var lead := Vector3(player.velocity.x, 0, player.velocity.z) * 0.3
		target += lead.limit_length(2.5)
	return target


func _jump(player: CharacterBody3D) -> void:
	_target = predicted_landing(player)
	var vy: float = JUMP_Y[phase - 1]
	var t_air := 2.0 * vy / _gravity
	var d := Vector3(_target.x - global_position.x, 0, _target.z - global_position.z)
	var vh := d / t_air
	vh = vh.limit_length(JUMP_H_MAX)
	velocity = Vector3(vh.x, vy, vh.z)
	_air_t = 0.0
	_last_dist = d.length()
	_enter(S.AIR)
	_unsquash(0.1)
	_squash(Vector3(0.85, 1.25, 0.85), 0.3)
	_Vis.play_state(self, "jump", true)
	_make_shadow()


func _make_shadow() -> void:
	_free_node(_shadow)
	_shadow = _disc(SLAM_RADIUS, Color(0.95, 0.12, 0.1, 0.38))
	_update_shadow()


func _update_shadow() -> void:
	if _shadow == null or not is_instance_valid(_shadow):
		return
	# Тень показывает точку приземления по баллистике (с учётом текущей скорости).
	var vy := velocity.y
	var y0 := global_position.y
	var ground := _ground_y_at(_target)
	var a := 0.5 * _gravity
	var b := -vy
	var c := ground - y0
	var disc := b * b - 4.0 * a * c
	var t_rem := 0.0
	if disc > 0.0:
		t_rem = maxf(0.0, (-b + sqrt(disc)) / (2.0 * a))
	var p := global_position + Vector3(velocity.x, 0, velocity.z) * t_rem
	_shadow.global_position = Vector3(p.x, ground + 0.04, p.z)
	var k := clampf(1.0 - t_rem / 1.5, 0.25, 1.0)
	var inner := _shadow.get_node_or_null("Inner") as Node3D
	if inner:
		inner.scale = Vector3(k, 1, k)


func _land(player: CharacterBody3D) -> void:
	velocity = Vector3.ZERO
	_free_node(_shadow)
	_shadow = null
	attack_log["slam"] += 1
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")):
			cm.call("absorb_trees_near", global_position, 4.5)   # прыжок сносит деревья
			heal_from_blocks(int(cm.get("last_absorbed_blocks")))
	_unsquash(0.06)
	_squash(Vector3(1.3, 0.72, 1.3), 0.08)
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_unsquash(0.25))
	_debris(global_position + Vector3(0, 0.3, 0), 8, 5.0)
	var to_p := player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	if flat.length() <= SLAM_RADIUS and to_p.y < 2.2 and to_p.y > -1.0:
		if _hurt(player, SLAM_DAMAGE, "слэм", 11.0) > 0:
			attack_log["slam_hit"] += 1
	if phase >= 2:
		_spawn_wave()
	# Прогресс сближения (для «застряла» → пересборка).
	if flat.length() > 6.0 and flat.length() >= _last_dist - 1.0:
		_no_progress += 1
	else:
		_no_progress = 0
	_maybe_spawn_minions()
	_stagger_len = float(STAGGER[phase - 1])
	_set_crack_glow(true)
	_enter(S.STAGGER)
	_Vis.play_state(self, "idle", true)
	if _pending_transition > 0:
		_start_transition()


# ---------------------------------------------------------------- ударная волна (фаза 2+)

func _spawn_wave() -> void:
	attack_log["shockwave"] += 1
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = WAVE_HEIGHT
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 40
	cm.rings = 1
	ring.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.75)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world().add_child(ring)
	var center := global_position
	ring.global_position = center + Vector3(0, WAVE_HEIGHT * 0.5, 0)
	ring.scale = Vector3(WAVE_START, 1, WAVE_START)
	_waves.append({"node": ring, "r": WAVE_START, "center": center, "hit": false})


func _tick_waves(delta: float, player: CharacterBody3D) -> void:
	var i := 0
	while i < _waves.size():
		var w: Dictionary = _waves[i]
		var r: float = float(w["r"]) + WAVE_SPEED * delta
		w["r"] = r
		var node: MeshInstance3D = w["node"]
		if is_instance_valid(node):
			node.scale = Vector3(r, 1, r)
			var mat := node.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = 0.75 * clampf((WAVE_END - r) / 3.0, 0.0, 1.0)
		if player and not bool(w["hit"]):
			var c: Vector3 = w["center"]
			var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
			var above := player.global_position.y - c.y
			# Волна бьёт только стоящих на земле: перепрыгни кольцо (прыжок 1.5 м > 0.55 м).
			if absf(d - r) < 0.45 and above < WAVE_HEIGHT and player.is_on_floor():
				w["hit"] = true
				if _hurt(player, WAVE_DAMAGE, "ударная волна", 6.0) > 0:
					attack_log["wave_hit"] += 1
		if r >= WAVE_END:
			_free_node(node)
			_waves.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- пересборка (телепорт)

func _start_scatter() -> void:
	_tp_cd = float(TP_CD[phase - 1])
	_no_progress = 0
	attack_log["teleport"] += 1
	_enter(S.SCATTER)
	_debris(global_position + Vector3(0, 1.2, 0), 16, 6.5)
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.visible = false
	var bar := get_node_or_null("HPBar") as Node3D
	if bar:
		bar.visible = false
	collision_layer = 0


func _show_marker(player: CharacterBody3D) -> void:
	_marker_pos = player.global_position
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")):
			cm.call("absorb_trees_near", _marker_pos, 5.0)
	_marker_pos.y = _ground_y_at(_marker_pos)
	_free_node(_marker)
	_marker = _disc(REASSEMBLE_RADIUS, Color(1.0, 0.55, 0.1, 0.42))
	_marker.global_position = _marker_pos + Vector3(0, 0.05, 0)
	var pillar := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.35
	pm.bottom_radius = 0.6
	pm.height = 7.0
	pillar.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.3)
	pillar.material_override = m
	pillar.position = Vector3(0, 3.5, 0)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(pillar)
	# Блоки слетаются к маркеру.
	for i in range(10):
		var a := float(i) / 10.0 * TAU
		var from := _marker_pos + Vector3(cos(a) * 6.0, 4.0 + _rng.randf() * 2.0, sin(a) * 6.0)
		var cube := _mini_block(from)
		var tw := cube.create_tween()
		tw.tween_property(cube, "global_position", _marker_pos + Vector3(0, 1.2, 0), MARKER_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(cube.queue_free)


func _reassemble(player: CharacterBody3D) -> void:
	_free_node(_marker)
	_marker = null
	global_position = _marker_pos + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	collision_layer = 16
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.visible = true
	var bar := get_node_or_null("HPBar") as Node3D
	if bar:
		bar.visible = true
	_debris(global_position + Vector3(0, 0.5, 0), 10, 4.0)
	var d := Vector2(player.global_position.x - _marker_pos.x, player.global_position.z - _marker_pos.z).length()
	if d <= REASSEMBLE_RADIUS and absf(player.global_position.y - _marker_pos.y) < 2.5:
		if _hurt(player, REASSEMBLE_DAMAGE, "пересборка", 10.0) > 0:
			attack_log["reassemble_hit"] += 1
	_stagger_len = REASSEMBLE_STAGGER
	_set_crack_glow(true)
	_enter(S.STAGGER)
	_Vis.play_state(self, "idle", true)


# ---------------------------------------------------------------- кирпичный дождь (фаза 3)

func _start_rain(player: CharacterBody3D) -> void:
	attack_log["brick_rain"] += 1
	var center := player.global_position
	for i in range(RAIN_BRICKS):
		var delay := float(i) / float(RAIN_BRICKS) * RAIN_SPREAD
		var p: Vector3
		if i % 4 == 0:
			p = center  # прицельные: в точку игрока на момент каста (уйди с места)
		else:
			var a := _rng.randf() * TAU
			var r := 1.5 + _rng.randf() * 5.5
			p = center + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _ground_y_at(p)
		get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if is_instance_valid(self) and state != S.DEAD:
				_spawn_brick(p))


func _spawn_brick(p: Vector3) -> void:
	attack_log["brick"] += 1
	var shadow := _disc(BRICK_RADIUS, Color(0.6, 0.05, 0.05, 0.5))
	shadow.global_position = p + Vector3(0, 0.04, 0)
	var brick := MeshInstance3D.new()
	brick.mesh = BlockTex.cube_mesh("ruin", Vector3(0.9, 0.9, 0.9))
	_world().add_child(brick)
	brick.global_position = p + Vector3(0, 14.0, 0)
	_bricks.append({"node": brick, "shadow": shadow, "pos": p, "t": 0.0, "done": false})


func _tick_bricks(delta: float, player: CharacterBody3D) -> void:
	var i := 0
	while i < _bricks.size():
		var b: Dictionary = _bricks[i]
		b["t"] = float(b["t"]) + delta
		var t: float = b["t"]
		var node: Node3D = b["node"]
		var p: Vector3 = b["pos"]
		if not bool(b["done"]):
			var k := clampf(t / BRICK_SHADOW, 0.0, 1.0)
			if is_instance_valid(node):
				node.global_position = p + Vector3(0, 0.45 + 14.0 * (1.0 - k * k), 0)
			var sh: Node3D = b["shadow"]
			if is_instance_valid(sh):
				var inner := sh.get_node_or_null("Inner") as Node3D
				if inner:
					inner.scale = Vector3(maxf(k, 0.2), 1, maxf(k, 0.2))
			if t >= BRICK_SHADOW:
				b["done"] = true
				_free_node(b["shadow"])
				if player:
					var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
					var dy := player.global_position.y - p.y
					if d <= BRICK_RADIUS + 0.35 and dy < 2.0 and dy > -0.5:
						if _hurt(player, BRICK_DAMAGE, "кирпич", 3.0) > 0:
							attack_log["brick_hit"] += 1
		elif t > BRICK_SHADOW + 1.6:
			_free_node(node)
			_bricks.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- выводок (блоклинги)

func alive_minions() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("blockling"):
		if is_instance_valid(m) and int(m.get("hp")) > 0:
			n += 1
	return n


func minion_roll(roll: float) -> bool:
	## RNG с защитой от серий: локаут 2 приземления после спавна; гарантия после 3 пустых.
	if _lockout > 0:
		_lockout -= 1
		_landings_since_spawn += 1
		return false
	_landings_since_spawn += 1
	if _landings_since_spawn >= MINION_PITY or roll < MINION_CHANCE:
		_landings_since_spawn = 0
		_lockout = MINION_LOCKOUT
		return true
	return false


func _maybe_spawn_minions() -> void:
	var cap: int = mini(MINION_HARD_CAP, int(MINION_CAP[phase - 1]))
	var room := cap - alive_minions()
	if room <= 0:
		return
	if not minion_roll(_rng.randf()):
		return
	var n := mini(room, int(MINION_SPAWN[phase - 1]))
	var script: GDScript = load("res://scripts/blockling.gd")
	for i in range(n):
		var a := _rng.randf() * TAU
		var m: CharacterBody3D = script.new()
		_world().add_child(m)
		m.global_position = global_position + Vector3(cos(a) * 2.2, 1.0, sin(a) * 2.2)
		m.velocity = Vector3(cos(a) * 3.0, 4.0, sin(a) * 3.0)
	attack_log["minion_spawn"] += 1
	attack_log["minions"] += n
	GameState.chat("Мать блоков рожает блоклингов (%d)." % n, Color(1.0, 0.75, 0.5))


# ---------------------------------------------------------------- переходы, смерть, уход

func _start_transition() -> void:
	var to := _pending_transition
	_pending_transition = 0
	if to <= phase:
		return
	phase = to
	attack_log["transition"] += 1
	_enter(S.TRANSITION)
	velocity = Vector3.ZERO
	_free_node(_shadow)
	_shadow = null
	_Vis.play_state(self, "attack", true)
	_squash(Vector3(1.35, 0.6, 1.35), TRANSITION_TIME * 0.6)
	get_tree().create_timer(TRANSITION_TIME * 0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and state == S.TRANSITION:
			_unsquash(0.3)
			roar(true)
			_roar_push())
	var what := "Ударная волна: перепрыгивай оранжевое кольцо!" if phase == 2 else "Кирпичный дождь: уходи с красных теней!"
	GameState.chat("Мать блоков в ярости — фаза %d. %s" % [phase, what], Color(1.0, 0.5, 0.35))


func _roar_push() -> void:
	## Рёв: без урона, отталкивает игрока (контрплей — отойти заранее/принять толчок).
	var player := _player()
	_debris(global_position + Vector3(0, 1.0, 0), 12, 6.0)
	if player == null:
		return
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() < ROAR_PUSH_RADIUS:
		var dir := d.normalized() if d.length() > 0.05 else Vector3(1, 0, 0)
		player.velocity += dir * 9.0 + Vector3(0, 3.5, 0)


func _hurt(player: CharacterBody3D, amount: int, source: String, knock: float) -> int:
	var dealt: int = GameState.damage_player(amount, "Мать блоков: " + source)
	if dealt > 0:
		var push := player.global_position - global_position
		push.y = 0.0
		if push.length() < 0.05:
			push = Vector3(1, 0, 0)
		player.velocity += push.normalized() * knock + Vector3(0, 2.0, 0)
	return dealt


func _die() -> void:
	_enter(S.DEAD)
	_cleanup_fx()
	roar(false)
	if GameState.has_method("on_mother_killed"):
		GameState.on_mother_killed()
	GameState.reward_kill(true, "Мать блоков")
	if not GameState.dev_mode:
		GameState.add_item_count("reagent3", REWARD_R3)
		GameState.add_item_count("reagent2", REWARD_R2)
	GameState.chat("Мать блоков рассыпалась. Награда: 250 осыпи, %d реагент3, %d реагент2. Сутки она не вернётся." % [REWARD_R3, REWARD_R2], Color(0.6, 1.0, 0.6))
	for m in get_tree().get_nodes_in_group("blockling"):
		if is_instance_valid(m) and m.has_method("crumble"):
			m.crumble()
	_Vis.play_state(self, "death", true)
	_debris(global_position + Vector3(0, 1.2, 0), 20, 7.0)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(false)
	var tree: SceneTree = get_tree()
	if tree:
		await tree.create_timer(1.7).timeout
	if is_instance_valid(self):
		queue_free()


func leave(msg: String = "") -> void:
	if state == S.DEAD or state == S.LEAVING:
		return
	_enter(S.LEAVING)
	_cleanup_fx()
	if msg != "":
		GameState.chat(msg, Color(1.0, 0.75, 0.5))
	for m in get_tree().get_nodes_in_group("blockling"):
		if is_instance_valid(m) and m.has_method("crumble"):
			m.crumble()
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(false)
	collision_layer = 0
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + Vector3(0, -4, 0), 1.2)
	tw.tween_callback(queue_free)


func _cleanup_fx() -> void:
	_free_node(_shadow)
	_free_node(_marker)
	_shadow = null
	_marker = null
	for b in _bricks:
		_free_node(b["node"])
		_free_node(b["shadow"])
	_bricks.clear()
	for w in _waves:
		_free_node(w["node"])
	_waves.clear()


func _exit_tree() -> void:
	_cleanup_fx()
	if GameState and state != S.DEAD and state != S.LEAVING and bool(GameState.get("boss_alive")):
		GameState.set_boss_alive(false)


# ---------------------------------------------------------------- вспомогательное

func _world() -> Node:
	return get_parent() if get_parent() != null else get_tree().current_scene


func _ground_y_at(p: Vector3) -> float:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("walk_height_at") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			return float(cm.call("walk_height_at", floori(p.x), floori(p.z)))
	return 0.0


func _disc(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := MeshInstance3D.new()
	inner.name = "Inner"
	var cm2 := CylinderMesh.new()
	cm2.top_radius = radius
	cm2.bottom_radius = radius
	cm2.height = 0.05
	cm2.radial_segments = 32
	cm2.rings = 1
	inner.mesh = cm2
	var m2 := m.duplicate() as StandardMaterial3D
	m2.albedo_color = Color(col.r, col.g * 0.6, col.b * 0.6, minf(1.0, col.a + 0.25))
	inner.material_override = m2
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.scale = Vector3(0.2, 1, 0.2)
	mi.add_child(inner)
	_world().add_child(mi)
	return mi


func _mini_block(at: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BlockTex.cube_mesh("hill" if _rng.randf() < 0.5 else "ruin", Vector3(0.45, 0.45, 0.45))
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world().add_child(cube)
	cube.global_position = at
	return cube


func _debris(at: Vector3, count: int, speed: float) -> void:
	## Разлёт блоков-осколков (чисто визуально).
	for i in range(count):
		var cube := _mini_block(at)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.2), _rng.randf_range(-1, 1)).normalized()
		var end := at + dir * speed * 0.5 + Vector3(0, -1.0, 0)
		var tw := cube.create_tween()
		tw.set_parallel(true)
		tw.tween_property(cube, "global_position", end, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(cube, "scale", Vector3(0.1, 0.1, 0.1), 0.6)
		tw.chain().tween_callback(cube.queue_free)


func _set_crack_glow(on: bool) -> void:
	## Окно уязвимости: модель светится жёлтым («трещины»), HUD пишет «УЯЗВИМА».
	var model := get_node_or_null("Model")
	if model == null or bool(get_meta("glow", false)) == on:
		return
	set_meta("glow", on)
	for mi in _Vis._meshes_under(model):
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(i)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				bm.emission_enabled = on
				bm.emission = Color(1.0, 0.8, 0.2)
				bm.emission_energy_multiplier = 0.9 if on else 0.0


func _free_node(n: Variant) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


func debug_snapshot() -> Dictionary:
	return {"state": STATE_NAMES[state], "phase": phase, "hp": hp, "log": attack_log.duplicate()}
