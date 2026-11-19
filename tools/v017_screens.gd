extends SceneTree
## Кадры для отчёта v0.17 «Инструменты сновидца». Пишет в /tmp/v017shots/.
## Шаги нажимают настоящие действия ввода (L, B, N, O, Z, U, X) через узел DreamTools.
const OUT := "/tmp/v017shots/"
var gs; var main; var player; var tools
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
func _press(action: String, shift := false) -> void:
	if shift: Input.action_press("sprint")
	Input.action_press(action)
	await process_frame; await process_frame
	Input.action_release(action)
	if shift: Input.action_release("sprint")
	await process_frame

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	gs = root.get_node("GameState")
	gs.begin_world("shots017", "", "1707", 1707, false)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	tools = get_first_node_in_group("dream_tools")
	for dc in get_nodes_in_group("day_cycle"): dc.set_time(10.0 * 60.0)
	gs.tutorial_enabled = false
	gs.add_item_count("planks", 5); gs.add_item_count("stone", 5); gs.add_item_count("log", 5)
	var sp: Vector3 = gs.spawn_point
	var sx := int(floor(sp.x)) - 4; var sz := int(floor(sp.z)) - 20
	var top := -999
	for x in range(-1, 24):
		for z in range(-1, 12):
			top = maxi(top, int(main.dream_chunks.height_at(sx + x, sz + z)))
	B = Vector3i(sx, top + 2, sz)
	print("BASE ", B)
	main.switcher.enter_dream()
	gs.clarity = gs.dream_clarity_max()
	for i in range(gs.inv_dream.size()): gs.inv_dream[i] = {}
	gs.select_item_slot(0)
	await _wait(30)
	var eye := Vector3(B.x + 4.5, B.y + 7.0, B.z + 16.0)
	# 1) Рамка пола 9×1×7 + статус.
	gs.frame_mark(B); gs.frame_mark(B + Vector3i(8, 0, 6))
	gs.dream_material = "planks"
	_look(eye, 0.0, -0.38)
	await _wait(40)
	await _shot("01_frame.png")
	# 2) L — заливка (настоящее действие ввода).
	var n0: int = gs.dream_blocks.size()
	await _press("dream_fill")
	print("INPUT L fill=", gs.dream_blocks.size() - n0, " undo=", gs.undo_size())
	await _wait(30)
	await _shot("02_fill.png")
	# 3) X — зеркало (по прицелу), затем ставим плоскость точно в центр пола и строим половину стен.
	await _press("dream_mirror")
	print("INPUT X mirror_axis=", gs.mirror_axis)
	gs.mirror_axis = 1; gs.mirror_at = B + Vector3i(4, 1, 3)
	gs.dream_material = "stone"
	var placed := 0
	for y in range(1, 4):
		for z in range(0, 7):
			if z == 3 and y <= 2: continue  # окно-проём
			placed += gs.dream_tool_place(B + Vector3i(0, y, z), "stone").size()
		for x in range(1, 4):
			if not (x == 3 and y <= 2): placed += gs.dream_tool_place(B + Vector3i(x, y, 6), "stone").size()
			placed += gs.dream_tool_place(B + Vector3i(x, y, 0), "stone").size()
	for x in range(0, 5):
		for z in range(0, 7): placed += gs.dream_tool_place(B + Vector3i(x, 4, z), "log").size()
	print("MIRROR placed=", placed)
	await _wait(40)
	await _shot("03_mirror.png")
	# 4) Рамка дома → B (сохранить) → N (выбрать) → O (повернуть) → контур.
	gs.mirror_axis = 0
	gs.frame_mark(B); gs.frame_mark(B + Vector3i(8, 4, 6))
	await _press("blueprint_save")
	gs.blueprint_shown = -1
	await _press("blueprint_show")
	await _press("blueprint_rotate")
	print("INPUT B/N/O bps=", gs.blueprints.size(), " shown=", gs.blueprint_shown, " rot=", gs.paste_rot, " size=", gs.blueprints.back()["size"])
	gs.clear_frame()
	tools._aim_t = 1e9   # фиксируем точку вставки для кадра
	gs.set_paste_origin(B + Vector3i(12, 0, 0))
	get_first_node_in_group("blueprint_ghost").rebuild()
	var eye2 := Vector3(B.x + 10.0, B.y + 9.0, B.z + 20.0)
	_look(eye2, 0.0, -0.42)
	await _wait(40)
	print("GHOST cells=", get_first_node_in_group("blueprint_ghost").shown_cells)
	await _shot("04_blueprint_ghost.png")
	# 5) Вставка с поворотом 90°.
	var pn: int = gs.paste_blueprint(B + Vector3i(12, 0, 0))
	print("PASTE n=", pn, " cost=", gs.last_tool.cost)
	await _wait(40)
	await _shot("05_pasted_rotated.png")
	# 6) Z — отмена вставки, U — возврат (настоящий ввод).
	var before: int = gs.dream_blocks.size()
	await _press("dream_undo")
	var after_undo: int = gs.dream_blocks.size()
	await _wait(30)
	await _shot("06_undo.png")
	await _press("dream_redo")
	print("INPUT Z/U undo_removed=", before - after_undo, " redo_restored=", gs.dream_blocks.size() - after_undo)
	# 7) Материализация копии: якорь на второй дом → пробуждение → копия в Яви, оригинал во Сне.
	gs.blueprint_shown = -1; get_first_node_in_group("blueprint_ghost").rebuild()
	gs.dev_mode = true
	gs.add_item_count("planks", 0)
	main.switcher.show_result_ui = false
	gs.select_anchor(gs.AnchorType.ANCHOR3); gs.anchors3 = 1; gs.pouch.reagent1 = 50
	main.switcher.wake_up(); await _wait(10)
	player.set_physics_process(false)
	_look(eye2, 0.0, -0.42)
	await _wait(40)
	await _shot("07_wake_view.png")
	print("DONE")
	quit(0)
