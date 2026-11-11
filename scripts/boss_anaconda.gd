extends Node3D
## v0.7: босс «Анаконда» — подземный сегментный червь. Живёт в гнёздах (пещеры и закрытые купола).
## Выходит ТОЛЬКО ночью, на рассвете уходит в глубину. Оружие её не берёт (чешуя) — урон наносит
## только СВЕТ: поставленные факелы (зона r=3.5 м) и факел в руке (r=2.5 м). Контрплей — заманить
## под свет: вынырнув в освещённой точке, она слепнет (оглушение, урон ×2).
## Дизайн и баланс — docs/boss_anaconda.md.

const BlockTex := preload("res://scripts/block_tex.gd")
const Sfx := preload("res://scripts/sfx.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")

enum S { SPAWN, UNDER, TELEGRAPH, BURST, REST, STUNNED, DIVE, CAVEIN, COIL, CONSTRICT, TRANSITION, LEAVING, DEAD }
const STATE_NAMES := ["SPAWN", "UNDER", "TELEGRAPH", "BURST", "REST", "STUNNED", "DIVE", "CAVEIN", "COIL", "CONSTRICT", "TRANSITION", "LEAVING", "DEAD"]

# ---- баланс (см. дизайн-док, раздел 3)
const MAX_HP := 2850                   # TTK ≈ 210 с при 3 факелах (tools/anaconda_sim.gd)
const P2_AT := MAX_HP * 66 / 100       # 66%
const P3_AT := MAX_HP * 33 / 100       # 33%
const SEGMENTS := 10
const SPACING := 0.95
const HEAD_SIZE := 1.3
const UNDER_DEPTH := 2.6               # голова под полом во время подкопа
const UNDER_SPEED := [7.0, 8.0, 9.0]
const TELEGRAPH := [1.0, 0.85, 0.7]    # трещины на полу перед выныриванием (≥0.6 с)
const BURST_TIME := 0.35
const BURST_HEIGHT := 3.4
const BURST_RADIUS := 1.8
const BURST_DAMAGE := 30               # 30% HP игрока
const REST_TIME := [1.4, 1.2, 1.0]
const STUN_TIME := [2.6, 2.3, 2.0]
const DIVE_TIME := 0.6
const CONTACT_DAMAGE := 5              # голова на поверхности, вплотную (≤5%)
const CONTACT_CD := 1.0
const CAVEIN_EVERY := 2                # фаза 2+: каждый 2-й нырок — обвал
const CAVEIN_WINDUP := 1.0             # тени камней
const CAVEIN_ROCKS := 6
const ROCK_DAMAGE := 14
const ROCK_RADIUS := 0.9
const COIL_EVERY := 3                  # фаза 3: каждый 3-й нырок — кольцо
const COIL_RADIUS := 5.0
const COIL_TIME := 3.0
const CONSTRICT_WINDUP := 1.2
const CONSTRICT_DAMAGE := 25
const CONSTRICT_INNER := 4.2
const COIL_CONTACT := 8
const TRANSITION_TIME := 2.0
# ---- свет
const TORCH_RADIUS := 3.5
const HELD_TORCH_RADIUS := 2.5
const HEAD_LIGHT_DPS := 6.0            # за каждую зону света (макс. 2 зоны)
const BODY_LIGHT_DPS := 1.5            # за сегмент в свете (макс. 4 сегмента)
const STUN_MULT := 2.0
# ---- миньоны (землеройки)
const MINION_SPAWN := 2
const MINION_CAP := 4
const MINION_PITY := 3                 # 3 нырка без миньонов → гарантированно 1
# ---- поведение
const LEASH_DIST := 42.0
const LEASH_TIME := 8.0
const REWARD_DUST := 300
const REWARD_R3 := 4
const REWARD_R2 := 3
const SUMMON_DIST := 6.0              # призыв яйцом: в 6 м перед игроком

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var phase: int = 1
var state: int = S.SPAWN
var nest_id: String = ""
var home: Vector3 = Vector3.ZERO
var frozen: bool = false
var attack_log := {"burst": 0, "burst_hit": 0, "stun": 0, "rest": 0, "cavein": 0, "rock_hit": 0, "coil": 0, "constrict_hit": 0, "coil_broken": 0, "transition": 0, "minions": 0}
var state_log: Array = []
var light_damage_total: float = 0.0
var weapon_hits_ignored: int = 0
var leave_reason: String = ""
var hit_radius: float = 0.8

var _t: float = 0.0
var _head: Node3D
var _segs: Array[Node3D] = []
var _trail: Array[Vector3] = []
var _target: Vector3 = Vector3.ZERO
var _emerge: Vector3 = Vector3.ZERO
var _crack: MeshInstance3D = null
var _rocks: Array = []                 # [{shadow, at, t}]
var _dives: int = 0
var _no_minion_dives: int = 0
var _pending_transition: int = 0
var _dmg_acc: float = 0.0
var _contact_cd: float = 0.0
var _rumble_cd: float = 0.0
var _leash_t: float = 0.0
var _coil_center: Vector3 = Vector3.ZERO
var _coil_ang: float = 0.0
var _coil_hit_cd: float = 0.0
var _torches: Array[Vector3] = []
var _torch_scan: float = 0.0
var torch_break_cd := 0.0
var torches_broken := 0
var _torch_contacts: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _floor_y: float = 0.0
var _stun_len: float = 0.0


static func spawn_at(host: Node3D, pos: Vector3, nid: String) -> Node:
	if host == null or host.get_tree() == null:
		return null
	if host.get_tree().get_nodes_in_group("anaconda").size() > 0:
		return null
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
	if state == S.STUNNED:
		return "   — ОСЛЕПЛЕНА СВЕТОМ!"
	if is_invulnerable():
		return "   — в земле"
	return "   — бей СВЕТОМ (факелы)"


func _ready() -> void:
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
	GameState.set_boss_alive(true)
	if GameState.has_signal("world_changed"):
		GameState.world_changed.connect(_on_world)
	_on_world(GameState.is_dream())
	_enter(S.SPAWN)
	roar()
	GameState.chat("Из гнезда поднимается Анаконда! Сталь её не берёт — ставь факелы и заманивай под свет.", Color(1.0, 0.5, 0.3))


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
	return state in [S.SPAWN, S.UNDER, S.TELEGRAPH, S.TRANSITION, S.LEAVING, S.DEAD, S.DIVE]


func is_vulnerable() -> bool:
	return state == S.STUNNED


func take_damage(_amount: int) -> void:
	## Меч и кирка не пробивают чешую — только свет.
	weapon_hits_ignored += 1
	if weapon_hits_ignored == 1 or weapon_hits_ignored % 8 == 0:
		GameState.set_hint("Клинок соскальзывает с чешуи — Анаконду жжёт только свет факелов!", weapon_hits_ignored == 1)


func apply_light_damage(amount: float) -> int:
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
	light_damage_total += float(before - hp)
	_Vis.update_hp_bar(_head, hp, max_hp)
	if phase == 1 and hp <= P2_AT:
		_pending_transition = 2
	elif phase == 2 and hp <= P3_AT:
		_pending_transition = 3
	if hp <= 0:
		_die()
	return before - hp


func light_zones() -> Array:
	## [{pos, r, held}] — поставленные факелы + факел в руке игрока.
	var out: Array = []
	for t in _torches:
		out.append({"pos": t, "r": TORCH_RADIUS, "held": false})
	var p := _player()
	if p and GameState.selected_is("torch") and not GameState.is_dream():
		out.append({"pos": p.global_position + Vector3(0, 1.2, 0), "r": HELD_TORCH_RADIUS, "held": true})
	return out


func is_point_lit(pt: Vector3) -> bool:
	for z in light_zones():
		if (z["pos"] as Vector3).distance_to(pt) <= float(z["r"]):
			return true
	return false


func light_dps() -> float:
	## Текущий урон светом в секунду (голова — до 2 зон, тело — до 4 сегментов).
	if is_invulnerable():
		return 0.0
	var zones := light_zones()
	var head_z := 0
	var hp_pos := _head.global_position
	for z in zones:
		if (z["pos"] as Vector3).distance_to(hp_pos) <= float(z["r"]) + 0.4:
			head_z += 1
	var body := 0
	for s in _segs:
		if body >= 4:
			break
		for z2 in zones:
			if (z2["pos"] as Vector3).distance_to(s.global_position) <= float(z2["r"]):
				body += 1
				break
	var dps := HEAD_LIGHT_DPS * float(mini(head_z, 2)) + BODY_LIGHT_DPS * float(body)
	if state == S.STUNNED:
		dps *= STUN_MULT
	return dps


func _scan_torches() -> void:
	_torches.clear()
	for c in GameState.wake_blocks.keys():
		if str((GameState.wake_blocks[c] as Dictionary).get("kind", "")) == "torch":
			var cell: Vector3i = c
			var wp := Vector3(float(cell.x) + 0.5, float(cell.y) + 0.6, float(cell.z) + 0.5)
			if wp.distance_to(global_position) < 60.0:
				_torches.append(wp)


# ---------------------------------------------------------------- машина состояний

func _enter(s: int) -> void:
	state = s
	_t = 0.0
	state_log.append([STATE_NAMES[s], phase, hp])
	if state_log.size() > 400:
		state_log.remove_at(0)


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
	torch_break_cd = maxf(0.0, torch_break_cd - delta)
	_check_torch_collision()
	if frozen or state == S.DEAD or state == S.LEAVING:
		return
	_t += delta
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_coil_hit_cd = maxf(0.0, _coil_hit_cd - delta)
	_torch_scan -= delta
	if _torch_scan <= 0.0:
		_torch_scan = 0.5
		_scan_torches()
	# Рассвет — уходит.
	if not GameState.is_night():
		leave("Светает — Анаконда уходит в глубину.")
		return
	var player := _player()
	if player == null:
		return
	# Поводок: игрок убежал от гнезда.
	if player.global_position.distance_to(home) > LEASH_DIST:
		_leash_t += delta
		if _leash_t > LEASH_TIME:
			leave("Анаконда потеряла тебя и вернулась в гнездо.")
			return
	else:
		_leash_t = 0.0
	var dps := light_dps()
	if dps > 0.0:
		apply_light_damage(dps * delta)
		if state == S.DEAD:
			return
	_tick_rocks(delta, player)
	match state:
		S.SPAWN:
			_move_head(home + Vector3(0, 1.6 * minf(1.0, _t / 1.6), 0), delta, 4.0)
			if _t >= 2.0:
				_go_under()
		S.UNDER:
			_tick_under(delta, player)
		S.TELEGRAPH:
			_move_head(_emerge + Vector3(0, -UNDER_DEPTH, 0), delta, 10.0)
			if _crack:
				var k := 1.0 + 0.15 * sin(_t * 30.0)
				_crack.scale = Vector3(k, 1, k)
			if _t >= float(TELEGRAPH[phase - 1]):
				_start_burst(player)
		S.BURST:
			var f := minf(1.0, _t / BURST_TIME)
			_move_head(_emerge + Vector3(0, -UNDER_DEPTH + (UNDER_DEPTH + BURST_HEIGHT) * f, 0), delta, 40.0)
			if _t >= BURST_TIME:
				_after_burst()
		S.REST, S.STUNNED:
			var lie := _emerge + Vector3(0, HEAD_SIZE * 0.45, 0) + _rest_dir() * 1.6
			_move_head(lie, delta, 6.0)
			_contact(player)
			var len := _stun_len if state == S.STUNNED else float(REST_TIME[phase - 1])
			if _pending_transition > 0:
				_start_transition()
			elif _t >= len:
				_start_dive()
		S.DIVE:
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


func _tick_under(delta: float, player: CharacterBody3D) -> void:
	var pf := _floor_at(player.global_position)
	_target = Vector3(player.global_position.x, pf, player.global_position.z)
	var under_t := _target + Vector3(0, -UNDER_DEPTH, 0)
	_move_head(under_t, delta, float(UNDER_SPEED[phase - 1]))
	_rumble_cd -= delta
	if _rumble_cd <= 0.0:
		_rumble_cd = 1.6
		Sfx.play3d(_head, Sfx.ANACONDA_RUMBLE, -4.0, 40.0)
		_dust_puff(Vector3(_head.global_position.x, _floor_at(_head.global_position) + 0.1, _head.global_position.z))
	var flat := Vector2(_head.global_position.x - under_t.x, _head.global_position.z - under_t.z).length()
	if flat < 1.2 or _t > 6.0:
		_emerge = _target
		_floor_y = _target.y
		_enter(S.TELEGRAPH)
		_make_crack(_emerge)


func _start_burst(player: CharacterBody3D) -> void:
	_enter(S.BURST)
	attack_log["burst"] += 1
	_free_crack()
	_dust_puff(_emerge + Vector3(0, 0.2, 0))
	var to := player.global_position - _emerge
	if Vector2(to.x, to.z).length() <= BURST_RADIUS and to.y > -1.0 and to.y < 2.5:
		if GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,BURST_DAMAGE), "Анаконда: укус из-под земли") > 0:
			attack_log["burst_hit"] += 1
			player.velocity += Vector3(to.x, 0, to.z).normalized() * 7.0 + Vector3(0, 4.0, 0)


func _after_burst() -> void:
	if is_point_lit(_emerge + Vector3(0, 1.0, 0)):
		attack_log["stun"] += 1
		_stun_len = float(STUN_TIME[phase - 1])
		_enter(S.STUNNED)
		roar(false)
		GameState.set_hint("Анаконда ослеплена светом! Урон ×2", false)
	else:
		attack_log["rest"] += 1
		_enter(S.REST)


func _rest_dir() -> Vector3:
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
	if phase >= 2 and _dives % CAVEIN_EVERY == 0:
		_start_cavein(player)
		return
	_no_minion_dives += 1
	if phase >= 2 and _no_minion_dives >= MINION_PITY:
		_spawn_minions(1)
	_go_under()


func _contact(player: CharacterBody3D) -> void:
	if _contact_cd > 0.0:
		return
	if player.global_position.distance_to(_head.global_position) < HEAD_SIZE * 0.5 + 0.6:
		_contact_cd = CONTACT_CD
		GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,CONTACT_DAMAGE), "Анаконда: касание")


# ---------------------------------------------------------------- фаза 2: обвал + землеройки

func _start_cavein(player: CharacterBody3D) -> void:
	_enter(S.CAVEIN)
	attack_log["cavein"] += 1
	roar(true)
	GameState.set_hint("Обвал! Уходи с теней камней.", false)
	var center := player.global_position
	for i in range(CAVEIN_ROCKS):
		var p: Vector3
		if i == 0:
			p = center
		else:
			var a := _rng.randf() * TAU
			var r := 1.6 + _rng.randf() * 3.8
			p = center + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _floor_at(p)
		var sh := _disc(ROCK_RADIUS, Color(0.15, 0.1, 0.05, 0.75))
		sh.position = p + Vector3(0, 0.05, 0)
		_world().add_child(sh)
		_rocks.append({"shadow": sh, "at": p, "t": CAVEIN_WINDUP + 0.08 * float(i)})
	_spawn_minions(MINION_SPAWN)


func _tick_rocks(delta: float, player: CharacterBody3D) -> void:
	var keep: Array = []
	for r in _rocks:
		r["t"] = float(r["t"]) - delta
		if float(r["t"]) > 0.0:
			var sh: MeshInstance3D = r["shadow"]
			if is_instance_valid(sh):
				var k := 1.0 + 0.4 * (1.0 - clampf(float(r["t"]) / CAVEIN_WINDUP, 0.0, 1.0))
				sh.scale = Vector3(k, 1, k)
			keep.append(r)
			continue
		var at: Vector3 = r["at"]
		_free_node(r["shadow"])
		_dust_puff(at + Vector3(0, 0.3, 0))
		var d := player.global_position - at
		if Vector2(d.x, d.z).length() <= ROCK_RADIUS + 0.35 and d.y > -0.6 and d.y < 2.0:
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
	var room := MINION_CAP - alive_minions()
	var n := mini(count, room)
	if n <= 0:
		return 0
	_no_minion_dives = 0
	var script: GDScript = load("res://scripts/anaconda_worm.gd")
	for i in range(n):
		var w: Node3D = script.new()
		var a := _rng.randf() * TAU
		var p := _head.global_position + Vector3(cos(a) * 2.5, 0, sin(a) * 2.5)
		p.y = _floor_at(p)
		w.position = p
		_world().add_child(w)
	attack_log["minions"] += n
	return n


# ---------------------------------------------------------------- фаза 3: кольцо

func _start_coil(player: CharacterBody3D) -> void:
	_enter(S.COIL)
	attack_log["coil"] += 1
	roar(true)
	_coil_center = player.global_position
	_coil_center.y = _floor_at(_coil_center)
	var d := _head.global_position - _coil_center
	_coil_ang = atan2(d.z, d.x)
	GameState.set_hint("Анаконда сворачивается кольцом! Выпрыгни через тело или встань под факел.", false)


func _coil_point(ang: float) -> Vector3:
	return _coil_center + Vector3(cos(ang) * COIL_RADIUS, 0.6, sin(ang) * COIL_RADIUS)


func _tick_coil_body(delta: float) -> void:
	_coil_ang += TAU / COIL_TIME * delta * 0.35
	_move_head(_coil_point(_coil_ang), delta, 30.0)


func _tick_coil(delta: float, player: CharacterBody3D) -> void:
	_coil_ang += TAU / COIL_TIME * delta
	_move_head(_coil_point(_coil_ang), delta, 30.0)
	# Тело кольца — стена: касание сегмента бьёт (контрплей — не стоять у тела).
	if _coil_hit_cd <= 0.0:
		for s in _segs:
			if s.global_position.distance_to(player.global_position + Vector3(0, 0.6, 0)) < 0.9:
				_coil_hit_cd = 1.0
				GameState.damage_player(preload("res://scripts/enemy_navigation.gd").combat_damage(self,COIL_CONTACT), "Анаконда: чешуя кольца")
				break
	# Свет внутри кольца — кольцо рвётся, она слепнет.
	for z in light_zones():
		var zp: Vector3 = z["pos"]
		if Vector2(zp.x - _coil_center.x, zp.z - _coil_center.z).length() <= COIL_RADIUS + 0.5 and _t > 0.6:
			attack_log["coil_broken"] += 1
			_emerge = _head.global_position
			_emerge.y = _floor_at(_emerge)
			_stun_len = float(STUN_TIME[phase - 1]) + 1.0
			_enter(S.STUNNED)
			roar(false)
			GameState.set_hint("Свет разорвал кольцо — Анаконда ослеплена!", false)
			return
	if _t >= COIL_TIME:
		_enter(S.CONSTRICT)


func _resolve_constrict(player: CharacterBody3D) -> void:
	var d := player.global_position - _coil_center
	var inside := Vector2(d.x, d.z).length() < CONSTRICT_INNER and d.y < 1.6
	if inside and not is_point_lit(player.global_position + Vector3(0, 1.0, 0)):
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
	attack_log["transition"] += 1
	_enter(S.TRANSITION)
	roar(true)
	Sfx.play3d(_head, Sfx.ANACONDA_RUMBLE, 0.0, 60.0)
	var what := "Обвалы и землеройки!" if phase == 2 else "Удушающее кольцо — держи факел рядом!"
	GameState.chat("Анаконда в ярости — фаза %d. %s" % [phase, what], Color(1.0, 0.5, 0.3))


func roar(loud: bool = true) -> void:
	Sfx.play3d(_head if _head else self, Sfx.ANACONDA_ROAR, 3.0 if loud else -1.0, 90.0, _rng.randf_range(0.85, 1.0) if loud else 1.25)


func _die() -> void:
	_enter(S.DEAD)
	_cleanup_fx()
	roar(false)
	GameState.reward_kill(true, "Анаконда")
	if not GameState.dev_mode:
		GameState.add_item_count("reagent3", REWARD_R3)
		GameState.add_item_count("reagent2", REWARD_R2)
		GameState.add_item_count("dust", REWARD_DUST - GameState.DUST_PER_BOSS_KILL)
	var scales := randi_range(6,22)
	set_meta("last_scale_drop",scales)
	GameState.add_mined_block("anaconda_scale",scales)
	GameState.add_mined_block("anaconda_egg", 1)
	GameState.chat("Анаконда повержена! Награда: %d осыпи, %d реагент3, %d реагент2 и Яйцо Анаконды, %d чешуи." % [REWARD_DUST, REWARD_R3, REWARD_R2,scales], Color(0.6, 1.0, 0.6))
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
	for r in _rocks:
		_free_node(r["shadow"])
	_rocks.clear()


# ---------------------------------------------------------------- тело

func _move_head(to: Vector3, delta: float, speed: float) -> void:
	var cur := _head.global_position
	var d := to - cur
	speed = preload("res://scripts/enemy_navigation.gd").movement_speed(self,speed)
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
	return {"state": STATE_NAMES[state], "phase": phase, "hp": hp, "log": attack_log.duplicate(),
		"light_total": light_damage_total, "ignored": weapon_hits_ignored, "minions": alive_minions()}


# ---------------------------------------------------------------- появление (вызывается из ThreatDirector)

static func try_spawn(host: Node3D, player: Node3D, chunks: Node) -> Node:
	## Ночью у целого гнезда (≤12 м до яйца) или с Яйцом Анаконды в кармане под землёй — Анаконда приходит.
	if host == null or player == null or chunks == null:
		return null
	if not GameState.is_night() or GameState.peaceful or GameState.is_dream():
		return null
	if host.get_tree().get_nodes_in_group("anaconda").size() > 0:
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


func _check_torch_collision() -> void:
	if _head == null or state in [S.DEAD, S.LEAVING] or GameState.is_dream():
		return
	var contacts: Dictionary = {}
	for c in GameState.wake_blocks.keys():
		if GameState.wake_blocks[c].get("kind", "") != "torch":
			continue
		var pos := Vector3(c) + Vector3(0.5, 0.65, 0.5)
		if _head.global_position.distance_to(pos) > HEAD_SIZE * 0.5 + 0.15:
			continue
		contacts[c] = true
		if not _torch_contacts.has(c) and try_break_torch(c):
			break
	_torch_contacts = contacts

func try_break_torch(c: Vector3i, roll: float = -1.0) -> bool:
	if torch_break_cd > 0.0 or GameState.wake_blocks.get(c, {}).get("kind", "") != "torch":
		return false
	if (randf() if roll < 0.0 else roll) >= 1.0 / 3.0:
		return false
	torch_break_cd = 5.0
	torches_broken += 1
	GameState.wake_blocks.erase(c)
	for v in get_tree().get_nodes_in_group("voxel_world"):
		if not v.is_dream_layer:
			v.remove_block(c)
	_scan_torches()
	GameState.chat("Анаконда сломала факел!", Color(1,0.7,0.3))
	return true
