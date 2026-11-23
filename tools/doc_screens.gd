extends SceneTree
## «Всё про всё»: кадры UI и мобов. DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/doc_screens.gd
const OUT := "/workspace/doc/shots/ui/"
var gs; var main; var player; var con
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("SHOT ", name)
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch
func _mob(id: String, group: String, dist: float, h: float) -> void:
	con.execute("kill all"); await _wait(5)
	print(con.execute("spawn %s 1" % id)); await _wait(30)
	var arr := get_nodes_in_group(group)
	if arr.is_empty(): print("NO MOB ", id); return
	var m: Node3D = arr[arr.size() - 1]
	m.set_physics_process(false); m.set_process(false)
	var mp := m.global_position
	_look(mp + Vector3(0, h, dist), 0.0, -0.12); await _wait(15)
	await _shot("mob_" + id)
func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	await _shot("menu_main")
	mm._show("howto"); await _wait(5); await _shot("menu_howto")
	mm._show("worlds"); await _wait(5); await _shot("menu_worlds")
	mm._show("create"); mm._name_edit.text = "Всё про всё"; mm._seed_edit.text = "doc"; await _wait(5); await _shot("menu_create")
	mm._create_world()
	await _wait(3); await _shot("loading")
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player")
	await _shot("dream_start_tutorial")
	player.set_physics_process(false)
	var p0: Vector3 = player.global_position
	_look(p0 + Vector3(0, 1, 0), 0.4, -0.2); await _wait(20)
	await _shot("dream_hud")
	var inv = get_first_node_in_group("inventory_ui")
	if inv: inv.open(); await _wait(8); await _shot("dream_inventory"); inv.toggle(); await _wait(5)
	var craft = get_first_node_in_group("craft_menu")
	if craft: craft.toggle(); await _wait(8); await _shot("dream_craft"); craft.toggle(); await _wait(5)
	gs.skip_tutorial()
	main.switcher.wake_up(true); await _wait(60)
	await _shot("wake_transfer_result")
	var ui = get_first_node_in_group("transfer_result_ui")
	if ui and ui.panel.visible: ui.close()
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	_look(gs.spawn_point + Vector3(0, 0.2, 0), 0.6, -0.1); await _wait(40)
	await _shot("wake_hud")
	if inv: inv.open(); await _wait(8); await _shot("wake_inventory"); inv.toggle(); await _wait(5)
	if craft: craft.open_workbench(); await _wait(8); await _shot("wake_workbench"); craft.toggle(); await _wait(5)
	var pm = main.get_node_or_null("PauseMenu")
	if pm:
		pm.open(); await _wait(5); await _shot("pause")
		pm._open_settings(); await _wait(8); await _shot("settings")
		var sm = pm.get("_settings")
		if sm and sm.has_method("_open_keybinds"): sm._open_keybinds(); await _wait(8); await _shot("keybinds")
		if sm: sm.queue_free()
		pm.resume(); await _wait(5)
	gs.dev_mode = true; gs.world_seed = gs.DEV_SEED
	con = get_first_node_in_group("dev_console")
	print(con.execute("god"))
	con.open(); await _wait(3)
	con._print(con.execute("help"))
	await _wait(5); await _shot("console")
	con.close()
	await _wait(5)
	for id in ["seam","elite","enemy1","enemy2","enemy3","enemy4"]:
		await _mob(id, "enemy", 3.2, 0.6)
	print(con.execute("kill all"))
	gs.set_hint("Пример сообщения чата")
	print(con.execute("time night")); await _wait(30)
	_look(gs.spawn_point + Vector3(0, 0.2, 0), 0.6, -0.1); await _wait(20)
	await _shot("wake_night")
	quit()
