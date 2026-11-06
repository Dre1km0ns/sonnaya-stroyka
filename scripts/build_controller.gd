extends Node
## Режим стройки во сне: размещение / удаление блоков лучом камеры.

var player: CharacterBody3D
var dream_voxels: Node3D
var ghost: MeshInstance3D
var _place_cooldown := 0.0
var _hand_root: Node3D = null
var _pickaxe_view: Node3D = null
var _sword_view: Node3D = null


func setup(p: CharacterBody3D, dream_layer: Node3D) -> void:
	player = p
	dream_voxels = dream_layer
	_make_ghost()
	_ensure_hand_tools()


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
	_update_hand_tools()
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
	_play_tool_swing()
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null:
		return
	if collider.has_meta("voxel_cell"):
		if bool(collider.get_meta("is_dream")):
			return
		var cell: Vector3i = collider.get_meta("voxel_cell")
		if GameState.mine_wake_block(cell):
			var kind := str(GameState.last_mined_kind)
			for vox in get_tree().get_nodes_in_group("voxel_world"):
				if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
					vox.remove_block(cell)
			_finish_mine(cell, kind)
		return
	if collider.has_meta("terrain_cell"):
		var tcell: Vector3i = collider.get_meta("terrain_cell")
		var tkind := str(collider.get_meta("terrain_kind")) if collider.has_meta("terrain_kind") else "hill"
		_mine_terrain_cell(tcell, tkind)
		return
	var hit_pos: Vector3 = aim.get("position", Vector3.ZERO)
	var normal: Vector3 = aim.get("normal", Vector3.UP)
	var inside: Vector3 = hit_pos - normal * 0.05
	var gcell := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	if gcell.y != -1:
		return
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")):
			continue
		if cm.has_method("is_world_in_lake") and cm.is_world_in_lake(Vector3(float(gcell.x) + 0.5, 0.0, float(gcell.z) + 0.5)):
			return
	_mine_terrain_cell(gcell, "ground")


func _mine_terrain_cell(cell: Vector3i, kind: String) -> void:
	if GameState.is_dream():
		return
	if not GameState.selected_is("pickaxe"):
		return
	if not GameState.remove_terrain_cell(cell, kind):
		return
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")):
			continue
		if cm.has_method("rebuild_chunk_at_world"):
			cm.rebuild_chunk_at_world(cell.x, cell.z)
	_finish_mine(cell, kind)


func _finish_mine(cell: Vector3i, kind: String) -> void:
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
	drop.position = Vector3(float(cell.x) + 0.5, maxf(float(cell.y) + 0.55, 0.55), float(cell.z) + 0.5)
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
	_play_tool_swing()


func _ensure_hand_tools() -> void:
	if player == null or not player.has_node("CameraPivot/Camera3D"):
		return
	if _hand_root != null and is_instance_valid(_hand_root):
		return
	var cam: Node3D = player.get_node("CameraPivot/Camera3D")
	_hand_root = Node3D.new()
	_hand_root.name = "HandRoot"
	_hand_root.position = Vector3(0.32, -0.26, -0.48)
	_hand_root.rotation_degrees = Vector3(8, 0, -6)
	cam.add_child(_hand_root)
	_pickaxe_view = _instance_tool("res://assets/models/pickaxe.glb", "PickaxeView")
	if _pickaxe_view:
		# Модель ~1.7 м по Y (рукоять), голова на +Y; слегка наклоняем, чтобы голова была в кадре.
		_pickaxe_view.position = Vector3(0.02, -0.12, 0.0)
		_pickaxe_view.rotation_degrees = Vector3(-18, 5, 10)
		_pickaxe_view.scale = Vector3.ONE * 0.28
		_hand_root.add_child(_pickaxe_view)
	_sword_view = _instance_tool("res://assets/models/sword.glb", "SwordView")
	if _sword_view:
		# Импорт уже крутит клинок на +Y и даёт ~5.5 м; уменьшаем и кладём по диагонали кадра.
		_sword_view.position = Vector3(0.02, -0.04, 0.06)
		_sword_view.rotation_degrees = Vector3(28, 25, -40)
		_sword_view.scale = Vector3.ONE * 0.11
		_hand_root.add_child(_sword_view)
	_update_hand_tools()


func _instance_tool(path: String, node_name: String) -> Node3D:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return null
	var res = load(path)
	if res == null:
		return null
	var node: Node3D = null
	if res is PackedScene:
		node = (res as PackedScene).instantiate() as Node3D
	if node == null:
		return null
	node.name = node_name
	node.visible = false
	return node


func _update_hand_tools() -> void:
	_ensure_hand_tools()
	if _hand_root == null:
		return
	var show_pick := GameState.selected_is("pickaxe")
	var show_sword := GameState.selected_is("sword")
	if _pickaxe_view:
		_pickaxe_view.visible = show_pick
	if _sword_view:
		_sword_view.visible = show_sword
	_hand_root.visible = show_pick or show_sword


func _play_tool_swing() -> void:
	_ensure_hand_tools()
	if _hand_root == null or player == null:
		return
	_update_hand_tools()
	_hand_root.rotation_degrees = Vector3(62, 6, -22)
	var tw := player.create_tween()
	tw.tween_property(_hand_root, "rotation_degrees", Vector3(-48, 18, 14), 0.14)
	tw.tween_property(_hand_root, "rotation_degrees", Vector3(12, 0, -8), 0.12)
