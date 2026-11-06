extends CharacterBody3D
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
const SPEED := 2.45
const SEEK_RANGE := 42.0
const CONTACT_RANGE := 1.7
const HINT_RANGE := 12.0
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
	collision_layer = 0
	collision_mask = 1
	GameState.world_changed.connect(_on_world)
	_apply_dream_state(GameState.is_dream())
	_build_mesh()


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
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.95, 1.35, 0.95)
	mi.mesh = box
	mi.position = Vector3(0, 0.68, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colr
	mat.emission_enabled = true
	mat.emission = colr * 0.55
	mat.roughness = 0.55
	mi.material_override = mat
	add_child(mi)

	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cbox := BoxMesh.new()
	cbox.size = Vector3(0.7, 0.22, 0.7)
	cap.mesh = cbox
	cap.position = Vector3(0, 1.42, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = colr.lightened(0.25)
	cmat.emission_enabled = true
	cmat.emission = colr * 0.35
	cap.material_override = cmat
	add_child(cap)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = kind_name()
	tag.font_size = 36
	tag.position = Vector3(0, 1.85, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = colr.lightened(0.35)
	add_child(tag)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 1.35, 0.95)
	col.shape = shape
	col.position = Vector3(0, 0.68, 0)
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
	_hint_pulse = maxf(0.0, _hint_pulse - delta)

	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= HINT_RANGE and _hint_pulse <= 0.0:
		GameState.set_hint("%s рядом!" % kind_name())
		_hint_pulse = 2.5

	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	var target := compute_target(player.global_position, forward, _find_blinky_pos(), is_scatter_mode())
	var to_target := target - global_position
	to_target.y = 0.0
	var desired := Vector3.ZERO
	if to_target.length() > 0.15 and dist < SEEK_RANGE + 12.0:
		desired = to_target.normalized()

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	velocity.x = desired.x * SPEED
	velocity.z = desired.z * SPEED
	move_and_slide()

	if dist <= CONTACT_RANGE and _steal_cd <= 0.0:
		_hit_player(player, to_player)
		_steal_cd = STEAL_COOLDOWN


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
