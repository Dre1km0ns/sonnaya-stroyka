extends SceneTree
## v0.17: стенд инструментов сновидца (логика GameState + перестройка чанков VoxelWorld).
## godot --headless --path . -s res://tools/v017_bench.gd   → печатает BENCH17 {json}
func _init() -> void: call_deferred("_run")

func _med(a: Array) -> float:
	var b := a.duplicate(); b.sort(); return float(b[b.size() / 2])

func _t(f: Callable) -> float:
	var t := Time.get_ticks_usec(); f.call(); return float(Time.get_ticks_usec() - t) / 1000.0

func _run() -> void:
	var G: Node = root.get_node("GameState")
	var r := {"fill16": [], "undo16": [], "redo16": [], "clear16": [], "save_bp16": [], "paste16_rot1": [], "mirror_place100": [], "fill16_mesh": [], "save_with_bp": [], "load_with_bp": []}
	var out := {"version": ProjectSettings.get_setting("application/config/name", "")}
	for rep in range(5):
		G.reset_state(); G.dev_mode = false
		G.add_item_count("stone", 1)
		G.enter_dream(); G.clarity = 100000.0
		G.frame_mark(Vector3i(0, 4, 0)); G.frame_mark(Vector3i(15, 19, 15))
		r.fill16.append(_t(func(): G.dream_fill("stone")))
		out["fill_cells"] = G.last_tool.n; out["fill_cost"] = G.last_tool.cost
		r.undo16.append(_t(func(): G.dream_undo()))
		r.redo16.append(_t(func(): G.dream_redo()))
		r.save_bp16.append(_t(func(): G.save_blueprint()))
		G.blueprint_shown = G.blueprints.size() - 1; G.paste_rot = 1
		r.paste16_rot1.append(_t(func(): G.paste_blueprint(Vector3i(100, 4, 100))))
		out["paste_cells"] = G.last_tool.n
		var hold: Array = [{}]   # лямбды GDScript захватывают локальные по значению — держим в массиве
		r.save_with_bp.append(_t(func(): hold[0] = JSON.parse_string(JSON.stringify(G.to_save_dict()))))
		out["save_bytes"] = JSON.stringify(hold[0]).length()
		r.load_with_bp.append(_t(func(): G.apply_save_dict(hold[0])))
		G.enter_dream(); G.clarity = 100000.0
		G.frame_mark(Vector3i(0, 4, 0)); G.frame_mark(Vector3i(15, 19, 15))
		r.clear16.append(_t(func(): G.dream_clear()))
		out["clear_cells"] = G.last_tool.n; out["dream_after_load"] = G.dream_blocks.size(); out["is_dream"] = G.is_dream();
		G.cycle_mirror(Vector3i(-50, 4, 0))
		r.mirror_place100.append(_t(func():
			for i in 100: G.dream_tool_place(Vector3i(-40 + i % 10, 4 + i / 10, 3), "stone")))
		G.mirror_axis = 0
		# заливка + реальная перестройка мешей слоя Сна
		var vox = load("res://scripts/voxel_world.gd").new(); vox.is_dream_layer = true; root.add_child(vox)
		await process_frame
		G.frame_mark(Vector3i(200, 4, 200)); G.frame_mark(Vector3i(215, 19, 215))
		var t := Time.get_ticks_usec()
		G.dream_fill("stone")
		for k in 4: await process_frame
		r.fill16_mesh.append(float(Time.get_ticks_usec() - t) / 1000.0)
		vox.free()
	for k in r: out[k + "_ms"] = snappedf(_med(r[k]), 0.01)
	print("BENCH17 ", JSON.stringify(out))
	G.reset_state()
	quit(0)
