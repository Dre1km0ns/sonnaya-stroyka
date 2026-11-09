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
const BlockTex := preload("res://scripts/block_tex.gd")


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
	## v0.6: пиксельные текстуры из общего атласа (BlockTex) вместо однотонных цветов.
	var mi := MeshInstance3D.new()
	var kind: String = str(data.get("kind", "drift"))
	var anchored: bool = bool(data.get("anchored", false))
	var mutant: bool = bool(data.get("mutant", false)) or kind == "mouth"
	var tex_kind := kind
	var size := Vector3.ONE * (block_size * 0.98)
	var tint := Color(1, 1, 1)
	if kind == "torch":
		size = Vector3(0.12, 0.72, 0.12)
	elif kind == "beacon":
		size = Vector3(0.8, 0.5, 0.8)
	elif kind == "drift" or kind == "":
		if is_dream_layer:
			tex_kind = "drift_anchored" if anchored else "drift_dream"
		elif mutant:
			tex_kind = "mouth"
	elif mutant:
		tex_kind = "mouth"
	mi.mesh = BlockTex.cube_mesh(tex_kind, size, is_dream_layer, tint)
	mi.position = cell_to_world(cell)
	add_child(mi)
	_meshes[cell] = mi
	if kind == "torch":
		var flame := MeshInstance3D.new()
		var fs := SphereMesh.new()
		fs.radius = 0.14
		fs.height = 0.28
		flame.mesh = fs
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.62, 0.2)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.45, 0.1)
		fmat.emission_energy_multiplier = 1.4
		flame.material_override = fmat
		flame.position = Vector3(0, 0.42, 0)
		mi.add_child(flame)
		var light := OmniLight3D.new()
		light.name = "TorchLight"
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 1.55
		light.omni_range = 8.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.position = Vector3(0, 0.45, 0)
		mi.add_child(light)
	if kind == "beacon":
		mi.position = cell_to_world(cell) + Vector3(0, -0.25, 0)
		var core := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = 0.22
		cs.height = 0.44
		core.mesh = cs
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.45, 0.95, 1.0)
		cmat.emission_enabled = true
		cmat.emission = Color(0.35, 0.9, 1.0)
		cmat.emission_energy_multiplier = 2.0
		core.material_override = cmat
		core.position = Vector3(0, 0.45, 0)
		mi.add_child(core)
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		var bm := CylinderMesh.new()
		bm.top_radius = 0.18
		bm.bottom_radius = 0.18
		bm.height = 48.0
		bm.radial_segments = 8
		bm.rings = 1
		beam.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(0.45, 0.95, 1.0, 0.35)
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bmat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, 24.5, 0)
		mi.add_child(beam)
	if kind == "workbench":
		# Столешница — дочерний узел блока: враг/кирка снимают верстак целиком.
		var top := MeshInstance3D.new()
		top.mesh = BlockTex.cube_mesh("workbench", Vector3(1.16, 0.14, 1.16))
		top.position = Vector3(0, 0.50, 0)
		mi.add_child(top)

	var body := StaticBody3D.new()
	body.collision_layer = 4 # blocks
	body.collision_mask = 0
	body.position = mi.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if kind == "workbench":
		shape.size = Vector3(block_size, block_size * 1.2, block_size)
		body.position = mi.position + Vector3(0, 0.10, 0)
	else:
		shape.size = Vector3.ONE * block_size
	col.shape = shape
	body.add_child(col)
	body.set_meta("voxel_cell", cell)
	body.set_meta("is_dream", is_dream_layer)
	body.set_meta("kind", kind)
	if kind == "workbench":
		body.add_to_group("workbench")
	if kind == "torch":
		body.add_to_group("torch")
	if kind == "beacon":
		body.add_to_group("beacon")
	add_child(body)
	_bodies[cell] = body
