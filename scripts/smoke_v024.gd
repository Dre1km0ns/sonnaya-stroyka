extends RefCounted
## v0.24 смоук: коды 24001+. Зовётся из smoke_test._run.
var T: SceneTree
var fails: Array = []
var done := false
var G: Node


func _a(cond: Variant, code: int) -> void:
	if not bool(cond):
		fails.append(code)
		push_error("SMOKE ASSERT line %d" % code)


func _wait(n: int) -> void:
	for i in range(n): await T.process_frame


func run(tree: SceneTree) -> Array:
	T = tree
	G = T.root.get_node("GameState")
	var Gear := preload("res://scripts/gear.gd")
	var M := preload("res://scripts/mining_rules.gd")
	var Ore := preload("res://scripts/ore_rules.gd")
	# --- B: мечи, добыча любым предметом
	_a(is_equal_approx(Gear.sword_reach("sword"), 3.5) and is_equal_approx(Gear.sword_reach("sword3"), 4.5) and Gear.sword_reach("sword2") > 3.5 and Gear.sword_reach("metal_sword") > Gear.sword_reach("sword2"), 24001)
	_a(is_finite(M.seconds("stone", "stone")) and is_finite(M.seconds("dirt", "planks")), 24002)
	# --- C: руда только каменной киркой и лучше
	_a(is_inf(M.seconds("metal_ore", "")) and is_inf(M.seconds("metal_ore", "pickaxe")) and is_finite(M.seconds("metal_ore", "pickaxe2")) and M.seconds("metal_ore", "pickaxe3") < M.seconds("metal_ore", "pickaxe2"), 24003)
	_a(not M.drops("metal_ore", "pickaxe") and M.drops("metal_ore", "pickaxe2"), 24004)
	var ores := 0
	for x in range(-40, 40):
		for z in range(-40, 40):
			for y in range(-26, -6):
				if Ore.is_ore(Vector3i(x, y, z), 6767676767): ores += 1
	_a(ores > 200 and ores < 12000 and not Ore.is_ore(Vector3i(0, -3, 0), 1), 24005)
	print("SMOKE v024 ores in 80x80x20: %d" % ores)
	_a(G.find_recipe("metal_ingot").where == "lathe" and G.find_recipe("pickaxe3").items.has("metal_ingot") and G.find_recipe("bow").where == "workbench" and G.find_recipe("bow2").items.has("metal_ingot") and G.find_recipe("arrow2").items.has("milk_tooth"), 24006)
	_a(G.find_recipe("speed_potion").where == "alchemy" and G.find_recipe("burger_summoner").where == "alchemy" and G.find_recipe("burger_summoner").items.has("stone_heart") and G.find_recipe("burger_summoner").items.has("scale_fang"), 24007)
	_a(G.tool_max("pickaxe") < G.tool_max("pickaxe2") and G.tool_max("pickaxe2") < G.tool_max("pickaxe3") and G.ArmorRules.points("metal_chest") > G.ArmorRules.points("wood_chest") and G.ArmorRules.points("metal_chest") < G.ArmorRules.points("scale_chest"), 24008)
	for id in ["metal_ore", "metal_ingot", "pickaxe3", "metal_sword", "bow", "bow2", "arrow", "arrow2", "milk_tooth", "stone_heart", "scale_fang", "burger_summoner", "burger_core", "clown_nose", "grill_saucer", "burger_trophy", "speed_potion", "metal_helmet"]:
		_a(ResourceLoader.exists("res://assets/icons/%s.png" % id), 24009)
	# --- D: сложность
	G.reset_state()
	_a(G.difficulty == "normal" and is_equal_approx(G.diff_hp_mult(), 1.0), 24010)
	G.set_difficulty("expert")
	_a(is_equal_approx(G.diff_hp_mult(), 1.75) and G.diff_damage(20) > 20 and G.diff_speed() > 1.0 and G.diff_aggro() > 1.0 and G.diff_leash() > 1.0, 24011)
	var sv: Dictionary = JSON.parse_string(JSON.stringify(G.to_save_dict()))
	_a(str(sv.v024.difficulty) == "expert" and int(sv.version) == 18, 24012)
	G.reset_state()
	G.apply_save_dict(sv)
	_a(G.is_expert(), 24013)
	G.reset_state()
	var got := 0
	for i in range(2000):
		if G.roll_boss_token("mother") != "": got += 1
	_a(got > 560 and got < 840 and G.roll_boss_token("anaconda", 0.1) == "scale_fang" and G.roll_boss_token("mother", 0.5) == "", 24014)
	print("SMOKE: v0.24 rules OK")
	await _scene()
	done = true
	return fails


func _scene() -> void:
	G.begin_world("v024 test", "", "424242", 424242, false)
	var scene: Node = load("res://scenes/main.tscn").instantiate(); scene.set_meta("smoke", true); T.root.add_child(scene); T.current_scene = scene; scene.switcher.show_result_ui = false
	await _wait(3)
	G.dev_mode = false
	var build: Node = scene.build
	for i in range(G.ITEM_SLOT_COUNT): G.set_slot(i, {})
	G.set_slot(0, {"id": "stone", "name": "Камень", "count": 5}); G.select_item_slot(0)
	G.place_wake_block(Vector3i(0, 5, 0), "planks")
	_a(G.mine_wake_block(Vector3i(0, 5, 0)) and not G.wake_blocks.has(Vector3i(0, 5, 0)), 24015)
	var cm: Node = build._wake_chunks()
	var dc := Vector3i(3, -1, 3)
	var k: String = cm.terrain_kind_at(dc)
	build._mine_terrain_cell(dc, k if k != "" else "dirt")
	_a(G.is_terrain_removed(dc), 24016)
	G.set_slot(1, {"id": "sword", "name": "Меч", "count": 1}); G.select_item_slot(1)
	build._try_sword()
	_a(is_equal_approx(build.last_sword_reach, 3.5), 24017)
	G.set_slot(2, {"id": "sword3", "name": "Чешуйчатый меч", "count": 1}); G.select_item_slot(2)
	build._try_sword()
	_a(is_equal_approx(build.last_sword_reach, 4.5), 24018)
	G.set_slot(3, {"id": "pickaxe2", "name": "Каменная кирка", "count": 1}); G.select_item_slot(3)
	await _wait(2)
	var vm: Node = build.viewmodel
	_a(vm != null and vm.models.has("pickaxe2") and is_equal_approx(vm.models["pickaxe2"].rotation_degrees.y, 90.0), 24019)
	G.set_slot(4, {"id": "bow2", "name": "Металлический лук", "count": 1, "durability": G.tool_max("bow2")}); G.select_item_slot(4)
	G.set_slot(5, {"id": "arrow", "name": "Стрела", "count": 10})
	await _wait(2)
	_a(vm.current == "bow2", 24020)
	var arrow: Node = build.bow.fire("bow2", 1.0)
	_a(arrow != null and G.count_item("arrow") == 9 and build.bow.fire("bow2", 0.05) == null, 24021)
	var ppos: Vector3 = scene.player.global_position
	var e: CharacterBody3D = load("res://scripts/seam_creature.gd").new()
	scene.wake_world.add_child(e)
	e.global_position = ppos + Vector3(0, 30, -6)
	e.set_physics_process(false)
	await _wait(1)
	var hp0: int = e.hp
	build.bow.spawn_arrow(e.global_position + Vector3(0, 0.8, 3), Vector3(0, 0, -30), 12, "arrow", scene.player)
	await _wait(10)
	_a(not is_instance_valid(e) or e.hp < hp0, 24022)
	if is_instance_valid(e): e.queue_free()
	G.add_item_count("speed_potion", 1)
	G.stamina = 0.5
	_a(G.drink_speed_potion() and G.speed_potion_active(), 24023)
	G.tick_stamina(1.0, true)
	_a(G.stamina >= 0.5, 24024)
	G.speed_potion_t = 0.0
	G.tick_stamina(1.0, true)
	_a(G.stamina < 0.5, 24025)
	var liz: Node = load("res://scripts/lizard_minion.gd").spawn(scene.wake_world, ppos + Vector3(2, 0.5, 0))
	await _wait(2)
	_a(liz != null and liz.is_in_group("enemy"), 24026)
	if liz: liz.take_damage(999)
	await _wait(2)
	_a(G.lizards_killed >= 1, 24027)
	print("SMOKE: v0.24 scene B/C/D: block mining, reach, pick spin, bow+arrow hit, speed potion, lizards OK")
	await _burger(scene, ppos)
	var con: Node = T.get_first_node_in_group("dev_console")
	if con:
		G.dev_mode = true
		var ws: int = G.world_seed
		G.world_seed = G.DEV_SEED
		_a(str(con.execute("help burger")).contains("Бургер") and str(con.execute("difficulty")).contains("Нормальный") and con.completion_candidates("burger ").size() >= 8, 24043)
		G.dev_mode = false
		G.world_seed = ws
	for n in T.get_nodes_in_group("arrow"): n.queue_free()
	await _v024_more(scene)
	scene.queue_free(); await T.process_frame; T.current_scene = null; G.reset_state()


func _burger(scene: Node, ppos: Vector3) -> void:
	var bs: GDScript = load("res://scripts/burger_summon.gd")
	var sm: Node = bs.start(scene, 60.0)
	_a(sm != null and is_equal_approx(float(sm.left), 60.0), 24028)
	if sm == null: return
	sm.left = 0.01
	await _wait(3)
	var boss: Node = T.get_first_node_in_group("burger_boss")
	_a(boss != null and boss.max_hp >= 3500 and boss.max_hp <= 4500 and boss.boss_title() == "Бургер Смерти", 24029)
	if boss == null: return
	_a(boss.weak_points_alive() == 4, 24030)
	boss._enter(boss.S.HOVER)
	var h0: int = boss.hp
	for wp in boss._weak:
		wp.hit_by_arrow(999); break
	_a(boss.hp <= h0 - boss.WEAK_BONUS and boss.state == boss.S.STUNNED and boss.weak_points_alive() == 3, 24031)
	boss._enter(boss.S.HOVER)
	boss.take_damage(99999)
	_a(boss.hp == int(round(boss.max_hp * 0.66)) and boss.state == boss.S.TRANSITION1, 24032)
	boss._drop_anton()
	_a(boss.phase == 2 and boss.boss_title() == "Антон t2x2", 24033)
	# pt138u: Антон-толстяк — шире, чем выше; без таблички; капсула и хитбокс под пузо; удар правой, затем левой
	var asz: Vector3 = boss.anton_size()
	var acol := boss.get_node("Col") as CollisionShape3D
	var no_tag := true
	for n in boss.find_children("*", "Label3D", true, false): no_tag = false
	_a(asz.x > asz.y and (acol.shape as CapsuleShape3D).radius >= 1.7 and boss.hit_radius >= 2.0 and no_tag and boss.FIST_RANGE >= 4.0, 24140)
	boss._fist_hits = 0; boss._fist_hit()
	var arm1: String = boss._punch_arm
	boss._fist_hits = 1; boss._fist_hit()
	_a(arm1 == "r" and boss._punch_arm == "l" and boss._pose == "punch", 24141)
	boss._enter(boss.S.ANTON_IDLE)
	boss.take_damage(99999)
	_a(boss.hp == int(round(boss.max_hp * 0.33)) and boss.state == boss.S.TRANSITION2, 24034)
	boss._t = 2.6
	await _wait(3)
	_a(boss.phase == 3, 24035)
	var clowns: Array = boss._spawn_clowns(1)
	_a(clowns.size() == 1, 24036)
	if clowns.size() == 1:
		boss._eat_clown = clowns[0]; boss._enter(boss.S.EAT_TELEGRAPH)
		clowns[0].take_damage(999)
		await _wait(2)
		_a(boss.state == boss.S.EAT_RECOVER and boss.is_vulnerable(), 24036)
	boss._enter(boss.S.ANTON_IDLE)
	boss.take_damage(99999)
	var shards: Array = T.get_nodes_in_group("burger_clown").filter(func(c: Node) -> bool: return bool(c.shard) and not c.is_queued_for_deletion())
	_a(boss.state == boss.S.SHARDS and shards.size() == 5, 24037)
	boss._shard_t = 0.0
	await _wait(3)
	_a(boss.state != boss.S.SHARDS and boss.hp == int(round(boss.max_hp * 0.25)), 24038)
	boss._enter(boss.S.ANTON_IDLE)
	var vic := [false]
	G.victory.connect(func() -> void: vic[0] = true, CONNECT_ONE_SHOT)
	boss.take_damage(99999)
	for c in T.get_nodes_in_group("burger_clown"):
		if bool(c.shard): c.take_damage(9999)
	await _wait(4)
	_a(G.burger_defeated and vic[0], 24039)
	var core := false
	for r in G.dropped_items:
		if str(r.get("id", "")) == "burger_core": core = true
	_a(core, 24040)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var nose := 0; var grill := 0; var trophy := 0
	var B: GDScript = load("res://scripts/boss_burger.gd")
	for i in range(2000):
		var dr: Array = B.roll_drops(rng)
		if "clown_nose" in dr: nose += 1
		if "grill_saucer" in dr: grill += 1
		if "burger_trophy" in dr: trophy += 1
	_a(absf(nose / 2000.0 - 0.25) < 0.04 and absf(grill / 2000.0 - 0.2) < 0.04 and absf(trophy / 2000.0 - 0.1) < 0.03, 24041)
	G.set_difficulty("expert")
	var b2: Node = B.spawn_at(scene.wake_world, ppos)
	await _wait(2)
	_a(b2 != null and b2.max_hp == ceili(4000 * 1.75) and b2.eats_left == 2, 24042)
	if b2: b2.queue_free()
	G.set_difficulty("normal")
	for n in T.get_nodes_in_group("burger_clown"): n.queue_free()
	print("SMOKE: v0.24 Burger: summon 60 s / weak points / 66% Anton / 33% rage / eat interrupt / 5 shards + recompose 25% / victory / drops / expert")


func _v024_more(scene: Node) -> void:
	# музыка Бургера: фаза 1 / фаза 2
	var mc: Node = scene.get_node_or_null("MusicController")
	_a(mc != null, 24049)
	if mc:
		_a(mc._path_for("burger1").ends_with("burger_phase1_ost.mp3") and mc._path_for("burger2").ends_with("burger_phase2_ost.ogg") and ResourceLoader.exists(mc._path_for("burger2")) and ResourceLoader.exists(mc._path_for("burger1")), 24050)
		var b: Node = load("res://scripts/boss_burger.gd").spawn_at(scene.wake_world, scene.player.global_position)
		await _wait(2)
		if b == null: return
		_a(mc._desired() == "burger1", 24051)
		b.phase = 2
		_a(mc._desired() == "burger2", 24052)
		b.queue_free()
		await _wait(2)
	# экран победы
	var vs: Control = T.get_first_node_in_group("victory_screen")
	_a(vs != null and not vs.visible, 24053)
	if vs:
		vs.open()
		_a(vs.visible and G.victory_open and G.ui_blocked() and vs.stats_text().contains("Сложность") and vs.find_child("Credits", true, false).get_child_count() >= 8, 24054)
		vs.close()
		_a(not vs.visible and not G.victory_open, 24055)
	# зелье скорости ускоряет
	_a(G.SPEED_POTION_BOOST > 1.0 and G.SPEED_POTION_BOOST < 1.3, 24056)
	# меню: выбор сложности
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	T.root.add_child(mm)
	await _wait(2)
	var opt: OptionButton = mm.find_child("Difficulty", true, false)
	_a(opt != null and opt.item_count == 2 and opt.get_item_text(1) == "Эксперт", 24057)
	mm.queue_free()
	await _wait(1)
	print("SMOKE: v0.24 burger music phases / victory screen + credits / difficulty menu OK")
	await _stage2(scene)


func _stage2(scene: Node) -> void:
	var GSet: Node = T.root.get_node("GameSettings")
	var player: Node3D = scene.player
	var build: Node = scene.build
	G.dev_mode = false
	G.god_mode = false
	# 4: мёртвый код удалён
	_a(not FileAccess.file_exists("res://scripts/boss_combat_sm.gd") and not load("res://scripts/blockling.gd").new().has_method("carrier_target"), 24100)
	# 5: журнал ошибок
	var e0: int = GSet.error_logger.errors if GSet.error_logger else -1
	push_warning("smoke v0.24: проверка журнала ошибок")
	_a(GSet.error_logger != null and GSet.error_logger.errors > e0 and FileAccess.file_exists("user://logs/errors.log") and str(GSet.error_log_path()).ends_with("errors.log"), 24101)
	# 8, 26: тряска, FOV
	G.shake(0.7)
	_a(player._shake > 0.5, 24102)
	await _wait(2)
	_a(absf(player.camera.fov - GSet.fov) < 6.0, 24099)
	GSet.set_value("fov", 90)
	await _wait(2)
	_a(absf(player.camera.fov - 90.0) < 6.0, 24103)
	GSet.set_value("fov", 75)
	# 7: шаги по материалу
	_a(str(player._step_sound()).begins_with("step"), 24104)
	# 10: исчезновение дропа и Q над слотом
	var rec: Dictionary = G.register_drop({"id": "stone", "name": "Камень", "count": 3}, player.global_position + Vector3(4, 1, 0))
	var dn: Node = build.spawn_drop(rec, Vector3.ZERO, 5.0)
	rec["age"] = 299.95
	await _wait(6)
	_a(not G.dropped_items.has(rec) and (not is_instance_valid(dn) or dn.is_queued_for_deletion()), 24105)
	var inv: Node = T.get_first_node_in_group("inventory_ui")
	if inv == null:
		for n in scene.find_children("*", "Control", true, false):
			if n.has_method("drop_hovered"): inv = n; break
	_a(inv != null, 24106)
	if inv:
		G.set_slot(10, {"id": "planks", "name": "Доски", "count": 5})
		var nd: int = G.dropped_items.size()
		_a(inv.drop_hovered(false, 10) and int(G.get_slot(10).get("count", 0)) == 4 and G.dropped_items.size() == nd + 1, 24107)
		_a(inv.drop_hovered(true, 10) and str(G.get_slot(10).get("id", "")) == "", 24108)
	# 11: фиолетовые иконки
	var sv: Panel = load("res://scripts/slot_view.gd").new()
	T.root.add_child(sv)
	sv.dream_tint = true; sv.set_item("stone", 3)
	_a(sv._icon.modulate.r < 0.9 and sv._icon.modulate.b > 0.95, 24109)
	sv.queue_free()
	# 12: пояснение один раз
	G.explained = {}
	_a(G.explain_once("trial", "x") and not G.explain_once("trial", "x"), 24110)
	# 15, 16: новые мобы
	var WM: GDScript = load("res://scripts/wake_mob.gd")
	var ww: Node = scene.wake_world
	var ar: Node3D = WM.spawn(ww, player.global_position + Vector3(0, 30, 10), "archer")
	var th: Node3D = WM.spawn(ww, player.global_position + Vector3(2, 30, 0), "thief")
	var jp: Node3D = WM.spawn(ww, player.global_position + Vector3(-2, 30, 0), "jumper")
	await _wait(2)
	ar.set_physics_process(false); th.set_physics_process(false); jp.set_physics_process(false)
	var shot: Node3D = ar._shoot(player)
	_a(shot != null and shot.hostile and ar.shots == 1, 24111)
	shot.queue_free()
	G.set_slot(11, {"id": "log", "name": "Бревно", "count": 9})
	_a(th.steal() and int(th.stolen.get("count", 0)) >= 1 and int(th.stolen.get("count", 0)) <= 4, 24112)
	var deaths0: int = load("res://scripts/mob_fx.gd").deaths
	var nd2: int = G.dropped_items.size()
	th.take_damage(999)
	await _wait(2)
	_a(load("res://scripts/mob_fx.gd").deaths == deaths0 + 1 and G.dropped_items.size() >= nd2 + 2, 24113)
	_a(WM.roll_kind(0.05, 0) == "jumper" and WM.roll_kind(0.15, 0) != "archer" and WM.roll_kind(0.15, 999) == "archer" and WM.roll_kind(0.9, 999) == "", 24114)
	for m in [ar, jp]:
		if is_instance_valid(m): m.queue_free()
	# 21: новые атаки боссов
	var BA: GDScript = load("res://scripts/boss_extra_attacks.gd")
	G.heal_player_full()
	var hp0: int = G.player_hp
	var gy := func(q: Vector3) -> float: return player.global_position.y
	var pl: Node3D = BA.pillars(ww, player.global_position - Vector3(0, 0, 6), player.global_position + Vector3(0, 0, 2), gy)
	_a(pl.points.size() >= 10 and G.player_hp == hp0, 24115)
	var py0: Vector3 = player.global_position
	await T.create_timer(1.6).timeout
	_a(pl._hit.size() > 0 or G.player_hp < hp0, 24116)
	G.heal_player_full()
	await T.create_timer(0.6).timeout
	var hd := Node3D.new(); ww.add_child(hd); hd.global_position = player.global_position + Vector3(0, 4, -6)
	var vn: Node3D = BA.venom(ww, hd, player.global_position, gy)
	_a(vn.points.size() == 3, 24117)
	var hp1: int = G.player_hp
	await T.create_timer(2.0).timeout
	_a(G.player_hp < hp1, 24118)
	hd.queue_free()
	G.heal_player_full()
	var mo: Node = load("res://scripts/block_mother.gd").new()
	_a(mo.has_method("start_pillars") and load("res://scripts/boss_anaconda.gd").new().has_method("start_spit"), 24119)
	mo.free()
	# 17: погода
	var w: Node = scene.get_node_or_null("Weather")
	_a(w != null, 24120)
	if w:
		var env: Environment = scene.get_node("WorldEnvironment").environment
		w.set_weather("clear", true); GSet.apply_distance_fog(env)
		var clear_end: float = env.fog_depth_end
		w.set_weather("fog", true); GSet.apply_distance_fog(env)
		_a(env.fog_depth_end < clear_end * 0.5, 24121)
		w.set_weather("rain", true)
		await _wait(2)
		_a(G.weather_rain_k > 0.9 and w._rain.visible and G.weather_dim() > 0.3, 24122)
		var sv2: Dictionary = G.v024_to_dict()
		_a(str(sv2.weather) == "rain", 24123)
		w.set_weather("clear", true)
	# 13: жизнь Сна
	var dl: Node = scene.get_node_or_null("DreamLife")
	_a(dl != null and dl.islands >= 10 and not dl.visible, 24124)
	# консоль
	var con: Node = T.get_first_node_in_group("dev_console")
	if con:
		G.dev_mode = true
		var ws: int = G.world_seed
		G.world_seed = G.DEV_SEED
		_a(str(con.execute("weather fog")).contains("туман") and str(con.execute("mobs spawn jumper")).contains("Прыгун") and str(con.execute("errlog")).contains("errors.log") and str(con.execute("help mobs")).contains("Воришка"), 24125)
		con.execute("weather clear")
		_a(str(con.execute("net status")).contains("выкл") and str(con.execute("help net")).contains("24567"), 24126)
		var ns: Node = scene.get_node("/root/NetSession")
		_a(ns != null and not ns.is_client() and ns.player_count() == 1 and G.boss_player_scale() == 1.0, 24127)
		var vs := str(con.execute("variety status"))
		_a(vs.contains("в радиусе"), 24128)
		var cmv: Node = null
		for c in scene.get_tree().get_nodes_in_group("chunk_manager"):
			if not bool(c.get("is_dream_layer")) and not bool(c.get("panorama_mode")): cmv = c
		var gro := 0; var cle := 0; var tw := 0; var rich := 0; var tg := 0; var tc := 0
		for dx in range(-14, 15):
			for dz in range(-14, 15):
				var cc := Vector2i(dx, dz)
				var fk: String = cmv.forest_kind(cc)
				if fk == "grove":
					gro += 1; tg += cmv.tree_plan(cc).size()
				elif fk == "clearing":
					cle += 1; tc += cmv.tree_plan(cc).size()
				if cmv.cave_rich(cc): rich += 1
				if cmv.chunk_has_ruin(cc):
					for h in cmv.ruin_plan(cc):
						if int(h.shape) == 3: tw += 1
		print("SMOKE24 variety groves=%d clearings=%d towers=%d cave_rich=%d trees_grove=%d trees_clear=%d" % [gro, cle, tw, rich, tg, tc])
		_a(gro > 0 and cle > 0 and tw > 0 and rich > 0, 24129)
		_a(gro > 0 and cle > 0 and float(tg) / gro > 2.0 * float(tc) / cle + 1.0, 24130)
		var PS: GDScript = load("res://scripts/progress_store.gd")
		PS.reset()
		var md: bool = G.mother_defeated
		G.mother_defeated = true
		_a("mother" in PS.current_conditions() and PS.mark("mother") and not PS.mark("mother") and PS.load_all().has("mother"), 24131)
		_a(str(con.execute("progress status")).contains("Мать блоков"), 24132)
		G.mother_defeated = md
		PS.reset()
		# п.25: у каждого предмета своя иконка; п.26: все действия переназначения есть в InputMap, Enter только у чата
		var IDB: GDScript = load("res://scripts/item_db.gd")
		var no_icon: Array = []
		for id in IDB.ITEMS.keys():
			if not ResourceLoader.exists("res://assets/icons/%s.png" % id): no_icon.append(id)
		for sp in IDB.SPECIAL:
			if not ResourceLoader.exists("res://assets/icons/%s.png" % sp.id): no_icon.append(sp.id)
		_a(no_icon.is_empty(), 24133)
		var GSet2: Node = scene.get_node("/root/GameSettings")
		var bad_act: Array = []
		var enters := 0
		for b in GSet2.BINDABLE:
			if not InputMap.has_action(b[0]) or InputMap.action_get_events(b[0]).is_empty(): bad_act.append(b[0])
			if b[2] == "key" and int(b[3]) == KEY_ENTER: enters += 1
		_a(bad_act.is_empty() and enters == 1 and InputMap.has_action("net_chat"), 24134)
		var ui_t: Theme = load("res://scripts/ui_theme.gd").shared()
		_a(ui_t != null and ui_t == load("res://scripts/ui_theme.gd").shared(), 24135)
		G.world_seed = ws
		G.dev_mode = false
	for m in T.get_nodes_in_group("wake_mob"): m.queue_free()
	await _wait(2)
	print("SMOKE: v0.24 stage 2: no dead code / error log / shake+fov / steps / drop despawn + Q / purple icons / explain / jumper archer thief / death fx + dust / pillars + venom / weather / dream life / console OK")
