extends SceneTree
## v0.14: хеш геометрии чанка — проверка, что оптимизация меша не меняет результат.
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var G: Node = root.get_node("GameState")
	G.reset_state(); G.current_world = G.World.DREAM
	var vox = load("res://scripts/voxel_world.gd").new(); vox.is_dream_layer = true; root.add_child(vox)
	var kinds := ["planks", "stone", "drift", "dirt", "log", "bricks"]
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for i in range(700):
		var c := Vector3i(rng.randi_range(0, 15), rng.randi_range(4, 9), rng.randi_range(0, 15))
		G.dream_blocks[c] = {"kind": kinds[i % kinds.size()], "anchored": i % 5 == 0}
	G.dream_blocks[Vector3i(3, 10, 3)] = {"kind": "torch"}
	vox.sync_from_state()
	var root3: Node = vox._placed_chunks[Vector2i(0, 0)]
	var mesh: ArrayMesh = (root3.get_child(0) as MeshInstance3D).mesh
	var a := mesh.surface_get_arrays(0)
	var h := 0
	var parts := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]
	var s := ""
	for k in parts:
		s += str(a[k].size()) + ":" + str(hash(var_to_bytes(a[k]))) + " "
	print("MESHHASH verts=%d %s" % [a[Mesh.ARRAY_VERTEX].size(), s])
	quit(0)
