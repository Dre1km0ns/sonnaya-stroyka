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
			if GameState.selected_is("sword"):
				_try_sword()
				_place_cooldown = 0.45
			elif GameState.selected_is("torch"):
				_try_place_torch()
				_place_cooldown = 0.16
			elif GameState.selected_is("pickaxe"):
				_try_mine_wake()
				_place_cooldown = 0.18
			elif GameState.is_placeable_block(str(GameState.get_selected_item().get("id", ""))):
				_try_place_wake_item()
				_place_cooldown = 0.16
		elif _place_cooldown <= 0.0 and Input.is_action_just_pressed("remove_block"):
			if GameState.selected_is("pickaxe"):
				_try_mine_wake()
				_place_cooldown = 0.18
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
		var kind := str(GameState.last_mined_kind)
		for vox in get_tree().get_nodes_in_group("voxel_world"):
			if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
				vox.remove_block(cell)
		_spawn_block_pickup(cell, kind)
		var host := _wake_world()
		if host:
			var boss_script: GDScript = load("res://scripts/block_mother.gd")
			boss_script.try_spawn_from_mine(host, cell)


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

func _wake_world() -> Node3D:
	var vox := _wake_voxels()
	if vox and vox.get_parent() is Node3D:
		return vox.get_parent()
	return get_tree().current_scene.get_node_or_null("WakeWorld") as Node3D


func _spawn_block_pickup(cell: Vector3i, kind: String) -> void:
	var host := _wake_world()
	if host == null:
		return
	var script: GDScript = load("res://scripts/block_pickup.gd")
	var drop: StaticBody3D = script.new()
	if drop.has_method("configure"):
		drop.configure(kind)
	drop.position = Vector3(float(cell.x) + 0.5, float(cell.y) + 0.55, float(cell.z) + 0.5)
	host.add_child(drop)


func _try_place_wake_item() -> void:
	var vox := _wake_voxels()
	if vox == null:
		return
	var id := str(GameState.get_selected_item().get("id", ""))
	if not GameState.is_placeable_block(id):
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
	if not GameState.consume_placeable(id):
		return
	if GameState.place_wake_block(cell, id):
		vox.add_block(cell, GameState.wake_blocks[cell])
	else:
		GameState.add_mined_block(id, 1)


func _try_sword() -> void:
	_play_sword_swing()
	var origin: Vector3 = player.global_position + Vector3(0, 1.15, 0)
	var forward := Vector3.FORWARD
	if player.has_node("CameraPivot/Camera3D"):
		forward = -player.get_node("CameraPivot/Camera3D").global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = -player.global_transform.basis.z
	forward = forward.normalized()
	var hit := 0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if n.has_method("get") and bool(n.get("frozen") if "frozen" in n else false):
			pass
		if "frozen" in n and bool(n.frozen):
			continue
		if "visible" in n and not bool(n.visible):
			continue
		var to: Vector3 = (n as Node3D).global_position - origin
		var dist := to.length()
		if dist > 2.6 or dist < 0.05:
			continue
		var dir := to.normalized()
		if dir.dot(forward) < 0.15:
			continue
		if n.has_method("take_damage"):
			n.take_damage(10)
			hit += 1
	if GameState.has_method("set_hint"):
		if hit > 0:
			GameState.set_hint("Меч: попаданий %d (−10 HP)." % hit)
		else:
			GameState.set_hint("Меч: мимо.")


func _play_sword_swing() -> void:
	if player == null or not player.has_node("CameraPivot"):
		return
	var pivot: Node3D = player.get_node("CameraPivot")
	var blade: MeshInstance3D = pivot.get_node_or_null("SwordMesh") as MeshInstance3D
	if blade == null:
		blade = MeshInstance3D.new()
		blade.name = "SwordMesh"
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.08, 0.85)
		blade.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.78, 0.82)
		mat.metallic = 0.65
		mat.roughness = 0.28
		blade.material_override = mat
		blade.position = Vector3(0.28, -0.12, -0.55)
		pivot.add_child(blade)
	blade.visible = true
	blade.rotation_degrees = Vector3(70, 0, -25)
	var tw := player.create_tween()
	tw.tween_property(blade, "rotation_degrees", Vector3(-35, 15, 10), 0.18)
	tw.tween_property(blade, "rotation_degrees", Vector3(20, 0, -8), 0.14)
