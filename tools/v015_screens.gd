extends SceneTree
## Кадры для отчёта v0.15. Пишет в /tmp/v015shots/.
## xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v015_screens.gd
const OUT := "/tmp/v015shots/"

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
	gs.begin_world("shots015", "", "6767676767", gs.DEV_SEED, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	var main = current_scene
	var con = main.get_tree().get_first_node_in_group("dev_console")
	con.execute("time day")
	con.execute("god")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	con.execute("fill air -3 0 2 8 6 14")
	var hud = main.get_node("HUD")
	var cf = hud.combat_feedback
	# 1–2. Кольца радиуса факела: один поставлен, второй — призрак (жёлтый → зелёный при перекрытии).
	var gy: int = int(main.wake_chunks.height_at(2, 6)) + 1
	main._v7_select("torch")
	main.build._update_hand_tools()
	_look(player, Vector3(2.5, gy + 1.6, 12.0), 0.0, -0.62)
	await _wait(10)
	main.build.update_torch_rings()
	print("RINGS empty ", main.build.ring_state)
	await _shot("01_torch_ring_ghost.png")
	var tc := Vector3i(-3, int(main.wake_chunks.height_at(-3, 5)) + 1, 5)
	gs.place_wake_block(tc, "torch")
	main.wake_voxels.add_block(tc, gs.wake_blocks[tc])
	main.wake_voxels.flush_dirty()
	await _wait(6)
	main.build.update_torch_rings()
	print("RINGS overlap ", main.build.ring_state)
	await _shot("02_torch_ring_crossfire.png")
	main._v7_select("sword3")
	main.build._update_hand_tools()
	main.build.update_torch_rings()
	# 3–5. Хит-маркеры у прицела: ядро / отскок / ядро захлопнулось.
	_look(player, Vector3(2.5, gy + 0.05, 11.0), 0.0, -0.1)
	await _wait(6)
	# llvmpipe даёт единицы FPS: маркер 0.28 с успевает погаснуть до захвата кадра — замедляем время на кадр.
	for kind in ["core", "bounce", "sealed"]:
		Engine.time_scale = 0.05
		gs.hit_marker.emit(kind)
		await _wait(2)
		print("MARK ", cf.current_marker())
		await _shot("0%d_marker_%s.png" % [3 + ["core", "bounce", "sealed"].find(kind), kind])
		Engine.time_scale = 1.0
		await _wait(30)
	# 6. Дуга урона: удар справа-сзади.
	var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
	var src: Vector3 = cam.global_position + cam.global_transform.basis.x * 4.0 + cam.global_transform.basis.z * 2.0
	gs.hit_from(src)
	gs._iframes = 0.0
	con.execute("god")   # выкл — урон должен пройти
	var dealt: int = gs.damage_player(14, "тест кадра")
	con.execute("god")
	await _wait(3)
	print("ARC dealt=", dealt, " angle=", cf.last_arc_angle())
	await _shot("06_hurt_direction.png")
	gs.player_hp = 100
	gs.player_hp_changed.emit(100, 100)
	await _wait(80)
	# 7–8. Мать: метка замаха и полоса окна ядра.
	var BM: GDScript = load("res://scripts/block_mother.gd")
	var mom = BM.spawn_near(main.get_node("WakeWorld"), Vector3i(0, 0, 0))
	await create_timer(0.3).timeout
	if is_instance_valid(mom):
		mom.global_position = Vector3(-1.5, float(main.wake_chunks.height_at(-2, 2)) + 0.15, 2.0)
		mom.set_physics_process(false)
		# метка лежит под игроком (туда Мать и прыгнет) — смотрим вниз, как игрок, увидевший замах
		_look(player, Vector3(-1.0, gy + 0.05, 7.5), 0.0, -1.05)
		mom._enter(mom.S.WINDUP)
		mom._t = 0.3
		mom._update_pre_shadow(player)
		await _wait(12)
		print("PRESHADOW ", is_instance_valid(mom._pre_shadow))
		await _shot("07_mother_windup_marker.png")
		mom._enter(mom.S.IDLE)
		mom._open_plate()
		mom._break_plate(mom.open_plate)
		mom.receive_weapon_hit(24, "sword3")
		_look(player, Vector3(-1.5, mom.global_position.y + 0.05, 9.5), 0.0, -0.08)
		await _wait(12)
		print("COREWIN ", mom.core_window_left())
		await _shot("08_core_window_bar.png")
	print("SHOTS DONE")
	quit(0)
