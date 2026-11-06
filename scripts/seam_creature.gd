extends CharacterBody3D
const _Nav := preload("res://scripts/enemy_navigation.gd")
## «Шовник» — враг Яви. elite = тяжелее, крадёт больше осыпи.
## В Сне заморожен.

const SPEED_NORMAL := 2.15 * 0.6
const SPEED_ELITE := 2.85 * 0.6
const SEEK_RANGE := 28.0
const CONTACT_RANGE := 1.7
const HINT_RANGE := 12.0
const STEAL_COOLDOWN := 1.6
const RIP_COOLDOWN := 4.5
const KNOCKBACK := 7.5
const KNOCKBACK_ELITE := 10.0

@export var wander_radius: float = 10.0
@export var elite: bool = false

var home: Vector3 = Vector3.ZERO
var frozen: bool = false
var _steal_cd: float = 0.0
var _rip_cd: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _hint_pulse: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mesh_built: bool = false


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


func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 1.4, 0.9) if not elite else Vector3(1.15, 1.7, 1.15)
	mi.mesh = box
	mi.position = Vector3(0, 0.7 if not elite else 0.85, 0)
	var mat := StandardMaterial3D.new()
	_apply_body_mat(mat)
	mi.material_override = mat
	add_child(mi)

	var seam := MeshInstance3D.new()
	seam.name = "Seam"
	var sbox := BoxMesh.new()
	sbox.size = Vector3(1.05, 0.12, 0.2) if not elite else Vector3(1.3, 0.18, 0.28)
	seam.mesh = sbox
	seam.position = Vector3(0, 1.05 if not elite else 1.35, 0.35)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.75, 0.4) if not elite else Color(1.0, 0.35, 0.25)
	smat.emission_enabled = true
	smat.emission = (Color(1.0, 0.6, 0.3) if not elite else Color(1.0, 0.2, 0.15)) * 0.7
	seam.material_override = smat
	add_child(seam)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.4, 0.9) if not elite else Vector3(1.15, 1.7, 1.15)
	col.shape = shape
	col.position = Vector3(0, 0.7 if not elite else 0.85, 0)
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


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_steal_cd = maxf(0.0, _steal_cd - delta)
	_rip_cd = maxf(0.0, _rip_cd - delta)
	_hint_pulse = maxf(0.0, _hint_pulse - delta)

	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var speed := SPEED_ELITE if elite else SPEED_NORMAL

	if dist <= HINT_RANGE and _hint_pulse <= 0.0:
		if elite:
			GameState.set_hint("Тяжёлый Шовник! Крадёт больше осыпи.")
		else:
			GameState.set_hint("Шовник рядом! Крадёт осыпь при касании.")
		_hint_pulse = 2.5

	var desired := Vector3.ZERO
	if dist < SEEK_RANGE and dist > 0.01:
		desired = to_player.normalized()
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 1.2:
			_pick_wander()
		desired = (_wander_target - global_position).normalized()

	_Nav.apply_movement(self, desired, speed, delta)

	if dist <= CONTACT_RANGE and _steal_cd <= 0.0:
		_hit_player(player, to_player)
		_steal_cd = STEAL_COOLDOWN * (0.75 if elite else 1.0)

	if dist <= (5.0 if elite else 4.0) and _rip_cd <= 0.0:
		_rip_nearby_wake_block()
		_rip_cd = RIP_COOLDOWN * (0.7 if elite else 1.0)


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
	var stolen := GameState.steal_resource_hardcore(amount)
	if stolen.begins_with("dust"):
		GameState.set_hint("Шовник вырвал осыпь (%s)!" % stolen)
	elif stolen == "reagent":
		GameState.set_hint("Шовник сорвал реагент (−1)!")
	else:
		GameState.set_hint("Шовник толкает — карман пуст, но удар есть.")


func _rip_nearby_wake_block() -> void:
	var best: Variant = null
	var best_d := 4.2 if elite else 3.5
	for cell in GameState.wake_blocks.keys():
		var c: Vector3i = cell
		var wp := Vector3(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5)
		var d := global_position.distance_to(wp)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return
	var ripped: Vector3i = best
	GameState.wake_blocks.erase(ripped)
	GameState.dust += 1
	GameState.inventory_changed.emit()
	GameState.set_hint("Шовник разорвал блок яви [%d,%d,%d] → +1 осыпь" % [ripped.x, ripped.y, ripped.z])
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
			vox.remove_block(ripped)
