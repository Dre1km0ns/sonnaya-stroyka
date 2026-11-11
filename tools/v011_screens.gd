extends SceneTree
## v0.11: реальные кадры игры (xvfb-run, gl_compatibility). Сохраняет PNG без переворота.
## xvfb-run -a -s '-screen 0 1280x720x24' godot --path . --rendering-method gl_compatibility --script res://tools/v011_screens.gd
const OUT := "/workspace/sonnaya-stroyka-v011-report/screens/"

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
	gs.begin_world("shots011", "", "6767676767", gs.DEV_SEED, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	var main = current_scene
	var con = main.get_tree().get_first_node_in_group("dev_console")
	con.execute("time day")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	# 1) Старт: разрушенный лагерь + панель целей + H-статус.
	var top: int = int(main.wake_chunks.height_at(0, 2))
	_look(player, Vector3(0.5, top + 1.05, 6.5), 0.0, -0.12)
	await _wait(30)
	await _shot("v011_start_camp.png")
	print("OBJ ", gs.current_objective())
	# 2) Инструменты в мире — та же постановка, что и v010_before_*.
	con.execute("god")
	con.execute("fill air -3 0 2 8 6 14")
	_look(player, Vector3(2.5, 0.05, 10.5), 0.0, -0.15)
	for id in ["pickaxe", "pickaxe2", "sword", "sword2", "sword3", "torch"]:
		main._v7_select(id)
		main.build._update_hand_tools()
		await _wait(10)
		await _shot("v011_after_%s.png" % id)
	# удар мечом в середине анимации
	main._v7_select("sword2")
	main.build._update_hand_tools()
	main.build._play_tool_swing()
	print("SWING started=", main.build.viewmodel.swinging, " count=", main.build.viewmodel.swing_count)
	await create_timer(0.17).timeout
	print("SWING mid rot=", main.build.viewmodel.swing_pivot.rotation_degrees)
	main.build.viewmodel._tween.pause()  # заморозить середину удара на время захвата кадра
	await _shot("v011_after_sword2_swing.png")
	main.build.viewmodel._tween.play()
	await create_timer(0.5).timeout
	# 3) Сундук: закрыт → открыт (крышка + UI).
	main._v7_select("")
	main.build._update_hand_tools()
	var gy: int = int(main.wake_chunks.height_at(2, 8)) + 1
	var cc := Vector3i(2, gy, 8)
	print("CHEST place=", gs.place_wake_block(cc, "chest"), " at ", cc)
	main.wake_voxels.add_block(cc, gs.wake_blocks[cc])
	if main.wake_voxels.has_method("flush_dirty"): main.wake_voxels.flush_dirty()
	var slots: Array = gs.storage_slots(cc, false, false)
	slots[0] = {"id": "log", "count": 12}
	slots[1] = {"id": "stone", "count": 30}
	await _wait(10)
	_look(player, Vector3(2.5, gy + 0.05, 10.4), 0.0, -0.45)
	await _wait(10)
	await _shot("v011_chest_closed.png")
	var st = main.get_tree().get_first_node_in_group("storage_ui")
	if st:
		st.open(cc, false)
	await create_timer(0.5).timeout
	await _shot("v011_chest_open_ui.png")
	if st: st.close()
	await create_timer(0.1).timeout
	# крышка открыта без UI (вид сбоку)
	main.wake_voxels.set_chest_open(cc, true, false)
	_look(player, Vector3(4.2, gy + 0.05, 10.0), 0.6, -0.5)
	await _wait(10)
	await _shot("v011_chest_lid_open.png")
	main.wake_voxels.set_chest_open(cc, false, false)
	# 4) Низкое HP: H-подсказка выбирает зелье.
	gs.add_item("heal1", "Зелье I", 2)
	gs.add_item("heal2", "Зелье II", 1)
	gs.player_hp = 48
	gs.player_hp_changed.emit(48, gs.PLAYER_MAX_HP)
	_look(player, Vector3(2.5, 0.05, 10.5), 0.0, -0.15)
	await _wait(10)
	await _shot("v011_hud_heal.png")
	print("HEAL ", gs.heal_status_text())
	quit(0)
