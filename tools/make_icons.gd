extends SceneTree
## Генератор иконок предметов v0.5: рендерит 3D-модели/примитивы в PNG (res://assets/icons/).
## Запуск (нужен GPU-контекст): xvfb-run godot --rendering-driver opengl3 --path . -s res://tools/make_icons.gd

const SIZE := 128
var vp: SubViewport
var world: Node3D
var cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	vp.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.25
	vp.add_child(light)
	var light2 := DirectionalLight3D.new()
	light2.rotation_degrees = Vector3(-10, -140, 0)
	light2.light_energy = 0.35
	vp.add_child(light2)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	vp.add_child(cam)
	cam.position = Vector3(2.2, 1.8, 2.2)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	DirAccess.make_dir_recursive_absolute("res://assets/icons")
	var jobs := {
		"reagent1": func() -> Node3D: return _model("res://assets/models/reagent_crystal.glb", Vector3(0, 20, 0)),
		"reagent2": func() -> Node3D: return _model("res://assets/models/reagent_herb.glb", Vector3(0, 20, 0)),
		"reagent3": func() -> Node3D: return _model("res://assets/models/reagent_ore.glb", Vector3(0, 20, 0)),
		"pickaxe": func() -> Node3D: return _model("res://assets/models/pickaxe.glb", Vector3(0, 45, 35)),
		"sword": func() -> Node3D: return _model("res://assets/models/sword.glb", Vector3(0, 45, 40)),
		"hill": func() -> Node3D: return _cube(Color(0.48, 0.55, 0.40), Color(0.40, 0.33, 0.24)),
		"ground": func() -> Node3D: return _cube(Color(0.55, 0.62, 0.48), Color(0.45, 0.36, 0.26)),
		"ruin": func() -> Node3D: return _cube(Color(0.50, 0.42, 0.34), Color(0.42, 0.35, 0.28), true),
		"drift": func() -> Node3D: return _cube(Color(0.72, 0.58, 0.42), Color(0.64, 0.50, 0.36)),
		"mouth": func() -> Node3D: return _mouth(),
		"workbench": func() -> Node3D: return _workbench(),
		"torch": func() -> Node3D: return _torch(),
		"dust": func() -> Node3D: return _dust(),
		"nail": func() -> Node3D: return _nail(),
		"wedge": func() -> Node3D: return _wedge(),
		"anchor3": func() -> Node3D: return _anchor(),
		"beacon": func() -> Node3D: return _beacon(),
		"unknown": func() -> Node3D: return _cube(Color(0.6, 0.6, 0.65), Color(0.5, 0.5, 0.55)),
	}
	for id in jobs.keys():
		var n: Node3D = (jobs[id] as Callable).call()
		var holder := Node3D.new()
		holder.add_child(n)
		vp.add_child(holder)
		_fit(holder, n)
		var zoom := {"pickaxe": 1.9, "sword": 1.75, "torch": 1.45, "nail": 1.45, "anchor3": 1.5, "beacon": 1.15, "reagent3": 1.15, "dust": 1.2}
		cam.size = 1.7 / float(zoom.get(id, 1.0))
		for _i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(96, 96, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/icons/%s.png" % id)
		print("ICON ", id)
		holder.queue_free()
		await process_frame
	quit(0)


func _fit(holder: Node3D, n: Node3D) -> void:
	var aabb := _aabb(n, n.global_transform.affine_inverse())
	var s := 1.15 / maxf(0.001, maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)))
	n.scale *= s
	aabb = _aabb(holder, holder.global_transform.affine_inverse())
	n.position -= aabb.get_center()


func _aabb(n: Node, inv: Transform3D) -> AABB:
	var acc := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi := c as MeshInstance3D
			var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			if first:
				acc = a
				first = false
			else:
				acc = acc.merge(a)
		for ch in c.get_children():
			stack.append(ch)
	return acc


func _mat(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _mi(mesh: Mesh, c: Color, pos: Vector3 = Vector3.ZERO, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, emit)
	mi.position = pos
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _model(path: String, rot: Vector3) -> Node3D:
	var packed: PackedScene = load(path)
	var n: Node3D = packed.instantiate()
	var wrap := Node3D.new()
	wrap.add_child(n)
	n.rotation_degrees = rot
	return wrap


func _cube(top: Color, side: Color, bricks: bool = false) -> Node3D:
	var r := Node3D.new()
	r.add_child(_mi(_box(Vector3(1, 0.82, 1)), side, Vector3(0, -0.09, 0)))
	r.add_child(_mi(_box(Vector3(1.002, 0.18, 1.002)), top, Vector3(0, 0.41, 0)))
	if bricks:
		for i in range(3):
			r.add_child(_mi(_box(Vector3(1.01, 0.04, 1.01)), side.darkened(0.3), Vector3(0, -0.35 + i * 0.27, 0)))
	return r


func _mouth() -> Node3D:
	var r := _cube(Color(0.80, 0.30, 0.38), Color(0.70, 0.22, 0.30))
	r.add_child(_mi(_box(Vector3(0.62, 0.16, 0.04)), Color(0.15, 0.02, 0.05), Vector3(0, -0.05, 0.51)))
	r.add_child(_mi(_box(Vector3(0.04, 0.16, 0.62)), Color(0.15, 0.02, 0.05), Vector3(0.51, -0.05, 0)))
	return r


func _workbench() -> Node3D:
	var r := Node3D.new()
	r.add_child(_mi(_box(Vector3(0.9, 0.8, 0.9)), Color(0.46, 0.30, 0.18), Vector3(0, -0.1, 0)))
	r.add_child(_mi(_box(Vector3(1.1, 0.16, 1.1)), Color(0.62, 0.42, 0.24), Vector3(0, 0.36, 0)))
	r.add_child(_mi(_box(Vector3(0.5, 0.05, 0.3)), Color(0.55, 0.55, 0.6), Vector3(0.1, 0.46, -0.1)))
	r.add_child(_mi(_box(Vector3(0.08, 0.08, 0.5)), Color(0.35, 0.22, 0.12), Vector3(-0.3, 0.48, 0.15)))
	return r


func _torch() -> Node3D:
	var r := Node3D.new()
	var stick := CylinderMesh.new()
	stick.top_radius = 0.06
	stick.bottom_radius = 0.06
	stick.height = 1.0
	r.add_child(_mi(stick, Color(0.48, 0.30, 0.14)))
	var flame := SphereMesh.new()
	flame.radius = 0.16
	flame.height = 0.4
	r.add_child(_mi(flame, Color(1.0, 0.62, 0.15), Vector3(0, 0.6, 0), 2.0))
	r.rotation_degrees = Vector3(0, 0, -25)
	return r


func _dust() -> Node3D:
	var r := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(26):
		var s := SphereMesh.new()
		var rad := rng.randf_range(0.07, 0.15)
		s.radius = rad
		s.height = rad * 2.0
		var a := rng.randf() * TAU
		var d := rng.randf() * 0.42
		var y := (0.42 - d) * 0.7 + rng.randf() * 0.05
		var c := Color(0.92, 0.78, 0.66).lerp(Color(0.62, 0.55, 0.85), rng.randf())
		r.add_child(_mi(s, c, Vector3(cos(a) * d, y, sin(a) * d), 0.35))
	return r


func _nail() -> Node3D:
	var r := Node3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.06
	shaft.bottom_radius = 0.02
	shaft.height = 1.0
	r.add_child(_mi(shaft, Color(0.95, 0.72, 0.55), Vector3.ZERO, 0.4))
	var head := CylinderMesh.new()
	head.top_radius = 0.2
	head.bottom_radius = 0.2
	head.height = 0.08
	r.add_child(_mi(head, Color(1.0, 0.78, 0.6), Vector3(0, 0.52, 0), 0.4))
	r.rotation_degrees = Vector3(0, 0, -30)
	return r


func _wedge() -> Node3D:
	var r := Node3D.new()
	var p := PrismMesh.new()
	p.size = Vector3(0.9, 1.0, 0.5)
	var mi := _mi(p, Color(0.98, 0.70, 0.52), Vector3.ZERO, 0.35)
	mi.rotation_degrees = Vector3(0, 0, 180)
	r.add_child(mi)
	return r


func _anchor() -> Node3D:
	var r := Node3D.new()
	var shank := CylinderMesh.new()
	shank.top_radius = 0.07
	shank.bottom_radius = 0.07
	shank.height = 1.0
	r.add_child(_mi(shank, Color(1.0, 0.70, 0.45), Vector3.ZERO, 0.5))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.1
	ring.outer_radius = 0.18
	var rmi := _mi(ring, Color(1.0, 0.70, 0.45), Vector3(0, 0.6, 0), 0.5)
	rmi.rotation_degrees = Vector3(90, 0, 0)
	r.add_child(rmi)
	r.add_child(_mi(_box(Vector3(0.6, 0.08, 0.08)), Color(1.0, 0.70, 0.45), Vector3(0, 0.32, 0), 0.5))
	var arc := TorusMesh.new()
	arc.inner_radius = 0.36
	arc.outer_radius = 0.46
	var ami := _mi(arc, Color(1.0, 0.62, 0.38), Vector3(0, -0.42, 0), 0.5)
	ami.rotation_degrees = Vector3(90, 0, 0)
	r.add_child(ami)
	return r


func _beacon() -> Node3D:
	var r := Node3D.new()
	r.add_child(_mi(_box(Vector3(0.8, 0.35, 0.8)), Color(0.32, 0.36, 0.44), Vector3(0, -0.4, 0)))
	var core := SphereMesh.new()
	core.radius = 0.22
	core.height = 0.44
	r.add_child(_mi(core, Color(0.45, 0.95, 1.0), Vector3(0, -0.05, 0), 2.0))
	var beam := CylinderMesh.new()
	beam.top_radius = 0.12
	beam.bottom_radius = 0.12
	beam.height = 0.9
	r.add_child(_mi(beam, Color(0.6, 1.0, 1.0), Vector3(0, 0.55, 0), 1.5))
	return r
