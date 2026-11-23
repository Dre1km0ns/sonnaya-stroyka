extends SceneTree
## v0.24 (п.22): бот баланса — настоящие боссы в настоящей сцене, бой настоящим ударом build._try_sword().
## godot --headless --fixed-fps 60 --path . -s res://tools/v024_balance.gd -- [--only=mother|anaconda|burger] [--runs=1]
## Бот: кружит вокруг цели на дистанции удара (уклонение = только движение по кругу, без чтения телеграфов),
## бьёт мечом каждые 0.5 с, по слабым точкам Бургера стреляет из лука (70 % попаданий, 1 выстрел / 1.2 с),
## против Анаконды держит факел в руке. Урон считается по падению HP; ниже 35 HP — «выпил зелье» (HP до максимума).
## Итог: время боя, урон по игроку в минуту, зелий за бой — для Нормального и Эксперта. Пишет benchmarks/v024_balance.json.
var gs; var main; var player; var build
var only := ""
var rows: Array = []
const LIMIT := 600.0

func _init() -> void: call_deferred("_go")
func _f() -> void: await physics_frame

func _go() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
	root.get_node("GameSettings").dream_start = false
	var meta: Dictionary = load("res://scripts/world_store.gd").create_world("Баланс", "баланс", 424242, false)
	gs = root.get_node("GameState")
	gs.begin_world(str(meta.get("name", "Баланс")), str(meta.get("folder", "")), "баланс", 424242, false)
	gs.tutorial_enabled = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150: await process_frame
	main = current_scene; player = main.get_node("Player"); build = main.build
	if gs.is_dream():
		main.switcher.wake_up(true)
		for i in 60: await process_frame
	gs.skip_tutorial()
	for boss in ["mother", "anaconda", "burger"]:
		if only != "" and only != boss: continue
		for diff in ["normal", "expert"]:
			rows.append(await _fight(boss, diff))
	var f := FileAccess.open("res://benchmarks/v024_balance.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  ")); f.close()
	for r in rows:
		print("BALANCE %-8s %-6s %-7s бой %5.1f с · урон/мин %5.1f · зелий %d · ударов %d · HP босса %d" % [r.boss, r.diff, r.end, r.t, r.dmg_per_min, r.potions, r.swings, r.max_hp])
	print("BALANCE DONE")
	root.get_node("GameSettings").safe_quit(0)

func _give(slot: int, id: String, n: int) -> void:
	gs.set_slot(slot, {"id": id, "name": id, "count": n})

func _fight(kind: String, diff: String) -> Dictionary:
	gs.set_difficulty(diff)
	var vs := get_first_node_in_group("victory_screen")
	if vs and vs.has_method("close"): vs.close()
	paused = false
	for i in 10: await process_frame
	gs.god_mode = false
	gs.heal_player_full()
	gs.mother_defeated = false; gs.anaconda_defeated = false; gs.burger_defeated = false
	# ожидаемое снаряжение к этому боссу: Мать — Меч2, Бургер — металлический меч + металлический лук
	_give(0, "sword2" if kind == "mother" else "metal_sword", 1); _give(1, "torch", 64); _give(2, "bow2", 1); _give(3, "arrow2", 64)
	gs.select_item_slot(0); build._update_hand_tools()
	var host: Node3D = main.wake_world
	var c: Vector3 = player.global_position + Vector3(20, 0, 20)
	var boss: Node
	match kind:
		"mother": boss = load("res://scripts/block_mother.gd").spawn_near(host, Vector3i(c))
		"anaconda": boss = load("res://scripts/boss_anaconda.gd").spawn_at(host, c, "console")
		"burger": boss = load("res://scripts/boss_burger.gd").spawn_at(host, c)
	var t := 0.0; var swing := 0.0; var shot := 0.0; var ang := 0.0
	var taken := 0; var potions := 0; var swings := 0; var deaths := 0
	var last_hp: int = int(gs.player_hp)
	var max_hp := 0
	var end := "timeout"
	if kind == "anaconda":
		gs.select_item_slot(1); build._update_hand_tools()
	# Анаконда уходит с рассветом — бой ночью (23:00)
	if kind == "anaconda":
		for d in get_nodes_in_group("day_cycle"): d.set_time(fposmod(23.0 - 6.0, 24.0) * 60.0)
	while t < LIMIT:
		await _f()
		t += 1.0 / 60.0
		if paused:
			var vs2 := get_first_node_in_group("victory_screen")
			if vs2 and vs2.has_method("close"): vs2.close()
			paused = false
		var won: bool = (kind == "mother" and gs.mother_defeated) or (kind == "anaconda" and gs.anaconda_defeated) or (kind == "burger" and gs.burger_defeated)
		if not is_instance_valid(boss) or boss.is_queued_for_deletion():
			end = "killed" if won else "gone"; break
		if "max_hp" in boss: max_hp = maxi(max_hp, int(boss.max_hp))
		if "state" in boss and fmod(t, 30.0) < 1.0 / 60.0: print("BALANCE dbg ", kind, " t=", int(t), " state=", boss.state, " hp=", boss.get("hp"), " phase=", boss.get("phase"), " vis=", (boss as Node3D).visible)
		if (kind == "mother" and gs.mother_defeated) or (kind == "anaconda" and gs.anaconda_defeated) or (kind == "burger" and gs.burger_defeated):
			end = "killed"; break
		# цель: центр удара босса (у Анаконды — голова)
		var tgt: Vector3 = boss.hit_center() if boss.has_method("hit_center") else (boss as Node3D).global_position
		if kind == "anaconda" and boss.get("_head") != null:
			tgt = (boss._head as Node3D).global_position
		var r := 3.4 if kind != "burger" else (5.2 if int(boss.phase) > 1 else 3.0)
		ang += (1.0 / 60.0) * 0.9
		var want := Vector3(tgt.x + cos(ang) * r, player.global_position.y, tgt.z + sin(ang) * r)
		var step: Vector3 = want - player.global_position; step.y = 0
		if step.length() > 0.2:
			player.global_position += step.normalized() * minf(step.length(), 9.0 / 60.0) if step.length() < 12.0 else step
		var to: Vector3 = tgt - player.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		# HP
		var hp: int = int(gs.player_hp)
		if hp < last_hp: taken += last_hp - hp
		if hp <= 0:
			deaths += 1
			var dm := get_first_node_in_group("death_menu")
			if dm and dm.has_method("_respawn"): dm._respawn()
			gs.heal_player_full()
		elif hp < 35:
			potions += 1; gs.heal_player_full()
		last_hp = gs.player_hp
		# атаки
		swing -= 1.0 / 60.0; shot -= 1.0 / 60.0
		if kind == "burger" and int(boss.phase) == 1:
			if shot <= 0.0:
				shot = 1.2
				for wp in boss._weak:
					if is_instance_valid(wp) and int(wp.hp) > 0:
						if randf() < 0.7: wp.hit_by_arrow(16, null)
						break
		if swing <= 0.0 and kind != "anaconda":
			swing = 0.5
			gs.select_item_slot(0)
			build._try_sword(); swings += 1
			if kind == "burger":
				for cl in get_nodes_in_group("burger_clown"):
					if is_instance_valid(cl) and (cl as Node3D).global_position.distance_to(player.global_position) < 4.5:
						cl.take_damage(30)
	if is_instance_valid(boss): boss.queue_free()
	for g in ["burger_clown", "enemy"]:
		for n in get_nodes_in_group(g): n.queue_free()
	for i in 30: await process_frame
	var guard := 0
	while (get_nodes_in_group("block_mother").size() + get_nodes_in_group("anaconda").size() + get_nodes_in_group("boss").size()) > 0 and guard < 600:
		for n in get_nodes_in_group("block_mother") + get_nodes_in_group("anaconda") + get_nodes_in_group("boss"): n.queue_free()
		await process_frame; guard += 1
	var res := {"boss": kind, "diff": diff, "end": end, "t": snappedf(t, 0.1), "taken": taken, "dmg_per_min": snappedf(taken / maxf(t / 60.0, 0.01), 0.1),
		"potions": potions, "deaths": deaths, "swings": swings, "max_hp": max_hp}
	print("BALANCE row ", JSON.stringify(res))
	return res
