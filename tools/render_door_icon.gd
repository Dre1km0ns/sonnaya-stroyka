extends SceneTree
func _initialize() -> void:
	call_deferred("_render")
func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64,64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	viewport.add_child(env)
	var leaf := MeshInstance3D.new()
	leaf.mesh = preload("res://scripts/block_tex.gd").wooden_door_mesh()
	viewport.add_child(leaf)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-35,0)
	light.light_energy = 1.1
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.45
	viewport.add_child(camera)
	camera.position = Vector3(2.2,0.8,4.5)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image.save_png("res://assets/icons/door.png")==OK)
	print("DOOR ICON rendered")
	viewport.queue_free()
	await process_frame
	quit(0)
