extends Node
## Режим стройки во сне: размещение / удаление блоков лучом камеры.

var player: CharacterBody3D
var dream_voxels: Node3D
var ghost: MeshInstance3D
var _place_cooldown := 0.0


func setup(p: CharacterBody3D, dream_layer: Node3D) -> void:
	player = p
	dream_voxels = dream_layer
	_make_ghost()


func _make_ghost() -> void:
	ghost = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.98
	ghost.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = mat
	ghost.visible = false
	add_child(ghost)


func _process(delta: float) -> void:
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	if player == null or dream_voxels == null:
		return
	if not GameState.is_dream():
		ghost.visible = false
		return
	_update_ghost()
	if Input.is_action_just_pressed("place_block") and _place_cooldown <= 0.0:
		_try_place()
		_place_cooldown = 0.12
	if Input.is_action_just_pressed("remove_block") and _place_cooldown <= 0.0:
		_try_remove()
		_place_cooldown = 0.12


func _aim() -> Dictionary:
	if player.has_method("get_look_ray"):
		return player.get_look_ray()
	return {"hit": false}


func _update_ghost() -> void:
	var aim := _aim()
	if not aim.get("hit", false):
		ghost.visible = false
		return
	var normal: Vector3 = aim["normal"]
	var hit_pos: Vector3 = aim["position"]
	var place_pos := hit_pos + normal * 0.51
	var cell: Vector3i = dream_voxels.world_to_cell(place_pos)
	ghost.global_position = dream_voxels.cell_to_world(cell)
	ghost.visible = true


func _try_place() -> void:
	var aim := _aim()
	if not aim.get("hit", false):
		# Размещение в воздухе перед игроком
		var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
		var forward := -cam.global_transform.basis.z
		var place_pos := cam.global_position + forward * 4.0
		var cell: Vector3i = dream_voxels.world_to_cell(place_pos)
		if cell.y < 0:
			cell.y = 0
		_place_at(cell)
		return
	var normal: Vector3 = aim["normal"]
	var hit_pos: Vector3 = aim["position"]
	var place_pos2 := hit_pos + normal * 0.51
	var cell2: Vector3i = dream_voxels.world_to_cell(place_pos2)
	_place_at(cell2)


func _place_at(cell: Vector3i) -> void:
	if GameState.place_dream_block(cell, "drift"):
		dream_voxels.add_block(cell, GameState.dream_blocks[cell])
		GameState.set_hint("Дрейф-блок [%d,%d,%d]" % [cell.x, cell.y, cell.z])


func _try_remove() -> void:
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null or not collider.has_meta("voxel_cell"):
		return
	if not bool(collider.get_meta("is_dream")):
		return
	var cell: Vector3i = collider.get_meta("voxel_cell")
	if GameState.remove_dream_block(cell):
		dream_voxels.remove_block(cell)
		GameState.set_hint("Снят блок [%d,%d,%d]" % [cell.x, cell.y, cell.z])
