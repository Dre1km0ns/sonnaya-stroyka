extends SceneTree
## Headless smoke v0.4: transfer + чанки + враг + сейв + реагенты + инвентарь + призраки.
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
	assert(int(result["dust"]) == 9)
	assert(gs.dust == before_dust + 9)
	assert(gs.wake_blocks.has(Vector3i(1, 1, 1)))
	assert(gs.craft_nail_from_dust())

	# Клин из осыпи
	gs.dust = 20
	var wedges_before: int = gs.wedges
	assert(gs.craft_wedge_from_dust())
	assert(gs.wedges == wedges_before + 1)
	assert(gs.dust == 20 - gs.WEDGE_CRAFT_DUST)

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

	# Инвентарь 5 слотов
	assert(gs.item_slots.size() == 5)
	gs.select_item_slot(3)
	assert(gs.selected_slot == 3)
	gs.cycle_item_slot(1)
	assert(gs.selected_slot == 4)
	gs.cycle_item_slot(1)
	assert(gs.selected_slot == 0)
	var added_at: int = gs.add_item("test_tool", "Тест", 1)
	assert(added_at == 2)
	assert(str(gs.item_slots[2].get("id")) == "test_tool")
	assert(int(gs.item_slots[2].get("count")) == 1)

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
	for x in range(-8, 9):
		for z in range(-8, 9):
			var c := Vector2i(x, z)
			if cm.chunk_has_lake(c):
				cm.ensure_chunk_loaded(c)
				found_lake = true
			if cm.chunk_has_ruin(c):
				cm.ensure_chunk_loaded(c)
				found_ruin = true
	assert(found_lake)
	assert(found_ruin)
	assert(cm.count_loaded_lakes() >= 1)
	assert(cm.count_loaded_ruins() >= 1)
	assert(cm.count_loaded_reagents() >= 1)
	var lake_p: Vector3 = cm.get_any_lake_sample_point()
	assert(lake_p != Vector3.ZERO)
	assert(cm.is_world_in_lake(lake_p))
	assert(not cm.is_world_in_lake(Vector3(0, 1, 0)))

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
	assert(str(gs2.item_slots[2].get("id")) == "test_tool")
	# Очистка smoke-файла
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var enemy_count := 0
	for n in get_nodes_in_group("seam_creature"):
		enemy_count += 1
	var ghost_count := 0
	for n2 in get_nodes_in_group("enemy_ghost"):
		ghost_count += 1

	print("SMOKE: OK transferred=%d dust_result=%d mutations=%d nails=%d wedges=%d chunks=%d enemies=%d ghosts=%d lakes=%d ruins=%d reagents=%d save=1 exits=%d" % [
		int(result["transferred"]), int(result["dust"]), int(result["mutations"]), gs.nails, gs.wedges,
		cm.get_loaded_count(), enemy_count, ghost_count, cm.count_loaded_lakes(), cm.count_loaded_ruins(),
		cm.count_loaded_reagents(), gs_m.dream_exit_count
	])
	quit(0)
