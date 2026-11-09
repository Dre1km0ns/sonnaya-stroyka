extends SceneTree
## v0.7: headless-симуляция боя с Анакондой (TTK). Без рендера и чанков: пол y=0.
## Запуск: godot --headless --path . -s res://tools/anaconda_sim.gd -- --bot=torches3|torches2|held|idle [--runs=5]
## torches3 — «разумная расстановка»: 3 факела треугольником (r=2.2 м), игрок держит факел, уходит от трещины
##            на 2.4 м внутри освещённой зоны. torches2 — 2 факела. held — только факел в руке. idle — без света.

const DT := 1.0 / 60.0
const MAX_T := 600.0


func _init() -> void:
	call_deferred("_run")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _run() -> void:
	var bot := _arg("bot", "torches3")
	var runs := int(_arg("runs", "5"))
	var G: Node = root.get_node("GameState")
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var results: Array = []
	for run in range(runs):
		G.reset_state()
		G.peaceful = false
		G.day_time = 1020.0 + 5.0      # начало ночи (ночь = 1020..1440, 420 с)
		var host := Node3D.new()
		root.add_child(host)
		var pl := CharacterBody3D.new()
		pl.add_to_group("player")
		host.add_child(pl)
		var torches: Array = []
		var n_t := 3 if bot == "torches3" else (2 if bot == "torches2" else 0)
		for i in range(n_t):
			var ang := TAU * float(i) / float(maxi(1, n_t))
			var cell := Vector3i(floori(cos(ang) * 2.2), 0, floori(sin(ang) * 2.2))
			G.wake_blocks[cell] = {"kind": "torch", "mutant": false}
			torches.append(Vector3(cell.x + 0.5, 0.0, cell.z + 0.5))
		if bot != "idle" and bot != "torches3_noheld":
			G.add_item_count("torch", 1)
			G.select_item_slot(0)
		pl.global_position = Vector3(0.3, 0, 0.3)
		var ana: Node3D = AS.spawn_at(host, Vector3(9, 0, 6), "sim")
		ana.set_physics_process(false)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + run
		var t := 0.0
		var dmg_taken := 0
		var hp_prev: int = G.player_hp
		var last_state := -1
		var dodge_to := pl.global_position
		var died := 0
		while t < MAX_T:
			t += DT
			G.day_time += DT
			G._process(DT)
			# Бот: уходит от трещины, оставаясь у факелов.
			if ana.state != last_state:
				last_state = ana.state
				if ana.state == ana.S.TELEGRAPH:
					var best := pl.global_position
					var bd := -1.0
					for k in range(16):
						var cand := Vector3(rng.randf_range(-2.4, 2.4), 0, rng.randf_range(-2.4, 2.4))
						if torches.size() > 0:
							var near := false
							for tp in torches:
								if (tp as Vector3).distance_to(cand) < 2.6:
									near = true
							if not near:
								continue
						var dd := Vector2(cand.x - ana._emerge.x, cand.z - ana._emerge.z).length()
						if dd > 2.4 and (bd < 0 or dd < bd + 0.5):
							bd = dd
							best = cand
					dodge_to = best
				elif ana.state == ana.S.CAVEIN:
					# Уходим с теней камней (тень видна 1.0 с) — к факелу, подальше от всех теней.
					var bestc := pl.global_position
					var bsc := -1.0
					for k2 in range(24):
						var cand2 := Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
						var md := 99.0
						for rk in ana._rocks:
							var ra: Vector3 = rk["at"]
							md = minf(md, Vector2(cand2.x - ra.x, cand2.z - ra.z).length())
						var lit_ok := torches.is_empty()
						for tp2 in torches:
							if (tp2 as Vector3).distance_to(cand2) < 3.0:
								lit_ok = true
						if lit_ok and md > bsc:
							bsc = md
							bestc = cand2
					dodge_to = bestc
				elif ana.state == ana.S.COIL and torches.size() == 0:
					dodge_to = pl.global_position + Vector3(6, 0, 0)
			var step := 5.5 * DT
			var dv := dodge_to - pl.global_position
			pl.global_position += dv if dv.length() <= step else dv.normalized() * step
			ana.tick(DT)
			if G.player_hp < hp_prev:
				dmg_taken += hp_prev - G.player_hp
			if G.player_hp <= 0:
				died += 1
				G.heal_player_full()
			hp_prev = G.player_hp
			if ana.state == ana.S.DEAD or ana.state == ana.S.LEAVING:
				break
		results.append({"ttk": t, "dead": ana.state == ana.S.DEAD, "hp_left": ana.hp, "dmg_taken": dmg_taken,
			"deaths": died, "log": ana.attack_log.duplicate(), "phase": ana.phase, "reason": ana.leave_reason})
		ana.free()
		host.free()
		G.wake_blocks.clear()
	var tsum := 0.0
	var kills := 0
	for r in results:
		print("ANASIM bot=%s ttk=%.1f killed=%s hp_left=%d phase=%d taken=%d deaths=%d stun=%d rest=%d burst_hit=%d cavein=%d coil=%d broken=%d %s" % [
			bot, r["ttk"], str(r["dead"]), r["hp_left"], r["phase"], r["dmg_taken"], r["deaths"],
			r["log"]["stun"], r["log"]["rest"], r["log"]["burst_hit"], r["log"]["cavein"], r["log"]["coil"], r["log"]["coil_broken"], r["reason"]])
		if r["dead"]:
			kills += 1
			tsum += float(r["ttk"])
	print("ANASIM SUMMARY bot=%s MAX_HP=%d kills=%d/%d avg_ttk=%.1f s (night=420 s)" % [bot, AS.MAX_HP, kills, runs, tsum / maxf(1.0, float(kills))])
	quit(0)
