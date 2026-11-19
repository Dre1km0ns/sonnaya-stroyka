extends SceneTree
## Кадры для отчёта v0.20 «Бета-путь». /tmp/v020shots/
const OUT := "/tmp/v020shots/"
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
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	await _shot("01_menu.png")
	mm._show("howto"); await _wait(10)
	await _shot("02_howto.png")
	mm._show("create"); mm._name_edit.text = "Кадры v0.20"; mm._seed_edit.text = "сон"
	await _wait(5)
	await _shot("03_create_world.png")
	mm._create_world()
	await _wait(150)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	print("START dream=", gs.is_dream(), " tutorial=", gs.tutorial_active)
	var p0: Vector3 = player.global_position
	_look(p0 + Vector3(0, 2, 0), 0.4, -0.35); await _wait(40)
	await _shot("04_start_in_dream_step1.png")
	_look(p0 + Vector3(0, 3, 9), 0.0, -0.45); await _wait(6)
	var base := Vector3i(floori(p0.x) - 3, floori(p0.y) + 1, floori(p0.z) - 2)
	await _press("hotbar_9")
	for i in range(6): main.build._place_at(base + Vector3i(i, 0, 0))
	gs.dream_material = "drift"
	gs.frame_mark(base + Vector3i(0, 1, -3)); gs.frame_mark(base + Vector3i(5, 2, -3))
	await _press("dream_fill")
	await _wait(20)
	await _shot("05_tutorial_step4_trial.png")
	gs.frame_mark(base + Vector3i(-1, 0, -4)); gs.frame_mark(base + Vector3i(6, 2, 1))
	await _press("dream_trial")
	await _wait(45)
	await _shot("06_tutorial_trial_running.png")
	var kb = load("res://scripts/keybind_menu.gd").new()
	if main.has_node("HUD"): main.get_node("HUD").add_child(kb)
	else: main.add_child(kb)
	await _wait(5)
	var sc: ScrollContainer = null
	for n in kb.find_children("*", "ScrollContainer", true, false): sc = n
	var hdr: Control = kb.find_child("Section_dream_palette", true, false)
	await _wait(3)
	if sc and hdr: sc.scroll_vertical = int(hdr.position.y) - 4
	await _wait(5)
	await _shot("07_keybinds_dream_section.png")
	kb.queue_free(); await _wait(3)
	# закончить обучение: верстак, якорь, пробуждение
	var wb := -1
	for i in range(9):
		if typeof(gs.inv_dream[i]) == TYPE_DICTIONARY and str(gs.inv_dream[i].get("id", "")) == "workbench": wb = i
	if wb >= 0: await _press("hotbar_%d" % (wb + 1))
	var wcell := base + Vector3i(2, 0, 3)
	main.build._place_at(wcell)
	await _press("hotbar_9")
	gs.select_anchor(gs.AnchorType.WEDGE)
	for i in range(200):
		if gs.anchor_preview(wcell).ready: break
		await process_frame
	print("ANCHOR ", gs.try_place_anchor(wcell))
	await _wait(10)
	_look(Vector3(wcell.x + 0.5, wcell.y + 3.0, wcell.z + 6.0), 0.0, -0.4)
	await _wait(10)
	await _shot("08_anchor_on_workbench.png")
	main.switcher.show_result_ui = false
	main.switcher.wake_up()
	await _wait(90)
	_look(Vector3(wcell.x + 0.5, wcell.y + 2.5, wcell.z + 6.0), 0.0, -0.3)
	await _wait(40)
	print("WAKE dream=", gs.is_dream(), " wb=", gs.wake_kind_count("workbench"), " tutorial_done=", gs.milestones.has("tutorial"))
	await _shot("09_wake_workbench_tutorial_done.png")
	print("DONE")
	quit()
