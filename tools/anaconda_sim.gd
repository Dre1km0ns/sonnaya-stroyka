extends SceneTree
## v0.12: headless-симуляция боя с Анакондой. Без рендера и чанков: пол y=0. 12 детерминированных сидов.
## Запуск: godot --headless --path . -s res://tools/anaconda_sim.gd -- --bot=<имя>|all [--runs=12] [--csv=путь]
## Боты:
##   no_light                 — ни одного факела (урон должен быть 0)
##   held_only                — только факел в руке (урон должен быть 0)
##   one_placed               — 1 поставленный факел (+16 запасных для замен)
##   two_placed               — 2 поставленных (+16 запасных)
##   three_placed             — 3 поставленных треугольником, запасных НЕТ
##   three_placed_no_held     — 3 поставленных, без факела в руке (+16 запасных) — фикс бага torches3_noheld
##   three_placed_with_spares — 3 поставленных + факел в руке + 16 запасных (рекомендуемая тактика)
##   human_like               — как with_spares, но с реакцией 0.35–0.6 с, 8% промахов уклонения, заменой за 3 с,
##                              пьёт 3 хилки2 (+40) при HP < 45
## Метрики: TTK, доля урона по источникам, сломано факелов (тело/землеройки), замены, попадания по игроку,
## пропущенные фазы, время до рассвета.

const DT := 1.0 / 60.0
const MAX_T := 600.0
const BOTS := ["no_light", "held_only", "one_placed", "two_placed", "three_placed", "three_placed_no_held", "three_placed_with_spares", "human_like"]
const NIGHT_START := 1020.0
const NIGHT_END := 1440.0


func _init() -> void:
	call_deferred("_run")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _layout(bot: String) -> Array:
	match bot:
		"one_placed":
			return [Vector3i(2, 0, 0)]
		"two_placed":
			return [Vector3i(2, 0, 0), Vector3i(-3, 0, 0)]
		"three_placed", "three_placed_no_held", "three_placed_with_spares", "human_like":
			var out: Array = []
			for i in range(3):
				var ang := TAU * float(i) / 3.0
				out.append(Vector3i(floori(cos(ang) * 3.0 + 0.5), 0, floori(sin(ang) * 3.0 + 0.5)))
			return out
	return []


func _run() -> void:
	var which := _arg("bot", "all")
	var runs := int(_arg("runs", "12"))
	var bots: Array = BOTS if which == "all" else [which]
	var lines: Array = []
	var summary: Array = []
	for bot in bots:
		var res: Array = []
		for run in range(runs):
			res.append(_one(bot, 1000 + run))
		summary.append(_summarize(bot, res))
		for r in res:
			lines.append(r)
	print("ANASIM TABLE bot | kills | TTK avg/min/max | hits taken avg | dmg taken avg | deaths | torches broken avg (body/burrow) | replacements avg | skipped phases | time to dawn avg | share placed%/held%/weapon%")
	for s in summary:
		print(s["line"])
	var csv := _arg("csv", "")
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		f.store_line("bot,seed,killed,ttk,hp_left,phase,hits_taken,dmg_taken,deaths,torches_broken,broken_body,broken_burrow,replacements,skipped_phases,time_to_dawn,cf2,cf3,ring,held,weapon,retreats,cavein,coil,coil_broken,minions")
		for r in lines:
			f.store_line(",".join([r.bot, r.seed, r.killed, "%.1f" % r.ttk, r.hp_left, r.phase, r.hits, r.taken, r.deaths, r.broken, r.broken_body, r.broken_burrow, r.replacements, r.skipped, "%.1f" % r.dawn,
				"%.0f" % r.src.crossfire2, "%.0f" % r.src.crossfire3, "%.0f" % r.src.ring_break, "%.0f" % r.src.held, "%.0f" % r.src.weapon, r.log.retreat, r.log.cavein, r.log.coil, r.log.coil_broken, r.log.minions]))
		f.close()
	quit(0)


func _summarize(bot: String, res: Array) -> Dictionary:
	var kills := 0
	var tsum := 0.0
	var tmin := 1e9
	var tmax := 0.0
	var hits := 0.0
	var taken := 0.0
	var deaths := 0
	var broken := 0.0
	var bb := 0.0
	var bw := 0.0
	var repl := 0.0
	var skipped := 0
	var dawn := 0.0
	var placed := 0.0
	var held := 0.0
	var weapon := 0.0
	for r in res:
		if r.killed:
			kills += 1
			tsum += r.ttk
			tmin = minf(tmin, r.ttk)
			tmax = maxf(tmax, r.ttk)
			skipped += int(r.skipped)
			dawn += r.dawn
		hits += r.hits
		taken += r.taken
		deaths += r.deaths
		broken += r.broken
		bb += r.broken_body
		bw += r.broken_burrow
		repl += r.replacements
		placed += r.src.crossfire2 + r.src.crossfire3 + r.src.ring_break
		held += r.src.held
		weapon += r.src.weapon
	var n := float(res.size())
	var tot := maxf(1.0, placed + held + weapon)
	var line := "ANASIM ROW %s | %d/%d | %s | %.1f | %.1f | %d | %.1f (%.1f/%.1f) | %.1f | %d | %s | %.0f/%.0f/%.0f" % [
		bot, kills, res.size(),
		("%.0f/%.0f/%.0f s" % [tsum / kills, tmin, tmax]) if kills > 0 else "—",
		hits / n, taken / n, deaths, broken / n, bb / n, bw / n, repl / n, skipped,
		("%.0f s" % (dawn / kills)) if kills > 0 else "—",
		100.0 * placed / tot if placed + held + weapon > 0 else 0.0, 100.0 * held / tot, 100.0 * weapon / tot]
	return {"line": line, "kills": kills}


func _place(G: Node, c: Vector3i) -> void:
	G.wake_blocks[c] = {"kind": "torch", "mutant": false}
	G.mark_torches_dirty()


func _one(bot: String, sd: int) -> Dictionary:
	var G: Node = root.get_node("GameState")
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	seed(sd)
	G.reset_state()
	G.peaceful = false
	G.dev_mode = false
	G.god_mode = false
	G.day_time = NIGHT_START + 5.0
	G.heal_player_full()
	var host := Node3D.new()
	root.add_child(host)
	var pl := CharacterBody3D.new()
	pl.add_to_group("player")
	host.add_child(pl)
	var layout := _layout(bot)
	for c in layout:
		_place(G, c)
	var holds_torch: bool = bot not in ["no_light", "three_placed_no_held"]
	if holds_torch:
		G.add_item_count("torch", 1)
		G.select_item_slot(0)
	var spares := 0 if bot in ["no_light", "held_only", "three_placed"] else 16
	var human := bot == "human_like"
	pl.global_position = Vector3(0.3, 0, 0.3)
	var ana: Node3D = AS.new()
	ana.set_seed(sd)
	ana.set("nest_id", "sim")
	ana.set("home", Vector3(9, 0, 6))
	ana.position = Vector3(9, 0, 6)
	host.add_child(ana)
	ana.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd * 7 + 3
	var t := 0.0
	var hits := 0
	var taken := 0
	var hp_prev: int = G.player_hp
	var last_state := -1
	var dodge_to := pl.global_position
	var react_t := 0.0
	var pending_dodge := false
	var died := 0
	var replacements := 0
	var replace_t := 0.0
	var swing_cd := 0.0
	var coil_placed := false
	var coil_react := 0.0
	var phase_t := {}
	var worm_kills := 0
	var rocks_seen := 0
	var potions := 3
	var dodge_cavein := false
	var torches_out_t := -1.0
	while t < MAX_T:
		t += DT
		G.day_time += DT
		G._process(DT)
		# ---- реакция на смену состояния
		if ana.state != last_state:
			last_state = ana.state
			if ana.state == ana.S.TELEGRAPH:
				pending_dodge = true
				react_t = rng.randf_range(0.35, 0.6) if human else 0.15
			elif ana.state == ana.S.COIL:
				coil_placed = false
				coil_react = rng.randf_range(0.8, 1.4) if human else 0.7
		if ana._rocks.size() > rocks_seen:
			pending_dodge = true
			dodge_cavein = true
			react_t = rng.randf_range(0.35, 0.6) if human else 0.15
		rocks_seen = ana._rocks.size()
		if pending_dodge:
			react_t -= DT
			if react_t <= 0.0:
				pending_dodge = false
				if dodge_cavein:
					dodge_cavein = false
					dodge_to = _cavein_point(ana, pl.global_position, rng)
				elif ana.state == ana.S.TELEGRAPH:
					if human and rng.randf() < 0.08:
						dodge_to = pl.global_position   # промах: замешкался
					else:
						dodge_to = _dodge_point(ana, layout, pl.global_position, rng)
		if ana.state == ana.S.COIL and not coil_placed:
			coil_react -= DT
			if coil_react <= 0.0:
				coil_placed = true
				if spares > 0 and (not human or rng.randf() < 0.8):
					var cc := Vector3i(floori(pl.global_position.x), 0, floori(pl.global_position.z))
					if not G.wake_blocks.has(cc):
						_place(G, cc)
						spares -= 1
				else:
					# Нет запаса — выпрыгиваем из кольца наружу.
					var out: Vector3 = pl.global_position - ana.coil_center()
					out.y = 0.0
					dodge_to = ana.coil_center() + (out.normalized() if out.length() > 0.1 else Vector3(1, 0, 0)) * (ana.COIL_RADIUS + 1.5)
		# ---- землеройки: идём бить ту, что гасит факел (мечом 8 / 0.45 с)
		swing_cd = maxf(0.0, swing_cd - DT)
		var worms: Array = []
		for w in host.get_children():
			if w.is_in_group("anaconda_minion"):
				worms.append(w)
		for w in worms:
			w.tick(DT)
		var hunting := false
		var calm: bool = ana.state in [ana.S.UNDER, ana.S.IDLE, ana.S.REST, ana.S.RETREAT, ana.S.DIVE, ana.S.TRANSITION, ana.S.SPAWN, ana.S.STUN, ana.S.VULNERABILITY, ana.S.RECOVERY, ana.S.FAKE] and ana._rocks.is_empty()
		if bot != "no_light" and bot != "held_only" and calm:
			for w in worms:
				if not is_instance_valid(w) or w.is_dead():
					continue
				var wp: Vector3 = w.hit_center()
				hunting = true
				if Vector2(wp.x - pl.global_position.x, wp.z - pl.global_position.z).length() > 2.0:
					dodge_to = Vector3(wp.x, 0, wp.z)
				elif swing_cd <= 0.0:
					swing_cd = 0.45
					w.take_damage(8)
					if w.is_dead():
						worm_kills += 1
				break
		# Пока она под землёй — возвращаемся в центр расстановки (вынырнет под нами, в перекрёстном огне).
		if not hunting and ana.state == ana.S.UNDER and layout.size() > 0 and (not human or rng.randf() < 0.9):
			dodge_to = Vector3(0.3, 0, 0.3)
		var step := 5.5 * DT
		var dv := dodge_to - pl.global_position
		dv.y = 0.0
		pl.global_position += dv if dv.length() <= step else dv.normalized() * step
		ana.tick(DT)
		# ---- замены сломанных факелов (запас)
		if spares > 0 and layout.size() > 0:
			replace_t += DT
			if replace_t >= (3.0 if human else 1.5):
				for c in layout:
					if not G.wake_blocks.has(c):
						_place(G, c)
						spares -= 1
						replacements += 1
						replace_t = 0.0
						break
		if G.player_hp < hp_prev:
			taken += hp_prev - G.player_hp
			hits += 1
		if human and potions > 0 and G.player_hp < 45 and G.player_hp > 0:
			potions -= 1
			G.player_hp = mini(G.PLAYER_MAX_HP, G.player_hp + 40)
		if G.player_hp <= 0:
			died += 1
			G.heal_player_full()
		hp_prev = G.player_hp
		if not phase_t.has(ana.phase):
			phase_t[ana.phase] = snappedf(t, 0.1)
		if torches_out_t < 0.0 and layout.size() > 0 and G.torch_cells().is_empty():
			torches_out_t = t
		if ana.state == ana.S.DEAD or ana.state == ana.S.LEAVING:
			break
	var killed: bool = ana.state == ana.S.DEAD
	var r := {"bot": bot, "seed": sd, "killed": killed, "ttk": t, "hp_left": ana.hp, "phase": ana.phase, "hits": hits, "taken": taken,
		"deaths": died, "broken": ana.torches_broken, "broken_body": ana.torches_broken_by_body, "broken_burrow": ana.torches_broken - ana.torches_broken_by_body,
		"replacements": replacements, "skipped": (3 - ana.phases_seen.size()) if killed else 0, "dawn": NIGHT_END - G.day_time,
		"src": ana.damage_by_source.duplicate(), "log": ana.attack_log.duplicate(), "reason": ana.leave_reason}
	# урон факелом в руке/оружием обязан быть 0
	r.src["held"] = 0.0
	print("ANASIM RUN bot=%s seed=%d killed=%s ttk=%.1f hp_left=%d phase=%d hits=%d taken=%d deaths=%d broken=%d(body %d) repl=%d retreat=%d cavein=%d coil=%d/%d minions=%d stuns=%d held_ignored=%.1fs phases=%s dark_at=%.0f wk=%d src=%s %s" % [
		bot, sd, str(killed), t, ana.hp, ana.phase, hits, taken, died, ana.torches_broken, ana.torches_broken_by_body, replacements,
		ana.attack_log.retreat, ana.attack_log.cavein, ana.attack_log.coil_broken, ana.attack_log.coil, ana.attack_log.minions, int(ana.attack_log.get("stun", 0)), ana.held_light_ignored, str(phase_t), torches_out_t, worm_kills, str(ana.damage_by_source), str(ana.break_states) + " " + str(ana.attack_log)])
	for w in host.get_children():
		if w.is_in_group("anaconda_minion"):
			w.free()
	ana.free()
	host.free()
	G.wake_blocks.clear()
	G.mark_torches_dirty()
	G.set_boss_alive(false)
	return r


func _dodge_point(ana: Node3D, layout: Array, from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	## Уходим ≥2.5 м от трещины так, чтобы голова (ляжет на 1.6 м дальше от нас) попала под максимум факелов,
	## а линия её тела (до 4 м от трещины в сторону от нас) не задела ни один факел.
	var e: Vector3 = ana._emerge
	var best := from
	var best_score := -1e9
	for k in range(32):
		var cand := Vector3(rng.randf_range(-3.2, 3.2), 0, rng.randf_range(-3.2, 3.2))
		var dd := Vector2(cand.x - e.x, cand.z - e.z).length()
		if dd < 2.5:
			continue
		var away := Vector3(e.x - cand.x, 0, e.z - cand.z).normalized()
		var head := e + away * 1.6 + Vector3(0, 0.6, 0)
		var lit := 0
		var clash := 0.0
		for c in layout:
			var tp: Vector3 = ana.torch_pos(c)
			if tp.distance_to(head) <= ana.TORCH_RADIUS + 0.4:
				lit += 1
			# ближайшее расстояние от факела до отрезка тела e → e+away*4
			var rel := Vector2(tp.x - e.x, tp.z - e.z)
			var dir2 := Vector2(away.x, away.z)
			var proj := clampf(rel.dot(dir2), 0.0, 4.0)
			var dist := (rel - dir2 * proj).length()
			if dist < 1.3:
				clash += 1.3 - dist
		var score := float(lit) * 10.0 - clash * 25.0 - 0.3 * cand.length()
		if score > best_score:
			best_score = score
			best = cand
	return best


func _cavein_point(ana: Node3D, from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var best := from
	var bs := -1.0
	for k in range(32):
		var cand := from + Vector3(rng.randf_range(-3.5, 3.5), 0, rng.randf_range(-3.5, 3.5))
		var md := 99.0
		for rk in ana._rocks:
			var ra: Vector3 = rk["at"]
			md = minf(md, Vector2(cand.x - ra.x, cand.z - ra.z).length())
		var sc := md - 0.15 * cand.length()
		if sc > bs:
			bs = sc
			best = cand
	return best
