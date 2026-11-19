extends SceneTree
## v0.20: бот-прогон «Бета-путь» — 30–60 минут игрового времени по вехам, настоящие сцены меню и игры.
## godot --headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40
##
## Что настоящее: меню → создание мира → старт во Сне; полёт (удержание клавиш, физика игрока); постановка
## блоков через build._place_at (как ЛКМ); M, L, J, F1, F — через ввод (InputEventAction); якоря, пробуждение,
## сон, смена суток, ночные угрозы, кошмары, автосейв, сейв/загрузка с диска.
## Что симулировано (бот не прицеливается и не сражается): добыча — выдачей предметов тем же путём, что подбор
## дропа (add_item_count в Яви); рамка K — вызовом frame_mark; поломка постройки чудовищем — destroy_wake_structure;
## победа над Матерью — unlock_zone («Каменный сад»); бессмертие (god_mode), чтобы прогон не прервала смерть.
var fails: Array = []
var log: Array = []
var gs: Node
var main: Node
var game_t := 0.0
var t0_ms := 0
var frame_us: PackedInt32Array = PackedInt32Array()
var _last_us := 0
var minutes := 40.0
var saves := 0
var loads := 0
var nights := 0
var _was_night := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="): minutes = clampf(float(a.split("=")[1]), 1.0, 90.0)
	call_deferred("_go")


func _frame() -> void:
	await process_frame
	var now := Time.get_ticks_usec()
	if _last_us > 0: frame_us.append(now - _last_us)
	_last_us = now
	game_t += 1.0 / 60.0
	if gs != null:
		var n: bool = gs.is_night()
		if n and not _was_night: nights += 1
		_was_night = n


func _wait(n: int) -> void:
	for i in range(n): await _frame()


func _wait_game(sec: float) -> void:
	var end := game_t + sec
	while game_t < end: await _frame()


func _mark(id: String, ok: bool, note: String = "") -> void:
	var e := {"id": id, "ok": ok, "game_min": snappedf(game_t / 60.0, 0.01), "real_s": snappedf((Time.get_ticks_msec() - t0_ms) / 1000.0, 0.1), "note": note}
	log.append(e)
	print("BOT %s %6.2f мин  %s  %s" % ["ok  " if ok else "FAIL", game_t / 60.0, id, note])
	if not ok: fails.append(id)


func _press(action: String, hold_frames: int = 2) -> void:
	var e := InputEventAction.new(); e.action = action; e.pressed = true; Input.parse_input_event(e)
	await _wait(hold_frames)
	e = InputEventAction.new(); e.action = action; e.pressed = false; Input.parse_input_event(e)
	await _wait(1)


func _place_row(from: Vector3i, n: int, step: Vector3i) -> int:
	var k := 0
	for i in range(n):
		var before: int = gs.dream_blocks.size()
		main.build._place_at(from + step * i)
		if gs.dream_blocks.size() > before: k += 1
	return k


func _anchor_at(c: Vector3i, t: int) -> bool:
	gs.select_anchor(t)
	for i in range(240):
		var p: Dictionary = gs.anchor_preview(c)
		if p.ready: return gs.try_place_anchor(c)
		await _wait(1)
	return false


func _fill(lo: Vector3i, hi: Vector3i, kind: String) -> int:
	gs.dream_material = kind
	gs.frame_mark(lo); gs.frame_mark(hi)
	var before: int = gs.dream_blocks.size()
	await _press("dream_fill")
	return gs.dream_blocks.size() - before


func _house(o: Vector3i, kind: String) -> void:
	## 9×9: пол + стены в 2 блока, проём под дверь.
	await _fill(o, o + Vector3i(8, 0, 8), kind)
	await _fill(o + Vector3i(0, 1, 0), o + Vector3i(8, 2, 0), kind)
	await _fill(o + Vector3i(0, 1, 8), o + Vector3i(8, 2, 8), kind)
	await _fill(o + Vector3i(0, 1, 1), o + Vector3i(0, 2, 7), kind)
	await _fill(o + Vector3i(8, 1, 1), o + Vector3i(8, 2, 7), kind)


func _save_load_check(tag: String) -> void:
	var nb: int = gs.dream_blocks.size(); var nw: int = gs.wake_blocks.size(); var cl: float = gs.clarity
	var ok_s: bool = main.saver.save_game("bot-" + tag); saves += 1
	await _wait(2)
	var ok_l: bool = main.saver.load_game(); loads += 1
	await _wait(5)
	_mark("сейв/загрузка " + tag, ok_s and ok_l and gs.dream_blocks.size() == nb and gs.wake_blocks.size() == nw and absf(gs.clarity - cl) < 0.5, "Сон %d→%d, Явь %d→%d, осозн. %.2f→%.2f" % [nb, gs.dream_blocks.size(), nw, gs.wake_blocks.size(), cl, gs.clarity])


func _sleep() -> void:
	main.switcher.enter_dream(); await _wait(6)


func _wake() -> Dictionary:
	main.switcher.show_result_ui = false
	var r: Dictionary = main.switcher.wake_up(); await _wait(6)
	return r


func _go() -> void:
	t0_ms = Time.get_ticks_msec()
	root.get_node("GameSettings").dream_start = true
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(10)
	var mm = current_scene
	mm._name_edit.text = "Бот v0.20"
	mm._seed_edit.text = "бета-путь"
	mm._create_world()
	await _wait(40)
	gs = root.get_node("GameState"); main = current_scene
	gs.god_mode = true
	_mark("новая игра начинается во Сне", gs.is_dream() and gs.tutorial_active, "обучение: %s" % str(gs.tutorial_current().get("title", "")))
	# --- обучение ---
	var e := InputEventAction.new(); e.action = "move_forward"; e.pressed = true; Input.parse_input_event(e)
	await _wait_game(3.0)
	e = InputEventAction.new(); e.action = "move_forward"; e.pressed = false; Input.parse_input_event(e)
	await _wait(3)
	_mark("обучение: полёт (W 3 с)", gs.tutorial_done.has("fly"))
	var p: Vector3 = main.player.global_position
	var base := Vector3i(floori(p.x), floori(p.y) + 4, floori(p.z))
	gs.dream_material = "drift"
	var wb := -1
	for i in range(9):
		if typeof(gs.inv_dream[i]) == TYPE_DICTIONARY and str(gs.inv_dream[i].get("id", "")) == "workbench": wb = i
	await _press("hotbar_9")   # пустая рука — ставится материал палитры (дрейф)
	_place_row(base, 6, Vector3i(1, 0, 0))
	await _wait(3)
	_mark("обучение: 5 блоков", gs.tutorial_done.has("build"))
	var wall := base + Vector3i(0, 0, 3)
	await _fill(wall, wall + Vector3i(5, 1, 0), "drift")
	_mark("обучение: рамка и заливка (L)", gs.tutorial_done.has("frame"))
	for i in range(4): await _frame()
	await _press("dream_trial")
	_mark("обучение: испытание (M)", gs.tutorial_done.has("trial"), "оценка %s" % str(gs.last_trial.get("grade", "?")))
	if wb >= 0: await _press("hotbar_%d" % (wb + 1))
	var wcell := base + Vector3i(2, 0, -4)
	main.build._place_at(wcell)
	await _wait(2)
	_mark("обучение: верстак", gs.tutorial_done.has("workbench") and str(gs.dream_blocks.get(wcell, {}).get("kind", "")) == "workbench", "слот %d" % (wb + 1))
	await _press("hotbar_9")
	_mark("обучение: якорь (подаренные реагенты)", await _anchor_at(wcell, gs.AnchorType.WEDGE))
	main.switcher.show_result_ui = false
	await _press("wake_up")
	await _wait(8)
	_mark("обучение: пробуждение, верстак в Яви", not gs.is_dream() and gs.wake_kind_count("workbench") > 0 and gs.milestones.has("tutorial"), "dream=%s wb=%d tut=%s" % [gs.is_dream(), gs.wake_kind_count("workbench"), gs.milestones.has("tutorial")])
	var tut_min := game_t / 60.0
	# --- Явь: добыча (симулирована выдачей предметов тем же путём, что подбор) ---
	await _wait_game(60.0)
	gs.add_item_count("log", 40); gs.add_item_count("dirt", 30)
	await _wait_game(60.0)
	gs.add_item_count("stone", 160); gs.add_item_count("reagent1", 14)
	await _wait_game(60.0)
	_mark("Явь: отпечатки бревна/земли/камня", gs.has_imprint("stone") and gs.has_imprint("log") and gs.milestones.has("imprint"), "осознанность %.0f/%.0f" % [gs.clarity, gs.dream_clarity_max()])
	await _save_load_check("после добычи")
	# --- Сон: дом из камня, испытание, материализация ---
	await _sleep()
	var h := Vector3i(floori(main.player.global_position.x) + 6, floori(main.player.global_position.y) + 6, floori(main.player.global_position.z) + 6)
	await _house(h, "stone")
	gs.frame_mark(h); gs.frame_mark(h + Vector3i(8, 3, 8))
	await _wait(4)
	await _press("dream_trial")
	var tr: Dictionary = gs.last_trial
	_mark("Сон: каменный дом 9×9 выдержал испытание", bool(tr.get("held", false)), "оценка %s, фантомов %d, прорывов %d" % [str(tr.get("grade", "?")), int(tr.get("phantoms", 0)), int(tr.get("breaches", 0))])
	var anchored := 0
	gs.wedges = maxi(gs.wedges, 1)
	for ax in [2, 6]:
		for az in [2, 6]:
			if await _anchor_at(h + Vector3i(ax, 1, az), gs.AnchorType.WEDGE): anchored += 1
	var r: Dictionary = await _wake()
	_mark("материализация дома", int(r.get("copied", 0)) >= 100 and float(r.get("trial_bonus", 0.0)) > 0.0, "якорей %d, копий %d, бонус испытания +%d, камня списано %d" % [anchored, int(r.get("copied", 0)), int(r.get("trial_bonus", 0)), int(r.get("materials", {}).get("stone", 0))])
	await _save_load_check("после дома")
	# --- ночь: чудовище ломает стену → трещина → кошмар на рассвете → заплатка ---
	var victim := h + Vector3i(4, 1, 8)
	var crack_ok: bool = gs.destroy_wake_structure(victim)
	_mark("Явь: чудовище сломало стену → трещина во Сне", crack_ok and gs.dream_cracks.size() >= 1, "трещин %d" % gs.dream_cracks.size())
	# во Сне у трещины — неякорённый дрейф (декор у стены): его и будут грызть кошмары
	await _sleep()
	gs.dream_material = "drift"
	for dx in [-1, 0, 1]: main.build._place_at(victim + Vector3i(dx, 0, 2))
	await _wake()
	var eaten0: int = gs.nightmare_eaten
	var dawns := 0
	var guard := 0
	while dawns < 1 and game_t < minutes * 60.0 - 300.0 and guard < 200000:
		var was: bool = gs.is_night()
		await _frame(); guard += 1
		if was and not gs.is_night(): dawns += 1
	_mark("рассвет: кошмар сгрыз дрейф у трещины", dawns >= 1 and gs.nightmare_eaten > eaten0, "сгрызено дрейфа всего %d (было %d), трещин %d" % [gs.nightmare_eaten, eaten0, gs.dream_cracks.size()])
	gs.add_item_count("reagent1", 6)   # реагенты на якорь-заплатку (у дома ушло 12 из 14)
	await _sleep()
	var pr: bool = await _anchor_at(victim, gs.AnchorType.WEDGE)
	if not pr: print("BOT anchor hint: ", gs.hint_text if "hint_text" in gs else "", " reagents=", gs.reagents, " clarity=", gs.clarity)
	var rp: Dictionary = await _wake()
	_mark("заплатка: якорь во Сне чинит Явь и закрывает трещину", pr and int(rp.get("patched", 0)) >= 1 and gs.wake_blocks.has(victim), "залатано %d" % int(rp.get("patched", 0)))
	# --- просьба Сна, чертёж, сад ---
	var rq: Dictionary = gs.ensure_request()
	gs.add_item_count(str(rq.kind), int(rq.n))
	await _sleep()
	for i in range(4): await _frame()
	var done0: int = gs.requests_done
	await _press("dream_offer")
	_mark("просьба Сна (J)", gs.requests_done == done0 + 1, "%d × %s" % [int(rq.n), str(rq.kind)])
	gs.frame_mark(h); gs.frame_mark(h + Vector3i(8, 2, 8))
	await _press("blueprint_save")
	var bp_ok: bool = gs.blueprints.size() >= 1
	gs.blueprint_shown = gs.blueprints.size() - 1
	var pasted: int = gs.paste_blueprint(h + Vector3i(14, 0, 0))
	_mark("чертёж дома (B) и вставка копии", bp_ok and pasted >= 100, "вставлено %d" % pasted)
	gs.unlock_zone("stone_garden")
	_mark("Каменный сад (симуляция победы над Матерью)", gs.has_imprint("ruin") or gs.dream_zones.has("stone_garden"))
	await _wake()
	# --- свободная игра до конца: циклы «Явь → Сон → проект → испытание → материализация», сейв каждые 5 мин ---
	var cycle := 0
	var next_save := game_t + 300.0
	while game_t < minutes * 60.0:
		cycle += 1
		await _wait_game(90.0)
		gs.add_item_count("stone", 100); gs.add_item_count("reagent1", 6)
		await _sleep()
		var o := h + Vector3i(-14 - 6 * (cycle % 4), 0, 12 * (cycle / 4))
		await _fill(o, o + Vector3i(4, 3, 4), "stone")
		gs.frame_mark(o); gs.frame_mark(o + Vector3i(4, 3, 4))
		await _press("dream_trial")
		await _anchor_at(o + Vector3i(2, 1, 2), gs.AnchorType.WEDGE)
		await _wait_game(30.0)
		var rc: Dictionary = await _wake()
		_mark("цикл %d: башня 5×4×5" % cycle, bool(rc.get("ok", false)), "копий %d, Сон %d блоков, Явь %d, осознанность %.0f" % [int(rc.get("copied", 0)), gs.dream_blocks.size(), gs.wake_blocks.size(), gs.clarity])
		if game_t >= next_save:
			next_save = game_t + 300.0
			await _save_load_check("цикл %d" % cycle)
	# --- итог ---
	var arr := Array(frame_us); arr.sort()
	var pct := func(q: float) -> float: return float(arr[clampi(int(arr.size() * q), 0, arr.size() - 1)]) / 1000.0
	var res := {"minutes_game": snappedf(game_t / 60.0, 0.01), "real_seconds": snappedf((Time.get_ticks_msec() - t0_ms) / 1000.0, 0.1),
		"frames": arr.size(), "frame_ms_p50": snappedf(pct.call(0.5), 0.01), "frame_ms_p95": snappedf(pct.call(0.95), 0.01), "frame_ms_p99": snappedf(pct.call(0.99), 0.01), "frame_ms_max": snappedf(float(arr.back()) / 1000.0, 0.01),
		"tutorial_minutes": snappedf(tut_min, 0.01), "tutorial_step_seconds": gs.tutorial_times, "nights": nights, "saves": saves, "loads": loads,
		"dream_blocks": gs.dream_blocks.size(), "wake_blocks": gs.wake_blocks.size(), "milestones": gs.milestones.keys(), "trials": gs.trials_run, "requests": gs.requests_done,
		"static_mem_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1), "fails": fails, "log": log}
	var f := FileAccess.open("res://benchmarks/v020_bot.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  ")); f.close()
	print("BOT RESULT ", JSON.stringify(res.duplicate().merged({"log": log.size()}, true)))
	print("BOT OK" if fails.is_empty() else "BOT FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
