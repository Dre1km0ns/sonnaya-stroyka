extends SceneTree
## Кадры для отчёта v0.18 «Живой Сон». Пишет в /tmp/v018shots/.
const OUT := "/tmp/v018shots/"
var gs; var main; var player
var B: Vector3i

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
	DirAccess.make_dir_recursive_absolute(OUT)
	gs = root.get_node("GameState")
	gs.begin_world("shots018", "", "1808", 1808, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	for dc in get_nodes_in_group("day_cycle"): dc.set_time(10.0 * 60.0)
	gs.tutorial_enabled = false
	gs.add_item_count("stone", 3); gs.add_item_count("planks", 3)
	var sp: Vector3 = gs.spawn_point
	var sx := int(floor(sp.x)) - 6; var sz := int(floor(sp.z)) - 18
	var top := -999
	for x in range(-1, 16):
		for z in range(-1, 6):
			top = maxi(top, int(main.dream_chunks.height_at(sx + x, sz + z)))
			top = maxi(top, int(main.wake_chunks.height_at(sx + x, sz + z)))
	B = Vector3i(sx, top + 2, sz)
	print("BASE ", B)
	# Постройка: пол из камня, стена — левая половина дрейф, правая — доски; копия уже стоит в Яви.
	var cells := {}
	for x in range(14):
		for z in range(4): cells[B + Vector3i(x, 0, z)] = "stone"
		for y in range(1, 5): cells[B + Vector3i(x, y, 0)] = "drift" if x < 7 else "planks"
	for c in cells:
		gs.dream_blocks[c] = {"kind": cells[c], "anchored": false, "mutant": false}
		gs.wake_blocks[c] = {"kind": cells[c]}
	gs.dream_blocks[B + Vector3i(12, 1, 2)] = {"kind": "lumen", "anchored": false, "mutant": false}   # свет защищает правый край
	gs.placed_cells_changed.emit(true, cells.keys()); gs.placed_cells_changed.emit(false, cells.keys())
	# Ночью чудовища ломают материализованное: 3 дыры в дрейфе, 1 в досках у светоблока.
	var holes := [B + Vector3i(2, 1, 0), B + Vector3i(4, 2, 0), B + Vector3i(5, 1, 0), B + Vector3i(11, 1, 0)]
	for h in holes: gs.destroy_wake_structure(h)
	gs.placed_cells_changed.emit(false, holes)
	print("CRACKS ", gs.dream_cracks.size())
	var eye := Vector3(B.x + 7.0, B.y + 3.5, B.z + 13.0)
	_look(eye, 0.0, -0.18)
	await _wait(50)
	await _shot("01_wake_damage.png")
	main.switcher.enter_dream()
	gs.clarity = 60.0
	await _wait(30)
	_look(eye, 0.0, -0.18)
	await _wait(30)
	print("CRACK NODE shown=", get_first_node_in_group("dream_cracks").shown)
	await _shot("02_dream_cracks.png")
	var nm: Dictionary = gs.nightmare_tick()
	print("NIGHTMARE ", nm)
	await _wait(30)
	await _shot("03_after_nightmare.png")
	# Просьба Сна: в Яви есть 8 брёвен → J во Сне.
	gs.inv_wake[7] = {"id": "log", "name": "Бревно", "count": 8}
	gs.ensure_request(); gs.objective_changed.emit()
	await _wait(10)
	await _shot("04_request_panel.png")
	await _press("dream_offer")
	print("OFFER requests_done=", gs.requests_done, " new=", gs.dream_request)
	await _wait(10)
	await _shot("05_request_done.png")
	# Сады Сна: Мать → Каменный сад, Анаконда → Сад света (небо Сна меняется).
	main.switcher.show_result_ui = false
	main.switcher.wake_up(); await _wait(5)
	gs.on_mother_killed()
	main.switcher.enter_dream(); await _wait(20)
	player.set_physics_process(false)
	_look(eye, 0.0, -0.18); await _wait(20)
	await _shot("06_stone_garden.png")
	main.switcher.wake_up(); await _wait(5)
	gs.on_anaconda_killed()
	main.switcher.enter_dream(); await _wait(20)
	player.set_physics_process(false)
	_look(eye, 0.0, -0.18); await _wait(20)
	await _shot("07_light_garden.png")
	print("ZONES ", gs.dream_zones, " palette=", gs.dream_palette().size())
	print("DONE")
	quit(0)
