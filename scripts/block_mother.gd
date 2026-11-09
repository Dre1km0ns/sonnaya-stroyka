extends CharacterBody3D
const _Vis := preload("res://scripts/enemy_visuals.gd")
## Босс «Мать блоков»: прыгает как слайм Minecraft.

const MAX_HP := 1000
const JUMP_SPEED := 7.2
const JUMP_Y := 9.2
const LAND_RADIUS := 3.1
const CONTACT_RANGE := 2.0
const CONTACT_CD := 1.05
const PAUSE_MIN := 0.55
const PAUSE_MAX := 1.05
const MODEL_PATH := "res://assets/models/greenblob.glb"
const SPAWN_CHANCE := 0.25

var hp: int = MAX_HP
var max_hp: int = MAX_HP
var _dead: bool = false
var _pause: float = 0.4
var _airborne: bool = false
var _contact_cd: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


static func try_spawn_from_mine(host: Node3D, cell: Vector3i) -> Node:
	if host == null or host.get_tree() == null:
		return null
	if GameState != null and bool(GameState.get("boss_alive")):
		return null
	if host.get_tree().get_nodes_in_group("block_mother").size() > 0:
		return null
	if randf() >= SPAWN_CHANCE:
		return null
	return spawn_near(host, cell)


static func spawn_near(host: Node3D, cell: Vector3i) -> Node:
	var pos := Vector3(float(cell.x) + 3.4, 0.15, float(cell.z) + 1.6)
	if host.get_tree() != null:
		for cm in host.get_tree().get_nodes_in_group("chunk_manager"):
			if cm.has_method("height_at") and not bool(cm.get("is_dream_layer")):
				var h: int = int(cm.call("height_at", int(pos.x), int(pos.z)))
				pos.y = float(h) + 0.15
				break
	var script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = script.new()
	boss.position = pos
	host.add_child(boss)
	return boss


func _ready() -> void:
	add_to_group("block_mother")
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 16
	collision_mask = 1 | 2 | 4
	_Vis.attach_model(self, MODEL_PATH, 3.15)
	_Vis.attach_hp_bar(self, 3.45)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.15
	col.shape = shape
	col.position = Vector3(0, 1.15, 0)
	add_child(col)
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(true)
	_Vis.play_state(self, "idle", true)


func take_damage(amount: int) -> void:
	if _dead:
		return
	hp = maxi(0, hp - amount)
	_Vis.update_hp_bar(self, hp, max_hp)
	if hp <= 0:
		_die()


func _die() -> void:
	_dead = true
	GameState.reward_kill(true, "Мать блоков")
	_Vis.play_state(self, "death", true)
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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_contact_cd = maxf(0.0, _contact_cd - delta)
	if not is_on_floor():
		_airborne = true
		velocity.y -= _gravity * delta
	else:
		if _airborne:
			_airborne = false
			_on_land()
			_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
			velocity.x = 0.0
			velocity.z = 0.0
			_Vis.play_state(self, "idle")
		velocity.y = 0.0
		_pause -= delta
		if _pause <= 0.0:
			_do_jump()
	move_and_slide()
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and global_position.distance_to(player.global_position) <= CONTACT_RANGE and _contact_cd <= 0.0:
		_hurt_player(player, false)
		_contact_cd = CONTACT_CD


func _do_jump() -> void:
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var dir := Vector3.FORWARD
	if player:
		dir = player.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	look_at(global_position + dir, Vector3.UP)
	velocity = dir * JUMP_SPEED
	velocity.y = JUMP_Y
	_airborne = true
	_Vis.play_state(self, "jump", true)


func _on_land() -> void:
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and global_position.distance_to(player.global_position) <= LAND_RADIUS:
		_hurt_player(player, true)


func _hurt_player(player: CharacterBody3D, landing: bool) -> void:
	var push: Vector3 = player.global_position - global_position
	push.y = 0.0
	if push.length() < 0.01:
		push = Vector3(1, 0, 0)
	var kb := 14.0 if landing else 9.0
	player.velocity += push.normalized() * kb + Vector3(0, 0.55 if landing else 0.3, 0)
	var stolen := "none"
	if GameState.has_method("steal_resource_hardcore"):
		stolen = str(GameState.steal_resource_hardcore(4 if landing else 2))
	if GameState.has_method("set_hint"):
		if landing:
			GameState.set_hint("Мать блоков приземлилась! (%s)" % stolen)
		else:
			GameState.set_hint("Мать блоков задела тебя (%s)." % stolen)
