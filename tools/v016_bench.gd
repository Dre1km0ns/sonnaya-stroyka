extends SceneTree
## v0.16: стенд «до/после» для постоянного Сна. Тот же файл запускается на v0.15 и v0.16.
## godot --headless --path . -s res://tools/v016_bench.gd
func _init() -> void: call_deferred("_run")

func _med(a: Array) -> float:
	var b := a.duplicate(); b.sort(); return float(b[b.size() / 2])

func _fill(G: Node, n: int) -> void:
	# 5000 блоков Сна: «посёлок» 50×50 по 2 слоя (дрейф — бесплатный в обеих версиях)
	var i := 0
	for x in range(50):
		for z in range(50):
			for y in range(2):
				if i >= n: return
				G.place_dream_block(Vector3i(x, 3 + y, z), "drift"); i += 1

func _run() -> void:
	var G: Node = root.get_node("GameState")
	var out := {"version": ProjectSettings.get_setting("application/config/name", "")}
	var place: Array = []; var prev: Array = []; var wake: Array = []; var save: Array = []; var load_t: Array = []
	var enter: Array = []; var sync: Array = []; var bytes := 0
	for rep in range(5):
		G.reset_state(); G.dev_mode = false
		G.pouch.reagent1 = 50; G.anchors3 = 3; G.nails = 3; G.wedges = 3
		for k in 2000: G.wake_blocks[Vector3i(k % 40 - 200, 0, k / 40)] = {"kind": "stone"}
		var t := Time.get_ticks_usec(); G.enter_dream(); enter.append(float(Time.get_ticks_usec() - t) / 1000.0)
		t = Time.get_ticks_usec(); _fill(G, 5000); place.append(float(Time.get_ticks_usec() - t) / 1000.0)
		G.select_anchor(G.AnchorType.WEDGE)
		t = Time.get_ticks_usec()
		for k in 50: G.anchor_preview(Vector3i(25, 4, 25))
		prev.append(float(Time.get_ticks_usec() - t) / 50.0)
		var vox = load("res://scripts/voxel_world.gd").new(); vox.is_dream_layer = true; root.add_child(vox)
		G.current_world = G.World.DREAM
		t = Time.get_ticks_usec(); vox.sync_from_state(); sync.append(float(Time.get_ticks_usec() - t) / 1000.0)
		vox.free()
		t = Time.get_ticks_usec(); var d: Dictionary = G.to_save_dict(); var js := JSON.stringify(d); save.append(float(Time.get_ticks_usec() - t) / 1000.0)
		bytes = js.length()
		var parsed: Dictionary = JSON.parse_string(js)
		t = Time.get_ticks_usec(); G.apply_save_dict(parsed); load_t.append(float(Time.get_ticks_usec() - t) / 1000.0)
		G.enter_dream(); G.clarity = 100.0; G.dev_mode = false; G.pouch.reagent1 = 50; G.anchors3 = 3
		G.select_anchor(G.AnchorType.ANCHOR3)
		var ok: bool = G.try_place_anchor(Vector3i(25, 4, 25))
		t = Time.get_ticks_usec(); var r: Dictionary = G.resolve_wake(); wake.append(float(Time.get_ticks_usec() - t) / 1000.0)
		out["wake_ok"] = ok; out["transferred"] = r.get("transferred", -1); out["dream_left_after_wake"] = G.dream_blocks.size()
	out["enter_dream_ms"] = _med(enter); out["place_5000_ms"] = _med(place); out["anchor_preview_wedge_us"] = _med(prev)
	out["dream_sync_5000_ms"] = _med(sync); out["save_ms"] = _med(save); out["save_bytes"] = bytes
	out["load_ms"] = _med(load_t); out["wake_anchor3_ms"] = _med(wake)
	print("BENCH016 ", JSON.stringify(out))
	quit()
