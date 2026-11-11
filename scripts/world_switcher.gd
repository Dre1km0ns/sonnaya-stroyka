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
var sync_sequences:=0
var show_result_ui:=true


func setup(p: CharacterBody3D, wake: Node3D, dream: Node3D, bed_node: Node3D, wake_vox: Node3D, dream_vox: Node3D) -> void:
	player = p
	wake_root = wake
	dream_root = dream
	bed = bed_node
	wake_voxels = wake_vox
	dream_voxels = dream_vox
	add_to_group("world_switcher")
	var scene := wake_root.get_parent()
	var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if scene else null
	if we:
		_env = we.environment
	GameState.world_changed.connect(_on_world_changed)
	_apply_visibility(GameState.is_dream())


func _process(delta: float) -> void:
	if GameState.transfer_ui_open: return
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
	if Input.is_action_just_pressed("pillow_check") and not GameState.is_dream() and aimed_bed() != null:
		open_pillow()
	if Input.is_action_just_pressed("use_heal") and not GameState.is_dream():
		GameState.use_heal()


const BED_REACH := 4.0


func aimed_bed() -> Node:
	## Кровать под прицелом (спавн-кровать или поставленная), не дальше BED_REACH.
	if player == null or not player.has_method("get_look_ray"):
		return null
	var aim: Dictionary = player.get_look_ray()
	if not aim.get("hit", false):
		return null
	var collider = aim["collider"]
	if collider == null or not is_instance_valid(collider):
		return null
	var target: Node = collider
	if not target.is_in_group("bed") and target.get_parent() != null and target.get_parent().is_in_group("bed"):
		target = target.get_parent()
	if not target.is_in_group("bed"):
		return null
	if (aim["position"] as Vector3).distance_to(player.global_position + Vector3(0, 1.4, 0)) > BED_REACH:
		return null
	return target


func open_pillow() -> void:
	for p in get_tree().get_nodes_in_group("pillow_ui"):
		if p.has_method("open"):
			p.open()


func bed_spawn_point(bed_node: Node) -> Vector3:
	if bed_node != null and bed_node.has_meta("voxel_cell"):
		var c: Vector3i = bed_node.get_meta("voxel_cell")
		return Vector3(float(c.x) + 0.5, float(c.y) + 1.1, float(c.z) + 0.5)
	return GameState.DEFAULT_SPAWN


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
			# v0.7: спать можно у любой кровати — там же и проснёшься/возродишься.
			GameState.spawn_point = bed_spawn_point(target)
			GameState.active_bed = GameState.cell_key(target.get_meta("voxel_cell")) if target.has_meta("voxel_cell") else "starter"
			enter_dream()
		return
	if (target.is_in_group("reagent") or target.is_in_group("pickup")) and target.has_method("collect"):
		target.collect()
		return
	if collider.has_meta("voxel_cell"):
		var at: Vector3i = collider.get_meta("voxel_cell")
		var source := GameState.dream_blocks if GameState.is_dream() else GameState.wake_blocks
		at = GameState.root_cell(source, at)
		var kind: String = source.get(at, GameState.wake_blocks.get(at, {})).get("kind", "")
		if kind in ["chest", "idea_catcher"]:
			if kind == "idea_catcher" and not GameState.station_upgraded(at, "bed") and not _catcher_bed_in_wake(at):
				GameState.set_hint("Ловец идей должен стоять гранью к кровати.")
				return
			for ui in get_tree().get_nodes_in_group("storage_ui"):
				ui.open(at, kind == "idea_catcher")
			return
		if kind in ["sawmill", "alchemy"]:
			for menu in get_tree().get_nodes_in_group("craft_menu"):
				menu.open_station(kind, GameState.station_upgraded(at))
			return
	if collider.has_meta("voxel_cell") and not GameState.is_dream():
		var cell: Vector3i = collider.get_meta("voxel_cell")
		var data: Dictionary = GameState.wake_blocks.get(cell, {})
		if str(data.get("kind", "")) == "workbench" or collider.is_in_group("workbench"):
			for menu in get_tree().get_nodes_in_group("craft_menu"):
				if menu.has_method("open_workbench"):
					menu.open_workbench()
			return
		if str(data.get("kind", "")) == "lathe" or collider.is_in_group("lathe"):
			for menu2 in get_tree().get_nodes_in_group("craft_menu"):
				if menu2.has_method("open_lathe"):
					menu2.open_lathe()
			return


func enter_dream() -> void:
	var destination:=player.global_position if GameState.dream_mapping=="parallel" else Vector3(0,3,0)
	destination.y=maxf(destination.y,3.0)
	player.global_position=destination
	GameState.enter_dream()
	# Стартовая площадка сна у нуля — MVP-стройка; дальше бесконечные чанки.
	if GameState.dream_blocks.is_empty():
		for x in range(-2, 3):
			for z in range(-2, 3):
				var c := Vector3i(floori(destination.x)+x,floori(destination.y)-2,floori(destination.z)+z)
				GameState.place_dream_block(c, "drift")
				dream_voxels.add_block(c, GameState.dream_blocks[c])
	dream_voxels.flush_dirty()
	player.global_position = destination
	if "flying" in player:
		player.set("flying", true)
	# Dream manager configured once by main; initial generation starts lazily after this transition.
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.is_dream_layer and dream_root.is_ancestor_of(cm): cm._update_chunks(true)
	switched.emit(true)


func wake_up(abort_transfer:bool=false) -> Dictionary:
	var result:=GameState.resolve_wake(abort_transfer)
	if result.ok:
		# One safety chunk at a far return bed, never a global worker join or a 9-chunk load.
		for cm in get_tree().get_nodes_in_group("chunk_manager"):
			if not cm.is_dream_layer and not cm.panorama_mode and wake_root.is_ancestor_of(cm): cm.ensure_chunk_loaded(cm.world_to_chunk(GameState.spawn_point))
		player.global_position=GameState.spawn_point;player.velocity=Vector3.ZERO
		if "flying" in player: player.set("flying",false)
		switched.emit(false)
	if show_result_ui:
		for ui in get_tree().get_nodes_in_group("transfer_result_ui"): ui.show_result(result,self)
	print("Wake resolved: ",result)
	return result


func _tint_dream(is_dream: bool) -> void:
	if _env == null:
		return
	if is_dream:
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.18, 0.14, 0.32)
		_env.ambient_light_color = Color(0.55, 0.45, 0.75)
		_env.fog_light_color = Color(0.45, 0.35, 0.65)
		GameSettings.apply_distance_fog(_env)
		_env.glow_intensity = 0.45
	else:
		for dc in get_tree().get_nodes_in_group("day_cycle"):
			if dc.has_method("apply_lighting"):
				dc.apply_lighting()
				return
		_env.background_color = Color(0.55, 0.62, 0.7)
		_env.ambient_light_color = Color(0.7, 0.68, 0.62)
		_env.fog_light_color = Color(0.7, 0.65, 0.55)
		GameSettings.apply_distance_fog(_env)
		_env.glow_intensity = 0.25


func _on_world_changed(dream: bool) -> void:
	_apply_visibility(dream);_tint_dream(dream)

func _apply_visibility(is_dream: bool) -> void:
	sync_sequences+=1
	if wake_root:
		wake_root.visible = not is_dream
		_set_process_recursive(wake_root, not is_dream)
	if dream_root:
		dream_root.visible = is_dream
		_set_process_recursive(dream_root, is_dream)


func _set_process_recursive(root: Node, enabled: bool) -> void:
	if root==wake_root or root==dream_root: root.process_mode=Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
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


func _catcher_bed_in_wake(c: Vector3i) -> bool:
	for d in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		if GameState.wake_blocks.get(c + d, {}).get("kind", "") in ["bed", "bed_foot"]:
			return true
	return false
