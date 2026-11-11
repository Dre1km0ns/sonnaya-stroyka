extends CharacterBody3D
## v0.6: «Блоклинг» — дитя Матери блоков. Маленький прыгучий куб: HP 20 (2 удара мечом),
## прыжки к игроку 3.5 м/с, укус 5 урона (КД 1.2 с), живёт 30 с, затем рассыпается.
## v0.11.1 режимы:
##   "minion"     — боевой выводок Матери (как раньше).
##   "blockolith" — Блоколит: нейтральный бродяга Яви (после первой победы над Матерью заменяет 1/120 обычных спавнов).
##                  Не атакует, не исчезает по таймеру; его убийство вызывает Мать блоков.
##   "carrier"    — Носильщик (фаза II Матери): бежит к осколку, несёт его к Матери; доставка чинит одну пластину.
##                  Убийство носильщика отменяет починку.
const _Nav := preload("res://scripts/enemy_navigation.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
const BlockTex := preload("res://scripts/block_tex.gd")

const MAX_HP := 20
const HOP_SPEED := 3.5
const HOP_UP := 4.2
const HOP_CD := 0.55
const BITE_DAMAGE := 5
const BITE_CD := 1.2
const BITE_RANGE := 1.15
const LIFETIME := 30.0
const DUST_REWARD := 2

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var hit_radius: float = 0.35
var frozen: bool = false
var _hop_cd: float = 0.3
var _bite_cd: float = 0.6
var _life: float = 0.0
var _dead: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mode := "minion"
var mother: Node3D = null
var fragment_at: Vector3 = Vector3.ZERO
var carrying := false
var delivered := false
var _wander_dir := Vector3.ZERO
var _wander_t := 0.0
const BLOCKOLITH_HP := 40
const CARRIER_HP := 24
const CARRIER_SPEED := 3.0
const BLOCKOLITH_SPEED := 1.4


func configure(m: String, boss: Node3D = null, fragment: Vector3 = Vector3.ZERO) -> void:
	mode = m
	mother = boss
	fragment_at = fragment
	if mode == "blockolith":
		max_hp = BLOCKOLITH_HP
		hp = BLOCKOLITH_HP
	elif mode == "carrier":
		max_hp = CARRIER_HP
		hp = CARRIER_HP


func is_neutral() -> bool:
	return mode == "blockolith"


func _ready() -> void:
	if mode == "blockolith":
		add_to_group("blockolith")
	elif mode == "carrier":
		add_to_group("mother_carrier")
	else:
		add_to_group("blockling")
	add_to_group("enemy")
	collision_layer = 16
	collision_mask = 1 | 4 | 16
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := MeshInstance3D.new()
	var look: Array = {"blockolith": ["ruin", 0.8], "carrier": ["stone", 0.66]}.get(mode, ["hill", 0.62])
	var sz: float = look[1]
	body.mesh = BlockTex.cube_mesh(str(look[0]), Vector3(sz, sz, sz))
	if mode == "blockolith":
		# Тёплая «трещина» на груди — видно, что это родня Матери.
		var core := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.22, 0.22, 0.04)
		core.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(1.0, 0.55, 0.15)
		cmat.emission_enabled = true
		cmat.emission = Color(1.0, 0.45, 0.1)
		cmat.emission_energy_multiplier = 1.6
		core.material_override = cmat
		core.position = Vector3(0, 0.3, 0.41)
		core.name = "Core"
		model.add_child(core)
	body.position = Vector3(0, 0.31, 0)
	model.add_child(body)
	for sx in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.1, 0.12, 0.03)
		eye.mesh = em
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.03, 0.05)
		eye.material_override = m
		eye.position = Vector3(sx, 0.42, 0.315)   # смотрит вдоль +Z, как модели Quaternius
		model.add_child(eye)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 0.6, 0.6)
	col.shape = sh
	col.position = Vector3(0, 0.3, 0)
	add_child(col)
	_Vis.attach_hp_bar(self, 0.95)
	var bar := get_node_or_null("HPBar") as Node3D
	if bar:
		bar.scale = Vector3(0.6, 0.6, 0.6)
	_Vis.update_hp_bar(self, hp, max_hp)
	GameState.world_changed.connect(func(d: bool) -> void:
		frozen = d
		visible = not d
		set_physics_process(not d))


func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.3, 0)


func take_damage(amount: int) -> void:
	if _dead:
		return
	hp = maxi(0, hp - amount)
	_Vis.update_hp_bar(self, hp, max_hp)
	if hp <= 0:
		_dead = true
		if not GameState.dev_mode:
			GameState.add_item_count("dust", DUST_REWARD)
		if mode == "blockolith":
			_summon_mother()
		crumble()


func _summon_mother() -> void:
	## Убит Блоколит → Мать блоков выходит рядом (если нет другого босса).
	if not GameState.on_blockolith_killed() or not is_inside_tree():
		return
	var host := get_parent() as Node3D
	var cell := Vector3i(floori(global_position.x), floori(global_position.y), floori(global_position.z))
	var bm: GDScript = load("res://scripts/block_mother.gd")
	if bm.spawn_near(host, cell) != null:
		GameState.chat("Блоколит рассыпался — и земля ответила рёвом. Мать блоков пришла за своим!", Color(1.0, 0.35, 0.35))


func crumble() -> void:
	_dead = true
	hp = 0
	collision_layer = 0
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.25)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if frozen or _dead:
		return
	_life += delta
	if mode == "blockolith":
		_tick_wander(delta)
		return
	if mode == "carrier":
		_tick_carrier(delta)
		return
	if _life > LIFETIME:
		crumble()
		return
	_hop_cd -= delta
	_bite_cd -= delta
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		if player and _hop_cd <= 0.0:
			var d := player.global_position - global_position
			d.y = 0.0
			if d.length() > 0.6:
				var dir := d.normalized()
				velocity = Vector3(dir.x * HOP_SPEED, HOP_UP, dir.z * HOP_SPEED)
				_hop_cd = HOP_CD
	move_and_slide()
	if player:
		_Nav.face_point(self, player.global_position, delta, 12.0)
		var to := player.global_position - global_position
		if Vector2(to.x, to.z).length() <= BITE_RANGE and absf(to.y) < 1.6 and _bite_cd <= 0.0:
			_bite_cd = BITE_CD
			GameState.damage_player(BITE_DAMAGE, "блоклинг")



func _gravity_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)


func _tick_wander(delta: float) -> void:
	## Нейтральный Блоколит: бродит медленно, игрока не трогает. Мирный, как животное.
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(2.5, 5.0)
		var a := randf() * TAU
		_wander_dir = Vector3(cos(a), 0, sin(a)) if randf() < 0.7 else Vector3.ZERO
	_gravity_step(delta)
	velocity.x = _wander_dir.x * BLOCKOLITH_SPEED
	velocity.z = _wander_dir.z * BLOCKOLITH_SPEED
	if is_on_floor() and is_on_wall():
		velocity.y = HOP_UP * 0.8
	move_and_slide()
	if _wander_dir.length() > 0.1:
		_Nav.face_dir(self, _wander_dir, delta, 4.0)


func carrier_target() -> Vector3:
	if not carrying:
		return fragment_at
	return mother.global_position if mother != null and is_instance_valid(mother) else global_position


func _tick_carrier(delta: float) -> void:
	## Носильщик: к осколку → подбирает → к Матери → доставка (Мать чинит пластину). Не кусает.
	if mother == null or not is_instance_valid(mother) or _life > 40.0:
		crumble()
		return
	var to := carrier_target() - global_position
	to.y = 0.0
	if not carrying and to.length() < 0.8:
		carrying = true
		var frag := MeshInstance3D.new()
		frag.name = "Fragment"
		frag.mesh = BlockTex.cube_mesh("ruin", Vector3(0.4, 0.4, 0.4))
		frag.position = Vector3(0, 0.95, 0)
		add_child(frag)
	elif carrying and to.length() < float(mother.get("hit_radius")) + 0.9:
		delivered = true
		if mother.has_method("on_carrier_delivered"):
			mother.on_carrier_delivered(self)
		crumble()
		return
	_gravity_step(delta)
	var dir := to.normalized() if to.length() > 0.05 else Vector3.ZERO
	velocity.x = dir.x * CARRIER_SPEED
	velocity.z = dir.z * CARRIER_SPEED
	if is_on_floor() and is_on_wall():
		velocity.y = HOP_UP
	move_and_slide()
	if dir.length() > 0.1:
		_Nav.face_dir(self, dir, delta, 8.0)


func tick_carrier_for_sim(delta: float) -> void:
	## Для headless-симуляции без физики: двигаемся напрямую.
	if _dead:
		return
	_life += delta
	if mother == null or not is_instance_valid(mother):
		crumble()
		return
	var to := carrier_target() - global_position
	to.y = 0.0
	if not carrying and to.length() < 0.8:
		carrying = true
	elif carrying and to.length() < float(mother.get("hit_radius")) + 0.9:
		delivered = true
		if mother.has_method("on_carrier_delivered"):
			mother.on_carrier_delivered(self)
		crumble()
		return
	if to.length() > 0.05:
		global_position += to.normalized() * minf(to.length(), CARRIER_SPEED * delta)
