extends SceneTree
## Perf probe: loads main scene, enables mobs, walks player, records frame stats.
var t := 0.0
var frames: Array = []
var phase := 0
var started := false
var player: Node3D
var hitch := 0.0
var label := ""

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	label = args[0] if args.size() > 0 else "run"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	call_deferred("_go")

func _go() -> void:
	var gs = root.get_node_or_null("GameState")
	print("PERF autoload GameState=", gs != null)
	if gs:
		gs.dream_exit_count = (0 if "nomobs" in OS.get_cmdline_user_args() else 2)
	change_scene_to_file(_scene())
	started = true

func _scene() -> String:
	var args := OS.get_cmdline_user_args()
	return args[1] if args.size() > 1 else "res://scenes/main.tscn"

func _process(delta: float) -> bool:
	if not started:
		return false
	t += delta
	if current_scene == null:
		return false
	if player == null:
		player = current_scene.find_child("Player", true, false) as Node3D
		var gs2 = root.get_node_or_null("GameState")
		if gs2:
			gs2.dream_exit_count = (0 if "nomobs" in OS.get_cmdline_user_args() else 2)
	if t < 4.0:
		return false
	frames.append(delta)
	if t > 9.0 and player:
		# walk
		player.global_position += Vector3(12.0 * delta, 0, 6.0 * delta)
		if t < 19.0:
			hitch = maxf(hitch, delta)
	if t >= 9.0 and phase == 0:
		phase = 1
		_report("idle")
		frames.clear()
	if t >= 19.0 and phase == 1:
		phase = 2
		_report("walking")
		print("PERF %s max_frame_ms_while_walking=%.1f" % [label, hitch * 1000.0])
		quit(0)
	return false

func _report(what: String) -> void:
	var s := 0.0
	var mx := 0.0
	for f in frames:
		s += f
		mx = maxf(mx, f)
	var avg := s / maxf(1.0, frames.size())
	print("PERF %s %s frames=%d avg_ms=%.2f fps=%.1f max_ms=%.1f nodes=%d objects_in_frame=%d draw_calls=%d prims=%d proc_ms=%.2f phys_ms=%.2f" % [
		label, what, frames.size(), avg * 1000.0, 1.0 / maxf(avg, 0.0001), mx * 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	var enemies := get_nodes_in_group("enemy").size()
	print("PERF %s %s enemies=%d bodies=%d" % [label, what, enemies, Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
