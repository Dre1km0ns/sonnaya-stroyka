extends Node
## Режим стройки во сне: размещение / удаление блоков лучом камеры.

var player: CharacterBody3D
var dream_voxels: Node3D
var ghost: MeshInstance3D
var _place_cooldown := 0.0
var _hand_root: Node3D = null
var _pickaxe_view: Node3D = null
var _sword_view: Node3D = null
const SWORD_DAMAGE := 7
const SWORD_COOLDOWN := 0.45
const SWORD_REACH := 2.6
## v0.7: Меч2 — 25 урона, дальность ×1.25.
const SWORD2_DAMAGE := 13
const SWORD3_DAMAGE := 23
const SWORD2_REACH := SWORD_REACH * 1.25
const MIN_PLACE_Y := -30
var _pickaxe2_view: Node3D = null
var _sword2_view: Node3D = null
var _sword3_view: Node3D = null
var last_sword_damage := 0
var last_sword_hits := 0
var _mine_cell := Vector3i(99999,99999,99999)
var _mine_elapsed := 0.0
var _mine_swing_t := 0.0
var cracks: MeshInstance3D
var _mine_tool := ""


func setup(p: CharacterBody3D, dream_layer: Node3D) -> void:
	player = p
	dream_voxels = dream_layer
	_make_ghost()
	cracks = load("res://scripts/mining_cracks.gd").new()
	add_child(cracks)
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
	if cracks: cracks.visible = false
	_mine_swing_t = maxf(0.0,_mine_swing_t-delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	_update_hand_tools()
	if player == null or dream_voxels == null:
		return
	if GameState.ui_blocked():
		_mine_elapsed = 0.0
		ghost.visible = false
		return
	if Input.is_action_just_pressed("place_beacon"):
		_try_place_beacon()
	if not GameState.is_dream():
		ghost.visible = false
		if Input.is_action_just_pressed("remove_block") and _toggle_aimed_door():
			return
		if (GameState.selected_is("pickaxe") or GameState.selected_is("pickaxe2") or GameState.get_selected_item().get("id","")=="") and (Input.is_action_pressed("place_block") or Input.is_action_pressed("remove_block")):
			_tick_mining(delta)
			return
		_mine_elapsed = 0.0
		_mine_cell = Vector3i(99999,99999,99999)
		if Input.is_action_just_pressed("remove_block") and _toggle_aimed_door():
			return
		if _place_cooldown <= 0.0 and Input.is_action_just_pressed("place_block"):
			if GameState.selected_is("heal1") or GameState.selected_is("heal2"):
				GameState.use_heal(str(GameState.get_selected_item().id))
			elif GameState.selected_is("sword") or GameState.selected_is("sword2") or GameState.selected_is("sword3"):
				_try_sword()
				_place_cooldown = SWORD_COOLDOWN
			elif GameState.selected_is("torch"):
				_try_place_torch()
				_place_cooldown = 0.16
			elif GameState.selected_is("pickaxe") or GameState.selected_is("pickaxe2"):
				_try_mine_wake()
				_place_cooldown = 0.18
			elif GameState.selected_is("anaconda_egg"):
				_try_summon_anaconda()
				_place_cooldown = 0.5
			elif GameState.is_placeable_block(str(GameState.get_selected_item().get("id", ""))):
				_try_place_wake_item()
				_place_cooldown = 0.16
		elif _place_cooldown <= 0.0 and Input.is_action_just_pressed("remove_block"):
			if GameState.selected_is("pickaxe") or GameState.selected_is("pickaxe2"):
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
	for item_kind in DREAM_ITEM_BLOCKS:
		if GameState.selected_is(item_kind):
			if not GameState.consume_item(item_kind, 1):
				GameState.set_hint("Нет «%s» в инвентаре сна." % GameState.block_display_name(item_kind))
				return
			kind = item_kind
			break
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var facing := posmod(roundi(atan2(-forward.x,-forward.z)/(PI/2.0)),4)
	if GameState.place_dream_block(cell, kind, facing):
		dream_voxels.sync_cells([cell])
		if kind != "drift":
			GameState.set_hint("%s [%d,%d,%d]. Заякорь гвоздём, чтобы унести в явь." % [GameState.block_display_name(kind), cell.x, cell.y, cell.z])
		else:
			GameState.set_hint("Дрейф-блок [%d,%d,%d]" % [cell.x, cell.y, cell.z], false)
	elif kind != "drift":
		GameState.add_item_count(kind, 1)


## Предметы, которые во сне ставятся как блоки (иначе ставится бесплатный дрейф-блок).
const DREAM_ITEM_BLOCKS := ["workbench", "bed", "lathe", "sawmill", "alchemy", "idea_catcher", "chest", "door", "ground", "hill", "dirt", "stone", "deep_stone", "log", "leaves", "planks", "ruin", "mossy_ruin", "sand"]


func _try_remove() -> void:
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null or not (collider.has_meta("voxel_cell") or collider.has_meta("placed_chunk")):
		return
	if not bool(collider.get_meta("is_dream")):
		return
	var cell: Vector3i = GameState.ray_cell(aim)
	if GameState.remove_dream_block(cell):
		dream_voxels.remove_block(cell)
		GameState.set_hint("Снят блок [%d,%d,%d]" % [cell.x, cell.y, cell.z], false)


func _try_mine_wake() -> void:
	_play_tool_swing()
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var collider = aim["collider"]
	if collider == null:
		return
	if collider.has_meta("voxel_cell") or collider.has_meta("placed_chunk"):
		if bool(collider.get_meta("is_dream")):
			return
		var cell: Vector3i = GameState.ray_cell(aim)
		if GameState.mine_wake_block(cell):
			var kind := str(GameState.last_mined_kind)
			for vox in get_tree().get_nodes_in_group("voxel_world"):
				if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
					vox.remove_block(cell)
			_finish_mine(cell, kind)
		return
	var hit_pos: Vector3 = aim.get("position", Vector3.ZERO)
	var normal: Vector3 = aim.get("normal", Vector3.UP)
	var inside: Vector3 = hit_pos - normal * 0.05
	var gcell := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	if collider.has_meta("terrain_chunk"):
		# v0.5: один StaticBody на чанк — клетку определяем по точке попадания.
		var cm := _wake_chunks()
		if cm == null:
			return
		var kind: String = cm.terrain_kind_at(gcell)
		if kind == "":
			return
		_mine_terrain_cell(gcell, kind)
		return
	if collider.has_meta("terrain_cell"):
		var tcell: Vector3i = collider.get_meta("terrain_cell")
		var tkind := str(collider.get_meta("terrain_kind")) if collider.has_meta("terrain_kind") else "hill"
		_mine_terrain_cell(tcell, tkind)
		return


func _wake_chunks() -> Node:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			return cm
	return null


func _try_place_beacon() -> void:
	## Маяк (G): ставится в яви на точку прицела — высокий световой столб, виден издалека.
	if GameState.is_dream():
		GameState.set_hint("Маяк ставится в яви.")
		return
	var vox := _wake_voxels()
	if vox == null:
		return
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var cell: Vector3i = vox.world_to_cell(aim["position"] + aim["normal"] * 0.51)
	if not _wake_cell_free(cell):
		return
	if not GameState.consume_item("beacon", 1):
		GameState.set_hint("Нет маяков. Крафт во сне: %d осыпи + 1 реагент3." % GameState.BEACON_CRAFT_DUST)
		return
	if GameState.place_wake_block(cell, "beacon"):
		vox.sync_cells([cell])
		GameState.set_hint("Маяк установлен.")
	else:
		GameState.add_item_count("beacon", 1)


func _mine_terrain_cell(cell: Vector3i, kind: String) -> void:
	if GameState.is_dream():
		return
	if not GameState.selected_is("pickaxe") and not GameState.selected_is("pickaxe2") and GameState.get_selected_item().get("id","")!="":
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
	var mined_tool := str(GameState.get_selected_item().get("id",""))
	GameState.wear_tool(1)
	Sfx.play("break_" + Mining.material(kind), get_tree().root)
	if Mining.drops(kind,mined_tool):
		_spawn_block_pickup(cell,kind)
	var host := _wake_world()
	# v0.6: решение о боссе брошено на прошлом блоке (и объявлено в чате) — спавним сейчас.
	if GameState.on_block_mined() and host:
		var boss_script: GDScript = load("res://scripts/block_mother.gd")
		boss_script.spawn_near(host, cell)


func _wake_voxels() -> Node3D:
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if not bool(vox.get("is_dream_layer")):
			return vox
	return null


func _try_summon_anaconda() -> Node:
	## v0.7: ЛКМ с Яйцом Анаконды в руке ночью в яви — призыв босса (яйцо тратится, кулдауна нет).
	var script: GDScript = load("res://scripts/boss_anaconda.gd")
	return script.summon_with_egg(_wake_world(), player, _wake_chunks())


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
	if not _wake_cell_free(cell):
		return
	if not GameState.consume_item("torch", 1):
		return
	if GameState.place_wake_block(cell, "torch"):
		vox.sync_cells([cell])
	else:
		GameState.add_item("torch", "Факел", 1)

func _wake_cell_free(cell: Vector3i) -> bool:
	## v0.7: ставить можно и под землёй (до y=-30), но не внутрь твёрдой клетки и не в игрока.
	if cell.y < MIN_PLACE_Y:
		return false
	var cm := _wake_chunks()
	if cm and cm.has_method("is_cell_solid") and bool(cm.is_cell_solid(cell)):
		return false
	if player:
		var pp := player.global_position
		var pc := Vector3i(floori(pp.x), floori(pp.y + 0.1), floori(pp.z))
		if cell == pc or cell == pc + Vector3i.UP:
			return false
	return true


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
	var drop: CharacterBody3D = script.new()
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
	if not _wake_cell_free(cell) or (GameState.shape_part(id) != "" and not _wake_cell_free(cell + GameState.part_offset(id))):
		return
	if not GameState.consume_placeable(id):
		return
	if GameState.place_wake_block(cell, id):
		vox.sync_cells([cell])
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
	var s2 := GameState.selected_is("sword2")
	var reach := SWORD2_REACH if s2 else SWORD_REACH
	var dmg := SWORD3_DAMAGE if GameState.selected_is("sword3") else (SWORD2_DAMAGE if s2 else SWORD_DAMAGE)
	last_sword_damage = dmg
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if n.has_method("get") and bool(n.get("frozen") if "frozen" in n else false):
			pass
		if "frozen" in n and bool(n.frozen):
			continue
		if "visible" in n and not bool(n.visible):
			continue
		var center: Vector3 = (n as Node3D).global_position
		if n.has_method("hit_center"):
			center = n.hit_center()
		var to: Vector3 = center - origin
		var r: float = float(n.get("hit_radius")) if "hit_radius" in n else 0.0
		var dist := to.length() - r
		if dist > reach or to.length() < 0.05:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		var dir := flat.normalized() if flat.length() > 0.05 else forward
		if dir.dot(forward) < 0.15:
			continue
		if n.has_method("take_damage"):
			n.take_damage(dmg)
			hit += 1
	last_sword_hits = hit
	if hit > 0:
		GameState.wear_tool(1)


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
	var bt: GDScript = load("res://scripts/block_tex.gd")
	for id in ["pickaxe", "pickaxe2", "sword", "sword2", "sword3"]:
		var tool := MeshInstance3D.new()
		tool.name = id.capitalize() + "View"
		tool.mesh = bt.tool_mesh(id)
		tool.position = Vector3(0.02, -0.1, 0.02)
		if id.begins_with("sword"):
			tool.position = Vector3(0.02,0.04,-0.12)
		tool.rotation_degrees = Vector3(-20, 20, -28)
		tool.scale = Vector3.ONE * 0.6
		if id.begins_with("pickaxe"):
			tool.position = Vector3(0.08,-0.16,-0.08)
			tool.rotation_degrees = Vector3(-12,-24,25)
			tool.scale = Vector3.ONE*0.58
		if id=="sword3":
			tool.scale=Vector3.ONE*0.38;tool.rotation_degrees=Vector3(-12,-10,20);tool.position=Vector3(0.02,-0.04,-0.19)
		_hand_root.add_child(tool)
		match id:
			"pickaxe": _pickaxe_view = tool
			"pickaxe2": _pickaxe2_view = tool
			"sword": _sword_view = tool
			"sword2": _sword2_view = tool
			"sword3": _sword3_view = tool
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
	var show_pick := GameState.selected_is("pickaxe") or GameState.selected_is("pickaxe2")
	var show_sword := GameState.selected_is("sword")
	var show_s2 := GameState.selected_is("sword2")
	if _pickaxe_view:
		_pickaxe_view.visible = GameState.selected_is("pickaxe")
	if _pickaxe2_view:
		_pickaxe2_view.visible = GameState.selected_is("pickaxe2")
	if _sword_view:
		_sword_view.visible = show_sword
	if _sword2_view:
		_sword2_view.visible = show_s2
	if _sword3_view: _sword3_view.visible = GameState.selected_is("sword3")
	_hand_root.visible = (show_pick or show_sword or show_s2 or GameState.selected_is("sword3")) and not GameState.ui_blocked()


func _play_tool_swing() -> void:
	_ensure_hand_tools()
	if _hand_root == null or player == null:
		return
	_update_hand_tools()
	_hand_root.rotation_degrees = Vector3(62, 6, -22)
	var tw := player.create_tween()
	tw.tween_property(_hand_root, "rotation_degrees", Vector3(-48, 18, 14), 0.14)
	tw.tween_property(_hand_root, "rotation_degrees", Vector3(12, 0, -8), 0.12)


const Mining := preload("res://scripts/mining_rules.gd")
const Sfx := preload("res://scripts/sfx.gd")

func _toggle_aimed_door() -> bool:
	var aim := _aim()
	var collider = aim.get("collider")
	return GameState.toggle_door(collider.get_meta("voxel_cell")) if collider and collider.has_meta("voxel_cell") else false

func _tick_mining(delta: float) -> void:
	if _place_cooldown > 0:
		return
	var aim := _aim()
	if not aim.get("hit", false):
		_mine_elapsed = 0.0
		return
	var collider = aim.get("collider")
	if collider == null:
		return
	var tool := str(GameState.get_selected_item().get("id", ""))
	if collider.is_in_group("enemy") or collider.get_parent().is_in_group("enemy"):
		var target = collider if collider.is_in_group("enemy") else collider.get_parent()
		if target.has_method("take_damage"):
			target.take_damage(6 if tool=="pickaxe2" else (2 if tool=="pickaxe" else 1))
			GameState.wear_tool(2)
			_play_tool_swing()
			_place_cooldown = 0.5
		return
	var cell: Vector3i
	var kind := ""
	if collider.has_meta("voxel_cell") or collider.has_meta("placed_chunk"):
		cell = GameState.ray_cell(aim)
		cell = GameState.root_cell(GameState.wake_blocks, cell)
		kind = str(GameState.wake_blocks.get(cell, {}).get("kind", ""))
	elif collider.has_meta("terrain_chunk") or collider.has_meta("terrain_cell"):
		var inside: Vector3 = aim["position"] - aim["normal"] * 0.05
		cell = Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
		var cm := _wake_chunks()
		if cm:
			kind = cm.terrain_kind_at(cell)
	else:
		return
	if cell != _mine_cell or tool != _mine_tool:
		_mine_cell = cell
		_mine_tool = tool
		_mine_elapsed = 0.0
	if kind == "":
		return
	var duration := Mining.seconds(kind,tool)
	if not is_finite(duration): return
	_mine_elapsed += delta
	if cracks: cracks.show_progress(cell,_mine_elapsed/duration)
	if _mine_swing_t<=0.0:
		_mine_swing_t = 0.35
		_play_tool_swing()
	if _mine_elapsed >= duration:
		_try_mine_wake()
		_mine_elapsed = 0.0
		_place_cooldown = 0.1
