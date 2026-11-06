extends SceneTree
## Headless smoke v0.4.3: transfer + чанки + враг + сейв + реагенты + инвентарь + призраки.
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
	assert(not gs.craft_nail_from_dust())
	gs.dust = 10
	assert(gs.craft_nail_from_dust())
	assert(gs.NAIL_CRAFT_DUST == 10)

	# Клин из осыпи
	gs.dust = 100
	var wedges_before: int = gs.wedges
	assert(gs.craft_wedge_from_dust())
	assert(gs.wedges == wedges_before + 1)
	assert(gs.dust == 0)
	assert(gs.WEDGE_CRAFT_DUST == 100)
	gs.dust = 250
	var a3_before: int = gs.anchors3
	assert(gs.craft_anchor3_from_dust())
	assert(gs.anchors3 == a3_before + 1)
	assert(gs.dust == 0)
	assert(gs.ANCHOR3_CRAFT_DUST == 250)
	assert(gs.ANCHOR3_SIZE == 9)
	assert(is_equal_approx(gs.CLARITY_DRAIN_PER_SEC, 1.25))
	assert(gs.recipe_defs().size() >= 6)
	assert(not gs.find_recipe("torch").is_empty())
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

	# Инвентарь 5 слотов (0 гвоздь, 1 клин, 2 якорь3)
	assert(gs.item_slots.size() == 5)
	assert(str(gs.item_slots[2].get("id")) == "anchor3")
	gs.select_item_slot(3)
	assert(gs.selected_slot == 3)
	gs.cycle_item_slot(1)
	assert(gs.selected_slot == 4)
	gs.cycle_item_slot(1)
	assert(gs.selected_slot == 0)
	var added_at: int = gs.add_item("test_tool", "Тест", 1)
	assert(added_at == 3)
	assert(str(gs.item_slots[3].get("id")) == "test_tool")
	assert(int(gs.item_slots[3].get("count")) == 1)

	# Верстак и кирка
	var gs_c: Node = gs_script.new()
	root.add_child(gs_c)
	gs_c.enter_dream()
	gs_c.reagent_counts = [10, 0, 0]
	gs_c.reagents = 10
	assert(gs_c.craft_recipe("workbench", {"is_dream": true}))
	assert(str(gs_c.item_slots[3].get("id")) == "workbench")
	assert(not gs_c.craft_recipe("pickaxe", {"at_workbench": false}))
	gs_c.reagent_counts = [0, 2, 3]
	gs_c.reagents = 5
	assert(gs_c.craft_recipe("pickaxe", {"at_workbench": true}))
	assert(str(gs_c.item_slots[4].get("id")) == "pickaxe")
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
	gs_c.select_item_slot(4)
	assert(gs_c.selected_is("pickaxe"))
	var mine_cell := Vector3i(3, 0, 3)
	gs_c.wake_blocks[mine_cell] = {"kind": "drift", "mutant": false}
	assert(gs_c.mine_wake_block(mine_cell))
	assert(not gs_c.wake_blocks.has(mine_cell))
	var gs_t: Node = gs_script.new()
	root.add_child(gs_t)
	gs_t.reagent_counts = [1, 1, 0]
	gs_t.reagents = 2
	assert(gs_t.craft_recipe("torch", {"at_workbench": true}))
	assert(str(gs_t.item_slots[3].get("id")) == "torch")
	var torch_cell := Vector3i(4, 0, 5)
	assert(gs_t.place_wake_block(torch_cell, "torch"))
	assert(str(gs_t.wake_blocks[torch_cell].get("kind")) == "torch")
	assert(FileAccess.file_exists("res://assets/audio/music.mp3"))
	assert(ResourceLoader.exists("res://assets/models/ghost.glb"))
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
	var td_script: GDScript = load("res://scripts/threat_director.gd")
	var td: Node = td_script.new()
	assert(td.MAX_ENEMIES == 7)
	var dc_script: GDScript = load("res://scripts/day_cycle.gd")
	var dc: Node = dc_script.new()
	assert(is_equal_approx(dc.DAY_LENGTH, 300.0))
	dc.time_of_day = 10.0
	assert(not dc.is_night())
	dc.time_of_day = 301.0
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
	var blob: Dictionary = gs.to_save_dict()
	assert(blob.has("wake_blocks"))
	assert(blob.has("dust"))
	assert(blob.has("dream_exit_count"))
	assert(blob.has("reagent_counts"))
	assert(blob.has("item_slots"))
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
	assert(gs2.dream_exit_count == gs.dream_exit_count)
	assert(gs2.get_reagent_count(2) == gs.get_reagent_count(2))
	assert(gs2.get_reagent_count(3) == gs.get_reagent_count(3))
	assert(str(gs2.item_slots[3].get("id")) == "test_tool")
	# Очистка smoke-файла
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var enemy_count := 0
	for n in get_nodes_in_group("seam_creature"):
		enemy_count += 1
	var ghost_count := 0
	for n2 in get_nodes_in_group("enemy_ghost"):
		ghost_count += 1

	print("SMOKE: OK v0.4.3 transferred=%d dust_result=%d mutations=%d nails=%d wedges=%d a3=%d chunks=%d enemies=%d ghosts=%d lakes=%d ruins=%d reagents=%d ruin_max=%d save=1 exits=%d persist=%d hill4=%d night=1 torch=1 music=1 col=0" % [
		int(result["transferred"]), int(result["dust"]), int(result["mutations"]), gs.nails, gs.wedges, gs.anchors3,
		cm.get_loaded_count(), enemy_count, ghost_count, cm.count_loaded_lakes(), cm.count_loaded_ruins(),
		cm.count_loaded_reagents(), max_ruin_reagents, gs_m.dream_exit_count, persist_count, 1 if found_h4 else 0
	])
	quit(0)
