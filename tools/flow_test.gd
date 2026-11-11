extends SceneTree
## Сценарий: меню → создать мир → игра → изменить → пауза → выйти в меню → снова войти (сейв подхватился).
func _init() -> void:
	call_deferred("_go")

func _wait(n: int) -> void:
	for i in range(n):
		await process_frame

func _go() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(10)
	var mm = current_scene
	assert(mm.name != "")
	mm._name_edit.text = "Флоу тест"
	mm._seed_edit.text = "сонная деревня"
	mm._create_world()
	await _wait(30)
	var gs = root.get_node("GameState")
	print("FLOW scene=", current_scene.name, " world=", gs.world_folder, " seed=", gs.world_seed)
	assert(current_scene.scene_file_path.ends_with("main.tscn"))
	var folder: String = gs.world_folder
	var seed: int = gs.world_seed
	assert(seed == gs.seed_from_text("сонная деревня"))
	assert(FileAccess.file_exists("user://worlds/%s/save.json" % folder))
	gs.add_item_count("drift", 17)
	gs.nails = 9
	var pm = current_scene.get_node("PauseMenu")
	pm.open()
	assert(paused)
	pm._quit_to_menu()
	await _wait(20)
	assert(current_scene.scene_file_path.ends_with("main_menu.tscn"))
	assert(not paused)
	var mm2 = current_scene
	mm2._refresh_worlds()
	var idx := -1
	for i in range(mm2._worlds.size()):
		if str(mm2._worlds[i].get("folder", "")) == folder:
			idx = i
	assert(idx >= 0)
	mm2._start_world(mm2._worlds[idx])
	await _wait(30)
	print("FLOW reload drift=", gs.raw_count("drift"), " nails=", gs.nails)
	assert(gs.raw_count("drift") == 17)
	assert(gs.nails == 9)
	assert(gs.world_seed == seed)
	var ws: GDScript = load("res://scripts/world_store.gd")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(5)
	assert(ws.delete_world(folder))
	print("FLOW OK")
	quit(0)
