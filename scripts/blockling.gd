extends CharacterBody3D
## v0.6: «Блоклинг» — дитя Матери блоков. Маленький прыгучий куб: HP 20 (2 удара мечом),
## прыжки к игроку 3.5 м/с, укус 5 урона (КД 1.2 с), живёт 30 с, затем рассыпается.
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


func _ready() -> void:
	add_to_group("blockling")
	add_to_group("enemy")
	collision_layer = 16
	collision_mask = 1 | 4 | 16
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := MeshInstance3D.new()
	body.mesh = BlockTex.cube_mesh("hill", Vector3(0.62, 0.62, 0.62))
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
		crumble()


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
