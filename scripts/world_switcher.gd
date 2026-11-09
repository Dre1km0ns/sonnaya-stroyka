extends Node
## Переключение Явь ↔ Сон через кровать / клавишу F.

signal switched(is_dream: bool)

var player: CharacterBody3D
var wake_root: Node3D
var dream_root: Node3D
var wake_voxels: Node3D
var dream_voxels: Node3D
var bed: Node3D
var _env: Environment


func setup(p: CharacterBody3D, wake: Node3D, dream: Node3D, bed_node: Node3D, wake_vox: Node3D, dream_vox: Node3D) -> void:
	player = p
	wake_root = wake
	dream_root = dream
	bed = bed_node
	wake_voxels = wake_vox
	dream_voxels = dream_vox
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
	_apply_visibility(false)


func _process(delta: float) -> void:
	if GameState.is_dream():
		GameState.drain_clarity(delta)
		if GameState.clarity <= 0.0:
			wake_up()
			return
	if GameState.ui_blocked():
		return
	if Input.is_action_just_pressed("wake_up") and GameState.is_dream():
		wake_up()
	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _try_interact() -> void:
	if player == null:
		return
	var aim: Dictionary = player.get_look_ray() if player.has_method("get_look_ray") else {"hit": false}
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null:
		return
	var target: Node = collider
	if not target.is_in_group("bed") and not target.is_in_group("reagent") and not target.is_in_group("pickup"):
		if collider.get_parent() != null:
			target = collider.get_parent()
	if target.is_in_group("bed"):
		if GameState.is_dream():
			wake_up()
		else:
			enter_dream()
		return
	if (target.is_in_group("reagent") or target.is_in_group("pickup")) and target.has_method("collect"):
		target.collect()
		return
	if collider.has_meta("voxel_cell") and not GameState.is_dream():
		var cell: Vector3i = collider.get_meta("voxel_cell")
		var data: Dictionary = GameState.wake_blocks.get(cell, {})
		if str(data.get("kind", "")) == "workbench" or collider.is_in_group("workbench"):
			for menu in get_tree().get_nodes_in_group("craft_menu"):
				if menu.has_method("open_workbench"):
					menu.open_workbench()
			return


func enter_dream() -> void:
	GameState.enter_dream()
	_apply_visibility(true)
	_tint_dream(true)
	# Стартовая площадка сна у нуля — MVP-стройка; дальше бесконечные чанки.
	if GameState.dream_blocks.is_empty():
		for x in range(-2, 3):
			for z in range(-2, 3):
				var c := Vector3i(x, 0, z)
				GameState.place_dream_block(c, "drift")
				dream_voxels.add_block(c, GameState.dream_blocks[c])
	player.global_position = Vector3(0, 3, 0)
	if "flying" in player:
		player.set("flying", true)
	# Подтянуть чанки сна к игроку
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("setup") and bool(cm.get("is_dream_layer")):
			cm.setup(player, GameState.world_seed_dream)
	switched.emit(true)


func wake_up() -> void:
	var result := GameState.resolve_wake()
	_apply_visibility(false)
	_tint_dream(false)
	if wake_voxels.has_method("_rebuild_from_state"):
		wake_voxels.call("_rebuild_from_state")
	if dream_voxels and dream_voxels.has_method("_rebuild_from_state"):
		dream_voxels.call("_rebuild_from_state")
	player.global_position = Vector3(0, 2, 6)
	if "flying" in player:
		player.set("flying", false)
	switched.emit(false)
	print("Wake resolved: ", result)


func _tint_dream(is_dream: bool) -> void:
	if _env == null:
		return
	if is_dream:
		_env.background_color = Color(0.18, 0.14, 0.32)
		_env.ambient_light_color = Color(0.55, 0.45, 0.75)
		_env.fog_light_color = Color(0.45, 0.35, 0.65)
		_env.fog_density = 0.008
		_env.glow_intensity = 0.45
	else:
		for dc in get_tree().get_nodes_in_group("day_cycle"):
			if dc.has_method("apply_lighting"):
				dc.apply_lighting()
				return
		_env.background_color = Color(0.55, 0.62, 0.7)
		_env.ambient_light_color = Color(0.7, 0.68, 0.62)
		_env.fog_light_color = Color(0.7, 0.65, 0.55)
		_env.fog_density = 0.002
		_env.glow_intensity = 0.25


func _apply_visibility(is_dream: bool) -> void:
	if wake_root:
		wake_root.visible = not is_dream
		_set_process_recursive(wake_root, not is_dream)
	if dream_root:
		dream_root.visible = is_dream
		_set_process_recursive(dream_root, is_dream)


func _set_process_recursive(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		_set_process_recursive(child, enabled)
	if root is CollisionObject3D:
		# Не сохраняем 0 — иначе новый чанк невидимого мира «запомнит» пустой слой.
		var co := root as CollisionObject3D
		if co.collision_layer != 0:
			co.set_meta("_saved_layer", co.collision_layer)
		if enabled:
			if co.has_meta("_saved_layer") and int(co.get_meta("_saved_layer")) != 0:
				co.collision_layer = int(co.get_meta("_saved_layer"))
		else:
			co.collision_layer = 0
