extends SceneTree
## «Всё про всё»: крупные планы блоков. DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/doc_blocks.gd
const OUT := "/workspace/doc/shots/blocks/"
const BT := preload("res://scripts/block_tex.gd")
func _init() -> void: call_deferred("_go")
func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var w := Node3D.new(); root.add_child(w)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.55, 0.62, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.8, 0.8, 0.85); env.environment.ambient_light_energy = 0.7
	w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0); sun.light_energy = 1.1; w.add_child(sun)
	var cam := Camera3D.new(); w.add_child(cam); cam.fov = 40
	var kinds := ["dirt","sand","stone","deep_stone","bedrock","ruin","mossy_ruin","log","leaves","planks","drift","mouth","nest","egg","beacon","strut","torch","bed","workbench","sawmill","lathe","alchemy","idea_catcher","chest","door"]
	var dream_variants := {"drift_dream": "drift_dream", "drift_anchored": "drift_anchored", "ground_dream": "ground", "hill_dream": "hill", "stone_dream": "stone"}
	var jobs := []
	for k in kinds: jobs.append([k, k, false])
	for k in dream_variants: jobs.append([k, dream_variants[k], true])
	for j in jobs:
		var mi := MeshInstance3D.new(); w.add_child(mi)
		var k: String = j[1]
		var center := Vector3(0.5, 0.5, 0.5)
		if k == "torch": mi.mesh = BT.torch_mesh()
		elif k == "bed": mi.mesh = BT.bed_mesh(2.0); center = Vector3(0.5, 0.4, 1.0)
		elif k in ["lathe","sawmill","alchemy","idea_catcher","chest","door"]: mi.mesh = BT.station_mesh(k)
		else: mi.mesh = BT.cube_mesh(k, Vector3.ONE, j[2])
		if k == "chest":
			var lid := MeshInstance3D.new(); lid.mesh = BT.chest_lid_mesh(); lid.position = BT.CHEST_HINGE; mi.add_child(lid)
		var ab: AABB = mi.mesh.get_aabb(); center = ab.get_center()
		var r: float = ab.size.length()
		cam.position = center + Vector3(1.0, 0.8, 1.3).normalized() * r * 1.6
		cam.look_at(center)
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.crop(1280, 720)
		var sq := img.get_region(Rect2i(280, 0, 720, 720)); sq.resize(360, 360)
		sq.save_png(OUT + str(j[0]) + ".png"); print("SHOT ", j[0])
		mi.queue_free()
	quit()
