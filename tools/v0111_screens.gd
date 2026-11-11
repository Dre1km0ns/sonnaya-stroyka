extends SceneTree
## v0.11.1: самопроверка кадров (меч3, факел, батарейка, инвентарь, пластины Матери). Пишет в /tmp, в отчёт не входит.
## xvfb-run -a -s '-screen 0 1280x720x24' godot --path . --rendering-method gl_compatibility --script res://tools/v0111_screens.gd
const OUT := "/tmp/v0111shots/"

func _init() -> void: call_deferred("_go")

func _wait(n: int) -> void:
	for i in range(n): await process_frame

func _shot(name: String) -> void:
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT + name)
	print("SHOT ", name)

func _look(player: Node3D, pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = root.get_node("GameState")
	gs.begin_world("shots0111", "", "6767676767", gs.DEV_SEED, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	var main = current_scene
	var con = main.get_tree().get_first_node_in_group("dev_console")
	con.execute("time day")
	con.execute("god")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	con.execute("fill air -3 0 2 8 6 14")
	_look(player, Vector3(2.5, 0.05, 10.5), 0.0, -0.15)
	for id in ["sword3", "torch"]:
		main._v7_select(id)
		main.build._update_hand_tools()
		await _wait(10)
		await _shot("a_%s.png" % id)
	# Поставленный факел ночью.
	con.execute("time night")
	var gy: int = int(main.wake_chunks.height_at(2, 7)) + 1
	var tc := Vector3i(2, gy, 7)
	gs.place_wake_block(tc, "torch")
	main.wake_voxels.add_block(tc, gs.wake_blocks[tc])
	if main.wake_voxels.has_method("flush_dirty"): main.wake_voxels.flush_dirty()
	main._v7_select("")
	main.build._update_hand_tools()
	_look(player, Vector3(2.5, gy + 0.05, 9.0), 0.0, -0.35)
	await _wait(20)
	await _shot("b_torch_placed.png")
	con.execute("time day")
	# Батарейка: 62 HP.
	gs.player_hp = 62
	gs.player_hp_changed.emit(62, gs.PLAYER_MAX_HP)
	await _wait(10)
	await _shot("c_battery.png")
	# Инвентарь.
	var hud = main.get_node("HUD")
	hud.inventory.open()
	await create_timer(0.4).timeout
	await _shot("d_inventory.png")
	hud.inventory.toggle()
	await _wait(5)
	# Мать: пластины, одна открыта.
	var BM: GDScript = load("res://scripts/block_mother.gd")
	var mom = BM.spawn_near(main.get_node("WakeWorld"), Vector3i(0, 0, 0))
	await create_timer(0.3).timeout
	if mom:
		mom.frozen = true if "frozen" in mom else false
		mom.global_position = Vector3(-1.5, float(main.wake_chunks.height_at(-2, 4)) + 0.15, 4.0)
		mom._enter(mom.S.IDLE)
		mom._open_plate()
		mom.set_physics_process(false)
		_look(player, Vector3(-1.5, mom.global_position.y + 0.05, 9.5), 0.0, -0.08)
		await _wait(15)
		await _shot("e_mother_plate_open.png")
		mom._break_plate(mom.open_plate)
		await _wait(10)
		await _shot("f_mother_core.png")
		_look(player, Vector3(4.0, mom.global_position.y + 0.05, 1.0), 2.1, -0.08)
		await _wait(10)
		await _shot("g_mother_side.png")
	quit(0)
