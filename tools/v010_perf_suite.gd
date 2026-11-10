extends SceneTree
var tag := "before"
var frames: Array[float] = []
func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty(): tag=OS.get_cmdline_user_args()[0]
	call_deferred("run")
func pct(a: Array, p: float) -> float:
	var b=a.duplicate();b.sort();return b[mini(b.size()-1,int(b.size()*p))] if not b.is_empty() else 0.0
func stats(label: String, a: Array, extra: Dictionary={}) -> void:
	var d={"tag":tag,"case":label,"avg_ms":0.0,"p95_ms":pct(a,0.95),"p99_ms":pct(a,0.99),"max_ms":pct(a,1),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"meshes":root.find_children("*","MeshInstance3D",true,false).size(),"bodies":root.find_children("*","CollisionObject3D",true,false).size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	for t in a:d.avg_ms+=t/maxi(a.size(),1)
	d.merge(extra,true);print("SUITE "+JSON.stringify(d))
func sample(n: int) -> Array:
	var a=[]
	for i in range(n):
		var t=Time.get_ticks_usec();await process_frame;a.append((Time.get_ticks_usec()-t)/1000.0)
	return a
func run() -> void:
	var G=root.get_node("GameState")
	for n in [100,500,1000]:
		G.reset_state();G.current_world=G.World.DREAM
		var vox=load("res://scripts/voxel_world.gd").new();vox.is_dream_layer=true;root.add_child(vox)
		var a=[]
		for i in range(n):
			var c=Vector3i(i%40,5+int(i/400),int(i/40)%10)
			var t=Time.get_ticks_usec();G.place_dream_block(c,"planks")
			if vox.has_method("flush_dirty"):vox.flush_dirty()
			else:vox._rebuild_from_state()
			a.append((Time.get_ticks_usec()-t)/1000.0);await process_frame
		stats("build_%d"%n,a,{"sum_ms":a.reduce(func(x,y):return x+y,0.0)})
		var remove=[]
		for c in G.dream_blocks.keys():
			var t=Time.get_ticks_usec();G.remove_dream_block(c)
			if vox.has_method("flush_dirty"):vox.flush_dirty()
			else:vox._rebuild_from_state()
			remove.append((Time.get_ticks_usec()-t)/1000.0);await process_frame
		stats("remove_%d"%n,remove)
		vox.queue_free();await process_frame
	G.begin_world("benchmark","","6767676767",G.DEV_SEED,true)
	var scene=load("res://scenes/main.tscn").instantiate();scene.set_meta("smoke",true)
	var t=Time.get_ticks_usec();root.add_child(scene);current_scene=scene;scene.switcher.show_result_ui=false
	stats("startup",[(Time.get_ticks_usec()-t)/1000.0])
	await create_timer(1.5).timeout
	var console=get_first_node_in_group("dev_console")
	console.execute("god")
	Input.action_press("move_forward");Input.action_press("sprint")
	stats("walking_physics",await sample(90));Input.action_release("move_forward");Input.action_release("sprint")
	for i in range(2):
		t=Time.get_ticks_usec();scene.switcher.enter_dream();stats("enter_dream",[(Time.get_ticks_usec()-t)/1000.0]);await sample(4)
		t=Time.get_ticks_usec();scene.switcher.wake_up();stats("wake",[(Time.get_ticks_usec()-t)/1000.0]);await sample(4)
	console.execute("spawn enemy1 7");var nav=load("res://scripts/enemy_navigation.gd");nav.ai_max_frame_usec=0;stats("seven_enemies",await sample(90),{"ai_max_work_us":nav.ai_max_frame_usec,"ai_paths":nav.ai_paths_completed})
	console.execute("spawn mother");stats("boss",await sample(90));console.execute("kill all")
	scene.player.auto_pickup_enabled=false
	for i in range(300):
		var item=load("res://scripts/block_pickup.gd").new();item.configure("stone");item.position=scene.player.global_position+Vector3((i%10)*0.1,0,(i/10)*0.03);scene.wake_world.add_child(item)
	await physics_frame;await physics_frame
	t=Time.get_ticks_usec();var picked=scene.player.auto_pickup();var first=(Time.get_ticks_usec()-t)/1000.0
	stats("mass_pickup",[first],{"picked":picked,"candidates":scene.player.pickup_last_candidates})
	var calls=[first];var total=picked;var wall_start=Time.get_ticks_usec()
	for i in range(20):
		if total>=300:break
		await physics_frame;t=Time.get_ticks_usec();total+=scene.player.auto_pickup();calls.append((Time.get_ticks_usec()-t)/1000.0)
	stats("mass_pickup_total",calls,{"picked":total,"cpu_sum_ms":calls.reduce(func(x,y):return x+y,0.0),"wall_ms":(Time.get_ticks_usec()-wall_start)/1000.0})
	# Actual flowing-water fixture crossing x15/16, unlike invalid old water_cells=0 row.
	scene.player.global_position=Vector3(14,0.1,12);scene.player.camera.look_at(Vector3(16,-1,9))
	var cm=scene.wake_chunks;cm.ensure_chunk_loaded(Vector2i.ZERO);cm.ensure_chunk_loaded(Vector2i(1,0))
	console.execute("fill air 12 -2 8 19 -1 10");cm.load_all_pending()
	var source=Vector3i(12,-1,9);cm._water_src[source]=true
	if not cm._water_src_by_chunk.has(Vector2i.ZERO):cm._water_src_by_chunk[Vector2i.ZERO]={}
	cm._water_src_by_chunk[Vector2i.ZERO][source]=true;cm.water_notify(source)
	stats("water_active",await sample(90),{"water_cells":cm.water_cell_count(),"mesh_builds":cm.water_mesh_builds,"mesh_us":cm.water_mesh_last_usec})
	scene.queue_free();await process_frame
	paused=true
	for audio in root.find_children("*","AudioStreamPlayer",true,false)+root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.queue_free()
	await create_timer(0.3).timeout
	print("SUITE COMPLETE "+tag);quit(0)
