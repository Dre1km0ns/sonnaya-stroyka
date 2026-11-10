extends SceneTree
var tag:="before"
func _initialize():
	if not OS.get_cmdline_user_args().is_empty():tag=OS.get_cmdline_user_args()[0]
	call_deferred("run")
func run():
	var g=root.get_node("GameState");g.begin_world("water fixture","","6767676767",g.DEV_SEED,true)
	for x in range(12,20):
		for y in range(-2,0):
			for z in range(8,11):g.remove_terrain_cell_silent(Vector3i(x,y,z),"dirt")
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene;var player:=Node3D.new();scene.add_child(player)
	var cm=load("res://scripts/chunk_manager.gd").new();scene.add_child(cm);cm.setup(player,g.DEV_SEED);cm.set_process(false);cm.ensure_chunk_loaded(Vector2i.ZERO);cm.ensure_chunk_loaded(Vector2i(1,0))
	var source:=Vector3i(12,-1,9);cm._water_src[source]=true
	if "_water_src_by_chunk" in cm:
		if not cm._water_src_by_chunk.has(Vector2i.ZERO):cm._water_src_by_chunk[Vector2i.ZERO]={}
		cm._water_src_by_chunk[Vector2i.ZERO][source]=true
	cm.water_notify(source);var times:Array=[];var builds:=0
	for i in range(80):
		var started:=Time.get_ticks_usec();cm.water_step();builds+=cm._water_dirty.size();cm._rebuild_water_meshes();times.append((Time.get_ticks_usec()-started)/1000.0)
	var cpu:=0.0
	for ms in times:cpu+=ms
	times.sort();print("WATER ",JSON.stringify({"tag":tag,"steps":80,"cells":cm.water_cell_count(),"border_level":cm.water_level(Vector3i(16,-2,9)),"cpu_sum_ms":cpu,"p95_ms":times[76],"max_ms":times[-1],"dirty_meshes":builds}))
	scene.queue_free();await process_frame;quit()
