extends Node3D
## v0.12: босс «Анаконда» — подземный сегментный червь. Живёт в гнёздах, выходит ТОЛЬКО ночью (ночь 420 с),
## на рассвете уходит. Дизайн и баланс — docs/boss_anaconda.md, GAMEPLAY_REDESIGN_V0.12.md.
##
## Урон наносят ТОЛЬКО поставленные факелы (оружие = 0, факел в руке = 0). Перекрёстный огонь по голове:
##   1 источник — видимость + SLOW, урона нет; 2 — EXPOSED (жжёт); 3+ — усиленный ожог + тактическое замедление.
## Стан (0.75 с) — ТОЛЬКО от событий (разрыв кольца факелом, контрудар по рывку). Свет стан НЕ обновляет.
## После стана — иммунитет 2.5 с и возврат к полноценному AI. Причина вечного стана v0.10/v0.11:
##   обработчик света каждый кадр сбрасывал _stun_len, пока голова была в зоне факелов.
## Каждая секция тела ломает факел касанием (кеш GameState.torch_cells()).
## Фазы: I Охота — трещины, укус, рывок, ложное появление, заманивание в свет;
##        II Территориальный хищник — телеграфируемые атаки по факелам, землеройки (до 3, конечный спавн);
##        III Удушающее кольцо — сжимается, рвётся поставленным факелом внутри → окно стана и контратаки.

const BlockTex := preload("res://scripts/block_tex.gd")
const Sfx := preload("res://scripts/sfx.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
const SM := preload("res://scripts/boss_combat_sm.gd")

enum S { SPAWN, IDLE, UNDER, TELEGRAPH, ATTACK, RECOVERY, VULNERABILITY, STUN, TRANSITION, BURST, REST, RETREAT, DIVE, FAKE, DASH, CAVEIN, TORCHSTRIKE, COIL, CONSTRICT, LEAVING, DEAD }
const STATE_NAMES := ["SPAWN", "IDLE", "UNDER", "TELEGRAPH", "ATTACK", "RECOVERY", "VULNERABILITY", "STUN", "TRANSITION", "BURST", "REST", "RETREAT", "DIVE", "FAKE", "DASH", "CAVEIN", "TORCHSTRIKE", "COIL", "CONSTRICT", "LEAVING", "DEAD"]

# ---- баланс (см. docs/boss_anaconda.md, раздел 3)
const MAX_HP := 1250
const P2_AT := MAX_HP * 66 / 100       # 66%
const P3_AT := MAX_HP * 33 / 100       # 33%
const SEGMENTS := 10
const SPACING := 0.95
const HEAD_SIZE := 1.3
const UNDER_DEPTH := 2.6
const UNDER_SPEED := [7.0, 8.0, 9.0]
const TELEGRAPH := [1.1, 1.0, 0.9]    # трещины на полу перед выныриванием (≥0.8 с)
const BURST_TIME := 0.35
const BURST_HEIGHT := 3.4
const BURST_RADIUS := 1.8
const BURST_DAMAGE := 30               # 30% HP игрока (кап 35%)
const REST_TIME := [2.8, 2.5, 2.3]     # окно на поверхности для перекрёстного огня
const RETREAT_AFTER := 1.6             # столько секунд усиленного ожога — и она вынужденно отступает
const RETREAT_TIME := 0.5
const DIVE_TIME := 0.6
const CONTACT_DAMAGE := 5
const CONTACT_CD := 1.0
const CAVEIN_EVERY := 2
const CAVEIN_WINDUP := 1.3             # зоны обвала видны 1.3 с
const CAVEIN_ZONES_MIN := 3
const CAVEIN_ZONES_MAX := 4
const ROCK_DAMAGE := 14
const ROCK_RADIUS := 1.5
const COIL_EVERY := 3
const COIL_RADIUS := 5.5              # стартовый радиус; к концу сжатия — COIL_END_R
const COIL_TIME := 3.8
const CONSTRICT_WINDUP := 1.2
const CONSTRICT_DAMAGE := 25
const CONSTRICT_INNER := 4.2
const CONSTRICT_SAFE_R := 1.6          # у своего факела внутри кольца сжатие не достаёт
const COIL_CONTACT := 8
const RING_BREAK_DAMAGE := 45          # факел внутри кольца: ожог + стан + окно контратаки
const TRANSITION_TIME := 2.0
# ---- свет и CC (v0.12)
const TORCH_RADIUS := 3.5
const HELD_TORCH_RADIUS := 2.5         # только для подсказок: урона факел в руке не наносит
const BURN_DPS := 13.0                 # 2 источника
const BOOST_MULT := 2.0                # 3+ источника
const TORCH_BREAK_R := 0.65            # касание секцией тела по горизонтали (полширины сегмента + 0.07)
const TORCH_BREAK_DY := 1.0
const STUN_TIME := 0.75
const STUN_IMMUNITY := 2.5
const SLOW_FACTOR := 0.65              # 35% (в диапазоне 25–40%)
const EXPOSED_TIME := 3.0
const SENSE_RADIUS := 16.0
const SENSE_SPRINT_RADIUS := 22.0
# ---- атаки фазы I
const DASH_TIME := 0.9
const DASH_SPEED := 16.0
const DASH_DAMAGE := 22
const DASH_RADIUS := 1.5
const FAKE_TIME := 0.7
# ---- телеграфируемый удар по факелу (фаза II+)
const TORCHSTRIKE_WINDUP := 1.4
const TORCHSTRIKE_CD := 7.0
# ---- землеройки
const MINION_SPAWN := 1
const MINION_CAP := 3
const MINION_FIGHT_MAX := 8
# ---- кольцо (сжимается)
const COIL_START_R := 5.5
const COIL_END_R := 2.6
# ---- поведение
const LEASH_DIST := 42.0
const LEASH_TIME := 8.0
const REWARD_DUST := 300
const REWARD_R3 := 4
const REWARD_R2 := 3
const SUMMON_DIST := 6.0

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var phase: int = 1
var state: int = S.SPAWN
var nest_id: String = ""
var home: Vector3 = Vector3.ZERO
var frozen: bool = false
var combat = SM.new()
var attack_log := {"burst": 0, "burst_hit": 0, "rest": 0, "retreat": 0, "detected": 0, "cavein": 0, "rock_hit": 0,
	"coil": 0, "constrict_hit": 0, "coil_broken": 0, "transition": 0, "minions": 0, "contact_hit": 0, "coil_hit": 0,
	"dash": 0, "dash_hit": 0, "fake": 0, "torchstrike": 0, "torchstrike_hit": 0, "stun": 0, "stun_blocked": 0}
var damage_by_source := {"crossfire2": 0.0, "crossfire3": 0.0, "ring_break": 0.0, "held": 0.0, "weapon": 0.0}
var state_log: Array = []
var phases_seen := {1: true}
var light_damage_total: float = 0.0
var weapon_hits_ignored: int = 0
var held_light_ignored: float = 0.0
var leave_reason: String = ""
var hit_radius: float = 0.8
var torches_broken := 0
var torches_broken_by_body := 0
var break_states: Dictionary = {}

var _t: float = 0.0
var _head: Node3D
var _segs: Array[Node3D] = []
var _trail: Array[Vector3] = []
var _target: Vector3 = Vector3.ZERO
var _emerge: Vector3 = Vector3.ZERO
var _crack: MeshInstance3D = null
var _rocks: Array = []                 # [{shadow, at, t}]
var _dives: int = 0
var _pending_transition: int = 0
var _dmg_acc: float = 0.0
var _contact_cd: float = 0.0
var _rumble_cd: float = 0.0
var _leash_t: float = 0.0
var _coil_center: Vector3 = Vector3.ZERO
var _coil_ang: float = 0.0
var _coil_hit_cd: float = 0.0
var _coil_start_torches: Dictionary = {}
var _boost_t: float = 0.0
var _detect_flag := false
var _rng := RandomNumberGenerator.new()
var _floor_y: float = 0.0
var _last_known: Vector3 = Vector3.ZERO
var _seen_t: float = 99.0
var _lure_in_light: bool = false
var _torch_heat: Dictionary = {}
var _torchstrike_cd: float = 4.0
var _torchstrike_cell := Vector3i(0, -9999, 0)
var _minions_spawned: int = 0
var _next_attack: String = "bite"
var _coil_disc: MeshInstance3D = null
var _dash_dir: Vector3 = Vector3(1, 0, 0)
var _seg_lit: Array = []
var _zones_cache: Array = []
var _zones_stamp := -1
var _zones_torch_rev := -1
var _tick_n := 0


static func spawn_at(host: Node3D, pos: Vector3, nid: String) -> Node:
	if host == null or host.get_tree() == null:
		return null
	if host.get_tree().get_nodes_in_group("anaconda").size() > 0:
		return null
	if host.get_tree().get_nodes_in_group("block_mother").size() > 0:
		return null  # никогда два босса одновременно
	var script: GDScript = load("res://scripts/boss_anaconda.gd")
	var b: Node3D = script.new()
	b.set("nest_id", nid)
	b.set("home", pos)
	b.position = pos
	host.add_child(b)
	return b


func boss_title() -> String:
	return "Анаконда"


func boss_hint() -> String:
	if state == S.STUN:
		return "   — оглушена! окно контратаки"
	if state == S.RETREAT:
		return "   — ОТСТУПАЕТ от света!"
	if state == S.COIL:
		return "   — поставь факел ВНУТРИ сжимающегося кольца!"
	if state == S.TORCHSTRIKE:
		return "   — бьёт по факелу!"
	if state == S.DASH:
		return "   — РЫВОК!"
	if is_invulnerable():
		return "   — в земле"
	if combat.is_slowed() and crossfire_level() == 1:
		return "   — замедлена одним факелом: нужен второй"
	match crossfire_level():
		0: return "   — нужен свет поставленных факелов"
		1: return "   — один факел только заметил её: нужен второй"
		2: return "   — горит в перекрёстном огне"
	return "   — ожог ×2 (3+ факела)"


func set_seed(v: int) -> void:
	_rng.seed = v
	set_meta("seeded", true)


func _ready() -> void:
	if not has_meta("seeded"):
		_rng.randomize()
	add_to_group("anaconda")
	add_to_group("boss")
	add_to_group("enemy")
	_build_body()
	home = position if home == Vector3.ZERO else home
	_floor_y = _floor_at(position)
	for i in range(SEGMENTS * 12):
		_trail.append(position + Vector3(0, -UNDER_DEPTH - float(i) * 0.08, 0))
	_head.position = Vector3(0, -UNDER_DEPTH, 0)
	_last_known = Vector3(position.x, _floor_y, position.z)
	GameState.set_boss_alive(true)
	if GameState.has_signal("world_changed"):
		GameState.world_changed.connect(_on_world)
	_on_world(GameState.is_dream())
	_enter(S.SPAWN)
	roar()
	GameState.chat("Из гнезда поднимается Анаконда! Сталь и факел в руке её не берут — жгут только ПОСТАВЛЕННЫЕ факелы, 2–3 с разных сторон.", Color(1.0, 0.5, 0.3))


func _on_world(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream


func _build_body() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	var hm := MeshInstance3D.new()
	hm.name = "Mesh"
	hm.mesh = BlockTex.cube_mesh("scale_head", Vector3(HEAD_SIZE, HEAD_SIZE * 0.85, HEAD_SIZE * 1.25))
	_head.add_child(hm)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.18, 0.14, 0.06)
		eye.mesh = em
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.6, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.1)
		mat.emission_energy_multiplier = 2.2
		eye.material_override = mat
		eye.position = Vector3(side * 0.32, 0.18, -HEAD_SIZE * 0.63)
		_head.add_child(eye)
	_Vis.attach_hp_bar(_head, HEAD_SIZE + 0.4)
	var bar := _head.get_node_or_null("HPBar") as Node3D
	if bar:
		bar.scale = Vector3(2.0, 2.0, 2.0)
	for i in range(1, SEGMENTS):
		var k := 1.0 - float(i) / float(SEGMENTS) * 0.45
		var seg := MeshInstance3D.new()
		seg.name = "Seg%d" % i
		seg.mesh = BlockTex.cube_mesh("scale", Vector3(1.15, 1.0, 1.15) * k, false, Color(1, 1, 1) if i % 2 == 0 else Color(0.86, 0.9, 0.8))
		add_child(seg)
		_segs.append(seg)


# ---------------------------------------------------------------- урон

func hit_center() -> Vector3:
	return _head.global_position if _head else global_position


func is_fight_active() -> bool:
	return state != S.DEAD and state != S.LEAVING


func is_invulnerable() -> bool:
	return state in [S.SPAWN, S.IDLE, S.UNDER, S.TELEGRAPH, S.TRANSITION, S.LEAVING, S.DEAD, S.DIVE, S.FAKE]


func is_vulnerable() -> bool:
	## Уязвима, когда голова на поверхности или в стане/окне контратаки. Свет сам по себе AI не стопит.
	return state in [S.BURST, S.REST, S.RETREAT, S.COIL, S.CONSTRICT, S.CAVEIN, S.STUN, S.DASH, S.VULNERABILITY, S.RECOVERY, S.ATTACK, S.TORCHSTRIKE]


func take_damage(_amount: int) -> void:
	receive_weapon_hit(_amount, "")


func receive_weapon_hit(_amount: int, _weapon_id: String = "") -> Dictionary:
	## Меч и кирка не пробивают чешую — 0 урона, только подсказка.
	weapon_hits_ignored += 1
	if weapon_hits_ignored == 1 or weapon_hits_ignored % 8 == 0:
		GameState.set_hint("Клинок соскальзывает с чешуи — Анаконду жгут только поставленные факелы!", weapon_hits_ignored == 1)
	return {"dealt": 0, "target": "scales", "bounce": true}


func apply_light_damage(amount: float, source: String = "crossfire2") -> int:
	if state == S.DEAD or state == S.LEAVING or is_invulnerable() or amount <= 0.0:
		return 0
	_dmg_acc += amount
	var dmg := int(_dmg_acc)
	if dmg <= 0:
		return 0
	_dmg_acc -= float(dmg)
	var floor_hp := 0
	if phase == 1:
		floor_hp = P2_AT
	elif phase == 2:
		floor_hp = P3_AT
	var before := hp
	hp = maxi(floor_hp, hp - dmg)
	var dealt := before - hp
	light_damage_total += float(dealt)
	damage_by_source[source] = float(damage_by_source.get(source, 0.0)) + float(dealt)
	_Vis.update_hp_bar(_head, hp, max_hp)
	if phase == 1 and hp <= P2_AT:
		_pending_transition = 2
	elif phase == 2 and hp <= P3_AT:
		_pending_transition = 3
	if hp <= 0:
		_die()
	return dealt


static func torch_pos(c: Vector3i) -> Vector3:
	return Vector3(float(c.x) + 0.5, float(c.y) + 0.6, float(c.z) + 0.5)


func light_zones() -> Array:
	## [{pos, r, held}] — только ПОСТАВЛЕННЫЕ факелы (кеш GameState). Факел в руке в список не входит.
	## Кэш на один physics-tick, но сбрасывается при изменении списка факелов в том же кадре
	## (постановка/разрыв кольца, тесты, пишущие в wake_blocks).
	var cells: Array[Vector3i] = [] if GameState.is_dream() else GameState.torch_cells()
	var rev := int(GameState.torch_cache_rebuilds)
	if _zones_stamp == _tick_n and _zones_torch_rev == rev:
		return _zones_cache
	var out: Array = []
	if not GameState.is_dream():
		for c in cells:
			var wp := torch_pos(c)
			if _head == null or wp.distance_to(_head.global_position) < 40.0:
				out.append({"pos": wp, "r": TORCH_RADIUS, "held": false, "cell": c})
	_zones_cache = out
	_zones_stamp = _tick_n
	_zones_torch_rev = rev
	return out


func is_point_lit(pt: Vector3) -> bool:
	for z in light_zones():
		if (z["pos"] as Vector3).distance_to(pt) <= float(z["r"]):
			return true
	return false


func crossfire_level() -> int:
	## v0.12: максимум пересечений по сегментам. Два источника на ОДНОМ сегменте — уязвимость.
	if _head == null:
		return 0
	var best := 0
	for p in segment_positions():
		var n := 0
		for z in light_zones():
			if (z["pos"] as Vector3).distance_to(p) <= float(z["r"]) + 0.4:
				n += 1
		if n > best:
			best = n
	return best


func light_dps() -> float:
	## 1 источник — 0 (обнаружение), 2 — BURN_DPS, 3+ — BURN_DPS × BOOST_MULT. Факел в руке — всегда 0.
	if is_invulnerable():
		return 0.0
	var n := crossfire_level()
	if n < 2:
		return 0.0
	return BURN_DPS * (BOOST_MULT if n >= 3 else 1.0)


func held_torch_near() -> bool:
	var p := _player()
	return p != null and _head != null and GameState.selected_is("torch") and p.global_position.distance_to(_head.global_position) <= HELD_TORCH_RADIUS + 1.0


# ---------------------------------------------------------------- машина состояний

func _shared_phase(s: int) -> int:
	match s:
		S.SPAWN, S.IDLE, S.UNDER:
			return SM.Phase.IDLE
		S.TELEGRAPH, S.TORCHSTRIKE:
			return SM.Phase.TELEGRAPH
		S.BURST, S.DASH, S.FAKE, S.ATTACK, S.CAVEIN, S.COIL, S.CONSTRICT:
			return SM.Phase.ATTACK
		S.RETREAT, S.DIVE, S.RECOVERY:
			return SM.Phase.RECOVERY
		S.REST, S.STUN, S.VULNERABILITY:
			return SM.Phase.VULNERABILITY
		S.TRANSITION:
			return SM.Phase.TRANSITION
	return SM.Phase.CUSTOM


func _state_max(s: int) -> float:
	match s:
		S.SPAWN: return 3.0
		S.UNDER, S.IDLE: return 10.0
		S.TELEGRAPH: return 2.5
		S.BURST: return 1.2
		S.DASH: return 2.0
		S.FAKE: return 2.0
		S.TORCHSTRIKE: return 2.4
		S.CAVEIN: return 3.5
		S.COIL: return 8.0
		S.CONSTRICT: return 2.5
		S.REST, S.VULNERABILITY: return 4.5
		S.RETREAT, S.DIVE, S.RECOVERY: return 1.8
		S.STUN: return 1.5
		S.TRANSITION: return 3.0
		S.LEAVING, S.DEAD: return 8.0
	return 8.0


func _enter(s: int) -> void:
	state = s
	_t = 0.0
	state_log.append([STATE_NAMES[s], phase, hp])
	if state_log.size() > 400:
		state_log.remove_at(0)
	combat.enter(STATE_NAMES[s], _shared_phase(s), _state_max(s))


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D if is_inside_tree() else null


func _chunks() -> Node:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			return cm
	return null


func _floor_at(p: Vector3) -> float:
	var cm := _chunks()
	if cm and cm.has_method("floor_y_below"):
		return float(cm.floor_y_below(p + Vector3(0, 1.2, 0), 40))
	return 0.0


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if frozen or state == S.DEAD or state == S.LEAVING:
		return
	_tick_n += 1
	combat.tick(delta)
	if combat.timed_out() and state not in [S.DEAD, S.LEAVING]:
		_recover_timeout(_player())
		if state == S.DEAD or state == S.LEAVING:
			return
	check_body_torch_contacts()
	_t += delta
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_coil_hit_cd = maxf(0.0, _coil_hit_cd - delta)
	_torchstrike_cd = maxf(0.0, _torchstrike_cd - delta)
	if not GameState.is_night():
		leave("Светает — Анаконда уходит в глубину.")
		return
	var player := _player()
	if player == null:
		return
	if player.global_position.distance_to(home) > LEASH_DIST:
		_leash_t += delta
		if _leash_t > LEASH_TIME:
			leave("Анаконда потеряла тебя и вернулась в гнездо.")
			return
	else:
		_leash_t = 0.0
	_update_sense(player, delta)
	_track_torch_heat(player, delta)
	var lvl := crossfire_level() if not is_invulnerable() else 0
	if lvl == 1 and not _detect_flag:
		attack_log["detected"] += 1
	_detect_flag = lvl == 1
	# CC от света: только SLOW/EXPOSED. Стан от освещения ЗАПРЕЩЁН — это была первопричина вечного стана.
	_apply_light_cc(lvl, delta)
	var dps := light_dps()
	if dps > 0.0:
		apply_light_damage(dps * delta, "crossfire3" if lvl >= 3 else "crossfire2")
		if state == S.DEAD:
			return
	if held_torch_near() and not is_invulnerable():
		held_light_ignored += delta
	_tick_rocks(delta, player)
	_update_seg_light()
	match state:
		S.SPAWN:
			_move_head(home + Vector3(0, 1.6 * minf(1.0, _t / 1.6), 0), delta, 4.0)
			if _t >= 2.0:
				_go_under()
		S.IDLE, S.UNDER:
			_tick_under(delta, player)
		S.TELEGRAPH:
			_move_head(_emerge + Vector3(0, -UNDER_DEPTH, 0), delta, 10.0)
			if _crack:
				var k := 1.0 + 0.15 * sin(_t * 30.0)
				_crack.scale = Vector3(k, 1, k)
			if _t >= float(TELEGRAPH[phase - 1]):
				_resolve_telegraph(player)
		S.BURST, S.ATTACK:
			var f := minf(1.0, _t / BURST_TIME)
			_move_head(_emerge + Vector3(0, -UNDER_DEPTH + (UNDER_DEPTH + BURST_HEIGHT) * f, 0), delta, 40.0)
			if _t >= BURST_TIME:
				attack_log["rest"] += 1
				_boost_t = 0.0
				_rest_lock = _rest_dir()
				_enter(S.REST)
				if phase >= 2 and _dives % CAVEIN_EVERY == 1:
					_start_cavein(player)
		S.DASH:
			_tick_dash(delta, player)
		S.FAKE:
			_tick_fake(delta, player)
		S.TORCHSTRIKE:
			_tick_torchstrike(delta, player)
		S.STUN, S.VULNERABILITY:
			# Стан: дрожь на месте. По истечении таймера — REST (окно контратаки), AI не блокируется светом.
			if _head:
				_head.position += Vector3(sin(_t * 48.0) * 0.015, 0, cos(_t * 41.0) * 0.015)
			if not combat.is_stunned() or (state == S.VULNERABILITY and _t >= EXPOSED_TIME):
				_flash_body(false)
				if _pending_transition > 0:
					_start_transition()
				else:
					attack_log["rest"] += 1
					_boost_t = 0.0
					_enter(S.REST)
		S.REST:
			var lie := _emerge + Vector3(0, HEAD_SIZE * 0.45, 0) + _rest_dir() * 1.6
			_move_head(lie, delta, 6.0)
			_contact(player)
			_boost_t = _boost_t + delta if lvl >= 3 else maxf(0.0, _boost_t - delta * 0.5)
			if _pending_transition > 0:
				_start_transition()
			elif _boost_t >= RETREAT_AFTER:
				attack_log["retreat"] += 1
				_enter(S.RETREAT)
				roar(false)
				_flash_body(true)
			elif _t >= float(REST_TIME[phase - 1]):
				_start_dive()
		S.RETREAT:
			var away := _emerge + _rest_dir() * 2.4 + Vector3(0, HEAD_SIZE * 0.3, 0)
			_move_head(away, delta, 9.0)
			if _t >= RETREAT_TIME:
				_flash_body(false)
				_start_dive()
		S.DIVE, S.RECOVERY:
			var f2 := minf(1.0, _t / DIVE_TIME)
			_move_head(_emerge + _rest_dir() * 3.2 + Vector3(0, lerpf(HEAD_SIZE * 0.45, -UNDER_DEPTH, f2), 0), delta, 20.0)
			if _t >= DIVE_TIME:
				_after_dive(player)
		S.CAVEIN:
			if _t >= CAVEIN_WINDUP + 0.6:
				_go_under()
		S.COIL:
			_tick_coil(delta, player)
		S.CONSTRICT:
			_tick_coil_body(delta)
			_flash_body(true)
			if _t >= CONSTRICT_WINDUP:
				_flash_body(false)
				_resolve_constrict(player)
		S.TRANSITION:
			_move_head(_head.global_position.lerp(Vector3(_head.global_position.x, _floor_y + 3.5, _head.global_position.z), 0.1), delta, 8.0)
			if _t >= TRANSITION_TIME:
				_go_under()
	_update_body()


func _go_under() -> void:
	_enter(S.UNDER)
	_free_crack()
	_free_coil_disc()


func _update_sense(player: CharacterBody3D, delta: float) -> void:
	## Нет wallhack: точная позиция игрока известна только в радиусе слуха/вибрации или когда она на поверхности и «видит».
	var d := Vector2(_head.global_position.x - player.global_position.x, _head.global_position.z - player.global_position.z).length() if _head else 99.0
	var speeding := player.velocity.length() > 4.0
	var heard := d <= SENSE_RADIUS or (speeding and d <= SENSE_SPRINT_RADIUS)
	var seen := is_vulnerable() and d <= 14.0
	if heard or seen:
		var pf := _floor_at(player.global_position)
		_last_known = Vector3(player.global_position.x, pf, player.global_position.z)
		_seen_t = 0.0
		_lure_in_light = _count_lights_at(_last_known) >= 2
	else:
		_seen_t += delta


func _count_lights_at(pt: Vector3) -> int:
	var n := 0
	for z in light_zones():
		if (z["pos"] as Vector3).distance_to(pt) <= float(z["r"]):
			n += 1
	return n


func _track_torch_heat(player: CharacterBody3D, _delta: float) -> void:
	for z in light_zones():
		if (z["pos"] as Vector3).distance_to(player.global_position) <= 3.2:
			var c: Vector3i = z.get("cell", Vector3i.ZERO)
			_torch_heat[c] = float(_torch_heat.get(c, 0.0)) + _delta


func _hottest_torch() -> Vector3i:
	var best := Vector3i(0, -9999, 0)
	var bh := -1.0
	for c in GameState.torch_cells():
		var h := float(_torch_heat.get(c, 0.0))
		# Если тепло одинаковое — ближе к последней известной позиции игрока.
		var d := torch_pos(c).distance_to(_last_known) if _last_known != Vector3.ZERO else 0.0
		var score := h * 10.0 - d
		if score > bh:
			bh = score
			best = c
	return best


func _steer_under(to: Vector3) -> Vector3:
	## Обходит освещённые зоны, если игрок специально не заманивает её в свет.
	if _lure_in_light:
		return to
	if not is_point_lit(to + Vector3(0, UNDER_DEPTH, 0)) and not is_point_lit(to):
		return to
	var nearest := Vector3.ZERO
	var nd := 99.0
	for z in light_zones():
		var d: float = (z["pos"] as Vector3).distance_to(to)
		if d < nd:
			nd = d
			nearest = z["pos"]
	var away := to - nearest
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	return to + away.normalized() * (TORCH_RADIUS + 1.2)


func _choose_attack() -> String:
	# Заманенная в свет не делает ложный выпад — игрок должен получить окно урона.
	if phase >= 2 and _torchstrike_cd <= 0.0 and _hottest_torch().y != -9999 and _rng.randf() < 0.28:
		return "torchstrike"
	var r := _rng.randf()
	if _lure_in_light:
		if r < 0.28:
			return "dash"
		return "bite"
	if phase == 1:
		if r < 0.12:
			return "fake"
		if r < 0.34:
			return "dash"
		return "bite"
	if r < 0.10:
		return "fake"
	if r < 0.38:
		return "dash"
	return "bite"


func _tick_under(delta: float, player: CharacterBody3D) -> void:
	if _last_known == Vector3.ZERO:
		_last_known = Vector3(player.global_position.x, _floor_at(player.global_position), player.global_position.z)
	_target = _steer_under(_last_known)
	_target.y = _floor_at(_target)
	var under_t := _target + Vector3(0, -UNDER_DEPTH, 0)
	_move_head(under_t, delta, float(UNDER_SPEED[phase - 1]))
	_rumble_cd -= delta
	if _rumble_cd <= 0.0:
		_rumble_cd = 1.6
		Sfx.play3d(_head, Sfx.ANACONDA_RUMBLE, -4.0, 40.0)
		var crack_at := Vector3(_head.global_position.x, _floor_at(_head.global_position) + 0.1, _head.global_position.z)
		_dust_puff(crack_at)
		# Движущаяся трещина-телеграф направления охоты.
		if _t > 0.4:
			_make_hunt_crack(crack_at)
	var flat := Vector2(_head.global_position.x - under_t.x, _head.global_position.z - under_t.z).length()
	if flat < 1.2 or _t > 6.0:
		_emerge = _target
		_floor_y = _target.y
		_next_attack = _choose_attack()
		if _next_attack == "torchstrike":
			_start_torchstrike()
		else:
			_enter(S.TELEGRAPH)
			_make_crack(_emerge)


func _recover_timeout(player: CharacterBody3D) -> void:
	## Failsafe: ни одно боевое состояние не длится бесконечно.
	if state == S.COIL:
		_enter(S.CONSTRICT)
	elif state == S.CONSTRICT:
		_resolve_constrict(player if player else _player())
	elif state in [S.STUN, S.REST, S.VULNERABILITY, S.RETREAT, S.DASH, S.FAKE, S.TORCHSTRIKE, S.BURST, S.ATTACK, S.TELEGRAPH, S.CAVEIN]:
		_start_dive()
	elif state == S.TRANSITION:
		_go_under()
	elif state in [S.UNDER, S.IDLE] and player:
		_emerge = _last_known if _last_known != Vector3.ZERO else player.global_position
		_emerge.y = _floor_at(_emerge)
		_enter(S.TELEGRAPH)
		_make_crack(_emerge)


func _apply_light_cc(lvl: int, delta: float) -> void:
	## Свет никогда не вызывает try_stun. 1 факел — SLOW; 2+ — ещё и EXPOSED (урон идёт через light_dps).
	if lvl >= 1 and is_vulnerable():
		combat.apply_slow(SLOW_FACTOR, 0.25)
	if lvl >= 2 and is_vulnerable():
		combat.apply_exposed(0.25)
	# Диагностика: если какой-то старый путь попытается станить светом — счётчик вырастет, стан не применится.
	if lvl >= 3:
		combat.try_stun(STUN_TIME, "light")


func _resolve_telegraph(player: CharacterBody3D) -> void:
	match _next_attack:
		"fake":
			_start_fake(player)
		"dash":
			_start_dash(player)
		_:
			_start_burst(player)


func _start_burst(player: CharacterBody3D) -> void:
	if not combat.begin_attack("bite", 0.8):
		_start_dive()
		return
	_rest_lock = Vector3.ZERO
	_enter(S.BURST)
	attack_log["burst"] += 1
	_free_crack()
	_dust_puff(_emerge + Vector3(0, 0.2, 0))
	var hid := "burst_%d" % attack_log["burst"]
	var to := player.global_position - _emerge
	if combat.can_hit(hid) and Vector2(to.x, to.z).length() <= BURST_RADIUS and to.y > -1.0 and to.y < 2.5:
		if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,BURST_DAMAGE), "Анаконда: укус из-под земли") > 0:
			attack_log["burst_hit"] += 1
			player.velocity += Vector3(to.x, 0, to.z).normalized() * 7.0 + Vector3(0, 4.0, 0)


func _start_fake(_player: CharacterBody3D) -> void:
	if not combat.begin_attack("fake", 1.2):
		_start_burst(_player)
		return
	attack_log["fake"] += 1
	_enter(S.FAKE)
	# Трещина гаснет — ложное появление, настоящее будет в стороне.


func _tick_fake(delta: float, player: CharacterBody3D) -> void:
	_move_head(_emerge + Vector3(0, -UNDER_DEPTH - 0.4, 0), delta, 8.0)
	if _crack:
		_crack.transparency = clampf(_t / FAKE_TIME, 0.0, 1.0)
		_crack.scale = Vector3(1.0 + _t, 1, 1.0 + _t) * (1.0 - _t / (FAKE_TIME + 0.05))
	if _t >= FAKE_TIME:
		_free_crack()
		# Переезжает на 7 м в сторону и снова идёт в охоту — игрок успел среагировать впустую.
		var side := Vector3(cos(_rng.randf() * TAU), 0, sin(_rng.randf() * TAU)) * 7.0
		_last_known = _steer_under(_emerge + side)
		_go_under()


func _start_dash(player: CharacterBody3D) -> void:
	if not combat.begin_attack("dash", 1.6):
		_start_burst(player)
		return
	attack_log["dash"] += 1
	_rest_lock = Vector3.ZERO
	_enter(S.DASH)
	_free_crack()
	var aim := _last_known if _seen_t < 1.2 else player.global_position
	_dash_dir = Vector3(aim.x - _emerge.x, 0, aim.z - _emerge.z)
	if _dash_dir.length() < 0.1:
		_dash_dir = _rest_dir() * -1.0
	_dash_dir = _dash_dir.normalized()
	_coil_start_torches = {}
	for c in GameState.torch_cells():
		_coil_start_torches[c] = true
	_dust_puff(_emerge + Vector3(0, 0.2, 0))
	roar(false)


func _tick_dash(delta: float, player: CharacterBody3D) -> void:
	var rise := minf(1.0, _t / 0.2)
	var ahead := _emerge + _dash_dir * (DASH_SPEED * minf(_t, DASH_TIME)) + Vector3(0, lerpf(-UNDER_DEPTH, HEAD_SIZE * 0.4, rise), 0)
	_move_head(ahead, delta, 28.0)
	var hid := "dash_%d" % attack_log["dash"]
	if combat.can_hit(hid):
		# can_hit помечает сразу — проверяем попадание в этом же кадре, иначе удар «сгорает».
		pass
	# Попадание одно на рывок, но can_hit уже сжёг id. Отдельный флаг:
	if not attack_log.has("dash_landed_%d" % attack_log["dash"]):
		var d := player.global_position - _head.global_position
		if Vector2(d.x, d.z).length() <= DASH_RADIUS and d.y > -0.8 and d.y < 2.2:
			if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,DASH_DAMAGE), "Анаконда: рывок") > 0:
				attack_log["dash_hit"] += 1
				player.velocity += _dash_dir * 8.0 + Vector3(0, 3.5, 0)
			attack_log["dash_landed_%d" % attack_log["dash"]] = 1
			# Контрудар проверяется ниже по новым факелам у головы.
	# Контрудар: факел, поставленный у головы ВО ВРЕМЯ рывка, — событие стана.
	if state == S.DASH:
		for c in GameState.torch_cells():
			if _coil_start_torches.has(c):
				continue
			if torch_pos(c).distance_to(_head.global_position) <= 2.2:
				_maybe_event_stun("dash_counter")
				return
	if _t >= DASH_TIME:
		_emerge = _head.global_position
		_emerge.y = _floor_at(_emerge)
		_rest_lock = _dash_dir
		_boost_t = 0.0
		attack_log["rest"] += 1
		_enter(S.REST)


func _maybe_event_stun(source: String) -> bool:
	## Стан только от события (не от поля света).
	if combat.try_stun(STUN_TIME, source, STUN_IMMUNITY):
		attack_log["stun"] += 1
		combat.apply_exposed(EXPOSED_TIME)
		_enter(S.STUN)
		_flash_body(true)
		GameState.set_hint("Анаконда оглушена! Окно контратаки.", false)
		return true
	attack_log["stun_blocked"] += 1
	return false


func _start_torchstrike() -> void:
	_torchstrike_cell = _hottest_torch()
	if _torchstrike_cell.y == -9999 or not combat.begin_attack("torchstrike", TORCHSTRIKE_CD):
		_enter(S.TELEGRAPH)
		_make_crack(_emerge)
		_next_attack = "bite"
		return
	attack_log["torchstrike"] += 1
	_torchstrike_cd = TORCHSTRIKE_CD
	_enter(S.TORCHSTRIKE)
	var tp := torch_pos(_torchstrike_cell)
	_emerge = Vector3(tp.x, _floor_at(tp), tp.z)
	_make_crack(_emerge)
	if _crack:
		# Более яркий телеграф выбранного факела.
		var mat := _crack.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.85, 0.2, 0.85)
			mat.emission = Color(1.0, 0.8, 0.15)
			mat.emission_energy_multiplier = 1.4
	GameState.set_hint("Анаконда целится в факел!", false)
	roar(false)


func _tick_torchstrike(delta: float, _player: CharacterBody3D) -> void:
	var tp := torch_pos(_torchstrike_cell)
	_move_head(Vector3(tp.x, _floor_at(tp) - UNDER_DEPTH * 0.4, tp.z), delta, 14.0)
	if _crack:
		var k := 1.0 + 0.2 * sin(_t * 26.0)
		_crack.scale = Vector3(k, 1, k)
	if _t >= TORCHSTRIKE_WINDUP:
		if str(GameState.wake_blocks.get(_torchstrike_cell, {}).get("kind", "")) == "torch":
			if break_torch(_torchstrike_cell, "удар"):
				attack_log["torchstrike_hit"] += 1
		_free_crack()
		_start_dive()


var _rest_lock := Vector3.ZERO


func _rest_dir() -> Vector3:
	## Направление, куда ляжет тело, фиксируется в момент выныривания (читаемо: тело не «метёт» по кругу).
	if _rest_lock != Vector3.ZERO and state in [S.REST, S.RETREAT, S.DIVE]:
		return _rest_lock
	var p := _player()
	if p == null:
		return Vector3(1, 0, 0)
	var d := _emerge - p.global_position
	d.y = 0
	return d.normalized() if d.length() > 0.1 else Vector3(1, 0, 0)


func _start_dive() -> void:
	_enter(S.DIVE)
	_dives += 1


func _after_dive(player: CharacterBody3D) -> void:
	if phase >= 3 and _dives % COIL_EVERY == 0:
		_start_coil(player)
		return
	_go_under()


func _contact(player: CharacterBody3D) -> void:
	if _contact_cd > 0.0:
		return
	if player.global_position.distance_to(_head.global_position) < HEAD_SIZE * 0.5 + 0.6:
		_contact_cd = CONTACT_CD
		if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,CONTACT_DAMAGE), "Анаконда: касание") > 0:
			attack_log["contact_hit"] += 1


# ---------------------------------------------------------------- касание тела ломает факелы

func check_body_torch_contacts() -> int:
	## Каждая секция ломает факел касанием. Во время рывка — нет: иначе световая сеть сносится без телеграфа.
	if _head == null or GameState.is_dream() or state == S.DASH:
		return 0
	var cells := GameState.torch_cells()
	if cells.is_empty():
		return 0
	var parts: Array = segment_positions()
	var hpos := _head.global_position
	var victims: Array = []
	for c in cells:
		var tp := torch_pos(c)
		if tp.distance_to(hpos) > SPACING * float(SEGMENTS) + 3.0:
			continue
		for pp in parts:
			var q: Vector3 = pp
			if Vector2(q.x - tp.x, q.z - tp.z).length() <= TORCH_BREAK_R and absf(q.y - tp.y) <= TORCH_BREAK_DY:
				victims.append(c)
				break
	for v in victims:
		break_torch(v, "тело")
	return victims.size()


func break_torch(c: Vector3i, by: String = "тело") -> bool:
	if not GameState.remove_torch(c):
		return false
	torches_broken += 1
	if by == "тело":
		torches_broken_by_body += 1
		var bk := "break_in_" + str(STATE_NAMES[state])
		break_states[bk] = int(break_states.get(bk, 0)) + 1
	if is_inside_tree():
		for v in get_tree().get_nodes_in_group("voxel_world"):
			if not v.is_dream_layer:
				v.remove_block(c)
		_dust_puff(torch_pos(c))
	GameState.chat("Анаконда сломала факел (%s)!" % by, Color(1, 0.7, 0.3))
	return true


func try_break_torch(c: Vector3i, _roll: float = -1.0) -> bool:
	## Совместимость v0.11: теперь касание ломает всегда.
	return break_torch(c, "тело")


# ---------------------------------------------------------------- фаза 2: обвал + землеройки

func cavein_zone_count() -> int:
	return CAVEIN_ZONES_MIN + (1 if _rng.randf() < 0.5 else 0)


func _start_cavein(player: CharacterBody3D) -> void:
	## Обвал не отнимает окно урона: камни падают, пока голова на поверхности (состояние REST сохраняется).
	attack_log["cavein"] += 1
	roar(true)
	GameState.set_hint("Обвал! Уходи из тёмных кругов.", false)
	var center := player.global_position
	var n := cavein_zone_count()
	var base := _rng.randf() * TAU
	for i in range(n):
		var p: Vector3
		if i == 0:
			p = center
		else:
			# Зоны по кругу с промежутками: между ними всегда есть безопасный проход.
			var a := base + TAU * float(i) / float(n - 1) * 0.85
			p = center + Vector3(cos(a) * 3.4, 0, sin(a) * 3.4)
		p.y = _floor_at(p)
		var sh := _disc(ROCK_RADIUS, Color(0.15, 0.1, 0.05, 0.75))
		sh.position = p + Vector3(0, 0.05, 0)
		_world().add_child(sh)
		_rocks.append({"shadow": sh, "at": p, "t": CAVEIN_WINDUP + 0.1 * float(i)})
	attack_log["cavein_n"] = int(attack_log.get("cavein_n", 0)) + n
	_spawn_minions(MINION_SPAWN)   # по одной землеройке на обвал, живых не больше 2


func _tick_rocks(delta: float, player: CharacterBody3D) -> void:
	var keep: Array = []
	for r in _rocks:
		r["t"] = float(r["t"]) - delta
		if float(r["t"]) > 0.0:
			var sh: MeshInstance3D = r["shadow"]
			if is_instance_valid(sh):
				var k := 1.0 + 0.25 * (1.0 - clampf(float(r["t"]) / CAVEIN_WINDUP, 0.0, 1.0))
				sh.scale = Vector3(k, 1, k)
			keep.append(r)
			continue
		var at: Vector3 = r["at"]
		_free_node(r["shadow"])
		_dust_puff(at + Vector3(0, 0.3, 0))
		var d := player.global_position - at
		if Vector2(d.x, d.z).length() <= ROCK_RADIUS + 0.3 and d.y > -0.6 and d.y < 2.0:
			if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,ROCK_DAMAGE), "Анаконда: обвал") > 0:
				attack_log["rock_hit"] += 1
	_rocks = keep


func alive_minions() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("anaconda_minion"):
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			n += 1
	return n


func _spawn_minions(count: int) -> int:
	var room := mini(MINION_CAP - alive_minions(), MINION_FIGHT_MAX - _minions_spawned)
	var n := mini(count, room)
	if n <= 0:
		return 0
	var script: GDScript = load("res://scripts/anaconda_worm.gd")
	for i in range(n):
		var w: Node3D = script.new()
		var a := _rng.randf() * TAU
		var p := _head.global_position + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)
		p.y = _floor_at(p)
		w.position = p
		w.set("boss", self)
		_world().add_child(w)
	attack_log["minions"] += n
	_minions_spawned += n
	return n


# ---------------------------------------------------------------- фаза 3: кольцо

func _start_coil(player: CharacterBody3D) -> void:
	if not combat.begin_attack("coil", 4.0):
		_go_under()
		return
	_enter(S.COIL)
	attack_log["coil"] += 1
	roar(true)
	_coil_center = player.global_position
	_coil_center.y = _floor_at(_coil_center)
	var d := _head.global_position - _coil_center
	_coil_ang = atan2(d.z, d.x)
	_coil_start_torches = {}
	for c in GameState.torch_cells():
		_coil_start_torches[c] = true
	_free_coil_disc()
	_coil_disc = _disc(coil_radius(), Color(0.85, 0.2, 0.1, 0.45))
	_coil_disc.position = _coil_center + Vector3(0, 0.06, 0)
	_world().add_child(_coil_disc)
	GameState.set_hint("Анаконда сворачивается кольцом и сжимает его! Поставь факел ВНУТРИ — или выпрыгни.", false)


func coil_center() -> Vector3:
	return _coil_center


func coil_radius() -> float:
	var k := clampf(_t / COIL_TIME, 0.0, 1.0) if state in [S.COIL, S.CONSTRICT] else 0.0
	if state == S.CONSTRICT:
		k = 1.0
	return lerpf(COIL_START_R, COIL_END_R, k)


func _coil_point(ang: float) -> Vector3:
	var r := coil_radius()
	return _coil_center + Vector3(cos(ang) * r, 0.6, sin(ang) * r)


func _tick_coil_body(delta: float) -> void:
	_coil_ang += TAU / COIL_TIME * delta * 0.35
	_move_head(_coil_point(_coil_ang), delta, 30.0)


func torch_placed_inside_coil() -> bool:
	## Кольцо рвёт только факел, поставленный внутри кольца ПОСЛЕ его начала (факел в руке не считается).
	var r := coil_radius()
	for c in GameState.torch_cells():
		if _coil_start_torches.has(c):
			continue
		var tp := torch_pos(c)
		if Vector2(tp.x - _coil_center.x, tp.z - _coil_center.z).length() <= r - 0.4:
			return true
	return false


func _tick_coil(delta: float, player: CharacterBody3D) -> void:
	_coil_ang += TAU / COIL_TIME * delta
	_move_head(_coil_point(_coil_ang), delta, 30.0)
	if _coil_disc and is_instance_valid(_coil_disc):
		var r := coil_radius()
		_coil_disc.scale = Vector3(r / maxf(0.2, COIL_START_R), 1, r / maxf(0.2, COIL_START_R))
		_coil_disc.position = _coil_center + Vector3(0, 0.06, 0)
	if _coil_hit_cd <= 0.0:
		var hid := "coil_tick_%d" % int(_t)
		for s in _segs:
			if s.global_position.distance_to(player.global_position + Vector3(0, 0.6, 0)) < 0.9:
				_coil_hit_cd = 1.0
				if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,COIL_CONTACT), "Анаконда: чешуя кольца") > 0:
					attack_log["coil_hit"] += 1
				break
	if _t > 0.4 and torch_placed_inside_coil():
		attack_log["coil_broken"] += 1
		apply_light_damage(float(RING_BREAK_DAMAGE), "ring_break")
		if state == S.DEAD:
			return
		_emerge = _head.global_position
		_emerge.y = _floor_at(_emerge)
		_free_coil_disc()
		roar(false)
		GameState.set_hint("Факел разорвал кольцо — Анаконда оглушена!", false)
		if not _maybe_event_stun("ring_break"):
			_enter(S.RETREAT)
		return
	if _t >= COIL_TIME:
		_enter(S.CONSTRICT)


func _resolve_constrict(player: CharacterBody3D) -> void:
	var d := player.global_position - _coil_center
	var inside := Vector2(d.x, d.z).length() < CONSTRICT_INNER and d.y < 1.6
	var safe := false
	for c in GameState.torch_cells():
		if torch_pos(c).distance_to(player.global_position + Vector3(0, 0.6, 0)) <= CONSTRICT_SAFE_R:
			safe = true
			break
	if inside and not safe:
		if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,CONSTRICT_DAMAGE), "Анаконда: удушение") > 0:
			attack_log["constrict_hit"] += 1
	_emerge = _head.global_position
	_emerge.y = _floor_at(_emerge)
	_enter(S.REST)


func _flash_body(on: bool) -> void:
	for s in _segs:
		var mi := s as MeshInstance3D
		if mi:
			mi.transparency = 0.0
			mi.scale = Vector3.ONE * (1.08 if on and int(_t * 10.0) % 2 == 0 else 1.0)


# ---------------------------------------------------------------- переходы, смерть, уход

func _start_transition() -> void:
	var to := _pending_transition
	_pending_transition = 0
	if to <= phase:
		return
	phase = to
	phases_seen[phase] = true
	attack_log["transition"] += 1
	_enter(S.TRANSITION)
	roar(true)
	Sfx.play3d(_head, Sfx.ANACONDA_RUMBLE, 0.0, 60.0)
	var what := "Обвалы и землеройки — они гасят факелы!" if phase == 2 else "Удушающее кольцо — ставь факел внутри него!"
	GameState.chat("Анаконда в ярости — фаза %d. %s" % [phase, what], Color(1.0, 0.5, 0.3))


func roar(loud: bool = true) -> void:
	Sfx.play3d(_head if _head else self, Sfx.ANACONDA_ROAR, 3.0 if loud else -1.0, 90.0, _rng.randf_range(0.85, 1.0) if loud else 1.25)


func _die() -> void:
	_enter(S.DEAD)
	_cleanup_fx()
	roar(false)
	GameState.reward_kill(true, "Анаконда")
	if GameState.has_method("on_anaconda_killed"): GameState.on_anaconda_killed()
	if not GameState.dev_mode:
		GameState.add_item_count("reagent3", REWARD_R3)
		GameState.add_item_count("reagent2", REWARD_R2)
		GameState.add_item_count("dust", maxi(0, REWARD_DUST - GameState.DUST_PER_ANACONDA_KILL))
	var scales := randi_range(14,22)
	set_meta("last_scale_drop",scales)
	GameState.add_mined_block("anaconda_scale",scales)
	GameState.add_mined_block("anaconda_egg", 1)
	GameState.chat("Анаконда повержена! Сердце света твоё. Награда: %d осыпи, %d реагент3, %d реагент2, Яйцо Анаконды, %d чешуи." % [REWARD_DUST, REWARD_R3, REWARD_R2,scales], Color(0.6, 1.0, 0.6))
	for m in get_tree().get_nodes_in_group("anaconda_minion"):
		if is_instance_valid(m) and m.has_method("crumble"):
			m.crumble()
	GameState.set_boss_alive(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 1.4)
	tw.tween_callback(queue_free)


func leave(msg: String = "") -> void:
	if state == S.DEAD or state == S.LEAVING:
		return
	leave_reason = msg
	_enter(S.LEAVING)
	_cleanup_fx()
	if msg != "":
		GameState.chat(msg, Color(1.0, 0.75, 0.5))
	for m in get_tree().get_nodes_in_group("anaconda_minion"):
		if is_instance_valid(m) and m.has_method("crumble"):
			m.crumble()
	GameState.set_boss_alive(false)
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + Vector3(0, -6, 0), 1.2)
	tw.tween_callback(queue_free)


func _exit_tree() -> void:
	_cleanup_fx()
	if GameState and state != S.DEAD and state != S.LEAVING:
		state = S.LEAVING
		GameState.set_boss_alive(false)


func _cleanup_fx() -> void:
	_free_crack()
	_free_coil_disc()
	for r in _rocks:
		_free_node(r["shadow"])
	_rocks.clear()


# ---------------------------------------------------------------- тело

func _move_head(to: Vector3, delta: float, speed: float) -> void:
	var cur := _head.global_position
	var d := to - cur
	speed = preload("res://scripts/enemy_navigation.gd").movement_speed(self,speed) * combat.speed_scale()
	var step := speed * delta
	var nxt := to if d.length() <= step else cur + d.normalized() * step
	if (nxt - cur).length() > 0.001:
		var look := nxt - cur
		if Vector2(look.x, look.z).length() > 0.02 or absf(look.y) > 0.02:
			var up := Vector3.UP if absf(look.normalized().y) < 0.95 else Vector3.FORWARD
			_head.global_transform = Transform3D(Basis.looking_at(look.normalized(), up), nxt)
		else:
			_head.global_position = nxt
	if _trail.is_empty() or _trail[0].distance_to(nxt) >= 0.12:
		_trail.push_front(nxt)
		if _trail.size() > SEGMENTS * 14:
			_trail.pop_back()


func _update_body() -> void:
	## Сегменты идут по следу головы на равных дистанциях.
	var acc := 0.0
	var idx := 0
	for i in range(_segs.size()):
		var want := SPACING * float(i + 1)
		while idx + 1 < _trail.size() and acc + _trail[idx].distance_to(_trail[idx + 1]) < want:
			acc += _trail[idx].distance_to(_trail[idx + 1])
			idx += 1
		var p: Vector3 = _trail[mini(idx, _trail.size() - 1)]
		if idx + 1 < _trail.size():
			var seg_len := _trail[idx].distance_to(_trail[idx + 1])
			if seg_len > 0.0001:
				p = _trail[idx].lerp(_trail[idx + 1], clampf((want - acc) / seg_len, 0.0, 1.0))
		_segs[i].global_position = p


func segment_positions() -> Array:
	var out: Array = [_head.global_position]
	for s in _segs:
		out.append(s.global_position)
	return out


# ---------------------------------------------------------------- эффекты

func _world() -> Node:
	return get_parent() if get_parent() != null else get_tree().current_scene


func _make_crack(at: Vector3) -> void:
	_free_crack()
	_crack = _disc(BURST_RADIUS, Color(0.9, 0.55, 0.2, 0.7))
	_crack.position = at + Vector3(0, 0.06, 0)
	_world().add_child(_crack)
	_dust_puff(at + Vector3(0, 0.1, 0))


func _make_hunt_crack(at: Vector3) -> void:
	## Короткая трещина-пыль, указывающая направление охоты. Не держит стан и не тяжёлая по нодам.
	_dust_puff(at)


func _free_coil_disc() -> void:
	_free_node(_coil_disc)
	_coil_disc = null


func _update_seg_light() -> void:
	## Подсветка сегментов, которые видят 2+ факела — читаемый перекрёстный огонь.
	if _head == null:
		return
	var parts: Array = segment_positions()
	for i in range(_segs.size()):
		var n := 0
		var p: Vector3 = _segs[i].global_position
		for z in light_zones():
			if (z["pos"] as Vector3).distance_to(p) <= float(z["r"]):
				n += 1
		var mi := _segs[i] as MeshInstance3D
		if mi:
			mi.transparency = 0.0
			if n >= 2 and is_vulnerable():
				mi.scale = Vector3.ONE * (1.06 if int(_t * 8.0) % 2 == 0 else 1.0)
			elif combat.is_stunned():
				mi.scale = Vector3.ONE * (1.05 if int(_t * 14.0) % 2 == 0 else 1.0)
			else:
				mi.scale = Vector3.ONE


func on_hit_feedback(res: Dictionary) -> void:
	## Оружие не проходит, но подтверждаем отскок визуально.
	if bool(res.get("bounce", false)):
		_flash_body(true)


func _free_crack() -> void:
	_free_node(_crack)
	_crack = null


func _disc(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 24
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _dust_puff(at: Vector3) -> void:
	if not is_inside_tree():
		return
	for i in range(6):
		var b := MeshInstance3D.new()
		b.mesh = BlockTex.cube_mesh("dirt", Vector3(0.18, 0.18, 0.18))
		b.position = at
		_world().add_child(b)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.6, 1.4), _rng.randf_range(-1, 1)).normalized()
		var tw := b.create_tween()
		tw.tween_property(b, "position", at + dir * 1.4, 0.45)
		tw.tween_callback(b.queue_free)


func _free_node(n: Variant) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


func debug_snapshot() -> Dictionary:
	var cc: Dictionary = combat.snapshot()
	return {"state": STATE_NAMES[state], "phase": phase, "hp": hp, "log": attack_log.duplicate(),
		"light_total": light_damage_total, "ignored": weapon_hits_ignored, "minions": alive_minions(),
		"by_source": damage_by_source.duplicate(), "torches_broken": torches_broken,
		"combat": cc, "cc": cc, "minions_spawned": _minions_spawned,
		"stun_active": combat.is_stunned(), "stun_immune": combat.is_stun_immune(),
		"slow": combat.is_slowed(), "exposed": combat.is_exposed()}


# ---------------------------------------------------------------- появление (вызывается из ThreatDirector)

static func try_spawn(host: Node3D, player: Node3D, chunks: Node) -> Node:
	## Ночью у целого гнезда (≤12 м до яйца) или с Яйцом Анаконды в кармане под землёй — Анаконда приходит.
	if host == null or player == null or chunks == null:
		return null
	if not GameState.is_night() or GameState.peaceful or GameState.is_dream():
		return null
	if host.get_tree().get_nodes_in_group("anaconda").size() > 0:
		return null
	# v0.11.1: ограничение «только после Матери» откачено; правило «не два босса сразу» осталось.
	if GameState.boss_alive:
		return null
	if not chunks.has_method("nests_near"):
		return null
	for n in chunks.nests_near(player.global_position, 12.0):
		if bool(n["taken"]):
			continue
		var c: Vector3 = n["center"]
		var night_key := "%s@%d" % [str(n["id"]), GameState.night_index()]
		if GameState.anaconda_seen.has(night_key):
			continue
		GameState.anaconda_seen[night_key] = true
		return spawn_at(host, c + Vector3(0, 0.0, 0), str(n["id"]))
	return null


static func summon_with_egg(host: Node3D, player: Node3D, chunks: Node) -> Node:
	## v0.7: Яйцо Анаконды в руке + ЛКМ (явь, ночь) — призыв. Яйцо тратится. Кулдауна нет:
	## убил — получил новое яйцо — можно призвать снова (в ту же или следующую ночь).
	if host == null or player == null:
		return null
	if GameState.is_dream():
		GameState.set_hint("Яйцо Анаконды молчит во сне — призывать можно только в яви.", false)
		return null
	if GameState.peaceful:
		GameState.set_hint("Мирный мир: Анаконда не приходит.", false)
		return null
	if not GameState.is_night():
		GameState.set_hint("Яйцо холодное. Анаконда откликнется только ночью.", false)
		return null
	if host.get_tree().get_nodes_in_group("anaconda").size() > 0:
		GameState.set_hint("Анаконда уже здесь!", false)
		return null
	if GameState.boss_alive:
		GameState.set_hint("Сначала разберись с Матерью блоков.", false)
		return null
	if GameState.count_item("anaconda_egg") <= 0:
		return null
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var p := player.global_position + fwd * SUMMON_DIST
	if chunks and chunks.has_method("floor_y_below"):
		p.y = float(chunks.floor_y_below(p + Vector3(0, 3.0, 0), 12))
	else:
		p.y = player.global_position.y
	if not GameState.consume_item("anaconda_egg", 1):
		return null
	GameState.chat("Яйцо треснуло — земля дрожит… Анаконда идёт на зов!", Color(1.0, 0.45, 0.3))
	return spawn_at(host, p, "summon")
