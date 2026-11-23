extends Node
## Режим стройки во сне: размещение / удаление блоков лучом камеры.

var player: CharacterBody3D
var dream_voxels: Node3D
var ghost: MeshInstance3D
var _place_cooldown := 0.0
var _hand_root: Node3D = null
var _pickaxe_view: Node3D = null
var _sword_view: Node3D = null
const SWORD_DAMAGE := 8
const SWORD_COOLDOWN := 0.45
const SWORD_REACH := 2.6
## v0.7: Меч2 — 25 урона, дальность ×1.25.
const SWORD2_DAMAGE := 14
const SWORD3_DAMAGE := 24
const SWORD2_REACH := SWORD_REACH * 1.25
const MIN_PLACE_Y := -30
var _pickaxe2_view: Node3D = null
var _sword2_view: Node3D = null
var _sword3_view: Node3D = null
var viewmodel: Node3D = null
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
	add_to_group("build_controller")
	_make_ghost()
	cracks = load("res://scripts/mining_cracks.gd").new()
	add_child(cracks)
	_ensure_hand_tools()
	if not GameState.wake_cell_removed.is_connected(_on_wake_cell_removed):
		GameState.wake_cell_removed.connect(_on_wake_cell_removed)


func _on_wake_cell_removed(cell: Vector3i) -> void:
	## v0.22: опору сломал кто угодно — игрок, моб, Мать — факел без опоры падает предметом.
	call_deferred("drop_unsupported_torches", cell)


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
	_temp_hand_t = maxf(0.0, _temp_hand_t - delta)
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
		update_torch_rings()
		# v0.23: схема v0.22 — ЛКМ: удар и добыча (с любым предметом в руке, удар в воздух тоже);
		# ПКМ: использовать (дверь, яйцо) и поставить (блок, факел).
		if Input.is_action_just_pressed("drop_item"):
			drop_selected(Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))
		var sel := str(GameState.get_selected_item().get("id", ""))
		var sword := sel == "sword" or sel == "sword2" or sel == "sword3"
		if Input.is_action_just_pressed("use_place") and _place_cooldown <= 0.0:
			if _toggle_aimed_door():
				_arms("use")
				_place_cooldown = 0.16
			elif sel == "anaconda_egg":
				_try_summon_anaconda()
				_arms("use")
				_place_cooldown = 0.5
			elif sel == "torch":
				_try_place_torch()
				_arms("place")
				_place_cooldown = 0.16
			elif GameState.is_placeable_block(sel):
				_try_place_wake_item()
				_arms("place")
				_place_cooldown = 0.16
			return
		if sword:
			_reset_mining()
			if _place_cooldown <= 0.0 and Input.is_action_just_pressed("attack_break"):
				_try_sword()   # замах всегда, даже в воздух
				_place_cooldown = SWORD_COOLDOWN
			return
		if Input.is_action_just_pressed("attack_break") and _place_cooldown <= 0.0:
			if _try_pick_up_torch():
				_arms("break")
				_place_cooldown = 0.16
				return
			if not _aim().get("hit", false):
				swing_air()
				return
		if Input.is_action_pressed("attack_break"):
			_tick_mining(delta)
			return
		_reset_mining()
		return
	_update_ghost()
	# Сон (как в v0.22): ПКМ — поставить, ЛКМ — снять; дверь — ПКМ по двери.
	if Input.is_action_just_pressed("use_place") and _place_cooldown <= 0.0:
		if not _toggle_aimed_door():
			_try_place()
			_arms("place")
		_place_cooldown = 0.12
	if Input.is_action_just_pressed("attack_break") and _place_cooldown <= 0.0:
		_try_remove()
		_arms("break")
		_place_cooldown = 0.12


## v0.23: выбросить предмет из выбранного слота: Q — одну штуку, Ctrl+Q — всю стопку.
const DROP_SPEED := 5.0
const DROP_UP := 2.2


func drop_selected(all: bool = false) -> Node3D:
	if not GameState.can_drop_items():
		return null
	var slot := GameState.get_selected_item()
	var n := int(slot.get("count", 0)) if all else 1
	var payload := GameState.take_from_slot(GameState.selected_slot, n)
	if payload.is_empty():
		return null
	_arms("use")
	return throw_payload(payload)


func throw_payload(payload: Dictionary, delay: float = GameState.DROP_PICKUP_DELAY) -> Node3D:
	## Вылетает из-под камеры вперёд по взгляду. Подбор обычный (автоподбор), но не раньше delay секунд.
	if payload.is_empty() or int(payload.get("count", 0)) <= 0:
		return null
	var host := _wake_world()
	if host == null or player == null:
		return null
	var cam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var fwd := -player.global_transform.basis.z
	var origin := player.global_position + Vector3(0, 1.3, 0)
	if cam:
		fwd = -cam.global_transform.basis.z
		origin = cam.global_position - Vector3(0, 0.25, 0)
	var start := origin + fwd * 0.45
	var rec := GameState.register_drop(payload, start)
	var vel := fwd * DROP_SPEED + Vector3(0, DROP_UP, 0)
	var node := spawn_drop(rec, vel, delay)
	GameState.drops_thrown += int(payload.get("count", 0))
	return node


func spawn_drop(rec: Dictionary, vel: Vector3 = Vector3.ZERO, delay: float = 0.0) -> Node3D:
	var host := _wake_world()
	if host == null:
		return null
	var script: GDScript = load("res://scripts/dropped_item.gd")
	var d: CharacterBody3D = script.new()
	d.setup(rec, vel, delay)
	d.position = rec["pos"]
	host.add_child(d)
	return d


func spawn_saved_drops() -> int:
	for n in get_tree().get_nodes_in_group("dropped_item"):
		n.queue_free()
	var c := 0
	for rec in GameState.dropped_items:
		if spawn_drop(rec) != null:
			c += 1
	return c


## v0.23: удар в воздух — замах рукой/предметом без цели, с перезарядкой.
const AIR_SWING_COOLDOWN := 0.28
var air_swings := 0


func swing_air() -> void:
	air_swings += 1
	_play_tool_swing()
	_place_cooldown = AIR_SWING_COOLDOWN




func _reset_mining() -> void:
	_mine_elapsed = 0.0
	_mine_cell = Vector3i(99999,99999,99999)


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
	ghost.visible = placement_supported(cell, GameState.is_dream()) # v0.11.1: без опоры — ни призрака, ни блока


func _try_place() -> void:
	## v0.11.1: как в Minecraft — блок ставится только на грань соседнего блока (в воздух нельзя).
	var aim := _aim()
	if not aim.get("hit", false):
		return
	var normal: Vector3 = aim["normal"]
	var hit_pos: Vector3 = aim["position"]
	var place_pos2 := hit_pos + normal * 0.51
	var cell2: Vector3i = dream_voxels.world_to_cell(place_pos2)
	if not placement_supported(cell2, true):
		return
	_last_place_normal = normal
	_place_at(cell2)


func _place_at(cell: Vector3i) -> void:
	# v0.16: без предмета в руке ставится материал палитры Сна (отпечаток) — бесконечно и бесплатно.
	# v0.22: палитра — только из пустого слота 1 (HUD показывает в нём материал и ∞); другие пустые слоты ничего не ставят.
	var kind: String = GameState.dream_palette_kind()
	var from_palette := true
	var sel_id := str(GameState.get_selected_item().get("id", ""))
	if DREAM_ITEM_BLOCKS.has(sel_id):
		if not GameState.consume_item(sel_id, 1):
			GameState.set_hint("Нет «%s» в инвентаре Сна." % GameState.block_display_name(sel_id))
			return
		kind = sel_id
		from_palette = false
	elif not GameState.palette_slot_active():
		if sel_id == "":
			GameState.set_hint("Слот пуст. Материал Сна ставится из слота 1.", false)
		return
	var forward: Vector3 = -player.camera.global_transform.basis.z
	var facing := posmod(roundi(atan2(-forward.x,-forward.z)/(PI/2.0)),4)
	var placed_cells: Array = []
	if from_palette:
		placed_cells = GameState.dream_tool_place(cell, kind) # v0.17: зеркало + история отмены
	elif GameState.place_dream_block(cell, kind, facing):
		placed_cells = [cell]
	if placed_cells.has(cell):
		if kind == "torch": _attach_dream_torch(cell)
		if kind == "drift" and GameState.heart_structure and Input.is_action_pressed("sprint"):
			placed_cells.append_array(mass_place_row(cell, facing))
		dream_voxels.sync_cells(placed_cells)
		if not from_palette:
			GameState.set_hint("%s. Заякорь, чтобы унести в Явь." % GameState.block_display_name(kind))
		else:
			GameState.set_hint("%s%s" % [GameState.block_display_name(kind), GameState.palette_stock_text(kind)], false)
	elif not from_palette:
		GameState.add_item_count(kind, 1)


var _last_place_normal := Vector3.UP


func _attach_dream_torch(cell: Vector3i) -> void:
	## v0.22.1: факел Сна на стене — запоминаем опору, при переносе в Явь он останется настенным.
	var n := Vector3i(roundi(_last_place_normal.x), roundi(_last_place_normal.y), roundi(_last_place_normal.z))
	if n.y != 0 or n == Vector3i.ZERO or not GameState.dream_blocks.has(cell): return
	var sup := cell - n
	if GameState.dream_blocks.has(sup) and str(GameState.dream_blocks[sup].get("kind", "")) != "torch":
		GameState.dream_blocks[cell]["attach"] = [sup.x, sup.y, sup.z]


func mass_place_row(cell: Vector3i, facing: int) -> Array:
	## v0.12 (Сердце структуры): Shift+ПКМ дрейф-блоком — ряд из 5 поперёк взгляда. Каждый следующий опирается на предыдущий.
	var right := Vector3i(1, 0, 0) if facing % 2 == 0 else Vector3i(0, 0, 1)
	var out: Array = []
	for dir in [right, -right]:
		var c: Vector3i = cell
		for _i in range(2):
			c = c + dir
			if not GameState.dream_blocks.has(c) and placement_supported(c, true) and GameState.place_dream_block(c, "drift", facing):
				out.append(c)
			else:
				break
	return out


## Предметы, которые во сне ставятся как блоки (иначе ставится бесплатный дрейф-блок).
const DREAM_ITEM_BLOCKS := ["workbench", "bed", "lathe", "sawmill", "alchemy", "idea_catcher", "chest", "door", "dirt", "stone", "deep_stone", "log", "leaves", "planks", "ruin", "mossy_ruin", "sand", "strut"]


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
	var removed: Array = GameState.dream_tool_remove(cell) # v0.17: палитра — с зеркалом и отменой
	for c in removed:
		dream_voxels.remove_block(c)
	if not removed.is_empty():
		GameState.set_hint("Снят блок%s · Z — отменить" % ((" · +%d зеркально" % (removed.size() - 1)) if removed.size() > 1 else ""), false)


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
		var tkind := str(collider.get_meta("terrain_kind")) if collider.has_meta("terrain_kind") else "dirt"
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
	if not _wake_cell_free(cell) or not placement_supported(cell, false):
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
	if GameState.on_block_mined_at(cell, kind) and host:
		var boss_script: GDScript = load("res://scripts/block_mother.gd")
		if boss_script.spawn_near(host, cell) != null:
			GameState.chat("Мать блоков вырвалась на поверхность над твоей шахтой! Поднимайся — бой на открытой арене.", Color(1.0, 0.35, 0.35))


func _wake_voxels() -> Node3D:
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if not bool(vox.get("is_dream_layer")):
			return vox
	return null


func _try_summon_anaconda() -> Node:
	## v0.7 (v0.22: ПКМ): с Яйцом Анаконды в руке ночью в яви — призыв босса (яйцо тратится, кулдауна нет).
	var script: GDScript = load("res://scripts/boss_anaconda.gd")
	return script.summon_with_egg(_wake_world(), player, _wake_chunks())


func _try_pick_up_torch() -> bool:
	## v0.13 (v0.22: ЛКМ): снять свой факел (с факелом в руке) — без кирки и без потерь.
	var aim := _aim()
	if not aim.get("hit", false):
		return false
	var collider = aim["collider"]
	if collider == null or not (collider.has_meta("voxel_cell") or collider.has_meta("placed_chunk")):
		return false
	if bool(collider.get_meta("is_dream")):
		return false
	var cell: Vector3i = GameState.ray_cell(aim)
	if not GameState.pick_up_torch(cell):
		return false
	var vox := _wake_voxels()
	if vox:
		vox.remove_block(cell)
	Sfx.play("break_wood", get_tree().root)
	GameState.set_hint("Факел снят — поставь его в другое место.", false)
	return true


# ---------------------------------------------------------------- v0.15: радиус факела
const TORCH_RING_R := 3.5          # = boss_anaconda.TORCH_RADIUS (проверяется в смоуке)
const TORCH_RING_MAX := 10
const TORCH_RING_NEAR := 16.0
var _rings_root: Node3D
var _rings: Array[MeshInstance3D] = []
var ring_state := {"ghost": false, "ghost_cell": Vector3i.ZERO, "overlap": 0, "existing": 0}


func _ring_mesh(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = TORCH_RING_R - 0.07
	tm.outer_radius = TORCH_RING_R + 0.07
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.albedo_color = col
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _ring(i: int) -> MeshInstance3D:
	if _rings_root == null or not is_instance_valid(_rings_root):
		_rings_root = Node3D.new()
		_rings_root.name = "TorchRings"
		var host: Node = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
		host.add_child(_rings_root)
		_rings.clear()
	while _rings.size() <= i:
		var r := _ring_mesh(Color(1.0, 0.62, 0.2, 0.45))
		_rings_root.add_child(r)
		_rings.append(r)
	return _rings[i]


func _hide_rings() -> void:
	for r in _rings:
		if is_instance_valid(r):
			r.visible = false
	ring_state.ghost = false


func update_torch_rings() -> void:
	## Пока в руке факел: кольцо света на месте установки (зелёное, если даст перекрёстный огонь
	## с уже стоящим факелом) и тусклые кольца у ближайших поставленных факелов.
	if not GameState.selected_is("torch") or GameState.is_dream():
		_hide_rings()
		return
	var origin: Vector3 = player.global_position if player else Vector3.ZERO
	var near: Array = []
	for c in GameState.torch_cells():
		var wp := Vector3(c) + Vector3(0.5, 0.0, 0.5)
		if wp.distance_to(origin) <= TORCH_RING_NEAR:
			near.append(wp)
	near.sort_custom(func(a, b): return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	near = near.slice(0, TORCH_RING_MAX)
	var idx := 1
	for wp in near:
		var r := _ring(idx)
		r.global_position = wp + Vector3(0, 0.06, 0)
		(r.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.62, 0.2, 0.4)
		r.visible = true
		idx += 1
	for j in range(idx, _rings.size()):
		_rings[j].visible = false
	ring_state.existing = near.size()
	var g := _ring(0)
	var aim := _aim()
	var vox := _wake_voxels()
	g.visible = false
	ring_state.ghost = false
	if aim.get("hit", false) and vox:
		var cell: Vector3i = vox.world_to_cell(Vector3(aim["position"]) + Vector3(aim["normal"]) * 0.51)
		if _wake_cell_free(cell) and placement_supported(cell, false):
			var gp := Vector3(cell) + Vector3(0.5, 0.06, 0.5)
			var overlap := 0
			for wp in near:
				if Vector2(wp.x - gp.x, wp.z - gp.z).length() <= TORCH_RING_R * 2.0:
					overlap += 1
			g.global_position = gp
			(g.material_override as StandardMaterial3D).albedo_color = Color(0.35, 1.0, 0.45, 0.8) if overlap > 0 else Color(1.0, 0.9, 0.35, 0.75)
			g.visible = true
			ring_state.ghost = true
			ring_state.ghost_cell = cell
			ring_state.overlap = overlap


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
		return # v0.11.1: в воздух ставить нельзя
	if not _wake_cell_free(cell) or GameState.wake_blocks.has(cell):
		return
	# v0.22: факел держится как в Minecraft — на верхней грани блока или на стене (не на потолке и не на факеле).
	var attach := torch_attach_for(cell, Vector3(aim["normal"]))
	if attach.y == -9999:
		return
	if not GameState.consume_item("torch", 1):
		return
	if GameState.place_wake_block(cell, "torch"):
		GameState.wake_blocks[cell]["attach"] = [attach.x, attach.y, attach.z]
		vox.sync_cells([cell])
	else:
		GameState.add_item("torch", "Факел", 1)


func cell_solid_wake(c: Vector3i) -> bool:
	## Твёрдая клетка Яви для опоры факела: поставленный блок (не факел, не открытая дверь) или рельеф.
	if GameState.wake_blocks.has(c):
		return GameState.wake_solid(c)
	var cm := _layer_chunks(false)
	return cm != null and cm.has_method("is_cell_solid") and bool(cm.is_cell_solid(c))


func torch_attach_for(cell: Vector3i, normal: Vector3) -> Vector3i:
	## Возвращает клетку-опору или y=-9999, если факел тут не держится.
	var n := Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))
	if n.y < 0:
		return Vector3i(0, -9999, 0)               # потолок
	var sup := cell - n if n != Vector3i.ZERO else cell + Vector3i.DOWN
	if not cell_solid_wake(sup):
		sup = cell + Vector3i.DOWN                 # запасной вариант — пол
		if not cell_solid_wake(sup):
			return Vector3i(0, -9999, 0)
	return sup


func torch_supported(c: Vector3i) -> bool:
	var d: Dictionary = GameState.wake_blocks.get(c, {})
	if str(d.get("kind", "")) != "torch":
		return true
	var at = d.get("attach", null)
	if at is Array and (at as Array).size() == 3:
		return cell_solid_wake(Vector3i(int(at[0]), int(at[1]), int(at[2])))
	# старые сейвы без опоры: пол или любая боковая стена
	for dd in [Vector3i.DOWN, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if cell_solid_wake(c + dd):
			return true
	return false


func drop_unsupported_torches(removed: Vector3i) -> int:
	## v0.22: блок под/за факелом убрали — факел падает и выпадает предметом.
	var n := 0
	var vox := _wake_voxels()
	for d in _NEIGHBOURS6:
		var t: Vector3i = removed + d
		if str(GameState.wake_blocks.get(t, {}).get("kind", "")) == "torch" and not torch_supported(t):
			if GameState.remove_torch(t):
				if vox: vox.remove_block(t)
				_spawn_block_pickup(t, "torch")
				n += 1
	return n

const _NEIGHBOURS6 := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]

func _layer_chunks(dream: bool) -> Node:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")) == dream and not bool(cm.get("panorama_mode")):
			return cm
	return null


func placement_supported(cell: Vector3i, dream: bool) -> bool:
	## v0.11.1: опора как в Minecraft — хотя бы один из 6 соседей твёрдый (рельеф или поставленный блок
	## этого мира; факел и открытая дверь опорой не считаются). Генерация лагеря/платформ идёт мимо этой проверки.
	var cm := _layer_chunks(dream)
	for d in _NEIGHBOURS6:
		var n: Vector3i = cell + d
		if dream:
			if GameState.dream_blocks.has(n):
				return true
			if cm and cm.has_method("is_cell_solid") and not GameState.wake_blocks.has(n) and bool(cm.is_cell_solid(n)):
				return true
		else:
			if GameState.wake_solid(n):
				return true
			if cm and cm.has_method("is_cell_solid") and bool(cm.is_cell_solid(n)):
				return true
	return false


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
		return # v0.11.1: в воздух ставить нельзя
	if not _wake_cell_free(cell) or not placement_supported(cell, false) or (GameState.shape_part(id) != "" and not _wake_cell_free(cell + GameState.part_offset(id))):
		return
	if not GameState.consume_placeable(id):
		return
	if GameState.place_wake_block(cell, id):
		vox.sync_cells([cell])
	else:
		GameState.add_mined_block(id, 1)


func _try_sword() -> void:
	_play_sword_swing()
	_arms("attack")
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
		if n.has_method("receive_weapon_hit"):
			# v0.12: боссы различают оружие; feedback по результату (без ложных попаданий и без shake).
			var res: Dictionary = n.receive_weapon_hit(dmg, str(GameState.get_selected_item().get("id", "sword")))
			_combat_feedback(res, n)
			if int(res.get("dealt", 0)) > 0 or bool(res.get("bounce", false)):
				hit += 1
		elif n.has_method("take_damage"):
			n.take_damage(dmg)
			_combat_feedback({"dealt": dmg, "bounce": false}, n)
			hit += 1
	last_sword_hits = hit
	if hit > 0:
		GameState.wear_tool(1)


func _play_sword_swing() -> void:
	_play_tool_swing()


func _ensure_hand_tools() -> void:
	## v0.11: инструменты в руке — единый ViewModelRig (scripts/viewmodel_rig.gd), без хардкода трансформов здесь.
	if player == null or not player.has_node("CameraPivot/Camera3D"):
		return
	if viewmodel != null and is_instance_valid(viewmodel):
		return
	var cam: Node3D = player.get_node("CameraPivot/Camera3D")
	viewmodel = load("res://scripts/viewmodel_rig.gd").new()
	viewmodel.player = player
	cam.add_child(viewmodel)
	_hand_root = viewmodel.hand_root
	_pickaxe_view = viewmodel.models.get("pickaxe")
	_pickaxe2_view = viewmodel.models.get("pickaxe2")
	_sword_view = viewmodel.models.get("sword")
	_sword2_view = viewmodel.models.get("sword2")
	_sword3_view = viewmodel.models.get("sword3")
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
	if viewmodel == null:
		return
	var id := str(GameState.get_selected_item().get("id", ""))
	if _temp_hand_t > 0.0:
		id = _temp_hand
	if GameState.ui_blocked() or GameState.transfer_ui_open:
		id = ""
	viewmodel.set_tool(id)


## v0.23: на время действия в кисти — другой предмет (зелье при H), анимацию даёт рука.
var _temp_hand := ""
var _temp_hand_t := 0.0


func show_in_hand(id: String, seconds: float, action: String) -> void:
	_temp_hand = id
	_temp_hand_t = seconds
	_update_hand_tools()
	_arms(action)


func _arms(kind: String) -> void:
	## v0.22: анимация рук от первого лица (attack, break, place, use, jump, sleep, wake).
	_ensure_hand_tools()
	if viewmodel and viewmodel.has_method("play_action"):
		viewmodel.play_action(kind)


func _play_tool_swing() -> void:
	_ensure_hand_tools()
	if viewmodel == null or player == null:
		return
	_update_hand_tools()
	viewmodel.play_swing("attack" if GameState.selected_is("sword") or GameState.selected_is("sword2") or GameState.selected_is("sword3") else "break")


func _combat_feedback(res: Dictionary, target: Node) -> void:
	## Подтверждение попадания или отскока. Камеру не трясём.
	var bounce := bool(res.get("bounce", false))
	var dealt := int(res.get("dealt", 0))
	GameState.hit_marker.emit(hit_marker_kind(res))
	if dealt <= 0 and not bounce:
		return
	if viewmodel and viewmodel.has_method("play_recoil"):
		viewmodel.play_recoil(not bounce)
	if bounce:
		Sfx.play("break_stone", get_tree().root if is_inside_tree() else null)
	else:
		Sfx.play("break_wood", get_tree().root if is_inside_tree() else null)
	if target and target.has_method("on_hit_feedback"):
		target.on_hit_feedback(res)
	if dealt > 0 and knockback_enabled and target is CharacterBody3D and player and not _is_boss(target):
		var tool := str(GameState.get_selected_item().get("id", ""))
		last_knockback = load("res://scripts/enemy_navigation.gd").apply_knockback(target, player.global_position, float(KNOCKBACK.get(tool, KNOCKBACK[""])))


## v0.22: сила откидывания по оружию (м/с в начале импульса). Боссов не откидывает.
const KNOCKBACK := {"": 4.0, "pickaxe": 4.5, "pickaxe2": 5.0, "sword": 7.0, "sword2": 8.0, "sword3": 9.0}
var knockback_enabled := true
var last_knockback := Vector3.ZERO

static func _is_boss(n: Node) -> bool:
	return n.is_in_group("block_mother") or n.is_in_group("anaconda") or n.is_in_group("boss")


static func hit_marker_kind(res: Dictionary) -> String:
	## v0.15: тип хит-маркера у прицела по результату удара.
	if bool(res.get("killed", false)):
		return "kill"
	if bool(res.get("sealed", false)):
		return "sealed"
	if str(res.get("target", "")) == "scales":
		return "immune"
	if bool(res.get("bounce", false)):
		return "bounce"
	if int(res.get("dealt", 0)) <= 0:
		return "miss"
	if str(res.get("target", "")) == "core":
		return "core"
	return "hit"


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
		if target.has_method("receive_weapon_hit"):
			var res: Dictionary = target.receive_weapon_hit(6 if tool=="pickaxe2" else (2 if tool=="pickaxe" else 1), tool if tool != "" else "hand")
			_combat_feedback(res, target)
			GameState.wear_tool(2)
			_play_tool_swing()
			_place_cooldown = 0.5
		elif target.has_method("take_damage"):
			target.take_damage(6 if tool=="pickaxe2" else (2 if tool=="pickaxe" else 1))
			_combat_feedback({"dealt": 1, "bounce": false}, target)
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


func _heal_key() -> String:
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets and gsets.has_method("key_label"):
		return str(gsets.key_label("use_heal"))
	return "H"
