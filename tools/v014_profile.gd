extends SceneTree
## v0.14: посекционный профиль тика Анаконды (тот же стенд, что v012_bench).
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var G: Node = root.get_node("GameState")
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
	for i in range(300): ana.tick(1.0 / 60.0)
	var fns := ["crossfire_level", "light_dps", "check_body_torch_contacts", "_update_seg_light", "held_torch_near", "is_invulnerable"]
	for f in fns:
		if not ana.has_method(f):
			print("PROF missing ", f); continue
		var t := Time.get_ticks_usec()
		for i in range(2000): ana.call(f)
		print("PROF %s %.2f us" % [f, float(Time.get_ticks_usec() - t) / 2000.0])
	var t2 := Time.get_ticks_usec()
	for i in range(2000): ana._track_torch_heat(pl, 1.0 / 60.0)
	print("PROF _track_torch_heat %.2f us" % (float(Time.get_ticks_usec() - t2) / 2000.0))
	t2 = Time.get_ticks_usec()
	for i in range(2000): ana._update_sense(pl, 1.0 / 60.0)
	print("PROF _update_sense %.2f us" % (float(Time.get_ticks_usec() - t2) / 2000.0))
	t2 = Time.get_ticks_usec()
	for i in range(2000): ana.tick(1.0 / 60.0)
	print("PROF tick %.2f us state=%s" % [float(Time.get_ticks_usec() - t2) / 2000.0, ana.STATE_NAMES[ana.state]])
	quit(0)
