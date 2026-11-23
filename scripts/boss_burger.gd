extends CharacterBody3D
## v0.24: финальный босс «Бургер Смерти» (дизайн: /workspace/deepseek/BURGER_OF_DEATH.md, числа пересчитаны
## под 3D и 100 HP игрока). Фаза 1 — летающая тарелка-бургер, фаза 2 — Антон t2x2 в костюме клоуна,
## ярость с 33 %, смерть — 5 клоунов-осколков и 12 с, иначе пересборка с 25 %.
const Sfx := preload("res://scripts/sfx.gd")
const CU := preload("res://scripts/combat_util.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
const BreakFx := preload("res://scripts/break_fx.gd")
const CLOWN := preload("res://scripts/clown_bomb.gd")
const STING := "res://assets/audio/burger_sting.ogg"
const KENNEY := "res://assets/models/kenney_blocky/character-a.glb"

enum S { SPAWN, HOVER, LASER_AIM, LASER_FIRE, SLAM_AIM, SLAM_FALL, SLAM_RECOVER, RAIN, SPAWN_CLOWNS, RECOMPOSE_OUT, RECOMPOSE_IN, STUNNED,
	TRANSITION1, ANTON_IDLE, FIST_WIND, FIST_HIT, FIST_RECOVER, CALL, EAT_WALK, EAT_TELEGRAPH, EAT_RECOVER, JUMP, TRANSITION2, SHARDS, LEAVING, DEAD }

const MAX_HP := 4000            # обе фазы, нормал (Мать 560, Анаконда 2100)
const P2_FRAC := 0.66
const P3_FRAC := 0.33
const HOVER_H := 6.5
const LOW_H := 2.2
const ARENA_R := 18.0
const LEASH_DIST := 46.0
const LEASH_TIME := 10.0
# фаза 1
const LASER_TELE := 0.6
const LASER_DMG := 18
const LASER_FAN := 24.0          # градусы между лучами
const LASER_W := 0.9
const LASER_CD := [4.0, 6.0]
const SLAM_TELE := 0.7
const SLAM_DMG := 25
const SLAM_R := 3.2
const SLAM_CD := 8.0
const SLAM_RECOVER := 1.5
const WAVE_DMG := 10
const RAIN_TELE := 0.5
const RAIN_DMG := 14
const RAIN_N := 9
const RAIN_CD := 10.0
const CLOWN_CD := 12.0
const CLOWN_CAP := 4
const RECOMPOSE_DIST := 16.0
const RECOMPOSE_CD := 15.0
const RECOMPOSE_VULN := 1.2
const WEAK_POINTS := 4
const WEAK_HP := 45
const WEAK_BONUS := 120          # урон боссу за сбитую слабую точку
const WEAK_STUN := 3.0
const WEAK_REGROW := 35.0
const VULN_MULT := 1.5
# фаза 2
const ANTON_SPEED := 3.2
const FIST_TELE := 0.7
const FIST_GAP := 0.4
const FIST_DMG := 28
const FIST_RANGE := 3.4
const FIST_CD := 7.0
const FIST_RECOVER := 1.8
const CALL_TELE := 0.8
const CALL_CD := 14.0
const EAT_TELE := 1.0
const EAT_HEAL := 270
const EAT_CD := 10.0
const EAT_VULN := 1.2
const JUMP_CD := 9.0
const JUMP_DMG := 20
const RAGE_SPEED := 1.3
const RAGE_CD := 0.8
const RAIN2_N := 14
const RAIN2_CD := 8.0
# смерть
const SHARDS := 5
const SHARD_TIME := 12.0
const RECOMPOSE_HP := 0.25

var hp := MAX_HP
var max_hp := MAX_HP
var hit_radius := 2.0
var phase := 1
var state := S.SPAWN
var arena_center := Vector3.ZERO
var frozen := false
var damage_dealt := 0
var attacks_used: Dictionary = {}
var eats_left := 1
var shards_left := 0
var recomposes := 0
var leave_reason := ""
var _t := 0.0
var _cd := {"laser": 2.0, "slam": 4.0, "rain": 6.0, "clowns": 1.0, "recompose": 8.0, "fist": 0.0, "call": 6.0, "eat": 4.0, "jump": 3.0, "rain2": 4.0}
var _leash_t := 0.0
var _target: Node3D = null
var _aim_dirs: Array = []
var _laser_nodes: Array = []
var _slam_point := Vector3.ZERO
var _shadow: MeshInstance3D
var _rain: Array = []          # [{pos, t, hit, node, shadow}]
var _waves: Array = []
var _fist_hits := 0
var _eat_clown: Node3D = null
var _vuln_t := 0.0
var _shard_t := 0.0
var _saucer: Node3D
var _anton: Node3D
var _anton_ap: AnimationPlayer
var _weak: Array = []
var _regrow_t := 0.0
var _rng := RandomNumberGenerator.new()
var _gravity := 22.0
var _arena_ring: MeshInstance3D


static func spawn_at(host: Node3D, near: Vector3) -> Node:
	if host == null or host.get_tree() == null:
		return null
	for o in host.get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(o) and not o.is_queued_for_deletion():
			return null
	var center := near
	for cm in host.get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			cm.call("absorb_trees_near", center, 12.0)
	var b: CharacterBody3D = load("res://scripts/boss_burger.gd").new()
	b.arena_center = center
	b.position = center + Vector3(0, HOVER_H + 14.0, 0)
	host.add_child(b)
	return b


func boss_title() -> String:
	return "Бургер Смерти" if phase == 1 else ("Антон t2x2" if state != S.SHARDS else "Клоуны-осколки")


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	add_to_group("burger_boss")
	collision_layer = 16
	collision_mask = 1
	hp = MAX_HP
	max_hp = MAX_HP
	GameState.apply_enemy_scaling(self, MAX_HP, true)   # Эксперт +75 %, сеть — по числу игроков
	if GameState.is_expert():
		eats_left = 2
	_build_saucer()
	_build_anton()
	_build_arena_ring()
	var col := CollisionShape3D.new()
	var sh := CylinderShape3D.new(); sh.radius = 2.2; sh.height = 1.6
	col.shape = sh
	col.name = "Col"
	add_child(col)
	GameState.set_boss_alive(true)
	GameState.world_changed.connect(_on_world)
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	_on_world(GameState.is_dream())
	Sfx.play3d(self, STING, 4.0, 120.0)
	GameState.chat("Бургер Смерти спускается с неба!", Color(1.0, 0.4, 0.3), true)
	GameState.burger_state_changed.emit("spawn")
	_enter(S.SPAWN)


func _exit_tree() -> void:
	_clear_fx()
	if is_instance_valid(_arena_ring): _arena_ring.queue_free()


func _on_world(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream


func _on_player_died() -> void:
	if CU.players(get_tree()).size() <= 1:
		leave("Бургер Смерти улетел: в его кухне больше некого жарить.")


# ------------------------------------------------------------------ внешний вид
func _mat(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _cyl(r: float, h: float, y: float, c: Color, parent: Node3D, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = h; cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = _mat(c, emit)
	mi.position.y = y
	parent.add_child(mi)
	return mi


func _build_saucer() -> void:
	_saucer = Node3D.new(); _saucer.name = "Saucer"; add_child(_saucer)
	# тарелка-НЛО снизу, бургер сверху
	var rim := _cyl(2.6, 0.25, -0.35, Color(0.62, 0.65, 0.72), _saucer)
	rim.name = "Rim"
	_cyl(1.6, 0.3, -0.62, Color(0.45, 0.48, 0.55), _saucer)
	_cyl(1.9, 0.35, -0.05, Color(0.85, 0.55, 0.25), _saucer)          # нижняя булка
	_cyl(2.0, 0.28, 0.25, Color(0.36, 0.2, 0.12), _saucer)            # котлета
	_cyl(2.08, 0.08, 0.43, Color(1.0, 0.8, 0.2), _saucer)             # сыр
	_cyl(2.15, 0.1, 0.52, Color(0.4, 0.78, 0.3), _saucer)             # салат
	var top := MeshInstance3D.new()
	var sp := SphereMesh.new(); sp.radius = 1.95; sp.height = 2.0; sp.is_hemisphere = true
	top.mesh = sp; top.material_override = _mat(Color(0.88, 0.58, 0.26)); top.position.y = 0.57
	_saucer.add_child(top)
	for i in range(14):
		var seed := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.16, 0.06, 0.09)
		seed.mesh = bm; seed.material_override = _mat(Color(1, 0.95, 0.8))
		var a := float(i) * 2.4
		var rr := 0.5 + 1.1 * float(i % 4) / 3.0
		seed.position = Vector3(cos(a) * rr, 0.57 + sqrt(maxf(0.0, 1.95 * 1.95 - rr * rr)) * 0.98, sin(a) * rr)
		_saucer.add_child(seed)
	for i in range(8):
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new(); lm.radius = 0.12; lm.height = 0.24
		lamp.mesh = lm; lamp.material_override = _mat(Color(1, 0.3, 0.2) if i % 2 == 0 else Color(1, 0.9, 0.3), 3.0)
		lamp.position = Vector3(cos(TAU * i / 8.0) * 2.55, -0.35, sin(TAU * i / 8.0) * 2.55)
		_saucer.add_child(lamp)
	for i in range(WEAK_POINTS):
		var wp: Node3D = load("res://scripts/weak_point.gd").new()
		wp.boss = self
		wp.max_hp = WEAK_HP
		wp.hp = WEAK_HP
		wp.position = Vector3(cos(TAU * (i + 0.5) / WEAK_POINTS) * 2.3, -0.75, sin(TAU * (i + 0.5) / WEAK_POINTS) * 2.3)
		_saucer.add_child(wp)
		_weak.append(wp)
	_shadow = MeshInstance3D.new()
	var dm := CylinderMesh.new(); dm.top_radius = SLAM_R; dm.bottom_radius = SLAM_R; dm.height = 0.05
	_shadow.mesh = dm
	var shm := _mat(Color(0, 0, 0, 0.45)); shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = shm
	_shadow.visible = false
	_shadow.top_level = true
	add_child(_shadow)


func _build_anton() -> void:
	_anton = Node3D.new(); _anton.name = "Anton"; add_child(_anton)
	var packed: PackedScene = load(KENNEY)
	var m: Node3D = packed.instantiate()
	m.name = "Model"
	_anton.add_child(m)
	m.scale = Vector3.ONE * 2.6
	m.rotation.y = PI
	_anton_ap = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	# клоунский костюм: нос, колпак, жабо, рыжий парик
	var nose := MeshInstance3D.new(); var ns := SphereMesh.new(); ns.radius = 0.22; ns.height = 0.44
	nose.mesh = ns; nose.material_override = _mat(Color(1, 0.08, 0.1), 0.6); nose.position = Vector3(0, 2.05, -0.62)
	_anton.add_child(nose)
	var hat := MeshInstance3D.new(); var hc := CylinderMesh.new(); hc.top_radius = 0.0; hc.bottom_radius = 0.42; hc.height = 1.0
	hat.mesh = hc; hat.material_override = _mat(Color(0.3, 0.5, 1.0)); hat.position = Vector3(0, 3.35, 0)
	_anton.add_child(hat)
	var pom := MeshInstance3D.new(); var ps := SphereMesh.new(); ps.radius = 0.16; ps.height = 0.32
	pom.mesh = ps; pom.material_override = _mat(Color(1, 0.9, 0.2), 0.5); pom.position = Vector3(0, 3.9, 0)
	_anton.add_child(pom)
	for side in [-1.0, 1.0]:
		var wig := MeshInstance3D.new(); var ws := SphereMesh.new(); ws.radius = 0.36; ws.height = 0.6
		wig.mesh = ws; wig.material_override = _mat(Color(1.0, 0.45, 0.1)); wig.position = Vector3(side * 0.62, 2.6, 0.05)
		_anton.add_child(wig)
	var ruff := MeshInstance3D.new(); var rt := TorusMesh.new(); rt.inner_radius = 0.3; rt.outer_radius = 0.62
	ruff.mesh = rt; ruff.material_override = _mat(Color(1, 1, 1)); ruff.position = Vector3(0, 1.55, 0)
	_anton.add_child(ruff)
	var tag := Label3D.new(); tag.text = "Антон t2x2"; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 64; tag.outline_size = 12; tag.modulate = Color(1, 0.85, 0.3); tag.position = Vector3(0, 4.4, 0); tag.no_depth_test = true
	_anton.add_child(tag)
	_anton.visible = false


func _build_arena_ring() -> void:
	_arena_ring = MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = ARENA_R - 0.15; tm.outer_radius = ARENA_R + 0.15; tm.rings = 64; tm.ring_segments = 4
	_arena_ring.mesh = tm
	var m := _mat(Color(1.0, 0.5, 0.2, 0.55), 1.5); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arena_ring.material_override = m
	_arena_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arena_ring.name = "BurgerArena"
	var host := get_parent()
	if host:
		host.call_deferred("add_child", _arena_ring)
		_arena_ring.position = Vector3(arena_center.x, _ground_y(arena_center) + 0.1, arena_center.z)


func _anim(clip: String, speed: float = 1.0) -> void:
	if _anton_ap and _anton_ap.has_animation(clip):
		if _anton_ap.current_animation != clip:
			_anton_ap.play(clip, 0.15, speed)


# ------------------------------------------------------------------ урон
func hit_center() -> Vector3:
	return global_position + (Vector3(0, 2.0, 0) if phase > 1 else Vector3.ZERO)


func is_vulnerable() -> bool:
	return _vuln_t > 0.0 or state in [S.SLAM_RECOVER, S.STUNNED, S.FIST_RECOVER, S.EAT_RECOVER]


func is_invulnerable() -> bool:
	return state in [S.SPAWN, S.RECOMPOSE_OUT, S.TRANSITION1, S.TRANSITION2, S.SHARDS, S.LEAVING, S.DEAD]


func is_dead_v024() -> bool:
	return state == S.DEAD or state == S.SHARDS


func take_arrow(amount: int, _arrow: Node) -> void:
	take_damage(amount)


func take_damage(amount: int) -> void:
	if is_invulnerable() or amount <= 0:
		return
	var dmg := amount
	if is_vulnerable():
		dmg = int(round(float(amount) * VULN_MULT))
	var floor_hp := 0
	if phase == 1:
		floor_hp = int(round(max_hp * P2_FRAC))
	elif phase == 2:
		floor_hp = int(round(max_hp * P3_FRAC))
	var before := hp
	hp = maxi(floor_hp, hp - dmg)
	damage_dealt += before - hp
	_flash()
	if phase == 1 and hp <= floor_hp:
		_start_transition1()
	elif phase == 2 and hp <= floor_hp:
		_start_transition2()
	elif phase == 3 and hp <= 0:
		_start_shards()


func weak_point_destroyed(_wp: Node) -> void:
	Sfx.play("weakpoint", get_tree().root, -4.0)
	attacks_used["weak_point"] = int(attacks_used.get("weak_point", 0)) + 1
	var keep := state
	_vuln_t = 0.0
	take_damage(WEAK_BONUS)
	if phase == 1 and keep != S.TRANSITION1 and state != S.TRANSITION1:
		_clear_fx()
		_enter(S.STUNNED)
	_regrow_t = WEAK_REGROW


func _flash() -> void:
	var tgt: Node3D = _saucer if phase == 1 else _anton
	if tgt == null: return
	var tw := create_tween()
	tw.tween_property(tgt, "scale", Vector3.ONE * 1.06, 0.05)
	tw.tween_property(tgt, "scale", Vector3.ONE * (1.15 if phase == 3 else 1.0), 0.08)


# ------------------------------------------------------------------ логика
func _enter(s: int) -> void:
	state = s
	_t = 0.0


func _cdm() -> float:
	return RAGE_CD if phase == 3 else 1.0


func _speed() -> float:
	return ANTON_SPEED * GameState.diff_speed() * (RAGE_SPEED if phase == 3 else 1.0)


func _ground_y(p: Vector3) -> float:
	for cm in get_tree().get_nodes_in_group("chunk_manager") if is_inside_tree() else []:
		if cm.has_method("walk_height_at") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			return float(cm.call("walk_height_at", int(floor(p.x)), int(floor(p.z))))
	return 0.0


func _physics_process(delta: float) -> void:
	if frozen or state == S.DEAD:
		return
	_t += delta
	_vuln_t = maxf(0.0, _vuln_t - delta)
	for k in _cd.keys():
		_cd[k] = maxf(0.0, float(_cd[k]) - delta)
	_target = CU.nearest_player(get_tree(), global_position)
	_tick_rain(delta)
	_tick_waves(delta)
	_tick_weak(delta)
	if state == S.LEAVING:
		global_position.y += 9.0 * delta
		if _t > 2.5:
			_finish_leave()
		return
	if _target == null:
		return
	if _check_leash(delta):
		return
	if phase == 1 or state == S.TRANSITION1:
		_phase1(delta)
	else:
		_phase2(delta)


func _check_leash(delta: float) -> bool:
	var far := true
	for p in CU.players(get_tree()):
		if Vector2((p as Node3D).global_position.x - arena_center.x, (p as Node3D).global_position.z - arena_center.z).length() < LEASH_DIST * GameState.diff_leash():
			far = false
	_leash_t = _leash_t + delta if far else 0.0
	if _leash_t > LEASH_TIME * GameState.diff_leash():
		leave("Бургер Смерти потерял тебя и улетел. Призывалку придётся делать заново.")
		return true
	return false


func _tp() -> Vector3:
	return _target.global_position if _target else arena_center


func _hover_to(goal: Vector3, delta: float, speed: float = 6.0) -> void:
	var d := goal - global_position
	if d.length() > 0.05:
		global_position += d.normalized() * minf(d.length(), speed * GameState.diff_speed() * delta)
	_saucer.rotation.y += delta * 1.4


func _phase1(delta: float) -> void:
	var p := _tp()
	var gy := _ground_y(p)
	match state:
		S.SPAWN:
			_hover_to(Vector3(arena_center.x, _ground_y(arena_center) + HOVER_H, arena_center.z), delta, 9.0)
			if _t > 2.2:
				_enter(S.HOVER)
		S.HOVER:
			var orbit := p + Vector3(cos(_t * 0.6) * 5.0, 0, sin(_t * 0.6) * 5.0)
			_hover_to(Vector3(orbit.x, gy + HOVER_H, orbit.z), delta)
			if _t > 0.8:
				_choose1()
		S.LASER_AIM:
			_hover_to(global_position, delta)
			_update_laser_aim(false)
			if _t >= LASER_TELE:
				_enter(S.LASER_FIRE)
				Sfx.play3d(self, "res://assets/audio/sfx_laser.ogg", 2.0, 90.0)
				_laser_damage()
				_update_laser_aim(true)
		S.LASER_FIRE:
			if _t > 0.3:
				_clear_lasers()
				_enter(S.HOVER)
		S.SLAM_AIM:
			_hover_to(Vector3(_slam_point.x, _slam_point.y + HOVER_H, _slam_point.z), delta, 10.0)
			_shadow.visible = true
			_shadow.global_position = _slam_point + Vector3(0, 0.05, 0)
			var tele := SLAM_TELE - (0.1 if GameState.is_expert() else 0.0)
			if _t >= tele:
				_enter(S.SLAM_FALL)
		S.SLAM_FALL:
			global_position = global_position.move_toward(_slam_point + Vector3(0, 1.0, 0), 30.0 * delta)
			if global_position.y <= _slam_point.y + 1.05:
				_slam_impact()
				_enter(S.SLAM_RECOVER)
		S.SLAM_RECOVER:
			if _t > SLAM_RECOVER:
				_enter(S.HOVER)
		S.RAIN:
			_hover_to(Vector3(p.x, gy + HOVER_H + 2.0, p.z), delta)
			if _t > 0.4:
				_enter(S.HOVER)
		S.SPAWN_CLOWNS:
			_hover_to(global_position, delta)
			if _t > 0.4:
				_spawn_clowns(2)
				_enter(S.HOVER)
		S.RECOMPOSE_OUT:
			_saucer.scale = Vector3.ONE * maxf(0.05, 1.0 - _t / 0.5)
			if _t > 0.5:
				global_position = Vector3(p.x, gy + LOW_H + 1.0, p.z) + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2))
				_enter(S.RECOMPOSE_IN)
				_vuln_t = RECOMPOSE_VULN
		S.RECOMPOSE_IN:
			_saucer.scale = Vector3.ONE * minf(1.0, 0.05 + _t / 0.3)
			if _t > RECOMPOSE_VULN:
				_saucer.scale = Vector3.ONE
				_enter(S.HOVER)
		S.STUNNED:
			_hover_to(Vector3(global_position.x, gy + LOW_H, global_position.z), delta, 8.0)
			_saucer.rotation.z = sin(_t * 18.0) * 0.12
			if _t > WEAK_STUN:
				_saucer.rotation.z = 0.0
				_enter(S.HOVER)
		S.TRANSITION1:
			_saucer.rotation.z = sin(_t * 30.0) * 0.08 * _t
			if _t > 3.0:
				_drop_anton()


func _choose1() -> void:
	var p := _tp()
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	var cap := CLOWN_CAP + (1 if GameState.is_expert() else 0)
	if _alive_clowns() < 2 and _cd.clowns <= 0.0 and _alive_clowns() < cap:
		_enter(S.SPAWN_CLOWNS)
		_cd.clowns = CLOWN_CD * (0.75 if GameState.is_expert() else 1.0)
		Sfx.play3d(self, STING, 2.0, 90.0)   # pt129u: короткий звук на спавн клоунов
		_used("clowns")
	elif flat < 4.0 and _cd.slam <= 0.0:
		_start_slam(p)
	elif flat > RECOMPOSE_DIST and _cd.recompose <= 0.0:
		_enter(S.RECOMPOSE_OUT)
		_cd.recompose = RECOMPOSE_CD
		_used("recompose")
	elif _cd.rain <= 0.0:
		_start_rain(RAIN_N)
		_cd.rain = RAIN_CD
		_enter(S.RAIN)
	elif _cd.slam <= 0.0 and _rng.randf() < 0.4:
		_start_slam(p)
	elif _cd.laser <= 0.0:
		_start_laser(p)
	else:
		_enter(S.HOVER)


func _used(id: String) -> void:
	attacks_used[id] = int(attacks_used.get(id, 0)) + 1


func _start_slam(p: Vector3) -> void:
	_slam_point = Vector3(p.x, _ground_y(p), p.z)
	_cd.slam = SLAM_CD
	_enter(S.SLAM_AIM)
	_used("slam")


func _slam_impact() -> void:
	_shadow.visible = false
	Sfx.play3d(self, "res://assets/audio/sfx_slam.ogg", 4.0, 90.0)
	BreakFx.puff(get_parent(), _slam_point + Vector3(0, 0.3, 0), Color(0.7, 0.6, 0.45), 26)
	for pl in CU.players(get_tree()):
		var d := Vector2((pl as Node3D).global_position.x - _slam_point.x, (pl as Node3D).global_position.z - _slam_point.z).length()
		if d <= SLAM_R and absf((pl as Node3D).global_position.y - _slam_point.y) < 2.5:
			CU.hurt(pl, SLAM_DMG, "Бургер Смерти: слэм", _slam_point)
			CU.push(pl, Vector3(0, 6, 0))
	_spawn_wave(_slam_point)


func _spawn_wave(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.9; tm.outer_radius = 1.0; tm.rings = 48; tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = _mat(Color(1.0, 0.7, 0.3), 2.0)
	mi.top_level = true
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.3, 0)
	_waves.append({"node": mi, "r": 1.0, "center": at, "hit": {}})


func _tick_waves(delta: float) -> void:
	for w in _waves.duplicate():
		w.r = float(w.r) + 8.0 * delta
		var mi: MeshInstance3D = w.node
		if is_instance_valid(mi):
			mi.scale = Vector3(w.r, 1.0, w.r)
		for pl in CU.players(get_tree()):
			if w.hit.has(pl.get_instance_id()):
				continue
			var c: Vector3 = w.center
			var d := Vector2((pl as Node3D).global_position.x - c.x, (pl as Node3D).global_position.z - c.z).length()
			var on_ground: bool = (pl as CharacterBody3D).is_on_floor() if pl is CharacterBody3D else true
			if absf(d - float(w.r)) < 0.6 and on_ground and absf((pl as Node3D).global_position.y - c.y) < 1.6:
				w.hit[pl.get_instance_id()] = true
				CU.hurt(pl, WAVE_DMG, "Бургер Смерти: ударная волна", c)
		if float(w.r) > 11.0:
			if is_instance_valid(mi): mi.queue_free()
			_waves.erase(w)


func _start_laser(p: Vector3) -> void:
	_cd.laser = _rng.randf_range(LASER_CD[0], LASER_CD[1]) * _cdm()
	_aim_dirs.clear()
	var base := p + Vector3(0, 0.9, 0) - global_position
	for i in [-1, 0, 1]:
		_aim_dirs.append(base.normalized().rotated(Vector3.UP, deg_to_rad(LASER_FAN * float(i))))
	_enter(S.LASER_AIM)
	Sfx.play3d(self, "res://assets/audio/sfx_laser_charge.ogg", 0.0, 80.0)
	_used("laser")


func _update_laser_aim(firing: bool) -> void:
	while _laser_nodes.size() < _aim_dirs.size():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1, 1, 1)
		mi.mesh = bm
		var m := _mat(Color(1, 0.15, 0.1, 0.5), 3.0); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_laser_nodes.append(mi)
	for i in range(_aim_dirs.size()):
		var mi: MeshInstance3D = _laser_nodes[i]
		var dir: Vector3 = _aim_dirs[i]
		var length := 34.0
		var w := (LASER_W if firing else 0.06)
		var from := global_position + Vector3(0, -0.6, 0)
		mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT).scaled(Vector3(w, w, length)), from + dir * length * 0.5)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 0.25, 0.1, 0.85 if firing else 0.45)


func _laser_damage() -> void:
	var from := global_position + Vector3(0, -0.6, 0)
	for pl in CU.players(get_tree()):
		var pp := (pl as Node3D).global_position + Vector3(0, 0.9, 0)
		for d in _aim_dirs:
			var dir: Vector3 = d
			var tt := (pp - from).dot(dir)
			if tt > 0.0 and tt < 34.0 and pp.distance_to(from + dir * tt) < LASER_W * 0.5 + 0.35:
				CU.hurt(pl, LASER_DMG, "Бургер Смерти: лазер", from)
				break


func _clear_lasers() -> void:
	for n in _laser_nodes:
		if is_instance_valid(n): n.queue_free()
	_laser_nodes.clear()


func _start_rain(n: int) -> void:
	## Тени-телеграфы, бургеры падают по очереди; одна тень всегда точно под игроком (pity), каждый бургер бьёт один раз.
	var p := _tp()
	var placed: Array = []
	for i in range(n):
		var pos := p if i == 0 else p + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
		var tries := 0
		while tries < 6 and placed.any(func(q: Vector3) -> bool: return Vector2(q.x - pos.x, q.z - pos.z).length() < 1.6):
			pos = p + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
			tries += 1
		pos.y = _ground_y(pos)
		placed.append(pos)
		var sh := MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = 0.9; cm.bottom_radius = 0.9; cm.height = 0.04
		sh.mesh = cm
		var m := _mat(Color(0, 0, 0, 0.5)); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sh.material_override = m
		sh.top_level = true
		add_child(sh)
		sh.global_position = pos + Vector3(0, 0.06, 0)
		var delay := (RAIN_TELE if phase == 1 else 0.4) + float(i) * 0.12
		_rain.append({"pos": pos, "t": -delay, "shadow": sh, "node": null, "done": false})
	Sfx.play3d(self, "res://assets/audio/sfx_rain_whistle.ogg", 0.0, 80.0)
	_used("rain" if phase == 1 else "rain2")


func _tick_rain(delta: float) -> void:
	for r in _rain.duplicate():
		r.t = float(r.t) + delta
		if float(r.t) >= 0.0 and r.node == null and not r.done:
			var b := MeshInstance3D.new()
			b.mesh = _burger_mesh()
			b.top_level = true
			add_child(b)
			b.global_position = r.pos + Vector3(0, 9, 0)
			r.node = b
		if r.node != null and not r.done:
			var b2: MeshInstance3D = r.node
			b2.global_position.y -= 22.0 * delta
			if b2.global_position.y <= float(r.pos.y) + 0.3:
				r.done = true
				for pl in CU.players(get_tree()):
					var d := Vector2((pl as Node3D).global_position.x - r.pos.x, (pl as Node3D).global_position.z - r.pos.z).length()
					if d < 1.1 and absf((pl as Node3D).global_position.y - float(r.pos.y)) < 2.2:
						CU.hurt(pl, RAIN_DMG, "Бургер Смерти: бургер-дождь", r.pos)
				BreakFx.puff(get_parent(), r.pos + Vector3(0, 0.3, 0), Color(0.85, 0.55, 0.25), 8)
				b2.queue_free()
				if is_instance_valid(r.shadow): (r.shadow as Node).queue_free()
				_rain.erase(r)


static var _bmesh: Mesh = null
func _burger_mesh() -> Mesh:
	if _bmesh: return _bmesh
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	for part in [[0.5, 0.14, 0.0, Color(0.85, 0.55, 0.25)], [0.52, 0.12, 0.13, Color(0.36, 0.2, 0.12)], [0.54, 0.04, 0.21, Color(0.4, 0.78, 0.3)], [0.48, 0.2, 0.33, Color(0.88, 0.58, 0.26)]]:
		var cm := CylinderMesh.new(); cm.top_radius = part[0]; cm.bottom_radius = part[0]; cm.height = part[1]; cm.radial_segments = 12
		var arr := cm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in range(verts.size()): verts[i].y += float(part[2])
		arr[Mesh.ARRAY_VERTEX] = verts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := StandardMaterial3D.new(); m.albedo_color = part[3]
		am.surface_set_material(am.get_surface_count() - 1, m)
	_bmesh = am
	return am


func _alive_clowns() -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("burger_clown"):
		if is_instance_valid(c) and not bool(c.get("dead")) and not bool(c.get("shard")):
			n += 1
	return n


func _spawn_clowns(n: int, shard: bool = false) -> Array:
	var out: Array = []
	for i in range(n):
		var c: CharacterBody3D = CLOWN.new()
		c.shard = shard
		c.boss = self
		var a := _rng.randf() * TAU
		var base := global_position if phase == 1 else global_position
		var pos := base + Vector3(cos(a) * 2.5, 0, sin(a) * 2.5)
		pos.y = _ground_y(pos) + (0.5 if phase > 1 else 0.2)
		if phase == 1:
			pos = global_position + Vector3(cos(a) * 1.5, -1.0, sin(a) * 1.5)
		c.position = pos
		get_parent().add_child(c)
		out.append(c)
	return out


func _tick_weak(delta: float) -> void:
	if phase != 1:
		return
	if _regrow_t > 0.0:
		_regrow_t -= delta
		if _regrow_t <= 0.0:
			for wp in _weak:
				if is_instance_valid(wp) and wp.has_method("regrow"):
					wp.regrow()


func weak_points_alive() -> int:
	var n := 0
	for wp in _weak:
		if is_instance_valid(wp) and int(wp.get("hp")) > 0:
			n += 1
	return n


# ------------------------------------------------------------------ переходы
func _start_transition1() -> void:
	if state == S.TRANSITION1:
		return
	_clear_fx()
	_enter(S.TRANSITION1)
	_used("transition1")
	GameState.chat("Тарелка трескается!", Color(1.0, 0.5, 0.3), true)


func _drop_anton() -> void:
	phase = 2
	GameState.burger_state_changed.emit("phase2")
	Sfx.play3d(self, STING, 4.0, 120.0)   # pt129u: короткий звук — Антон выпадает из бургера
	BreakFx.puff(get_parent(), global_position, Color(0.85, 0.55, 0.25), 40)
	_saucer.visible = false
	for wp in _weak:
		if is_instance_valid(wp): wp.queue_free()
	_weak.clear()
	_anton.visible = true
	var g := _ground_y(global_position)
	global_position = Vector3(global_position.x, g + 0.1, global_position.z)
	velocity = Vector3.ZERO
	var col := get_node_or_null("Col") as CollisionShape3D
	if col:
		var sh := CapsuleShape3D.new(); sh.radius = 0.9; sh.height = 3.6
		col.shape = sh
		col.position = Vector3(0, 1.8, 0)
	hit_radius = 1.0
	collision_mask = 1
	_vuln_t = 2.0
	_enter(S.ANTON_IDLE)
	GameState.chat("Из бургера выпал Антон t2x2 в костюме клоуна!", Color(1.0, 0.6, 0.3), true)


func _start_transition2() -> void:
	if state == S.TRANSITION2:
		return
	_clear_fx()
	_enter(S.TRANSITION2)
	_used("transition2")


func _phase2(delta: float) -> void:
	var p := _tp()
	var flat := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	var dist := flat.length()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = maxf(velocity.y, -1.0)
	var move := Vector3.ZERO
	match state:
		S.ANTON_IDLE:
			if dist > 2.6:
				move = flat.normalized() * _speed()
				_anim("walk", 1.2)
			else:
				_anim("idle")
			_face(flat, delta)
			if _t > 0.5:
				_choose2(dist)
		S.FIST_WIND:
			_face(flat, delta)
			_anim("idle")
			_anton.position.z = 0.25 * sin(_t * 20.0) * 0.2
			if _t >= FIST_TELE:
				_fist_hit()
				_fist_hits = 1
				_enter(S.FIST_HIT)
		S.FIST_HIT:
			if _t >= FIST_GAP and _fist_hits == 1:
				_face(flat, delta * 3.0)
				_fist_hit()
				_fist_hits = 2
			if _t >= FIST_GAP + 0.2:
				_enter(S.FIST_RECOVER)
		S.FIST_RECOVER:
			_anim("idle")
			if _t > FIST_RECOVER - (0.3 if phase == 3 else 0.0):
				_enter(S.ANTON_IDLE)
		S.CALL:
			_anim("emote-yes")
			if _t >= CALL_TELE:
				_spawn_clowns(2)
				for c in get_tree().get_nodes_in_group("burger_clown"):
					if is_instance_valid(c) and c.has_method("leap_at"):
						c.leap_at(p)
				_enter(S.ANTON_IDLE)
		S.EAT_WALK:
			if not is_instance_valid(_eat_clown) or bool(_eat_clown.get("dead")):
				_eat_interrupted()
			else:
				var to := _eat_clown.global_position - global_position
				to.y = 0.0
				_face(to, delta)
				if to.length() > 2.2:
					move = to.normalized() * _speed() * 1.3
					_anim("walk", 1.5)
				else:
					_eat_clown.set("held", true)
					_enter(S.EAT_TELEGRAPH)
				if _t > 5.0:
					_eat_interrupted()
		S.EAT_TELEGRAPH:
			_anim("pick-up")
			if not is_instance_valid(_eat_clown) or bool(_eat_clown.get("dead")):
				_eat_interrupted()
			elif _t >= EAT_TELE:
				var heal := int(EAT_HEAL * (1.33 if GameState.is_expert() else 1.0) * float(max_hp) / float(MAX_HP))
				var cap := int(round(max_hp * (P2_FRAC if phase == 2 else P3_FRAC)))
				hp = mini(cap, hp + heal)
				Sfx.play3d(self, "res://assets/audio/sfx_eat.ogg", 2.0, 60.0)
				_eat_clown.call("eaten")
				_used("eat")
				_enter(S.ANTON_IDLE)
		S.EAT_RECOVER:
			_anim("idle")
			if _t > EAT_VULN:
				_enter(S.ANTON_IDLE)
		S.JUMP:
			if _t < 0.05:
				pass
			move = Vector3(velocity.x, 0, velocity.z)
			if _t > 0.25 and is_on_floor():
				_land_jump()
				_enter(S.ANTON_IDLE)
		S.TRANSITION2:
			_anim("idle")
			var k := minf(1.0, _t / 2.5)
			_anton.scale = Vector3.ONE * (1.0 + 0.15 * k)
			if _t > 2.5:
				phase = 3
				GameState.burger_state_changed.emit("rage")
				GameState.chat("Антон t2x2 в ярости!", Color(1.0, 0.35, 0.3), true)
				_vuln_t = 1.5
				_enter(S.ANTON_IDLE)
		S.SHARDS:
			_shard_t -= delta
			var alive := 0
			for c in get_tree().get_nodes_in_group("burger_clown"):
				if is_instance_valid(c) and bool(c.get("shard")) and not bool(c.get("dead")):
					alive += 1
			shards_left = alive
			if alive == 0:
				_die()
				return
			if _shard_t <= 0.0:
				_recompose_from_shards()
				return
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func _face(flat: Vector3, delta: float) -> void:
	if flat.length() < 0.05:
		return
	var want := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 6.0, 0.0, 1.0))


func _choose2(dist: float) -> void:
	var clowns := _alive_clowns()
	if clowns >= 1 and _cd.eat <= 0.0 and eats_left > 0 and hp < int(max_hp * 0.5):
		_eat_clown = _nearest_clown()
		if _eat_clown:
			_cd.eat = EAT_CD * _cdm()
			eats_left -= 1
			_enter(S.EAT_WALK)
			return
	if clowns >= 3 and _cd.call <= 0.0:
		_cd.call = CALL_CD * _cdm()
		_enter(S.CALL)
		Sfx.play3d(self, "res://assets/audio/sfx_clown_honk.ogg", 2.0, 80.0)
		_used("call")
		return
	if dist < FIST_RANGE + 0.6 and _cd.fist <= 0.0:
		_cd.fist = FIST_CD * _cdm()
		_enter(S.FIST_WIND)
		Sfx.play3d(self, STING, 3.0, 90.0)   # pt129u: короткий звук — кулак-комбо Антона
		_used("fist")
		return
	if phase == 3 and _cd.rain2 <= 0.0:
		_cd.rain2 = RAIN2_CD
		_start_rain(RAIN2_N)
		return
	if (dist > 9.0 or _rng.randf() < 0.2) and _cd.jump <= 0.0:
		_cd.jump = JUMP_CD * _cdm()
		_start_jump()
		return
	if clowns < 2 and _cd.call <= 0.0:
		_cd.call = CALL_CD * _cdm()
		_enter(S.CALL)
		Sfx.play3d(self, "res://assets/audio/sfx_clown_honk.ogg", 2.0, 80.0)
		_used("call")


func _nearest_clown() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for c in get_tree().get_nodes_in_group("burger_clown"):
		if is_instance_valid(c) and not bool(c.get("dead")) and not bool(c.get("shard")):
			var d := (c as Node3D).global_position.distance_to(global_position)
			if d < bd:
				bd = d; best = c
	return best


func _eat_interrupted() -> void:
	## Клоуна убили до того, как Антон его съел, — окно уязвимости 1.2 с.
	_eat_clown = null
	_used("eat_interrupted")
	_enter(S.EAT_RECOVER)


func _fist_hit() -> void:
	_anim("attack-melee-right", 1.6)
	if _anton_ap: _anton_ap.seek(0.0, true)
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	for pl in CU.players(get_tree()):
		var to := (pl as Node3D).global_position - global_position
		to.y = 0
		if to.length() <= FIST_RANGE and (to.length() < 1.2 or to.normalized().dot(fwd) > 0.3):
			CU.hurt(pl, FIST_DMG, "Антон t2x2: кулак", global_position)
			CU.push(pl, to.normalized() * 6.0 + Vector3(0, 3, 0))


func _start_jump() -> void:
	var p := _tp()
	var to := p - global_position
	to.y = 0
	var tflight := 1.0
	velocity = to / tflight
	velocity.y = _gravity * tflight * 0.5
	_anim("jump")
	_enter(S.JUMP)
	_used("jump")


func _land_jump() -> void:
	Sfx.play3d(self, "res://assets/audio/sfx_slam.ogg", 2.0, 80.0)
	var at := global_position
	for pl in CU.players(get_tree()):
		var d := (pl as Node3D).global_position.distance_to(at)
		if d < 3.0:
			CU.hurt(pl, JUMP_DMG, "Антон t2x2: прыжок", at)
	_spawn_wave(at)
	velocity.x = 0
	velocity.z = 0


func _start_shards() -> void:
	_clear_fx()
	_enter(S.SHARDS)
	_anton.visible = false
	collision_layer = 0
	_shard_t = SHARD_TIME
	_spawn_clowns(SHARDS, true)
	shards_left = SHARDS
	_used("shards")
	GameState.chat("Антон рассыпался на клоунов! Добей всех за 12 секунд.", Color(1.0, 0.8, 0.3), true)


func _recompose_from_shards() -> void:
	for c in get_tree().get_nodes_in_group("burger_clown"):
		if is_instance_valid(c) and bool(c.get("shard")):
			c.queue_free()
	recomposes += 1
	hp = int(round(max_hp * RECOMPOSE_HP))
	phase = 3
	_anton.visible = true
	collision_layer = 16
	_enter(S.ANTON_IDLE)
	GameState.chat("Клоуны пересобрались — Антон t2x2 снова в бою!", Color(1.0, 0.5, 0.3), true)


func shard_time_left() -> float:
	return _shard_t if state == S.SHARDS else -1.0


func core_window_left() -> float:
	return _shard_t / SHARD_TIME if state == S.SHARDS else -1.0


# ------------------------------------------------------------------ финал
func _clear_fx() -> void:
	_clear_lasers()
	if is_instance_valid(_shadow): _shadow.visible = false
	for w in _waves:
		if is_instance_valid(w.node): (w.node as Node).queue_free()
	_waves.clear()


func _die() -> void:
	_enter(S.DEAD)
	hp = 0
	_clear_fx()
	for r in _rain:
		if is_instance_valid(r.shadow): (r.shadow as Node).queue_free()
		if r.node != null and is_instance_valid(r.node): (r.node as Node).queue_free()
	_rain.clear()
	for c in get_tree().get_nodes_in_group("burger_clown"):
		if is_instance_valid(c): c.queue_free()
	GameState.reward_kill(true, "Бургер Смерти")
	var drops := roll_drops(_rng)
	_spawn_drops(drops)
	if not GameState.dev_mode:
		GameState.add_item_count("reagent3", 5)
		GameState.add_item_count("reagent2", 4)
	GameState.set_boss_alive(false)
	GameState.on_burger_killed(drops)
	Sfx.play("victory", get_tree().root, -4.0)
	if is_instance_valid(_arena_ring): _arena_ring.queue_free()
	queue_free()


static func roll_drops(rng: RandomNumberGenerator) -> Array:
	var out: Array = ["burger_core"]
	if rng.randf() < 0.25: out.append("clown_nose")
	if rng.randf() < 0.20: out.append("grill_saucer")
	if rng.randf() < 0.10: out.append("burger_trophy")
	return out


func _spawn_drops(ids: Array) -> void:
	var bc := get_tree().get_first_node_in_group("build_controller")
	var at := global_position + Vector3(0, 1.0, 0)
	for i in range(ids.size()):
		var rec := GameState.register_drop({"id": ids[i], "name": ItemDB.display_name(ids[i]), "count": 1}, at)
		if bc and bc.has_method("spawn_drop"):
			bc.spawn_drop(rec, Vector3(cos(i * 1.7) * 2.5, 5.0, sin(i * 1.7) * 2.5), 0.5)


func leave(msg: String = "") -> void:
	if state in [S.LEAVING, S.DEAD]:
		return
	leave_reason = msg
	_clear_fx()
	for c in get_tree().get_nodes_in_group("burger_clown"):
		if is_instance_valid(c): c.queue_free()
	_saucer.visible = true
	_anton.visible = false
	_enter(S.LEAVING)
	if msg != "":
		GameState.chat(msg, Color(1.0, 0.75, 0.5), true)


func _finish_leave() -> void:
	_enter(S.DEAD)
	GameState.set_boss_alive(false)
	GameState.burger_state_changed.emit("left")
	if is_instance_valid(_arena_ring): _arena_ring.queue_free()
	queue_free()


const ItemDB := preload("res://scripts/item_db.gd")
