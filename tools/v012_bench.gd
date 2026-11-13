extends SceneTree
## v0.12: микробенчмарк — кеш факелов + tick Анаконды/Матери. Без рендера сцены.
## godot --headless --path . -s res://tools/v012_bench.gd
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var G: Node = root.get_node("GameState")
	var out := {"version": "", "torch_cache": [], "anaconda_tick_us": 0.0, "mother_tick_us": 0.0}
	out["version"] = ProjectSettings.get_setting("application/config/name", "")
	# --- кеш факелов
	for total in [2000, 20000]:
		G.reset_state()
		for i in range(total):
			G.wake_blocks[Vector3i(i % 200, i / 40000, (i / 200) % 200)] = {"kind": "torch" if i % 250 == 0 else "stone"}
		G.mark_torches_dirty()
		var iters := 200
		var t0 := Time.get_ticks_usec()
		var n1 := 0
		for k in range(iters):
			var scan: Array = []
			for c in G.wake_blocks:
				if str((G.wake_blocks[c] as Dictionary).get("kind", "")) == "torch":
					scan.append(c)
			n1 = scan.size()
		var scan_us := float(Time.get_ticks_usec() - t0) / iters
		G.torch_cells()
		t0 = Time.get_ticks_usec()
		var n2 := 0
		for k in range(iters):
			n2 = G.torch_cells().size()
		var cache_us := float(Time.get_ticks_usec() - t0) / iters
		out["torch_cache"].append({"blocks": total, "torches": n2, "scan_us": scan_us, "cache_us": cache_us})
		print("V012BENCH torch blocks=%d torches=%d scan=%.1f us cache=%.2f us" % [total, n2, scan_us, cache_us])
	# --- tick Анаконды (3 факела, 4000 блоков)
	G.reset_state()
	G.day_time = 1200.0
	for i in range(4000):
		G.wake_blocks[Vector3i(i % 80, 0, i / 80)] = {"kind": "stone"}
	for c in [Vector3i(2, 0, 0), Vector3i(-3, 0, 0), Vector3i(0, 0, 3)]:
		G.wake_blocks[c] = {"kind": "torch"}
	G.mark_torches_dirty()
	var host := Node3D.new()
	root.add_child(host)
	var pl := CharacterBody3D.new()
	pl.add_to_group("player")
	host.add_child(pl)
	pl.global_position = Vector3(0.3, 0, 0.3)
	var AS: GDScript = load("res://scripts/boss_anaconda.gd")
	var ana: Node3D = AS.new()
	ana.set_seed(42)
	ana.set("home", Vector3(4, 0, 4))
	ana.position = Vector3(4, 0, 4)
	host.add_child(ana)
	ana.set_physics_process(false)
	var ticks := 1800
	var t1 := Time.get_ticks_usec()
	for i in range(ticks):
		ana.tick(1.0 / 60.0)
	var ana_us := float(Time.get_ticks_usec() - t1) / ticks
	out["anaconda_tick_us"] = ana_us
	print("V012BENCH anaconda tick=%.2f us/frame (%d ticks, hp=%d state=%s)" % [ana_us, ticks, ana.hp, ana.STATE_NAMES[ana.state]])
	ana.free()
	# --- tick Матери
	var mom: Node = load("res://scripts/block_mother.gd").new()
	host.add_child(mom)
	mom.set_physics_process(false)
	if mom.has_method("set_seed"):
		mom.set_seed(42)
	mom.position = Vector3(0, 0, 0)
	t1 = Time.get_ticks_usec()
	for i in range(ticks):
		if mom.has_method("tick"):
			mom.tick(1.0 / 60.0)
		else:
			mom._physics_process(1.0 / 60.0)
	var mom_us := float(Time.get_ticks_usec() - t1) / ticks
	out["mother_tick_us"] = mom_us
	print("V012BENCH mother tick=%.2f us/frame (%d ticks, hp=%d state=%s)" % [mom_us, ticks, mom.hp, mom.STATE_NAMES[mom.state]])
	mom.free()
	host.free()
	var path := "res://BENCHMARK_V0.12.json"
	# write after we have before/after — this script prints numbers; caller saves JSON.
	print("V012BENCH JSON %s" % JSON.stringify(out))
	quit(0)
