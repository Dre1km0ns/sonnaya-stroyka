extends SceneTree
var tag:="before"
var G:Node
var camera:Camera3D
func _initialize():
	if not OS.get_cmdline_user_args().is_empty():tag=OS.get_cmdline_user_args()[0]
	call_deferred("run")
func stats(label:String,samples:Array,extra:Dictionary={}):
	var sorted:=samples.duplicate();sorted.sort();var sum:=0.0
	for value in samples:sum+=value
	var row:Dictionary={"tag":tag,"case":label,"avg_ms":sum/maxi(1,samples.size()),"p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max_ms":sorted[-1],"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	row.merge(extra,true);print("STRESS "+JSON.stringify(row))
func frames(n:int)->Array:
	var values:Array=[]
	for i in range(n):var start:=Time.get_ticks_usec();await process_frame;values.append((Time.get_ticks_usec()-start)/1000.0)
	return values
func run():
	G=root.get_node("GameState");G.begin_world("stress","","12345",12345,true)
	var stage:=Node3D.new();root.add_child(stage);current_scene=stage
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);stage.add_child(light)
	for n in [100,500,1000]:
		G.reset_state();var vox=load("res://scripts/voxel_world.gd").new();stage.add_child(vox)
		for i in range(n):G.place_wake_block(Vector3i(i%20,int(i/200),int(i/20)%10),"planks")
		vox._rebuild_from_state();camera.position=Vector3(20,16,30);camera.look_at(Vector3(10,2,5));await frames(5)
		stats("base_render_%d"%n,await frames(40));vox.queue_free();await process_frame
	G.reset_state();var doors=load("res://scripts/voxel_world.gd").new();stage.add_child(doors)
	var positions:Array[Vector3i]=[]
	for i in range(100):
		var c:=Vector3i((i%10)*2,0,int(i/10)*3);positions.append(c);G.place_wake_block(c,"door")
	doors._rebuild_from_state();camera.position=Vector3(20,18,37);camera.look_at(Vector3(9,1,12));await frames(5)
	stats("doors100_render",await frames(60))
	var toggle:Array=[]
	for i in range(60):
		var started:=Time.get_ticks_usec();G.toggle_door(positions[i%100]);toggle.append((Time.get_ticks_usec()-started)/1000.0);await process_frame
	stats("doors100_toggle",toggle);doors.queue_free();await process_frame
	G.reset_state();var player:=Node3D.new();stage.add_child(player)
	var cm=load("res://scripts/chunk_manager.gd").new();stage.add_child(cm)
	var start:=Time.get_ticks_usec();cm.setup(player,12345);var setup_ms:=(Time.get_ticks_usec()-start)/1000.0
	var stream_frames:Array=[]
	for i in range(40):
		start=Time.get_ticks_usec();player.position=Vector3(i*32,3,(i%3)*32);camera.position=player.position+Vector3(0,12,20);camera.look_at(player.position)
		cm._update_chunks(true);cm.rebuild_chunk_at_world(int(player.position.x),int(player.position.z));await process_frame
		stream_frames.append((Time.get_ticks_usec()-start)/1000.0)
	for i in range(180):
		if cm._pending.is_empty() and cm._jobs.is_empty():break
		await process_frame
	var over:=0
	for ms in stream_frames:
		if ms>33:over+=1
	stats("rapid_streaming",stream_frames,{"setup_ms":setup_ms,"over33ms":over,"loaded":cm.get_loaded_count(),"jobs_left":cm._jobs.size(),"stale":cm.stale_jobs_discarded if "stale_jobs_discarded" in cm else -1})
	stage.queue_free();await process_frame;paused=true
	for audio in root.find_children("*","AudioStreamPlayer",true,false)+root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.queue_free()
	await create_timer(0.3).timeout;print("STRESS COMPLETE "+tag);quit()
