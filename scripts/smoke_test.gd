extends SceneTree
## Headless smoke v0.6 (+ деревья, сутки 24 мин, луна, клавиши, босс 500 HP, предвестие):\n## v0.5: меню/миры/сиды/инвентарь 9+27/дев-сид + всё из v0.4.5.
## Запуск: godot --headless --path ... -s res://scripts/smoke_test.gd


var _fails: Array = []
var _v08_done := false


func _a(cond: Variant, line: int) -> void:
	if not bool(cond):
		_fails.append(line)
		push_error("SMOKE ASSERT line %d" % line)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("SMOKE: start")
	var gs_script: GDScript = load("res://scripts/game_state.gd")
	var gs: Node = gs_script.new()
	root.add_child(gs)

	gs.reagents = 5
	gs.nails = 2
	gs.wedges = 1
	gs.enter_dream()
	_a(gs.is_dream(), 29)
	for x in range(0, 3):
		for z in range(0, 3):
			gs.place_dream_block(Vector3i(x, 0, z), "drift")
	gs.place_dream_block(Vector3i(1, 1, 1), "drift")
	_a(gs.dream_blocks.size() == 10, 34)
	gs.select_anchor(gs.AnchorType.NAIL)
	_a(gs.try_place_anchor(Vector3i(1, 1, 1)), 36)
	var before_dust: int = gs.dust
	var result: Dictionary = gs.resolve_wake()
	_a(not gs.is_dream(), 39)
	_a(int(result["transferred"]) == 1, 40)
	_a(int(result["dust"]) == 1, 41)
	_a(gs.dust == before_dust + 1, 42)
	_a(gs.wake_blocks.has(Vector3i(1, 1, 1)), 43)
	# v0.7: при пробуждении все блоки сна исчезают (заякоренные уже перенесены).
	_a(gs.dream_blocks.is_empty(), 45)
	gs.enter_dream()
	_a(gs.dream_blocks.is_empty(), 47)
	gs.resolve_wake()
	# Высота ячейки в яви совпадает со сном.
	_a(gs.wake_blocks.has(Vector3i(1, 1, 1)), 50)
	var vw_script: GDScript = load("res://scripts/voxel_world.gd")
	var dv: Node3D = vw_script.new()
	dv.is_dream_layer = true
	var wv: Node3D = vw_script.new()
	wv.is_dream_layer = false
	var height_cell := Vector3i(1, 1, 1)
	_a(dv.cell_to_world(height_cell).is_equal_approx(wv.cell_to_world(height_cell)), 57)
	_a(is_equal_approx(dv.cell_to_world(Vector3i(2, 0, 4)).y, 0.5), 58)
	dv.free()
	wv.free()
	gs.dust = 9
	_a(not gs.craft_recipe("nail", {"is_dream": true}), 60)
	gs.dust = 10
	_a(gs.craft_recipe("nail", {"is_dream": true}), 62)
	_a(not gs.craft_recipe("nail", {"is_dream": false}), 63)
	_a(not gs.craft_recipe("nail", {"at_workbench": true, "is_dream": true}), 64)
	_a(gs.NAIL_CRAFT_DUST == 10, 65)

	# Клин из осыпи — только во сне, не на верстаке
	gs.dust = gs.WEDGE_CRAFT_DUST
	var wedges_before: int = gs.wedges
	_a(gs.craft_recipe("wedge", {"is_dream": true}), 70)
	_a(gs.wedges == wedges_before + 1, 71)
	_a(gs.dust == 0, 72)
	_a(gs.WEDGE_CRAFT_DUST == 60, 73) # v0.11: клин дешевле (был 100)
	gs.dust = gs.ANCHOR3_CRAFT_DUST
	var a3_before: int = gs.anchors3
	_a(gs.craft_recipe("anchor3", {"is_dream": true}), 76)
	_a(gs.anchors3 == a3_before + 1, 77)
	_a(gs.dust == 0, 78)
	_a(gs.ANCHOR3_CRAFT_DUST == 180, 79) # v0.11
	_a(gs.ANCHOR3_SIZE == 9, 80)
	_a(is_equal_approx(gs.CLARITY_DRAIN_PER_SEC, 0.85), 81) # v0.11: ≈118 с
	_a(gs.recipe_defs().size() >= 7, 82)
	_a(not gs.find_recipe("torch").is_empty(), 83)
	_a(not gs.find_recipe("sword").is_empty(), 84)
	_a(not ("макс" in gs.inventory_status_text()), 85)

	# Хардкор-кража (может вернуть dust:N)
	gs.dust = 3
	gs.reagents = 1
	var st: String = gs.steal_resource_hardcore(2)
	_a(st.begins_with("dust"), 91)
	_a(gs.dust == 1, 92)
	gs.dust = 0
	_a(gs.steal_resource_hardcore() == "reagent", 94)
	_a(gs.reagents == 0, 95)
	_a(gs.steal_resource_hardcore() == "none", 96)

	# Типы реагентов и кап 100
	gs.reagent_counts = [0, 0, 0]
	gs.reagents = 0
	_a(gs.add_typed_reagent(1, 50) == 50, 101)
	_a(gs.add_typed_reagent(1, 60) == 50, 102)
	_a(gs.get_reagent_count(1) == 100, 103)
	_a(gs.add_typed_reagent(1, 1) == 0, 104)
	_a(gs.add_typed_reagent(2, 10) == 10, 105)
	_a(gs.add_typed_reagent(3, 7) == 7, 106)
	_a(gs.reagent_type_name(1) == "реагент1", 107)
	_a(gs.reagent_type_name(2) == "реагент2", 108)
	_a(gs.reagent_type_name(3) == "реагент3", 109)
	_a(gs.reagents == 117, 110)
	_a(gs.spend_reagents(5), 111)
	_a(gs.get_reagent_count(1) == 95, 112)
	_a(gs.reagents == 112, 113)

	# Мобы только после второго выхода из сна
	var gs_m: Node = gs_script.new()
	root.add_child(gs_m)
	_a(gs_m.dream_exit_count == 0, 118)
	_a(not gs_m.mobs_unlocked(), 119)
	gs_m.enter_dream()
	gs_m.resolve_wake()
	_a(gs_m.dream_exit_count == 1, 122)
	_a(not gs_m.mobs_unlocked(), 123)
	gs_m.enter_dream()
	gs_m.resolve_wake()
	_a(gs_m.dream_exit_count == 2, 126)
	_a(gs_m.mobs_unlocked(), 127)

	# Инвентарь 9+27, якоря/маяки — отдельно (вертикальная полоса)
	_a(gs.item_slots.size() == 36, 130)
	_a(gs.HOTBAR_SIZE == 9 and gs.MAIN_INV_SIZE == 27, 131)
	_a(_slot_of(gs, "nail") == -1 and _slot_of(gs, "anchor3") == -1, 132)
	gs.select_item_slot(8)
	_a(gs.selected_slot == 8, 134)
	gs.cycle_item_slot(1)
	_a(gs.selected_slot == 0, 136)
	gs.cycle_item_slot(-1)
	_a(gs.selected_slot == 8, 138)
	var added_at: int = gs.add_item("test_tool", "Тест", 1)
	_a(added_at >= 0 and added_at < 9, 140)
	_a(int(gs.item_slots[added_at].get("count")) == 1, 141)

	# Верстак и кирка
	var gs_c: Node = gs_script.new()
	root.add_child(gs_c)
	gs_c.enter_dream()
	gs_c.reagent_counts = [10, 0, 0]
	gs_c.reagents = 10
	_a(gs_c.craft_recipe("workbench", {"is_dream": true}), 149)
	_a(_slot_of(gs_c, "workbench") >= 0, 150)
	_a(not gs_c.craft_recipe("pickaxe", {"at_workbench": false}), 151)
	var wb := Vector3i(8, 0, 8)
	_a(gs_c.place_dream_block(wb, "workbench"), 153)
	gs_c.nails = 2
	gs_c.reagent_counts = [3, 2, 3]
	gs_c.reagents = 8
	gs_c.clarity = 100.0
	gs_c.select_anchor(gs_c.AnchorType.NAIL)
	_a(gs_c.try_place_anchor(wb), 159)
	var wb_res: Dictionary = gs_c.resolve_wake()
	_a(int(wb_res["transferred"]) >= 1, 161)
	_a(gs_c.wake_blocks.has(wb), 162)
	_a(str(gs_c.wake_blocks[wb].get("kind")) == "workbench", 163)
	# v0.7: кирку крафтим на верстаке в яви — она попадает в инвентарь яви.
	gs_c.reagent_counts = [2, 1, 0] # v0.11: кирка = 2 р1 + 1 р2
	gs_c.reagents = 3
	_a(gs_c.craft_recipe("pickaxe", {"at_workbench": true}), 167)
	_a(_slot_of(gs_c, "pickaxe") >= 0, 168)
	_a(gs_c.inv_dream.all(func(it): return str(it.get("id", "")) != "pickaxe"), 169)
	gs_c.select_item_slot(_slot_of(gs_c, "pickaxe"))
	_a(gs_c.selected_is("pickaxe"), 171)
	var mine_cell := Vector3i(3, 0, 3)
	gs_c.wake_blocks[mine_cell] = {"kind": "drift", "mutant": false}
	_a(gs_c.mine_wake_block(mine_cell), 174)
	_a(not gs_c.wake_blocks.has(mine_cell), 175)
	_a(str(gs_c.last_mined_kind) == "drift", 176)
	var drop_script: GDScript = load("res://scripts/block_pickup.gd")
	var drop: CharacterBody3D = drop_script.new()
	drop.configure("drift")
	root.add_child(drop)
	await process_frame
	_a(drop.is_in_group("pickup"), 182)
	_a(drop.has_method("collect"), 183)
	gs_c.add_mined_block("drift", 1)
	var stored_c := 0
	for sl2 in gs_c.item_slots:
		if str(sl2.get("id", "")) == "drift":
			stored_c += int(sl2.get("count", 0))
	stored_c += int(gs_c.block_stash.get("drift", 0))
	_a(stored_c >= 1, 190)
	var gs_t: Node = gs_script.new()
	root.add_child(gs_t)
	gs_t.reagent_counts = [1, 0, 0] # v0.11: факел ×4 = 1 р1 + 1 бревно
	gs_t.reagents = 1
	gs_t.add_item_count("log", 1)
	_a(gs_t.craft_recipe("torch", {"at_workbench": true}), 195)
	_a(_slot_of(gs_t, "torch") >= 0, 196)
	var torch_cell := Vector3i(4, 0, 5)
	_a(gs_t.place_wake_block(torch_cell, "torch"), 198)
	_a(str(gs_t.wake_blocks[torch_cell].get("kind")) == "torch", 199)
	_a(FileAccess.file_exists("res://assets/audio/music.mp3"), 200)
	_a(FileAccess.file_exists("res://assets/audio/dream_ost.mp3"), 201)
	_a(FileAccess.file_exists("res://assets/audio/boss_ost.mp3"), 202)
	_a(ResourceLoader.exists("res://assets/models/ghost.glb"), 203)
	_a(ResourceLoader.exists("res://assets/models/greenblob.glb"), 204)
	_a(ResourceLoader.exists("res://assets/models/reagent_crystal.glb"), 205)
	_a(ResourceLoader.exists("res://assets/models/reagent_herb.glb"), 206)
	_a(ResourceLoader.exists("res://assets/models/reagent_ore.glb"), 207)
	_a(FileAccess.file_exists("res://assets/models/pickaxe.glb"), 208)
	_a(FileAccess.file_exists("res://assets/models/sword.glb"), 209)
	var gs_s: Node = gs_script.new()
	root.add_child(gs_s)
	gs_s.reagent_counts = [5, 2, 0]
	gs_s.reagents = 7
	_a(not gs_s.craft_recipe("sword", {"at_workbench": false}), 214)
	_a(gs_s.craft_recipe("sword", {"at_workbench": true}), 215)
	_a(_slot_of(gs_s, "sword") >= 0, 216)
	var wb_only: Array = gs_s.get_visible_recipes({"at_workbench": true, "is_dream": true})
	for recw in wb_only:
		var ridw := str(recw.get("id", ""))
		_a(ridw != "nail" and ridw != "wedge" and ridw != "anchor3", 220)
	var found_sword := false
	for recw2 in wb_only:
		if str(recw2.get("id", "")) == "sword":
			found_sword = true
	_a(found_sword, 225)
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	root.add_child(menu)
	_a(menu.is_centered_modal(), 229)

	# Чанки
	var cm_script: GDScript = load("res://scripts/chunk_manager.gd")
	var cm: Node3D = cm_script.new()
	cm.is_dream_layer = false
	cm.chunk_size = 16
	cm.load_radius = 1
	cm.unload_radius = 2
	root.add_child(cm)
	var dummy := Node3D.new()
	dummy.position = Vector3(0, 2, 0)
	root.add_child(dummy)
	cm.setup(dummy, 1337)
	_a(cm.get_loaded_count() >= 1, 243)
	_a(cm.world_to_chunk(Vector3(0, 0, 0)) == Vector2i(0, 0), 244)
	_a(cm.height_at(0, 0) == 0, 245)
	dummy.position = Vector3(40, 2, 40)
	cm._update_chunks(false)
	_a(cm.world_to_chunk(dummy.position) == Vector2i(2, 2), 248)

	# Руины / озёра / реагенты в генерации
	var found_lake := false
	var found_ruin := false
	var ruin_candidates := 0
	var max_ruin_reagents := 0
	for x in range(-8, 9):
		for z in range(-8, 9):
			var c := Vector2i(x, z)
			if cm.chunk_has_lake(c):
				cm.ensure_chunk_loaded(c)
				found_lake = true
			if cm.chunk_has_ruin(c):
				ruin_candidates += 1
				cm.ensure_chunk_loaded(c)
				found_ruin = true
				max_ruin_reagents = maxi(max_ruin_reagents, cm.count_reagents_in_chunk(c))
	_a(found_lake, 266)
	_a(found_ruin, 267)
	_a(ruin_candidates <= 24, 268)
	_a(cm.count_loaded_lakes() >= 1, 269)
	_a(cm.count_loaded_ruins() >= 1, 270)
	_a(max_ruin_reagents >= 2, 271)
	_a(max_ruin_reagents <= 6, 272)
	var lake_p: Vector3 = cm.get_any_lake_sample_point()
	_a(lake_p != Vector3.ZERO, 274)
	_a(cm.is_world_in_lake(lake_p), 275)
	_a(not cm.is_world_in_lake(Vector3(0, 1, 0)), 276)
	# Озеро неровное: клеток меньше, чем у описанного прямоугольника.
	var irregular_ok := false
	for x2 in range(-8, 9):
		for z2 in range(-8, 9):
			var lc := Vector2i(x2, z2)
			if not cm.chunk_has_lake(lc):
				continue
			cm.ensure_chunk_loaded(lc)
			var ncells: int = cm.lake_cell_count(lc)
			var bbox: int = cm.lake_bbox_area(lc)
			if ncells > 0 and ncells < bbox:
				irregular_ok = true
				break
		if irregular_ok:
			break
	_a(irregular_ok, 292)
	var lakes_flat := true
	for lx in range(-8, 9):
		for lz in range(-8, 9):
			var lcc := Vector2i(lx, lz)
			if cm.chunk_has_lake(lcc):
				cm.ensure_chunk_loaded(lcc)
				if cm.has_method("lake_has_no_hills") and not cm.lake_has_no_hills(lcc):
					lakes_flat = false
	_a(lakes_flat, 301)
	var col_issues: Array = cm.collect_collision_issues()
	_a(col_issues.is_empty(), 303)
	_a(cm.lake_water_is_planar(), 304)
	_a(cm.LAKE_DEPTH >= 1.0, 305)
	_a(cm.HILL_MAX == 6, 306)
	var found_h4 := false
	var max_h := 0
	var hill_n := 0
	var sample_n := 0
	for hx in range(-80, 81):
		for hz in range(-80, 81):
			var hh: int = cm.height_at(hx, hz)
			sample_n += 1
			if hh > 0:
				hill_n += 1
			max_h = maxi(max_h, hh)
			if hh == cm.HILL_MAX:
				found_h4 = true
	_a(found_h4, 320)
	_a(max_h == cm.HILL_MAX, 321)
	_a(hill_n * 3 < sample_n, 322) # холмы заметно реже трети клеток
	# Добыча процедурного террейна: луч по холму и стене руин, reload чанка и save/load.
	var hill_cell := Vector3i(0, -999, 0)
	for hx2 in range(16, 120):
		for hz2 in range(16, 120):
			var hht: int = cm.height_at(hx2, hz2)
			if hht <= 0:
				continue
			var cand := Vector3i(hx2, hht - 1, hz2)
			cm.ensure_chunk_loaded(cm.world_to_chunk(Vector3(hx2, 0, hz2)))
			if cm.has_terrain_visual(cand):
				hill_cell = cand
				break
		if hill_cell.y != -999:
			break
	_a(hill_cell.y != -999, 337)
	_a(cm.has_terrain_visual(hill_cell), 338)
	await process_frame
	await physics_frame
	await physics_frame
	var hfrom := Vector3(float(hill_cell.x) + 0.5, float(hill_cell.y) + 3.3, float(hill_cell.z) + 0.5)
	var hto := Vector3(float(hill_cell.x) + 0.5, float(hill_cell.y) + 0.4, float(hill_cell.z) + 0.5)
	var hhit: Dictionary = cm.ray_query_terrain(hfrom, hto)
	_a(not hhit.is_empty(), 345)
	_a(hhit.collider != null, 346)
	_a(hhit.collider.has_meta("terrain_chunk"), 347)
	_a(str(hhit["kind"]) == "hill", 348)
	var hmined: Vector3i = hhit["cell"]
	_a(hmined == hill_cell, 350)
	_a(cm.mine_terrain_at(hmined, "hill"), 351)
	_a(not cm.has_terrain_visual(hmined), 352)
	cm.rebuild_chunk(cm.world_to_chunk(Vector3(hmined.x, 0, hmined.z)))
	_a(not cm.has_terrain_visual(hmined), 354)
	var ruin_cell: Vector3i = cm.find_first_terrain("ruin")
	if ruin_cell.y == -999:
		for rx in range(-8, 9):
			for rz in range(-8, 9):
				if cm.chunk_has_ruin(Vector2i(rx, rz)):
					cm.ensure_chunk_loaded(Vector2i(rx, rz))
		ruin_cell = cm.find_first_terrain("ruin")
	_a(ruin_cell.y != -999, 362)
	while cm.terrain_kind_at(ruin_cell + Vector3i(0, 1, 0)) == "ruin":
		ruin_cell += Vector3i(0, 1, 0)
	_a(cm.has_terrain_visual(ruin_cell), 365)
	await process_frame
	await physics_frame
	var rfrom := Vector3(float(ruin_cell.x) + 0.5, float(ruin_cell.y) + 3.3, float(ruin_cell.z) + 0.5)
	var rto := Vector3(float(ruin_cell.x) + 0.5, float(ruin_cell.y) + 0.4, float(ruin_cell.z) + 0.5)
	var rhit: Dictionary = cm.ray_query_terrain(rfrom, rto)
	_a(not rhit.is_empty(), 371)
	_a(rhit.collider != null, 372)
	_a(rhit.collider.has_meta("terrain_chunk"), 373)
	_a(str(rhit["kind"]) == "ruin", 374)
	var rmined: Vector3i = rhit["cell"]
	_a(cm.mine_terrain_at(rmined, "ruin"), 376)
	_a(not cm.has_terrain_visual(rmined), 377)
	cm.rebuild_chunk(cm.world_to_chunk(Vector3(rmined.x, 0, rmined.z)))
	_a(not cm.has_terrain_visual(rmined), 379)
	var gs_r: Node = gs_script.new()
	root.add_child(gs_r)
	_a(gs_r.remove_terrain_cell(hmined, "hill"), 382)
	_a(gs_r.remove_terrain_cell(rmined, "ruin"), 383)
	_a(gs_r.is_terrain_removed(hmined), 384)
	_a(gs_r.is_terrain_removed(rmined), 385)
	var terrain_blob: Dictionary = gs_r.to_save_dict()
	_a(terrain_blob.has("removed_terrain"), 387)
	var gs_r2: Node = gs_script.new()
	root.add_child(gs_r2)
	gs_r2.apply_save_dict(terrain_blob)
	_a(gs_r2.is_terrain_removed(hmined), 391)
	_a(gs_r2.is_terrain_removed(rmined), 392)
	_a(str(gs_r2.terrain_removed_kind(hmined)) == "hill", 393)
	_a(str(gs_r2.terrain_removed_kind(rmined)) == "ruin", 394)
	var hud_packed = load("res://scenes/hud.tscn")
	if hud_packed:
		var hud_n: Node = hud_packed.instantiate()
		root.add_child(hud_n)
		await process_frame
		if hud_n.has_method("boss_bar_fill_is_red"):
			_a(hud_n.boss_bar_fill_is_red(), 401)
	var reagent_on_top := true
	for node in cm.get_tree().get_nodes_in_group("reagent"):
		if not (node is Node3D):
			continue
		if not cm.is_ancestor_of(node):
			continue
		var gp: Vector3 = node.global_position
		var rh: int = cm.height_at(floori(gp.x), floori(gp.z))
		if gp.y < float(rh) + 0.2:
			reagent_on_top = false
	_a(reagent_on_top, 412)
	var nav_script: GDScript = load("res://scripts/enemy_navigation.gd")
	_a(nav_script.WATER_COST > 1.0, 414)
	var pth: Array = nav_script.find_path(Vector3(0, 1, 0), Vector3(6, 1, 0), cm)
	_a(pth.size() >= 2, 416)

	# Враг (Шовник)
	var enemy_script: GDScript = load("res://scripts/seam_creature.gd")
	var enemy: CharacterBody3D = enemy_script.new()
	enemy.position = Vector3(18, 1, 16)
	root.add_child(enemy)
	await process_frame
	await process_frame
	_a(enemy.is_in_group("seam_creature"), 425)
	enemy.configure_elite(true)
	_a(enemy.elite, 427)
	enemy._apply_dream_state(true)
	_a(enemy.frozen, 429)
	enemy._apply_dream_state(false)
	_a(not enemy.frozen, 431)
	_a(is_equal_approx(enemy.SPEED_NORMAL, 2.15 * 0.6), 432)
	_a(is_equal_approx(enemy.SPEED_ELITE, 2.85 * 0.6), 433)
	_a(enemy.collision_layer == 16, 434)
	_a(enemy.collision_mask & 16 != 0, 435)
	_a(enemy.collision_mask & 1 != 0, 436)
	_a(enemy.collision_mask & 2 != 0, 437)
	_a(enemy.collision_mask & 4 != 0, 438)
	_a(enemy.has_node("Model"), 439)
	_a(enemy.hp == 50, 440)
	_a(enemy.max_hp == 50, 441)
	var vis: GDScript = load("res://scripts/enemy_visuals.gd")
	_a(vis.has_clip(enemy, "walk"), 443)
	_a(vis.has_clip(enemy, "attack"), 444)
	_a(vis.has_clip(enemy, "idle"), 445)
	_a(vis.has_clip(enemy, "death"), 446)
	var played: String = vis.play_state(enemy, "walk", true)
	_a(played != "", 448)
	enemy.take_damage(10)
	_a(enemy.hp == 40, 450)
	_a(is_equal_approx(enemy.ATTACK_INTERVAL, 0.55), 451)

	# Четыре типа призраков / цели Pac-Man
	var ghost_script: GDScript = load("res://scripts/enemy_ghost.gd")
	var g1: CharacterBody3D = ghost_script.new()
	g1.configure(0, Vector3.ZERO, Vector3(10, 1, 10))
	g1.position = Vector3(0, 1, 0)
	root.add_child(g1)
	var g2: CharacterBody3D = ghost_script.new()
	g2.configure(1, Vector3.ZERO, Vector3(-10, 1, 10))
	root.add_child(g2)
	var g3: CharacterBody3D = ghost_script.new()
	g3.configure(2, Vector3.ZERO, Vector3(10, 1, -10))
	root.add_child(g3)
	var g4: CharacterBody3D = ghost_script.new()
	g4.configure(3, Vector3.ZERO, Vector3(-10, 1, -10))
	g4.position = Vector3(0, 1, 0)
	root.add_child(g4)
	await process_frame
	await process_frame
	_a(g1.is_in_group("enemy_ghost"), 471)
	_a(g1.kind_name() == "враг1", 472)
	_a(g2.kind_name() == "враг2", 473)
	_a(g3.kind_name() == "враг3", 474)
	_a(g4.kind_name() == "враг4", 475)
	var blinky_t: Vector3 = g1.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	_a(blinky_t.is_equal_approx(Vector3(5, 0, 0)), 477)
	var pinky_t: Vector3 = g2.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	_a(pinky_t.is_equal_approx(Vector3(11, 0, 0)), 479)
	var inky_t: Vector3 = g3.compute_target(Vector3(4, 0, 0), Vector3(0, 0, -1), Vector3.ZERO, false)
	_a(inky_t.is_equal_approx(Vector3(8, 0, 0)), 481)
	var clyde_far: Vector3 = g4.compute_target(Vector3(30, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	_a(clyde_far.is_equal_approx(Vector3(30, 0, 0)), 483)
	var clyde_near: Vector3 = g4.compute_target(Vector3(2, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	_a(clyde_near.is_equal_approx(Vector3(-10, 1, -10)), 485)
	var scatter_t: Vector3 = g1.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, true)
	_a(scatter_t.is_equal_approx(Vector3(10, 1, 10)), 487)
	g1._apply_dream_state(true)
	_a(g1.frozen, 489)
	_a(is_equal_approx(g1.SPEED, 2.45 * 0.6), 490)
	_a(g1.collision_layer == 16, 491)
	_a(g1.collision_mask & 16 != 0, 492)
	_a(g1.collision_mask & 2 != 0, 493)
	_a(g1.collision_mask & 4 != 0, 494)
	_a(g1.has_node("Model"), 495)
	_a(g1.hp == 40, 496) # v0.11: призраки 40 HP
	g1.take_damage(10)
	_a(g1.hp == 30, 498)
	_a(vis.has_clip(g1, "walk"), 499)
	_a(vis.has_clip(g1, "attack"), 500)
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = boss_script.new()
	boss.position = Vector3(4, 1, 4)
	root.add_child(boss)
	await process_frame
	await process_frame
	_a(boss.is_in_group("block_mother"), 507)
	_a(boss.hp == 620, 508) # v0.11.1: Мать 620 HP (фиксировано)
	_a(boss.max_hp == 620, 509)
	boss.take_damage(10)           # SPAWN — неуязвима
	_a(boss.hp == 620, 511)
	boss._enter(boss.S.IDLE)
	boss.take_damage(10)           # v0.11.1: броня закрыта → меч отскакивает
	_a(boss.hp == 620 and boss.plate_log.bounces >= 1, 514)
	_a(boss.get_tree() != null, 515)
	var td_script: GDScript = load("res://scripts/threat_director.gd")
	var td: Node = td_script.new()
	_a(td.MAX_ENEMIES == 7, 518)
	td.free()
	var dc_script: GDScript = load("res://scripts/day_cycle.gd")
	var dc: Node = dc_script.new()
	dc.time_of_day = 10.0
	_a(not dc.is_night(), 522)
	dc.time_of_day = 1100.0
	_a(dc.is_night(), 524)
	root.add_child(dc)

	var persist_count: int = gs.dream_blocks.size()

	# Save round-trip через GameState сериализацию + файл user://
	gs.dust = 11
	gs.reagents = 4
	gs.nails = 7
	gs.wedges = 2
	gs.wake_blocks[Vector3i(3, 1, 4)] = {"kind": "drift", "mutant": false}
	gs.dream_blocks.clear()
	gs.place_dream_block(Vector3i(2, 2, 2), "drift")
	_a(gs.remove_terrain_cell(Vector3i(9, 2, 9), "hill"), 537)
	_a(gs.remove_terrain_cell(Vector3i(11, 1, 7), "ruin"), 538)
	var blob: Dictionary = gs.to_save_dict()
	_a(blob.has("wake_blocks"), 540)
	_a(blob.has("dust"), 541)
	_a(blob.has("dream_exit_count"), 542)
	_a(blob.has("reagent_counts"), 543)
	_a(blob.has("item_slots"), 544)
	_a(blob.has("removed_terrain"), 545)
	_a(int(blob["dream_exit_count"]) >= 1, 546)
	var path := "user://sonnaya_smoke_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	_a(f != null, 549)
	f.store_string(JSON.stringify(blob))
	f = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_a(typeof(parsed) == TYPE_DICTIONARY, 553)
	var gs2: Node = gs_script.new()
	root.add_child(gs2)
	gs2.apply_save_dict(parsed)
	_a(gs2.dust == 11, 557)
	_a(gs2.nails == 7, 558)
	_a(gs2.wedges == 2, 559)
	_a(gs2.wake_blocks.has(Vector3i(3, 1, 4)), 560)
	_a(gs2.dream_blocks.has(Vector3i(2, 2, 2)), 561)
	_a(gs2.is_terrain_removed(Vector3i(9, 2, 9)), 562)
	_a(gs2.is_terrain_removed(Vector3i(11, 1, 7)), 563)
	_a(gs2.dream_exit_count == gs.dream_exit_count, 564)
	_a(gs2.get_reagent_count(2) == gs.get_reagent_count(2), 565)
	_a(gs2.get_reagent_count(3) == gs.get_reagent_count(3), 566)
	_a(gs2.item_slots[added_at].get("id") == "test_tool", 567)
	# Очистка smoke-файла
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var enemy_count := 0
	for n in get_nodes_in_group("seam_creature"):
		enemy_count += 1
	var ghost_count := 0
	for n2 in get_nodes_in_group("enemy_ghost"):
		ghost_count += 1

	await _v05_checks(gs_script, cm_script)
	if not _v05_ok:
		push_error("SMOKE: v0.5 checks FAILED")
		quit(1)
		return
	await _v06_checks(gs_script, cm_script)
	if not _v06_ok:
		push_error("SMOKE: v0.6 checks FAILED")
		quit(1)
		return

	await _v07_checks(gs_script, cm_script)
	if not _v07_done:
		_fails.append("v0.7 aborted")
	await _v08_checks()
	if not _v08_done:
		_fails.append("v0.8 aborted")
	await _v09_checks()
	if not _v09_done: _fails.append("v0.9 aborted")
	await _v010_build_checks()
	await _v010_gameplay_checks()
	await _v010_stream_checks()
	await _v010_entity_checks()
	await _v010_transfer_checks()
	await _v011_checks()
	if not _fails.is_empty():
		push_error("SMOKE: FAILED asserts at lines %s" % str(_fails))
		quit(1)
		return
	print("SMOKE: OK v0.11 transferred=%d dust_result=%d mutations=%d nails=%d wedges=%d a3=%d chunks=%d enemies=%d ghosts=%d lakes=%d ruins=%d reagents=%d ruin_max=%d save=1 exits=%d persist=%d hill4=%d night=1 torch=1 sword=1 boss=1 drops=1 music=1 col=0 mine=1 tools=1 bossbar=1" % [
		int(result["transferred"]), int(result["dust"]), int(result["mutations"]), gs.nails, gs.wedges, gs.anchors3,
		cm.get_loaded_count(), enemy_count, ghost_count, cm.count_loaded_lakes(), cm.count_loaded_ruins(),
		cm.count_loaded_reagents(), max_ruin_reagents, gs_m.dream_exit_count, persist_count, 1 if found_h4 else 0
	])
	# Quiesce old fixtures: no mob may start a new sound during audio teardown.
	paused = true
	# Остановить тестовые звуки и дать аудиопотоку освободить playback до закрытия движка.
	for audio in root.find_children("*","AudioStreamPlayer",true,false)+root.find_children("*","AudioStreamPlayer3D",true,false):
		audio.stop()
		audio.queue_free()
	await create_timer(0.15).timeout
	quit(0)


var _v05_ok := false


func _slot_of(g: Node, id: String) -> int:
	for i in range(g.item_slots.size()):
		if str(g.item_slots[i].get("id", "")) == id:
			return i
	return -1


func _v05_checks(gs_script: GDScript, cm_script: GDScript) -> void:
	print("SMOKE: v0.5 checks")
	# --- Сцены грузятся ---
	for sc in ["res://scenes/main_menu.tscn", "res://scenes/main.tscn", "res://scenes/hud.tscn"]:
		var pk: PackedScene = load(sc)
		_a(pk != null, 619)
		_a(pk.can_instantiate(), 620)
	for scr in ["res://scripts/inventory_ui.gd", "res://scripts/settings_menu.gd", "res://scripts/pause_menu.gd",
			"res://scripts/main_menu.gd", "res://scripts/entity_culler.gd", "res://scripts/world_store.gd",
			"res://scripts/item_db.gd", "res://scripts/slot_view.gd"]:
		_a(load(scr) != null, 624)

	# --- Сиды ---
	_a(gs_script.seed_from_text("12345") == 12345, 627)
	_a(gs_script.seed_from_text("6767676767") == 6767676767, 628)
	_a(gs_script.seed_from_text("дом") == gs_script.seed_from_text("дом"), 629)
	_a(gs_script.seed_from_text("дом") != gs_script.seed_from_text("сон"), 630)
	_a(gs_script.derive_dream_seed(42) == gs_script.derive_dream_seed(42), 631)
	_a(gs_script.derive_dream_seed(42) != gs_script.derive_dream_seed(43), 632)
	var sigs := []
	for sv in [424242, 424242, 777]:
		var c: Node3D = cm_script.new()
		c.is_dream_layer = false
		c.panorama_mode = true
		c.load_radius = 1
		root.add_child(c)
		var anchor := Node3D.new()
		root.add_child(anchor)
		c.setup(anchor, sv)
		sigs.append(c.terrain_signature(4))
		c.queue_free()
		anchor.queue_free()
	_a(sigs[0] == sigs[1], 646)
	_a(sigs[0] != sigs[2], 647)
	print("SMOKE: determinism sig=%d other=%d" % [sigs[0], sigs[2]])

	# --- Инвентарь: стаки, swap, quick_move, set_slot ---
	var gi: Node = gs_script.new()
	root.add_child(gi)
	gi.reset_state()
	_a(gi.add_item_count("drift", 150) == 150, 654)
	_a(gi.raw_count("drift") == 150, 655)
	_a(int(gi.item_slots[0].get("count")) == 100, 656)
	_a(int(gi.item_slots[1].get("count")) == 50, 657)
	gi.swap_slots(0, 20)
	_a(int(gi.item_slots[20].get("count")) == 100 and str(gi.item_slots[0].get("id")) == "", 659)
	gi.quick_move(20) # основной → хотбар
	_a(str(gi.item_slots[20].get("id")) == "", 661)
	_a(gi.raw_count("drift") == 150, 662)
	gi.quick_move(1) # хотбар → основной
	var in_main := 0
	for i in range(9, 36):
		if str(gi.item_slots[i].get("id", "")) == "drift":
			in_main += int(gi.item_slots[i]["count"])
	_a(in_main >= 6, 668)
	gi.set_slot(5, {"id": "torch", "count": 3})
	_a(gi.count_item("torch") == 3, 670)
	_a(gi.remove_item("torch", 2) and gi.count_item("torch") == 1, 671)
	_a(not gi.remove_item("torch", 5), 672)
	gi.add_item_count("nail", 2)
	_a(_slot_of(gi, "nail") == -1, 674) # якоря не в инвентаре
	gi.dust = 40
	_a(gi.count_item("dust") == 40 and gi.dust == 40, 676)
	var icon: Texture2D = load("res://scripts/item_db.gd").icon("pickaxe")
	_a(icon != null, 678)
	for iid in load("res://scripts/item_db.gd").all_icon_ids():
		_a(ResourceLoader.exists("res://assets/icons/%s.png" % iid), 680)

	# --- Осыпь за убийства ---
	_a(gs_script.DUST_PER_KILL_MIN == 5 and gs_script.DUST_PER_KILL_MAX == 8, 683)
	gi.dust = 0
	var kill_reward: int = gi.reward_kill(false,"Шовник")
	_a(kill_reward >= 5 and kill_reward <= 8,685)
	_a(gi.dust == kill_reward,686)
	_a("+%d осыпи" % kill_reward in gi.last_hint,687)
	_a(gi.reward_kill(true, "Мать блоков") == 200, 688) # v0.11: Мать 200 осыпи
	_a(gi.dust == 200+kill_reward,689)

	# --- Дев-сид 6767676767: всё бесконечно ---
	var gd: Node = gs_script.new()
	root.add_child(gd)
	gd.begin_world("dev", "", "6767676767", gs_script.seed_from_text("6767676767"), false)
	_a(gd.dev_mode, 695)
	_a(gd.dust == gd.INF_COUNT, 696)
	_a(gd.get_reagent_count(1) == gd.INF_COUNT, 697)
	_a(gd.count_text(gd.special_display_count("nail")) == "∞", 698)
	var n0: int = gd.nails
	for rec in gd.recipe_defs():
		_a(gd.can_afford_recipe(rec), 701)
	_a(gd.craft_recipe("wedge", {"is_dream": true}), 702)
	_a(gd.craft_recipe("pickaxe", {"at_workbench": true}), 703)
	_a(gd.dust == gd.INF_COUNT, 704)
	_a(gd.consume_item("torch", 1), 705)
	_a(gd.count_item("torch") == gd.INF_COUNT, 706)
	gd.enter_dream()
	gd.select_anchor(gd.AnchorType.NAIL)
	gd.place_dream_block(Vector3i(0, 0, 0), "drift")
	_a(gd.try_place_anchor(Vector3i(0, 0, 0)), 710)
	_a(gd.nails == n0, 711)
	_a(gd.reward_kill(false, "x") == 0 or gd.dust == gd.INF_COUNT, 712)
	_a(gd.steal_resource_hardcore() == "none", 713)

	# --- Миграция сейва v4 → v5 ---
	var v4 := {"version": 4, "dust": 33, "reagent_counts": [4, 5, 6], "nails": 2, "wedges": 1, "anchors3": 1,
		"item_slots": [{"id": "nail", "count": 2}, {"id": "wedge", "count": 1}, {"id": "anchor3", "count": 1},
			{"id": "pickaxe", "name": "Кирка", "count": 1}, {"id": "drift", "name": "Нанос", "count": 5}],
		"wake_blocks": {}, "dream_blocks": {}}
	var gm: Node = gs_script.new()
	root.add_child(gm)
	gm.apply_save_dict(v4)
	_a(gm.item_slots.size() == 36, 723)
	_a(gm.dust == 33, 724)
	_a(gm.get_reagent_count(2) == 5, 725)
	_a(gm.count_item("pickaxe") == 1 and gm.count_item("drift") == 5, 726)
	_a(gm.nails == 2 and gm.anchors3 == 1, 727)
	_a(_slot_of(gm, "nail") == -1, 728)
	var v5: Dictionary = gm.to_save_dict()
	_a(int(v5["version"]) >= 5, 730)
	var gm2: Node = gs_script.new()
	root.add_child(gm2)
	gm2.apply_save_dict(JSON.parse_string(JSON.stringify(v5)))
	_a(gm2.dust == 33 and gm2.count_item("drift") == 5, 734)

	# --- Хранилище миров ---
	var ws: GDScript = load("res://scripts/world_store.gd")
	var meta: Dictionary = ws.create_world("Смоук тест", "abc", gs_script.seed_from_text("abc"), false)
	var folder := str(meta.get("folder", ""))
	_a(folder != "", 740)
	var found := false
	for w in ws.list_worlds():
		if str(w.get("folder", "")) == folder:
			found = true
			_a(ws.meta_seed(w) == gs_script.seed_from_text("abc"), 745)
	_a(found, 746)
	ws.delete_world(folder)
	for w2 in ws.list_worlds():
		_a(str(w2.get("folder", "")) != folder, 749)

	# --- Настройки ---
	var gset: Node = root.get_node("GameSettings")
	_a(gset.render_distance >= 2 and gset.render_distance <= 8, 753)
	_a(gset.entity_distance_m() > 0.0, 754)

	# --- HUD: хотбар 9 + вертикальная полоса ---
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	_a(hud.find_child("SpecialBar", true, false) != null, 760)
	var hb: Node = hud.find_child("Hotbar", true, false)
	_a(hb != null and hb.get_child_count() == 9, 762)
	print("SMOKE: v0.5 checks OK")
	_v05_ok = true


var _v06_ok := false


func _v06_checks(gs_script: GDScript, cm_script: GDScript) -> void:
	print("SMOKE: v0.6 checks")
	var G: Node = root.get_node("GameState")
	G.reset_state()
	G.peaceful = false
	_a(not G.is_dream(), 775)
	# --- Сутки 24 минуты, фазы ---
	_a(is_equal_approx(G.DAY_CYCLE, 1440.0), 777)
	_a(G.phase_at(30.0) == "morning", 778)
	_a(G.phase_at(500.0) == "day", 779)
	_a(G.phase_at(900.0) == "evening", 780)
	_a(G.phase_at(1200.0) == "night", 781)
	_a(G.phase_at(1440.0 + 30.0) == "morning", 782)
	_a(G.clock_text(0.0) == "06:00", 783)
	_a(G.clock_text(1080.0) == "00:00", 784)
	# --- Луна: видна и светит синевато только ночью ---
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	holder.add_child(sun)
	var env := Environment.new()
	var dc: Node = load("res://scripts/day_cycle.gd").new()
	holder.add_child(dc)
	dc.setup(sun, env)
	dc.set_time(1230.0)
	_a(G.is_night() and dc.is_night(), 795)
	var moon: DirectionalLight3D = dc.get_moon()
	_a(moon != null and moon.visible and moon.light_energy > 0.15, 797)
	_a(moon.light_color.b > moon.light_color.r, 798)
	_a(sun.light_energy < 0.05 or not sun.visible, 799)
	_a(dc.moon_dir().y > 0.2, 800)   # луна над горизонтом
	dc.set_time(500.0)
	_a(not dc.is_night(), 802)
	_a(moon.light_energy < 0.01 or not moon.visible, 803)
	_a(sun.light_energy > 0.5, 804)
	holder.queue_free()
	# --- Деревья: детерминированно по сидам, по всему миру, с коллизией ---
	var cm1: Node3D = cm_script.new()
	cm1.panorama_mode = true
	_a(cm1.tree_plan(Vector2i(5, -7)) == cm1.tree_plan(Vector2i(5, -7)), 809)
	cm1.free()
	var anchor := Node3D.new()
	anchor.position = Vector3(40, 0, 40)
	root.add_child(anchor)
	var cm: Node3D = cm_script.new()
	cm.is_dream_layer = false
	cm.load_radius = 2
	root.add_child(cm)
	cm.setup(anchor, 6767676767)
	for i in range(30):
		await process_frame
	var trees: int = cm.count_loaded_trees()
	_a(trees >= 6, 822)
	var tree: Dictionary = cm.find_first_tree()
	_a(not tree.is_empty(), 824)
	var log1: Vector3i = (tree["logs"] as Array)[1]
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = Vector3(log1) + Vector3(0.5, 0.5, 0.5)
	q.collide_with_bodies = true
	var tree_col := space.intersect_point(q).size() > 0
	_a(tree_col, 833)
	# --- Ломаем все брёвна → листва постепенно опадает ---
	var leaves: Array = tree["leaves"]
	for raw in tree["logs"]:
		var c: Vector3i = raw
		_a(G.remove_terrain_cell(c, "log"), 838)
		cm.rebuild_chunk_at_world(c.x, c.z)
	var pend: int = cm.pending_leaf_decay()
	_a(pend > 0, 841)
	var left_before := 0
	for raw2 in leaves:
		if not G.is_terrain_removed(raw2):
			left_before += 1
	_a(left_before > 0, 846)   # не мгновенно
	cm.force_leaf_decay_tick(30.0)
	_a(cm.pending_leaf_decay() == 0, 848)
	for raw3 in leaves:
		_a(G.is_terrain_removed(raw3), 850)
	# Сохранение: сломанные брёвна/листва — в сейве
	var blob: Dictionary = G.to_save_dict()
	var g2: Node = gs_script.new()
	root.add_child(g2)
	g2.apply_save_dict(JSON.parse_string(JSON.stringify(blob)))
	_a(g2.is_terrain_removed((tree["logs"] as Array)[0]), 856)
	_a(g2.is_terrain_removed(leaves[0]), 857)
	_a(int(blob["version"]) == 10, 858)
	cm.queue_free()
	anchor.queue_free()
	# --- Бревно → доски (верстак) ---
	_a(G.find_recipe("planks").size() > 0, 862)
	# --- Шанс босса + предвестие + флаг в сейве ---
	var chats: Array = []
	var cb := func(t: String, _c: Color = Color.WHITE) -> void: chats.append(t)
	G.chat_message.connect(cb)
	G.world_seed = 6767676767
	G.dev_mode = true
	_a(is_equal_approx(G.boss_spawn_chance(), 0.25), 869)
	G.dev_mode = false
	G.world_seed = 12345
	_a(is_equal_approx(G.boss_spawn_chance(), 0.01), 872)
	G.boss_next_mine = false
	G.set_boss_alive(false)
	# v0.11: «Угроза глубин» вместо 1% на любой блок. Поверхность не копит угрозу.
	G.milestones["first_transfer"] = true
	G.dream_exit_count = 2
	G.mother_cooldown = 0.0
	G.peaceful = false
	G.deep_threat = 0.0
	_a(not G.on_block_mined_at(Vector3i(3, -2, 3), "stone", 0.5) and G.deep_threat == 0.0, 875)
	_a(G.deep_threat_gain(Vector3i(0, -8, 0), "stone") == 1.0 and G.deep_threat_gain(Vector3i(0, -20, 0), "deep_stone") == 3.0 and G.deep_threat_gain(Vector3i(0, -8, 0), "ruin") == 3.0, 876)
	# v0.11.1: 1% на КАЖДЫЙ блок (угроза глубин — только атмосфера, не вызывает Мать).
	var spawned_at := -1
	for i in range(120):
		if G.on_block_mined_at(Vector3i(i, -8, 0), "stone", 0.5):
			spawned_at = i
			break
	_a(spawned_at == -1 and G.deep_threat < 100.0, 877)   # 120 блоков без удачного броска → Матери нет (шкала сбрасывается на 100)
	_a(not G.on_block_mined_at(Vector3i(0, -2, 0), "stone", 0.009) and G.boss_next_mine and chats.any(func(t): return G.BOSS_OMEN_TEXT in str(t)), 878)
	_a(G.on_block_mined_at(Vector3i(1, -2, 0), "stone", 0.99) and not G.boss_next_mine, 879)   # предвестие → Мать на следующем блоке
	_a(not G.on_block_mined_at(Vector3i(2, -2, 0), "stone", 0.0101), 8790)
	_a(G.BOSS_OMEN_TEXT == "Вы слышите разъярённые крики убитой горем матери", 880)
	G.deep_threat = 55.0
	var b2: Dictionary = G.to_save_dict()
	var g3: Node = gs_script.new()
	root.add_child(g3)
	g3.apply_save_dict(JSON.parse_string(JSON.stringify(b2)))
	_a(is_equal_approx(g3.deep_threat, 55.0), 885)
	G.set_boss_alive(true)               # пока жив другой босс — Мать не приходит
	G.deep_threat = 99.5
	_a(not G.on_block_mined_at(Vector3i(0, -8, 0), "stone", 0.0) and not G.boss_next_mine, 886)
	G.set_boss_alive(false)
	G.peaceful = true
	_a(not G.on_block_mined_at(Vector3i(0, -8, 0), "stone", 0.0), 887)
	G.peaceful = false
	G.deep_threat = 0.0
	G.chat_message.disconnect(cb)
	# --- Урон-капы игрока ---
	G.heal_player_full()
	var total := 0
	for k in range(4):
		total += int(G.damage_player(30, "smoke", true))
	_a(total <= 70, 894)
	_a(G.player_hp == 100 - total, 895)
	G.heal_player_full()
	# --- Клавиши: переназначение, конфликт, сохранение ---
	var gset: Node = root.get_node("GameSettings")
	gset.reset_bindings()
	var jump_new := {"type": "key", "code": KEY_KP_7}
	_a(gset.rebind("jump", jump_new) == "", 901)
	var has_f := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_KP_7:
			has_f = true
	_a(has_f, 906)
	var back_b: Dictionary = gset.bindings["move_back"] if gset.bindings.has("move_back") else gset.bindings["back"]
	var back_name := "move_back" if gset.bindings.has("move_back") else "back"
	var fwd_name := "move_forward" if gset.bindings.has("move_forward") else "forward"
	var fwd_old: Dictionary = gset.bindings[fwd_name]
	_a(gset.rebind(fwd_name, back_b) == back_name, 911)   # конфликт → обмен
	_a(gset.bindings[fwd_name] == back_b and gset.bindings[back_name] == fwd_old, 912)
	var gs_new: Node = load("res://scripts/game_settings.gd").new()
	gs_new.load_settings()
	_a(gs_new.bindings["jump"] == jump_new, 915)
	_a(gs_new.bindings[fwd_name] == back_b, 916)
	gs_new.free()
	gset.reset_bindings()
	_a(gset.bindings["jump"] == gset.default_binding("jump"), 919)
	# --- Босс: 500 HP, фазы 66/33 с переходами, уязвимость ---
	var host := Node3D.new()
	root.add_child(host)
	var bs: GDScript = load("res://scripts/block_mother.gd")
	for old in get_nodes_in_group("block_mother"):
		old.free()
	var boss: CharacterBody3D = bs.new()
	host.add_child(boss)
	await process_frame
	_a(boss.hp == 620 and boss.phase == 1, 929)
	# v0.11.1: урон мечом только по открытому ядру (CORE ×1.25) → пороги фаз не проскакиваются.
	boss._enter(boss.S.CORE)
	boss.take_damage(450)                 # не проваливается сквозь порог фазы
	_a(boss.hp == boss.P2_AT, 932)
	_a(boss.phase == 2 and boss.state == boss.S.TRANSITION, 933)
	boss.take_damage(50)                  # переход неуязвим
	_a(boss.hp == boss.P2_AT, 935)
	boss._enter(boss.S.CORE)
	_a(boss.is_vulnerable(), 938)
	boss.receive_weapon_hit(8, "sword")   # ×1.25 по ядру → 10
	_a(boss.hp == boss.P2_AT - 10, 940)
	boss._enter(boss.S.CORE)
	boss.take_damage(400)
	_a(boss.hp == boss.P3_AT and boss.phase == 3, 942)
	boss._enter(boss.S.CORE_LONG)
	boss.take_damage(400)
	_a(boss.hp <= 0 or boss.state == boss.S.DEAD, 945)
	# Пити-таймер блоклингов и жёсткий кап
	var b3: CharacterBody3D = bs.new()
	host.add_child(b3)
	await process_frame
	var got := 0
	for r in range(3):
		if b3.minion_roll(0.99):
			got += 1
	_a(got == 1, 954)                       # 3 неудачи подряд → гарантия
	_a(not b3.minion_roll(0.0) and not b3.minion_roll(0.0), 955)   # локаут 2 приземления
	_a(b3.MINION_HARD_CAP == 4, 956)
	for cap in b3.MINION_CAP:
		_a(int(cap) <= b3.MINION_HARD_CAP, 958)
	# Телеграфы ≥0.4 с, урон одного удара ≤40% HP
	for w in b3.WINDUP:
		_a(float(w) >= 0.4, 961)
	_a(b3.RAIN_WINDUP >= 0.4 and b3.BRICK_SHADOW >= 0.4 and b3.MARKER_TIME >= 0.4, 962)
	for dmg in [b3.SLAM_DAMAGE, b3.WAVE_DAMAGE, b3.REASSEMBLE_DAMAGE, b3.BRICK_DAMAGE, b3.CONTACT_DAMAGE]:
		_a(int(dmg) <= 40, 964)
	b3.queue_free()
	host.queue_free()
	await process_frame
	print("SMOKE: v0.6 checks OK trees=%d tree_col=%s leaves_pending=%d" % [trees, str(tree_col), pend])
	_v06_ok = true



# ============================================================ v0.7

var v07_report: Dictionary = {}
var _v07_done := false


func _v07_checks(gs_script: GDScript, cm_script: GDScript) -> void:
	print("SMOKE: v0.7 checks")
	var G: Node = root.get_node("GameState")
	G.reset_state()
	G.peaceful = false
	G.dev_mode = false
	G.world_seed = 12345
	# --- Мутация «рот» 7% ---
	_a(is_equal_approx(G.MUTATION_CHANCE, 0.07), 987)
	# --- Стак 100, ресурсы в общем кошеле, инвентари сна/яви раздельно ---
	_a(load("res://scripts/item_db.gd").max_stack("drift") == 100 and load("res://scripts/item_db.gd").max_stack("planks") == 100, 989)
	_a(load("res://scripts/item_db.gd").max_stack("pickaxe") == 1, 990)
	_a(not G.is_dream(), 991)
	_a(is_same(G.item_slots, G.inv_wake), 992)
	G.add_item_count("planks", 5)
	G.add_item_count("reagent1", 3)
	G.enter_dream()
	_a(is_same(G.item_slots, G.inv_dream), 996)
	_a(G.count_item("planks") == 0, 997)              # предметы яви во сне не видны
	_a(G.count_item("reagent1") == 3, 998)            # кошель общий
	G.add_item_count("drift", 4)
	G.resolve_wake()
	_a(G.count_item("drift") == 0 and G.count_item("planks") == 5, 1001)
	_a(G.inv_dream.any(func(it): return str(it.get("id", "")) == "drift"), 1002)
	# --- Сон → явь: все блоки сна исчезают, заякоренный переносится ---
	G.enter_dream()
	G.place_dream_block(Vector3i(30, 0, 30), "drift")
	G.place_dream_block(Vector3i(31, 0, 30), "drift")
	G.nails = 1
	G.select_anchor(G.AnchorType.NAIL)
	_a(G.try_place_anchor(Vector3i(30, 0, 30)), 1009)
	G.resolve_wake()
	_a(G.dream_blocks.is_empty(), 1011)
	_a(G.wake_blocks.has(Vector3i(30, 0, 30)), 1012)
	# --- Кровать (сон) и хилка1 → под подушку ---
	G.enter_dream()
	G.add_item_count("dust", 200)
	G.add_item_count("reagent1", 3)
	_a(G.craft_recipe("bed", {"is_dream": true}), 1017)
	_a(G.count_item("bed") == 1, 1018)
	_a(not G.craft_recipe("heal1", {"is_dream": false}), 1019)
	var dust0: int = G.count_item("dust")
	_a(G.craft_recipe("heal1", {"is_dream": true}), 1021)
	_a(G.count_item("dust") == dust0 - G.HEAL1_DUST and G.HEAL1_DUST == 35, 1022)
	_a(G.pillow_count("heal1") == 1 and G.count_item("heal1") == 0, 1023)
	G.resolve_wake()
	_a(G.count_item("heal1") == 0, 1025)
	var pslot := -1
	for i in range(G.pillow.size()):
		if str(G.pillow[i].get("id", "")) == "heal1":
			pslot = i
	_a(G.take_from_pillow(pslot), 1030)
	_a(G.count_item("heal1") == 1 and G.pillow_count("heal1") == 0, 1031)
	_a(not G.take_from_pillow(pslot), 1032)            # только забирать
	# --- Хилка: +20 HP, перезарядка 15 с ---
	G.add_item_count("heal1", 1)
	G.player_hp = 50
	_a(G.use_heal(), 1036)
	_a(G.player_hp == 70 and is_equal_approx(G.heal_cd, 15.0), 1037)
	_a(not G.use_heal(), 1038)
	_a(G.player_hp == 70, 1039)
	G._process(15.1)
	_a(G.can_use_heal(), 1041)
	# --- Регенерация 1 HP/с после 15 с без урона ---
	G.player_hp = 100
	G._iframes = 0.0
	G._combo_log = []
	G.damage_player(20, "test")
	_a(G.player_hp == 80, 1047)
	_a(is_equal_approx(G.regen_delay_left(), 15.0), 1048)
	for i in range(10):
		G._process(1.0)
	_a(G.player_hp == 80, 1051)
	for i in range(8):
		G._process(1.0)
	_a(G.player_hp >= 82 and G.player_hp <= 84, 1054)
	# --- Смерть: выпадает всё, кроме гвоздей/якорей ---
	G.nails = 3
	G.add_item_count("planks", 7)
	var drop: Array = G.collect_death_drop()
	var drop_ids: Array = drop.map(func(d): return str(d["id"]))
	_a("planks" in drop_ids and "reagent1" in drop_ids, 1060)
	_a(G.nails == 3, 1061)
	_a(G.count_item("planks") == 0 and G.count_item("reagent1") == 0, 1062)
	var gid: int = G.add_grave(Vector3(1, 1, 1), drop)
	var blob: Dictionary = JSON.parse_string(JSON.stringify(G.to_save_dict()))
	var g2: Node = gs_script.new()
	root.add_child(g2)
	g2.apply_save_dict(blob)
	_a(g2.graves.size() == 1, 1068)
	_a(g2.pickup_grave(gid) > 0 and g2.count_item("planks") == 12, 1069)
	_a(g2.graves.is_empty(), 1070)
	g2.queue_free()
	# --- Станок: верстак + 7 реагент3; свои рецепты; Меч2 ровно 1 Меч + 2/2/2 ---
	G.reset_state()
	var lathe_ids: Array = G.get_visible_recipes({"at_lathe": true}).map(func(r): return str(r["id"]))
	var bench_ids: Array = G.get_visible_recipes({"at_workbench": true}).map(func(r): return str(r["id"]))
	_a(lathe_ids == ["sword3", "sword2", "pickaxe2", "scale_helmet","scale_chest","scale_legs","scale_boots"], 1076)
	_a(not ("lathe" in bench_ids) and not ("sword2" in bench_ids), 1077)
	for rid in bench_ids:
		_a(not (rid in lathe_ids), 1079)
	var lr: Dictionary = G.find_recipe("lathe")
	# v0.11: станок во Сне платится только кошелём (5 р3 + 2 р2 + 20 осыпи), верстак-предмет не нужен.
	_a(not (lr as Dictionary).has("items") and int(lr["reagent3"]) == 5 and int(lr["reagent2"]) == 2 and int(lr["dust"]) == 20, 1081)
	G.add_item_count("reagent3", 4)
	G.add_item_count("reagent2", 2)
	G.add_item_count("dust", 20)
	_a(not G.craft_recipe("lathe", {"at_workbench": true}), 1084)
	G.add_item_count("reagent3", 1)
	_a(not G.craft_recipe("lathe", {"at_lathe": true}), 1086)
	G.enter_dream()
	_a(G.craft_recipe("lathe", {"is_dream": true}), 1087)
	_a(G.count_item("lathe") == 1 and G.count_item("reagent3") == 0 and G.count_item("reagent2") == 0 and G.dust == 0, 1088)
	G.resolve_wake()
	var sr: Dictionary = G.find_recipe("sword2")
	_a(sr["items"] == {"sword": 1, "stone": 6} and int(sr["reagent2"]) == 2, 1090)
	G.add_item_count("stone", 6)
	G.add_item_count("reagent2", 2)
	_a(not G.craft_recipe("sword2", {"at_lathe": true}), 1094)     # без Меча — нельзя
	G.add_item_count("sword", 1)
	_a(not G.craft_recipe("sword2", {"at_workbench": true}), 1096)
	_a(G.craft_recipe("sword2", {"at_lathe": true}), 1097)
	_a(G.count_item("sword2") == 1 and G.count_item("sword") == 0, 1098)
	_a(G.count_item("stone") == 0 and G.count_item("reagent2") == 0, 1099)
	var bc: GDScript = load("res://scripts/build_controller.gd")
	_a(bc.SWORD2_DAMAGE == 14 and bc.SWORD_DAMAGE==8 and bc.SWORD3_DAMAGE==24 and is_equal_approx(bc.SWORD2_REACH, bc.SWORD_REACH * 1.25), 1101)
	var cmenu: Node = load("res://scripts/craft_menu.gd").new()
	root.add_child(cmenu)
	await process_frame
	cmenu.open_lathe()
	_a(cmenu.station() == "lathe" and cmenu.visible_recipe_ids() == ["sword3", "sword2", "pickaxe2", "scale_helmet","scale_chest","scale_legs","scale_boots"], 1106)
	cmenu.close()
	cmenu.queue_free()
	_a(G.is_placeable_block("bed") and G.is_placeable_block("lathe"), 1109)
	for k in ["bed", "lathe", "sword2", "heal1", "anaconda_egg", "stone", "nest"]:
		_a(ResourceLoader.exists("res://assets/icons/%s.png" % k), 1111)
	_a(ResourceLoader.exists("res://assets/models/potion_heal.glb"), 1112)
	# --- Чат: никаких краж/убийств, кроме боссов ---
	var chats: Array = []
	var cb := func(t: String, _c: Color = Color.WHITE) -> void: chats.append(t)
	G.chat_message.connect(cb)
	G.reward_kill(false, "Шовник")
	G.set_hint("Шовник украл блок!", false)
	_a(chats.is_empty(), 1119)
	G.reward_kill(true, "Мать блоков")
	_a(chats.size() == 1, 1121)
	G.chat_message.disconnect(cb)
	# --- Боссы: лимит 2 врага; Мать: кулдаун сутки ---
	var td: GDScript = load("res://scripts/threat_director.gd")
	_a(td.BOSS_ENEMY_CAP == 2, 1125)
	G.set_boss_alive(true)
	_a(G.boss_alive, 1127)
	var tdn: Node = td.new()
	_a(tdn.enemy_cap() == 2, 1129)
	G.set_boss_alive(false)
	_a(not G.boss_alive and tdn.enemy_cap() > 2, 1131)
	tdn.free()
	_a(is_equal_approx(G.boss_spawn_chance(), 0.01), 1133)
	G.on_mother_killed()
	_a(is_equal_approx(G.mother_cooldown, 1440.0), 1135)
	G.boss_next_mine = true
	_a(not G.on_block_mined(0.0) and not G.on_block_mined(0.0), 1137)
	var blob2: Dictionary = JSON.parse_string(JSON.stringify(G.to_save_dict()))
	_a(float(blob2["mother_cooldown"]) > 1400.0, 1139)
	G._process(1441.0)
	_a(G.mother_cooldown == 0.0, 1141)
	# Мать: +5 HP за сломанный ею блок, рык
	var bs: GDScript = load("res://scripts/block_mother.gd")
	var host := Node3D.new()
	root.add_child(host)
	var Sfx: GDScript = load("res://scripts/sfx.gd")
	var roars0: int = Sfx.count(Sfx.MOTHER_ROAR)
	var boss: CharacterBody3D = bs.new()
	host.add_child(boss)
	await process_frame
	_a(Sfx.count(Sfx.MOTHER_ROAR) > roars0, 1151)
	_a(ResourceLoader.exists(Sfx.MOTHER_ROAR) and ResourceLoader.exists(Sfx.ANACONDA_ROAR), 1152)
	boss.hp = 400
	_a(boss.heal_from_blocks(3) == 0 and boss.hp == 400, 1154)   # v0.11.1: скрытый хил от деревьев убран
	boss.hp = boss.max_hp-1
	boss.heal_from_blocks(4)
	_a(boss.hp == boss.max_hp-1, 1157)
	boss.queue_free()
	await process_frame
	G.reset_state()
	# --- Мобы бьют ---
	_a(load("res://scripts/seam_creature.gd").HIT_DAMAGE > 0 and load("res://scripts/enemy_ghost.gd").HIT_DAMAGE > 0, 1162)
	# --- Луна ярче ---
	var dcs: GDScript = load("res://scripts/day_cycle.gd")
	_a(is_equal_approx(dcs.MOON_MAX_ENERGY,0.56),1165)
	# --- Мир: 30 уровней вниз, бедрок y=-31, пещеры/гнёзда, вода ---
	_a(G.BEDROCK_Y == -31, 1167)
	var anchor := Node3D.new()
	anchor.position = Vector3(0, 2, 6)
	root.add_child(anchor)
	var cm: Node3D = cm_script.new()
	cm.is_dream_layer = false
	cm.load_radius = 2
	root.add_child(cm)
	cm.setup(anchor, 12345)
	for i in range(20):
		await process_frame
	_a(cm.BEDROCK_Y == -31 and cm.MIN_DIG_Y == -30, 1178)
	_a(cm.terrain_kind_at(Vector3i(3, -31, 3)) == "bedrock", 1179)
	_a(not G.remove_terrain_cell(Vector3i(3, -31, 3), "bedrock"), 1180)
	_a(cm.terrain_kind_at(Vector3i(3, -30, 3)) in ["stone", "deep_stone"], 1181)
	_a(cm.terrain_kind_at(Vector3i(3, -1, 3)) == "ground", 1182)
	_a(cm.floor_y_below(Vector3(3.5, -29.0, 3.5), 5) >= -30.0, 1183)
	# Частоты генерации (не загружая меши): руины ~5%, гнёзда ~1/3 от руин.
	var stats: Dictionary = cm.generation_stats(30)
	v07_report["stats"] = stats
	print("SMOKE: gen stats chunks=%d ruins=%.2f%% entrances=%.2f%% nests=%.2f%% (cave=%d dome=%d) ratio=%.2f" % [
		int(stats["chunks"]), float(stats["ruin_pct"]), float(stats["entrance_pct"]), float(stats["nest_pct"]),
		int(stats["nests_cave"]), int(stats["nests_dome"]), float(stats["ruin_pct"]) / maxf(0.01, float(stats["nest_pct"]))])
	_a(float(stats["ruin_pct"]) > 2.0, 1190)
	_a(float(stats["nest_pct"]) > 0.8 and float(stats["nest_pct"]) < 3.0, 1191)
	var ratio: float = float(stats["ruin_pct"]) / maxf(0.01, float(stats["nest_pct"]))
	_a(ratio > 2.0 and ratio < 4.5, 1193)
	_a(int(stats["nests_cave"]) > 0 and int(stats["nests_dome"]) > 0, 1194)
	_a(float(stats["entrance_pct"]) > 2.0 and float(stats["entrance_pct"]) < 12.0, 1195)
	# Вода течёт: копаем рядом с озером — вода заливает яму.
	var lake_edge := Vector3i.ZERO
	var found_edge := false
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			if found_edge:
				break
			for lx in range(16):
				if found_edge:
					break
				for lz in range(16):
					var wx := cx * 16 + lx
					var wz := cz * 16 + lz
					if cm.water_level(Vector3i(wx, -1, wz)) == 8 and cm.water_level(Vector3i(wx + 1, -1, wz)) == 0 \
							and not cm._world_is_lake_cell(wx + 1, wz) and not cm._world_is_lake_cell(wx + 2, wz) \
							and cm.height_at(wx + 1, wz) == 0 and cm.height_at(wx + 2, wz) == 0 \
							and cm.get_loaded_count() > 0 and cm.is_cell_solid(Vector3i(wx + 1, -1, wz)):
						lake_edge = Vector3i(wx, -1, wz)
						found_edge = true
						break
	_a(found_edge, 1216)
	var flowed := 0
	if found_edge:
		var c1 := lake_edge + Vector3i(1, 0, 0)
		var c2 := lake_edge + Vector3i(2, 0, 0)
		var c3 := lake_edge + Vector3i(2, -1, 0)
		G.remove_terrain_cell(c1, "ground")
		G.remove_terrain_cell(c3, "ground")
		G.remove_terrain_cell(c2, "ground")
		var t0 := Time.get_ticks_usec()
		cm.water_settle(100)
		var us := Time.get_ticks_usec() - t0
		flowed = cm.water_cell_count()
		v07_report["water_us"] = us
		print("SMOKE: water c1=%d c2=%d c3=%d cells=%d settle_us=%d" % [cm.water_level(c1), cm.water_level(c2), cm.water_level(c3), flowed, us])
		_a(cm.water_level(c1) == 7, 1231)
		_a(cm.water_level(c3) == 8, 1232)       # падает вниз
		_a(cm.water_level(c2) >= 1, 1233)
		_a(us < 200000, 1234)
	cm.queue_free()
	anchor.queue_free()
	await process_frame
	# --- Дев-сид: пещера с гнездом и яйцом в 15–25 м от спавна, вход видно ---
	G.reset_state()
	G.world_seed = 6767676767
	G.dev_mode = true
	var anchor2 := Node3D.new()
	anchor2.position = G.DEFAULT_SPAWN
	root.add_child(anchor2)
	var cmd: Node3D = cm_script.new()
	cmd.is_dream_layer = false
	cmd.load_radius = 2
	root.add_child(cmd)
	cmd.setup(anchor2, 6767676767)
	for i in range(20):
		await process_frame
	var dn: Dictionary = cmd.nearest_nest(G.DEFAULT_SPAWN, 40.0)
	_a(not dn.is_empty(), 1253)
	if not dn.is_empty():
		var hd := Vector2(dn["center"].x - G.DEFAULT_SPAWN.x, dn["center"].z - G.DEFAULT_SPAWN.z).length()
		var ent: Vector3 = dn["entrance"]
		var he := Vector2(ent.x - G.DEFAULT_SPAWN.x, ent.z - G.DEFAULT_SPAWN.z).length()
		print("SMOKE: dev nest dist=%.1f entrance=%s entrance_dist=%.1f" % [hd, str(ent), he])
		v07_report["dev_nest_dist"] = hd
		_a(hd >= 15.0 and hd <= 25.0, 1260)
		_a(he >= 12.0 and he <= 25.0, 1261)
		var egg: Vector3i = dn["egg"]
		_a(cmd.terrain_kind_at(egg) == "egg", 1263)
		_a(cmd.terrain_kind_at(egg + Vector3i.DOWN) == "nest", 1264)
		# Вход виден: устье открыто к небу, под ним вырыто.
		var ec := Vector3i(floori(ent.x), 0, floori(ent.z))
		_a(cmd.is_carved(ec + Vector3i.DOWN), 1267)
		_a(not cmd.is_cell_solid(ec + Vector3i.DOWN) and not cmd.is_cell_solid(ec), 1268)
		# Яйцо: добыча → в инвентарь, отметка в сейве.
		_a(G.remove_terrain_cell(egg, "egg"), 1270)
		_a(G.collected_eggs.has(str(dn["id"])), 1271)
	cmd.queue_free()
	anchor2.queue_free()
	await process_frame
	G.dev_mode = false
	G.world_seed = 12345
	G.reset_state()
	# --- Анаконда: неуязвима к оружию, урон светом, уходит на рассвете ---
	var host2 := Node3D.new()
	root.add_child(host2)
	var pl := CharacterBody3D.new()
	pl.add_to_group("player")
	host2.add_child(pl)
	pl.global_position = Vector3(50, 0, 50)
	G.day_time = 1200.0
	_a(G.is_night(), 1286)
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var ana: Node3D = AS.spawn_at(host2, Vector3(40, 0, 40), "test")
	await process_frame
	_a(ana != null and ana.hp == ana.MAX_HP and ana.MAX_HP == 1250, 1290)
	_a(G.boss_alive, 1291)
	_a(Sfx.count(Sfx.ANACONDA_ROAR) > 0, 1292)
	# OST Анаконды: зациклен, приоритет над темой Матери, кроссфейд обратно после ухода.
	_a(FileAccess.file_exists("res://assets/audio/anaconda_ost.mp3"), 1294)
	var mus: Node = load("res://scripts/music_controller.gd").new()
	host2.add_child(mus)
	await process_frame
	_a(mus._desired() == "anaconda", 1298)
	var ost: AudioStream = mus._load_stream(mus.PATH_ANACONDA)
	_a(ost != null and (ost as AudioStreamMP3).loop, 1300)
	G.set_boss_alive(true)                      # будто Мать тоже жива
	_a(mus._desired() == "anaconda", 1302)
	mus._process(0.6)
	_a(mus.current_key() == "anaconda", 1304)
	ana.take_damage(200)
	_a(ana.hp == ana.MAX_HP and ana.weapon_hits_ignored == 1, 1306)
	_a(ana.receive_weapon_hit(24, "sword3").dealt == 0 and ana.hp == ana.MAX_HP, 13060)   # v0.11.1: меч = 0
	_a(ana.is_invulnerable(), 1307)                 # SPAWN — в земле
	# v0.11.1: урон наносят ТОЛЬКО поставленные факелы, перекрёстный огонь 1/2/3.
	ana._emerge = Vector3(40, 0, 40)
	ana._enter(ana.S.REST)
	_a(ana.light_dps() == 0.0 and ana.hp == ana.MAX_HP, 1313)
	ana._head.global_position = Vector3(40.5, 0.6, 40.5)
	for sg in ana._segs:
		sg.global_position = Vector3(40.5, 0.6, 52.5)       # тело «далеко» для изоляции теста света
	var hc := Vector3i(40, 0, 40)
	G.wake_blocks[hc + Vector3i(2, 0, 0)] = {"kind": "torch", "mutant": false}
	_a(ana.crossfire_level() == 1 and ana.light_dps() == 0.0, 1319)        # 1 источник — только обнаружение
	G.wake_blocks[hc + Vector3i(0, 0, 2)] = {"kind": "torch", "mutant": false}
	_a(ana.crossfire_level() == 2 and is_equal_approx(ana.light_dps(), ana.BURN_DPS), 1326)   # 2 — ожог
	G.wake_blocks[hc + Vector3i(-2, 0, 0)] = {"kind": "torch", "mutant": false}
	_a(ana.crossfire_level() >= 3 and is_equal_approx(ana.light_dps(), ana.BURN_DPS * ana.BOOST_MULT), 1330)   # 3 — усиление
	print("SMOKE: anaconda crossfire dps=%.1f" % ana.light_dps())
	_a(ana.apply_light_damage(10.0, "crossfire3") == 10 and ana.hp == ana.MAX_HP - 10, 1333)
	_a(not ("STUNNED" in ana.STATE_NAMES) and not ("stun" in ana.debug_snapshot()), 13330)   # оглушения факелом нет
	# Факел в руке: в light_zones не входит.
	for z in ana.light_zones():
		_a(not bool(z["held"]), 13331)
	# Касание любой секцией тела ломает факел (без шанса и КД).
	ana._segs[ana._segs.size() - 1].global_position = Vector3(46.5, 0.6, 40.5)
	var tail_c := Vector3i(46, 0, 40)
	G.wake_blocks.clear()
	G.wake_blocks[tail_c] = {"kind": "torch", "mutant": false}
	var broke_n: int = ana.check_body_torch_contacts()
	_a(broke_n == 1 and not G.wake_blocks.has(tail_c) and ana.torches_broken_by_body == 1, 13332)   # хвост
	G.wake_blocks[hc] = {"kind": "torch", "mutant": false}
	_a(ana.check_body_torch_contacts() >= 1 and not G.wake_blocks.has(hc), 13333)   # голова
	G.wake_blocks[hc] = {"kind": "torch", "mutant": false}
	_a(ana.check_body_torch_contacts() >= 1, 13334)                                  # повторно сразу — без КД
	G.wake_blocks.clear()
	# Ни одного неизбежного урона: телеграф ≥0.6 с, удар ≤35%, кап комбо 70.
	for tt in ana.TELEGRAPH:
		_a(float(tt) >= 0.6, 1336)
	for dmg in [ana.BURST_DAMAGE, ana.ROCK_DAMAGE, ana.CONSTRICT_DAMAGE, ana.CONTACT_DAMAGE, ana.COIL_CONTACT]:
		_a(int(dmg) <= 35, 1338)
	_a(G.COMBO_CAP <= 70, 1339)
	_a(ana.MINION_CAP <= 3 and ana.cavein_zone_count() >= 3 and ana.cavein_zone_count() <= 4, 1340)
	# Рассвет — уходит.
	G.day_time = 1440.0 + 400.0
	_a(not G.is_night(), 1343)
	ana.tick(0.1)
	_a(ana.state == ana.S.LEAVING and "Светает" in ana.leave_reason, 1345)
	_a(mus._desired() == "boss", 1346)             # Анаконда ушла — снова тема Матери
	mus._process(0.6)
	_a(mus.current_key() == "boss", 1348)
	G.set_boss_alive(false)                     # Мать «ушла»
	_a(mus._desired() == "wake", 1350)
	_a(not G.boss_alive, 1351)
	G.wake_blocks.clear()
	await create_timer(1.5).timeout
	_a(get_nodes_in_group("anaconda").is_empty(), 1354)
	# Миньон: меч убивает, свет убивает.
	var ws: GDScript = load("res://scripts/anaconda_worm.gd")
	var w: Node3D = ws.new()
	host2.add_child(w)
	w.take_damage(25)
	_a(w._dead, 1360)
	# Спавн у гнезда только ночью
	G.day_time = 500.0
	_a(AS.try_spawn(host2, pl, null) == null, 1363)
	# Призыв яйцом: только ночью, яйцо тратится; кулдауна после убийства НЕТ (он только у Матери).
	G.add_item_count("anaconda_egg", 2)
	_a(AS.summon_with_egg(host2, pl, null) == null and G.count_item("anaconda_egg") == 2, 1366)   # день
	G.day_time = 1200.0
	var s1: Node3D = AS.summon_with_egg(host2, pl, null)
	await process_frame
	_a(s1 != null and G.count_item("anaconda_egg") == 1, 1370)
	_a(AS.summon_with_egg(host2, pl, null) == null and G.count_item("anaconda_egg") == 1, 1371)   # уже здесь
	s1._die()
	_a(G.count_item("anaconda_egg") == 2, 1373)          # +1 яйцо в награду
	_a(not ("anaconda_cooldown" in G), 1374)
	await create_timer(1.6).timeout
	var s2: Node3D = AS.summon_with_egg(host2, pl, null)
	await process_frame
	_a(s2 != null and G.count_item("anaconda_egg") == 1, 1378)   # сразу после убийства — снова можно
	s2.leave("")
	await create_timer(1.4).timeout
	G.day_time = 500.0
	# --- Автоподбор ---
	var pcs: GDScript = load("res://scripts/player_controller.gd")
	var pc: CharacterBody3D = pcs.new()
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	var ray := RayCast3D.new()
	ray.name = "InteractRay"
	cam.add_child(ray)
	pivot.add_child(cam)
	pc.add_child(pivot)
	host2.add_child(pc)
	pc.set_physics_process(false)
	pc.set_process(false)
	pc.global_position = Vector3(5, 0, 5)
	var pk: CharacterBody3D = load("res://scripts/block_pickup.gd").new()
	pk.configure("planks")
	host2.add_child(pk)
	pk.global_position = Vector3(5.5, 0.6, 5)
	var planks0: int = G.count_item("planks")
	G.player_hp = 100 # isolate pickup from the preceding boss attacks
	await physics_frame
	await physics_frame # broadphase must see the newly spawned pickup body
	_a(pc.auto_pickup() >= 1 and pk.collected,1394)
	_a(G.count_item("planks") == planks0 + 1, 1395)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host2.queue_free()
	host.queue_free()
	await process_frame
	print("SMOKE: v0.7 checks done")
	_v07_done = true

func _v08_checks() -> void:
	print("SMOKE: v0.8 checks")
	var G: Node = root.get_node("GameState")
	var Rules: GDScript = load("res://scripts/mining_rules.gd")
	G.reset_state()
	G.dev_mode = false
	_a(G.SAVE_FORMAT == 10, 8001)
	for pair in [["ground",0.6],["leaves",0.2],["log",2.0],["planks",2.0],["stone",1.5],["deep_stone",3.0],["sand",0.5]]:
		_a(is_equal_approx(Rules.hardness(pair[0]),pair[1]),8002)
	_a(is_equal_approx(Rules.seconds("stone","pickaxe"),3.0),8003)
	_a(is_equal_approx(Rules.seconds("stone","pickaxe2"),1.5),8004)
	_a(is_inf(Rules.seconds("bedrock","pickaxe2")),8005)
	for tool in ["pickaxe","sword","pickaxe2","sword2"]:
		G.set_slot(0,{"id":tool,"count":1})
		G.select_item_slot(0)
		_a(int(G.get_slot(0).durability) == (500 if tool.ends_with("2") else 100),8006)
		G.wear_tool(2)
		var remain: int = G.tool_max(tool)-2
		_a(int(G.get_slot(0).durability) == remain,8007)
		G.quick_move(0)
		_a(G.get_slot(9).get("durability") == remain,8008)
		G.swap_slots(0,9)
		var data: Dictionary = G.to_save_dict()
		G.apply_save_dict(data)
		_a(G.get_slot(0).get("durability") == remain,8009)
		G.wear_tool(remain)
		_a(G.get_slot(0).get("id","") == "",8010)
	# modal input runs before GUI eats Esc / Y; button closes too.
	var pil: Control = load("res://scripts/pillow_ui.gd").new()
	root.add_child(pil)
	await process_frame
	for action in ["ui_cancel","pillow_check"]:
		pil.open()
		_a(G.pillow_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,8011)
		var e := InputEventAction.new()
		e.action = action
		e.pressed = true
		pil._input(e)
		_a(not G.pillow_open and not pil.visible and (DisplayServer.get_name()=="headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED),8012)
	pil.open()
	pil.find_child("CloseButton",true,false).pressed.emit()
	_a(not G.pillow_open,8013)
	pil.queue_free()
	var ui: Control = load("res://scripts/storage_ui.gd").new()
	root.add_child(ui)
	await process_frame
	var c := Vector3i(5,0,5)
	for action in ["ui_cancel","pillow_check"]:
		ui.open(c,true)
		_a(G.storage_open and G.ui_blocked(),8014)
		var e := InputEventAction.new()
		e.action = action
		e.pressed = true
		ui._input(e)
		_a(not G.storage_open and not ui.visible and (DisplayServer.get_name()=="headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED),8015)
	ui.queue_free()
	# Stations: crafted via C in dream; ingredient consumed, unlock persists.
	for station in ["lathe","sawmill","alchemy","idea_catcher"]:
		_a(G.find_recipe(station).where == "dream",8016)
		_a(not G.recipe_available(G.find_recipe(station),{"at_workbench":true}),8017)
	_a(not G.recipe_available(G.find_recipe("alchemy"),{"is_dream":true}),8018)
	G.on_mother_killed()
	_a(G.recipe_available(G.find_recipe("alchemy"),{"is_dream":true}),8019)
	_a(G.recipe_available(G.find_recipe("idea_catcher"),{"is_dream":true}),8020)
	_a(not G.recipe_available(G.find_recipe("planks"),{"at_workbench":true}),8021)
	_a(G.recipe_available(G.find_recipe("planks"),{"station":"sawmill"}),8022)
	# v0.11: дверь и сундук — на обычной лесопилке; деревянная броня — только в мастерской (лесопилка у верстака).
	_a(G.recipe_available(G.find_recipe("door"),{"station":"sawmill","upgraded":false}) and G.recipe_available(G.find_recipe("chest"),{"station":"sawmill","upgraded":false}),8023)
	_a(not G.recipe_available(G.find_recipe("wood_chest"),{"station":"sawmill","upgraded":false}) and G.recipe_available(G.find_recipe("wood_chest"),{"station":"sawmill","upgraded":true}),8024)
	G.wake_blocks[c] = {"kind":"sawmill"}
	G.wake_blocks[c+Vector3i(1,0,1)] = {"kind":"workbench"}
	_a(not G.station_upgraded(c),8025)
	G.wake_blocks[c+Vector3i.RIGHT] = {"kind":"workbench"}
	_a(G.station_upgraded(c),8026)
	G.wake_blocks.clear()
	_a(G.find_recipe("pickaxe2").items == {"pickaxe":1,"stone":6},8027)
	G.add_item_count("pickaxe",1)
	G.add_item_count("stone",6)
	G.add_item_count("reagent2",1)
	_a(G.craft_recipe("pickaxe2",{"at_lathe":true}),8028)
	_a(G.count_item("pickaxe")==0 and G.count_item("pickaxe2")==1,8029)
	G.add_item_count("reagent1",1)
	G.add_item_count("log",1)
	_a(G.craft_recipe("torch",{"at_workbench":true}) and G.count_item("torch")==4 and G.count_item("log")==0,8030)
	G.add_item_count("heal2",1)
	G.select_item_slot(_slot_of(G,"heal2"))
	G.player_hp = 40
	G.heal_cd = 0
	_a(G.use_heal() and G.player_hp == 80 and G.heal_cd == 15,8031)
	_a(not G.use_heal(),8032)
	# v0.11: Ловец ест стопку ≥ 50 (49 остаётся); бонус ×2; один раз на тип, навсегда/в сейве.
	G.reset_state()
	G.set_slot(0,{"id":"stone","count":49})
	_a(G.storage_deposit(c,0,true)==49 and G.dream_bonus_seconds==0,8033)
	G.set_slot(0,{"id":"stone","count":1})
	_a(G.storage_deposit(c,0,true)==1 and G.dream_bonus_seconds==10,8034)
	G.set_slot(0,{"id":"stone","count":100})
	G.storage_deposit(c,0,true)
	_a(G.storage_slots(c,false,true)[0].count==100 and G.dream_bonus_seconds==10,8035)
	G.set_slot(0,{"id":"sword","count":1})
	_a(G.storage_deposit(c,0,true)==0,8036)
	G.add_item_count("reagent1",2)
	_a(G.storage_deposit(c,_slot_of(G,"reagent1"),true)==0,8037)
	var blob: Dictionary = G.to_save_dict()
	G.apply_save_dict(blob)
	_a(G.idea_eaten.has("stone") and G.dream_bonus_seconds==10 and G.storage_slots(c,false,true)[0].count==100,8038)
	_a(not G.storage_take(c,0,true),8039)
	G.enter_dream()
	_a(G.storage_take(c,0,true) and G.count_item("stone")==100,8040)
	_a(is_equal_approx(G.clarity,G.CLARITY_MAX+10.0*G.CLARITY_DRAIN_PER_SEC),8041)
	_a(G.storage_deposit(c,0,true)==0,8042)
	G.resolve_wake()
	# Chest roundtrip preserves worn tools and refuses mining while full.
	G.set_slot(0,{"id":"sword2","count":1,"durability":17})
	_a(G.storage_deposit(c,0,false)==1,8043)
	_a(not G.break_storage(c),8044)
	G.apply_save_dict(G.to_save_dict())
	_a(G.storage_take(c,0,false),8045)
	_a(G.get_slot(0).get("durability")==17,8046)
	_a(G.break_storage(c),8047)
	# Multipart occupancy and respawn fallback.
	G.reset_state()
	_a(G.place_wake_block(c,"bed"),8048)
	_a(G.wake_blocks.get(c+Vector3i.BACK,{}).get("kind")=="bed_foot",8049)
	_a(not G.place_wake_block(c+Vector3i.BACK,"stone"),8050)
	G.active_bed = G.cell_key(c)
	G.spawn_point = Vector3(c)+Vector3(0.5,1.1,0.5)
	G.add_item_count("pickaxe",1)
	G.select_item_slot(_slot_of(G,"pickaxe"))
	_a(G.mine_wake_block(c+Vector3i.BACK),8051)
	_a(not G.wake_blocks.has(c) and not G.wake_blocks.has(c+Vector3i.BACK) and G.spawn_point==G.creation_spawn,8052)
	_a(G.place_wake_block(c,"door") and G.toggle_door(c+Vector3i.UP),8053)
	_a(G.wake_blocks[c].open,8054)
	G.apply_save_dict(G.to_save_dict())
	_a(G.wake_blocks[c].open,8055)
	G.wake_blocks.clear()
	G.wake_blocks[c] = {"kind":"beacon"}
	_a(G.beacon_protects(c+Vector3i(10,10,-10)),8056)
	_a(not G.beacon_protects(c+Vector3i(11,0,0)),8057)
	var dust0: int = G.dust
	_a(G.suppress_mutation(c+Vector3i.RIGHT) and G.dust==dust0+5,8058)
	G.enter_dream()
	for i in range(11):
		G.place_dream_block(Vector3i(i,0,0),"drift")
	var res: Dictionary = G.resolve_wake()
	_a(res.dust==2,8059)
	# World layers and settlement distributions from deterministic plans.
	var CM: GDScript = load("res://scripts/chunk_manager.gd")
	_a(CM.depth_kind(-5)=="dirt" and CM.depth_kind(-6)=="stone" and CM.depth_kind(-18)=="deep_stone" and CM.depth_kind(-31)=="bedrock",8060)
	var cm: Node3D = CM.new()
	cm.panorama_mode = true
	cm._seed = G.DEV_SEED
	root.add_child(cm)
	_a(cm._is_settlement(Vector2i(2,1)),8061)
	var houses: Array = cm.ruin_plan(Vector2i(2,1))
	_a(houses.size()>=3 and houses.size()<=5,8062)
	var dev_center := Vector3(40,0,24)
	var dist: float = dev_center.distance_to(G.creation_spawn)
	_a(dist>=40 and dist<=50,8063)
	var settlements := 0
	var ruins := 0
	var large := 0
	var shapes := {}
	for x in range(-50,50):
		for z in range(-50,50):
			var coord := Vector2i(x,z)
			if cm._is_settlement(coord):
				settlements += 1
			elif cm.chunk_has_ruin(coord):
				ruins += 1
				var plan: Array = cm.ruin_plan(coord)
				shapes[int(plan[0].shape)] = true
				if int(plan[0].w)>=10:
					large += 1
	_a(shapes.size()==3 and large>0 and large<ruins/5,8064)
	print("SMOKE: v08 world samples=10000 ruins=",ruins," settlements=",settlements," large=",large," dev_settlement_distance=",dist," houses=",houses.size())
	cm.queue_free()
	# Torch collision: 1/15, 5-second successful-break cooldown.
	var host := Node3D.new()
	root.add_child(host)
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	G.wake_blocks[c] = {"kind":"torch"}
	G.wake_blocks[c+Vector3i.RIGHT] = {"kind":"torch"}
	var ana: Node3D = AS.spawn_at(host,Vector3(50,0,50),"smoke08")
	# v0.11.1: касание ломает ВСЕГДА — без шанса и без КД (try_break_torch — совместимый враппер).
	_a(ana.try_break_torch(c,0.99),8065)
	_a(not G.wake_blocks.has(c),8066)
	_a(ana.try_break_torch(c+Vector3i.RIGHT,0.99),8067)
	_a(not ana.try_break_torch(c+Vector3i.RIGHT,0.0),8068)   # уже сломан
	host.queue_free()
	# Falling drops only; placed unsupported blocks retain their grid position.
	var drop: CharacterBody3D = load("res://scripts/block_pickup.gd").new()
	drop.configure("stone")
	drop.position = Vector3(600,10,600)
	root.add_child(drop)
	G.wake_blocks[Vector3i(600,10,600)] = {"kind":"stone"}
	for i in range(12):
		await physics_frame
	_a(drop.position.y<10 and G.wake_blocks.has(Vector3i(600,10,600)),8069)
	drop.queue_free()
	# Закрытие инвентаря с предметом на курсоре не обновляет прочность.
	G.reset_state()
	var inv_ui: Control = load("res://scripts/inventory_ui.gd").new()
	root.add_child(inv_ui)
	G.set_slot(0,{"id":"pickaxe","count":1,"durability":66})
	inv_ui.open()
	inv_ui._on_slot_clicked(0,MOUSE_BUTTON_LEFT,false)
	inv_ui.close()
	_a(G.get_slot(0).get("durability")==66,1660)
	inv_ui.open()
	inv_ui._on_slot_clicked(0,MOUSE_BUTTON_LEFT,false)
	G.set_slot(0,{"id":"stone","count":1})
	inv_ui.close()
	_a(G.get_slot(1).get("durability")==66,1661)
	inv_ui.queue_free()
	# Полная транзакция алхимии: ингредиент-хилка берётся из подушки во сне.
	G.reset_state()
	G.enter_dream()
	G.on_mother_killed()
	# v0.11: алхимия во Сне — только кошель (4 р2 + 4 р3 + 60 осыпи); подушка не трогается.
	G.add_item_count("reagent2",4)
	G.add_item_count("reagent3",4)
	G.add_item_count("dust",60)
	G.add_to_pillow("heal1",1)
	_a(G.craft_recipe("alchemy",{"is_dream":true}),1662)
	_a(G.get_reagent_count(2)==0 and G.get_reagent_count(3)==0 and G.dust==0 and G.pillow_count("heal1")==1 and G.count_item("alchemy")==1,1663)
	# Маяк блокирует и источник, и цель распространения пасти.
	G.reset_state()
	var mouth := Vector3i(100,3,100)
	G.wake_blocks[mouth] = {"kind":"mouth"}
	G.wake_blocks[mouth+Vector3i.RIGHT] = {"kind":"planks"}
	G.wake_blocks[mouth+Vector3i(10,0,0)] = {"kind":"beacon"}
	_a(not G.spread_mouth_once(), 1670)
	G.wake_blocks.erase(mouth+Vector3i(10,0,0))
	_a(G.spread_mouth_once() and G.wake_blocks[mouth+Vector3i.RIGHT].kind == "mouth",1671)
	# Боковая полоса воды между слоями разной высоты добавляет ровно одну грань.
	var water_cm: Node3D = load("res://scripts/chunk_manager.gd").new()
	var water_host := Node3D.new()
	root.add_child(water_cm)
	water_cm.set_process(false)
	water_cm.add_child(water_host)
	water_cm._loaded[Vector2i.ZERO] = water_host
	water_cm._solid_by_chunk[Vector2i.ZERO] = {}
	water_cm._water = {Vector3i(3,3,3):8,Vector3i(4,3,3):8}
	water_cm._water_by_chunk[Vector2i.ZERO] = {Vector3i(3,3,3):true,Vector3i(4,3,3):true}
	water_cm._build_flow_water(Vector2i.ZERO)
	var equal_mesh: ArrayMesh = water_host.get_node("FlowWater").mesh
	var equal_count: int = equal_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	water_cm._water[Vector3i(4,3,3)] = 2
	water_cm._build_flow_water(Vector2i.ZERO)
	var unequal_mesh: ArrayMesh = water_host.get_node("FlowWater").mesh
	_a(unequal_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == equal_count+6,1672)
	water_cm.queue_free()
	# Порог задержки призраков и предел явно закреплены.
	var td_script: GDScript = load("res://scripts/threat_director.gd")
	_a(is_equal_approx(td_script.GHOST_RESPAWN_DELAY, 60.0),1673) # v0.11: было 25 с
	_a(td_script.MAX_GHOSTS_PER_SPOT == 3,1674)
	var director: Node = td_script.new()
	root.add_child(director)
	director.set_process(false)
	director.awake_time = 100.0
	_a(not director._ghost_can_spawn(0,1),1675)
	director.awake_time = 101.0
	_a(not director._ghost_can_spawn(0,0),1676)
	director.awake_time = 160.9
	_a(not director._ghost_can_spawn(0,0),1677)
	var gdump: Dictionary = JSON.parse_string(JSON.stringify(director.to_save_dict()))
	director.apply_save_dict(gdump)
	_a(not director._ghost_can_spawn(0,0),1678)
	director.awake_time = 161.0
	_a(director._ghost_can_spawn(0,0) and not director._ghost_can_spawn(0,3),1679)
	director.queue_free()
	G.reset_state()
	G.wake_blocks[c] = {"kind":"bed"}
	G.add_shape_parts(G.wake_blocks,c,"bed")
	G.active_bed = G.cell_key(c)
	_a(G.destroy_wake_structure(c+Vector3i.BACK),1680)
	_a(not G.wake_blocks.has(c) and not G.wake_blocks.has(c+Vector3i.BACK) and G.active_bed=="",1681)
	G.wake_blocks[c] = {"kind":"chest"}
	G.storage_slots(c)[0] = {"id":"stone","count":1}
	_a(not G.destroy_wake_structure(c) and G.wake_blocks.has(c),1682)
	G.reset_state()
	G.enter_dream()
	G.on_mother_killed()
	G.dust = 500
	G.add_item_count("reagent1",6)
	for i in range(36):
		G.set_slot(i,{"id":"stone","count":100})
	_a(not G.craft_recipe("idea_catcher",{"is_dream":true}),1683)
	_a(G.dust==500 and G.get_reagent_count(1)==6,1684)
	G.set_slot(0,{})
	_a(G.craft_recipe("idea_catcher",{"is_dream":true}) and G.dust==350,1685)
	G.reset_state()
	var old_save: Dictionary = G.to_save_dict()
	old_save["version"] = 7
	old_save["wake_blocks"] = {"1,0,1":{"kind":"bed"},"5,0,5":{"kind":"bed"},"5,0,6":{"kind":"stone"}}
	G.apply_save_dict(old_save)
	_a(G.wake_blocks.has(Vector3i(1,0,2)),1686)
	_a(G.wake_blocks[Vector3i(5,0,5)].get("legacy_compact",false) and G.wake_blocks[Vector3i(5,0,6)].kind=="stone",1687)
	_a(G.destroy_wake_structure(Vector3i(5,0,5)) and G.wake_blocks.has(Vector3i(5,0,6)),1688)
	var blocked_script := GDScript.new()
	blocked_script.source_code = 'extends "res://scripts/threat_director.gd"\nvar calls := 0\nfunc mobs_can_spawn() -> bool: return true\nfunc _count_all_enemies() -> int: return 0\nfunc _count_enemies() -> int: return 0\nfunc _spawn_one(_elite: bool) -> void: calls += 1\n'
	_a(blocked_script.reload()==OK,1689)
	var blocked: Node = blocked_script.new()
	root.add_child(blocked)
	blocked.set_process(false)
	blocked.apply_save_dict({"enemy_count":3})
	_a(blocked.calls == 32,1690)
	blocked.queue_free()
	await process_frame
	_v08_done = true
	print("SMOKE: v0.8 checks done")

var _v09_done := false
func _v09_checks() -> void:
	print("SMOKE: v0.9 checks")
	var G: Node = root.get_node("GameState")
	var A := preload("res://scripts/armor_rules.gd")
	var M := preload("res://scripts/mining_rules.gd")
	var Nav: GDScript = load("res://scripts/enemy_navigation.gd")
	# Exact mining/harvest numbers, including the last durability point.
	_a(is_equal_approx(M.seconds("dirt",""),0.75) and is_equal_approx(M.seconds("log",""),3.0),9001)
	_a(is_equal_approx(M.seconds("stone",""),7.5) and not M.drops("stone",""),9002)
	_a(M.seconds("stone","pickaxe")==3.0 and M.seconds("stone","pickaxe2")==1.5,9003)
	_a(M.seconds("dirt","pickaxe")==3.75 and M.seconds("ground","pickaxe2")==1.875,9004)
	for i in range(4):
		for tier in ["wood","scale"]:
			var id: String = tier+"_"+A.PARTS[i]
			_a(A.slot(id)==i and A.durability(id)==(A.WOOD_DURABILITY[i] if tier=="wood" else A.SCALE_DURABILITY[i]),9005)
			_a(ResourceLoader.exists("res://assets/icons/%s.png" % id),9006)
	# Ordinary world: all 8 recipes really consume materials, equip, wear, save and drop.
	G.begin_world("armor-test","","89",89,true)
	for tier in ["wood","scale"]:
		for i in range(4):
			var id: String = tier+"_"+A.PARTS[i]
			var material := "planks" if tier=="wood" else "anaconda_scale"
			var context := {"station":"sawmill","upgraded":true} if tier=="wood" else {"at_lathe":true}
			G.add_item_count(material,A.COST[i] if tier=="wood" else A.SCALE_COST[i])
			_a(not G.craft_recipe(id,{"at_workbench":true}),9007)
			_a(G.craft_recipe(id,context) and G.raw_count(material)==0,9008)
			_a(G.equip_armor_from_slot(_slot_of(G,id)),9009)
		_a(G.armor_points()==(7 if tier=="wood" else 15),9010)
		G.player_hp = 100; G._combo_log.clear(); G._iframes = 0
		var dealt: int = G.damage_player(10,"armor-test",true)
		_a(dealt==(8 if tier=="wood" else 5),9011)
		_a(G.armor[0].durability==A.durability(tier+"_helmet")-1,9012)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(G.to_save_dict()))
	G.apply_save_dict(saved)
	_a(G.armor_points()==15 and G.armor[2].durability==A.SCALE_DURABILITY[2]-1,9013)
	G.armor[0].durability = 1
	G.damage_player(5,"break-test",true)
	_a(G.armor[0].is_empty(),9014)
	var death: Array = G.collect_death_drop()
	_a(death.filter(func(d): return str(d.get("id","")).begins_with("scale_")).size()==3 and G.armor_points()==0,9015)
	# Isolate the real-scene command integration from older test fixtures.
	for group in ["player","chunk_manager","enemy","world_switcher","inventory_ui","craft_menu","threat_director","dev_console","day_cycle"]:
		for node in get_nodes_in_group(group):
			node.remove_from_group(group)
			node.set_process(false)
			node.set_physics_process(false)
	G.begin_world("v09 smoke","","6767676767",G.DEV_SEED,true)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	scene.set_meta("smoke",true)
	root.add_child(scene)
	current_scene = scene
	scene.switcher.show_result_ui=false
	await process_frame
	await physics_frame
	scene.player.set_physics_process(false)
	scene.build.set_process(false)
	scene.threat.set_process(false)
	var console: Node = get_first_node_in_group("dev_console")
	_a(console!=null and console.allowed() and console.open(),9016)
	_a(G.console_open and G.ui_blocked(),9017)
	console.close()
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_QUOTELEFT
	toggle.pressed = true
	console._input(toggle)
	_a(G.console_open,9071)
	console._input(toggle)
	_a(not G.console_open,9072)
	G.dev_mode = false
	_a(not console.open() and console.execute("give stone").begins_with("Ошибка"),9018)
	G.dev_mode = true
	_a(console.execute("help").contains("setblock") and console.execute("help").contains("fill"),9019)
	_a(console.completion_candidates("fill sto")==["fill stone"],9020)
	console.entry.text = "spawn ana"
	console.autocomplete()
	_a(console.entry.text=="spawn anaconda",9021)
	console.execute("seed")
	console.history_step(-1)
	_a(console.entry.text=="seed",9022)
	# Every command's actual effects, not just a success message.
	for cmd in ["god","fly","heal","hp 73","time night","time 9.5","time day","give torch 2","give beacon 2","give wood_helmet","give anaconda_scale 5","armor give wood"]:
		_a(not console.execute(cmd).begins_with("Ошибка"),9023)
	console.execute("time night")
	_a(G.is_night(),9060)
	console.execute("time 9.5")
	_a(G.clock_text(G.day_time)=="09:30",9061)
	console.execute("time night")
	console.execute("moon 0.61")
	var day: Node = get_first_node_in_group("day_cycle")
	_a(is_equal_approx(day.moon_energy,0.61) and day.get_moon().light_energy>0 and day.get_moon().light_energy<=0.610001,9064)
	console.execute("moon 0.47")
	_a(console.completion_candidates("moo")==["moon "] and G.to_save_dict().moon_energy==0.47,9065)
	console.execute("time day")
	_a(G.clock_text(G.day_time)=="12:00",9062)
	_a(G.god_mode and scene.player.flying and G.player_hp==73 and G.armor_points()==7,9024)
	_a(G.raw_count("wood_helmet")>0 and G.raw_count("anaconda_scale")>=5,9025)
	_a(G.damage_player(50,"god-test",true)==0 and G.player_hp==73,9026)
	_a(console.execute("hardness stone pickaxe").contains("3.000"),9027)
	_a(not console.execute("tp 3 3 8").begins_with("Ошибка") and scene.player.global_position==Vector3(3,3,8),9028)
	console.execute("tp spawn")
	_a(scene.player.global_position==G.spawn_point,9029)
	console.execute("cooldown reset")
	_a(G.mother_cooldown==0,9030)
	for mob in ["seam","elite","enemy1","enemy2","enemy3","enemy4","ghost","minion","mother","anaconda"]:
		_a(not console.execute("spawn "+mob).begins_with("Ошибка"),9031)
	_a(console._mobs("all").size()==9 and console._mobs("anaconda").is_empty(),9032)   # v0.11.1: два босса одновременно — никогда
	console.execute("mob damage 19 all")
	console.execute("mob speed 2.7 all")
	console.execute("mob hp 111 nearest")
	console.execute("mob tool pickaxe2 seam")
	for mob in console._mobs("all"):
		_a(Nav.combat_damage(mob,1)==19 and is_equal_approx(Nav.movement_speed(mob,1),2.7),9033)
	_a(console._mobs("nearest")[0].hp==111,9034)
	# Persistent crafting flag and live HP rebalance; new spawns use same base values.
	console.execute("sword2 on")
	# v0.11: крафт оружия больше НЕ раздувает HP врагов.
	_a(G.sword2_crafted and console._mobs("seam")[0].max_hp==111 and console._mobs("mother")[0].max_hp==620,9035)
	var flag_save: Dictionary = G.to_save_dict()
	_a(flag_save.sword2_crafted,9036)
	console.execute("sword2 off")
	_a(console._mobs("seam")[0].max_hp==111 and console._mobs("mother")[0].max_hp==620,9037)
	# Anaconda deterministic probability boundaries and real scale reward.
	for mm in console._mobs("mother"):
		mm.free()
	_a(not console.execute("spawn anaconda").begins_with("Ошибка") and console._mobs("anaconda").size()==1,90380)
	var ana: Node = console._mobs("anaconda")[0]
	var torch_cell := Vector3i(10,0,10)
	G.wake_blocks[torch_cell] = {"kind":"torch"}
	_a(ana.max_hp==1250 and ana.try_break_torch(torch_cell,0.99),9038)
	_a(not G.wake_blocks.has(torch_cell),9039)
	ana._die()
	_a(int(ana.get_meta("last_scale_drop"))>=6 and int(ana.get_meta("last_scale_drop"))<=22,9040)
	console.execute("kill all")
	await create_timer(1.6).timeout
	_a(console._mobs("all").is_empty(),9041)
	for cmd in ["setblock stone 5 2 8","fill planks 6 2 8 8 3 9","fill dirt 1"]:
		_a(not console.execute(cmd).begins_with("Ошибка"),9042)
	_a(G.wake_blocks[Vector3i(5,2,8)].kind=="stone" and G.wake_blocks[Vector3i(8,3,9)].kind=="planks",9043)
	_a(console.execute("fill stone 20").begins_with("Ошибка") and console.execute("fill stone 0 0 0 100 100 100").begins_with("Ошибка"),9044)
	console.execute("setblock bed 15 2 8")
	console.execute("setblock air 15 2 9")
	_a(not G.wake_blocks.has(Vector3i(15,2,8)),9045)
	console.execute("setblock torch 9 1 8")
	await physics_frame
	var torch_body: StaticBody3D = scene.wake_voxels._bodies[Vector3i(9,1,8)]
	_a(torch_body.collision_layer==32 and (scene.player.collision_mask&32)==0 and (scene.player.ray.collision_mask&32)!=0 and not G.wake_solid(Vector3i(9,1,8)),9046)
	# Real obstruction-timer destruction: dirt hand=.75s, mob=1.5s, never arbitrary adjacent blocks.
	var creature: CharacterBody3D = load("res://scripts/seam_creature.gd").new()
	scene.wake_world.add_child(creature)
	creature.set_physics_process(false)
	var cell := Vector3i(20,1,8)
	G.wake_blocks[cell] = {"kind":"dirt"}
	var cache := {}
	Nav.advance_mob_mining(creature,cell,"dirt",1.49,cache)
	_a(G.wake_blocks.has(cell),9047)
	Nav.advance_mob_mining(creature,cell,"dirt",0.02,cache)
	_a(not G.wake_blocks.has(cell),9048)
	creature.queue_free()
	# Real camera-ray mining: cracks follow elapsed time; last pick hit still drops stone.
	console.execute("fill air 29 4 7 33 7 13")
	console.execute("setblock stone 30 5 8")
	scene.player.global_position = Vector3(30.5,4,12)
	scene.player.camera.look_at(Vector3(30.5,5.5,8.5),Vector3.UP)
	G.set_slot(0,{"id":"pickaxe","count":1,"durability":1})
	G.select_item_slot(0)
	G.dev_mode = false
	await physics_frame
	await process_frame
	var pickup_before := get_nodes_in_group("pickup").size()
	scene.build._tick_mining(1.05)
	_a(scene.build.cracks.visible and scene.build.cracks.stage==3,9066)
	scene.build._tick_mining(2.0)
	_a(not G.wake_blocks.has(Vector3i(30,5,8)) and G.get_slot(0).get("id","")=="" and get_nodes_in_group("pickup").size()==pickup_before+1,9067)
	G.dev_mode = true
	console.execute("setblock stone 30 5 8")
	G.dev_mode = false
	await physics_frame
	await process_frame
	pickup_before = get_nodes_in_group("pickup").size()
	scene.build._place_cooldown = 0.0
	scene.build._tick_mining(7.6)
	_a(not G.wake_blocks.has(Vector3i(30,5,8)) and get_nodes_in_group("pickup").size()==pickup_before,9068)
	G.dev_mode = true
	console.execute("setblock torch 31 5 10")
	scene.player.global_position = Vector3(29,5,10.5)
	await physics_frame
	await process_frame
	_a(not scene.player.test_move(scene.player.global_transform,Vector3(4,0,0)),9069)
	var q := PhysicsRayQueryParameters3D.create(Vector3(30,5.5,10.5),Vector3(33,5.5,10.5),32)
	var hit: Dictionary = scene.player.get_world_3d().direct_space_state.intersect_ray(q)
	_a(not hit.is_empty() and hit.collider.is_in_group("torch"),9070)
	# Ten distinct real overlay textures and progress stages.
	for i in range(10):
		scene.build.cracks.show_progress(Vector3i(5,2,8),float(i)/10+0.01)
		_a(scene.build.cracks.stage==i and scene.build.cracks.visible and scene.build.cracks._textures[i]!=null,9049)
	scene.build.cracks.hide()
	# v0.9.1: real imported model geometry, materials, filtering and ten sparse alpha masks.
	var bt091: GDScript = load("res://scripts/block_tex.gd")
	for tool in ["pickaxe","pickaxe2"]:
		var mesh091: ArrayMesh = bt091.tool_mesh(tool)
		_a(mesh091.get_surface_count()==2 and mesh091.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==36,9100)
		_a(mesh091.surface_get_material(0).texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,9101)
	var prev_pixels := 0
	for texture in scene.build.cracks._textures:
		var im: Image = texture.get_image()
		var pixels := 0
		_a(im.get_width()==16 and im.get_height()==16,9102)
		for y in range(16):
			for x in range(16):
				var color := im.get_pixel(x,y)
				if color.a>0:
					pixels += 1
					_a(color.a>=0.6 and color.a<=0.8 and color.r<0.15,9103)
		_a(pixels>prev_pixels and pixels<130,9104)
		prev_pixels = pixels
	_a(scene.build.cracks._mat.albedo_color==Color.WHITE,9105)
	await _v091_door_checks(scene,console)
	# Fog distance and far plane really follow render distance.
	var settings: Node = root.get_node("GameSettings")
	var old_r: int = settings.render_distance
	settings.render_distance = 3
	settings.apply_distance_fog(scene.get_node("WorldEnvironment").environment)
	var env: Environment = scene.get_node("WorldEnvironment").environment
	_a(env.fog_mode==Environment.FOG_MODE_DEPTH and env.fog_depth_end==40 and env.fog_density==1.0 and scene.player.camera.far==48,9050)
	settings.render_distance = old_r
	# Actual worker result: deterministic mesh, non-main thread, no scene Nodes in job.
	var cm: Node = scene.wake_chunks
	var job: RefCounted = cm._job_for(Vector2i(2,1))
	var job2: RefCounted = cm._job_for(Vector2i(2,1))
	var tid := WorkerThreadPool.add_task(job.run)
	var tid2 := WorkerThreadPool.add_task(job2.run)
	WorkerThreadPool.wait_for_task_completion(tid)
	WorkerThreadPool.wait_for_task_completion(tid2)
	_a(job._ug_tiles(Vector3i(0,-5,0),false)==preload("res://scripts/block_tex.gd").faces_for("dirt") and job._ug_tiles(Vector3i(0,-17,0),false)==preload("res://scripts/block_tex.gd").faces_for("stone"),9074)
	_a(job.result.worker_id!=OS.get_main_thread_id() and cm.worker_chunk_count>=9 and cm.last_worker_id!=OS.get_main_thread_id(),9051)
	_a(job.result.solids==job2.result.solids and job.result.geometry.stream.v==job2.result.geometry.stream.v,9052)
	_a(job.grass_tint(4,5)==job2.grass_tint(4,5) and job.grass_tint(4,5)!=job.grass_tint(40,50),9053)
	var reagent_target := 0
	for i in range(1000): reagent_target += job.settlement_reagent_target(Vector2i(i,100))
	_a(float(reagent_target)/1000.0>12.6 and float(reagent_target)/1000.0<12.9,9054)
	var epoch_cm: Node3D = load("res://scripts/chunk_manager.gd").new()
	root.add_child(epoch_cm)
	epoch_cm.set_process(false)
	epoch_cm._queue_job(Vector2i(1,0))
	var old_task: int = epoch_cm._jobs[Vector2i(1,0)].id
	epoch_cm._terrain_edited(Vector3i(16,0,0))
	while not WorkerThreadPool.is_task_completed(old_task): await process_frame
	epoch_cm._poll_jobs(1)
	_a(epoch_cm.get_loaded_count()==0 and Vector2i(1,0) in epoch_cm._pending,9073)
	epoch_cm.queue_free()
	print("SMOKE: v09 thread=%s main=%s worker_chunks=%d settlement_target_mean=%.3f armor wood=7 scale=15 damage10=8/5" % [job.result.worker_id,OS.get_main_thread_id(),cm.worker_chunk_count,float(reagent_target)/1000.0])
	# Full-inventory equipment drag/swap: neither item nor individual durability is lost.
	var ui: Node = get_first_node_in_group("inventory_ui")
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i,{"id":"stone","count":100})
	G.set_slot(0,{"id":"pickaxe2","count":1,"durability":123})
	G.armor[0] = {"id":"wood_helmet","count":1,"durability":78}
	ui._on_armor_clicked(0,MOUSE_BUTTON_LEFT,false)
	ui._on_slot_clicked(0,MOUSE_BUTTON_LEFT,false)
	ui.close()
	_a(G.armor[0].id=="wood_helmet" and G.armor[0].durability==78 and G.get_slot(0).id=="pickaxe2" and G.get_slot(0).durability==123,9063)
	console.execute("world dream")
	_a(G.is_dream() and not console.execute("setblock deep_stone 10 5 10").begins_with("Ошибка"),9055)
	_a(G.dream_blocks[Vector3i(10,5,10)].kind=="deep_stone",9056)
	console.execute("fill planks 12 5 10 14 5 12")
	_a(G.dream_blocks[Vector3i(14,5,12)].kind=="planks",9057)
	console.execute("world wake")
	_a(not G.is_dream(),9058)
	var hud: Node = scene.get_node("HUD")
	var n: int = hud._chat.size()
	hud.add_chat("Сон. ЛКМ — блок")
	_a(hud._chat.size()==n and hud._name_label.offset_top<hud._hp_text.offset_top,9059)
	console.close()
	scene.queue_free()
	await process_frame
	current_scene = null
	G.reset_state()
	var moon_old: Dictionary = G.to_save_dict()
	moon_old.erase("moon_revision")
	moon_old.moon_energy = 0.47
	G.apply_save_dict(moon_old)
	_a(is_equal_approx(G.moon_energy,0.56),9106)
	G.moon_energy = 0.47
	G.apply_save_dict(G.to_save_dict())
	_a(is_equal_approx(G.moon_energy,0.47),9107)
	G.reset_state()
	_v09_done = true
	print("SMOKE: v0.9 checks done")

func _v091_door_checks(scene: Node,console: Node) -> void:
	var G: Node = root.get_node("GameState")
	var c := Vector3i(80,5,80)
	var vox: Node
	for candidate in get_nodes_in_group("voxel_world"):
		if not candidate.is_dream_layer and scene.is_ancestor_of(candidate): vox = candidate
	var mesh: ArrayMesh = preload("res://scripts/block_tex.gd").wooden_door_mesh()
	_a(is_equal_approx(mesh.get_aabb().size.y,2.0) and mesh.get_aabb().size.x<1.1 and mesh.get_aabb().size.z<0.3,9200)
	_a(mesh.surface_get_material(0).texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,9201)
	for facing in range(4):
		G.wake_blocks[c] = {"kind":"door","facing":facing,"open":false}
		G.add_shape_parts(G.wake_blocks,c,"door")
		vox._rebuild_from_state()
		await physics_frame
		await physics_frame
		var center := Vector3(c)+Vector3(0.5,1,0.5)
		var normal := Basis(Vector3.UP,float(facing)*PI/2)*Vector3.BACK
		var q := PhysicsRayQueryParameters3D.create(center+normal*2,center-normal*2,4)
		var hit: Dictionary = scene.player.get_world_3d().direct_space_state.intersect_ray(q)
		_a(not hit.is_empty() and hit.collider.get_meta("voxel_cell")==c,9202)
		var hinge_closed: Vector3 = vox._meshes[c].position+vox._meshes[c].basis*Vector3(-0.5,0,0)
		scene.player.global_position = Vector3(c)+Vector3(0.5,0.05,0.5)+normal*1.5
		_a(scene.player.test_move(scene.player.global_transform,-normal*3),9203)
		_a(console.execute("door toggle 80 6 80")=="Дверь: toggle",9204) # upper half routes to root
		await physics_frame
		await physics_frame
		var hinge_open: Vector3 = vox._meshes[c].position+vox._meshes[c].basis*Vector3(-0.5,0,0)
		_a(hinge_open.distance_to(hinge_closed)<0.0001 and not G.wake_solid(c),9205)
		var debug_hit: Dictionary = scene.player.get_world_3d().direct_space_state.intersect_ray(q)
		if not debug_hit.is_empty(): print("DOOR DEBUG ",facing," ",debug_hit," state=",G.wake_blocks[c]," body=",vox._bodies[c].position," rot=",vox._bodies[c].rotation)
		_a(debug_hit.is_empty(),9206)
		_a(not scene.player.test_move(scene.player.global_transform,-normal*3),9207)
		var leaf_center: Vector3 = vox._bodies[c].position
		var leaf_normal: Vector3 = vox._bodies[c].basis*Vector3.BACK
		var leaf_ray := PhysicsRayQueryParameters3D.create(leaf_center+leaf_normal*0.5,leaf_center-leaf_normal*0.5,4)
		hit = scene.player.get_world_3d().direct_space_state.intersect_ray(leaf_ray)
		_a(not hit.is_empty() and hit.collider.get_meta("voxel_cell")==c,9208) # opened leaf remains clickable
		scene.player.camera.look_at(leaf_center)
		_a(scene.build._toggle_aimed_door(),9209) # real RMB interaction path closes the opened leaf
		await physics_frame
		await physics_frame
		_a(G.wake_solid(c),9210)
	_a(console.execute("door rotate 80 5 80")=="Дверь: rotate" and G.wake_blocks[c].facing==0,9211)
	_a(console.completion_candidates("door ").size()==2 and console.execute("help").contains("door toggle"),9212)
	var saved: Dictionary = G._blocks_from_json(G._blocks_to_json(G.wake_blocks))
	_a(saved[c].facing==0 and not saved[c].open and saved[c+Vector3i.UP].root==G.cell_key(c),9213)
	G.remove_shape(G.wake_blocks,c)
	vox._rebuild_from_state()
	console.execute("world dream")
	scene.player.set_physics_process(false)
	G.set_slot(0,{"id":"door","count":1})
	G.select_item_slot(0)
	scene.player.camera.look_at(scene.player.camera.global_position+Vector3.LEFT)
	var d := Vector3i(90,5,80)
	scene.build._place_at(d)
	_a(G.dream_blocks[d].facing==1 and G.dream_blocks.has(d+Vector3i.UP),9214)
	G.dream_blocks[d]["open"] = true
	G.select_anchor(G.AnchorType.NAIL)
	var anchor_ready:Dictionary=G.anchor_preview(d)
	for attempt in range(300):
		if anchor_ready.ready: break
		await process_frame;anchor_ready=G.anchor_preview(d)
	_a(anchor_ready.ready and G.try_place_anchor(d),9215)
	G.resolve_wake()
	_a(G.wake_blocks[d].facing==1 and G.wake_blocks[d].open and G.wake_blocks.has(d+Vector3i.UP),9216)
	G.remove_shape(G.wake_blocks,d)
	vox._rebuild_from_state()
	print("SMOKE: door 4 facings, hinge, player collision, open-leaf ray, console, save OK")

func _v010_build_checks() -> void:
	var G: Node = root.get_node("GameState")
	G.reset_state();G.current_world=G.World.DREAM
	var vox: Node3D=load("res://scripts/voxel_world.gd").new()
	vox.is_dream_layer=true;root.add_child(vox);vox.set_process(false)
	var sync_before: int=vox.sync_count
	for i in range(1000):
		G.place_dream_block(Vector3i(1024+i%40,5+int(i/400),int(i/40)%10),"planks")
	vox.flush_dirty()
	_a(vox._placed_chunks.size()==3 and vox._meshes.is_empty() and vox._bodies.is_empty(),10001)
	_a(vox._data.size()==1000 and vox.sync_count==sync_before,10002)
	var rebuilt: int=vox.mesh_rebuild_count
	var c:=Vector3i(1039,5,0)
	G.remove_dream_block(c);vox.flush_dirty()
	_a(not vox._data.has(c) and vox.mesh_rebuild_count==rebuilt+2,10003)
	var b:=Vector3i(1100,5,0)
	G.place_dream_block(b,"bed");vox.flush_dirty()
	_a(vox._bodies.has(b) and vox._data.has(b+Vector3i.BACK),10004)
	G.remove_dream_block(b+Vector3i.BACK);vox.flush_dirty()
	_a(not vox._bodies.has(b) and not vox._data.has(b+Vector3i.BACK),10005)
	_a(vox.sync_count==sync_before,10006)
	vox.queue_free();await process_frame;G.reset_state()
	print("SMOKE: v0.10 incremental 1000 blocks / 3 meshes+bodies, boundary neighbours, multicell remove, no full resync OK")

func _v010_gameplay_checks() -> void:
	var G: Node=root.get_node("GameState")
	G.begin_world("v010 test","","6767676767",G.DEV_SEED,true)
	var scene: Node=load("res://scenes/main.tscn").instantiate();scene.set_meta("smoke",true);root.add_child(scene);current_scene=scene;scene.switcher.show_result_ui=false
	await process_frame
	var console: Node=get_first_node_in_group("dev_console")
	var hud: Node=scene.get_node("HUD")
	_a(console.execute("debug on").contains("true") and hud._debug_label.visible,10010)
	root.get_node("GameSettings").settings_changed.emit()
	_a(hud._debug_label.visible and hud._debug_label.text.contains("XYZ") and hud._debug_label.text.contains("Чанк"),10011)
	console.execute("debug off")
	_a(not hud._debug_label.visible and console.completion_candidates("sword3 ").size()==3,10012)
	for cmd in console.COMMAND_HELP:
		_a(console.execute("help "+cmd).contains("Пример:"),10013)
	G.dev_mode=false
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i,{})
	G.set_slot(4,{"id":"heal2","count":2});G.set_slot(9,{"id":"heal1","count":3});G.select_item_slot(9);G.player_hp=10;G.heal_cd=0
	_a(G.use_heal() and G.player_hp==50 and G.get_slot(4).count==1 and G.get_slot(9).count==3,10014)
	_a(not G.use_heal() and G.heal_cd>14.0,10015)
	G.heal_cd=0
	_a(G.use_heal("heal1") and G.player_hp==70 and G.get_slot(9).count==2,10016)
	var ui: Node=get_first_node_in_group("inventory_ui")
	ui._on_slot_clicked(4,MOUSE_BUTTON_LEFT,false);ui._on_slot_clicked(4,MOUSE_BUTTON_LEFT,false);ui.close()
	_a(not ui.has_method("_on_quick_heal_clicked") and ui.find_child("HealHelp",true,false)==null and ui.find_children("*","Label",true,false).all(func(l): return not str(l.text).contains("ЛКМ")),10116)
	_a(G.count_item("heal2")==1 and G.count_item("heal1")==2,10017)
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i,{})
	G.add_item_count("sword2",1);G.add_item_count("anaconda_scale",5);G.set_sword3_flag(false)
	_a(G.craft_recipe("sword3",{"at_lathe":true}) and G.sword3_crafted and G.count_item("sword2")==0 and G.count_item("anaconda_scale")==0 and G.count_item("sword3")==1,10018)
	_a(G.tool_max("sword3")==700 and load("res://scripts/item_db.gd").icon("sword3")!=null,10019)
	var save: Dictionary=G.to_save_dict();save.erase("sword3_crafted");save.erase("progression_revision");save.sword2_crafted=true
	G.apply_save_dict(save);_a(not G.sword3_crafted,10020)
	var door:=Vector3i(120,7,120)
	_a(G.place_wake_block(door,"door",3) and G.wake_blocks[door].facing==3,10021)
	for vox in get_nodes_in_group("voxel_world"):
		if not vox.is_dream_layer and scene.is_ancestor_of(vox):
			_a(vox._bodies[door].get_child(0).shape.size==Vector3(1,2,0.125),10022)
	G.dev_mode=true
	for command in ["sword give scale","potion give 2 2","potion cooldown reset","armor stats","armor repair","reagents give 3","dust 431","anchor give nail 2","anchor select wedge","beacon give 2","bed spawn","chunks stats","chunks radius 3"]:
		_a(not console.execute(command).begins_with("Ошибка"),10023)
	_a(int(G.pouch.dust)==431 and G.selected_anchor==G.AnchorType.WEDGE,10024)
	_a(scene.dream_chunks.get_loaded_count()==0,10025)
	var sync_before: int=scene.switcher.sync_sequences
	var wake_clock: float=scene.wake_chunks._clock;var wake_loaded: int=scene.wake_chunks.get_loaded_count()
	console.execute("world dream")
	for i in range(8): await process_frame
	_a(scene.switcher.sync_sequences==sync_before+1 and scene.wake_world.process_mode==Node.PROCESS_MODE_DISABLED and scene.dream_world.process_mode==Node.PROCESS_MODE_INHERIT,10026)
	_a(scene.wake_chunks._clock==wake_clock and scene.wake_chunks.get_loaded_count()==wake_loaded,10027)
	console.execute("world wake")
	var dream_clock: float=scene.dream_chunks._clock;var dream_loaded: int=scene.dream_chunks.get_loaded_count()
	for i in range(8): await process_frame
	_a(scene.switcher.sync_sequences==sync_before+2 and scene.dream_chunks._clock==dream_clock and scene.dream_chunks.get_loaded_count()==dream_loaded,10028)
	_a(not console.execute("water stats").begins_with("Ошибка") and not console.execute("chunks revisions").begins_with("Ошибка"),10029)
	console.close();scene.queue_free();await process_frame;current_scene=null;G.reset_state()
	print("SMOKE: v0.10 F3, potion slot priority/quick alias, sword3 craft+legacy migration, grid door and expanded Russian console OK")

func _v010_stream_checks() -> void:
	var G: Node=root.get_node("GameState");G.begin_world("stream test","","1337",1337,false)
	var player:=Node3D.new();root.add_child(player)
	var cm: Node3D=load("res://scripts/chunk_manager.gd").new();root.add_child(cm);cm.setup(player,1337);cm.set_process(false);cm.load_radius=1;cm.unload_radius=4;cm._pending.clear()
	cm._queue_job(Vector2i(1,0));cm._queue_job(Vector2i(3,0))
	cm._terrain_edited(Vector3i(16,-2,0))
	while not cm._jobs.is_empty():
		cm._poll_jobs(10);await process_frame
	_a(cm._loaded.has(Vector2i(3,0)) and not cm._loaded.has(Vector2i(1,0)) and cm.stale_jobs_discarded==1,10030)
	_a(cm._chunk_revisions.has(Vector2i.ZERO) and not cm._chunk_revisions.has(Vector2i(3,0)),10031)
	for i in range(10000): G.mark_reagent_collected("%d,0,1000000"%(1000000+i))
	cm._job_for(Vector2i.ZERO) # one-off index construction belongs to save/load, not each snapshot
	G.mark_reagent_collected("16,0,1")
	var job: RefCounted=cm._job_for(Vector2i.ZERO)
	_a(job.collected.size()==1 and cm.snapshot_cells_copied==1,10032)
	print("SMOKE: v0.10 bounded snapshot 10001 collected IDs => %d copied / %d us (index once %d us)"%[cm.snapshot_cells_copied,cm.last_snapshot_usec,G.snapshot_index_usec])
	G.current_world=G.World.DREAM
	var pending: int=cm._pending.size();var updates: int=cm.water_updates_total;var clock: float=cm._clock
	cm._process(1.0);cm._water_process(1.0)
	_a(cm._pending.size()==pending and cm._clock==clock and cm.water_updates_total==updates,10033)
	G.current_world=G.World.WAKE
	for x in range(12,20):
		for y in range(-2,0):
			for z in range(8,11): G.remove_terrain_cell_silent(Vector3i(x,y,z),"ground")
	cm.rebuild_chunk(Vector2i.ZERO);cm.rebuild_chunk(Vector2i(1,0));cm.load_all_pending()
	var source:=Vector3i(12,-1,9);cm._water_src[source]=true
	if not cm._water_src_by_chunk.has(Vector2i.ZERO): cm._water_src_by_chunk[Vector2i.ZERO]={}
	cm._water_src_by_chunk[Vector2i.ZERO][source]=true;cm.water_notify(source);cm.water_settle(100)
	_a(cm.water_cell_count()>10 and not cm._water_by_chunk.get(Vector2i(1,0),{}).is_empty(),10034)
	var n: int=cm.water_mesh_builds;cm._water_process(1.0)
	_a(cm.water_mesh_builds==n,10035)
	var c:=Vector3i(16,-2,9);var level: int=cm.water_level(c)
	cm._water_set(c,level);_a(cm._water_dirty.is_empty(),10036)
	cm._water_dirty[Vector2i.ZERO]=true;cm._water_dirty[Vector2i(1,0)]=true
	cm._rebuild_water_meshes(1);_a(cm._water_dirty.size()==1,10037);cm._rebuild_water_meshes()
	cm._unload_chunk(Vector2i(1,0));_a(G.flowing_water.has(c),10038)
	cm.ensure_chunk_loaded(Vector2i(1,0));_a(cm.water_level(c)==level and level>0,10039)
	var saved: Dictionary=G.to_save_dict();G.apply_save_dict(saved)
	_a(int(G.flowing_water.get(c,0))==level and G.dream_mapping=="parallel",10040)
	print("SMOKE: v0.10 water active=%d border level=%d idle rebuilds=0 cap/unload/reload/save OK"%[cm.water_cell_count(),level])
	# clear_all retires work without a global join; teardown is allowed to join for safety.
	cm._queue_job(Vector2i(2,1));cm.clear_all();_a(cm._jobs.is_empty() and not cm._retired_jobs.is_empty(),10041)
	cm.queue_free();player.queue_free();await process_frame;G.reset_state()

func _v010_entity_checks() -> void:
	var G: Node=root.get_node("GameState");G.begin_world("entity test","","6767676767",G.DEV_SEED,true)
	var scene: Node=load("res://scenes/main.tscn").instantiate();scene.set_meta("smoke",true);root.add_child(scene);current_scene=scene;scene.switcher.show_result_ui=false
	var player: Node=scene.player;player.auto_pickup_enabled=false;player.set_physics_process(false);player.global_position=Vector3(3.5,0.1,3.5)
	G.dev_mode=false
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i,{})
	for i in range(200):
		var pickup: Node3D=load("res://scripts/block_pickup.gd").new();pickup.configure("planks");scene.wake_world.add_child(pickup);pickup.global_position=player.global_position+Vector3((i%10)*0.04,0.6,(i/10)*0.015);pickup.set_physics_process(false)
	await physics_frame;await physics_frame
	var emitted: Array[int]=[0];var callback: Callable=func()->void:emitted[0]+=1
	G.inventory_changed.connect(callback)
	var ticks:=0;var maximum:=0
	while G.count_item("planks")<200 and ticks<50:
		var picked: int=player.auto_pickup();_a(picked<=64,10050);maximum=maxi(maximum,player.pickup_last_usec);ticks+=1;await process_frame
	_a(G.count_item("planks")==200 and emitted[0]<=ticks,10051)
	G.inventory_changed.disconnect(callback)
	var gid: int=G.add_grave(player.global_position,[{"id":"stone","count":3}]);var pile: Node3D=load("res://scripts/grave_pile.gd").new();pile.configure(gid);scene.wake_world.add_child(pile);pile.global_position=player.global_position
	await physics_frame;await physics_frame
	_a(player.auto_pickup()>0 and pile.collected and G.count_item("stone")==3,10052)
	var culler: Node=scene.get_node("Systems/EntityCuller")
	var far:=Node3D.new();scene.wake_world.add_child(far);far.add_to_group("enemy");far.position=Vector3(1000,1,1000);far.set_process(true);far.set_physics_process(true)
	var boss:=Node3D.new();scene.wake_world.add_child(boss);boss.add_to_group("enemy");boss.add_to_group("anaconda");boss.position=Vector3(1000,1,1000);boss.set_process(true);boss.set_physics_process(true)
	culler._process(0.31);_a(not far.visible and not far.is_processing() and not far.is_physics_processing(),10053)
	_a(boss.visible and boss.is_processing() and boss.is_physics_processing(),10054)
	far.global_position=player.global_position;culler._process(0.31);_a(far.visible and far.is_processing() and far.is_physics_processing(),10055)
	far.remove_from_group("enemy");boss.remove_from_group("enemy");boss.remove_from_group("anaconda");far.queue_free();boss.queue_free()
	var Nav=load("res://scripts/enemy_navigation.gd")
	var search: Dictionary=Nav._new_search(Vector3(2,0,2),Vector3(6,0,2),scene.wake_chunks);var turns:=0
	while not search.done and turns<100: Nav._advance_search(search,scene.wake_chunks,500);turns+=1
	_a(search.done and search.out.size()>=2 and search.out.back().distance_to(Vector3(6.5,0,2.5))<0.01,10056)
	for i in range(1000): G.wake_blocks[Vector3i(10000+i,0,10000)]={"kind":"stone"}
	var near:=Vector3i(3,1,3);G.wake_blocks[near]={"kind":"planks"}
	_a(Nav.nearest_adjacent_block(player)==near,10057)
	for node in get_nodes_in_group("reagent"):
		if scene.is_ancestor_of(node): _a(not node.is_processing(),10058)
	print("SMOKE: v0.10 local pickup200 in %d ticks / signals%d / max%dus; grave sensor, full culling/boss exclusion, cooperative A*, local nearest block OK"%[ticks,emitted[0],maximum])
	scene.queue_free();await process_frame;current_scene=null;G.reset_state()

func _v010_transfer_checks() -> void:
	var Plan=load("res://scripts/transfer_plan.gd");var gs:Node=load("res://scripts/game_state.gd").new();root.add_child(gs)
	var times:Array=[]
	for n in [100,500,1000]:
		gs.reset_state();gs.enter_dream();gs.world_seed_dream=12345
		var cells:Array=[]
		for i in range(n):
			var c:=Vector3i(200+i%10,5+int(i/100),200+int(i%100/10));gs.place_dream_block(c,"drift");gs.dream_blocks[c].anchored=true;cells.append(c)
		gs.pending_anchors=[{"type":2,"cells":cells,"receipt":{"dev":true}}]
		var snapshot:Dictionary=gs.to_save_dict();var preflight:Dictionary=gs.transfer_plan()
		_a(preflight.ok and preflight.count==n and preflight.cells.size()==n,10060)
		var result:Dictionary=gs.resolve_wake();var first:Dictionary=gs._blocks_to_json(gs.wake_blocks)
		_a(result.ok and result.transferred==n and result.mutations<=floori(n*0.03) and gs.dream_blocks.is_empty(),10061)
		times.append({"blocks":n,"preflight_us":gs.last_transfer_preflight_usec,"apply_us":gs.last_transfer_apply_usec,"mutations":result.mutations})
		gs.apply_save_dict(snapshot);var second:Dictionary=gs.resolve_wake()
		_a(first==gs._blocks_to_json(gs.wake_blocks) and second.mutations==result.mutations,10062)
	gs.reset_state();gs.enter_dream();gs.nails=3;gs.reagent_counts=[0,1,2];gs.select_anchor(gs.AnchorType.NAIL)
	var c:=Vector3i(250,5,250);gs.place_dream_block(c,"door",3);gs.dream_blocks[c].open=true;gs.wake_blocks[c+Vector3i.UP]={"kind":"stone","mutant":false}
	var wallet:Dictionary=gs.pouch.duplicate();var clarity_before:float=gs.clarity
	_a(not gs.try_place_anchor(c+Vector3i.UP) and gs.nails==3 and wallet==gs.pouch and gs.clarity==clarity_before and gs.pending_anchors.is_empty(),10063)
	gs.remove_shape(gs.wake_blocks,c+Vector3i.UP)
	_a(gs.try_place_anchor(c+Vector3i.UP) and gs.pending_anchors[0].cells.size()==2 and gs.pouch.reagent2==0 and gs.nails==2,10064)
	_a(not gs.try_place_anchor(c) and gs.nails==2,10065)
	var reserved:Dictionary=gs.to_save_dict();gs.apply_save_dict(reserved)
	_a(gs.pending_anchors[0].receipt.wallet.reagent2==1,10066)
	gs.wake_blocks[c+Vector3i.UP]={"kind":"stone","mutant":false};var failed:Dictionary=gs.resolve_wake()
	_a(not failed.ok and failed.blocked==1 and gs.is_dream() and gs.dream_blocks.size()==2 and gs.nails==2 and gs.wake_blocks.size()==1,10067)
	gs.add_typed_reagent(2,100);var refund:Dictionary=gs.cancel_anchors()
	_a(refund.reagents==1 and gs.pouch.reagent2==101 and gs.nails==3 and gs.pending_anchors.is_empty() and not gs.dream_blocks[c].anchored,10068)
	gs.apply_save_dict(gs.to_save_dict());gs.spend_reagents(1)
	_a(gs.pouch.reagent2==100 and gs.pouch.reagent3==2,10069)
	gs.remove_shape(gs.wake_blocks,c+Vector3i.UP);_a(gs.try_place_anchor(c),10070)
	var aborted:Dictionary=gs.resolve_wake(true)
	_a(aborted.ok and aborted.aborted and aborted.transferred==0 and gs.dream_blocks.size()==2 and gs.pending_anchors.is_empty() and not gs.is_dream(),10071)
	gs.enter_dream();_a(gs.dream_blocks.has(c) and gs.try_place_anchor(c),10072)
	var transferred:Dictionary=gs.resolve_wake();_a(transferred.transferred==1 and gs.wake_blocks[c].facing==3 and gs.wake_blocks[c].open and gs.wake_blocks[c+Vector3i.UP].root==gs.cell_key(c),10073)
	gs.reset_state();gs.enter_dream();gs.nails=5;gs.reagent_counts=[10,10,10]
	var at_spawn:=Vector3i(floori(gs.creation_spawn.x),floori(gs.creation_spawn.y),floori(gs.creation_spawn.z));gs.place_dream_block(at_spawn,"stone")
	_a(not gs.try_place_anchor(at_spawn) and gs.nails==5,10074)
	var source:Dictionary={c:{"kind":"stone"}};var terrain:Dictionary={c:"stone"}
	_a(not Plan.build(source,{},[c],terrain,[]).ok,10075)
	source[c]={"kind":"door"};_a(not Plan.build(source,{},[c],{},[]).ok,10076)
	source.clear();var roots:Array=[]
	for i in range(10000): var cell:=Vector3i(i%100,10,int(i/100));source[cell]={"kind":"stone"};roots.append(cell)
	var rolled:Dictionary=Plan.mutations(source,roots,[],98765,[])
	_a(rolled.rolled>600 and rolled.rolled<800 and rolled.cells.size()==300,10077)
	var protected_roots:Array=[];source.clear()
	for i in range(1000):var cell:=Vector3i(200+i%10,5+int(i/100),200+int(i%100/10));source[cell]={"kind":"stone"};protected_roots.append(cell)
	var protected_result:Dictionary=Plan.mutations(source,protected_roots,[Vector3i(205,10,205)],12345,[])
	_a(protected_result.cells.is_empty() and protected_result.protected>30 and protected_result.protected<110,10078)
	# Real v0.9.1 serializer fixture (source commit recorded in JSON), not a new save with fields removed.
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v091_save.json"));gs.apply_save_dict(old)
	_a(old._fixture_source.begins_with("89cbb0d") and gs.dream_mapping=="legacy_workshop" and not gs.sword3_crafted,10079)
	_a(gs.inv_wake[0].durability==117 and gs.armor[1].id=="scale_chest" and gs.armor[1].durability==37 and gs.storage_slots(Vector3i(45,4,40),false)[0].count==23 and gs.world_storage.has("w:45,4,40"),10080)
	_a(gs.wake_blocks[Vector3i(40,4,40)].facing==3 and gs.wake_blocks[Vector3i(40,4,40)].open and gs.transfer_plan().cells.size()==2,10081)
	var old_r1:int=gs.pouch.reagent1;gs.cancel_anchors();_a(gs.pouch.reagent1==old_r1+1 and gs.dream_blocks.size()==2,10082)
	gs.queue_free();await process_frame
	var G:Node=root.get_node("GameState");G.begin_world("transfer scene test","","6767676767",G.DEV_SEED,true)
	var scene:Node=load("res://scenes/main.tscn").instantiate();scene.set_meta("smoke",true);root.add_child(scene);current_scene=scene
	await process_frame;scene.player.set_physics_process(false);scene.switcher.enter_dream()
	var far:=Vector3i(512,80,512);G.place_dream_block(far,"door",2);G.select_anchor(G.AnchorType.NAIL)
	var loaded_before:int=scene.wake_chunks.get_loaded_count();var p:Dictionary=G.anchor_preview(far)
	_a(not p.ready and not G.try_place_anchor(far) and G.pending_anchors.is_empty(),10083)
	for i in range(300):
		if p.ready:break
		await process_frame;p=G.anchor_preview(far)
	_a(p.ready and p.ok and scene.wake_chunks.get_loaded_count()==loaded_before and G.try_place_anchor(far),10084)
	# Explicit natural lookup is accurate even for unloaded chunks, without scene insertion.
	var natural:Dictionary=scene.wake_chunks.transfer_natural([Vector3i(512,-31,512)])
	_a(natural.ready and natural.kinds[Vector3i(512,-31,512)]=="bedrock",10085)
	G.wake_blocks[far+Vector3i.UP]={"kind":"stone","mutant":false};G.placed_cells_changed.emit(false,[far+Vector3i.UP]);G.clarity=0;var ui:Node=get_first_node_in_group("transfer_result_ui")
	var stopped:Dictionary=scene.switcher.wake_up()
	_a(not stopped.ok and G.is_dream() and G.transfer_ui_open and paused and ui.panel.visible,10086)
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;ui._input(key)
	_a(not G.is_dream() and ui.last_result.aborted and G.dream_blocks.has(far) and G.pending_anchors.is_empty(),10087)
	key.keycode=KEY_Y;ui._input(key);_a(not G.transfer_ui_open and not paused,10088)
	_a(DisplayServer.get_name()=="headless" or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,100881)
	G.remove_shape(G.wake_blocks,far+Vector3i.UP);scene.switcher.enter_dream();_a(G.try_place_anchor(far),10089)
	var success:Dictionary=scene.switcher.wake_up();_a(success.ok and success.transferred==1 and ui.panel.visible and paused and G.dream_blocks.is_empty(),10090)
	ui._input(key);_a(not paused and not G.transfer_ui_open,10091)
	var console:Node=get_first_node_in_group("dev_console")
	for command in ["help transfer","transfer plan","transfer risk","transfer cancel"]:_a(not console.execute(command).begins_with("Ошибка"),10092)
	_a(console.completion_candidates("transfer ").size()==5,10093)
	print("SMOKE: v0.10 atomic preflight/apply ",JSON.stringify(times)," rolls7%=",rolled.rolled,"/10000; beacon protected=",protected_result.protected," legacy v091/receipts/refund overflow/multicell/async validation/pause/Esc/Y safe abort OK")
	var file:=FileAccess.open("user://transfer_measures.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"sizes":times,"rolls_10000":rolled.rolled,"beacon_protected":protected_result.protected},"  "));file.close()
	scene.queue_free();await process_frame;current_scene=null;G.reset_state()


# ============================================================ v0.11 (раздел 16 ТЗ)

func _rec(gs: Node, id: String) -> Dictionary:
	for r in gs.recipe_defs():
		if str(r.get("id", "")) == id: return r
	return {}


func _v011_checks() -> void:
	var gs: Node = load("res://scripts/game_state.gd").new(); root.add_child(gs)
	# --- 16.1 H-автолечение: 90/75/50/10, без зелий, кулдаун, нет слота ---
	_a(gs.choose_heal(10,3,2) == "heal1" and gs.choose_heal(25,3,2) == "heal1" and gs.choose_heal(50,3,2) == "heal2" and gs.choose_heal(90,3,2) == "heal2", 11001)
	_a(gs.choose_heal(90,1,0) == "heal1" and gs.choose_heal(10,0,2) == "heal2" and gs.choose_heal(4,3,3) == "", 11002)
	gs.reset_state(); gs.dev_mode = false
	gs.set_slot(2, {"id":"heal1","name":"хилка1","count":3}); gs.set_slot(22, {"id":"heal2","name":"хилка2","count":2})  # хилка2 в рюкзаке, не в хотбаре
	gs.select_item_slot(0)
	var expect := {90: ["heal1", 100], 75: ["heal1", 95], 50: ["heal2", 90], 10: ["heal2", 50]}
	for hp in [90, 75, 50, 10]:
		gs.player_hp = hp; gs.heal_cd = 0.0
		_a(gs.use_heal() and gs.last_heal_choice == expect[hp][0] and gs.player_hp == expect[hp][1], 11003)
	_a(gs.count_item("heal1") == 1 and gs.count_item("heal2") == 0, 11004)
	gs.player_hp = 40
	_a(not gs.use_heal() and gs.player_hp == 40 and gs.heal_cd > 14.0 and gs.count_item("heal1") == 1, 11005)  # кулдаун, зелье не списано
	gs.heal_cd = 0.0; gs.player_hp = 97
	_a(not gs.use_heal() and gs.count_item("heal1") == 1, 11006)  # почти полное HP — не тратим
	gs.set_slot(2, {}); gs.player_hp = 30; gs.heal_cd = 0.0
	_a(not gs.use_heal() and gs.player_hp == 30 and gs.heal_cd == 0.0, 11007)  # нет зелий: ничего не происходит
	_a(gs.heal_status_text().contains("нет зелий"), 11008)
	# --- 16.2 Сундук: сохранение/загрузка (w:), перенос якорем (d:→w:), возврат содержимого несвязанного ---
	gs.reset_state(); gs.dev_mode = false
	var wc := Vector3i(300,5,300)
	_a(gs.place_wake_block(wc, "chest"), 11010)
	gs.set_slot(0, {"id":"log","name":"Бревно","count":10})
	gs.storage_deposit(wc, 0, false)
	_a(gs.world_storage.has("w:300,5,300") and str(gs.storage_slots(wc, false)[0].id) == "log" and int(gs.storage_slots(wc, false)[0].count) == 10 and gs.count_item("log") == 0, 11011)
	var sv: Dictionary = JSON.parse_string(JSON.stringify(gs.to_save_dict()))
	gs.reset_state(); gs.apply_save_dict(sv)
	_a(gs.world_storage.has("w:300,5,300") and int(gs.storage_slots(wc, false)[0].count) == 10, 11012)
	_a(gs.storage_take(wc, 0, false) and gs.count_item("log") == 10, 11013)
	gs.enter_dream()
	var dc := Vector3i(310,5,310); var lost := Vector3i(320,5,320)
	gs.place_dream_block(dc, "chest"); gs.place_dream_block(lost, "chest")
	gs.storage_slots(dc, true)[0] = {"id":"stone","name":"Камень","count":7}
	gs.storage_slots(lost, true)[0] = {"id":"planks","name":"Доски","count":4}
	_a(gs.world_storage.has("d:310,5,310") and gs.world_storage.has("d:320,5,320") and not gs.world_storage.has("w:310,5,310"), 11014)
	var dsv: Dictionary = JSON.parse_string(JSON.stringify(gs.to_save_dict())); gs.apply_save_dict(dsv)
	_a(gs.world_storage.has("d:310,5,310") and int(gs.world_storage["d:310,5,310"][0].count) == 7, 11015)
	gs.dream_blocks[dc].anchored = true
	gs.pending_anchors = [{"type":2,"cells":[dc],"receipt":{"dev":true}}]
	var cr: Dictionary = gs.resolve_wake()
	_a(cr.ok and cr.transferred == 1 and int(cr.chest_moved) == 1 and int(cr.chest_returned) == 1, 11016)
	_a(str(gs.wake_blocks.get(dc,{}).get("kind","")) == "chest" and gs.world_storage.has("w:310,5,310") and int(gs.world_storage["w:310,5,310"][0].count) == 7, 11017)
	_a(not gs.world_storage.has("d:310,5,310") and not gs.world_storage.has("d:320,5,320") and gs._inv_count(gs.inv_dream, "planks") + gs.dream_stash.size() >= 1, 11018)
	# --- 16.3 Дом 100+ блоков с дверью и сундуком → перенос целиком, цель «Убежище» ---
	gs.reset_state(); gs.dev_mode = false; gs.enter_dream()
	var base := Vector3i(400, 10, 400)
	var door_at := base + Vector3i(2, 1, 0)
	for x in range(5):
		for z in range(5):
			gs.place_dream_block(base + Vector3i(x, 0, z), "planks")
			gs.place_dream_block(base + Vector3i(x, 5, z), "planks")
			for y in range(1, 5):
				var edge := x == 0 or x == 4 or z == 0 or z == 4
				var p := base + Vector3i(x, y, z)
				if edge and not (p == door_at or p == door_at + Vector3i.UP):
					gs.place_dream_block(p, "stone" if y < 3 else "planks")
	_a(gs.place_dream_block(door_at, "door", 0), 11020)
	var hc := base + Vector3i(2, 1, 2)
	gs.place_dream_block(hc, "chest"); gs.storage_slots(hc, true)[3] = {"id":"torch","name":"Факел","count":9}
	var house_cells: Array = []
	for c in gs.dream_blocks.keys():
		gs.dream_blocks[c].anchored = true; house_cells.append(c)
	var roots := 0
	for c in gs.dream_blocks.keys():
		if not gs.dream_blocks[c].has("root"): roots += 1
	_a(house_cells.size() >= 100, 11021)
	gs.pending_anchors = [{"type":2,"cells":house_cells,"receipt":{"dev":true}}]
	var hr: Dictionary = gs.resolve_wake()
	_a(hr.ok and hr.transferred == roots and gs.dream_blocks.is_empty() and gs.wake_blocks.size() == house_cells.size() and int(hr.chest_moved) == 1, 11022)
	_a(gs.wake_build_count() >= 100 and gs.wake_kind_count("door") == 1 and int(gs.world_storage["w:" + gs.cell_key(hc)][3].count) == 9, 11023)
	gs._objectives_eval(true)
	_a(gs.milestones.has("first_transfer") and gs.milestones.has("shelter") and gs.milestones.has("chest"), 11024)
	# --- 16.4 Переключение миров: раздельные инвентари, стартовый верстак Сна — один раз ---
	gs.reset_state(); gs.dev_mode = false
	gs.set_slot(0, {"id":"pickaxe","name":"Кирка","count":1,"dur":100})
	_a(not gs.starter_kit_given, 11030)
	gs.enter_dream()
	_a(gs.is_dream() and str(gs.get_slot(0).get("id","")) != "pickaxe" and gs._inv_count(gs.inv_dream, "workbench") == 1 and gs.milestones.has("first_dream"), 11031)
	gs.resolve_wake(true)
	_a(not gs.is_dream() and str(gs.get_slot(0).get("id","")) == "pickaxe", 11032)
	gs.enter_dream()
	_a(gs._inv_count(gs.inv_dream, "workbench") == 1, 11033)  # повторно не выдаётся
	gs.resolve_wake(true)
	# --- 16.6 Обычный бой: HP задаёт мир, а не оружие; усталость от фарма ---
	gs.reset_state(); gs.dev_mode = false; gs.creation_spawn = Vector3.ZERO
	_a(is_equal_approx(gs.enemy_zone_mult(Vector3(20,2,20)), 1.0) and is_equal_approx(gs.enemy_zone_mult(Vector3(200,2,0)), gs.FAR_LANDS_HP) and is_equal_approx(gs.enemy_zone_mult(Vector3(5,-20,5)), gs.DEPTH_HP), 11040)
	gs.set_sword3_flag(true)
	_a(is_equal_approx(gs.enemy_zone_mult(Vector3(20,2,20)), 1.0), 11041)  # чешуйчатый меч не раздувает HP мобов
	var BC: GDScript = load("res://scripts/build_controller.gd")
	_a(ceili(40.0 / BC.SWORD_DAMAGE) == 5 and ceili(40.0 / BC.SWORD2_DAMAGE) == 3 and ceili(50.0 / BC.SWORD2_DAMAGE) == 4 and ceili(90.0 / BC.SWORD3_DAMAGE) == 4, 11042)
	gs.kill_log = []
	var first_mult: float = gs.kill_fatigue_mult()
	for i in range(10): gs.reward_kill(false, "")
	_a(is_equal_approx(first_mult, 1.0) and gs.kill_fatigue_mult() <= gs.KILL_FATIGUE_MIN + 0.001, 11043)
	_a(gs.reward_kill(true, "Мать блоков") == gs.DUST_PER_BOSS_KILL and gs.reward_kill(true, "Анаконда") == gs.DUST_PER_ANACONDA_KILL, 11044)
	# --- 16.7 Мать блоков: приход только после первого переноса, угроза глубин 40/70/100 ---
	gs.reset_state(); gs.dev_mode = false; gs.dream_exit_count = gs.MOBS_UNLOCK_AT_EXITS
	_a(not gs.mother_can_come() and not gs.on_block_mined_at(Vector3i(0,-20,0), "stone") and gs.deep_threat == 0.0, 11050)
	gs.milestones["first_transfer"] = true
	_a(gs.mother_can_come() and not gs.on_block_mined_at(Vector3i(0,-3,0), "stone") and gs.deep_threat == 0.0, 11051)  # у поверхности тихо
	# v0.11.1: угроза глубин — только атмосфера; Мать — 1% на каждый блок (предвестие → следующий блок).
	var spawned := false; var n := 0
	while not spawned and n < 200:
		spawned = gs.on_block_mined_at(Vector3i(0,-20,0), "stone", 0.5); n += 1
	_a(not spawned and n == 200, 11052)
	_a(not gs.on_block_mined_at(Vector3i(0,-20,0), "stone", 0.0) and gs.on_block_mined_at(Vector3i(0,-20,0), "stone", 0.5), 110520)
	_a(gs.milestones.has("mother_signs") and not gs.milestones.has("mother"), 11053)
	gs.boss_alive = true
	_a(not gs.mother_can_come(), 11054)
	_a(not gs.recipe_available(_rec(gs, "alchemy"), {"is_dream": true}), 11055)
	gs.boss_alive = false; gs.on_mother_killed()
	_a(gs.mother_defeated and gs.deep_threat == 0.0 and not gs.mother_can_come(), 11056)  # кулдаун после победы
	gs._objectives_eval(true)
	_a(gs.milestones.has("mother") and gs.recipe_available(_rec(gs, "alchemy"), {"is_dream": true}) and gs.recipe_available(_rec(gs, "idea_catcher"), {"is_dream": true}), 11057)
	_a(load("res://scripts/block_mother.gd").MAX_HP == 620, 11058)
	# --- 16.8 Анаконда: гнёзда спят до Матери, только свет ---
	var AN: GDScript = load("res://scripts/boss_anaconda.gd")
	_a(AN.MAX_HP == 1250, 11060)
	var G: Node = root.get_node("GameState")
	G.reset_state(); G.mother_defeated = false
	var host := Node3D.new(); root.add_child(host)
	_a(AN.try_spawn(host, host, host) == null, 11061)
	host.queue_free()
	gs.nest_found = true; gs.on_anaconda_killed(); gs._objectives_eval(true)
	_a(gs.anaconda_defeated and gs.milestones.has("nest") and gs.milestones.has("anaconda"), 11062)
	# --- 16.9 Цепочка целей: следующий этап после выполнения текущего ---
	gs.reset_state(); gs.dev_mode = false
	var o0: Dictionary = gs.current_objective()
	_a(str(o0.id) == "reagents" and int(o0.stage) == 0, 11070)
	gs.collected_reagent_ids = {"a": true, "b": true} if typeof(gs.collected_reagent_ids) == TYPE_DICTIONARY else ["a", "b"]
	gs._objectives_eval(true)
	_a(str(gs.current_objective().id) == "first_dream", 11071)
	gs.enter_dream()
	_a(str(gs.current_objective().id) == "dream_build", 11072)
	for i in range(5): gs.place_dream_block(Vector3i(500 + i, 5, 500), "drift")
	gs._objectives_eval(true)
	_a(str(gs.current_objective().id) == "first_anchor" and bool(gs.next_big_objective().get("big", false)), 11073)
	gs.resolve_wake(true)
	gs.milestones["chest"] = true  # перескочил вперёд: ★«Первый перенос» всё равно остаётся текущей целью
	_a(str(gs.current_objective().id) == "first_transfer", 11074)
	gs.milestones["first_transfer"] = true
	_a(str(gs.current_objective().id) == "shelter", 11075)
	# --- 16.10 Миграция реальных сейвов v0.10 ---
	for f in ["res://tests/fixtures/v010_wake_save.json", "res://tests/fixtures/v010_dream_save.json"]:
		gs.reset_state()
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
		_a(int(old.version) < 10, 11080)
		gs.apply_save_dict(old)
		_a(gs.world_storage.has("w:12,1,11") and not gs.world_storage.has("12,1,11"), 11081)
		_a(gs.starter_camp_built and gs.starter_kit_given and gs.milestones.has("first_dream") and gs.milestones.has("first_transfer"), 11082)
		if f.contains("dream"):
			_a(gs.is_dream() and gs.world_storage.has("d:0,2,10") and gs.dream_blocks.size() == 32 and gs.pending_anchors.size() == 1, 11083)
			var mr: Dictionary = gs.resolve_wake()
			_a(mr.ok and not gs.is_dream() and not gs.world_storage.has("d:0,2,10"), 11084)
		var resave: Dictionary = gs.to_save_dict()
		_a(int(resave.version) == gs.SAVE_FORMAT and int(resave.get("progression_revision", 0)) == gs.PROGRESSION_REVISION, 11085)
	gs.queue_free(); await process_frame
	print("SMOKE: v0.11 H-heal 90/75/50/10, chest w:/d: save+anchor, house>=100, worlds, combat zones/fatigue, Mother/Anaconda gates, objectives chain, v0.10 fixtures OK")
	await _v011_scene_checks()


func _v011_scene_checks() -> void:
	## Сцена: стартовый лагерь, нет слота хилки в HUD, смена оружия → ViewModelRig, урон мечей, взмах возвращается в ноль.
	var G: Node = root.get_node("GameState")
	G.begin_world("v011 test", "", "424242", 424242, false)
	var scene: Node = load("res://scenes/main.tscn").instantiate(); scene.set_meta("smoke", true); root.add_child(scene); current_scene = scene; scene.switcher.show_result_ui = false
	for i in range(3): await process_frame
	var camp := 0
	for c in G.wake_blocks:
		if G.wake_blocks[c].get("camp", false): camp += 1
	_a(G.starter_camp_built and camp >= 30 and G.wake_kind_count("torch") == 0 and int(G.pouch.reagent1) == G.START_REAGENT1, 11100)
	var hud: Node = scene.get_node("HUD")
	var hs: Dictionary = hud.heal_indicator_state()
	_a(not hs.slot and hud.find_child("HealSlot", true, false) == null and hud.find_child("ObjectivePanel", true, false) != null, 11101)
	G.dev_mode = false
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i, {})
	G.set_slot(0, {"id":"sword","name":"Меч","count":1}); G.set_slot(1, {"id":"sword2","name":"Каменный меч","count":1})
	G.set_slot(2, {"id":"sword3","name":"Чешуйчатый меч","count":1}); G.set_slot(3, {"id":"pickaxe2","name":"Каменная кирка","count":1})
	G.set_slot(4, {"id":"torch","name":"Факел","count":4}); G.set_slot(5, {"id":"stone","name":"Камень","count":10})
	var build: Node = scene.build
	var dmg := {0: 8, 1: 14, 2: 24}
	for s in [0, 1, 2]:
		G.select_item_slot(s); build._update_hand_tools()
		var vm: Node3D = build.viewmodel
		_a(vm != null and vm.current == str(G.get_slot(s).id) and vm.hand_root.visible, 11102)
		build._try_sword()
		_a(build.last_sword_damage == dmg[s], 11103)
	var vm: Node3D = build.viewmodel
	_a(vm.name == "ViewModelRoot" and vm.get_parent() is Camera3D and vm.hand_root.get_parent() == vm and vm.grip_pivot.get_parent() == vm.hand_root and vm.swing_pivot.get_parent() == vm.grip_pivot, 11104)
	var vis := 0
	for k in vm.models:
		if vm.models[k].visible: vis += 1
	_a(vis == 1, 11105)
	G.select_item_slot(3); build._update_hand_tools()
	_a(vm.current == "pickaxe2" and vm.models["pickaxe2"].visible and not vm.models["sword3"].visible, 11106)
	G.select_item_slot(4); build._update_hand_tools()
	_a(vm.current == "torch" and vm.get_node("HandRoot/GripPivot/SwingPivot/HeldLight").visible, 11107)
	G.select_item_slot(5); build._update_hand_tools()
	_a(vm.current == "" and not vm.hand_root.visible, 11108)
	G.select_item_slot(1); build._update_hand_tools()
	var hand_pos: Vector3 = vm.hand_root.position
	build._play_tool_swing()
	_a(vm.swinging and vm.swing_count >= 1, 11109)
	await create_timer(0.7).timeout
	_a(not vm.swinging and vm.swing_pivot.rotation.length() < 0.001 and vm.hand_root.position.distance_to(hand_pos) < 0.05, 11110)
	await _v0111_scene_checks(scene)
	scene.queue_free(); await process_frame; current_scene = null; G.reset_state()
	print("SMOKE: v0.11 starter camp, no heal slot, weapon switch → ViewModelRig, sword dmg 8/14/24, swing returns to rest OK")



func _labels_text(n: Node) -> Array:
	var out: Array = []
	for l in n.find_children("*", "Label", true, false):
		out.append(str((l as Label).text))
	return out


func _v0111_scene_checks(scene: Node) -> void:
	## v0.11.1 §9: правки пользователя A1–A8 + новые механики боссов.
	var G: Node = root.get_node("GameState")
	var build: Node = scene.build
	var hud: Node = scene.get_node("HUD")
	# A2: опора как в Minecraft — в воздухе ставить нельзя, рядом с блоком можно.
	var air := Vector3i(3, 60, 3)
	_a(not build.placement_supported(air, false) and not build.placement_supported(air, true), 12001)
	G.wake_blocks[Vector3i(3, 59, 3)] = {"kind": "stone"}
	_a(build.placement_supported(air, false), 12002)
	G.wake_blocks.erase(Vector3i(3, 59, 3))
	G.wake_blocks[Vector3i(4, 60, 3)] = {"kind": "torch"}
	_a(not build.placement_supported(air, false), 12003)   # факел — не опора
	G.wake_blocks.erase(Vector3i(4, 60, 3))
	G.dream_blocks[Vector3i(3, 60, 4)] = {"kind": "drift"}
	_a(build.placement_supported(air, true) and not build.placement_supported(air, false), 12004)   # опора своего слоя
	G.dream_blocks.erase(Vector3i(3, 60, 4))
	# A3: фонаря нет, миграция сейва → 4 факела.
	_a(not G.find_recipe("lantern").size() > 0 and not ResourceLoader.exists("res://assets/icons/lantern.png"), 12010)
	var save: Dictionary = G.to_save_dict()
	var inv: Array = save.get("item_slots", [])
	if inv.size() > 7:
		inv[7] = {"id": "lantern", "name": "Фонарь", "count": 2}
		save["item_slots"] = inv
		var g2: Node = load("res://scripts/game_state.gd").new()
		root.add_child(g2)
		g2.apply_save_dict(JSON.parse_string(JSON.stringify(save)))
		var torches := 0
		var lanterns := 0
		for sl in g2.inv_wake:
			if typeof(sl) == TYPE_DICTIONARY and str(sl.get("id", "")) == "torch": torches += int(sl.get("count", 0))
			if typeof(sl) == TYPE_DICTIONARY and str(sl.get("id", "")) == "lantern": lanterns += 1
		_a(lanterns == 0 and torches >= 8, 12011)
		g2.queue_free()
	else:
		_a(G.LANTERN_TORCH_REFUND == 4, 12011)
	# A6: земной прыжок — высота апекса ≈1.26 м (v²/2g), меньше 1.5 блока.
	var PC: GDScript = load("res://scripts/player_controller.gd")
	var apex: float = PC.JUMP_VELOCITY * PC.JUMP_VELOCITY / (2.0 * PC.PLAYER_GRAVITY)
	_a(apex > 1.1 and apex < 1.4, 12020)
	print("SMOKE: v0.11.1 jump apex=%.2f m" % apex)
	# A7: батарейка с числом внутри, без «100 HP» и «H — хилка1».
	var hs: Dictionary = hud.heal_indicator_state()
	var bat: Node = hud.find_child("HealthBattery", true, false)
	_a(bool(hs.battery) and bat != null and str(bat.label.text) == str(G.player_hp) and not bool(hs.hearts), 12030)
	for t in _labels_text(hud):
		_a(not ("хилк" in t.to_lower()) and not (" HP" in t) and not ("HP " in t), 12031)
	G.damage_player(30, "smoke", true)
	await process_frame
	_a(str(bat.label.text) == str(G.player_hp) and bat.fraction() < 1.0, 12032)
	G.heal_player_full()
	# A8: инвентарь без текстовых подсказок.
	hud.inventory.open()
	await process_frame
	_a(hud.inventory.find_child("HealHelp", true, false) == null, 12040)
	for t in _labels_text(hud.inventory):
		_a(not ("ЛКМ" in t) and not ("Shift" in t) and not ("DEV" in t) and not ("Лечение" in t), 12041)
	hud.inventory.toggle()
	await process_frame
	# A1: меч3 — объёмная 3D-модель (не плоская текстура).
	var BT: GDScript = load("res://scripts/block_tex.gd")
	var sm: Mesh = BT.sword3_mesh()
	var aabb: AABB = sm.get_aabb()
	_a(sm != null and aabb.size.x > 0.05 and aabb.size.z > 0.05 and aabb.size.y > 0.9 and aabb.size.y < 1.2, 12050)
	var tm: Mesh = BT.torch_mesh()
	_a(tm != null and tm.get_aabb().size.y > 0.6 and BT.torch_flame_mesh() != null, 12051)
	# A4: 1% на блок; блоколиты 1/120 после первой победы, нейтральны, убийство зовёт Мать.
	G.reset_state(); G.peaceful = false; G.dev_mode = false
	_a(not G.blockolith_roll(0.0), 12060)                       # до победы над Матерью — нет
	G.mother_defeated = true
	_a(G.blockolith_roll(0.008) and not G.blockolith_roll(0.0084), 12061)   # 1/120 = 0.00833
	G.set_boss_alive(true)
	_a(not G.blockolith_roll(0.0), 12062)
	G.set_boss_alive(false)
	var host := Node3D.new(); scene.wake_world.add_child(host)
	var bl: CharacterBody3D = load("res://scripts/blockling.gd").new()
	bl.configure("blockolith", null, Vector3.ZERO)
	bl.position = scene.player.global_position + Vector3(1.0, 0, 0)
	host.add_child(bl)
	await physics_frame
	var hp0: int = G.player_hp
	for i in range(90): await physics_frame
	_a(bl.is_in_group("blockolith") and bl.max_hp == bl.BLOCKOLITH_HP and G.player_hp == hp0, 12063)   # нейтрален: не кусает
	for m in get_nodes_in_group("block_mother"): m.free()
	bl.take_damage(999)
	for i in range(3): await process_frame
	_a(get_nodes_in_group("block_mother").size() == 1 and G.blockoliths_killed == 1, 12064)
	var mom: Node = get_nodes_in_group("block_mother")[0]
	# Никогда два босса: Анаконда не выходит при живой Матери.
	_a(load("res://scripts/boss_anaconda.gd").spawn_at(host, Vector3(30, 0, 30), "smoke") == null, 12065)
	# Мать: 3 пластины × 6, кирка 2 / кирка2 6, меч по броне 0 (отскок).
	mom._enter(mom.S.IDLE)
	_a(mom.PLATE_COUNT == 3 and mom.PLATE_DURABILITY == 6 and mom.PICK_PLATE_DAMAGE["pickaxe"] == 2 and mom.PICK_PLATE_DAMAGE["pickaxe2"] == 6, 12070)
	var r0: Dictionary = mom.receive_weapon_hit(24, "sword3")
	_a(int(r0.dealt) == 0 and bool(r0.bounce) and mom.hp == mom.MAX_HP, 12071)
	mom._open_plate()
	_a(mom.state == mom.S.PLATE_OPEN and mom.open_plate >= 0, 12072)
	var op: int = mom.open_plate
	_a(int(mom.receive_weapon_hit(8, "sword").dealt) == 0 and mom.hp == mom.MAX_HP, 12073)   # меч и по открытой пластине — 0
	mom.receive_weapon_hit(2, "pickaxe"); mom.receive_weapon_hit(2, "pickaxe")
	_a(int(mom.plates[op]["dur"]) == 2 and mom.state == mom.S.PLATE_OPEN, 12074)
	mom.receive_weapon_hit(2, "pickaxe")
	_a(int(mom.plates[op]["dur"]) == 0 and mom.state == mom.S.CORE and mom.is_vulnerable(), 12075)   # ядро открыто + оглушение
	var hpc: int = mom.hp
	mom.receive_weapon_hit(8, "sword")
	_a(mom.hp == hpc - 10, 12076)                                  # ×1.25 по ядру
	_a(mom.CORE_TIME >= 2.5 and mom.CORE_TIME <= 3.5 and mom.PLATE_OPEN_TIME >= 3.0 and mom.PLATE_OPEN_TIME <= 4.0, 12077)
	# Фаза II: носильщик возвращает пластину; фаза III — без восстановления.
	mom.phase = 2
	_a(mom.restore_plate() and int(mom.plates[op]["dur"]) == mom.PLATE_DURABILITY, 12078)
	mom.plates[op]["dur"] = 0; mom.plates[op]["broken"] = true
	mom.on_carrier_delivered(null)
	_a(int(mom.plates[op]["dur"]) == mom.PLATE_DURABILITY, 12079)
	mom.plates[op]["dur"] = 0; mom.plates[op]["broken"] = true
	mom.phase = 3
	_a(not mom.restore_plate() and int(mom.plates[op]["dur"]) == 0, 12080)
	# Кирпичный дождь: 4–6 кирпичей, тени, навес спасает.
	var plan: Array = mom.rain_plan(scene.player.global_position, 6)
	_a(plan.size() == 6 and mom.RAIN_BRICKS_MIN >= 4 and mom.RAIN_BRICKS_MAX <= 6, 12081)
	for i in range(plan.size()):
		for j in range(i + 1, plan.size()):
			var pi_: Vector3 = plan[i]["pos"]; var pj_: Vector3 = plan[j]["pos"]
			_a(Vector2(pi_.x - pj_.x, pi_.z - pj_.z).length() >= 1.85, 12082)
	mom._spawn_cover(scene.player.global_position)
	_a(not mom._covers.is_empty() and mom.under_cover((mom._covers[0]["pos"] as Vector3)) and not mom.under_cover((mom._covers[0]["pos"] as Vector3) + Vector3(5, 0, 0)), 12083)
	# Скрытого хила нет, урон ≤35% HP.
	_a(mom.heal_from_blocks(5) == 0, 12084)
	for d in [mom.SLAM_DAMAGE, mom.WAVE_DAMAGE, mom.REASSEMBLE_DAMAGE, mom.BRICK_DAMAGE, mom.CONTACT_DAMAGE]:
		_a(int(d) <= 35, 12085)
	mom.free()
	await process_frame
	# Анаконда: кеш факелов.
	G.reset_state()
	var reb0: int = G.torch_cache_rebuilds
	G.wake_blocks[Vector3i(1, 1, 1)] = {"kind": "torch"}
	_a(G.torch_cells().size() == 1, 12090)
	var reb1: int = G.torch_cache_rebuilds
	for i in range(50): G.torch_cells()
	_a(G.torch_cache_rebuilds == reb1 and reb1 > reb0, 12091)       # без изменений — без пересканирования
	_a(G.remove_torch(Vector3i(1, 1, 1)) and G.torch_cells().is_empty(), 12092)
	# Сердца: сохраняются, Сердце структуры: клинья +2, перенос без мутаций.
	G.heart_light = true; G.heart_structure = true
	_a(G.wedge_size() == G.WEDGE_SIZE + 2 and G.anchor3_size() == G.ANCHOR3_SIZE + 2, 12100)
	var sv: Dictionary = JSON.parse_string(JSON.stringify(G.to_save_dict()))
	var g3: Node = load("res://scripts/game_state.gd").new()
	root.add_child(g3)
	g3.apply_save_dict(sv)
	_a(g3.heart_light and g3.heart_structure, 12101)
	g3.queue_free()
	_a(G.recipe_available(_rec(G, "lumen"), {"is_dream": true}) and G.is_placeable_block("lumen"), 12102)
	G.heart_light = false
	_a(not G.recipe_available(_rec(G, "lumen"), {"is_dream": true}), 12103)
	G.heart_structure = false
	_a(G.wedge_size() == G.WEDGE_SIZE, 12104)
	host.queue_free()
	await process_frame
	print("SMOKE: v0.11.1 placement/lantern/jump/battery/inventory/sword3/torch/blockolith/plates/carriers/cover/cache/hearts OK")
