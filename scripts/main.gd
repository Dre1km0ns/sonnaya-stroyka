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
	if _want_shots06():
		GameState.begin_world("Скриншоты v0.6", "", "6767676767", GameState.DEV_SEED, false)
	elif _want_shots05():
		GameState.begin_world("Скриншоты", "", "6767676767", GameState.DEV_SEED, true)
	elif GameState.world_folder == "" and not _want_shots() and not _want_perf():
		# Сцену запустили напрямую (F6 в редакторе) — временный мир без сохранения.
		GameState.begin_world("", "", "1337", 1337, false)
	elif _want_perf() and GameState.world_folder == "":
		GameState.begin_world("", "", "1337", 1337, false)
	build.setup(player, dream_voxels)
	anchors.setup(player, dream_voxels)
	switcher.setup(player, wake_world, dream_world, bed, wake_voxels, dream_voxels)
	threat.setup(player, wake_world, bed)
	saver.setup(self, player, wake_voxels, dream_voxels, threat)
	var loaded := false
	if not _want_shots() and saver.has_save():
		loaded = saver.load_game()
	if not loaded:
		if wake_chunks and wake_chunks.has_method("setup"):
			wake_chunks.setup(player, GameState.world_seed_wake)
		if dream_chunks and dream_chunks.has_method("setup"):
			dream_chunks.setup(player, GameState.world_seed_dream)
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
	_apply_settings()
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		gsets.settings_changed.connect(_apply_settings)
	_start_music()
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	if _want_shots06():
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
	print("Сонная стройка v0.6 ready. world=%s seed=%d dev=%s" % [GameState.world_folder, GameState.world_seed, GameState.dev_mode])


func _on_player_died() -> void:
	## v0.6: смерть — возрождение у кровати с полным HP, штраф: до 3 ресурсов; босс уходит (как в Terraria).
	for b in get_tree().get_nodes_in_group("block_mother"):
		if b.has_method("leave"):
			b.leave("Мать блоков потеряла к тебе интерес и ушла под землю.")
	var lost := GameState.steal_resource_hardcore(3)
	player.global_position = Vector3(0, 2, 6)
	player.velocity = Vector3.ZERO
	GameState.heal_player_full()
	if lost != "none":
		GameState.chat("Потеряно при смерти: %s" % lost, Color(1.0, 0.6, 0.5))


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
	return "--shots" in args or "--shots05" in args or "--shots06" in args


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
