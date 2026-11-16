extends SceneTree
## Кадры для отчёта v0.13. Пишет в /tmp/v013shots/game/.
## xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v013_screens.gd
const OUT := "/tmp/v013shots/game/"

func _init() -> void: call_deferred("_go")

func _wait(n: int) -> void:
	for i in range(n):
		await process_frame

func _shot(name: String) -> void:
	await process_frame
	await process_frame
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
	gs.begin_world("shots013", "", "6767676767", gs.DEV_SEED, false)
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
	# 1. Чешуйчатый меч в игре — рукоять в кулаке.
	main._v7_select("sword3")
	main.build._update_hand_tools()
	await _wait(14)
	await _shot("01_sword3_ingame.png")
	# 2–3. Факел: поставлен, затем снят ПКМ (счётчик вернулся).
	var gy: int = int(main.wake_chunks.height_at(2, 7)) + 1
	var tc := Vector3i(2, gy, 7)
	gs.place_wake_block(tc, "torch")
	main.wake_voxels.add_block(tc, gs.wake_blocks[tc])
	if main.wake_voxels.has_method("flush_dirty"):
		main.wake_voxels.flush_dirty()
	main._v7_select("torch")
	main.build._update_hand_tools()
	_look(player, Vector3(2.5, gy + 0.05, 9.0), 0.0, -0.45)
	await _wait(14)
	print("TORCHES before pickup ", gs.count_item("torch"))
	await _shot("02_torch_placed.png")
	var ok: bool = main.build._try_pick_up_torch()
	if main.wake_voxels.has_method("flush_dirty"):
		main.wake_voxels.flush_dirty()
	print("PICKUP ", ok, " torches after ", gs.count_item("torch"))
	await _wait(10)
	await _shot("03_torch_picked_up.png")
	main._v7_select("sword3")
	main.build._update_hand_tools()
	# 4–5. Мать: локальное свечение ядра, затем «захлопнулось» по капу окна.
	var BM: GDScript = load("res://scripts/block_mother.gd")
	var mom = BM.spawn_near(main.get_node("WakeWorld"), Vector3i(0, 0, 0))
	await create_timer(0.3).timeout
	if mom:
		mom.global_position = Vector3(-1.5, float(main.wake_chunks.height_at(-2, 4)) + 0.15, 4.0)
		mom._enter(mom.S.IDLE)
		mom._open_plate()
		mom.set_physics_process(false)
		_look(player, Vector3(-1.5, mom.global_position.y + 0.05, 9.5), 0.0, -0.08)
		mom._break_plate(mom.open_plate)
		await _wait(12)
		print("GLOW ", mom.glow_snapshot())
		await _shot("04_mother_core_local_glow.png")
		mom._seal_core()
		await _wait(12)
		print("SEALED glow ", mom.glow_snapshot())
		await _shot("05_mother_core_sealed.png")
	print("SHOTS DONE")
	quit(0)
