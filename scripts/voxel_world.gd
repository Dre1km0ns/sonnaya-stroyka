extends Node3D
## Визуализация и коллизии воксельных блоков для Яви или Сна.

@export var is_dream_layer: bool = false
@export var block_size: float = 1.0

var _meshes: Dictionary = {} # Vector3i -> MeshInstance3D
var _bodies: Dictionary = {} # Vector3i -> StaticBody3D

const COLOR_WAKE := Color(0.72, 0.58, 0.42)       # охра
const COLOR_WAKE_MOUTH := Color(0.75, 0.25, 0.35) # рот — мутация
const COLOR_DREAM := Color(0.55, 0.48, 0.85)      # индиго
const COLOR_DREAM_ANCHORED := Color(0.98, 0.72, 0.55) # персик шов
const COLOR_DREAM_PEACH := Color(0.95, 0.70, 0.62)


func _ready() -> void:
	add_to_group("voxel_world")
	if is_dream_layer:
		GameState.world_changed.connect(_on_world)
	else:
		GameState.world_changed.connect(_on_world)
		GameState.wake_resolved.connect(_on_wake_resolved)
	_rebuild_from_state()


func _on_world(_is_dream: bool) -> void:
	_rebuild_from_state()


func _on_wake_resolved(_t: int, _d: int, _m: int) -> void:
	_rebuild_from_state()


func _rebuild_from_state() -> void:
	_clear_all()
	var source: Dictionary = GameState.dream_blocks if is_dream_layer else GameState.wake_blocks
	for cell in source.keys():
		var data: Dictionary = source[cell]
		_spawn_visual(cell, data)


func _clear_all() -> void:
	for c in _meshes.keys():
		var m: Node = _meshes[c]
		if is_instance_valid(m):
			m.queue_free()
	for c in _bodies.keys():
		var b: Node = _bodies[c]
		if is_instance_valid(b):
			b.queue_free()
	_meshes.clear()
	_bodies.clear()


func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell) * block_size + Vector3.ONE * (block_size * 0.5)


func world_to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(floori(pos.x / block_size), floori(pos.y / block_size), floori(pos.z / block_size))


func has_block(cell: Vector3i) -> bool:
	return _meshes.has(cell)


func add_block(cell: Vector3i, data: Dictionary) -> void:
	if _meshes.has(cell):
		return
	_spawn_visual(cell, data)


func remove_block(cell: Vector3i) -> void:
	if _meshes.has(cell):
		_meshes[cell].queue_free()
		_meshes.erase(cell)
	if _bodies.has(cell):
		_bodies[cell].queue_free()
		_bodies.erase(cell)


func refresh_block(cell: Vector3i, data: Dictionary) -> void:
	remove_block(cell)
	_spawn_visual(cell, data)


func _spawn_visual(cell: Vector3i, data: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * (block_size * 0.98)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	mat.metallic = 0.0
	var kind: String = str(data.get("kind", "drift"))
	var anchored: bool = bool(data.get("anchored", false))
	var mutant: bool = bool(data.get("mutant", false)) or kind == "mouth"
	if is_dream_layer:
		if anchored:
			mat.albedo_color = COLOR_DREAM_ANCHORED
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.6, 0.35) * 0.35
		else:
			mat.albedo_color = COLOR_DREAM if kind == "drift" else COLOR_DREAM_PEACH
	else:
		mat.albedo_color = COLOR_WAKE_MOUTH if mutant else COLOR_WAKE
		if mutant:
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.2, 0.3) * 0.4
	mi.material_override = mat
	mi.position = cell_to_world(cell)
	add_child(mi)
	_meshes[cell] = mi

	var body := StaticBody3D.new()
	body.collision_layer = 4 # blocks
	body.collision_mask = 0
	body.position = mi.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * block_size
	col.shape = shape
	body.add_child(col)
	body.set_meta("voxel_cell", cell)
	body.set_meta("is_dream", is_dream_layer)
	add_child(body)
	_bodies[cell] = body
