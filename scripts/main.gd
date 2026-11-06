extends Node3D
## Главная сцена v0.4.4: реагенты, инвентарь, призраки, руины/озёра.

@onready var player: CharacterBody3D = $Player
@onready var wake_world: Node3D = $WakeWorld
@onready var dream_world: Node3D = $DreamWorld
@onready var wake_voxels: Node3D = $WakeWorld/WakeVoxels
@onready var dream_voxels: Node3D = $DreamWorld/DreamVoxels
@onready var bed: StaticBody3D = $WakeWorld/Bed
@onready var build: Node = $Systems/BuildController
@onready var anchors: Node = $Systems/AnchorSystem
@onready var switcher: Node = $Systems/WorldSwitcher
@onready var wake_chunks: Node3D = $WakeWorld/WakeChunks
@onready var dream_chunks: Node3D = $DreamWorld/DreamChunks
@onready var threat: Node = $Systems/ThreatDirector
@onready var saver: Node = $Systems/SaveSystem


func _ready() -> void:
	build.setup(player, dream_voxels)
	anchors.setup(player, dream_voxels)
	switcher.setup(player, wake_world, dream_world, bed, wake_voxels, dream_voxels)
	threat.setup(player, wake_world, bed)
	saver.setup(self, player, wake_voxels, dream_voxels, threat)
	if wake_chunks and wake_chunks.has_method("setup"):
		wake_chunks.setup(player, GameState.world_seed_wake)
	if dream_chunks and dream_chunks.has_method("setup"):
		dream_chunks.setup(player, GameState.world_seed_dream)
	var day_script: GDScript = load("res://scripts/day_cycle.gd")
	var day: Node = day_script.new()
	$Systems.add_child(day)
	var sun := wake_world.get_node_or_null("Sun") as DirectionalLight3D
	var fill := wake_world.get_node_or_null("WarmFill") as OmniLight3D
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if day.has_method("setup"):
		day.setup(sun, we.environment if we else null, fill)
	# Автозагрузка при старте, если есть сейв
	_start_music()
	if _want_shots():
		call_deferred("_capture_shots")
	elif saver.has_save():
		saver.load_game()
		GameState.set_hint("Продолжение с диска (F5 сейв / F9 лоад).")
	print("Сонная стройка v0.4.4 ready. Path OK.")


func apply_world_visibility(is_dream: bool) -> void:
	if switcher and switcher.has_method("_apply_visibility"):
		switcher.call("_apply_visibility", is_dream)
	if switcher and switcher.has_method("_tint_dream"):
		switcher.call("_tint_dream", is_dream)
	if "flying" in player:
		player.set("flying", is_dream)


func _start_music() -> void:
	if has_node("MusicController"):
		return
	var script: GDScript = load("res://scripts/music_controller.gd")
	var mc: Node = script.new()
	mc.name = "MusicController"
	add_child(mc)


func _want_shots() -> bool:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return "--shots" in args


func _save_shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "/workspace/shots/%s" % name
	img.save_png(path)
	print("SHOT saved ", path, " ", img.get_width(), "x", img.get_height())


func _capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	GameState.dust = 400
	GameState.nails = 5
	GameState.wedges = 2
	GameState.anchors3 = 1
	GameState.reagent_counts = [20, 20, 20]
	GameState.reagents = 60
	GameState.inventory_changed.emit()
	await get_tree().create_timer(1.2).timeout
	var lake_p: Vector3 = Vector3(8, 1.5, 16)
	if wake_chunks and wake_chunks.has_method("get_any_lake_sample_point"):
		var sample: Vector3 = wake_chunks.get_any_lake_sample_point()
		if sample != Vector3.ZERO:
			lake_p = sample
	var sides: Array = [
		["water_n.png", Vector3(0, 2.4, -6.5)],
		["water_e.png", Vector3(6.5, 2.4, 0)],
		["water_s.png", Vector3(0, 2.4, 6.5)],
		["water_w.png", Vector3(-6.5, 2.4, 0)],
	]
	for entry in sides:
		var fname: String = str(entry[0])
		var off: Vector3 = entry[1]
		var pos: Vector3 = Vector3(lake_p.x, 2.4, lake_p.z) + off
		pos.y = 2.5
		player.global_position = pos
		var look: Vector3 = Vector3(lake_p.x, 0.2, lake_p.z)
		var dir: Vector3 = look - pos
		player.rotation.y = atan2(-dir.x, -dir.z)
		if player.has_node("CameraPivot"):
			player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
		await get_tree().create_timer(0.2).timeout
		await _save_shot(fname)
	# Плоская площадка у спавна (height_at == 0), камера смотрит на -Z.
	var stage := Vector3(6.0, 0.0, 6.0)
	var rscript: GDScript = load("res://scripts/reagent_node.gd")
	for i in range(3):
		var rn: StaticBody3D = rscript.new()
		rn.configure(i + 1, "shot-%d" % i, 1)
		rn.position = stage + Vector3(float(i) * 1.15 - 1.15, 0.35, 0.0)
		wake_world.add_child(rn)
	player.global_position = stage + Vector3(0.0, 1.55, 3.3)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
	await get_tree().create_timer(0.3).timeout
	await _save_shot("reagents.png")
	var gs := load("res://scripts/seam_creature.gd")
	var gg := load("res://scripts/enemy_ghost.gd")
	var look2 := stage + Vector3(0.0, 0.0, -0.4)
	var seam: CharacterBody3D = gs.new()
	seam.position = look2 + Vector3(-1.3, 0.0, 0.0)
	wake_world.add_child(seam)
	var ghosts: Array[Node] = []
	for i2 in range(4):
		var g: CharacterBody3D = gg.new()
		g.configure(i2, look2, look2)
		g.position = look2 + Vector3(float(i2) * 1.25 - 0.4, 0.0, 0.15)
		wake_world.add_child(g)
		ghosts.append(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var vis: GDScript = load("res://scripts/enemy_visuals.gd")
	vis.play_state(seam, "walk", true)
	for g2 in ghosts:
		vis.play_state(g2, "walk", true)
	player.global_position = look2 + Vector3(0.2, 1.85, 4.6)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-8, 0, 0)
	await get_tree().create_timer(0.45).timeout
	await _save_shot("enemy_walk.png")
	vis.play_state(seam, "attack", true)
	for g3 in ghosts:
		vis.play_state(g3, "attack", true)
	await get_tree().create_timer(0.35).timeout
	await _save_shot("enemy_attack.png")
	if seam.has_method("take_damage"):
		seam.take_damage(20)
	for g4 in ghosts:
		if g4.has_method("take_damage"):
			g4.take_damage(15)
	GameState.add_item("sword", "Меч", 1)
	for si in range(GameState.ITEM_SLOT_COUNT):
		if str(GameState.item_slots[si].get("id", "")) == "sword":
			GameState.select_item_slot(si)
			break
	if build.has_method("_play_sword_swing"):
		build._play_sword_swing()
	if build.has_method("_try_sword"):
		build._try_sword()
	await get_tree().create_timer(0.28).timeout
	await _save_shot("sword_hit.png")
	var boss_script: GDScript = load("res://scripts/block_mother.gd")
	var boss: Node3D = boss_script.spawn_near(wake_world, Vector3i(int(look2.x), 0, int(look2.z)))
	if boss:
		boss.global_position = look2 + Vector3(0.15, 0.05, 0.2)
	await get_tree().create_timer(0.45).timeout
	player.global_position = look2 + Vector3(0.2, 2.3, 6.4)
	player.rotation_degrees = Vector3(0, 0, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
	await _save_shot("boss.png")
	var report := []
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("collect_collision_issues"):
			var issues: Array = cm.collect_collision_issues()
			report.append("%s issues=%d active=%s planar=%s" % [
				cm.name, issues.size(),
				cm._physics_active() if cm.has_method("_physics_active") else "?",
				cm.lake_water_is_planar() if cm.has_method("lake_water_is_planar") else "?"
			])
			for it in issues:
				report.append("  %s" % str(it))
	var rf := FileAccess.open("/workspace/shots/collision_report.txt", FileAccess.WRITE)
	if rf:
		rf.store_string("\n".join(report))
	print("SHOT report:\n", "\n".join(report))
	get_tree().quit(0)
