extends SceneTree
## Headless smoke v0.6 (+ деревья, сутки 24 мин, луна, клавиши, босс 500 HP, предвестие):\n## v0.5: меню/миры/сиды/инвентарь 9+27/дев-сид + всё из v0.4.5.
## Запуск: godot --headless --path ... -s res://scripts/smoke_test.gd


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
	assert(gs.is_dream())
	for x in range(0, 3):
		for z in range(0, 3):
			gs.place_dream_block(Vector3i(x, 0, z), "drift")
	gs.place_dream_block(Vector3i(1, 1, 1), "drift")
	assert(gs.dream_blocks.size() == 10)
	gs.select_anchor(gs.AnchorType.NAIL)
	assert(gs.try_place_anchor(Vector3i(1, 1, 1)))
	var before_dust: int = gs.dust
	var result: Dictionary = gs.resolve_wake()
	assert(not gs.is_dream())
	assert(int(result["transferred"]) == 1)
	assert(int(result["dust"]) == 0)
	assert(gs.dust == before_dust)
	assert(gs.wake_blocks.has(Vector3i(1, 1, 1)))
	# Сон не сбрасывается — можно достраивать.
	assert(gs.dream_blocks.size() == 10)
	assert(gs.dream_blocks.has(Vector3i(0, 0, 0)))
	assert(gs.dream_blocks.has(Vector3i(1, 1, 1)))
	gs.enter_dream()
	assert(gs.dream_blocks.size() == 10)
	gs.resolve_wake()
	assert(gs.dream_blocks.size() == 10)
	# Высота ячейки в яви совпадает со сном.
	assert(gs.wake_blocks.has(Vector3i(1, 1, 1)))
	var vw_script: GDScript = load("res://scripts/voxel_world.gd")
	var dv: Node3D = vw_script.new()
	dv.is_dream_layer = true
	var wv: Node3D = vw_script.new()
	wv.is_dream_layer = false
	var height_cell := Vector3i(1, 1, 1)
	assert(dv.cell_to_world(height_cell).is_equal_approx(wv.cell_to_world(height_cell)))
	assert(is_equal_approx(dv.cell_to_world(Vector3i(2, 0, 4)).y, 0.5))
	gs.dust = 9
	assert(not gs.craft_recipe("nail", {"is_dream": true}))
	gs.dust = 10
	assert(gs.craft_recipe("nail", {"is_dream": true}))
	assert(not gs.craft_recipe("nail", {"is_dream": false}))
	assert(not gs.craft_recipe("nail", {"at_workbench": true, "is_dream": true}))
	assert(gs.NAIL_CRAFT_DUST == 10)

	# Клин из осыпи — только во сне, не на верстаке
	gs.dust = 100
	var wedges_before: int = gs.wedges
	assert(gs.craft_recipe("wedge", {"is_dream": true}))
	assert(gs.wedges == wedges_before + 1)
	assert(gs.dust == 0)
	assert(gs.WEDGE_CRAFT_DUST == 100)
	gs.dust = 250
	var a3_before: int = gs.anchors3
	assert(gs.craft_recipe("anchor3", {"is_dream": true}))
	assert(gs.anchors3 == a3_before + 1)
	assert(gs.dust == 0)
	assert(gs.ANCHOR3_CRAFT_DUST == 250)
	assert(gs.ANCHOR3_SIZE == 9)
	assert(is_equal_approx(gs.CLARITY_DRAIN_PER_SEC, 1.25))
	assert(gs.recipe_defs().size() >= 7)
	assert(not gs.find_recipe("torch").is_empty())
	assert(not gs.find_recipe("sword").is_empty())
	assert(not ("макс" in gs.inventory_status_text()))

	# Хардкор-кража (может вернуть dust:N)
	gs.dust = 3
	gs.reagents = 1
	var st: String = gs.steal_resource_hardcore(2)
	assert(st.begins_with("dust"))
	assert(gs.dust == 1)
	gs.dust = 0
	assert(gs.steal_resource_hardcore() == "reagent")
	assert(gs.reagents == 0)
	assert(gs.steal_resource_hardcore() == "none")

	# Типы реагентов и кап 100
	gs.reagent_counts = [0, 0, 0]
	gs.reagents = 0
	assert(gs.add_typed_reagent(1, 50) == 50)
	assert(gs.add_typed_reagent(1, 60) == 50)
	assert(gs.get_reagent_count(1) == 100)
	assert(gs.add_typed_reagent(1, 1) == 0)
	assert(gs.add_typed_reagent(2, 10) == 10)
	assert(gs.add_typed_reagent(3, 7) == 7)
	assert(gs.reagent_type_name(1) == "реагент1")
	assert(gs.reagent_type_name(2) == "реагент2")
	assert(gs.reagent_type_name(3) == "реагент3")
	assert(gs.reagents == 117)
	assert(gs.spend_reagents(5))
	assert(gs.get_reagent_count(1) == 95)
	assert(gs.reagents == 112)

	# Мобы только после второго выхода из сна
	var gs_m: Node = gs_script.new()
	root.add_child(gs_m)
	assert(gs_m.dream_exit_count == 0)
	assert(not gs_m.mobs_unlocked())
	gs_m.enter_dream()
	gs_m.resolve_wake()
	assert(gs_m.dream_exit_count == 1)
	assert(not gs_m.mobs_unlocked())
	gs_m.enter_dream()
	gs_m.resolve_wake()
	assert(gs_m.dream_exit_count == 2)
	assert(gs_m.mobs_unlocked())

	# Инвентарь 9+27, якоря/маяки — отдельно (вертикальная полоса)
	assert(gs.item_slots.size() == 36)
	assert(gs.HOTBAR_SIZE == 9 and gs.MAIN_INV_SIZE == 27)
	assert(_slot_of(gs, "nail") == -1 and _slot_of(gs, "anchor3") == -1)
	gs.select_item_slot(8)
	assert(gs.selected_slot == 8)
	gs.cycle_item_slot(1)
	assert(gs.selected_slot == 0)
	gs.cycle_item_slot(-1)
	assert(gs.selected_slot == 8)
	var added_at: int = gs.add_item("test_tool", "Тест", 1)
	assert(added_at >= 0 and added_at < 9)
	assert(int(gs.item_slots[added_at].get("count")) == 1)

	# Верстак и кирка
	var gs_c: Node = gs_script.new()
	root.add_child(gs_c)
	gs_c.enter_dream()
	gs_c.reagent_counts = [10, 0, 0]
	gs_c.reagents = 10
	assert(gs_c.craft_recipe("workbench", {"is_dream": true}))
	assert(_slot_of(gs_c, "workbench") >= 0)
	assert(not gs_c.craft_recipe("pickaxe", {"at_workbench": false}))
	gs_c.reagent_counts = [0, 2, 3]
	gs_c.reagents = 5
	assert(gs_c.craft_recipe("pickaxe", {"at_workbench": true}))
	assert(_slot_of(gs_c, "pickaxe") >= 0)
	var wb := Vector3i(8, 0, 8)
	assert(gs_c.place_dream_block(wb, "workbench"))
	gs_c.nails = 2
	gs_c.reagent_counts = [3, 2, 3]
	gs_c.reagents = 8
	gs_c.clarity = 100.0
	gs_c.select_anchor(gs_c.AnchorType.NAIL)
	assert(gs_c.try_place_anchor(wb))
	var wb_res: Dictionary = gs_c.resolve_wake()
	assert(int(wb_res["transferred"]) >= 1)
	assert(gs_c.wake_blocks.has(wb))
	assert(str(gs_c.wake_blocks[wb].get("kind")) == "workbench")
	gs_c.select_item_slot(_slot_of(gs_c, "pickaxe"))
	assert(gs_c.selected_is("pickaxe"))
	var mine_cell := Vector3i(3, 0, 3)
	gs_c.wake_blocks[mine_cell] = {"kind": "drift", "mutant": false}
	assert(gs_c.mine_wake_block(mine_cell))
	assert(not gs_c.wake_blocks.has(mine_cell))
	assert(str(gs_c.last_mined_kind) == "drift")
	var drop_script: GDScript = load("res://scripts/block_pickup.gd")
	var drop: StaticBody3D = drop_script.new()
	drop.configure("drift")
	root.add_child(drop)
	await process_frame
	assert(drop.is_in_group("pickup"))
	assert(drop.has_method("collect"))
	gs_c.add_mined_block("drift", 1)
	var stored_c := 0
	for sl2 in gs_c.item_slots:
		if str(sl2.get("id", "")) == "drift":
			stored_c += int(sl2.get("count", 0))
	stored_c += int(gs_c.block_stash.get("drift", 0))
	assert(stored_c >= 1)
	var gs_t: Node = gs_script.new()
	root.add_child(gs_t)
	gs_t.reagent_counts = [1, 1, 0]
	gs_t.reagents = 2
	assert(gs_t.craft_recipe("torch", {"at_workbench": true}))
	assert(_slot_of(gs_t, "torch") >= 0)
	var torch_cell := Vector3i(4, 0, 5)
	assert(gs_t.place_wake_block(torch_cell, "torch"))
	assert(str(gs_t.wake_blocks[torch_cell].get("kind")) == "torch")
	assert(FileAccess.file_exists("res://assets/audio/music.mp3"))
	assert(FileAccess.file_exists("res://assets/audio/dream_ost.mp3"))
	assert(FileAccess.file_exists("res://assets/audio/boss_ost.mp3"))
	assert(ResourceLoader.exists("res://assets/models/ghost.glb"))
	assert(ResourceLoader.exists("res://assets/models/greenblob.glb"))
	assert(ResourceLoader.exists("res://assets/models/reagent_crystal.glb"))
	assert(ResourceLoader.exists("res://assets/models/reagent_herb.glb"))
	assert(ResourceLoader.exists("res://assets/models/reagent_ore.glb"))
	assert(FileAccess.file_exists("res://assets/models/pickaxe.glb"))
	assert(FileAccess.file_exists("res://assets/models/sword.glb"))
	var gs_s: Node = gs_script.new()
	root.add_child(gs_s)
	gs_s.reagent_counts = [5, 2, 0]
	gs_s.reagents = 7
	assert(not gs_s.craft_recipe("sword", {"at_workbench": false}))
	assert(gs_s.craft_recipe("sword", {"at_workbench": true}))
	assert(_slot_of(gs_s, "sword") >= 0)
	var wb_only: Array = gs_s.get_visible_recipes({"at_workbench": true, "is_dream": true})
	for recw in wb_only:
		var ridw := str(recw.get("id", ""))
		assert(ridw != "nail" and ridw != "wedge" and ridw != "anchor3")
	var found_sword := false
	for recw2 in wb_only:
		if str(recw2.get("id", "")) == "sword":
			found_sword = true
	assert(found_sword)
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	root.add_child(menu)
	assert(menu.is_centered_modal())

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
	assert(cm.get_loaded_count() >= 1)
	assert(cm.world_to_chunk(Vector3(0, 0, 0)) == Vector2i(0, 0))
	assert(cm.height_at(0, 0) == 0)
	dummy.position = Vector3(40, 2, 40)
	cm._update_chunks(false)
	assert(cm.world_to_chunk(dummy.position) == Vector2i(2, 2))

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
	assert(found_lake)
	assert(found_ruin)
	assert(ruin_candidates <= 24)
	assert(cm.count_loaded_lakes() >= 1)
	assert(cm.count_loaded_ruins() >= 1)
	assert(max_ruin_reagents >= 2)
	assert(max_ruin_reagents <= 6)
	var lake_p: Vector3 = cm.get_any_lake_sample_point()
	assert(lake_p != Vector3.ZERO)
	assert(cm.is_world_in_lake(lake_p))
	assert(not cm.is_world_in_lake(Vector3(0, 1, 0)))
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
	assert(irregular_ok)
	var lakes_flat := true
	for lx in range(-8, 9):
		for lz in range(-8, 9):
			var lcc := Vector2i(lx, lz)
			if cm.chunk_has_lake(lcc):
				cm.ensure_chunk_loaded(lcc)
				if cm.has_method("lake_has_no_hills") and not cm.lake_has_no_hills(lcc):
					lakes_flat = false
	assert(lakes_flat)
	var col_issues: Array = cm.collect_collision_issues()
	assert(col_issues.is_empty())
	assert(cm.lake_water_is_planar())
	assert(cm.LAKE_DEPTH > 1.0)
	assert(cm.HILL_MAX == 4)
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
			if hh == 4:
				found_h4 = true
	assert(found_h4)
	assert(max_h == 4)
	assert(hill_n * 3 < sample_n) # холмы заметно реже трети клеток
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
	assert(hill_cell.y != -999)
	assert(cm.has_terrain_visual(hill_cell))
	await process_frame
	await physics_frame
	await physics_frame
	var hfrom := Vector3(float(hill_cell.x) + 0.5, float(hill_cell.y) + 3.3, float(hill_cell.z) + 0.5)
	var hto := Vector3(float(hill_cell.x) + 0.5, float(hill_cell.y) + 0.4, float(hill_cell.z) + 0.5)
	var hhit: Dictionary = cm.ray_query_terrain(hfrom, hto)
	assert(not hhit.is_empty())
	assert(hhit.collider != null)
	assert(hhit.collider.has_meta("terrain_chunk"))
	assert(str(hhit["kind"]) == "hill")
	var hmined: Vector3i = hhit["cell"]
	assert(hmined == hill_cell)
	assert(cm.mine_terrain_at(hmined, "hill"))
	assert(not cm.has_terrain_visual(hmined))
	cm.rebuild_chunk(cm.world_to_chunk(Vector3(hmined.x, 0, hmined.z)))
	assert(not cm.has_terrain_visual(hmined))
	var ruin_cell: Vector3i = cm.find_first_terrain("ruin")
	if ruin_cell.y == -999:
		for rx in range(-8, 9):
			for rz in range(-8, 9):
				if cm.chunk_has_ruin(Vector2i(rx, rz)):
					cm.ensure_chunk_loaded(Vector2i(rx, rz))
		ruin_cell = cm.find_first_terrain("ruin")
	assert(ruin_cell.y != -999)
	while cm.terrain_kind_at(ruin_cell + Vector3i(0, 1, 0)) == "ruin":
		ruin_cell += Vector3i(0, 1, 0)
	assert(cm.has_terrain_visual(ruin_cell))
	await process_frame
	await physics_frame
	var rfrom := Vector3(float(ruin_cell.x) + 0.5, float(ruin_cell.y) + 3.3, float(ruin_cell.z) + 0.5)
	var rto := Vector3(float(ruin_cell.x) + 0.5, float(ruin_cell.y) + 0.4, float(ruin_cell.z) + 0.5)
	var rhit: Dictionary = cm.ray_query_terrain(rfrom, rto)
	assert(not rhit.is_empty())
	assert(rhit.collider != null)
	assert(rhit.collider.has_meta("terrain_chunk"))
	assert(str(rhit["kind"]) == "ruin")
	var rmined: Vector3i = rhit["cell"]
	assert(cm.mine_terrain_at(rmined, "ruin"))
	assert(not cm.has_terrain_visual(rmined))
	cm.rebuild_chunk(cm.world_to_chunk(Vector3(rmined.x, 0, rmined.z)))
	assert(not cm.has_terrain_visual(rmined))
	var gs_r: Node = gs_script.new()
	root.add_child(gs_r)
	assert(gs_r.remove_terrain_cell(hmined, "hill"))
	assert(gs_r.remove_terrain_cell(rmined, "ruin"))
	assert(gs_r.is_terrain_removed(hmined))
	assert(gs_r.is_terrain_removed(rmined))
	var terrain_blob: Dictionary = gs_r.to_save_dict()
	assert(terrain_blob.has("removed_terrain"))
	var gs_r2: Node = gs_script.new()
	root.add_child(gs_r2)
	gs_r2.apply_save_dict(terrain_blob)
	assert(gs_r2.is_terrain_removed(hmined))
	assert(gs_r2.is_terrain_removed(rmined))
	assert(str(gs_r2.terrain_removed_kind(hmined)) == "hill")
	assert(str(gs_r2.terrain_removed_kind(rmined)) == "ruin")
	var hud_packed = load("res://scenes/hud.tscn")
	if hud_packed:
		var hud_n: Node = hud_packed.instantiate()
		root.add_child(hud_n)
		await process_frame
		if hud_n.has_method("boss_bar_fill_is_red"):
			assert(hud_n.boss_bar_fill_is_red())
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
	assert(reagent_on_top)
	var nav_script: GDScript = load("res://scripts/enemy_navigation.gd")
	assert(nav_script.WATER_COST > 1.0)
	var pth: Array = nav_script.find_path(Vector3(0, 1, 0), Vector3(6, 1, 0), cm)
	assert(pth.size() >= 2)

	# Враг (Шовник)
	var enemy_script: GDScript = load("res://scripts/seam_creature.gd")
	var enemy: CharacterBody3D = enemy_script.new()
	enemy.position = Vector3(18, 1, 16)
	root.add_child(enemy)
	await process_frame
	await process_frame
	assert(enemy.is_in_group("seam_creature"))
	enemy.configure_elite(true)
	assert(enemy.elite)
	enemy._apply_dream_state(true)
	assert(enemy.frozen)
	enemy._apply_dream_state(false)
	assert(not enemy.frozen)
	assert(is_equal_approx(enemy.SPEED_NORMAL, 2.15 * 0.6))
	assert(is_equal_approx(enemy.SPEED_ELITE, 2.85 * 0.6))
	assert(enemy.collision_layer == 16)
	assert(enemy.collision_mask & 16 != 0)
	assert(enemy.collision_mask & 1 != 0)
	assert(enemy.collision_mask & 2 != 0)
	assert(enemy.collision_mask & 4 != 0)
	assert(enemy.has_node("Model"))
	assert(enemy.hp == 50)
	assert(enemy.max_hp == 50)
	var vis: GDScript = load("res://scripts/enemy_visuals.gd")
	assert(vis.has_clip(enemy, "walk"))
	assert(vis.has_clip(enemy, "attack"))
	assert(vis.has_clip(enemy, "idle"))
	assert(vis.has_clip(enemy, "death"))
	var played: String = vis.play_state(enemy, "walk", true)
	assert(played != "")
	enemy.take_damage(10)
	assert(enemy.hp == 40)
	assert(is_equal_approx(enemy.ATTACK_INTERVAL, 0.55))

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
	assert(g1.is_in_group("enemy_ghost"))
	assert(g1.kind_name() == "враг1")
	assert(g2.kind_name() == "враг2")
	assert(g3.kind_name() == "враг3")
	assert(g4.kind_name() == "враг4")
	var blinky_t: Vector3 = g1.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	assert(blinky_t.is_equal_approx(Vector3(5, 0, 0)))
	var pinky_t: Vector3 = g2.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	assert(pinky_t.is_equal_approx(Vector3(11, 0, 0)))
	var inky_t: Vector3 = g3.compute_target(Vector3(4, 0, 0), Vector3(0, 0, -1), Vector3.ZERO, false)
	assert(inky_t.is_equal_approx(Vector3(8, 0, 0)))
	var clyde_far: Vector3 = g4.compute_target(Vector3(30, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	assert(clyde_far.is_equal_approx(Vector3(30, 0, 0)))
	var clyde_near: Vector3 = g4.compute_target(Vector3(2, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, false)
	assert(clyde_near.is_equal_approx(Vector3(-10, 1, -10)))
	var scatter_t: Vector3 = g1.compute_target(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3.ZERO, true)
	assert(scatter_t.is_equal_approx(Vector3(10, 1, 10)))
	g1._apply_dream_state(true)
	assert(g1.frozen)
	assert(is_equal_approx(g1.SPEED, 2.45 * 0.6))
	assert(g1.collision_layer == 16)
	assert(g1.collision_mask & 16 != 0)
	assert(g1.collision_mask & 2 != 0)
	assert(g1.collision_mask & 4 != 0)
	assert(g1.has_node("Model"))
	assert(g1.hp == 50)
	g1.take_damage(10)
	assert(g1.hp == 40)
	assert(vis.has_clip(g1, "walk"))
	assert(vis.has_clip(g1, "attack"))
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = boss_script.new()
	boss.position = Vector3(4, 1, 4)
	root.add_child(boss)
	await process_frame
	await process_frame
	assert(boss.is_in_group("block_mother"))
	assert(boss.hp == 500)
	assert(boss.max_hp == 500)
	boss.take_damage(10)           # SPAWN — неуязвима
	assert(boss.hp == 500)
	boss._enter(boss.S.IDLE)
	boss.take_damage(10)
	assert(boss.hp == 490)
	assert(boss.get_tree() != null)
	var td_script: GDScript = load("res://scripts/threat_director.gd")
	var td: Node = td_script.new()
	assert(td.MAX_ENEMIES == 7)
	var dc_script: GDScript = load("res://scripts/day_cycle.gd")
	var dc: Node = dc_script.new()
	dc.time_of_day = 10.0
	assert(not dc.is_night())
	dc.time_of_day = 1100.0
	assert(dc.is_night())
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
	assert(gs.remove_terrain_cell(Vector3i(9, 2, 9), "hill"))
	assert(gs.remove_terrain_cell(Vector3i(11, 1, 7), "ruin"))
	var blob: Dictionary = gs.to_save_dict()
	assert(blob.has("wake_blocks"))
	assert(blob.has("dust"))
	assert(blob.has("dream_exit_count"))
	assert(blob.has("reagent_counts"))
	assert(blob.has("item_slots"))
	assert(blob.has("removed_terrain"))
	assert(int(blob["dream_exit_count"]) >= 1)
	var path := "user://sonnaya_smoke_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_string(JSON.stringify(blob))
	f = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(typeof(parsed) == TYPE_DICTIONARY)
	var gs2: Node = gs_script.new()
	root.add_child(gs2)
	gs2.apply_save_dict(parsed)
	assert(gs2.dust == 11)
	assert(gs2.nails == 7)
	assert(gs2.wedges == 2)
	assert(gs2.wake_blocks.has(Vector3i(3, 1, 4)))
	assert(gs2.dream_blocks.has(Vector3i(2, 2, 2)))
	assert(gs2.is_terrain_removed(Vector3i(9, 2, 9)))
	assert(gs2.is_terrain_removed(Vector3i(11, 1, 7)))
	assert(gs2.dream_exit_count == gs.dream_exit_count)
	assert(gs2.get_reagent_count(2) == gs.get_reagent_count(2))
	assert(gs2.get_reagent_count(3) == gs.get_reagent_count(3))
	assert(gs2.item_slots[added_at].get("id") == "test_tool")
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

	print("SMOKE: OK v0.6 transferred=%d dust_result=%d mutations=%d nails=%d wedges=%d a3=%d chunks=%d enemies=%d ghosts=%d lakes=%d ruins=%d reagents=%d ruin_max=%d save=1 exits=%d persist=%d hill4=%d night=1 torch=1 sword=1 boss=1 drops=1 music=1 col=0 mine=1 tools=1 bossbar=1" % [
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
		assert(pk != null)
		assert(pk.can_instantiate())
	for scr in ["res://scripts/inventory_ui.gd", "res://scripts/settings_menu.gd", "res://scripts/pause_menu.gd",
			"res://scripts/main_menu.gd", "res://scripts/entity_culler.gd", "res://scripts/world_store.gd",
			"res://scripts/item_db.gd", "res://scripts/slot_view.gd"]:
		assert(load(scr) != null)

	# --- Сиды ---
	assert(gs_script.seed_from_text("12345") == 12345)
	assert(gs_script.seed_from_text("6767676767") == 6767676767)
	assert(gs_script.seed_from_text("дом") == gs_script.seed_from_text("дом"))
	assert(gs_script.seed_from_text("дом") != gs_script.seed_from_text("сон"))
	assert(gs_script.derive_dream_seed(42) == gs_script.derive_dream_seed(42))
	assert(gs_script.derive_dream_seed(42) != gs_script.derive_dream_seed(43))
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
	assert(sigs[0] == sigs[1])
	assert(sigs[0] != sigs[2])
	print("SMOKE: determinism sig=%d other=%d" % [sigs[0], sigs[2]])

	# --- Инвентарь: стаки, swap, quick_move, set_slot ---
	var gi: Node = gs_script.new()
	root.add_child(gi)
	gi.reset_state()
	assert(gi.add_item_count("drift", 70) == 70)
	assert(gi.raw_count("drift") == 70)
	assert(int(gi.item_slots[0].get("count")) == 64)
	assert(int(gi.item_slots[1].get("count")) == 6)
	gi.swap_slots(0, 20)
	assert(int(gi.item_slots[20].get("count")) == 64 and str(gi.item_slots[0].get("id")) == "")
	gi.quick_move(20) # основной → хотбар
	assert(str(gi.item_slots[20].get("id")) == "")
	assert(gi.raw_count("drift") == 70)
	gi.quick_move(1) # хотбар → основной
	var in_main := 0
	for i in range(9, 36):
		if str(gi.item_slots[i].get("id", "")) == "drift":
			in_main += int(gi.item_slots[i]["count"])
	assert(in_main >= 6)
	gi.set_slot(5, {"id": "torch", "count": 3})
	assert(gi.count_item("torch") == 3)
	assert(gi.remove_item("torch", 2) and gi.count_item("torch") == 1)
	assert(not gi.remove_item("torch", 5))
	gi.add_item_count("nail", 2)
	assert(_slot_of(gi, "nail") == -1) # якоря не в инвентаре
	gi.dust = 40
	assert(gi.count_item("dust") == 40 and gi.dust == 40)
	var icon: Texture2D = load("res://scripts/item_db.gd").icon("pickaxe")
	assert(icon != null)
	for iid in load("res://scripts/item_db.gd").all_icon_ids():
		assert(ResourceLoader.exists("res://assets/icons/%s.png" % iid))

	# --- Осыпь за убийства ---
	assert(gs_script.new().DUST_PER_KILL == 20)
	gi.dust = 0
	assert(gi.reward_kill(false, "Шовник") == 20)
	assert(gi.dust == 20)
	assert("+20 осыпи" in gi.last_hint)
	assert(gi.reward_kill(true, "Мать блоков") == 250)
	assert(gi.dust == 270)

	# --- Дев-сид 6767676767: всё бесконечно ---
	var gd: Node = gs_script.new()
	root.add_child(gd)
	gd.begin_world("dev", "", "6767676767", gs_script.seed_from_text("6767676767"), false)
	assert(gd.dev_mode)
	assert(gd.dust == gd.INF_COUNT)
	assert(gd.get_reagent_count(1) == gd.INF_COUNT)
	assert(gd.count_text(gd.special_display_count("nail")) == "∞")
	var n0: int = gd.nails
	for rec in gd.recipe_defs():
		assert(gd.can_afford_recipe(rec))
	assert(gd.craft_recipe("wedge", {"is_dream": true}))
	assert(gd.craft_recipe("pickaxe", {"at_workbench": true}))
	assert(gd.dust == gd.INF_COUNT)
	assert(gd.consume_item("torch", 1))
	assert(gd.count_item("torch") == gd.INF_COUNT)
	gd.enter_dream()
	gd.select_anchor(gd.AnchorType.NAIL)
	gd.place_dream_block(Vector3i(0, 0, 0), "drift")
	assert(gd.try_place_anchor(Vector3i(0, 0, 0)))
	assert(gd.nails == n0)
	assert(gd.reward_kill(false, "x") == 0 or gd.dust == gd.INF_COUNT)
	assert(gd.steal_resource_hardcore() == "none")

	# --- Миграция сейва v4 → v5 ---
	var v4 := {"version": 4, "dust": 33, "reagent_counts": [4, 5, 6], "nails": 2, "wedges": 1, "anchors3": 1,
		"item_slots": [{"id": "nail", "count": 2}, {"id": "wedge", "count": 1}, {"id": "anchor3", "count": 1},
			{"id": "pickaxe", "name": "Кирка", "count": 1}, {"id": "drift", "name": "Нанос", "count": 5}],
		"wake_blocks": {}, "dream_blocks": {}}
	var gm: Node = gs_script.new()
	root.add_child(gm)
	gm.apply_save_dict(v4)
	assert(gm.item_slots.size() == 36)
	assert(gm.dust == 33)
	assert(gm.get_reagent_count(2) == 5)
	assert(gm.count_item("pickaxe") == 1 and gm.count_item("drift") == 5)
	assert(gm.nails == 2 and gm.anchors3 == 1)
	assert(_slot_of(gm, "nail") == -1)
	var v5: Dictionary = gm.to_save_dict()
	assert(int(v5["version"]) >= 5)
	var gm2: Node = gs_script.new()
	root.add_child(gm2)
	gm2.apply_save_dict(JSON.parse_string(JSON.stringify(v5)))
	assert(gm2.dust == 33 and gm2.count_item("drift") == 5)

	# --- Хранилище миров ---
	var ws: GDScript = load("res://scripts/world_store.gd")
	var meta: Dictionary = ws.create_world("Смоук тест", "abc", gs_script.seed_from_text("abc"), false)
	var folder := str(meta.get("folder", ""))
	assert(folder != "")
	var found := false
	for w in ws.list_worlds():
		if str(w.get("folder", "")) == folder:
			found = true
			assert(ws.meta_seed(w) == gs_script.seed_from_text("abc"))
	assert(found)
	ws.delete_world(folder)
	for w2 in ws.list_worlds():
		assert(str(w2.get("folder", "")) != folder)

	# --- Настройки ---
	var gset: Node = root.get_node("GameSettings")
	assert(gset.render_distance >= 2 and gset.render_distance <= 8)
	assert(gset.entity_distance_m() > 0.0)

	# --- HUD: хотбар 9 + вертикальная полоса ---
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	assert(hud.find_child("SpecialBar", true, false) != null)
	var hb: Node = hud.find_child("Hotbar", true, false)
	assert(hb != null and hb.get_child_count() == 9)
	print("SMOKE: v0.5 checks OK")
	_v05_ok = true


var _v06_ok := false


func _v06_checks(gs_script: GDScript, cm_script: GDScript) -> void:
	print("SMOKE: v0.6 checks")
	var G: Node = root.get_node("GameState")
	G.reset_state()
	G.peaceful = false
	assert(not G.is_dream())
	# --- Сутки 24 минуты, фазы ---
	assert(is_equal_approx(G.DAY_CYCLE, 1440.0))
	assert(G.phase_at(30.0) == "morning")
	assert(G.phase_at(500.0) == "day")
	assert(G.phase_at(900.0) == "evening")
	assert(G.phase_at(1200.0) == "night")
	assert(G.phase_at(1440.0 + 30.0) == "morning")
	assert(G.clock_text(0.0) == "06:00")
	assert(G.clock_text(1080.0) == "00:00")
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
	assert(G.is_night() and dc.is_night())
	var moon: DirectionalLight3D = dc.get_moon()
	assert(moon != null and moon.visible and moon.light_energy > 0.15)
	assert(moon.light_color.b > moon.light_color.r)
	assert(sun.light_energy < 0.05 or not sun.visible)
	assert(dc.moon_dir().y > 0.2)   # луна над горизонтом
	dc.set_time(500.0)
	assert(not dc.is_night())
	assert(moon.light_energy < 0.01 or not moon.visible)
	assert(sun.light_energy > 0.5)
	holder.queue_free()
	# --- Деревья: детерминированно по сидам, по всему миру, с коллизией ---
	var cm1: Node3D = cm_script.new()
	cm1.panorama_mode = true
	assert(cm1.tree_plan(Vector2i(5, -7)) == cm1.tree_plan(Vector2i(5, -7)))
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
	assert(trees >= 6)
	var tree: Dictionary = cm.find_first_tree()
	assert(not tree.is_empty())
	var log1: Vector3i = (tree["logs"] as Array)[1]
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = Vector3(log1) + Vector3(0.5, 0.5, 0.5)
	q.collide_with_bodies = true
	var tree_col := space.intersect_point(q).size() > 0
	assert(tree_col)
	# --- Ломаем все брёвна → листва постепенно опадает ---
	var leaves: Array = tree["leaves"]
	for raw in tree["logs"]:
		var c: Vector3i = raw
		assert(G.remove_terrain_cell(c, "log"))
		cm.rebuild_chunk_at_world(c.x, c.z)
	var pend: int = cm.pending_leaf_decay()
	assert(pend > 0)
	var left_before := 0
	for raw2 in leaves:
		if not G.is_terrain_removed(raw2):
			left_before += 1
	assert(left_before > 0)   # не мгновенно
	cm.force_leaf_decay_tick(30.0)
	assert(cm.pending_leaf_decay() == 0)
	for raw3 in leaves:
		assert(G.is_terrain_removed(raw3))
	# Сохранение: сломанные брёвна/листва — в сейве
	var blob: Dictionary = G.to_save_dict()
	var g2: Node = gs_script.new()
	root.add_child(g2)
	g2.apply_save_dict(JSON.parse_string(JSON.stringify(blob)))
	assert(g2.is_terrain_removed((tree["logs"] as Array)[0]))
	assert(g2.is_terrain_removed(leaves[0]))
	assert(int(blob["version"]) == 6)
	cm.queue_free()
	anchor.queue_free()
	# --- Бревно → доски (верстак) ---
	assert(G.find_recipe("planks").size() > 0)
	# --- Шанс босса + предвестие + флаг в сейве ---
	var chats: Array = []
	var cb := func(t: String, _c: Color = Color.WHITE) -> void: chats.append(t)
	G.chat_message.connect(cb)
	G.world_seed = 6767676767
	G.dev_mode = true
	assert(is_equal_approx(G.boss_spawn_chance(), 0.25))
	G.dev_mode = false
	G.world_seed = 12345
	assert(is_equal_approx(G.boss_spawn_chance(), 0.01))
	G.boss_next_mine = false
	G.set_boss_alive(false)
	assert(not G.on_block_mined(0.5))       # 0.5 ≥ 1% → нет
	assert(not G.boss_next_mine)
	assert(not G.on_block_mined(0.005))     # бросок на СЛЕДУЮЩИЙ блок → предвестие
	assert(G.boss_next_mine)
	assert(chats.has(G.BOSS_OMEN_TEXT))
	assert(G.BOSS_OMEN_TEXT == "Вы слышите разъярённые крики убитой горем матери")
	var b2: Dictionary = G.to_save_dict()
	var g3: Node = gs_script.new()
	root.add_child(g3)
	g3.apply_save_dict(JSON.parse_string(JSON.stringify(b2)))
	assert(g3.boss_next_mine)
	assert(G.on_block_mined(0.9))           # следующий блок — босс
	assert(not G.boss_next_mine)
	G.chat_message.disconnect(cb)
	# --- Урон-капы игрока ---
	G.heal_player_full()
	var total := 0
	for k in range(4):
		total += int(G.damage_player(30, "smoke", true))
	assert(total <= 70)
	assert(G.player_hp == 100 - total)
	G.heal_player_full()
	# --- Клавиши: переназначение, конфликт, сохранение ---
	var gset: Node = root.get_node("GameSettings")
	gset.reset_bindings()
	var jump_new := {"type": "key", "code": KEY_KP_7}
	assert(gset.rebind("jump", jump_new) == "")
	var has_f := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_KP_7:
			has_f = true
	assert(has_f)
	var back_b: Dictionary = gset.bindings["move_back"] if gset.bindings.has("move_back") else gset.bindings["back"]
	var back_name := "move_back" if gset.bindings.has("move_back") else "back"
	var fwd_name := "move_forward" if gset.bindings.has("move_forward") else "forward"
	var fwd_old: Dictionary = gset.bindings[fwd_name]
	assert(gset.rebind(fwd_name, back_b) == back_name)   # конфликт → обмен
	assert(gset.bindings[fwd_name] == back_b and gset.bindings[back_name] == fwd_old)
	var gs_new: Node = load("res://scripts/game_settings.gd").new()
	gs_new.load_settings()
	assert(gs_new.bindings["jump"] == jump_new)
	assert(gs_new.bindings[fwd_name] == back_b)
	gs_new.free()
	gset.reset_bindings()
	assert(gset.bindings["jump"] == gset.default_binding("jump"))
	# --- Босс: 500 HP, фазы 66/33 с переходами, уязвимость ---
	var host := Node3D.new()
	root.add_child(host)
	var bs: GDScript = load("res://scripts/block_mother.gd")
	for old in get_nodes_in_group("block_mother"):
		old.free()
	var boss: CharacterBody3D = bs.new()
	host.add_child(boss)
	await process_frame
	assert(boss.hp == 500 and boss.phase == 1)
	boss._enter(boss.S.IDLE)
	boss.take_damage(400)                 # не проваливается сквозь порог фазы
	assert(boss.hp == boss.P2_AT)
	assert(boss.phase == 2 and boss.state == boss.S.TRANSITION)
	boss.take_damage(50)                  # переход неуязвим
	assert(boss.hp == boss.P2_AT)
	boss._enter(boss.S.STAGGER)
	boss._stagger_len = 2.0
	assert(boss.is_vulnerable())
	boss.take_damage(10)                  # ×1.5 в окне уязвимости
	assert(boss.hp == boss.P2_AT - 15)
	boss.take_damage(400)
	assert(boss.hp == boss.P3_AT and boss.phase == 3)
	boss._enter(boss.S.STAGGER)
	boss.take_damage(400)
	assert(boss.hp <= 0 or boss.state == boss.S.DEAD)
	# Пити-таймер блоклингов и жёсткий кап
	var b3: CharacterBody3D = bs.new()
	host.add_child(b3)
	await process_frame
	var got := 0
	for r in range(3):
		if b3.minion_roll(0.99):
			got += 1
	assert(got == 1)                       # 3 неудачи подряд → гарантия
	assert(not b3.minion_roll(0.0) and not b3.minion_roll(0.0))   # локаут 2 приземления
	assert(b3.MINION_HARD_CAP == 6)
	for cap in b3.MINION_CAP:
		assert(int(cap) <= b3.MINION_HARD_CAP)
	# Телеграфы ≥0.4 с, урон одного удара ≤40% HP
	for w in b3.WINDUP:
		assert(float(w) >= 0.4)
	assert(b3.RAIN_WINDUP >= 0.4 and b3.BRICK_SHADOW >= 0.4 and b3.MARKER_TIME >= 0.4)
	for dmg in [b3.SLAM_DAMAGE, b3.WAVE_DAMAGE, b3.REASSEMBLE_DAMAGE, b3.BRICK_DAMAGE, b3.CONTACT_DAMAGE]:
		assert(int(dmg) <= 40)
	b3.queue_free()
	host.queue_free()
	await process_frame
	print("SMOKE: v0.6 checks OK trees=%d tree_col=%s leaves_pending=%d" % [trees, str(tree_col), pend])
	_v06_ok = true
