extends SceneTree
## Кадры v0.25: «толстые» мобы, их атаки, Бургер ×2, лук без натяжения, блоки в хотбаре/инвентаре/руке,
## карта мира со значком босса, броня на модели игрока.
## DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v025_screens.gd -- --out=/workspace/shots/v025
var OUT := "/workspace/shots/v025/"
var gs; var main; var player; var build
var only := ""
func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", name)
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch
func _sel(i: int) -> void:
	gs.select_item_slot(i); build._update_hand_tools(); await _wait(12)
func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): OUT = a.substr(6).trim_suffix("/") + "/"
		if a.begins_with("--only="): only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_node("GameSettings").dream_start = false
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(60)
	var mm = current_scene
	mm._show("create"); mm._name_edit.text = "Кадры v0.25"; mm._seed_edit.text = "6767676767"
	mm._difficulty.select(1); mm._update_diff_info()
	await _wait(10)
	mm._create_world()
	await _wait(160)
	gs = root.get_node("GameState"); main = current_scene; player = main.get_node("Player"); build = main.build
	gs.skip_tutorial()
	if gs.is_dream():
		main.switcher.wake_up(true); await _wait(60)
		var ui = get_first_node_in_group("transfer_result_ui")
		if ui and ui.panel.visible: ui.close()
	print("DIFF ", gs.difficulty)
	gs.dev_mode = false
	gs.day_time = 400.0
	for d in get_nodes_in_group("day_cycle"): d.set_time(400.0)
	player.set_physics_process(false)
	for i in range(gs.ITEM_SLOT_COUNT): gs.set_slot(i, {})
	gs.set_slot(0, {"id":"pickaxe2","name":"Каменная кирка","count":1})
	gs.set_slot(1, {"id":"pickaxe3","name":"Металлическая кирка","count":1})
	gs.set_slot(2, {"id":"bow","name":"Деревянный лук","count":1})
	gs.set_slot(3, {"id":"bow2","name":"Металлический лук","count":1})
	gs.set_slot(4, {"id":"metal_sword","name":"Металлический меч","count":1})
	gs.set_slot(5, {"id":"arrow","name":"Стрела","count":60})
	gs.set_slot(6, {"id":"planks","name":"Доски","count":32})
	gs.set_slot(7, {"id":"speed_potion","name":"Зелье скорости","count":2})
	gs.set_slot(8, {"id":"log","name":"Бревно","count":20})
	var sp: Vector3 = gs.spawn_point
	var at := sp + Vector3(4, 0.2, 6)
	for n in get_nodes_in_group("enemy"): n.queue_free()
	var host: Node3D = main.build._wake_world()
	# --- 1. мобы в два ряда кадров (рост как у старых, воришка ниже); рядом игрок-аватар для масштаба
	for cm in get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")): cm.call("absorb_trees_near", at + Vector3(0, 0, -6), 18.0)
	await _wait(20)
	var groups := [[["seam", false], ["seam", true], ["ghost", 0], ["ghost", 1], ["ghost", 2], ["ghost", 3]], [["jumper", 0], ["archer", 0], ["thief", 0], ["clown", 0], ["lizard", 0], ["avatar", 0]]]
	var gi := 0
	for specs in groups:
		var mobs: Array = []
		var x0: float = at.x - float((specs as Array).size() - 1) * 0.95
		for k in range((specs as Array).size()):
			var sp2: Array = (specs as Array)[k]
			var pos := Vector3(x0 + k * 1.9, at.y, at.z - 6.0)
			var m: Node3D
			match str(sp2[0]):
				"seam":
					m = load("res://scripts/seam_creature.gd").new()
					if bool(sp2[1]): m.configure_elite(true)
					m.position = pos; host.add_child(m)
				"ghost":
					m = load("res://scripts/enemy_ghost.gd").new(); m.configure(int(sp2[1]), pos, pos); m.position = pos; host.add_child(m)
				"clown":
					m = load("res://scripts/clown_bomb.gd").new(); m.position = pos; host.add_child(m)
				"lizard":
					m = load("res://scripts/lizard_minion.gd").spawn(host, pos)
				"avatar":
					m = load("res://scripts/net_avatar.gd").new(); m.display_name = "Игрок"; host.add_child(m); m.global_position = pos
					m.set_meta("target", pos); m.set_meta("yaw", PI); m.set_meta("item", "sword2"); m.set_meta("hp", 100)
				_:
					m = load("res://scripts/wake_mob.gd").spawn(host, pos, str(sp2[0]))
			mobs.append(m)
		await _wait(10)
		for m in mobs:
			if not is_instance_valid(m): continue
			m.set_physics_process(false); m.set("frozen", true)
			var md := m.get_node_or_null("Model") as Node3D
			if md == null: md = m.find_child("Model", true, false) as Node3D
			if md and not m.is_in_group("remote_player"): md.rotation.y = 0.0
			m.rotation.y = 0.0
			m.global_position.y = at.y
		_look(Vector3(at.x, at.y + 0.2, at.z + 2.0), 0.0, -0.06)
		player.get_node("CameraPivot/Camera3D").fov = 70.0
		for c in main.get_children():
			if c is CanvasLayer: c.visible = false
		await _wait(30)
		await _shot("22_mobs_lineup_%d.png" % gi)
		for m in mobs:
			if not is_instance_valid(m): continue
			var md2: Node = m.get_node_or_null("Model")
			if md2 == null: md2 = m.find_child("Model", true, false)
			if md2 and md2.has_method("play_state"): md2.play_state("attack", true)
		await _wait(14)
		await _shot("23_mobs_attack_%d.png" % gi)
		for m in mobs:
			if is_instance_valid(m): m.queue_free()
		gi += 1
	for c in main.get_children():
		if c is CanvasLayer: c.visible = true
	player.get_node("CameraPivot/Camera3D").fov = 75.0
	# --- 2. Бургер ×2, высота +7
	var B: GDScript = load("res://scripts/boss_burger.gd")
	var boss: Node3D = B.spawn_at(host, at + Vector3(0, 0, -16))
	await _wait(5)
	boss.set_physics_process(false); boss.set("frozen", true)
	boss.global_position = at + Vector3(0, boss.HOVER_H, -16)
	_look(Vector3(at.x, at.y, at.z + 6), 0.0, 0.32)
	await _wait(30)
	await _shot("24_burger_x2_high.png")
	# --- 3. карта мира со значком Бургера
	_look(at, 0.0, -0.05); await _wait(40)
	await _shot("25_world_map_boss.png")
	boss.queue_free(); await _wait(5)
	# --- 4. лук без натяжения: клик — выстрел, перезарядка
	_look(at, 0.0, 0.02)
	await _sel(2); await _shot("26_bow_hand.png")
	await _sel(3); await _shot("27_bow2_hand.png")
	Input.action_press("attack_break"); await _wait(3); Input.action_release("attack_break"); await _wait(4)
	await _shot("28_bow_arrow_straight.png")
	print("BOW shots=", build.bow.shots, " cd=", build.bow.cooldown)
	# --- 5. блоки: хотбар, рука, инвентарь
	await _sel(6); await _shot("29_block_hand_planks.png")
	await _sel(8); await _shot("30_block_hand_log.png")
	var inv = get_first_node_in_group("inventory_ui"); inv.open(); await _wait(15); await _shot("31_inventory_blocks.png"); inv.close(); await _wait(5)
	# --- 6. другой игрок: модель 1,75 м, металлическая броня, удар
	var av: Node3D = load("res://scripts/net_avatar.gd").new()
	av.display_name = "Друг"; av.idx = 1
	host.add_child(av)
	av.global_position = at + Vector3(0, 0, -3.2)
	av.set_meta("target", av.global_position); av.set_meta("yaw", 0.0); av.set_meta("item", "metal_sword"); av.set_meta("hp", 100)
	av.set_meta("armor", ["metal_helmet", "metal_chest", "metal_legs", "metal_boots"])
	_look(Vector3(at.x, at.y, at.z), 0.0, -0.05)
	await _wait(30)
	await _shot("32_player_metal_armor.png")
	av.set_meta("act", "attack"); av.set_meta("act_n", 1); await _wait(8)
	await _shot("33_player_swing.png")
	quit()
