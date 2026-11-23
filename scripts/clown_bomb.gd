extends CharacterBody3D
## v0.24: миньоны Бургера. Клоун-бомба — идёт к игроку 3 м/с, рядом мигает и взрывается через 2 с.
## Клоун-осколок (shard) — после смерти Антона: прыгает хаотично, бьёт касанием, 12 с на всех.
## friendly — дружественный клоун от Носа клоуна: идёт к ближайшему врагу и взрывается на нём.
const CU := preload("res://scripts/combat_util.gd")
const Sfx := preload("res://scripts/sfx.gd")
const BreakFx := preload("res://scripts/break_fx.gd")
const SPEED := 3.0
const FUSE := 2.0
const BLAST_R := 2.2
const BLAST_DMG := 20
const LIFE := 15.0
const SHARD_HP := 70
const SHARD_DMG := 10
const BOMB_HP := 20
var boss: Node = null
var shard := false
var friendly := false
var dead := false
var held := false
var hp := BOMB_HP
var max_hp := BOMB_HP
var hit_radius := 0.4
var fuse := -1.0
var life := LIFE
var _hop_cd := 0.0
var _hit_cd := 0.0
var _body: Node3D
var _nose_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("burger_clown")
	if not friendly:
		add_to_group("enemy")
	collision_layer = 16 if not friendly else 0
	collision_mask = 1
	max_hp = SHARD_HP if shard else BOMB_HP
	hp = max_hp
	GameState.apply_enemy_scaling(self, max_hp, true)
	_build()
	var col := CollisionShape3D.new()
	var sh := CapsuleShape3D.new(); sh.radius = 0.35; sh.height = 1.1
	col.shape = sh; col.position = Vector3(0, 0.55, 0)
	add_child(col)
	if shard:
		life = 999.0


func _build() -> void:
	_body = Node3D.new(); add_child(_body)
	var packed: PackedScene = load("res://assets/models/kenney_blocky/character-a.glb")
	var m: Node3D = packed.instantiate()
	m.scale = Vector3.ONE * (0.75 if not shard else 0.6)
	m.rotation.y = PI
	_body.add_child(m)
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("walk"): ap.play("walk")
	var nose := MeshInstance3D.new(); var ns := SphereMesh.new(); ns.radius = 0.09; ns.height = 0.18
	nose.mesh = ns
	_nose_mat = StandardMaterial3D.new(); _nose_mat.albedo_color = Color(1, 0.1, 0.1); _nose_mat.emission_enabled = true; _nose_mat.emission = Color(1, 0.1, 0.1)
	nose.material_override = _nose_mat
	nose.position = Vector3(0, 0.62 if not shard else 0.5, -0.2)
	_body.add_child(nose)
	var hat := MeshInstance3D.new(); var hc := CylinderMesh.new(); hc.top_radius = 0.0; hc.bottom_radius = 0.17; hc.height = 0.4
	hat.mesh = hc
	var hm := StandardMaterial3D.new(); hm.albedo_color = Color(1, 0.85, 0.1) if not friendly else Color(0.3, 1, 0.4)
	if shard: hm.albedo_color = Color(0.8, 0.3, 1.0)
	hat.material_override = hm
	hat.position = Vector3(0, 1.1 if not shard else 0.88, 0)
	_body.add_child(hat)


func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)


func is_dead_v024() -> bool:
	return dead


func take_damage(amount: int) -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0:
		_die(false)


func leap_at(p: Vector3) -> void:
	## «Клоунский зов»: все клоуны прыгают к игроку (общий телеграф 0.8 с у Антона).
	var to := p - global_position
	to.y = 0
	velocity = to.limit_length(9.0) + Vector3(0, 7.5, 0)
	fuse = minf(fuse, 0.9) if fuse > 0.0 else 1.2


func eaten() -> void:
	dead = true
	queue_free()


func _target() -> Node3D:
	if friendly:
		var best: Node3D = null
		var bd := INF
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D and is_instance_valid(e) and not e.is_in_group("burger_clown"):
				var d := (e as Node3D).global_position.distance_to(global_position)
				if d < bd: bd = d; best = e
		return best
	return CU.nearest_player(get_tree(), global_position)


func _physics_process(delta: float) -> void:
	if dead or GameState.is_dream():
		return
	life -= delta
	_hop_cd -= delta
	_hit_cd -= delta
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	var t := _target()
	if held:
		velocity = Vector3.ZERO
		return
	if t != null:
		var to := t.global_position - global_position
		to.y = 0
		if to.length() > 0.05:
			rotation.y = atan2(to.x, to.z)
		if shard:
			if is_on_floor() and _hop_cd <= 0.0:
				_hop_cd = randf_range(0.5, 1.1)
				var dir := (to.normalized() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.8).normalized()
				velocity = dir * 5.0 + Vector3(0, 6.0, 0)
				Sfx.play3d(self, "res://assets/audio/sfx_shard.ogg", -6.0, 30.0)
			if to.length() < 1.1 and _hit_cd <= 0.0:
				_hit_cd = 1.0
				CU.hurt(t, SHARD_DMG, "Клоун-осколок", global_position)
		else:
			if fuse < 0.0:
				var sp := SPEED * GameState.diff_speed()
				if is_on_floor():
					velocity.x = to.normalized().x * sp
					velocity.z = to.normalized().z * sp
				if to.length() < 1.6:
					fuse = FUSE
			if fuse >= 0.0:
				fuse -= delta
				_nose_mat.emission_energy_multiplier = 4.0 if int(fuse * 8.0) % 2 == 0 else 0.5
				if is_on_floor():
					velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
					velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
				if fuse <= 0.0:
					_explode()
					return
	if life <= 0.0 and not shard:
		_explode()
		return
	move_and_slide()


func _explode() -> void:
	Sfx.play3d(self, "res://assets/audio/sfx_explosion.ogg", 0.0, 60.0)
	BreakFx.puff(get_parent(), global_position + Vector3(0, 0.5, 0), Color(1, 0.6, 0.2), 24)
	if friendly:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D and (e as Node3D).global_position.distance_to(global_position) < BLAST_R and e.has_method("take_damage"):
				e.take_damage(30)
	else:
		for p in CU.players(get_tree()):
			if (p as Node3D).global_position.distance_to(global_position) < BLAST_R:
				CU.hurt(p, BLAST_DMG, "Клоун-бомба", global_position)
	_die(true)


func _die(exploded: bool) -> void:
	dead = true
	collision_layer = 0
	if not exploded:
		BreakFx.puff(get_parent(), global_position + Vector3(0, 0.5, 0), Color(1, 0.3, 0.3) if not shard else Color(0.8, 0.3, 1), 14)
		Sfx.play3d(self, "res://assets/audio/sfx_mob_die.ogg", -4.0, 40.0)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.25)
	tw.tween_callback(queue_free)
