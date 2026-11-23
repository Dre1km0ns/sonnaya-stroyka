extends SceneTree
## Кадры v0.24: кирка 90°, луки, руда, Бургер (обе фазы), меню сложности, экран победы.
## DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v024_screens.gd -- --out=/workspace/shots/v024
var OUT := "/workspace/shots/v024/"
var gs; var main; var player; var build
var only := ""
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", name)
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch
func _sel(i: int) -> void:
	gs.select_item_slot(i); build._update_hand_tools(); await _wait(12)
func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
		if a.begins_with("--only="): only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = false
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	mm._show("create"); mm._name_edit.text = "Кадры v0.24"; mm._seed_edit.text = "6767676767"
	mm._difficulty.select(1); mm._update_diff_info()
	await _wait(10)
	await _shot("01_menu_expert.png")
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player"); build = main.build
	gs.skip_tutorial()
	if gs.is_dream():
		main.switcher.wake_up(true); await _wait(60)
		var ui = get_first_node_in_group("transfer_result_ui")
		if ui and ui.panel.visible: ui.close()
	print("DIFF ", gs.difficulty)
	gs.dev_mode = false
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	player.set_physics_process(false)
	for i in range(gs.ITEM_SLOT_COUNT): gs.set_slot(i, {})
	gs.set_slot(0, {"id":"pickaxe2","name":"Каменная кирка","count":1})
	gs.set_slot(1, {"id":"pickaxe3","name":"Металлическая кирка","count":1})
	gs.set_slot(2, {"id":"bow","name":"Деревянный лук","count":1})
	gs.set_slot(3, {"id":"bow2","name":"Металлический лук","count":1})
	gs.set_slot(4, {"id":"metal_sword","name":"Металлический меч","count":1})
	gs.set_slot(5, {"id":"arrow","name":"Стрела","count":30})
	gs.set_slot(6, {"id":"stone","name":"Камень","count":32})
	gs.set_slot(7, {"id":"speed_potion","name":"Зелье скорости","count":2})
	gs.set_slot(8, {"id":"burger_summoner","name":"Призывалка","count":1})
	var sp: Vector3 = gs.spawn_point
	var at := sp + Vector3(4, 0.2, 6)
	_look(at, 0.4, -0.25); await _wait(40)
	# руда: стенка из металлической руды перед игроком
	var base := Vector3i(int(floor(at.x)) - 1, int(floor(at.y)), int(floor(at.z)) - 4)
	for x in range(3):
		for y in range(3):
			gs.place_wake_block(base + Vector3i(x, y, 0), "metal_ore" if (x + y) % 2 == 0 else "stone")
	_look(at, 0.0, -0.05); await _wait(30)
	await _sel(0); await _shot("02_pickaxe2_idle_ore.png")
	Engine.time_scale = 0.2; build._play_tool_swing(); await _wait(5); await _shot("03_pickaxe_swing.png"); Engine.time_scale = 1.0; await _wait(30)
	await _sel(1); await _shot("04_pickaxe3_idle.png")
	await _sel(6); Engine.time_scale = 0.2; build._place_cooldown = 0.0; build.swing_air(); await _wait(4); await _shot("05_block_swing.png"); Engine.time_scale = 1.0; await _wait(30)
	_look(at, PI, -0.05); await _wait(10)
	await _sel(2); await _shot("06_bow_idle.png")
	Input.action_press("attack_break"); await _wait(70); await _shot("07_bow_drawn.png")
	Input.action_release("attack_break"); await _wait(3); await _shot("08_arrow_flight.png")
	await _sel(3); Input.action_press("attack_break"); await _wait(70); await _shot("08b_bow2_drawn.png")
	Input.action_release("attack_break"); await _wait(20)
	if only == "bow": quit(); return
	await _sel(4); await _shot("09_metal_sword.png")
	# Бургер
	var B = load("res://scripts/boss_burger.gd")
	gs.god_mode = true
	var boss = B.spawn_at(main.wake_world, at + Vector3(0, 0, 12))
	await _wait(150)
	boss.frozen = true
	boss.global_position = at + Vector3(0, 5.5, 11)
	_look(at, PI, 0.3); await _wait(20)
	await _shot("10_burger_phase1.png")
	boss._start_laser(player.global_position); boss._update_laser_aim(false); await _wait(10); await _shot("11_burger_laser.png")
	boss._clear_lasers(); boss._enter(boss.S.HOVER)
	boss.take_damage(99999); await _wait(5)
	boss._drop_anton(); boss.global_position = at + Vector3(0, 0, 7)
	for i in 30:
		boss.global_position.y = boss._ground_y(boss.global_position) + 0.1; await process_frame
	boss.look_at(Vector3(at.x, boss.global_position.y, at.z), Vector3.UP, true)
	_look(at, PI, 0.1); await _wait(10)
	await _shot("12_anton_phase2.png")
	boss._spawn_clowns(2); await _wait(30); await _shot("13_anton_clowns.png")
	boss.queue_free()
	for c in get_nodes_in_group("burger_clown"): c.queue_free()
	await _wait(10)
	var vs = get_first_node_in_group("victory_screen")
	vs.open(); await _wait(90); await _shot("14_victory.png")
	vs.close()
	quit()
