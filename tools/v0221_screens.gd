extends SceneTree
## Кадры v0.22.1. DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v0221_screens.gd -- --out=/workspace/shots/v0221
var OUT := "/workspace/shots/v0221/"
var gs; var main; var player
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", name)
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch
func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	await _shot("00_main_menu.png")
	var mm = current_scene
	mm._show("create"); mm._name_edit.text = "Кадры v0.22.1"; mm._seed_edit.text = "6767676767"
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player")
	gs.skip_tutorial()
	player.set_physics_process(false)
	var p0: Vector3 = player.global_position
	print("DREAM p0 ", p0, " spawn ", gs.spawn_point)
	# Сон у спавна: что висит в воздухе
	_look(p0 + Vector3(0, 1.5, 0), 0.0, -0.15); await _wait(40)
	await _shot("01_dream_spawn_n.png")
	_look(p0 + Vector3(0, 1.5, 0), PI, -0.15); await _wait(20)
	await _shot("02_dream_spawn_s.png")
	_look(p0 + Vector3(0, 12, 14), 0.0, -0.6); await _wait(30)
	await _shot("03_dream_spawn_above.png")
	# фиолетовые блоки Сна
	var base := Vector3i(int(p0.x) + 3, int(floor(p0.y)), int(p0.z) - 4)
	var cells: Array = []
	var kinds := ["stone", "planks", "log", "dirt", "strut", "ruin", "sand", "leaves"]
	for i in range(kinds.size()):
		var c := base + Vector3i(i % 4, 0, i / 4)
		if gs.place_dream_block(c, kinds[i]): cells.append(c)
	var wb := base + Vector3i(0, 0, 3)
	if gs.place_dream_block(wb, "workbench"): cells.append(wb)
	var tc := base + Vector3i(2, 0, 3)
	if gs.place_dream_block(tc, "torch"): cells.append(tc)
	main.dream_voxels.sync_cells(cells)
	print("DREAM placed ", cells.size())
	_look(Vector3(base) + Vector3(1.5, 2.6, 6.5), 0.0, -0.35); await _wait(30)
	await _shot("04_dream_purple_blocks.png")
	print("DREAM chat ", gs.muted_chat.slice(maxi(0, gs.muted_chat.size() - 5)))
	# Явь
	main.switcher.wake_up(true); await _wait(60)
	var ui = get_first_node_in_group("transfer_result_ui")
	if ui and ui.panel.visible: ui.close()
	await _wait(10)
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	var sp: Vector3 = gs.spawn_point
	_look(sp + Vector3(0, 0.2, 0), 0.6, -0.1); await _wait(40)
	await _shot("05_wake_camp.png")
	_look(sp + Vector3(0, 9, 13), 0.0, -0.55); await _wait(40)
	await _shot("06_wake_camp_above.png")
	# стамина
	gs.stamina = 0.45; gs.stamina_changed.emit(gs.stamina, false)
	_look(sp + Vector3(3, 0.2, 3), 2.0, -0.05); await _wait(10)
	await _shot("07_stamina_bar.png")
	gs.stamina = 1.0; gs.stamina_changed.emit(1.0, false)
	# земля: трава сверху, земля под блоком; подпорка; настенный факел
	gs.dev_mode = true
	var con = get_first_node_in_group("dev_console")
	var g0 := Vector3i(int(sp.x) + 8, int(main.wake_chunks.height_at(int(sp.x) + 8, int(sp.z) + 8)), int(sp.z) + 8)
	var wc: Array = []
	for y in range(3):
		for x in range(3):
			var c := g0 + Vector3i(x, y, 0)
			if gs.place_wake_block(c, "dirt" if x < 2 else "strut"): wc.append(c)
	var t1 := g0 + Vector3i(1, 1, 1)
	if gs.place_wake_block(t1, "torch"):
		gs.wake_blocks[t1]["attach"] = [g0.x + 1, g0.y + 1, g0.z]; wc.append(t1)
	var t2 := g0 + Vector3i(-1, 2, 0)
	if gs.place_wake_block(t2, "torch"):
		gs.wake_blocks[t2]["attach"] = [g0.x, g0.y + 2, g0.z]; wc.append(t2)
	main.wake_voxels.sync_cells(wc)
	gs.day_time = 1250.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(1250.0)
	_look(Vector3(g0) + Vector3(1.5, 1.6, 4.8), 0.0, -0.15); await _wait(40)
	await _shot("08_dirt_strut_wall_torch_night.png")
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	_look(Vector3(g0) + Vector3(-1.5, 3.2, 4.0), -0.5, -0.4); await _wait(30)
	await _shot("09_dirt_grass_strut_day.png")
	print(con.execute("walltorch"))
	# моб без надписи
	print(con.execute("god")); print(con.execute("spawn enemy1 1")); await _wait(30)
	for e in get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.global_position = sp + Vector3(0, 0.1, -5)
		break
	_look(sp + Vector3(0, 0.3, 0), 0.0, -0.05); await _wait(20)
	await _shot("10_mob_no_label.png")
	# крафт без хвостов
	var craft = get_first_node_in_group("craft_menu")
	if craft:
		craft.open_workbench(); await _wait(10)
		await _shot("11_craft_names.png")
		craft.toggle(); await _wait(5)
	# босс-бар
	print(con.execute("time night")); print(con.execute("spawn mother 1")); await _wait(120)
	var m = get_first_node_in_group("block_mother")
	if m:
		_look(m.global_position + Vector3(0, 1.2, 7.0), 0.0, 0.0); await _wait(15)
		await _shot("12_boss_bar.png")
	print("WAKE chat ", gs.muted_chat.slice(maxi(0, gs.muted_chat.size() - 8)))
	await _wait(5)
	quit()
