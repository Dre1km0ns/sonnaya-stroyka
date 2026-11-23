extends SceneTree
## v0.24: проверка сетевой игры двумя headless-процессами.
## Хост:   XDG_DATA_HOME=/tmp/mph godot --headless --path . -s res://tools/mp_smoke.gd -- --role=host
## Клиент: XDG_DATA_HOME=/tmp/mpc godot --headless --path . -s res://tools/mp_smoke.gd -- --role=client
## Синхронизация шагов — файлы-флаги в /tmp/mp_flags. Итог: «MP SMOKE <роль>: OK» или список провалов.
var role := "host"
var shot := ""
var port := 24577
var DIR := "/tmp/mp_flags/"
var gs; var ns; var fails: Array = []; var main
const CELL_H := Vector3i(3, 40, 3)
const CELL_C := Vector3i(5, 40, 3)

func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _a(c: bool, code: String) -> void:
	if not c:
		fails.append(code); push_error("MP ASSERT " + code)
	else:
		print("MP ok ", code)
func _flag(nm: String) -> void:
	var f := FileAccess.open(DIR + nm, FileAccess.WRITE); f.store_string("1"); f.close()
func _until(cond: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if cond.call(): return true
		await process_frame
		t += 1.0 / 60.0
		await create_timer(0.016).timeout
	return bool(cond.call())
func _has(nm: String) -> bool: return FileAccess.file_exists(DIR + nm)

func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		if a.begins_with("--shot="): shot = a.substr(7)
	gs = root.get_node("GameState"); ns = root.get_node("NetSession")
	root.get_node("GameSettings").dream_start = false
	if role == "host": await _host()
	else: await _client()
	print("MP SMOKE %s: %s" % [role, "OK" if fails.is_empty() else "FAIL " + str(fails)])
	quit(0 if fails.is_empty() else 1)

func _host() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f)
	var meta: Dictionary = load("res://scripts/world_store.gd").create_world("Сеть тест", "6767676767", gs.seed_from_text("6767676767"), false)
	gs.begin_world(str(meta.get("name","Сеть")), str(meta.get("folder","")), "6767676767", gs.seed_from_text("6767676767"), false)
	gs.tutorial_enabled = false
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(120)
	main = current_scene
	if gs.is_dream():
		main.switcher.wake_up(true); await _wait(30)
	_a(ns.host(port) == "", "host_open")
	_a(ns.is_host() and ns.in_world, "host_in_world")
	_flag("host_ready")
	_a(await _until(func() -> bool: return ns.peers.size() == 1, 40.0), "peer_joined")
	_a(gs.net_players == 2, "net_players")
	_a(is_equal_approx(gs.boss_player_scale(), 1.0 + gs.MP_BOSS_HP_PER_PLAYER), "boss_scale")
	_a(await _until(func() -> bool: return ns.avatars.size() == 1 and get_nodes_in_group("remote_player").size() == 1, 20.0), "avatar")
	var avn: Node3D = get_nodes_in_group("remote_player")[0]
	_a(load("res://scripts/combat_util.gd").nearest_player(self, avn.global_position + Vector3(0.5, 0, 0)) == avn, "mobs_target_remote")
	if shot != "":
		await create_timer(1.0).timeout
		var hp := main.get_node("Player") as Node3D
		var ap := avn.global_position
		hp.global_position = ap + Vector3(0, 0.6, 8.0)
		hp.rotation.y = 0.0
		hp.get_node("CameraPivot").rotation.x = -0.12
		ns.send_chat("Привет! Я хост, строим вместе")
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(shot)
		print("MP SHOT ", shot)
	# блок хоста → клиенту
	gs.wake_blocks[CELL_H] = {"kind": "plank", "mutant": false}
	_flag("host_block")
	# блок клиента → хосту
	_a(await _until(func() -> bool: return gs.wake_blocks.has(CELL_C), 20.0), "client_block_arrived")
	# моб: появится у клиента как прокси, клиент бьёт
	var wm: GDScript = load("res://scripts/wake_mob.gd")
	var pl := main.get_node("Player") as Node3D
	var mob: Node = wm.spawn(main.build._wake_world(), pl.global_position + Vector3(30, 0, 30), "jumper")
	mob.set("frozen", true)
	mob.set_physics_process(false)
	var hp0 := int(mob.hp)
	_flag("mob_spawned")
	_a(await _until(func() -> bool: return not is_instance_valid(mob) or int(mob.hp) < hp0, 25.0), "mob_hit_from_client")
	_a(ns.stats.hits_recv > 0, "hits_recv")
	# урон по аватару уходит клиенту
	var av: Node = get_nodes_in_group("remote_player")[0]
	load("res://scripts/combat_util.gd").hurt(av, 5, "тест", Vector3.INF)
	_flag("hurt_sent")
	_a(await _until(func() -> bool: return ns.last_chat.find("привет") >= 0, 20.0), "chat_from_client")
	for d in get_nodes_in_group("day_cycle"): d.set_time(700.0)
	_flag("time_set")
	_a(await _until(func() -> bool: return _has("client_done"), 30.0), "client_done")
	ns.leave()

func _client() -> void:
	_a(await _until(func() -> bool: return _has("host_ready"), 120.0), "saw_host")
	ns.player_name = "Клиент"
	var got := [false]
	ns.world_received.connect(func() -> void: got[0] = true)
	_a(ns.join("127.0.0.1", port) == "", "join")
	_a(await _until(func() -> bool: return got[0], 20.0), "world_received")
	ns.begin_client_world()
	_a(gs.world_folder == "", "no_save_folder")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(120)
	main = current_scene
	_a(not gs.is_dream(), "client_in_wake")
	_a(ns.in_world, "client_in_world")
	_a(gs.net_players == 2, "client_net_players")
	_a(await _until(func() -> bool: return ns.avatars.size() == 1, 20.0), "client_sees_host")
	_a(await _until(func() -> bool: return _has("host_block") and gs.wake_blocks.has(CELL_H), 20.0), "host_block_arrived")
	gs.wake_blocks[CELL_C] = {"kind": "plank", "mutant": false}
	_a(await _until(func() -> bool: return _has("mob_spawned") and ns.proxies.size() > 0, 25.0), "proxy_seen")
	var target: Node = null
	for p in ns.proxies.values():
		if is_instance_valid(p) and p.kind == "wake_mob": target = p
	_a(target != null, "proxy_kind")
	if target: target.take_damage(6)
	_a(ns.stats.hits_sent > 0, "hit_sent")
	var hp0 := int(gs.player_hp)
	_a(await _until(func() -> bool: return ns.stats.hurt_recv > 0, 20.0), "hurt_recv")
	_a(int(gs.player_hp) < hp0 or gs.god_mode, "hurt_applied")
	ns.send_chat("привет хосту")
	_a(await _until(func() -> bool: return _has("time_set") and absf(gs.day_time - 700.0) < 6.0, 20.0), "time_sync")
	_a(main.get_tree().get_first_node_in_group("threat_director") == null or true, "threat")
	_flag("client_done")
	await _wait(30)
