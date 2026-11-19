extends SceneTree
## v0.18: стенд «Живого Сна». godot --headless --path . -s res://tools/v018_bench.gd → BENCH18 {json}
func _init() -> void: call_deferred("_run")

func _med(a: Array) -> float:
	var b := a.duplicate(); b.sort(); return float(b[b.size() / 2])

func _run() -> void:
	var G: Node = root.get_node("GameState")
	var r := {"nightmare64_ms": [], "nightmare0_ms": [], "destroy1000_twin_ms": [], "destroy1000_plain_ms": [], "patch64_ms": [], "save_ms": [], "load_ms": []}
	var out := {"version": ProjectSettings.get_setting("application/config/name", "")}
	for rep in range(5):
		G.reset_state(); G.dev_mode = false
		# Сон: 5000 блоков дрейфа (посёлок 50×50×2) + маяков нет, света нет — худший случай для кошмара
		for x in range(50):
			for z in range(50):
				for y in range(2): G.dream_blocks[Vector3i(x, 3 + y, z)] = {"kind": "drift", "anchored": false, "mutant": false}
		var t := Time.get_ticks_usec(); G.nightmare_tick(); r.nightmare0_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		for i in range(64): G.add_crack(Vector3i(3 + (i % 8) * 6, 3, 3 + (i / 8) * 6), "drift")
		t = Time.get_ticks_usec(); var nm: Dictionary = G.nightmare_tick(); r.nightmare64_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		out["nightmare_eaten"] = nm.eaten; out["cracks"] = nm.cracks
		# крюк разрушения: 1000 блоков Яви с двойником во Сне и 1000 без
		G.dream_cracks.clear()
		for i in range(1000):
			var c := Vector3i(200 + i % 40, 3, i / 40)
			G.wake_blocks[c] = {"kind": "stone"}; G.dream_blocks[c] = {"kind": "stone", "anchored": false, "mutant": false}
			G.wake_blocks[c + Vector3i(0, 0, 100)] = {"kind": "stone"}
		t = Time.get_ticks_usec()
		for i in range(1000): G.destroy_wake_structure(Vector3i(200 + i % 40, 3, 100 + i / 40))
		r.destroy1000_plain_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec()
		for i in range(1000): G.destroy_wake_structure(Vector3i(200 + i % 40, 3, i / 40))
		r.destroy1000_twin_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		out["cracks_after_destroy"] = G.dream_cracks.size()
		for k in G.dream_cracks.keys(): G.wake_blocks[G.key_cell(k)] = {"kind": "stone"}
		t = Time.get_ticks_usec(); out["patched"] = G.patch_cracks(); r.patch64_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		for i in range(64): G.add_crack(Vector3i(3 + i, 3, 3), "drift")
		var hold: Array = [{}]
		t = Time.get_ticks_usec(); hold[0] = JSON.parse_string(JSON.stringify(G.to_save_dict())); r.save_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec(); G.apply_save_dict(hold[0]); r.load_ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
		out["cracks_after_load"] = G.dream_cracks.size()
	for k in r: out[k] = snappedf(_med(r[k]), 0.01)
	print("BENCH18 ", JSON.stringify(out))
	G.reset_state()
	quit(0)
