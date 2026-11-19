extends SceneTree
## v0.16: сквозной прогон петли «Явь → отпечаток → Сон → палитра → якорь → пробуждение → сейв на диск → перезапуск мира».
## Настоящие сцены меню и игры, настоящий файл сейва. godot --headless --path . -s res://tools/v016_loop.gd
var fails: Array = []
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _ok(c: bool, tag: String) -> void:
	print(("LOOP ok   " if c else "LOOP FAIL ") + tag)
	if not c: fails.append(tag)

func _go() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(10)
	var mm = current_scene
	mm._name_edit.text = "Петля сна v016"
	mm._seed_edit.text = "сон помнит"
	mm._create_world()
	await _wait(40)
	var gs = root.get_node("GameState")
	var main = current_scene
	var folder: String = gs.world_folder
	main.player.set_physics_process(false)
	_ok(not gs.is_dream() and gs.dream_palette() == ["drift"], "новый мир: Явь, палитра только дрейф")
	# Явь: «добыли» 12 досок и 5 камней (тот же путь, что подбор дропа: add_item_count в Яви)
	var lucid0: float = gs.clarity
	gs.add_item_count("planks", 12); gs.add_item_count("stone", 5)
	_ok(gs.has_imprint("planks") and gs.has_imprint("stone") and gs.clarity >= minf(gs.dream_clarity_max(), lucid0 + 2 * gs.LUCID_IMPRINT) - 0.01, "отпечатки досок и камня + осознанность")
	# Сон через переключатель (как E на кровати)
	main.switcher.enter_dream()
	await _wait(5)
	_ok(gs.is_dream(), "уснул")
	gs.dream_material = "planks"
	for i in range(gs.inv_dream.size()): gs.inv_dream[i] = {}
	var b := Vector3i(40, 20, 40)
	for x in range(4):
		for z in range(3):
			var c := b + Vector3i(x, 0, z)
			main.build._place_at(c)
	gs.dream_material = "stone"
	for x in range(4): main.build._place_at(b + Vector3i(x, 1, 0))
	_ok(gs.dream_blocks.size() >= 16 + 25 and str(gs.dream_blocks[b].kind) == "planks" and str(gs.dream_blocks[b + Vector3i(0, 1, 0)].kind) == "stone", "построено из палитры: 12 досок + 4 камня")
	await _wait(3)
	_ok(main.dream_voxels._data.has(b) and main.dream_voxels._data.has(b + Vector3i(3, 1, 0)), "Сон отрисовал блоки")
	# Якорь: клин по центру — нужно 12 досок + 4 камня; камня 5 → хватает
	gs.select_anchor(gs.AnchorType.WEDGE); gs.wedges = maxi(gs.wedges, 1)
	gs.pouch.reagent1 = maxi(int(gs.pouch.reagent1), 5); gs.clarity = maxf(gs.clarity, 30.0)
	var p: Dictionary = gs.anchor_preview(b + Vector3i(1, 0, 1))
	for i in range(200):
		if p.ready: break
		await process_frame; p = gs.anchor_preview(b + Vector3i(1, 0, 1))
	_ok(p.ready and p.ok and int(p.materials.get("planks", 0)) == 12 and int(p.materials.get("stone", 0)) == 4, "превью якоря: цена 12 досок + 4 камня")
	_ok(gs.try_place_anchor(b + Vector3i(1, 0, 1)), "якорь поставлен")
	main.switcher.show_result_ui = false
	var r: Dictionary = main.switcher.wake_up()
	await _wait(5)
	_ok(r.ok and int(r.copied) == 16 and not gs.is_dream(), "проснулся: 16 копий")
	_ok(gs._inv_count(gs.inv_wake, "planks") == 0 and gs._inv_count(gs.inv_wake, "stone") == 1, "списано из Яви: доски 12, камень 4")
	_ok(main.wake_voxels._data.has(b) and str(gs.wake_blocks[b].kind) == "planks", "копия стоит в Яви и отрисована")
	_ok(gs.dream_blocks.has(b) and gs.dream_blocks.size() >= 41, "оригинал остался во Сне")
	# Сейв на диск → выход в меню → загрузка мира заново
	var ss = main.get_node_or_null("Systems/SaveSystem")
	if ss == null:
		for n in main.find_children("*", "", true, false):
			if n.has_method("save_game") and n.has_method("load_game"): ss = n; break
	_ok(ss != null and ss.save_game("v016 loop"), "сейв записан на диск")
	var pm = main.get_node("PauseMenu"); pm.open(); pm._quit_to_menu()
	await _wait(20)
	var mm2 = current_scene; mm2._refresh_worlds()
	var w: Dictionary = {}
	for it in mm2._worlds:
		if str(it.get("folder", "")) == folder: w = it
	mm2._start_world(w)
	await _wait(40)
	main = current_scene
	_ok(gs.dream_blocks.has(b) and str(gs.dream_blocks[b + Vector3i(0, 1, 0)].kind) == "stone" and gs.wake_blocks.has(b), "после перезапуска мира: Сон и Явь на месте")
	_ok(gs.has_imprint("planks") and gs.has_imprint("stone"), "отпечатки пережили перезапуск")
	# Ремонт: в Яви ломаем 3 доски, во Сне тот же клин чинит только их
	for c in [b, b + Vector3i(1, 0, 0), b + Vector3i(2, 0, 2)]: gs.remove_shape(gs.wake_blocks, c)
	gs.add_item_count("planks", 3)
	main.player.set_physics_process(false)
	main.switcher.enter_dream(); await _wait(5)
	gs.pouch.reagent1 = maxi(int(gs.pouch.reagent1), 5); gs.clarity = maxf(gs.clarity, 30.0)
	var p2: Dictionary = gs.anchor_preview(b + Vector3i(1, 0, 1))
	for i in range(200):
		if p2.ready: break
		await process_frame; p2 = gs.anchor_preview(b + Vector3i(1, 0, 1))
	_ok(p2.new_roots.size() == 3 and int(p2.same) == 13 and int(p2.materials.get("planks", 0)) == 3, "ремонт: 3 новых, 13 уже в Яви, цена 3 доски")
	_ok(gs.try_place_anchor(b + Vector3i(1, 0, 1)), "якорь ремонта")
	main.switcher.show_result_ui = false
	var r2: Dictionary = main.switcher.wake_up(); await _wait(3)
	_ok(int(r2.transferred) == 3 and gs.wake_blocks.has(b) and gs.wake_blocks.has(b + Vector3i(2, 0, 2)), "ремонт выполнен")
	change_scene_to_file("res://scenes/main_menu.tscn"); await _wait(5)
	load("res://scripts/world_store.gd").delete_world(folder)
	print("LOOP ", "OK" if fails.is_empty() else "FAILED " + str(fails))
	quit(0 if fails.is_empty() else 1)
