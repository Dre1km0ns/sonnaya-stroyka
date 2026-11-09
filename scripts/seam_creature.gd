extends CharacterBody3D
const _Nav := preload("res://scripts/enemy_navigation.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
## «Шовник» — враг Яви. elite = тяжелее, крадёт больше осыпи.
## В Сне заморожен.

const SPEED_NORMAL := 2.15 * 0.6
const SPEED_ELITE := 2.85 * 0.6
const SEEK_RANGE := 28.0
const CONTACT_RANGE := 1.7
const STEAL_COOLDOWN := 1.6
const RIP_COOLDOWN := 4.5
const ATTACK_INTERVAL := 0.55
const ATTACK_HITS := 2
const KNOCKBACK := 7.5
const KNOCKBACK_ELITE := 10.0

@export var wander_radius: float = 10.0
@export var elite: bool = false

const HIT_DAMAGE := 7
const HIT_DAMAGE_ELITE := 11
var home: Vector3 = Vector3.ZERO
var frozen: bool = false
var _steal_cd: float = 0.0
var _rip_cd: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _hint_pulse: float = 0.0
var _path_cache: Dictionary = {}
var _atk_cd: float = 0.0
var _atk_hits: int = 0
var _atk_cell: Variant = null
var _punch: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mesh_built: bool = false
var hp: int = 50
var max_hp: int = 50
var _dead: bool = false


func configure_elite(on: bool) -> void:
	elite = on
	if _mesh_built:
		_recolor()


func _ready() -> void:
	add_to_group("seam_creature")
	add_to_group("enemy")
	if elite:
		add_to_group("seam_elite")
	home = global_position
	_pick_wander()
	_Nav.setup_body(self)
	GameState.world_changed.connect(_on_world)
	_apply_dream_state(GameState.is_dream())
	_build_mesh()
	if GameState.has_signal("night_changed") and not GameState.night_changed.is_connected(_on_night_look):
		GameState.night_changed.connect(_on_night_look)
	_on_night_look(GameState.is_night() if GameState.has_method("is_night") else false)
	_Vis.update_hp_bar(self, hp, max_hp)


func _build_mesh() -> void:
	_Vis.build_seam(self, elite)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38 if not elite else 0.46
	shape.height = 1.5 if not elite else 1.8
	col.shape = shape
	col.position = Vector3(0, 0.75 if not elite else 0.9, 0)
	add_child(col)
	_mesh_built = true


func _apply_body_mat(mat: StandardMaterial3D) -> void:
	if elite:
		mat.albedo_color = Color(0.35, 0.08, 0.22)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.35) * 0.75
	else:
		mat.albedo_color = Color(0.55, 0.22, 0.48)
		mat.emission_enabled = true
		mat.emission = Color(0.85, 0.25, 0.55) * 0.55
	mat.roughness = 0.7


func _recolor() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body and body.material_override:
		_apply_body_mat(body.material_override)


func _on_world(is_dream: bool) -> void:
	_apply_dream_state(is_dream)


func _apply_dream_state(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream
	set_physics_process(not is_dream)


func take_damage(amount: int) -> void:
	if _dead:
		return
	hp = maxi(0, hp - amount)
	_Vis.update_hp_bar(self, hp, max_hp)
	if hp <= 0:
		_die()


func _die() -> void:
	_dead = true
	GameState.reward_kill(false, "Шовник")
	_Vis.play_state(self, "death", true)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var tree: SceneTree = get_tree()
	if tree:
		await tree.create_timer(1.5).timeout
	if is_instance_valid(self):
		queue_free()


func _physics_process(delta: float) -> void:
	if frozen or _dead:
		return
	_steal_cd = maxf(0.0, _steal_cd - delta)
	_rip_cd = maxf(0.0, _rip_cd - delta)
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_punch = maxf(0.0, _punch - delta)
	var bod := get_node_or_null("Body") as Node3D
	if bod and _punch <= 0.0:
		bod.position.z = 0.0

	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var speed := SPEED_ELITE if elite else SPEED_NORMAL

	var target := player.global_position
	if dist >= SEEK_RANGE:
		_wander_timer -= delta
		if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 1.2:
			_pick_wander()
		target = _wander_target

	var attacking := _tick_block_attack(delta)
	if not attacking:
		_Nav.follow_target(self, target, speed, delta, _path_cache)
	else:
		_Nav.apply_movement(self, Vector3.ZERO, 0.0, delta)

	if dist <= CONTACT_RANGE + 1.0:
		_Nav.face_point(self, player.global_position, delta)
	if dist <= CONTACT_RANGE and _steal_cd <= 0.0:
		_hit_player(player, to_player)
		_steal_cd = STEAL_COOLDOWN * (0.75 if elite else 1.0)
		_punch = maxf(_punch, 0.35)
	_update_anim(attacking or _punch > 0.0)


func _update_anim(attacking: bool) -> void:
	if _dead:
		return
	var moving := Vector3(velocity.x, 0.0, velocity.z).length() > 0.18
	if attacking:
		_Vis.play_state(self, "attack")
	elif moving:
		_Vis.play_state(self, "walk")
	else:
		_Vis.play_state(self, "idle")


func _pick_wander() -> void:
	var a := randf() * TAU
	var r := randf() * wander_radius
	_wander_target = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	_wander_timer = 3.0 + randf() * 3.0


func _hit_player(player: CharacterBody3D, to_player: Vector3) -> void:
	var push := to_player.normalized()
	if push.length() < 0.01:
		push = Vector3(1, 0, 0)
	var kb := KNOCKBACK_ELITE if elite else KNOCKBACK
	player.velocity += Vector3(push.x, 0.35, push.z).normalized() * kb
	var amount := 2 if elite else 1
	# Обычный тоже больнее со временем яви (хардкор scarce)
	if GameState.awake_time > 60.0:
		amount = maxi(amount, 2)
	# v0.7: мобы бьют игрока (i-frames и анти-комбо-кап — в GameState.damage_player).
	GameState.damage_player(HIT_DAMAGE_ELITE if elite else HIT_DAMAGE, "Шовник")
	var stolen := GameState.steal_resource_hardcore(amount)
	if stolen.begins_with("dust"):
		GameState.set_hint("Шовник вырвал осыпь (%s)!" % stolen, false)
	elif stolen == "reagent":
		GameState.set_hint("Шовник сорвал реагент (−1)!", false)
	else:
		GameState.set_hint("Шовник толкает — карман пуст, но удар есть.", false)


func _tick_block_attack(_delta: float) -> bool:
	var cell: Variant = _Nav.nearest_adjacent_block(self)
	if cell == null:
		_atk_cell = null
		_atk_hits = 0
		return false
	var ripped: Vector3i = cell
	var wp := Vector3(float(ripped.x) + 0.5, float(ripped.y) + 0.5, float(ripped.z) + 0.5)
	_Nav.face_point(self, wp, get_physics_process_delta_time())
	if _atk_cell != ripped:
		_atk_cell = ripped
		_atk_hits = 0
	if _atk_cd > 0.0:
		return true
	_atk_cd = ATTACK_INTERVAL
	_punch = 0.18
	_atk_hits += 1
	_Vis.play_state(self, "attack", true)
	var body := get_node_or_null("Body") as Node3D
	if body:
		body.position.z = 0.12
	if _atk_hits < ATTACK_HITS:
		return true
	_atk_hits = 0
	GameState.wake_blocks.erase(ripped)
	GameState.dust += 1
	GameState.inventory_changed.emit()
	GameState.set_hint("Шовник разбил блок яви [%d,%d,%d]" % [ripped.x, ripped.y, ripped.z], false)
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
			vox.remove_block(ripped)
	_atk_cell = null
	return true


func _on_night_look(night: bool) -> void:
	var model := get_node_or_null("Model")
	if model:
		_Vis.apply_night(model, night)
