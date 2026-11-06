extends CharacterBody3D
const _Nav := preload("res://scripts/enemy_navigation.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
## Четыре «призрака» в духе Pac-Man: враг1..враг4 (Blinky / Pinky / Inky / Clyde).
## Scatter/Chase задаёт ThreatDirector.

enum Kind { ENEMY1, ENEMY2, ENEMY3, ENEMY4 }

const KIND_NAMES: Array[String] = ["враг1", "враг2", "враг3", "враг4"]
const KIND_COLORS: Array[Color] = [
	Color(0.90, 0.14, 0.12),
	Color(1.00, 0.52, 0.74),
	Color(0.18, 0.78, 0.86),
	Color(1.00, 0.55, 0.12),
]
const SPEED := 2.45 * 0.6
const SEEK_RANGE := 42.0
const CONTACT_RANGE := 1.7
const ATTACK_INTERVAL := 0.55
const ATTACK_HITS := 2
const STEAL_COOLDOWN := 1.6
const PINKY_AHEAD := 6.0
const CLYDE_FLEE_DIST := 10.0
const KNOCKBACK := 6.5

@export var kind: int = Kind.ENEMY1

var home: Vector3 = Vector3.ZERO
var corner: Vector3 = Vector3.ZERO
var frozen: bool = false
var _steal_cd: float = 0.0
var _hint_pulse: float = 0.0
var _path_cache: Dictionary = {}
var _atk_cd: float = 0.0
var _atk_hits: int = 0
var _atk_cell: Variant = null
var _punch: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mesh_built: bool = false


func configure(k: int, home_pos: Vector3, corner_pos: Vector3) -> void:
	kind = clampi(k, 0, 3)
	home = home_pos
	corner = corner_pos


func kind_name() -> String:
	return KIND_NAMES[clampi(kind, 0, 3)]


func _ready() -> void:
	add_to_group("enemy_ghost")
	add_to_group("enemy")
	if kind == Kind.ENEMY1:
		add_to_group("enemy_blinky")
	if home == Vector3.ZERO:
		home = global_position
	if corner == Vector3.ZERO:
		corner = _default_corner()
	_Nav.setup_body(self)
	GameState.world_changed.connect(_on_world)
	_apply_dream_state(GameState.is_dream())
	_build_mesh()
	if GameState.has_signal("night_changed") and not GameState.night_changed.is_connected(_on_night_look):
		GameState.night_changed.connect(_on_night_look)
	_on_night_look(GameState.is_night() if GameState.has_method("is_night") else false)


func _default_corner() -> Vector3:
	match kind:
		Kind.ENEMY1:
			return Vector3(42.0, 1.0, 42.0)
		Kind.ENEMY2:
			return Vector3(-42.0, 1.0, 42.0)
		Kind.ENEMY3:
			return Vector3(42.0, 1.0, -42.0)
		_:
			return Vector3(-42.0, 1.0, -42.0)


func _build_mesh() -> void:
	var colr: Color = KIND_COLORS[clampi(kind, 0, 3)]
	_Vis.build_ghost(self, kind, colr)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = kind_name()
	tag.font_size = 32
	tag.position = Vector3(0, 1.95, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = colr.lightened(0.35)
	add_child(tag)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.45
	col.shape = shape
	col.position = Vector3(0, 0.72, 0)
	add_child(col)
	_mesh_built = true


func _on_world(is_dream: bool) -> void:
	_apply_dream_state(is_dream)


func _apply_dream_state(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream
	set_physics_process(not is_dream)


func is_scatter_mode() -> bool:
	for n in get_tree().get_nodes_in_group("threat_director"):
		if n.has_method("is_ghost_scatter"):
			return bool(n.call("is_ghost_scatter"))
		if "ghost_mode" in n:
			return int(n.get("ghost_mode")) == 1
	return false


func compute_target(player_pos: Vector3, player_forward: Vector3, blinky_pos: Vector3, scatter: bool) -> Vector3:
	if scatter:
		return corner
	match kind:
		Kind.ENEMY1:
			return player_pos
		Kind.ENEMY2:
			return player_pos + player_forward.normalized() * PINKY_AHEAD
		Kind.ENEMY3:
			return player_pos * 2.0 - blinky_pos
		_:
			if global_position.distance_to(player_pos) > CLYDE_FLEE_DIST:
				return player_pos
			return corner


func _find_blinky_pos() -> Vector3:
	for n in get_tree().get_nodes_in_group("enemy_blinky"):
		if n != self and is_instance_valid(n) and n is Node3D:
			return (n as Node3D).global_position
	return home


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_steal_cd = maxf(0.0, _steal_cd - delta)
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

	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	var target := compute_target(player.global_position, forward, _find_blinky_pos(), is_scatter_mode())
	var attacking := _tick_block_attack()
	if not attacking and dist < SEEK_RANGE + 12.0:
		_Nav.follow_target(self, target, SPEED, delta, _path_cache)
	elif attacking:
		_Nav.apply_movement(self, Vector3.ZERO, 0.0, delta)

	if dist <= CONTACT_RANGE and _steal_cd <= 0.0:
		_hit_player(player, to_player)
		_steal_cd = STEAL_COOLDOWN


func _tick_block_attack() -> bool:
	var cell: Variant = _Nav.nearest_adjacent_block(self)
	if cell == null:
		_atk_cell = null
		_atk_hits = 0
		return false
	var ripped: Vector3i = cell
	if _atk_cell != ripped:
		_atk_cell = ripped
		_atk_hits = 0
	if _atk_cd > 0.0:
		return true
	_atk_cd = ATTACK_INTERVAL
	_punch = 0.18
	_atk_hits += 1
	var body := get_node_or_null("Body") as Node3D
	if body:
		body.position.z = 0.12
	if _atk_hits < ATTACK_HITS:
		return true
	_atk_hits = 0
	GameState.wake_blocks.erase(ripped)
	GameState.inventory_changed.emit()
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
			vox.remove_block(ripped)
	_atk_cell = null
	return true


func _hit_player(player: CharacterBody3D, to_player: Vector3) -> void:
	var push := to_player.normalized()
	if push.length() < 0.01:
		push = Vector3(1, 0, 0)
	player.velocity += Vector3(push.x, 0.3, push.z).normalized() * KNOCKBACK
	var stolen := GameState.steal_resource_hardcore(1)
	if stolen.begins_with("dust"):
		GameState.set_hint("%s выхватил осыпь!" % kind_name())
	elif stolen.begins_with("reagent"):
		GameState.set_hint("%s сорвал реагент!" % kind_name())
	else:
		GameState.set_hint("%s толкает — карман пуст." % kind_name())


func _on_night_look(night: bool) -> void:
	var model := get_node_or_null("Model")
	if model:
		_Vis.apply_night(model, night)
