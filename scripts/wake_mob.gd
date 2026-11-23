extends CharacterBody3D
## v0.24: новые мобы Яви с понятным поведением и телеграфом.
##   jumper — «Прыгун»: приседает 0.55 с (сжимается и краснеет), затем прыгает дугой к игроку; удар при приземлении рядом.
##   archer — «Стрелок»: держит дистанцию 7–13 м, натягивает 1.0 с (светится лук), стреляет стрелой по дуге.
##   thief  — «Воришка»: быстро подбегает, крадёт до 4 штук материала из инвентаря и убегает; убьёшь — вернёт украденное.
const _Nav := preload("res://scripts/enemy_navigation.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
const BlockTex := preload("res://scripts/block_tex.gd")
const CU := preload("res://scripts/combat_util.gd")
const MobFx := preload("res://scripts/mob_fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
const KINDS := ["jumper", "archer", "thief"]
const NAMES := {"jumper": "Прыгун", "archer": "Стрелок", "thief": "Воришка"}
const HP_BY := {"jumper": 30, "archer": 22, "thief": 18}
const SPEED_BY := {"jumper": 1.6, "archer": 1.9, "thief": 4.2}
const SEEK := 26.0
const JUMP_TELE := 0.55
const JUMP_CD := 3.2
const JUMP_DMG := 9
const ARCHER_MIN := 7.0
const ARCHER_MAX := 13.0
const DRAW_TIME := 1.0
const SHOT_CD := 2.6
const SHOT_DMG := 7
const STEAL_MAX := 4
const FLEE_TIME := 9.0

var kind := "jumper"
var hp := 30
var max_hp := 30
var hit_radius := 0.45
var dead := false
var frozen := false
var stolen: Dictionary = {}
var state := "idle"
var shots := 0
var jumps := 0
var _t := 0.0
var _cd := 1.5
var _path_cache := {}
var _model: Node3D
var _glow: MeshInstance3D
var _wander := Vector3.ZERO
var _wt := 0.0
var _gravity := 22.0


static func spawn(host: Node, pos: Vector3, k: String) -> Node3D:
	if host == null:
		return null
	var m: CharacterBody3D = load("res://scripts/wake_mob.gd").new()
	m.kind = k if k in KINDS else "jumper"
	m.position = pos
	host.add_child(m)
	return m


static func roll_kind(roll: float, awake_time: float) -> String:
	## Часть обычных спавнов заменяется новыми мобами: прыгун 12 %, стрелок 9 % (с 3-й минуты Яви), воришка 7 %.
	if roll < 0.12: return "jumper"
	if roll < 0.21 and awake_time > 180.0: return "archer"
	if roll < 0.28: return "thief"
	return ""


func display_name() -> String:
	return str(NAMES.get(kind, "Моб"))


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("wake_mob")
	add_to_group("seam_creature")
	_Nav.setup_body(self)
	hp = int(HP_BY[kind]); max_hp = hp
	GameState.apply_enemy_scaling(self, int(HP_BY[kind]))
	_build()
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = Vector3(0.6, 0.9, 0.6)
	col.shape = sh; col.position = Vector3(0, 0.45, 0)
	add_child(col)
	_Vis.attach_hp_bar(self, 1.35)
	_Vis.update_hp_bar(self, hp, max_hp)
	GameState.world_changed.connect(func(d: bool) -> void: frozen = d; visible = not d)
	frozen = GameState.is_dream(); visible = not frozen


func _box(tile: String, size: Vector3, pos: Vector3, tint: Color = Color(1, 1, 1), parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BlockTex.cube_mesh(tile, size, false, tint)
	mi.material_override = BlockTex.material()
	mi.position = pos
	(parent if parent else _model).add_child(mi)
	return mi


func _build() -> void:
	_model = Node3D.new(); _model.name = "Model"; add_child(_model)
	match kind:
		"jumper":
			_box("mossy_ruin", Vector3(0.7, 0.6, 0.7), Vector3(0, 0.35, 0), Color(0.75, 1.0, 0.7))
			_box("leaves", Vector3(0.22, 0.3, 0.22), Vector3(-0.22, 0.12, 0), Color(0.8, 1, 0.8))
			_box("leaves", Vector3(0.22, 0.3, 0.22), Vector3(0.22, 0.12, 0), Color(0.8, 1, 0.8))
		"archer":
			_box("ruin", Vector3(0.45, 0.75, 0.32), Vector3(0, 0.55, 0), Color(0.85, 0.85, 1.0))
			_box("stone", Vector3(0.34, 0.32, 0.32), Vector3(0, 1.1, 0), Color(0.8, 0.8, 0.95))
			var bow := MeshInstance3D.new(); bow.mesh = BlockTex.bow_mesh(false); bow.material_override = BlockTex.material()
			bow.position = Vector3(0.32, 0.65, -0.2); bow.scale = Vector3.ONE * 0.9
			_model.add_child(bow)
		"thief":
			_box("planks", Vector3(0.42, 0.5, 0.3), Vector3(0, 0.4, 0), Color(0.5, 0.4, 0.55))
			_box("dirt", Vector3(0.32, 0.3, 0.3), Vector3(0, 0.82, 0), Color(0.55, 0.45, 0.6))
			_box("chest", Vector3(0.26, 0.26, 0.18), Vector3(0, 0.45, 0.24), Color(0.9, 0.8, 0.6))
	_glow = MeshInstance3D.new()
	var gm := BoxMesh.new(); gm.size = Vector3(0.24, 0.06, 0.02)
	_glow.mesh = gm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(1, 0.4, 0.2); m.emission_enabled = true; m.emission = Color(1, 0.35, 0.1); m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.material_override = m
	_glow.position = Vector3(0, 1.12 if kind == "archer" else (0.85 if kind == "thief" else 0.5), -0.17 if kind != "jumper" else -0.36)
	_model.add_child(_glow)


func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.5, 0)


func is_dead_v024() -> bool:
	return dead


func take_damage(amount: int) -> void:
	if dead or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	_Vis.update_hp_bar(self, hp, max_hp)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	GameState.stat_add("killed_" + kind)
	GameState.reward_kill(false, display_name(), self)
	if not stolen.is_empty():
		var rec := GameState.register_drop(stolen.duplicate(), global_position + Vector3(0, 0.6, 0))
		var bc := get_tree().get_first_node_in_group("build_controller")
		if bc and bc.has_method("spawn_drop"): bc.spawn_drop(rec, Vector3(0, 4, 0), 0.3)
		GameState.set_hint("Воришка выронил украденное: %s ×%d." % [str(stolen.get("name", "")), int(stolen.get("count", 0))], false)
		stolen = {}
	MobFx.death(self, Color(0.6, 0.5, 0.45))
	get_tree().create_timer(1.3).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	if frozen or dead:
		return
	_t += delta
	_cd = maxf(0.0, _cd - delta)
	var p := CU.nearest_player(get_tree(), global_position)
	if p == null:
		return
	var to := p.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var aggro := SEEK * GameState.diff_aggro()
	match kind:
		"jumper": _tick_jumper(delta, p, flat, dist, aggro)
		"archer": _tick_archer(delta, p, flat, dist, aggro)
		"thief": _tick_thief(delta, p, flat, dist, aggro)


func _wander_step(delta: float) -> void:
	_wt -= delta
	if _wt <= 0.0:
		_wt = randf_range(2.5, 4.5)
		_wander = global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	_Nav.follow_target(self, _wander, float(SPEED_BY[kind]) * 0.5, delta, _path_cache)


func _set_glow(on: float) -> void:
	if _glow:
		_glow.scale = Vector3.ONE * (1.0 + on * 1.4)
		(_glow.material_override as StandardMaterial3D).emission_energy_multiplier = 1.0 + on * 5.0


func _tick_jumper(delta: float, p: Node3D, flat: Vector3, dist: float, aggro: float) -> void:
	match state:
		"crouch":
			velocity.x = 0; velocity.z = 0
			if not is_on_floor(): velocity.y -= _gravity * delta
			move_and_slide()
			var k := clampf(_t / JUMP_TELE, 0.0, 1.0)
			_model.scale = Vector3(1.0 + 0.25 * k, 1.0 - 0.4 * k, 1.0 + 0.25 * k)
			_set_glow(k)
			if _t >= JUMP_TELE:
				_model.scale = Vector3.ONE
				_set_glow(0.0)
				var tflight := 0.75
				velocity = flat / tflight
				velocity.y = _gravity * tflight * 0.5 + 1.0
				state = "air"; _t = 0.0; jumps += 1
				Sfx.play3d(self, "res://assets/audio/sfx_mob_jump.ogg", -2.0, 30.0)
				move_and_slide()
		"air":
			velocity.y -= _gravity * delta
			move_and_slide()
			if _t > 0.15 and is_on_floor():
				state = "idle"; _t = 0.0; _cd = JUMP_CD
				velocity = Vector3.ZERO
				GameState.shake(0.15)
				for pl in CU.players(get_tree()):
					if (pl as Node3D).global_position.distance_to(global_position) < 1.8:
						CU.hurt(pl, _Nav.combat_damage(self, JUMP_DMG), "Прыгун", global_position)
		_:
			if dist > aggro:
				_wander_step(delta)
				return
			_Nav.face_point(self, p.global_position, delta, 8.0)
			if dist < 9.0 and _cd <= 0.0 and is_on_floor():
				state = "crouch"; _t = 0.0
				return
			_Nav.follow_target(self, p.global_position, float(SPEED_BY.jumper), delta, _path_cache)


func _tick_archer(delta: float, p: Node3D, flat: Vector3, dist: float, aggro: float) -> void:
	if dist > aggro:
		_set_glow(0.0); state = "idle"
		_wander_step(delta)
		return
	_Nav.face_point(self, p.global_position, delta, 10.0)
	if state == "draw":
		velocity.x = 0; velocity.z = 0
		if not is_on_floor(): velocity.y -= _gravity * delta
		move_and_slide()
		_set_glow(clampf(_t / DRAW_TIME, 0.0, 1.0))
		if _t >= DRAW_TIME:
			_shoot(p)
			state = "idle"; _cd = SHOT_CD; _set_glow(0.0)
		return
	if dist < ARCHER_MIN:
		var away := global_position - flat.normalized() * 4.0
		_Nav.follow_target(self, away, float(SPEED_BY.archer), delta, _path_cache)
	elif dist > ARCHER_MAX:
		_Nav.follow_target(self, p.global_position, float(SPEED_BY.archer), delta, _path_cache)
	else:
		velocity.x = 0; velocity.z = 0
		if not is_on_floor(): velocity.y -= _gravity * delta
		move_and_slide()
	if _cd <= 0.0 and dist <= ARCHER_MAX + 2.0:
		state = "draw"; _t = 0.0


func _shoot(p: Node3D) -> Node3D:
	var from := global_position + Vector3(0, 1.0, 0)
	var target := p.global_position + Vector3(0, 0.9, 0)
	var d := target - from
	var speed := 18.0
	var tt := d.length() / speed
	var v := d / maxf(tt, 0.05)
	v.y += 0.5 * 11.0 * tt   # компенсация гравитации стрелы
	var a: Node3D = load("res://scripts/arrow.gd").new()
	a.setup(v, _Nav.combat_damage(self, SHOT_DMG), "arrow", self)
	a.hostile = true
	get_parent().add_child(a)
	a.global_position = from + d.normalized() * 0.6
	shots += 1
	Sfx.play3d(self, "res://assets/audio/sfx_mob_shoot.ogg", -2.0, 35.0)
	return a


func _tick_thief(delta: float, p: Node3D, flat: Vector3, dist: float, aggro: float) -> void:
	if state == "flee":
		var away := global_position - flat.normalized() * 6.0
		_Nav.follow_target(self, away, float(SPEED_BY.thief) * 1.1, delta, _path_cache)
		if _t > FLEE_TIME and dist > 30.0:
			queue_free()   # сбежал с добычей
		return
	if dist > aggro:
		_wander_step(delta)
		return
	_Nav.follow_target(self, p.global_position, float(SPEED_BY.thief), delta, _path_cache)
	if dist < 1.3 and _cd <= 0.0:
		_cd = 1.0
		if CU.is_local(p) and steal():
			state = "flee"; _t = 0.0
			Sfx.play3d(self, "res://assets/audio/sfx_mob_steal.ogg", 0.0, 30.0)
		else:
			CU.hurt(p, _Nav.combat_damage(self, 4), "Воришка", global_position)


func steal() -> bool:
	## Крадёт материал (не инструмент, не броню, не еду) — до 4 штук из самой большой стопки.
	if GameState.dev_mode:
		return false
	var best := -1; var best_n := 0
	for i in range(GameState.ITEM_SLOT_COUNT):
		var d: Dictionary = GameState.get_slot(i)
		var id := str(d.get("id", ""))
		if id == "" or d.has("durability") or GameState.tool_max(id) > 0 or GameState.ArmorRules.slot(id) >= 0:
			continue
		if id in ["heal1", "heal2", "speed_potion", "burger_summoner", "torch"]:
			continue
		if int(d.get("count", 0)) > best_n:
			best = i; best_n = int(d.get("count", 0))
	if best < 0:
		return false
	stolen = GameState.take_from_slot(best, mini(STEAL_MAX, best_n))
	if stolen.is_empty():
		return false
	GameState.set_hint("Воришка утащил %s ×%d — догони его!" % [str(stolen.get("name", stolen.get("id", ""))), int(stolen.get("count", 0))], false)
	return true
