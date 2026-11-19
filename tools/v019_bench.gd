extends SceneTree
## v0.19: стенд испытания. godot --headless --path . -s res://tools/v019_bench.gd → BENCH19 {json}
## Плюс «сим» плана: стена держит N фантомов, дыра — нет (таблица случаев).
func _init() -> void: call_deferred("_run")
func _med(a: Array) -> float:
	var b := a.duplicate(); b.sort(); return float(b[b.size() / 2])
func _house(n: int, kind: String, h: int, hole: bool) -> Dictionary:
	var b := {}
	for x in range(n):
		for z in range(n):
			b[Vector3i(x, 0, z)] = {"kind": "stone"}
			for y in range(1, 1 + h):
				if (x == 0 or x == n - 1 or z == 0 or z == n - 1) and not (hole and x == n / 2 and z == 0):
					b[Vector3i(x, y, z)] = {"kind": kind}
	return b
func _run() -> void:
	var T = load("res://scripts/dream_trial.gd")
	var out := {}
	for n in [9, 17, 41]:
		for cfg in [["stone", false], ["drift", false], ["stone", true]]:
			var src := _house(n, cfg[0], 2, cfg[1])
			var ts: Array = []; var r: Dictionary
			for i in range(5):
				var t := Time.get_ticks_usec(); r = T.run(src, Vector3i.ZERO, Vector3i(n - 1, 3, n - 1)); ts.append(float(Time.get_ticks_usec() - t) / 1000.0)
			out["%dx%d_%s%s" % [n, n, cfg[0], "_hole" if cfg[1] else ""]] = {"ms": snappedf(_med(ts), 0.01), "held": r.held, "grade": r.grade, "breaches": r.breaches, "broken": r.broken.size(), "ticks": r.ticks}
	# сим плана: сколько фантомов выдерживает каменная стена 9×9 и что с дырой
	var sim := {}
	for nph in [12, 24, 48, 96]:
		sim["wall_%d" % nph] = T.run(_house(9, "stone", 2, false), Vector3i.ZERO, Vector3i(8, 3, 8), nph).breaches
		sim["hole_%d" % nph] = T.run(_house(9, "stone", 2, true), Vector3i.ZERO, Vector3i(8, 3, 8), nph).breaches
	out["sim_breaches"] = sim
	print("BENCH19 ", JSON.stringify(out))
	quit(0)
