extends SceneTree
## Кадры v0.23: предмет в кисти руки во всех действиях, выбрасывание.
## DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v023_screens.gd -- --out=/workspace/shots/v023
var OUT := "/workspace/shots/v023/"
var gs; var main; var player; var build
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", name, " clip=", build.viewmodel.arms.current_clip() if build.viewmodel else "")
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch
func _sel(i: int) -> void:
	gs.select_item_slot(i); build._update_hand_tools(); await _wait(12)
func _dbg(tag: String) -> void:
	var vm = build.viewmodel
	var cam: Node3D = vm.get_parent()
	var sk: Node3D = vm.hand_socket()
	print("DBG ", tag, " clip=", vm.arms.current_clip(), " pos=", vm.arms.ap.current_animation_position if vm.arms.ap.current_animation != "" else -1.0, " sk=", cam.to_local(sk.global_position), " hr=", cam.to_local(vm.hand_root.global_position), " vis=", vm.hand_root.visible)
func _seq(prefix: String, action: Callable, frames: Array) -> void:
	Engine.time_scale = 0.15
	action.call()
	var f := 0
	_dbg(prefix + " start")
	for target in frames:
		while f < int(target):
			await process_frame; f += 1
			_dbg(prefix + " f%d" % f)
		await _shot("%s_f%02d.png" % [prefix, f])
	Engine.time_scale = 1.0
	await _wait(40)
func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = false
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	mm._show("create"); mm._name_edit.text = "Кадры v0.23"; mm._seed_edit.text = "6767676767"
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player"); build = main.build
	gs.skip_tutorial()
	if gs.is_dream():
		main.switcher.wake_up(true); await _wait(60)
		var ui = get_first_node_in_group("transfer_result_ui")
		if ui and ui.panel.visible: ui.close()
	gs.dev_mode = false
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	player.set_physics_process(false)
	for i in range(gs.ITEM_SLOT_COUNT): gs.set_slot(i, {})
	gs.set_slot(0, {"id":"sword2","name":"Каменный меч","count":1})
	gs.set_slot(1, {"id":"pickaxe2","name":"Каменная кирка","count":1})
	gs.set_slot(2, {"id":"torch","name":"Факел","count":8})
	gs.set_slot(3, {"id":"stone","name":"Камень","count":32})
	gs.set_slot(4, {"id":"heal1","name":"Зелье","count":3})
	gs.set_slot(5, {"id":"planks","name":"Доски","count":20})
	var sp: Vector3 = gs.spawn_point
	var at := sp + Vector3(4, 0.2, 6)
	_look(at, 0.4, -0.25); await _wait(40)
	await _sel(0); await _shot("01_sword_idle.png")
	await _seq("02_sword_swing", func(): build._place_cooldown = 0.0; build._try_sword(), [3, 6, 9, 13])
	await _sel(1); await _shot("03_pickaxe_idle.png")
	await _seq("04_pickaxe_mine", func(): build._play_tool_swing(), [4, 8])
	await _sel(2); await _shot("05_torch_idle.png")
	await _seq("06_torch_place", func(): build._arms("place"), [5])
	await _sel(3); await _shot("07_block_idle.png")
	await _seq("08_block_swing_air", func(): build._place_cooldown = 0.0; build.swing_air(), [4, 8])
	await _seq("09_block_place", func(): build._arms("place"), [5])
	await _sel(4); await _shot("10_potion_idle.png")
	await _seq("11_potion_drink", func(): build.show_in_hand("heal1", 0.8, "drink"), [8, 16])
	gs.set_slot(6, {}); await _sel(6); await _shot("12_empty_hand.png")
	await _seq("13_empty_punch", func(): build._place_cooldown = 0.0; build.swing_air(), [4])
	# выбрасывание
	await _sel(3)
	_look(at, 0.4, 0.0); await _wait(5)
	build.drop_selected(false); await _wait(4)
	await _shot("14_drop_flying.png")
	await _sel(5); build.drop_selected(true); await _wait(70)
	await _sel(1); build.drop_selected(false); await _wait(70)
	var con = get_first_node_in_group("dev_console")
	print(con.execute("drop status"))
	var c := Vector3.ZERO
	var dn: Array = get_nodes_in_group("dropped_item")
	for n in dn: c += n.global_position
	c /= maxf(1.0, float(dn.size()))
	print("drops at ", c, " n=", dn.size())
	await _sel(6)
	var eye := c + Vector3(1.6, 1.0, 1.6)
	player.global_position = eye - Vector3(0, 1.5, 0)
	player.look_at(Vector3(c.x, player.global_position.y, c.z), Vector3.UP)
	player.get_node("CameraPivot").rotation.x = -0.45
	await _wait(20)
	await _shot("15_drops_on_ground.png")
	gs.dev_mode = true
	print(con.execute("drop status")); print(con.execute("hand")); print(con.execute("swing")); print(con.execute("help drop"))
	var inv = get_first_node_in_group("inventory_ui")
	gs.dev_mode = false
	inv.open(); await _wait(5)
	inv._on_slot_clicked(2, MOUSE_BUTTON_LEFT, false); await _wait(5)
	await _shot("16_inventory_held.png")
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	inv._on_outside_input(ev); inv.close(); await _wait(30)
	print("drops after inventory throw: ", gs.dropped_items.size())
	quit()
