extends SceneTree
## Кадры для отчёта v0.12. Пишет в /tmp/v012shots/.
## xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v012_screens.gd
const OUT := "/tmp/v012shots/"

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
	gs.begin_world("shots012", "", "6767676767", gs.DEV_SEED, false)
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
	# Полное HP, подпись «100 / 100» слева снизу.
	gs.player_hp = gs.PLAYER_MAX_HP
	gs.player_hp_changed.emit(gs.player_hp, gs.PLAYER_MAX_HP)
	main._v7_select("sword3")
	main.build._update_hand_tools()
	await _wait(12)
	await _shot("01_hud_full.png")
	# Средний урон — след и число.
	gs.player_hp = 62
	gs.player_hp_changed.emit(62, gs.PLAYER_MAX_HP)
	await _wait(8)
	await _shot("02_hud_mid.png")
	# Критическое HP.
	gs.player_hp = 18
	gs.player_hp_changed.emit(18, gs.PLAYER_MAX_HP)
	await _wait(8)
	await _shot("03_hud_crit.png")
	# Лечение: вспышка вверх к 58.
	gs.player_hp = 58
	gs.player_hp_changed.emit(58, gs.PLAYER_MAX_HP)
	await _wait(6)
	await _shot("04_hud_heal.png")
	gs.player_hp = gs.PLAYER_MAX_HP
	gs.player_hp_changed.emit(gs.player_hp, gs.PLAYER_MAX_HP)
	# Факел в руке и поставленный ночью.
	main._v7_select("torch")
	main.build._update_hand_tools()
	await _wait(10)
	await _shot("05_torch_held.png")
	con.execute("time night")
	var gy: int = int(main.wake_chunks.height_at(2, 7)) + 1
	var t1 := Vector3i(2, gy, 7)
	var t2 := Vector3i(4, gy, 5)
	var t3 := Vector3i(0, gy, 5)
	for tc in [t1, t2, t3]:
		gs.place_wake_block(tc, "torch")
		main.wake_voxels.add_block(tc, gs.wake_blocks[tc])
	if main.wake_voxels.has_method("flush_dirty"):
		main.wake_voxels.flush_dirty()
	main._v7_select("")
	main.build._update_hand_tools()
	_look(player, Vector3(2.5, gy + 0.05, 9.0), 0.0, -0.35)
	await _wait(20)
	await _shot("06_torches_night.png")
	# Анаконда в световой зоне (заморожена на поверхности).
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var ana = AS.spawn_at(main.get_node("WakeWorld"), Vector3(2.5, 0, 6.0), "shot")
	await _wait(8)
	if ana:
		ana._emerge = Vector3(2.5, float(gy), 6.0)
		ana._enter(ana.S.REST)
		if ana._head:
			ana._head.global_position = Vector3(2.5, gy + 0.8, 6.0)
		ana.set_physics_process(false)
		_look(player, Vector3(2.5, gy + 0.1, 10.2), 0.0, -0.2)
		await _wait(15)
		await _shot("07_anaconda_rest.png")
		if is_instance_valid(ana):
			ana.queue_free()
		await _wait(5)
	con.execute("time day")
	# Инвентарь без текстовых подсказок.
	var hud = main.get_node("HUD")
	gs.player_hp = 80
	gs.player_hp_changed.emit(80, gs.PLAYER_MAX_HP)
	hud.inventory.open()
	await create_timer(0.4).timeout
	await _shot("08_inventory.png")
	hud.inventory.toggle()
	await _wait(5)
	# Мать: открытая пластина и ядро.
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
		await _shot("09_mother_plate.png")
		mom._break_plate(mom.open_plate)
		await _wait(10)
		await _shot("10_mother_core.png")
	print("SHOTS DONE")
	quit(0)
