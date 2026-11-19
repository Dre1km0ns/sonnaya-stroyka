extends SceneTree
## Кадры для отчёта v0.19 «Испытание Сна». /tmp/v019shots/
const OUT := "/tmp/v019shots/"
var gs; var main; var player; var view
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
func _house(o: Vector3i, kind: String, hole: bool) -> void:
	for x in range(11):
		for z in range(9):
			gs.dream_blocks[o + Vector3i(x, 0, z)] = {"kind": "planks", "anchored": false, "mutant": false}
			for y in range(1, 3):
				if (x == 0 or x == 10 or z == 0 or z == 8) and not (hole and x == 5 and z == 8):
					var k := kind
					if kind == "mixed": k = "drift" if (x >= 3 and x <= 4 and z == 8) else "stone"
					gs.dream_blocks[o + Vector3i(x, y, z)] = {"kind": k, "anchored": false, "mutant": false}
func _clear_house(o: Vector3i) -> void:
	for x in range(-3, 14):
		for z in range(-3, 12):
			for y in range(0, 4): gs.dream_blocks.erase(o + Vector3i(x, y, z))
func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	gs = root.get_node("GameState")
	gs.begin_world("shots019", "", "1919", 1919, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	gs.tutorial_enabled = false
	var sp: Vector3 = gs.spawn_point
	var sx := int(floor(sp.x)) - 5; var sz := int(floor(sp.z)) - 20
	var top := -999
	for x in range(-4, 15):
		for z in range(-4, 13): top = maxi(top, int(main.dream_chunks.height_at(sx + x, sz + z)))
	B = Vector3i(sx, top + 2, sz)
	main.switcher.enter_dream()
	view = get_first_node_in_group("dream_trial_view")
	await _wait(10)
	var eye := Vector3(B.x + 5.5, B.y + 11.0, B.z + 19.0)
	# 1) дом с дырой в задней... нет — в передней стене, рамка, M
	_house(B, "stone", true)
	gs.placed_cells_changed.emit(true, gs.dream_blocks.keys())
	gs.frame_mark(B); gs.frame_mark(B + Vector3i(10, 3, 8))
	_look(eye, 0.0, -0.55); await _wait(40)
	await _press("dream_trial")
	print("TRIAL1 held=", gs.last_trial.held, " grade=", gs.last_trial.grade, " breaches=", gs.last_trial.breaches)
	view.playing = false; view.show_tick(14)
	await _wait(5)
	await _shot("01_trial_hole_phantoms.png")
	view.show_tick(40); await _wait(3)
	await _shot("02_trial_hole_breach.png")
	# 2) дыра закрыта, но секция стены из дрейфа — прогрызают
	view.stop(); _clear_house(B); _house(B, "mixed", false)
	main.dream_voxels.sync_from_state()
	gs.frame_mark(B); gs.frame_mark(B + Vector3i(10, 3, 8))
	await _wait(10)
	await _press("dream_trial")
	print("TRIAL2 held=", gs.last_trial.held, " grade=", gs.last_trial.grade, " broken=", gs.last_trial.broken.size())
	view.playing = false; view.show_tick(gs.last_trial.timeline.size() - 1)
	await _wait(5)
	await _shot("03_trial_drift_gnawed.png")
	# 3) каменная стена + свет у двери: выдержала, оценка S
	view.stop(); _clear_house(B); _house(B, "stone", true)
	for p in [Vector3i(3, 1, 10), Vector3i(7, 1, 10), Vector3i(5, 1, 11)]: gs.dream_blocks[B + p] = {"kind": "lumen", "anchored": false, "mutant": false}
	main.dream_voxels.sync_from_state()
	gs.frame_mark(B); gs.frame_mark(B + Vector3i(10, 3, 8))
	await _wait(10)
	await _press("dream_trial")
	print("TRIAL3 held=", gs.last_trial.held, " grade=", gs.last_trial.grade, " burned=", gs.last_trial.burned)
	view.playing = false; view.show_tick(10)
	await _wait(5)
	await _shot("04_trial_light_holds.png")
	view.show_tick(gs.last_trial.timeline.size() - 1); await _wait(3)
	await _shot("05_trial_result_S.png")
	print("DONE")
	quit(0)
