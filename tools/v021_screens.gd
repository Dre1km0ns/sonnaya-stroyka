extends SceneTree
## Кадры v0.21 (цикл 1). DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v021_screens.gd
var OUT := "/workspace/shots/v021c2/" # --out=<папка>
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
func _press(action: String) -> void:
	var e := InputEventAction.new(); e.action = action; e.pressed = true; Input.parse_input_event(e)
	await process_frame; await process_frame
	e = InputEventAction.new(); e.action = action; e.pressed = false; Input.parse_input_event(e)
	await process_frame
func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	await _shot("01_menu.png")
	mm._show("create"); mm._name_edit.text = "Кадры v0.21"; mm._seed_edit.text = "сон21"
	await _wait(5)
	mm._show_loading("Загрузка мира «Кадры v0.21»…")
	await _shot("01b_loading.png")
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	var p0: Vector3 = player.global_position
	_look(p0 + Vector3(0, 2, 0), 0.4, -0.12); await _wait(40)
	await _shot("02_dream_start_tutorial_only.png")
	_look(p0 + Vector3(0, 4, 0), 2.2, 0.35); await _wait(20)
	await _shot("03_dream_sky_islands.png")
	_look(p0 + Vector3(0, 6, 0), -1.0, 0.05); await _wait(20)
	await _shot("04_dream_horizon.png")
	_look(p0 + Vector3(6, 1.7, 6), 0.8, -0.25); await _wait(20)
	await _shot("04b_dream_ground_flora.png")
	# шаги: полёт, блоки
	gs.tutorial_event("fly")
	var base := Vector3i(floori(p0.x) - 2, floori(p0.y), floori(p0.z) - 4)
	for i in range(6): main.build._place_at(base + Vector3i(i, 0, 0))
	_look(p0 + Vector3(0, 3, 3), 0.0, -0.45); await _wait(15)
	await _shot("05_after_build_step_frame.png")
	for id in ["frame", "trial"]: gs.tutorial_early[id] = true
	gs.tutorial_event("frame")
	await _press("hotbar_5")
	var wcell := base + Vector3i(2, 1, 0)
	main.build._place_at(wcell)
	for i in range(120):
		if gs.anchor_preview(wcell).ready: break
		await process_frame
	_look(Vector3(wcell.x + 0.5, wcell.y + 1.6, wcell.z + 3.5), 0.0, -0.35); await _wait(20)
	print("STEP ", gs.tutorial_step_id())
	await _shot("06_anchor_step_compact_panel.png")
	_look(Vector3(wcell.x + 0.5, wcell.y + 3.0, wcell.z + 6.5), 2.6, 0.5); await _wait(20)
	await _shot("06b_anchor_step_no_target_hint.png")
	gs.skip_tutorial(); await _wait(10)
	await _press("hotbar_1")
	_look(Vector3(wcell.x + 0.5, wcell.y + 1.2, wcell.z + 2.5), 0.0, -0.4); await _wait(20)
	await _shot("07_after_tutorial_objectives_hints.png")
	# острова закреплены в мире: снизу и стоя на острове
	var sc = main.get_tree().get_first_node_in_group("dream_scenery")
	sc.update_islands(player.global_position)
	var near_isl: Node3D = null
	for isl in sc.islands.get_children():
		if isl == sc.landmark: continue
		if near_isl == null or isl.global_position.distance_to(player.global_position) < near_isl.global_position.distance_to(player.global_position): near_isl = isl
	if near_isl:
		var ip := near_isl.global_position
		var from := ip + Vector3(0, -ip.y + 3.0, 22.0)
		_look(from, 0.0, atan2(ip.y - from.y, 22.0)); await _wait(30)
		await _shot("07b_island_from_ground.png")
		gs.dev_mode = true; gs.world_seed = gs.DEV_SEED
		var con0 = main.get_tree().get_first_node_in_group("dev_console")
		print(con0.execute("dreamdecor island"))
		player.rotation.y = 2.4; player.get_node("CameraPivot").rotation.x = -0.35
		player.set_physics_process(true); await _wait(60); player.set_physics_process(false)
		print("ON ISLAND: player y=%.2f island top=%.2f" % [player.global_position.y, ip.y + 1.0])
		player.velocity = Vector3.ZERO
		await _shot("07c_standing_on_island.png")
	main.switcher.show_result_ui = false
	main.switcher.wake_up()
	await _wait(120)
	_look(Vector3(0.5, player.global_position.y + 1.0, 16.0), 0.0, -0.05); await _wait(40)
	await _shot("08_wake_camp_sign_far.png")
	_look(Vector3(0.5, player.global_position.y, -2.0), 0.0, 0.1); await _wait(20)
	await _shot("09_wake_camp_near.png")
	gs.dev_mode = true; gs.world_seed = gs.DEV_SEED
	var con = main.get_tree().get_first_node_in_group("dev_console")
	print(con.execute("god")); print(con.execute("time 21")); print(con.execute("spawn mother 1"))
	await _wait(120)
	var m = main.get_tree().get_first_node_in_group("block_mother")
	if m:
		var mp: Vector3 = m.global_position
		_look(mp + Vector3(0, 0.6, 2.4), 0.0, 0.15); await _wait(10)
		await _shot("10_mother_close_no_giant_bar.png")
		_look(mp + Vector3(0, 0.6, 7.0), 0.0, 0.05); await _wait(10)
		await _shot("11_mother_mid.png")
		main.get_tree().get_first_node_in_group("boss_camera").apply_fade(m, 0.55)
		await _shot("11b_mother_mid_fade55_test.png")
		main.get_tree().get_first_node_in_group("boss_camera").apply_fade(m, 0.0)
		print("SHELL r=", m.shell_radius())
		# честная проверка оболочки: физика игрока включена, игрок идёт прямо в Мать 2.5 с
		# детерминированно: Мать в обычной стойке (не «пересборка», где её коллизия честно выключена)
		m.set_physics_process(false); m.state = m.S.IDLE; m.collision_layer = 16; m._shell.collision_layer = 64
		m.global_position = mp
		_look(mp + Vector3(0, 0.2, 5.0), 0.0, 0.1)
		player.set_physics_process(true); player.flying = false
		player.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		for i in range(5):
			await _wait(30)
			print("walk t=%d pos=%s fly=%s vel=%s" % [i, player.global_position - mp, player.flying, player.velocity])
		Input.action_release("move_forward")
		var dd := Vector2(player.global_position.x - mp.x, player.global_position.z - mp.z).length()
		print("WALK-IN distance to Mother center = %.2f (shell %.2f + capsule 0.4; melee %.1f)" % [dd, m.shell_radius(), m.MELEE_RANGE])
		await _wait(90) # камера боя: прозрачность набирается плавно
		var bcam = main.get_tree().get_first_node_in_group("boss_camera")
		print("BOSSCAM: ", bcam.status_text())
		await _shot("12_walked_into_mother.png")
		bcam.enabled = false; await _wait(90)
		await _shot("12b_mother_bosscam_off.png")
		bcam.enabled = true
		# меч с этой дистанции достаёт?
		print(con.execute("give sword 1"))
		for i in range(gs.HOTBAR_SIZE):
			if str(gs.get_slot(i).get("id", "")) == "sword": gs.selected_slot = i
		main.build._try_sword()
		print("SWORD from walk-in distance: hits=%d" % main.build.last_sword_hits)
		player.set_physics_process(false)
	print(con.execute("kill all"))
	await _wait(10)
	root.get_node("GameSettings").safe_quit(0)
