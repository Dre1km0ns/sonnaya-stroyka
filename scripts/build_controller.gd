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
	if GameState.craft_menu_open:
		ghost.visible = false
		return
	if not GameState.is_dream():
		ghost.visible = false
		if _place_cooldown <= 0.0 and Input.is_action_just_pressed("place_block"):
			if GameState.selected_is("torch"):
				_try_place_torch()
				_place_cooldown = 0.16
			elif GameState.selected_is("pickaxe"):
				_try_mine_wake()
				_place_cooldown = 0.16
		elif _place_cooldown <= 0.0 and Input.is_action_just_pressed("remove_block"):
			if GameState.selected_is("pickaxe"):
				_try_mine_wake()
				_place_cooldown = 0.16
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
	var kind := "drift"
	if GameState.selected_is("workbench"):
		if not GameState.consume_item("workbench", 1):
			GameState.set_hint("Нет верстака в инвентаре.")
			return
		kind = "workbench"
	if GameState.place_dream_block(cell, kind):
		dream_voxels.add_block(cell, GameState.dream_blocks[cell])
		if kind == "workbench":
			GameState.set_hint("Верстак [%d,%d,%d]. Заякорь гвоздём, чтобы унести в явь." % [cell.x, cell.y, cell.z])
		else:
			GameState.set_hint("Дрейф-блок [%d,%d,%d]" % [cell.x, cell.y, cell.z])
	elif kind == "workbench":
		GameState.add_item("workbench", "Верстак", 1)


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


func _try_mine_wake() -> void:
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null or not collider.has_meta("voxel_cell"):
		return
	if bool(collider.get_meta("is_dream")):
		return
	var cell: Vector3i = collider.get_meta("voxel_cell")
	if GameState.mine_wake_block(cell):
		for vox in get_tree().get_nodes_in_group("voxel_world"):
			if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
				vox.remove_block(cell)


func _wake_voxels() -> Node3D:
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if not bool(vox.get("is_dream_layer")):
			return vox
	return null


func _try_place_torch() -> void:
	var vox := _wake_voxels()
	if vox == null:
		return
	var cell := Vector3i.ZERO
	var aim := _aim()
	if aim.get("hit", false):
		var hit_pos: Vector3 = aim["position"]
		var normal: Vector3 = aim["normal"]
		cell = vox.world_to_cell(hit_pos + normal * 0.51)
	else:
		var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
		var forward := -cam.global_transform.basis.z
		cell = vox.world_to_cell(cam.global_position + forward * 3.0)
	if cell.y < 0:
		cell.y = 0
	if not GameState.consume_item("torch", 1):
		return
	if GameState.place_wake_block(cell, "torch"):
		vox.add_block(cell, GameState.wake_blocks[cell])
	else:
		GameState.add_item("torch", "Факел", 1)
