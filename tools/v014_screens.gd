extends SceneTree
## Кадры для отчёта v0.14. Пишет в /tmp/v014shots/.
## xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v014_screens.gd
const OUT := "/tmp/v014shots/"

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
	gs.begin_world("shots014", "", "6767676767", gs.DEV_SEED, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	var main = current_scene
	var con = main.get_tree().get_first_node_in_group("dev_console")
	con.execute("time day")
	con.execute("god")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	con.execute("fill air -3 0 2 8 6 14")
	# 1. Постройка из обычных блоков — меш чанка собран новым emit_box/маской граней.
	var gy: int = int(main.wake_chunks.height_at(2, 6)) + 1
	var kinds := ["planks", "stone", "bricks", "log", "dirt"]
	var t0 := Time.get_ticks_usec()
	for x in range(-2, 7):
		for y in range(0, 4):
			var c := Vector3i(x, gy + y, 4)
			gs.place_wake_block(c, kinds[(x + y + 10) % kinds.size()])
			main.wake_voxels.add_block(c, gs.wake_blocks[c])
	for z in range(4, 8):
		for y in range(0, 2):
			var c2 := Vector3i(-2, gy + y, z)
			gs.place_wake_block(c2, "planks")
			main.wake_voxels.add_block(c2, gs.wake_blocks[c2])
	main.wake_voxels.flush_dirty()
	print("BUILD flush %.2f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	_look(player, Vector3(2.5, gy + 0.05, 11.0), 0.25, -0.12)
	await _wait(14)
	await _shot("01_build_chunk_mesh.png")
	# 2. Анаконда в перекрёстном огне ночью — пульс сегментов от нового _update_seg_light.
	con.execute("time night")
	var tz := 8
	var ty: int = int(main.wake_chunks.height_at(2, tz)) + 1
	for tc in [Vector3i(0, ty, tz), Vector3i(5, ty, tz), Vector3i(2, ty, tz + 3)]:
		gs.place_wake_block(tc, "torch")
		main.wake_voxels.add_block(tc, gs.wake_blocks[tc])
	main.wake_voxels.flush_dirty()
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var ana = AS.spawn_at(main.get_node("WakeWorld"), Vector3(2.5, 0, tz + 1.0), "shot")
	if ana:
		ana.frozen = true   # иначе на рассвете она честно уходит и освобождается — дальше обращаться нельзя
	await _wait(8)
	if is_instance_valid(ana):
		ana._emerge = Vector3(2.5, float(ty), tz + 1.0)
		ana._enter(ana.S.REST)
		if ana._head:
			ana._head.global_position = Vector3(2.5, ty + 0.8, tz + 1.0)
		for i in range(ana._segs.size()):
			ana._segs[i].global_position = Vector3(2.5 + 0.6 * sin(i * 0.7), ty + 0.5, tz + 1.0 + 0.9 * (i + 1) * 0.4)
		ana.set_physics_process(false)
		ana._t = 0.0
		ana._update_seg_light()
		print("CROSSFIRE lvl=", ana.crossfire_level(), " dps=", ana.light_dps())
		_look(player, Vector3(2.5, ty + 0.4, tz + 7.5), 0.0, -0.22)
		await _wait(15)
		await _shot("02_anaconda_crossfire.png")
		if is_instance_valid(ana):
			ana.queue_free()
		await _wait(5)
	con.execute("time day")
	# 3. HUD после удара — полоса перерисовывается только пока анимирует.
	_look(player, Vector3(2.5, gy + 0.05, 11.0), 0.25, -0.12)
	var hud = main.get_node("HUD")
	var bat = hud.find_children("*", "", true, false).filter(func(n): return n.get_script() == load("res://scripts/health_battery.gd"))
	gs.player_hp = 100
	gs.player_hp_changed.emit(100, gs.PLAYER_MAX_HP)
	await _wait(60)
	var d0: int = bat[0].draw_count if bat.size() > 0 else -1
	await _wait(60)
	var d1: int = bat[0].draw_count if bat.size() > 0 else -1
	gs.player_hp = 55
	gs.player_hp_changed.emit(55, gs.PLAYER_MAX_HP)
	await _wait(8)
	await _shot("03_hud_hit.png")
	await _wait(120)
	var d2: int = bat[0].draw_count if bat.size() > 0 else -1
	print("HUDDRAWS idle60=%d hit+128f=%d" % [d1 - d0, d2 - d1])
	print("SHOTS DONE")
	quit(0)
