extends Node3D
## Главная сцена v0.5: мир из выбранного сейва/сида, пауза (Esc), настройки, отсечение сущностей.

@onready var player: CharacterBody3D = $Player
@onready var wake_world: Node3D = $WakeWorld
@onready var dream_world: Node3D = $DreamWorld
@onready var wake_voxels: Node3D = $WakeWorld/WakeVoxels
@onready var dream_voxels: Node3D = $DreamWorld/DreamVoxels
@onready var bed: StaticBody3D = $WakeWorld/Bed
@onready var build: Node = $Systems/BuildController
@onready var anchors: Node = $Systems/AnchorSystem
@onready var switcher: Node = $Systems/WorldSwitcher
@onready var wake_chunks: Node3D = $WakeWorld/WakeChunks
@onready var dream_chunks: Node3D = $DreamWorld/DreamChunks
@onready var threat: Node = $Systems/ThreatDirector
@onready var saver: Node = $Systems/SaveSystem


func _ready() -> void:
	get_tree().paused = false
	if _want_perf():
		wake_chunks.legacy_generation = "--legacy-generation" in OS.get_cmdline_user_args()
		dream_chunks.legacy_generation = wake_chunks.legacy_generation
	if _want_shots07() or _want_inventory_mockup() or _want_shots08() or _want_shots09():
		GameState.begin_world("Скриншоты v0.7", "", "6767676767", GameState.DEV_SEED, true)
	elif _want_shots06():
		GameState.begin_world("Скриншоты v0.6", "", "6767676767", GameState.DEV_SEED, false)
	elif _want_shots05():
		GameState.begin_world("Скриншоты", "", "6767676767", GameState.DEV_SEED, true)
	elif GameState.world_folder == "" and not _want_shots() and not _want_perf() and not has_meta("smoke"):
		# Сцену запустили напрямую (F6 в редакторе) — временный мир без сохранения.
		GameState.begin_world("", "", "1337", 1337, false)
	elif _want_perf() and GameState.world_folder == "":
		GameState.begin_world("", "", "1337", 1337, false)
	build.setup(player, dream_voxels)
	anchors.setup(player, dream_voxels)
	switcher.setup(player, wake_world, dream_world, bed, wake_voxels, dream_voxels)
	threat.setup(player, wake_world, bed)
	dream_world.add_child(load("res://scripts/blueprint_ghost.gd").new())
	saver.setup(self, player, wake_voxels, dream_voxels, threat)
	var loaded := false
	if not _want_shots() and saver.has_save():
		loaded = saver.load_game()
	if not loaded:
		if wake_chunks and wake_chunks.has_method("setup"):
			wake_chunks.setup(player, GameState.world_seed_wake)
		if dream_chunks and dream_chunks.has_method("setup"):
			dream_chunks.setup(player, GameState.world_seed_dream)
		if not _want_shots() and not _want_shots05() and not _want_shots06() and not _want_shots07() and not _want_shots08() and not _want_shots09() and not _want_inventory_mockup():
			_build_starter_camp()
	var day_script: GDScript = load("res://scripts/day_cycle.gd")
	var day: Node = day_script.new()
	$Systems.add_child(day)
	var sun := wake_world.get_node_or_null("Sun") as DirectionalLight3D
	var fill := wake_world.get_node_or_null("WarmFill") as OmniLight3D
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if day.has_method("setup"):
		day.setup(sun, we.environment if we else null, fill)
	var culler_script: GDScript = load("res://scripts/entity_culler.gd")
	var culler: Node = culler_script.new()
	culler.name = "EntityCuller"
	$Systems.add_child(culler)
	culler.setup(player)
	var pause_script: GDScript = load("res://scripts/pause_menu.gd")
	var pause: Node = pause_script.new()
	pause.name = "PauseMenu"
	add_child(pause)
	var console := preload("res://scripts/dev_console.gd").new()
	add_child(console)
	add_child(preload("res://scripts/transfer_result_ui.gd").new())
	_apply_settings()
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.settings_changed.connect(_apply_settings)
	_start_music()
	_spawn_saved_graves()
	if loaded:
		player.global_position = player.global_position
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	if _want_shots09():
		call_deferred("_capture_v09")
	elif _want_shots08():
		call_deferred("_capture_v08")
	elif _want_inventory_mockup():
		call_deferred("_capture_inventory_mockup")
	elif _want_shots07():
		call_deferred("_capture_v07")
	elif _want_shots06():
		call_deferred("_capture_v06")
	elif _want_shots05():
		call_deferred("_capture_v05")
	elif _want_shots():
		call_deferred("_capture_shots")
	elif loaded:
		GameState.set_hint("Продолжение с диска (F5 сейв / F9 лоад).")
	else:
		saver.save_game("new-world")
	GameState.inventory_changed.emit()
	_camp_label()
	print("Сонная стройка v0.11 ready. world=%s seed=%d dev=%s" % [GameState.world_folder, GameState.world_seed, GameState.dev_mode])


func _on_player_died() -> void:
	## v0.7: смерть → кучка вещей на месте гибели (всё, кроме гвоздей/якорей/маяков) + меню смерти.
	for b in get_tree().get_nodes_in_group("block_mother"):
		if b.has_method("leave"):
			b.leave("Мать блоков потеряла к тебе интерес и ушла под землю.")
	for a in get_tree().get_nodes_in_group("anaconda"):
		if a.has_method("leave"):
			a.leave("Анаконда утащила добычу в глубину… и потеряла к тебе интерес.")
	for inv in get_tree().get_nodes_in_group("inventory_ui"):
		inv.close() # return cursor-held armour/tools before collecting the death drop
	var at := player.global_position
	var items: Array = GameState.collect_death_drop()
	var n := 0
	for it in items:
		n += int(it["count"])
	var gid := GameState.add_grave(at, items)
	if gid >= 0:
		_spawn_grave(gid)
	last_death_drop = n
	var info := "Вещи (%d шт.) лежат на месте гибели — подойди, чтобы подобрать.\nГвозди, клинья, якоря и маяки остались при тебе." % n if n > 0 else "Терять было нечего."
	if GameState.dev_mode:
		info = "DEV-сид: ресурсы бесконечны, ничего не выпало."
	var hud := get_node_or_null("HUD")
	if hud and "death_menu" in hud and hud.death_menu:
		var dm: Control = hud.death_menu
		if not dm.respawn_pressed.is_connected(respawn):
			dm.respawn_pressed.connect(respawn)
			dm.exit_pressed.connect(exit_world)
		dm.open(info)
		get_tree().paused = true
	else:
		respawn()


var last_death_drop := 0


func respawn() -> void:
	get_tree().paused = false
	var hud := get_node_or_null("HUD")
	if hud and "death_menu" in hud and hud.death_menu:
		hud.death_menu.close()
	GameState.death_open = false
	player.global_position = GameState.spawn_point
	player.velocity = Vector3.ZERO
	GameState.heal_player_full()


func exit_world() -> void:
	respawn()
	if saver and saver.has_method("save_game"):
		saver.save_game("death-exit")
	GameState.paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _spawn_grave(gid: int) -> Node3D:
	var idx := GameState.grave_index(gid)
	if idx < 0:
		return null
	var script: GDScript = load("res://scripts/grave_pile.gd")
	var g: Node3D = script.new()
	g.configure(gid)
	g.position = GameState.graves[idx]["pos"]
	wake_world.add_child(g)
	return g


func _spawn_saved_graves() -> void:
	for g in get_tree().get_nodes_in_group("grave_pile"):
		g.queue_free()
	for gr in GameState.graves:
		_spawn_grave(int(gr["id"]))


func _want_shots08() -> bool:
	return "--shots08" in OS.get_cmdline_user_args()


func _want_inventory_mockup() -> bool:
	return "--mock-inventory" in OS.get_cmdline_user_args()


func _want_shots07() -> bool:
	return "--shots07" in OS.get_cmdline_user_args()


func _want_shots06() -> bool:
	return "--shots06" in OS.get_cmdline_user_args()


func _apply_settings() -> void:
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets == null:
		return
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		gsets.apply_environment(we.environment)
	var sun := wake_world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = bool(gsets.shadows)
		sun.directional_shadow_max_distance = maxf(40.0, float(gsets.render_distance) * 16.0)


func _want_perf() -> bool:
	return "--perf" in OS.get_cmdline_user_args()


func apply_world_visibility(is_dream: bool) -> void:
	if switcher and switcher.has_method("_apply_visibility"):
		switcher.call("_apply_visibility", is_dream)
	if switcher and switcher.has_method("_tint_dream"):
		switcher.call("_tint_dream", is_dream)
	if "flying" in player:
		player.set("flying", is_dream)


func _start_music() -> void:
	if has_node("MusicController"):
		return
	var script: GDScript = load("res://scripts/music_controller.gd")
	var mc: Node = script.new()
	mc.name = "MusicController"
	add_child(mc)


func _want_shots() -> bool:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return _want_shots09() or _want_shots08() or _want_inventory_mockup() or "--shots" in args or "--shots05" in args or "--shots06" in args or "--shots07" in args


func _want_shots05() -> bool:
	return "--shots05" in OS.get_cmdline_user_args()


func _look_at_point(target: Vector3, from: Vector3) -> void:
	player.global_position = from
	var d := target - from
	player.rotation.y = atan2(-d.x, -d.z)
	if player.has_node("CameraPivot"):
		var flat := Vector2(d.x, d.z).length()
		player.get_node("CameraPivot").rotation.x = atan2(d.y, flat)


func _capture_v05() -> void:
	## v0.5: HUD (хотбар 9 + вертикальная полоса), открытый инвентарь, маяк, пауза, сон.
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	GameState.beacons = 3
	GameState.add_item_count("drift", 40)
	GameState.add_item_count("hill", 12)
	GameState.select_item_slot(0)
	if wake_chunks.has_method("load_all_pending"):
		wake_chunks.load_all_pending()
	var ruin: Vector3i = wake_chunks.find_first_terrain("ruin") if wake_chunks.has_method("find_first_terrain") else Vector3i(0, -999, 0)
	var focus := Vector3(8, 0.5, -10)
	if ruin.y != -999 and Vector2(ruin.x, ruin.z).length() < 70.0:
		focus = Vector3(ruin.x + 0.5, 1.0, ruin.z + 0.5)
	_look_at_point(focus, focus + Vector3(0, 2.4, 9))
	# маяк рядом с точкой обзора
	var bcell := Vector3i(floori(focus.x) - 4, 0, floori(focus.z) + 2)
	if GameState.place_wake_block(bcell, "beacon"):
		wake_voxels.add_block(bcell, GameState.wake_blocks[bcell])
	await get_tree().create_timer(1.2).timeout
	GameState.set_hint("v0.5: хотбар 1–9, инвентарь I/Tab, якоря — справа (R), маяк — G.")
	await _save_shot("v05_hud.png")
	var hud := get_node_or_null("HUD")
	if hud and "inventory" in hud and hud.inventory:
		hud.inventory.open()
		await get_tree().create_timer(0.3).timeout
		await _save_shot("v05_inventory.png")
		hud.inventory.close()
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.set_value("show_fps", true)
	await get_tree().create_timer(0.3).timeout
	await _save_shot("v05_hud_debug.png")
	if wake_chunks.has_method("get_any_lake_sample_point"):
		var lp: Vector3 = wake_chunks.get_any_lake_sample_point()
		if lp != Vector3.ZERO:
			_look_at_point(lp, lp + Vector3(6, 5, 6))
			await get_tree().create_timer(0.8).timeout
			await _save_shot("v05_lake.png")
			_look_at_point(focus, focus + Vector3(0, 2.4, 9))
	var pm := get_node_or_null("PauseMenu")
	if pm:
		pm.open()
		await get_tree().create_timer(0.2, true, false, true).timeout
		await _save_shot("v05_pause.png")
		pm.resume()
	if switcher.has_method("enter_dream"):
		switcher.enter_dream()
	elif switcher.has_method("_enter_dream"):
		switcher._enter_dream()
	await get_tree().create_timer(1.5).timeout
	await _save_shot("v05_dream.png")
	if gsets:
		gsets.set_value("show_fps", false)
	get_tree().quit(0)


func _day() -> Node:
	var arr := get_tree().get_nodes_in_group("day_cycle")
	return arr[0] if arr.size() > 0 else null


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _capture_v06() -> void:
	## v0.6: текстуры, деревья, фазы суток и луна, иконки, перебинд, мобы лицом вперёд, бой с боссом.
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.set("render_distance", 4)
	wake_chunks._apply_radius(4)
	wake_chunks._update_chunks(true)
	wake_chunks.load_all_pending()
	var day := _day()
	var tree: Dictionary = wake_chunks.find_first_tree()
	var tpos := Vector3(10, 0, 10)
	if not tree.is_empty():
		var base: Vector3i = (tree["logs"] as Array)[0]
		tpos = Vector3(base.x + 0.5, 0, base.z + 0.5)
	print("SHOT06 tree at ", tpos, " trees=", wake_chunks.count_loaded_trees())
	# 1. День: текстурированный рельеф и деревья
	day.set_time(500.0)
	_look_at_point(tpos + Vector3(0, 2.5, 0), tpos + Vector3(-7, 3.2, 9))
	GameState.select_item_slot(0)
	await _wait(1.0)
	await _save_shot("v06_day_trees.png")
	_look_at_point(Vector3(30, 0, -30), Vector3(0, 9, 8))
	await _wait(0.5)
	await _save_shot("v06_day_panorama.png")
	# 2. Утро, вечер, ночь с луной
	day.set_time(40.0)
	_look_at_point(Vector3(60, 6, 4), Vector3(0, 10, 4))
	await _wait(0.5)
	await _save_shot("v06_morning.png")
	day.set_time(985.0)
	_look_at_point(Vector3(-60, 6, 4), Vector3(0, 10, 4))
	await _wait(0.5)
	await _save_shot("v06_evening.png")
	day.set_time(1110.0)
	var md: Vector3 = day.moon_dir()
	_look_at_point(Vector3(0, 3.5, 6) + md * 50.0 + Vector3(0, -14, 0), Vector3(0, 3.5, 6))
	await _wait(0.6)
	await _save_shot("v06_night_moon.png")
	_look_at_point(tpos + Vector3(0, 2.0, 0), tpos + Vector3(-7, 3.2, 9))
	await _wait(0.4)
	await _save_shot("v06_night_trees.png")
	day.set_time(500.0)
	# 3. Инвентарь (иконки)
	var hud := get_node_or_null("HUD")
	if hud and "inventory" in hud and hud.inventory:
		hud.inventory.open()
		await _wait(0.3)
		await _save_shot("v06_inventory.png")
		hud.inventory.close()
	# 4. Перебинд клавиш
	var pm := get_node_or_null("PauseMenu")
	if pm:
		pm.open()
		pm._open_settings()
		await _wait(0.2)
		var sm: Node = pm._settings
		if sm and sm.has_method("_open_keybinds"):
			sm._open_keybinds()
			await _wait(0.2)
			sm._keybinds._start_wait("jump")
			await _wait(0.1)
			await _save_shot("v06_keybinds.png")
			sm._keybinds._close()
		pm.resume()
		await _wait(0.2)
	# 5. Дерево: сломать все брёвна → листва опадает
	if not tree.is_empty():
		_look_at_point(tpos + Vector3(0, 2.5, 0), tpos + Vector3(-6, 3.0, 7))
		for raw in tree["logs"]:
			var c: Vector3i = raw
			GameState.remove_terrain_cell(c, "log")
		wake_chunks.rebuild_chunk_at_world(int(tpos.x), int(tpos.z))
		await _wait(0.4)
		await _save_shot("v06_tree_logs_removed.png")
		print("SHOT06 decay pending=", wake_chunks.pending_leaf_decay())
		await _wait(5.0)
		await _save_shot("v06_tree_decaying.png")
		await _wait(7.0)
		await _save_shot("v06_tree_decayed.png")
		print("SHOT06 decay pending after=", wake_chunks.pending_leaf_decay())
	# 6. Мобы идут лицом вперёд (ИИ выключен, ведём apply_movement вручную)
	var stage := Vector3(0.0, 0.0, 1.0)
	var nav: GDScript = load("res://scripts/enemy_navigation.gd")
	var mobs: Array = []
	var gs_s: GDScript = load("res://scripts/seam_creature.gd")
	var gg_s: GDScript = load("res://scripts/enemy_ghost.gd")
	for i in range(3):
		var m: CharacterBody3D = gs_s.new() if i == 0 else gg_s.new()
		if i > 0:
			m.configure(i, stage, stage)
		m.position = stage + Vector3(-4.2 + float(i) * 2.2, 0.1, float(i) * 1.4 - 2.4)
		wake_world.add_child(m)
		mobs.append(m)
	var walker: CharacterBody3D = gg_s.new()
	walker.configure(0, stage, stage)
	walker.position = stage + Vector3(3.2, 0.1, -3.0)
	wake_world.add_child(walker)
	await get_tree().process_frame
	for m2 in mobs + [walker]:
		m2.set_physics_process(false)
	player.global_position = stage + Vector3(0, 0.2, 6.0)
	player.rotation_degrees = Vector3(0, 0, 0)
	player.get_node("CameraPivot").rotation_degrees = Vector3(-6, 0, 0)
	var vis: GDScript = load("res://scripts/enemy_visuals.gd")
	for k in range(60):
		for m3 in mobs:
			nav.apply_movement(m3, Vector3(1, 0, 0), 2.0, 1.0 / 60.0)
			vis.play_state(m3, "walk")
		nav.apply_movement(walker, Vector3(0, 0, 1), 2.0, 1.0 / 60.0)
		vis.play_state(walker, "walk")
		await get_tree().physics_frame
	await _save_shot("v06_mobs_facing.png")
	var facing_report := []
	for m4 in mobs + [walker]:
		facing_report.append(str(nav.model_world_forward(m4)))
	print("SHOT06 mob forward vectors (want +X for 3, +Z for last): ", facing_report)
	for m5 in mobs + [walker]:
		m5.queue_free()
	# 7. Предвестие босса в чате + бой
	GameState.boss_next_mine = false
	GameState.on_block_mined(0.0)
	var arena := Vector3(-8.0, 0.0, 14.0)
	player.global_position = arena + Vector3(0, 0.2, 9.0)
	player.rotation_degrees = Vector3(0, 0, 0)
	player.get_node("CameraPivot").rotation_degrees = Vector3(-14, 0, 0)
	await _wait(0.3)
	await _save_shot("v06_chat_omen.png")
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: Node3D = boss_script.spawn_near(wake_world, Vector3i(int(arena.x) - 4, 0, int(arena.z) - 2))
	GameState.add_item("sword", "Меч", 1)
	for si in range(GameState.ITEM_SLOT_COUNT):
		if str(GameState.item_slots[si].get("id", "")) == "sword":
			GameState.select_item_slot(si)
			break
	var shots := {"air": false, "wave": false}
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(boss) and Time.get_ticks_msec() - t0 < 25000:
		GameState.heal_player_full()
		player.global_position = Vector3(boss.global_position.x, player.global_position.y, boss.global_position.z + 9.0)
		player.global_position.y = 0.1
		var st := str(boss.STATE_NAMES[boss.state])
		if st == "AIR" and boss.get("_air_t") > 0.45 and not shots["air"]:
			shots["air"] = true
			await _save_shot("v06_boss_slam_shadow.png")
			boss.take_damage(200)
		elif st == "STAGGER" and boss.phase >= 2 and boss._waves.size() > 0 and not shots["wave"]:
			await _wait(0.25)
			shots["wave"] = true
			await _save_shot("v06_boss_shockwave.png")
			break
		await get_tree().physics_frame
	if is_instance_valid(boss):
		for bl in get_tree().get_nodes_in_group("blockling"):
			bl.queue_free()
		boss._start_scatter()
		await _wait(boss.SCATTER_TIME + 0.15)
		player.global_position += Vector3(0, 0, 4.5)
		await _wait(0.3)
		await _save_shot("v06_boss_teleport_marker.png")
		await _wait(1.2)
		boss.hp = 200
		boss.take_damage(60)
		await _wait(2.0)
		GameState.heal_player_full()
		boss._start_rain(player)
		player.get_node("CameraPivot").rotation_degrees = Vector3(-8, 0, 0)
		player.global_position += Vector3(0, 0, 4.0)
		await _wait(0.75)
		await _save_shot("v06_boss_brick_rain.png")
		await _wait(1.6)
		boss._stagger_len = 3.0
		boss._set_crack_glow(true)
		boss._enter(boss.S.STAGGER)
		await _wait(0.2)
		await _save_shot("v06_boss_vulnerable.png")
		print("SHOT06 boss log ", boss.debug_snapshot())
	get_tree().quit(0)


func _save_shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "/workspace/shots/%s" % name
	img.save_png(path)
	print("SHOT saved ", path, " ", img.get_width(), "x", img.get_height())


func _capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	GameState.dust = 400
	GameState.nails = 5
	GameState.wedges = 2
	GameState.anchors3 = 1
	GameState.reagent_counts = [20, 20, 20]
	GameState.reagents = 60
	GameState.inventory_changed.emit()
	await get_tree().create_timer(1.2).timeout
	var lake_p: Vector3 = Vector3(8, 1.5, 16)
	if wake_chunks and wake_chunks.has_method("get_any_lake_sample_point"):
		var sample: Vector3 = wake_chunks.get_any_lake_sample_point()
		if sample != Vector3.ZERO:
			lake_p = sample
	var sides: Array = [
		["water_n.png", Vector3(0, 2.4, -6.5)],
		["water_e.png", Vector3(6.5, 2.4, 0)],
		["water_s.png", Vector3(0, 2.4, 6.5)],
		["water_w.png", Vector3(-6.5, 2.4, 0)],
	]
	for entry in sides:
		var fname: String = str(entry[0])
		var off: Vector3 = entry[1]
		var pos: Vector3 = Vector3(lake_p.x, 2.4, lake_p.z) + off
		pos.y = 2.5
		player.global_position = pos
		var look: Vector3 = Vector3(lake_p.x, 0.2, lake_p.z)
		var dir: Vector3 = look - pos
		player.rotation.y = atan2(-dir.x, -dir.z)
		if player.has_node("CameraPivot"):
			player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
		await get_tree().create_timer(0.2).timeout
		await _save_shot(fname)
	# Плоская площадка у спавна (height_at == 0), камера смотрит на -Z.
	var stage := Vector3(6.0, 0.0, 6.0)
	var rscript: GDScript = load("res://scripts/reagent_node.gd")
	for i in range(3):
		var rn: StaticBody3D = rscript.new()
		rn.configure(i + 1, "shot-%d" % i, 1)
		rn.position = stage + Vector3(float(i) * 1.15 - 1.15, 0.35, 0.0)
		wake_world.add_child(rn)
	player.global_position = stage + Vector3(0.0, 1.55, 3.3)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
	await get_tree().create_timer(0.3).timeout
	await _save_shot("reagents.png")
	var gs := load("res://scripts/seam_creature.gd")
	var gg := load("res://scripts/enemy_ghost.gd")
	var look2 := stage + Vector3(0.0, 0.0, -0.4)
	var seam: CharacterBody3D = gs.new()
	seam.position = look2 + Vector3(-1.3, 0.0, 0.0)
	wake_world.add_child(seam)
	var ghosts: Array[Node] = []
	for i2 in range(4):
		var g: CharacterBody3D = gg.new()
		g.configure(i2, look2, look2)
		g.position = look2 + Vector3(float(i2) * 1.25 - 0.4, 0.0, 0.15)
		wake_world.add_child(g)
		ghosts.append(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var vis: GDScript = load("res://scripts/enemy_visuals.gd")
	vis.play_state(seam, "walk", true)
	for g2 in ghosts:
		vis.play_state(g2, "walk", true)
	player.global_position = look2 + Vector3(0.2, 1.85, 4.6)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-8, 0, 0)
	await get_tree().create_timer(0.45).timeout
	await _save_shot("enemy_walk.png")
	vis.play_state(seam, "attack", true)
	for g3 in ghosts:
		vis.play_state(g3, "attack", true)
	await get_tree().create_timer(0.35).timeout
	await _save_shot("enemy_attack.png")
	if seam.has_method("take_damage"):
		seam.take_damage(20)
	for g4 in ghosts:
		if g4.has_method("take_damage"):
			g4.take_damage(15)
	GameState.add_item("sword", "Меч", 1)
	for si in range(GameState.ITEM_SLOT_COUNT):
		if str(GameState.item_slots[si].get("id", "")) == "sword":
			GameState.select_item_slot(si)
			break
	if build.has_method("_play_sword_swing"):
		build._play_sword_swing()
	if build.has_method("_try_sword"):
		build._try_sword()
	await get_tree().create_timer(0.28).timeout
	await _save_shot("sword_hit.png")
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: Node3D = boss_script.spawn_near(wake_world, Vector3i(int(look2.x), 0, int(look2.z)))
	if boss:
		boss.global_position = look2 + Vector3(0.15, 0.05, 0.2)
	await get_tree().create_timer(0.45).timeout
	player.global_position = look2 + Vector3(0.2, 2.3, 6.4)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
	await _save_shot("boss.png")
	# Кирка: холм до/после добычи. Берём крайний верхний куб, камера близко 3/4.
	var hill_cell := Vector3i(0, -999, 0)
	var hill_eye_off := Vector3(1.9, 1.05, 1.55)
	if wake_chunks and wake_chunks.has_method("height_at"):
		for wx in range(16, 140):
			for wz in range(16, 140):
				var hh: int = int(wake_chunks.height_at(wx, wz))
				if hh < 2:
					continue
				var exposed := false
				var off := Vector3(1.9, 1.05, 1.55)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if int(wake_chunks.height_at(wx + d.x, wz + d.y)) < hh:
						exposed = true
						off = Vector3(float(d.x) * 2.15, 1.05, float(d.y) * 2.15)
						if d.x != 0:
							off.z += 1.25
						else:
							off.x += 1.25
						break
				if not exposed:
					continue
				var cand := Vector3i(wx, hh - 1, wz)
				wake_chunks.ensure_chunk_loaded(wake_chunks.world_to_chunk(Vector3(wx, 0, wz)))
				if wake_chunks.has_method("has_terrain_visual") and wake_chunks.has_terrain_visual(cand):
					hill_cell = cand
					hill_eye_off = off
					break
			if hill_cell.y != -999:
				break
	if hill_cell.y != -999:
		var target := Vector3(float(hill_cell.x) + 0.5, float(hill_cell.y) + 0.5, float(hill_cell.z) + 0.5)
		var eye: Vector3 = target + hill_eye_off
		player.global_position = eye - Vector3(0, 1.4, 0)
		var to_h: Vector3 = target - eye
		player.rotation.y = atan2(-to_h.x, -to_h.z)
		if player.has_node("CameraPivot"):
			var horiz := Vector2(to_h.x, to_h.z).length()
			player.get_node("CameraPivot").rotation.x = atan2(to_h.y, horiz)
		GameState.add_item("pickaxe", "Кирка", 1)
		for pi in range(GameState.ITEM_SLOT_COUNT):
			if str(GameState.item_slots[pi].get("id", "")) == "pickaxe":
				GameState.select_item_slot(pi)
				break
		if build.has_method("_ensure_hand_tools"):
			build._ensure_hand_tools()
		await get_tree().create_timer(0.35).timeout
		await _save_shot("hill_before_mine.png")
		if GameState.has_method("remove_terrain_cell"):
			GameState.remove_terrain_cell(hill_cell, "hill")
		if wake_chunks.has_method("rebuild_chunk_at_world"):
			wake_chunks.rebuild_chunk_at_world(hill_cell.x, hill_cell.z)
		await get_tree().create_timer(0.3).timeout
		await _save_shot("hill_after_mine.png")
	# Кирка и меч в руке от первого лица.
	player.global_position = Vector3(6.0, 1.55, 8.5)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-8, 0, 0)
	GameState.add_item("pickaxe", "Кирка", 1)
	for pi2 in range(GameState.ITEM_SLOT_COUNT):
		if str(GameState.item_slots[pi2].get("id", "")) == "pickaxe":
			GameState.select_item_slot(pi2)
			break
	if build.has_method("_ensure_hand_tools"):
		build._ensure_hand_tools()
	if build.has_method("_update_hand_tools"):
		build._update_hand_tools()
	await get_tree().create_timer(0.25).timeout
	await _save_shot("pickaxe_hand.png")
	GameState.add_item("sword", "Меч", 1)
	for si2 in range(GameState.ITEM_SLOT_COUNT):
		if str(GameState.item_slots[si2].get("id", "")) == "sword":
			GameState.select_item_slot(si2)
			break
	if build.has_method("_update_hand_tools"):
		build._update_hand_tools()
	await get_tree().create_timer(0.25).timeout
	await _save_shot("sword_hand.png")
	# Красная полоска босса: частичное HP, чтобы был виден красный fill и тёмный фон.
	if boss:
		if "hp" in boss:
			boss.hp = 620
		player.global_position = look2 + Vector3(0.2, 2.3, 6.4)
		player.rotation_degrees = Vector3(0, 0, 0)
		if player.has_node("CameraPivot"):
			player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
		await get_tree().create_timer(0.35).timeout
		await _save_shot("boss_bar.png")
	var report := []
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("collect_collision_issues"):
			var issues: Array = cm.collect_collision_issues()
			report.append("%s issues=%d active=%s planar=%s" % [
				cm.name, issues.size(),
				cm._physics_active() if cm.has_method("_physics_active") else "?",
				cm.lake_water_is_planar() if cm.has_method("lake_water_is_planar") else "?"
			])
			for it in issues:
				report.append("  %s" % str(it))
	var rf := FileAccess.open("/workspace/shots/collision_report.txt", FileAccess.WRITE)
	if rf:
		rf.store_string("\n".join(report))
	print("SHOT report:\n", "\n".join(report))
	get_tree().quit(0)


# ---------------------------------------------------------------- v0.7 скриншоты

func _v7_goto(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	wake_chunks._update_chunks(true)
	wake_chunks.load_all_pending()


func _v7_put(cell: Vector3i, kind: String) -> void:
	if GameState.wake_blocks.has(cell):
		return
	if GameState.place_wake_block(cell, kind):
		wake_voxels.add_block(cell, GameState.wake_blocks[cell])


func _v7_dig(cells: Array) -> void:
	var touched := {}
	for raw in cells:
		var c: Vector3i = raw
		var k: String = wake_chunks.terrain_kind_at(c)
		if k == "" or k == "air" or k == "bedrock":
			continue
		GameState.remove_terrain_cell_silent(c, k)
		touched[Vector2i(floori(float(c.x) / 16.0), floori(float(c.z) / 16.0))] = c
	for k2 in touched.keys():
		var c2: Vector3i = touched[k2]
		wake_chunks.rebuild_chunk_at_world(c2.x, c2.z)


func _v7_select(id: String) -> void:
	if GameState.count_item(id) <= 0:
		GameState.add_item_count(id, 1)
	for si in range(GameState.HOTBAR_SIZE):
		if str(GameState.item_slots[si].get("id", "")) == id:
			GameState.select_item_slot(si)
			return
	# Перекладываем в хотбар
	for sj in range(GameState.item_slots.size()):
		if str(GameState.item_slots[sj].get("id", "")) == id:
			GameState.swap_slots(sj, 8)
			GameState.select_item_slot(8)
			return


func _capture_v07() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.set("render_distance", 4)
	wake_chunks._apply_radius(4)
	_v7_goto(GameState.DEFAULT_SPAWN)
	var day := _day()
	day.set_time(500.0)
	threat.set_process(false)
	var hud := get_node_or_null("HUD")
	var report := {}
	# 1. Вход в пещеру (дев-сид, 15–25 м от спавна)
	var dn: Dictionary = wake_chunks.nearest_nest(GameState.DEFAULT_SPAWN, 40.0)
	report["dev_nest"] = dn
	var ent: Vector3 = dn.get("entrance", Vector3(16.5, 0.4, 2.5))
	_v7_goto(Vector3(ent.x - 6.0, 3.0, ent.z - 6.5))
	_look_at_point(ent + Vector3(0, -1.0, 0), Vector3(ent.x - 6.0, 3.2, ent.z - 6.5))
	await _wait(1.0)
	await _save_shot("v07_cave_entrance.png")
	# 2. Пещера изнутри (факелы)
	var path: Array = wake_chunks.DEV_CAVE_PATH
	for i in range(1, path.size()):
		var pp: Vector3 = path[i]
		var fy: float = wake_chunks.floor_y_below(pp + Vector3(0, 0.5, 0), 6)
		_v7_put(Vector3i(floori(pp.x), int(fy), floori(pp.z)), "torch")
	var mid: Vector3 = path[1]
	var mid_floor: float = wake_chunks.floor_y_below(mid + Vector3(0, 0.5, 0), 6)
	_v7_goto(Vector3(mid.x, mid_floor + 0.05, mid.z))
	_look_at_point(Vector3(dn["center"].x, dn["center"].y + 1.0, dn["center"].z), Vector3(mid.x, mid_floor + 0.05, mid.z))
	await _wait(0.8)
	await _save_shot("v07_cave_underground.png")
	# 3. Гнездо дев-сида с яйцом
	var nc: Vector3 = dn["center"]
	_v7_put(Vector3i(floori(nc.x) - 2, int(nc.y), floori(nc.z) + 2), "torch")
	_v7_put(Vector3i(floori(nc.x) + 2, int(nc.y), floori(nc.z) - 2), "torch")
	var cam_from := Vector3(nc.x - 3.0, nc.y + 0.05, nc.z - 2.5)
	_v7_goto(cam_from)
	_look_at_point(Vector3(nc.x, nc.y + 0.4, nc.z), cam_from)
	await _wait(0.8)
	await _save_shot("v07_dev_nest_egg.png")
	# 4. Анаконда с факелами (ночь, у гнезда)
	day.set_time(1230.0)
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var ana: Node3D = AS.spawn_at(wake_world, nc, str(dn.get("id", "dev")))
	await _wait(0.3)
	if ana:
		ana.set_physics_process(false)
		var ep := Vector3(nc.x + 2.2, nc.y + 2.0, nc.z + 0.5)
		var emerge := Vector3(ep.x, wake_chunks.floor_y_below(ep, 8), ep.z)
		ana._emerge = emerge
		ana._enter(ana.S.STUNNED)
		ana._stun_len = 99.0
		for k in range(90):
			ana._t = 0.0
			ana.tick(1.0 / 30.0)
			await get_tree().process_frame
		var hc: Vector3 = ana.hit_center()
		_v7_put(Vector3i(floori(hc.x) + 1, int(nc.y), floori(hc.z) + 1), "torch")
		var af := Vector3(nc.x - 2.5, emerge.y + 0.05, nc.z - 3.2)
		_v7_goto(af)
		_look_at_point(hc + Vector3(0, -0.3, 0), af)
		_v7_select("torch")
		ana.hp = int(ana.MAX_HP * 0.8)
		await _wait(0.5)
		await _save_shot("v07_anaconda_torches.png")
		report["anaconda"] = ana.debug_snapshot()
		ana.leave("")
	day.set_time(500.0)
	await _wait(1.4)
	# 5. Купол-гнездо после прокопа
	var dome: Dictionary = {}
	for n in wake_chunks.nests_near(Vector3(0, -10, 0), 420.0):
		if str(n.get("system", "")) == "dome":
			if dome.is_empty() or (n["center"] as Vector3).length() < (dome["center"] as Vector3).length():
				dome = n
	report["dome"] = dome
	if not dome.is_empty():
		var dc: Vector3 = dome["center"]
		var sx := floori(dc.x) - 3
		var sz := floori(dc.z) - 3
		_v7_goto(Vector3(sx + 0.5, 3, sz + 0.5))
		var shaft: Array = []
		var top: int = wake_chunks.height_at(sx, sz)
		for y in range(int(dc.y) + 1, top + 1):
			for dx in range(0, 2):
				for dz in range(0, 2):
					shaft.append(Vector3i(sx + dx, y, sz + dz))
		_v7_dig(shaft)
		_v7_put(Vector3i(floori(dc.x) + 2, int(dc.y), floori(dc.z) + 1), "torch")
		_v7_put(Vector3i(floori(dc.x) - 1, int(dc.y), floori(dc.z) + 3), "torch")
		_v7_put(Vector3i(sx, int(dc.y) + 1, sz), "torch")
		var from_d := Vector3(sx + 1.0, dc.y + 0.05, sz + 1.0)
		_v7_goto(from_d)
		_look_at_point(Vector3(dc.x, dc.y + 0.6, dc.z), from_d)
		await _wait(0.8)
		await _save_shot("v07_dome_nest_dug.png")
	# 6. Бедрок: шахта 5×5 до y=-30
	var bx := 40
	var bz := 44
	_v7_goto(Vector3(bx + 2.5, 3, bz + 2.5))
	var pit: Array = []
	for y2 in range(-30, wake_chunks.height_at(bx, bz) + 3):
		for ix in range(5):
			for iz in range(5):
				pit.append(Vector3i(bx + ix, y2, bz + iz))
	_v7_dig(pit)
	_v7_put(Vector3i(bx, -30, bz), "torch")
	_v7_put(Vector3i(bx + 4, -30, bz + 4), "torch")
	_v7_put(Vector3i(bx + 4, -27, bz), "torch")
	var bfrom := Vector3(bx + 1.0, -27.5, bz + 1.0)
	_v7_goto(bfrom)
	player.flying = true
	_look_at_point(Vector3(bx + 3.5, -31.0, bz + 3.5), bfrom)
	await _wait(0.8)
	await _save_shot("v07_bedrock.png")
	report["bedrock_kind"] = wake_chunks.terrain_kind_at(Vector3i(bx + 2, -31, bz + 2))
	player.flying = false
	# 7. Текущая вода: канава от озера
	var edge := Vector3i.ZERO
	var found := false
	for r in range(1, 6):
		if found:
			break
		for cx in range(-r, r + 1):
			if found:
				break
			for cz in range(-r, r + 1):
				if found or maxi(absi(cx), absi(cz)) != r:
					continue
				var ck := Vector2i(cx, cz)
				if not wake_chunks.chunk_has_lake(ck):
					continue
				wake_chunks.ensure_chunk_loaded(ck)
				for lx in range(16):
					if found:
						break
					for lz in range(16):
						var wx := cx * 16 + lx
						var wz := cz * 16 + lz
						if wake_chunks._world_is_lake_cell(wx, wz) and not wake_chunks._world_is_lake_cell(wx + 1, wz):
							var ok := true
							for k3 in range(1, 8):
								if wake_chunks._world_is_lake_cell(wx + k3, wz) or wake_chunks.height_at(wx + k3, wz) != 0:
									ok = false
							if ok:
								edge = Vector3i(wx, -1, wz)
								found = true
								break
	report["water_edge"] = edge
	if found:
		_v7_goto(Vector3(edge.x + 4.5, 1, edge.z + 0.5))
		var ch: Array = []
		for k4 in range(1, 8):
			ch.append(edge + Vector3i(k4, 0, 0))
			if k4 >= 5:
				ch.append(edge + Vector3i(k4, -1, 0))
				ch.append(edge + Vector3i(k4, -2, 0))
		ch.append(edge + Vector3i(4, 0, 1))
		ch.append(edge + Vector3i(4, 0, 2))
		_v7_dig(ch)
		for c5 in ch:
			wake_chunks.water_notify(c5)
		await _wait(3.5)
		var wfrom := Vector3(edge.x + 9.0, 2.6, edge.z + 4.0)
		_look_at_point(Vector3(edge.x + 3.0, -1.0, edge.z + 0.5), wfrom)
		await _wait(0.5)
		await _save_shot("v07_water_flow.png")
		report["water_cells"] = wake_chunks.water_cell_count()
	# 8. Ночь — яркая луна
	_v7_goto(GameState.DEFAULT_SPAWN)
	day.set_time(1230.0)
	var md: Vector3 = day.moon_dir()
	_look_at_point(Vector3(30, 0, -30), Vector3(0, 9, 8))
	await _wait(0.8)
	await _save_shot("v07_night_moon.png")
	day.set_time(500.0)
	# 9. Кровать (поставленная) + вопрос «под подушкой»
	var bedc := Vector3i(-8, 0, -6)
	for rn in get_tree().get_nodes_in_group("reagent") + get_tree().get_nodes_in_group("pickup"):
		if rn is Node3D and (rn as Node3D).global_position.distance_to(Vector3(-8, 0, -6)) < 9.0:
			rn.queue_free()
	_v7_put(bedc, "bed")
	GameState.add_to_pillow("heal1", 3)
	GameState.add_to_pillow("torch", 2)
	var bfrom2 := Vector3(-7.5, 0.05, -3.4)
	_v7_goto(bfrom2)
	_look_at_point(Vector3(-7.5, -1.1, -5.6), bfrom2)
	await _wait(0.6)
	await _save_shot("v07_bed.png")
	var la: Dictionary = player.get_look_ray()
	print("SHOT07 bed aim ", la, " col_groups=", (la["collider"] as Node).get_groups() if la.get("hit", false) else [], " layer=", (la["collider"] as CollisionObject3D).collision_layer if la.get("hit", false) else -1)
	report["bed_prompt"] = hud.bed_prompt_visible() if hud and hud.has_method("bed_prompt_visible") else false
	await _save_shot("v07_pillow_prompt.png")
	switcher.open_pillow()
	await _wait(0.3)
	await _save_shot("v07_pillow_chest.png")
	for p in get_tree().get_nodes_in_group("pillow_ui"):
		p.take(0)
	await _wait(0.2)
	await _save_shot("v07_pillow_taken.png")
	for p2 in get_tree().get_nodes_in_group("pillow_ui"):
		p2.close()
	# 10. Хилка: перезарядка и HP
	GameState.player_hp = 55
	GameState.player_hp_changed.emit(55, 100)
	GameState.add_item_count("heal1", 1)
	GameState.use_heal()
	await _wait(1.2)
	await _save_shot("v07_heal_cooldown.png")
	report["heal"] = hud.heal_indicator_state() if hud and hud.has_method("heal_indicator_state") else {}
	# 11. Меч2 в руке
	_v7_select("sword2")
	_look_at_point(Vector3(8, 0.5, 20), Vector3(2, 1.0, 10))
	await _wait(0.5)
	await _save_shot("v07_sword2_hand.png")
	# 12. Станок: модель и UI
	var lc := Vector3i(-3, 0, 3)
	_v7_put(lc, "lathe")
	_v7_put(Vector3i(-5, 0, 3), "workbench")
	var lfrom := Vector3(-3.5, 0.05, 6.4)
	_look_at_point(Vector3(-3.5, 0.4, 3.5), lfrom)
	await _wait(0.5)
	await _save_shot("v07_lathe_model.png")
	GameState.add_item_count("sword", 1)
	for cm in get_tree().get_nodes_in_group("craft_menu"):
		cm.open_lathe()
	await _wait(0.3)
	await _save_shot("v07_lathe_ui.png")
	for cm2 in get_tree().get_nodes_in_group("craft_menu"):
		cm2.close()
	# 13. Инвентари яви и сна
	if hud and hud.inventory:
		hud.inventory.open()
		await _wait(0.3)
		await _save_shot("v07_inventory_wake.png")
		hud.inventory.close()
		switcher.enter_dream()
		await _wait(0.6)
		hud.inventory.open()
		await _wait(0.3)
		await _save_shot("v07_inventory_dream.png")
		hud.inventory.close()
		switcher.wake_up()
		await _wait(0.6)
	# 14. Меню смерти
	_v7_goto(Vector3(6.5, 0.1, 9.5))
	GameState.player_hp = 1
	GameState._iframes = 0.0
	GameState.damage_player(5, "test")
	await _wait(0.5)
	await _save_shot("v07_death_menu.png")
	respawn()
	await _wait(0.4)
	print("SHOT07 report ", report)
	get_tree().quit(0)


func _capture_inventory_mockup() -> void:
	await _wait(2.0)
	GameState.day_time = 840.0
	_v7_goto(Vector3(6.5, 0.1, 9.5))
	_look_at_point(Vector3(2, 1.0, 10), Vector3(6.5, 0.1, 9.5))
	var inv = get_tree().get_first_node_in_group("inventory_ui")
	inv.open()
	await _wait(0.5)
	await _save_shot("mock_inv_wake.png")
	inv.close()
	switcher.enter_dream()
	await _wait(0.6)
	inv.open()
	await _wait(0.5)
	await _save_shot("mock_inv_dream.png")
	inv.close()
	get_tree().quit(0)


func _capture_v08() -> void:
	await _wait(2.0)
	GameState.day_time = 840
	GameState.tutorial_enabled = true
	_v7_goto(Vector3(6.5,0.1,9.5))
	_look_at_point(Vector3(2,1,10),Vector3(6.5,0.1,9.5))
	var inv = get_tree().get_first_node_in_group("inventory_ui")
	inv.open()
	await _wait(0.4)
	await _save_shot("v08_inventory_wake.png")
	inv.close()
	switcher.enter_dream()
	await _wait(0.5)
	inv.open()
	await _wait(0.4)
	await _save_shot("v08_inventory_dream.png")
	inv.close()
	var menu = get_tree().get_first_node_in_group("craft_menu")
	menu.open_general()
	await _wait(0.4)
	await _save_shot("v08_dream_craft.png")
	menu.close()
	switcher.wake_up()
	await _wait(0.4)
	GameState.add_to_pillow("heal1",2)
	switcher.open_pillow()
	await _wait(0.4)
	await _save_shot("v08_pillow_close.png")
	var pil = get_tree().get_first_node_in_group("pillow_ui")
	var e := InputEventAction.new()
	e.action = "pillow_check"
	e.pressed = true
	pil._input(e)
	await _wait(0.2)
	assert(not GameState.pillow_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	# Очистить только деревья вокруг постановочной UI-площадки (не обычный игровой запуск).
	var clear_cells := []
	for coord in wake_chunks._solid_by_chunk:
		for c in wake_chunks._solid_by_chunk[coord]:
			if wake_chunks._solid_by_chunk[coord][c] in ["log","leaves"] and c.x >= -12 and c.x <= 20 and c.z >= 0 and c.z <= 16:
				clear_cells.append(c)
	_v7_dig(clear_cells)
	var bc := Vector3i(5,0,5)
	var cc := Vector3i(4,0,5)
	for pair in [[bc,"bed"],[cc,"idea_catcher"],[Vector3i(2,0,5),"chest"],[Vector3i(0,0,5),"sawmill"],[Vector3i(1,0,5),"workbench"],[Vector3i(-2,0,5),"alchemy"],[Vector3i(-4,0,5),"door"],[Vector3i(-6,0,5),"lathe"]]:
		_v7_put(pair[0],pair[1])
	wake_voxels._rebuild_from_state()
	_look_at_point(Vector3(0,0.8,5.5),Vector3(1,2,12))
	await _wait(0.5)
	await _save_shot("v08_stations.png")
	_look_at_point(Vector3(5.5,0.3,6),Vector3(7,1.0,9))
	await _wait(0.4)
	await _save_shot("v08_bed_two_blocks.png")
	_look_at_point(Vector3(4.5,0.8,5.5),Vector3(6.5,1.0,8.5))
	await _wait(0.4)
	await _save_shot("v08_idea_catcher.png")
	var st = get_tree().get_first_node_in_group("storage_ui")
	GameState.storage_slots(cc)[0] = {"id":"stone","count":99}
	GameState.storage_slots(cc)[1] = {"id":"leaves","count":100}
	GameState.catcher_eat(cc)
	st.open(cc,true)
	await _wait(0.4)
	await _save_shot("v08_idea_storage_wake.png")
	st.close()
	switcher.enter_dream()
	await _wait(0.5)
	st.open(cc,true)
	await _wait(0.4)
	await _save_shot("v08_idea_storage_dream.png")
	st.close()
	switcher.wake_up()
	await _wait(0.5)
	GameState.storage_slots(Vector3i(2,0,5))[0] = {"id":"planks","count":32}
	st.open(Vector3i(2,0,5),false)
	await _wait(0.4)
	await _save_shot("v08_chest.png")
	st.close()
	menu.open_station("sawmill",true)
	await _wait(0.4)
	await _save_shot("v08_sawmill_recipes.png")
	menu.close()
	menu.open_station("alchemy")
	await _wait(0.4)
	await _save_shot("v08_alchemy_recipe.png")
	menu.close()
	menu.open_lathe()
	await _wait(0.4)
	await _save_shot("v08_lathe_pickaxe2.png")
	menu.close()
	_look_at_point(Vector3(-3.5,0.9,5.5),Vector3(-3.5,0.2,8))
	await _wait(0.4)
	await _save_shot("v08_door_closed.png")
	GameState.toggle_door(Vector3i(-4,0,5))
	await _wait(0.4)
	await _save_shot("v08_door_open.png")
	for id in ["pickaxe","pickaxe2","sword","sword2"]:
		_v7_select(id)
		GameState.item_slots[GameState.selected_slot]["durability"] = 35 if not id.ends_with("2") else 175
		GameState.inventory_changed.emit()
		await _wait(0.3)
		await _save_shot("v08_"+id+"_hand.png")
	_v7_goto(Vector3(53,15,40))
	player.flying = true
	_look_at_point(Vector3(40,1,24),Vector3(53,15,40))
	await _wait(0.5)
	await _save_shot("v08_settlement.png")
	# Материалы глубины и падение дропа на демонстрационном стенде.
	_v7_goto(Vector3(8,0.1,12))
	player.flying = false
	for pair in [[Vector3i(8,0,8),"ground"],[Vector3i(9,0,8),"stone"],[Vector3i(10,0,8),"deep_stone"],[Vector3i(11,0,8),"mossy_ruin"]]:
		_v7_put(pair[0],pair[1])
	_look_at_point(Vector3(10,0.4,8.5),Vector3(10,0.5,12))
	await _wait(0.4)
	await _save_shot("v08_stone_layers.png")
	var drop: CharacterBody3D = load("res://scripts/block_pickup.gd").new()
	drop.configure("stone")
	drop.position = Vector3(10,3,8)
	_look_at_point(Vector3(10,2,8),Vector3(10,0.6,13))
	wake_world.add_child(drop)
	await _wait(0.2)
	await _save_shot("v08_falling_drop.png")
	# Шов и маяк: постановочная иллюстрация самого эффекта (защита отдельно тестируется).
	_v7_put(Vector3i(11,0,5),"beacon")
	_look_at_point(Vector3(10,1,5),Vector3(11,0.5,10))
	load("res://scripts/seam_effect.gd").spawn(wake_world,Vector3(9,0.2,5))
	await _wait(0.16)
	await _save_shot("v08_seam_beacon.png")
	# Разные уровни текучей воды на стенде.
	var cells := []
	for x in range(13,18):
		for z in range(5,8):
			cells.append(Vector3i(x,-1,z))
	_v7_dig(cells)
	for x in range(13,18):
		wake_chunks._water_set(Vector3i(x,0,6),8-(x-13))
	wake_chunks._rebuild_water_meshes()
	_look_at_point(Vector3(15,0.2,6.5),Vector3(16,0.5,10))
	await _wait(0.1)
	await _save_shot("v08_water_sides.png")
	print("SHOT08 complete")
	get_tree().quit(0)

func _want_shots09() -> bool:
	return "--shots09" in OS.get_cmdline_user_args() or "--shots091" in OS.get_cmdline_user_args() or "--door-shots" in OS.get_cmdline_user_args()

func _v09_camera(at: Vector3,from: Vector3) -> void:
	_v7_goto(from)
	player.set_physics_process(false)
	player.camera.look_at(at,Vector3.UP)

func _capture_v09() -> void:
	if "--door-shots" in OS.get_cmdline_user_args():
		await _capture_v091_door()
		return
	if "--shots091" in OS.get_cmdline_user_args():
		await _capture_v091()
		return
	await _wait(1.0)
	var console := get_tree().get_first_node_in_group("dev_console")
	console.execute("god")
	console.execute("time day")
	GameState.tutorial_enabled = false
	# Real landscape with linear fog and seed-determined grass tint.
	_v09_camera(Vector3(35,0,13),Vector3(49,14,35))
	await _wait(1.5)
	await _save_shot("v09_fog_landscape.png")
	_v09_camera(Vector3(6,-0.05,7),Vector3(9,4,14))
	await _wait(0.4)
	await _save_shot("v09_grass_tint.png")
	# Clear only the screenshot stage, never normal worlds / saves.
	console.execute("fill air -3 0 4 8 7 13")
	console.execute("fill stone 2 0 8 2 1 8")
	_v09_camera(Vector3(2.5,1.5,8.5),Vector3(2.5,0.0,12))
	_v7_select("pickaxe")
	build._update_hand_tools()
	await _wait(0.4)
	await _save_shot("v09_pickaxe_wood.png")
	build.set_process(false)
	build._mine_elapsed = 0.0
	build._tick_mining(1.05)
	await _wait(0.1)
	await _save_shot("v09_cracks_03.png")
	build._tick_mining(1.4)
	await _wait(0.1)
	await _save_shot("v09_cracks_08.png")
	build.cracks.hide()
	_v7_select("pickaxe2")
	build._update_hand_tools()
	await _wait(0.35)
	await _save_shot("v09_pickaxe_stone.png")
	_v7_select("sword")
	build._update_hand_tools()
	await _wait(0.1)
	GameState.toast.emit("Название предмета больше не закрывает HP")
	await _save_shot("v09_hud_name_hp.png")
	get_node("HUD")._toast_t = 0.0
	console.execute("armor give wood")
	GameState.armor[0].durability = 90
	GameState.inventory_changed.emit()
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	inv.open()
	await _wait(0.3)
	await _save_shot("v09_armor_wake.png")
	inv.close()
	var craft := get_tree().get_first_node_in_group("craft_menu")
	craft.open_station("sawmill",true)
	await _wait(0.3)
	await _save_shot("v09_wood_armor_recipes.png")
	craft.close()
	console.execute("armor give scale")
	console.execute("world dream")
	player.set_physics_process(false)
	build._update_hand_tools()
	inv.open()
	await _wait(0.4)
	await _save_shot("v09_armor_dream.png")
	inv.close()
	console.execute("world wake")
	craft.open_lathe()
	await _wait(0.3)
	await _save_shot("v09_scale_armor_recipes.png")
	craft.close()
	_v09_camera(Vector3(2.5,1.5,8.5),Vector3(2.5,0,12))
	console.execute("setblock torch 5 0 8")
	console.execute("fill planks 10 0 8 12 1 10")
	console.execute("spawn enemy1")
	console.execute("sword2 on")
	console.execute("mob hp 188 all")
	await _wait(0.2)
	assert(console.open())
	console.execute("help")
	console.entry.text = "fill stone 3"
	await _wait(0.4)
	await _save_shot("v09_console.png")
	console.close()
	console.execute("kill all")
	console.execute("moon 0.47")
	console.execute("time night")
	_v09_camera(Vector3(-7,1.5,0),Vector3(4,0,18))
	await _wait(0.4)
	await _save_shot("v09_moon047.png")
	print("SHOT09 complete")
	get_tree().quit(0)

func _capture_v091() -> void:
	await _wait(1.0)
	var console := get_tree().get_first_node_in_group("dev_console")
	console.execute("god")
	console.execute("time day")
	GameState.tutorial_enabled = false
	console.execute("fill air -3 0 4 8 7 13")
	console.execute("fill stone 2 0 8 2 1 8")
	_v09_camera(Vector3(2.5,1.4,8.5),Vector3(2.5,0.0,11.3))
	build.set_process(false)
	_v7_select("pickaxe")
	build._update_hand_tools()
	await _wait(0.5)
	await _save_shot("v091_pickaxe_held_wood.png")
	_v7_select("pickaxe2")
	build._update_hand_tools()
	await _wait(0.35)
	await _save_shot("v091_pickaxe_held.png")
	# Actual mining-clock driven progress, not a screenshot-only textured prop.
	build._mine_elapsed = 0.0
	build._tick_mining(1.1)
	await _wait(0.2)
	await _save_shot("v091_cracks_ingame.png")
	_v09_camera(Vector3(2.5,1.5,8.5),Vector3(4.7,3.0,11.6))
	build._hand_root.hide()
	await _wait(0.2)
	await _save_shot("v091_cracks_corner.png")
	build.cracks.hide()
	console.execute("time night")
	await _wait(0.2)
	await _save_shot("v091_moon056.png")
	print("SHOT091 complete")
	get_tree().quit(0)

func _capture_v091_door() -> void:
	await _wait(1.0)
	var console := get_tree().get_first_node_in_group("dev_console")
	console.execute("god")
	console.execute("time day")
	GameState.tutorial_enabled = false
	console.execute("fill air -3 0 4 10 6 13")
	console.execute("fill stone 1 0 8 3 2 8")
	console.execute("fill air 2 0 8 2 1 8")
	console.execute("setblock door 2 0 8")
	_v09_camera(Vector3(2.5,1.0,8.5),Vector3(3.6,-0.25,10.9))
	build.set_process(false)
	build._hand_root.hide()
	await _wait(0.5)
	await _save_shot("v091_door_closed.png")
	console.execute("door toggle 2 0 8")
	await _wait(0.4)
	await _save_shot("v091_door_open.png")
	console.execute("door toggle 2 0 8")
	_v09_camera(Vector3(2.5,1.0,8.5),Vector3(0.7,0,5.2))
	await _wait(0.3)
	await _save_shot("v091_door_back.png")
	console.execute("setblock door 7 0 8")
	console.execute("door rotate 7 0 8")
	_v09_camera(Vector3(7.5,1.0,8.5),Vector3(11.2,0.0,10))
	await _wait(0.3)
	await _save_shot("v091_door_rotated.png")
	print("DOOR SHOTS complete")
	get_tree().quit(0)


# --- v0.11: стартовый «разрушенный лагерь» вокруг первой кровати ---

const CAMP_BED := Vector2i(0, -3)


static func camp_layout() -> Array:
	## [x, z, height, kind] — П-образные руины 11×8 с проломами; открыты в сторону спавна (+Z).
	var out: Array = []
	for x in range(-5, 6):
		if x in [-1, 2]: continue
		out.append([x, -8, 2 if (x * 7) % 3 != 0 else 1, "mossy_ruin" if (x + 8) % 3 == 0 else "ruin"])
	for z in range(-7, 0):
		if z != -4: out.append([-5, z, 2 if z < -5 else 1, "ruin" if z % 2 == 0 else "mossy_ruin"])
		if z != -2: out.append([5, z, 1 if z > -6 else 2, "mossy_ruin" if z % 2 == 0 else "ruin"])
	return out


func _build_starter_camp() -> void:
	if GameState.starter_camp_built or wake_chunks == null or not wake_chunks.has_method("height_at"):
		return
	GameState.starter_camp_built = true
	var placed := 0
	for e in camp_layout():
		var x: int = e[0]
		var z: int = e[1]
		if wake_chunks.has_method("_world_is_lake_cell") and wake_chunks._world_is_lake_cell(x, z):
			continue
		var top: int = int(wake_chunks.height_at(x, z))
		for h in range(int(e[2])):
			var c := Vector3i(x, top + 1 + h, z)
			if GameState.place_wake_block(c, str(e[3])):
				GameState.wake_blocks[c]["camp"] = true
				wake_voxels.add_block(c, GameState.wake_blocks[c])
				placed += 1
	for t in [Vector2i(-4, -7), Vector2i(4, -7), Vector2i(2, -1)]:
		var tc := Vector3i(t.x, int(wake_chunks.height_at(t.x, t.y)) + 1, t.y)
		if GameState.place_wake_block(tc, "torch"):
			GameState.wake_blocks[tc]["camp"] = true
			wake_voxels.add_block(tc, GameState.wake_blocks[tc])
	if wake_voxels.has_method("flush_dirty"):
		wake_voxels.flush_dirty()
	set_meta("camp_blocks", placed)


func _camp_label() -> void:
	if not GameState.starter_camp_built or wake_chunks == null or not wake_chunks.has_method("height_at"):
		return
	var has_camp := false
	for c in GameState.wake_blocks:
		if GameState.wake_blocks[c].get("camp", false):
			has_camp = true
			break
	if not has_camp:
		return
	var l := Label3D.new()
	l.name = "CampSign"
	l.text = "Разрушенный лагерь сновидца\nЛяг на кровать — во Сне можно построить невозможное"
	l.font_size = 40
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.85, 0.9, 1.0, 0.9)
	l.outline_size = 8
	l.position = Vector3(0.5, float(wake_chunks.height_at(0, -8)) + 3.6, -7.5)
	wake_world.add_child(l)
