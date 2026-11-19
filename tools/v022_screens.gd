extends SceneTree
## Кадры v0.22. DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v022_screens.gd -- --out=/workspace/shots/v022
var OUT := "/workspace/shots/v022/"
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
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
		if a.begins_with("--only="): only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	mm._show("create"); mm._name_edit.text = "Кадры v0.22"; mm._seed_edit.text = "сон22"
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player")
	gs.skip_tutorial()
	player.set_physics_process(false)
	var p0: Vector3 = player.global_position
	# Сон: хотбар, слот 1 — палитра
	gs.select_item_slot(0)
	_look(p0 + Vector3(0, 2, 0), 0.4, -0.25); await _wait(30)
	await _shot("01_dream_hotbar_arm.png")
	main.build._arms("place"); await _wait(6)
	await _shot("02_dream_arm_place.png")
	# Явь
	main.switcher.wake_up(true); await _wait(60)
	var ui = get_first_node_in_group("transfer_result_ui")
	if ui and ui.panel.visible: ui.close()
	await _wait(10)
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	var sp: Vector3 = gs.spawn_point
	_look(sp + Vector3(0, 0.2, 0), 0.6, -0.1); await _wait(40)
	await _shot("03_wake_camp_no_sign_empty_hand.png")
	gs.dev_mode = true
	gs.add_item("sword2", "Меч", 1)
	for i in range(9):
		if str(gs.item_slots[i].get("id", "")) == "sword2": gs.select_item_slot(i)
	await _wait(10)
	await _shot("04_wake_sword_hold.png")
	main.build._try_sword(); await _wait(4)
	await _shot("05_wake_sword_attack.png")
	# кровать без окна
	var bed: Node3D = main.get_node_or_null("WakeWorld/Bed")
	if bed:
		_look(bed.global_position + Vector3(0, 0.2, 2.2), 0.0, -0.45); await _wait(30)
		await _shot("06_bed_no_prompt.png")
	# крафт-меню (верстак)
	var craft = get_first_node_in_group("craft_menu")
	if craft:
		craft.open_workbench(); await _wait(10)
		await _shot("07_craft_menu_no_brackets.png")
		craft.toggle(); await _wait(5)
	gs.dev_mode = true; gs.world_seed = gs.DEV_SEED
	var con = get_first_node_in_group("dev_console")
	print(con.execute("god")); print(con.execute("time night"))
	var sp2: Vector3 = gs.spawn_point + Vector3(6, 0, 6)
	print(con.execute("spawn mother 1")); await _wait(120)
	var m = get_first_node_in_group("block_mother")
	if m:
		_look(m.global_position + Vector3(0, 1.2, 7.0), 0.0, 0.0); await _wait(15)
		await _shot("08_mother_v011.png")
		m.queue_free(); await _wait(10)
	print(con.execute("spawn anaconda 1")); await _wait(60)
	var ana = get_first_node_in_group("anaconda")
	if ana:
		_look(ana._head.global_position + Vector3(0, 3.0, 9.0), 0.0, -0.2); await _wait(20)
		await _shot("09_anaconda_v011.png")
	print(con.execute("aggro")); print(con.execute("economy")); print(con.execute("dayspawn")); print(con.execute("timeskip"))
	await _wait(5)
	quit()
