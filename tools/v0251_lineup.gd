extends SceneTree
## v0.25.1: кадры моделей мобов и игрока — спереди, сбоку, в атаке, игрок в броне.
## DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v0251_lineup.gd -- --out=/workspace/shots/v0251
const Chunky := preload("res://scripts/chunky_body.gd")
var out := "/workspace/shots/v0251"
var models: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_go.call_deferred()

func _shot(name: String) -> void:
	for i in 4: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", name)

func _go() -> void:
	root.size = Vector2i(1600, 700)
	var w := Node3D.new(); root.add_child(w)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.62, 0.74, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.75, 0.78, 0.85); e.ambient_light_energy = 0.55
	env.environment = e; w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0); sun.light_energy = 1.1; sun.shadow_enabled = true; w.add_child(sun)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 30); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_texture = Chunky.pixel_tex("cloth", Color(0.38, 0.55, 0.28)); gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; gm.uv1_triplanar = true; gm.uv1_scale = Vector3.ONE * 0.5
	g.material_override = gm; w.add_child(g)
	var names := ["seam", "seam_elite", "ghost0", "ghost1", "ghost2", "ghost3", "jumper", "archer", "thief", "clown", "clown_shard", "clown_friend", "lizard", "player"]
	var x := -float(names.size() - 1) * 0.6
	for n in names:
		var m: Node3D = Chunky.make(n)
		w.add_child(m); m.position = Vector3(x, 0, 0); x += 1.2
		models.append(m)
	var ref := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1, 2, 1); ref.mesh = bm
	ref.position = Vector3(x + 0.4, 1, 0); w.add_child(ref)   # эталон: 2 блока
	var cam := Camera3D.new(); w.add_child(cam); cam.current = true; cam.fov = 40
	cam.position = Vector3(0.6, 1.4, 24); cam.look_at(Vector3(0.6, 0.9, 0))
	await _shot("40_lineup_front")
	for m in models: m.rotation.y = PI * 0.5
	await _shot("41_lineup_side")
	for m in models: m.rotation.y = 0.0
	# крупно: три группы спереди, сбоку и в атаке
	cam.fov = 32
	var cx := [-5.4, 0.6, 6.6]
	for gi in 3:
		cam.position = Vector3(cx[gi], 1.0, 7.0); cam.look_at(Vector3(cx[gi], 0.85, 0))
		for m in models: m.rotation.y = 0.0
		await _shot("42_group%d_front" % gi)
		for m in models: m.rotation.y = PI * 0.5
		await _shot("43_group%d_side" % gi)
		for m in models: m.rotation.y = 0.5
		for m in models: m.play_state("attack", true)
		for i in 9: await process_frame
		await _shot("44_group%d_attack" % gi)
	# v0.25.1: боссы — Анаконда, Мать блоков, блоклинг, ящерка
	for m in models: m.visible = false
	var A: Node3D = load("res://scripts/boss_anaconda.gd").new()
	A.process_mode = Node.PROCESS_MODE_DISABLED
	A._build_body()
	w.add_child(A)
	A._head.position = Vector3(-3.0, 1.6, 1.5)
	A._head.rotation.y = PI + 0.5
	var segs: Array = A._segs
	for i in segs.size():
		(segs[i] as Node3D).position = Vector3(-3.0 + sin(i * 0.5) * 1.2 + i * 0.1, 0.7 - minf(i, 3) * 0.05, 1.5 - (i + 1) * 1.0)
	var M: Node3D = Chunky.make("mother")
	w.add_child(M); M.position = Vector3(2.5, 0, 0); M.rotation.y = -0.4
	var L: Node3D = Chunky.make("lizard")
	w.add_child(L); L.position = Vector3(0.2, 0, 2.5); L.rotation.y = 0.9
	var BL: Node3D = load("res://scripts/blockling.gd").new()
	BL.process_mode = Node.PROCESS_MODE_DISABLED
	w.add_child(BL); BL.position = Vector3(4.6, 0, 1.5)
	cam.fov = 45; cam.position = Vector3(0.5, 3.2, 10); cam.look_at(Vector3(0.5, 1.0, 0))
	await _shot("48_bosses")
	M.play_state("attack", true); L.play_state("attack", true)
	cam.position = Vector3(3.5, 2.0, 6.5); cam.look_at(Vector3(2.0, 1.3, 0))
	for i in 9: await process_frame
	await _shot("49_mother_attack")
	cam.position = Vector3(-0.5, 2.4, 6); cam.look_at(Vector3(-2.5, 1.0, 0))
	await _shot("50_anaconda_lizard")
	A.visible = false; M.visible = false; L.visible = false; BL.visible = false
	# игроки в броне
	for m in models: m.visible = false
	var sets := [["wood_helmet", "wood_chest", "wood_legs", "wood_boots"], ["metal_helmet", "metal_chest", "metal_legs", "metal_boots"], ["scale_helmet", "scale_chest"], []]
	var suits := [Color(0.3, 0.4, 0.55), Color(0.55, 0.28, 0.24), Color(0.3, 0.45, 0.3), Color(0.55, 0.47, 0.25)]
	var ps: Array = []
	for i in 4:
		var p: Node3D = Chunky.make("player", {"h": 1.75, "suit": suits[i]})
		w.add_child(p); p.position = Vector3(-2.4 + i * 1.6, 0, 0); p.rotation.y = 0.35
		p.set_armor(sets[i]); ps.append(p)
	cam.fov = 35; cam.position = Vector3(0, 1.3, 8); cam.look_at(Vector3(0, 0.95, 0))
	await _shot("46_players_armor")
	for p in ps: p.play_state("attack", true)
	for i in 10: await process_frame
	await _shot("47_players_swing")
	quit()
