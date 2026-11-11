extends SceneTree
## v0.11.1: сравнительный бенчмарк — кеш факелов (GameState.torch_cells) против полного скана wake_blocks.
## godot --headless --path . -s res://tools/torch_cache_bench.gd
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var G: Node = root.get_node("GameState")
	for total in [2000, 20000, 60000]:
		G.reset_state()
		for i in range(total):
			G.wake_blocks[Vector3i(i % 200, i / 40000, (i / 200) % 200)] = {"kind": "torch" if i % 250 == 0 else "stone"}
		G.mark_torches_dirty()
		var iters := 200
		var t0 := Time.get_ticks_usec()
		var n1 := 0
		for k in range(iters):
			var out: Array = []
			for c in G.wake_blocks:
				if str((G.wake_blocks[c] as Dictionary).get("kind", "")) == "torch":
					out.append(c)
			n1 = out.size()
		var scan_us := float(Time.get_ticks_usec() - t0) / iters
		G.torch_cells()
		t0 = Time.get_ticks_usec()
		var n2 := 0
		for k in range(iters):
			n2 = G.torch_cells().size()
		var cache_us := float(Time.get_ticks_usec() - t0) / iters
		print("TORCHBENCH blocks=%d torches=%d/%d scan=%.1f us/call cache=%.2f us/call rebuilds=%d" % [total, n1, n2, scan_us, cache_us, G.torch_cache_rebuilds])
	quit(0)
