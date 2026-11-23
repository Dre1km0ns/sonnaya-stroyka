extends SceneTree
## v0.11.1: headless-симуляция боя с «Матерью блоков». 12 детерминированных сидов на бота.
## godot --headless --fixed-fps 60 --path . -s res://tools/boss_sim.gd -- [--bot=starter|upgraded|sword3|idle|kite|all] [--runs=12]
## starter  — Деревянный меч (8) + Кирка (2 по пластине): стартовое оружие, цель 90–140 с.
## upgraded — Меч2 (14) + Кирка2 (6): быстрее.
## sword3   — Чешуйчатый меч (24) + Кирка2: ещё быстрее (HP Матери от Меча3 НЕ масштабируется).
## idle     — стоит вплотную и машет мечом (проверка капов урона: удар ≤35, за 3 с ≤70; меч по броне = 0).
## kite     — убегает каждые 30 с (проверка пересборки-антикемпа).
## Бот уклоняется от тени прыжка, волны (прыжком), маркера пересборки и теней кирпичей (или прячется под навес),
## бьёт киркой светящуюся пластину, мечом — открытое ядро, убивает носильщиков.

const SWORD_CD := 0.45
const PICK_CD := 0.5
const SWORD_REACH := 2.6
const WALK := 6.0
const SPRINT := 10.0
const JUMP_V := 8.4          # v0.11.1: земной прыжок (как у игрока)
const GRAVITY := 28.0
const SIM_LIMIT := 420.0
const BOTS := ["starter", "upgraded", "sword3", "idle", "kite", "novice", "novice_sword3"]
## v0.13: novice / novice_sword3 — «живой» новичок: реакция на телеграф 0.45–0.8 с, 25% телеграфов пропускает,
## перепрыгивает волну в 60% случаев, смена слота 0.7 с, меч 0.6 с и 25% промахов. Остальные боты уклоняются идеально.

var gs: Node


func _init() -> void:
	call_deferred("_setup")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _setup() -> void:
	gs = root.get_node("GameState")
	var which := _arg("bot", "all")
	var runs := int(_arg("runs", "12"))
	var bots: Array = BOTS if which == "all" else [which]
	var rows: Array = []
	var all_ok := true
	for bot in bots:
		var res: Array = []
		for r in range(runs):
			res.append(await _one(bot, 2000 + r))
		var kills := 0
		var tsum := 0.0
		var tmin := 1e9
		var tmax := 0.0
		var hits := 0.0
		var taken := 0.0
		var ms := 0
		var mw := 0
		var deaths := 0
		var broken := 0.0
		var restored := 0.0
		var bounces := 0.0
		var seals := 0.0
		for x in res:
			if x.end == "killed":
				kills += 1
				tsum += x.ttk
				tmin = minf(tmin, x.ttk)
				tmax = maxf(tmax, x.ttk)
			hits += x.hits
			taken += x.taken
			ms = maxi(ms, x.max_single)
			mw = maxi(mw, x.max_3s)
			deaths += x.deaths
			broken += x.broken
			restored += x.restored
			bounces += x.bounces
			seals += x.seals
		var n := float(res.size())
		var ok := ms <= 35 and mw <= 70
		all_ok = all_ok and ok
		rows.append("BOSSSIM ROW %s | %d/%d | %s | %.1f | %.1f | %d | %d/%d | plates broken %.1f restored %.1f | bounces %.0f | seals %.1f | caps %s" % [
			bot, kills, res.size(), ("%.0f/%.0f/%.0f s" % [tsum / kills, tmin, tmax]) if kills > 0 else "—",
			hits / n, taken / n, deaths, ms, mw, broken / n, restored / n, bounces / n, seals / n, "OK" if ok else "FAIL"])
	print("BOSSSIM TABLE bot | kills | TTK avg/min/max | hits taken avg | dmg taken avg | deaths | max single/3s | armor | bounces | caps")
	for r in rows:
		print(r)
	quit(0 if all_ok else 2)


func _one(bot: String, sd: int) -> Dictionary:
	seed(sd)
	gs.reset_state()
	if _arg("expert", "") == "1": gs.set_difficulty("expert")   # v0.24
	gs.peaceful = false
	gs.dev_mode = false
	gs.god_mode = false
	gs.heal_player_full()
	var host := Node3D.new()
	host.name = "World"
	root.add_child(host)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000, 1, 3000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	host.add_child(floor_body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	pcs.shape = cap
	pcs.position = Vector3(0, 0.85, 0)
	player.add_child(pcs)
	player.position = Vector3(0, 0.1, 8)
	host.add_child(player)
	var boss: CharacterBody3D = load("res://scripts/block_mother.gd").new()
	boss.set_seed(sd)
	boss.position = Vector3(0.5, 0.15, 0)
	host.add_child(boss)
	boss.set_physics_process(false)
	player.set_physics_process(false)
	await process_frame
	# v0.14: move_and_slide() берёт не наш delta, а get_process_delta_time() — реальное время кадра,
	# если вызван вне physics-кадра. Из-за этого шаг движения бота и Матери был случайным (зависел от ЦП),
	# и прогоны с одним сидом расходились. Продолжаем цикл внутри physics-кадра: там шаг = 1/60 = наш delta.
	await physics_frame
	var sword_dmg := 8
	var pick := "pickaxe"
	if bot == "upgraded":
		sword_dmg = 14
		pick = "pickaxe2"
	elif bot == "sword3" or bot == "novice_sword3":
		sword_dmg = 24
		pick = "pickaxe2"
	var nrng := RandomNumberGenerator.new()
	nrng.seed = sd * 13 + 5
	var st := {"rng": nrng, "novice": bot.begins_with("novice"), "seen_state": -1, "react": 0.0, "ignore": false, "t": 0.0, "swing": 0.0, "hits": 0, "taken": 0, "max_single": 0, "max_3s": 0, "deaths": 0, "events": [], "last_hp": 100}
	var on_hp := func(hp: int, _mx: int) -> void:
		if hp < int(st.last_hp):
			var d: int = int(st.last_hp) - hp
			st.events.append([float(st.t), d])
			st.hits += 1
			st.taken += d
			st.max_single = maxi(int(st.max_single), d)
			var w := 0
			for e in st.events:
				if float(st.t) - float(e[0]) <= 3.0:
					w += int(e[1])
			st.max_3s = maxi(int(st.max_3s), w)
		st.last_hp = hp
	gs.player_hp_changed.connect(on_hp)
	var end := "timeout"
	while true:
		var delta := 1.0 / 60.0
		st.t = float(st.t) + delta
		# v0.13: без тика GameState не истекали стартовые i-frames (1.5 с после heal_player_full) —
		# игрок был неуязвим весь бой, и все боты показывали 0 полученного урона («идеальное уклонение»).
		gs._process(delta)
		if is_instance_valid(boss):
			boss.set_meta("sim_clock", int(float(st.t) * 1000.0))
			boss._physics_process(delta)
		if not is_instance_valid(boss) or boss.state == boss.S.DEAD:
			end = "killed"
			break
		if boss.state == boss.S.LEAVING:
			end = "left"
			break
		if float(st.t) > SIM_LIMIT:
			break
		if gs.player_hp <= 0:
			st.deaths += 1
			gs.heal_player_full()
			st.last_hp = 100
		_drive(bot, boss, player, delta, st, sword_dmg, pick)
	gs.player_hp_changed.disconnect(on_hp)
	var out := {"bot": bot, "seed": sd, "end": end, "ttk": float(st.t), "hits": st.hits, "taken": st.taken, "max_single": st.max_single,
		"max_3s": st.max_3s, "deaths": st.deaths, "broken": 0, "restored": 0, "bounces": 0, "seals": 0}
	if is_instance_valid(boss):
		out.broken = boss.plate_log.broken
		out.restored = boss.plate_log.restored
		out.bounces = boss.plate_log.bounces
		out.seals = boss.window_seals
		print("BOSSSIM RUN bot=%s seed=%d end=%s ttk=%.1f hits=%d taken=%d max=%d/%d deaths=%d armor=%s weapon=%s log=%s" % [bot, sd, end, st.t, st.hits, st.taken, st.max_single, st.max_3s, st.deaths, str(boss.plate_log), str(boss.damage_by_weapon), str(boss.attack_log)])
	for n in root.get_tree().get_nodes_in_group("blockling") + root.get_tree().get_nodes_in_group("mother_carrier"):
		n.queue_free()
	host.queue_free()
	await process_frame
	await process_frame
	gs.set_boss_alive(false)
	return out


func _flat(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x - b.x, 0, a.z - b.z)


func _drive(bot: String, boss: Node, player: CharacterBody3D, delta: float, st: Dictionary, sword_dmg: int, pick: String) -> void:
	var p := player.global_position
	var bp: Vector3 = boss.global_position
	var to_b := _flat(bp, p)
	var dist := to_b.length()
	var want := Vector3.ZERO
	var speed := WALK
	var jump := false
	var s: int = boss.state
	var t: float = st.t
	if bot == "kite" and fmod(t, 30.0) > 4.0 and fmod(t, 30.0) < 9.0:
		want = -to_b.normalized() if dist > 0.1 else Vector3(0, 0, 1)
		speed = SPRINT
	elif bot != "idle":
		var danger := false
		var novice: bool = st.novice
		var rng: RandomNumberGenerator = st.rng
		if novice:
			if s != int(st.seen_state):
				st.seen_state = s
				st.react = rng.randf_range(0.45, 0.8)
				st.ignore = rng.randf() < 0.25
			st.react = maxf(0.0, float(st.react) - delta)
		var can_react: bool = (not novice) or (float(st.react) <= 0.0 and not bool(st.ignore))
		var threat: bool = s in [boss.S.WINDUP, boss.S.AIR, boss.S.MELEE, boss.S.COMBO, boss.S.MARKER, boss.S.SCATTER, boss.S.COLLAPSE, boss.S.RAIN, boss.S.RAIN_WINDUP]
		if novice and not can_react and threat:
			danger = true            # замешкался: стоит на месте, пока не среагирует (или пропустил телеграф целиком)
		if can_react and (s == boss.S.AIR or s == boss.S.WINDUP):
			var land: Vector3 = boss._target if s == boss.S.AIR else bp
			var away := _flat(p, land)
			if away.length() < boss.SLAM_RADIUS + 1.5:
				want = away.normalized() if away.length() > 0.05 else Vector3(1, 0, 0)
				speed = SPRINT
				danger = true
		if can_react and (s == boss.S.MARKER or s == boss.S.SCATTER):
			var away2 := _flat(p, boss._marker_pos)
			if away2.length() < boss.REASSEMBLE_RADIUS + 1.5:
				want = away2.normalized() if away2.length() > 0.05 else Vector3(0, 0, 1)
				speed = SPRINT
				danger = true
		if not can_react:
			pass
		elif not boss._bricks.is_empty() and not boss._covers.is_empty():
			var cv: Vector3 = boss._covers[0]["pos"]
			var dc := _flat(cv, p)
			if dc.length() > 0.4:
				want = dc.normalized()
				speed = SPRINT
			danger = true
		else:
			for b in boss._bricks:
				var away3 := _flat(p, b["pos"])
				if away3.length() < boss.BRICK_RADIUS + 0.9:
					want = (want + away3.normalized()).normalized()
					speed = SPRINT
					danger = true
		for w in boss._waves:
			var c: Vector3 = w["center"]
			var r: float = float(w["r"])
			var dd := _flat(p, c).length()
			if dd - r < 1.2 and dd - r > -0.2 and player.is_on_floor():
				if not w.has("novice_jump"):
					w["novice_jump"] = (not novice) or rng.randf() < 0.6
				if bool(w["novice_jump"]):
					jump = true
		if not danger:
			var carrier: Node3D = null
			for m in root.get_tree().get_nodes_in_group("mother_carrier"):
				if is_instance_valid(m) and int(m.hp) > 0:
					carrier = m
					break
			var reach: float = SWORD_REACH + boss.hit_radius - 0.4
			if s in [boss.S.PLATE_OPEN, boss.S.CORE, boss.S.CORE_LONG] or boss.is_vulnerable():
				if dist > reach:
					want = to_b.normalized()
					speed = SPRINT
			elif carrier != null:
				var tc := _flat(carrier.global_position, p)
				if tc.length() > 1.6:
					want = tc.normalized()
					speed = SPRINT
			elif _nearest_minion(player) != null:
				var mn: Node3D = _nearest_minion(player)
				var tm := _flat(mn.global_position, p)
				if tm.length() > 1.4:
					want = tm.normalized()
			else:
				var near_band: float = 2.6 if bool(st.novice) else 4.5   # новичок жмётся к боссу
				if dist < near_band:
					want = -to_b.normalized()
				elif dist > near_band + 2.5:
					want = to_b.normalized()
	else:
		if dist > 2.5:
			want = to_b.normalized()
	var v := player.velocity
	v.x = want.x * speed
	v.z = want.z * speed
	if player.is_on_floor():
		v.y = JUMP_V if jump else 0.0
	else:
		v.y -= GRAVITY * delta
	player.velocity = v
	player.move_and_slide()
	st.swing = maxf(0.0, float(st.swing) - delta)
	if float(st.swing) > 0.0:
		return
	var c2: Vector3 = boss.hit_center()
	var d2 := (c2 - (player.global_position + Vector3(0, 1.5, 0))).length()
	var in_reach: bool = d2 <= SWORD_REACH + float(boss.hit_radius)
	if in_reach and s == boss.S.PLATE_OPEN and bot != "idle":
		if str(st.get("held", "sword")) != "pick":
			st.held = "pick"
			st.swing = 0.7 if bool(st.novice) else 0.4   # смена слота на кирку
			return
		st.swing = PICK_CD
		boss.receive_weapon_hit(2 if pick == "pickaxe" else 6, pick)
		return
	if in_reach and (bot == "idle" or boss.is_vulnerable()):
		if str(st.get("held", "sword")) != "sword":
			st.held = "sword"
			st.swing = 0.7 if bool(st.novice) else 0.4   # обратно на меч
			return
		st.swing = 0.6 if bool(st.novice) else SWORD_CD
		if bool(st.novice) and (st.rng as RandomNumberGenerator).randf() < 0.25:
			return   # промах
		boss.receive_weapon_hit(sword_dmg, "sword" if sword_dmg == 8 else ("sword2" if sword_dmg == 14 else "sword3"))
		return
	for grp in ["mother_carrier", "blockling"]:
		for m in root.get_tree().get_nodes_in_group(grp):
			if is_instance_valid(m) and int(m.hp) > 0 and (m.global_position - player.global_position).length() < SWORD_REACH + 0.5:
				st.swing = SWORD_CD
				m.take_damage(sword_dmg)
				if int(m.hp) <= 0 and grp == "mother_carrier":
					boss.plate_log.carriers_killed += 1
				return


func _nearest_minion(player: Node3D) -> Node3D:
	var best: Node3D = null
	var bd := 7.0
	for m in root.get_tree().get_nodes_in_group("blockling"):
		if is_instance_valid(m) and int(m.hp) > 0:
			var d: float = (m.global_position - player.global_position).length()
			if d < bd:
				bd = d
				best = m
	return best
