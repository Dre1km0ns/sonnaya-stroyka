extends SceneTree
## Headless smoke v0.6 (+ деревья, сутки 24 мин, луна, клавиши, босс 500 HP, предвестие):\n## v0.5: меню/миры/сиды/инвентарь 9+27/дев-сид + всё из v0.4.5.
## Запуск: godot --headless --path ... -s res://scripts/smoke_test.gd


var _fails: Array = []


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
	_a(int(result["dust"]) == 0, 41)
	_a(gs.dust == before_dust, 42)
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
	gs.dust = 9
	_a(not gs.craft_recipe("nail", {"is_dream": true}), 60)
	gs.dust = 10
	_a(gs.craft_recipe("nail", {"is_dream": true}), 62)
	_a(not gs.craft_recipe("nail", {"is_dream": false}), 63)
	_a(not gs.craft_recipe("nail", {"at_workbench": true, "is_dream": true}), 64)
	_a(gs.NAIL_CRAFT_DUST == 10, 65)

	# Клин из осыпи — только во сне, не на верстаке
	gs.dust = 100
	var wedges_before: int = gs.wedges
	_a(gs.craft_recipe("wedge", {"is_dream": true}), 70)
	_a(gs.wedges == wedges_before + 1, 71)
	_a(gs.dust == 0, 72)
	_a(gs.WEDGE_CRAFT_DUST == 100, 73)
	gs.dust = 250
	var a3_before: int = gs.anchors3
	_a(gs.craft_recipe("anchor3", {"is_dream": true}), 76)
	_a(gs.anchors3 == a3_before + 1, 77)
	_a(gs.dust == 0, 78)
	_a(gs.ANCHOR3_CRAFT_DUST == 250, 79)
	_a(gs.ANCHOR3_SIZE == 9, 80)
	_a(is_equal_approx(gs.CLARITY_DRAIN_PER_SEC, 1.25), 81)
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
	gs_c.reagent_counts = [0, 2, 3]
	gs_c.reagents = 5
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
	var drop: StaticBody3D = drop_script.new()
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
	gs_t.reagent_counts = [1, 1, 0]
	gs_t.reagents = 2
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
	_a(g1.hp == 50, 496)
	g1.take_damage(10)
	_a(g1.hp == 40, 498)
	_a(vis.has_clip(g1, "walk"), 499)
	_a(vis.has_clip(g1, "attack"), 500)
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = boss_script.new()
	boss.position = Vector3(4, 1, 4)
	root.add_child(boss)
	await process_frame
	await process_frame
	_a(boss.is_in_group("block_mother"), 507)
	_a(boss.hp == 500, 508)
	_a(boss.max_hp == 500, 509)
	boss.take_damage(10)           # SPAWN — неуязвима
	_a(boss.hp == 500, 511)
	boss._enter(boss.S.IDLE)
	boss.take_damage(10)
	_a(boss.hp == 490, 514)
	_a(boss.get_tree() != null, 515)
	var td_script: GDScript = load("res://scripts/threat_director.gd")
	var td: Node = td_script.new()
	_a(td.MAX_ENEMIES == 7, 518)
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
	if not _fails.is_empty():
		push_error("SMOKE: FAILED asserts at lines %s" % str(_fails))
		quit(1)
		return
	print("SMOKE: OK v0.7 transferred=%d dust_result=%d mutations=%d nails=%d wedges=%d a3=%d chunks=%d enemies=%d ghosts=%d lakes=%d ruins=%d reagents=%d ruin_max=%d save=1 exits=%d persist=%d hill4=%d night=1 torch=1 sword=1 boss=1 drops=1 music=1 col=0 mine=1 tools=1 bossbar=1" % [
		int(result["transferred"]), int(result["dust"]), int(result["mutations"]), gs.nails, gs.wedges, gs.anchors3,
		cm.get_loaded_count(), enemy_count, ghost_count, cm.count_loaded_lakes(), cm.count_loaded_ruins(),
		cm.count_loaded_reagents(), max_ruin_reagents, gs_m.dream_exit_count, persist_count, 1 if found_h4 else 0
	])
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
	_a(gs_script.new().DUST_PER_KILL == 20, 683)
	gi.dust = 0
	_a(gi.reward_kill(false, "Шовник") == 20, 685)
	_a(gi.dust == 20, 686)
	_a("+20 осыпи" in gi.last_hint, 687)
	_a(gi.reward_kill(true, "Мать блоков") == 250, 688)
	_a(gi.dust == 270, 689)

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
	_a(int(blob["version"]) == 7, 858)
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
	_a(not G.on_block_mined(0.5), 875)       # 0.5 ≥ 1% → нет
	_a(not G.boss_next_mine, 876)
	_a(not G.on_block_mined(0.005), 877)     # бросок на СЛЕДУЮЩИЙ блок → предвестие
	_a(G.boss_next_mine, 878)
	_a(chats.has(G.BOSS_OMEN_TEXT), 879)
	_a(G.BOSS_OMEN_TEXT == "Вы слышите разъярённые крики убитой горем матери", 880)
	var b2: Dictionary = G.to_save_dict()
	var g3: Node = gs_script.new()
	root.add_child(g3)
	g3.apply_save_dict(JSON.parse_string(JSON.stringify(b2)))
	_a(g3.boss_next_mine, 885)
	_a(G.on_block_mined(0.9), 886)           # следующий блок — босс
	_a(not G.boss_next_mine, 887)
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
	_a(boss.hp == 500 and boss.phase == 1, 929)
	boss._enter(boss.S.IDLE)
	boss.take_damage(400)                 # не проваливается сквозь порог фазы
	_a(boss.hp == boss.P2_AT, 932)
	_a(boss.phase == 2 and boss.state == boss.S.TRANSITION, 933)
	boss.take_damage(50)                  # переход неуязвим
	_a(boss.hp == boss.P2_AT, 935)
	boss._enter(boss.S.STAGGER)
	boss._stagger_len = 2.0
	_a(boss.is_vulnerable(), 938)
	boss.take_damage(10)                  # ×1.5 в окне уязвимости
	_a(boss.hp == boss.P2_AT - 15, 940)
	boss.take_damage(400)
	_a(boss.hp == boss.P3_AT and boss.phase == 3, 942)
	boss._enter(boss.S.STAGGER)
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
	_a(b3.MINION_HARD_CAP == 6, 956)
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
	_a(G.count_item("dust") == dust0 - 50, 1022)
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
	_a(lathe_ids == ["sword2"], 1076)
	_a("lathe" in bench_ids and not ("sword2" in bench_ids), 1077)
	for rid in bench_ids:
		_a(not (rid in lathe_ids), 1079)
	var lr: Dictionary = G.find_recipe("lathe")
	_a(int((lr["items"] as Dictionary).get("workbench", 0)) == 1 and int(lr["reagent3"]) == 7, 1081)
	G.add_item_count("workbench", 1)
	G.add_item_count("reagent3", 6)
	_a(not G.craft_recipe("lathe", {"at_workbench": true}), 1084)
	G.add_item_count("reagent3", 1)
	_a(not G.craft_recipe("lathe", {"at_lathe": true}), 1086)
	_a(G.craft_recipe("lathe", {"at_workbench": true}), 1087)
	_a(G.count_item("lathe") == 1 and G.count_item("workbench") == 0 and G.count_item("reagent3") == 0, 1088)
	var sr: Dictionary = G.find_recipe("sword2")
	_a(sr["items"] == {"sword": 1} and int(sr["reagent1"]) == 2 and int(sr["reagent2"]) == 2 and int(sr["reagent3"]) == 2, 1090)
	G.add_item_count("reagent1", 2)
	G.add_item_count("reagent2", 2)
	G.add_item_count("reagent3", 2)
	_a(not G.craft_recipe("sword2", {"at_lathe": true}), 1094)     # без Меча — нельзя
	G.add_item_count("sword", 1)
	_a(not G.craft_recipe("sword2", {"at_workbench": true}), 1096)
	_a(G.craft_recipe("sword2", {"at_lathe": true}), 1097)
	_a(G.count_item("sword2") == 1 and G.count_item("sword") == 0, 1098)
	_a(G.count_item("reagent1") == 0 and G.count_item("reagent2") == 0 and G.count_item("reagent3") == 0, 1099)
	var bc: GDScript = load("res://scripts/build_controller.gd")
	_a(bc.SWORD2_DAMAGE == 25 and is_equal_approx(bc.SWORD2_REACH, bc.SWORD_REACH * 1.25), 1101)
	var cmenu: Node = load("res://scripts/craft_menu.gd").new()
	root.add_child(cmenu)
	await process_frame
	cmenu.open_lathe()
	_a(cmenu.station() == "lathe" and cmenu.visible_recipe_ids() == ["sword2"], 1106)
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
	_a(boss.heal_from_blocks(3) == 15 and boss.hp == 415, 1154)
	boss.hp = 499
	boss.heal_from_blocks(4)
	_a(boss.hp == 500, 1157)
	boss.queue_free()
	await process_frame
	G.reset_state()
	# --- Мобы бьют ---
	_a(load("res://scripts/seam_creature.gd").HIT_DAMAGE > 0 and load("res://scripts/enemy_ghost.gd").HIT_DAMAGE > 0, 1162)
	# --- Луна ярче ---
	var dcs: GDScript = load("res://scripts/day_cycle.gd")
	_a(dcs.MOON_MAX_ENERGY >= 0.7, 1165)
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
	_a(ana != null and ana.hp == ana.MAX_HP and ana.MAX_HP == 2850, 1290)
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
	_a(ana.is_invulnerable(), 1307)                 # SPAWN — в земле
	# Вынырнула и лежит (REST): без света урона нет.
	ana._emerge = Vector3(40, 0, 40)
	ana._enter(ana.S.REST)
	for i in range(5):
		ana.tick(0.05)
	_a(ana.light_dps() == 0.0 and ana.hp == ana.MAX_HP, 1313)
	# Факел рядом с головой → урон.
	var hpos: Vector3 = ana.hit_center()
	G.wake_blocks[Vector3i(floori(hpos.x), floori(hpos.y), floori(hpos.z))] = {"kind": "torch", "mutant": false}
	ana._torch_scan = 0.0
	ana.tick(0.05)
	_a(ana.light_dps() >= ana.HEAD_LIGHT_DPS, 1319)
	ana._enter(ana.S.REST)
	var hp_before: int = ana.hp
	for i in range(20):
		ana._t = 0.0
		ana.tick(0.1)
	print("SMOKE: anaconda light dps=%.1f hp %d→%d" % [ana.light_dps(), hp_before, ana.hp])
	_a(ana.hp < hp_before, 1326)
	# Ослеплена (STUNNED) — ×2 урон.
	ana._enter(ana.S.STUNNED)
	ana._stun_len = 5.0
	_a(ana.is_vulnerable(), 1330)
	var d_stun: float = ana.light_dps()
	ana._enter(ana.S.REST)
	_a(is_equal_approx(d_stun, ana.light_dps() * 2.0), 1333)
	# Ни одного неизбежного урона: телеграф ≥0.6 с, удар ≤40%, кап комбо 70.
	for tt in ana.TELEGRAPH:
		_a(float(tt) >= 0.6, 1336)
	for dmg in [ana.BURST_DAMAGE, ana.ROCK_DAMAGE, ana.CONSTRICT_DAMAGE, ana.CONTACT_DAMAGE, ana.COIL_CONTACT]:
		_a(int(dmg) <= 40, 1338)
	_a(G.COMBO_CAP <= 70, 1339)
	_a(ana.MINION_PITY == 3 and ana.MINION_CAP <= 4, 1340)
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
	host2.add_child(pc)
	pc.set_physics_process(false)
	pc.set_process(false)
	pc.global_position = Vector3(5, 0, 5)
	var pk: StaticBody3D = load("res://scripts/block_pickup.gd").new()
	pk.configure("planks")
	host2.add_child(pk)
	pk.global_position = Vector3(5.5, 0.6, 5)
	var planks0: int = G.count_item("planks")
	_a(pc.auto_pickup() == 1, 1394)
	_a(G.count_item("planks") == planks0 + 1, 1395)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host2.queue_free()
	host.queue_free()
	await process_frame
	print("SMOKE: v0.7 checks done")
	_v07_done = true
