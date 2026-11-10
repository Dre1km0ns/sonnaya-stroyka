extends SceneTree
var samples: Array[float] = []
func _init() -> void:
	call_deferred("run")
func run() -> void:
	Engine.max_fps = 60
	var p := Node3D.new()
	root.add_child(p)
	p.position = Vector3(100,3,100)
	var cm: Node3D = load("res://scripts/chunk_manager.gd").new()
	root.add_child(cm)
	cm.set_process(false)
	cm.circular_loading = false
	cm.legacy_generation = "--legacy" in OS.get_cmdline_user_args()
	cm.load_radius = 3
	cm.unload_radius = 4
	var start := Time.get_ticks_usec()
	cm.setup(p,6767676767)
	var startup := float(Time.get_ticks_usec()-start)/1000.0
	var work: Array[float] = []
	var prev := Time.get_ticks_usec()
	var frames := 0
	while cm.get_pending_count() > 0 and frames < 3600:
		var t := Time.get_ticks_usec()
		cm._drain_pending()
		work.append(float(Time.get_ticks_usec()-t)/1000.0)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-prev)/1000.0)
		prev = now
		frames += 1
	samples.sort()
	work.sort()
	var over := 0
	for f in samples:
		if f>33.34: over += 1
	print("HITCH_RESULT ",JSON.stringify({"startup_ms":startup,"frames":frames,"loaded":cm.get_loaded_count(),"frame_p95_ms":samples[int((samples.size()-1)*0.95)],"frame_max_ms":samples.back(),"work_p95_ms":work[int((work.size()-1)*0.95)],"work_max_ms":work.back(),"frames_over_33ms":over,"total_ms":float(Time.get_ticks_usec()-start)/1000.0}))
	cm.queue_free()
	p.queue_free()
	await process_frame
	quit()
