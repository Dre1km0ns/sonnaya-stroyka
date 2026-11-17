extends SceneTree
## v0.14: стенд «до/после». Тот же код запускается на v0.13 и v0.14.
## godot --headless --path . -s res://tools/v014_bench.gd
func _init() -> void: call_deferred("_run")

func _med(a: Array) -> float:
	var b := a.duplicate(); b.sort(); return float(b[b.size() / 2])

func _run() -> void:
	var G: Node = root.get_node("GameState")
	var out := {"version": ProjectSettings.get_setting("application/config/name", "")}
	# --- Анаконда: 3 факела, 4000 блоков, 1800 тиков × 5 повторов (медиана)
	var ana_runs: Array = []
	var mom_runs: Array = []
	for rep in range(5):
		G.reset_state(); G.day_time = 1200.0
		for i in range(4000):
			G.wake_blocks[Vector3i(i % 80, 0, i / 80)] = {"kind": "stone"}
		for c in [Vector3i(2, 0, 0), Vector3i(-3, 0, 0), Vector3i(0, 0, 3)]:
			G.wake_blocks[c] = {"kind": "torch"}
		G.mark_torches_dirty()
		var host := Node3D.new(); root.add_child(host)
		var pl := CharacterBody3D.new(); pl.add_to_group("player"); host.add_child(pl)
		pl.global_position = Vector3(0.3, 0, 0.3)
		var ana: Node3D = load("res://scripts/boss_anaconda.gd").new()
		ana.set_seed(42); ana.set("home", Vector3(4, 0, 4)); ana.position = Vector3(4, 0, 4)
		host.add_child(ana); ana.set_physics_process(false)
		var t := Time.get_ticks_usec()
		for i in range(1800): ana.tick(1.0 / 60.0)
		ana_runs.append(float(Time.get_ticks_usec() - t) / 1800.0)
		ana.free()
		var mom: Node = load("res://scripts/block_mother.gd").new()
		host.add_child(mom); mom.set_physics_process(false)
		if mom.has_method("set_seed"): mom.set_seed(42)
		t = Time.get_ticks_usec()
		for i in range(1800): mom._physics_process(1.0 / 60.0)
		mom_runs.append(float(Time.get_ticks_usec() - t) / 1800.0)
		mom.free(); host.free()
	out["anaconda_tick_us"] = _med(ana_runs); out["anaconda_runs"] = ana_runs
	out["mother_tick_us"] = _med(mom_runs); out["mother_runs"] = mom_runs
	# --- Пересборка полного чанка 16×16×4 (1024 обычных блока), 40 раз
	G.reset_state(); G.current_world = G.World.DREAM
	var vox = load("res://scripts/voxel_world.gd").new(); vox.is_dream_layer = true; root.add_child(vox)
	for x in range(16):
		for z in range(16):
			for y in range(4):
				G.dream_blocks[Vector3i(x, 5 + y, z)] = {"kind": "planks"}
	vox.sync_from_state()
	var rb: Array = []
	for i in range(40):
		var t := Time.get_ticks_usec()
		vox._build_placed_chunk(Vector2i(0, 0))
		rb.append(float(Time.get_ticks_usec() - t) / 1000.0)
		await process_frame
	out["chunk_rebuild_1024_ms"] = _med(rb)
	# --- Правка одного блока в полном чанке (place + flush, remove + flush), 60 раз
	var ed: Array = []
	for i in range(60):
		var c := Vector3i(i % 16, 9, (i / 16) % 16)
		var t := Time.get_ticks_usec()
		G.place_dream_block(c, "planks"); vox.flush_dirty()
		G.remove_dream_block(c); vox.flush_dirty()
		ed.append(float(Time.get_ticks_usec() - t) / 2000.0)
		await process_frame
	out["edit_in_full_chunk_ms"] = _med(ed)
	vox.queue_free()
	# --- HUD: полоса HP в покое — сколько перерисовок за 300 кадров (сигнал draw есть в обеих версиях)
	var bat: Control = load("res://scripts/health_battery.gd").new()
	bat.size = Vector2(220, 26); root.add_child(bat)
	bat.set_hp(80, 100)
	for i in range(90): await process_frame
	var draws := [0]
	bat.draw.connect(func() -> void: draws[0] += 1)
	# Как в игре: hud._process → _update_heal_indicator() → set_hp() каждый кадр.
	for i in range(300):
		bat.set_hp(80, 100)
		await process_frame
	out["hud_idle_draws_300f"] = draws[0]
	draws[0] = 0
	for i in range(300):
		bat.set_hp(40, 100)
		await process_frame
	out["hud_after_hit_draws_300f"] = draws[0]
	bat.queue_free()
	print("V014BENCH " + JSON.stringify(out))
	quit(0)
