extends Node3D
## Главная сцена v0.4.3: реагенты, инвентарь, призраки, руины/озёра.

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
	print("Сонная стройка v0.4.3 ready. Path OK.")


func apply_world_visibility(is_dream: bool) -> void:
	if switcher and switcher.has_method("_apply_visibility"):
		switcher.call("_apply_visibility", is_dream)
	if switcher and switcher.has_method("_tint_dream"):
		switcher.call("_tint_dream", is_dream)
	if "flying" in player:
		player.set("flying", is_dream)


func _start_music() -> void:
	if has_node("MusicPlayer"):
		return
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	var stream: Resource = load("res://assets/audio/music.mp3")
	if stream == null:
		push_warning("music.mp3 missing")
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	player.stream = stream
	player.volume_db = -8.0
	player.bus = "Music"
	add_child(player)
	player.play()


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
	await get_tree().create_timer(1.2).timeout
	player.global_position = Vector3(8, 3.4, 16)
	player.rotation_degrees = Vector3(0, 40, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-16, 0, 0)
	await _save_shot("terrain_day.png")
	player.global_position = Vector3(32, 5.0, 32)
	player.rotation_degrees = Vector3(0, 55, 0)
	await _save_shot("terrain_day_hills.png")
	var look := player.global_position + Vector3(3.2, 0.0, 1.4)
	var gs := load("res://scripts/seam_creature.gd")
	var gg := load("res://scripts/enemy_ghost.gd")
	var spawned: Array[Node] = []
	var seam: CharacterBody3D = gs.new()
	seam.position = look
	wake_world.add_child(seam)
	spawned.append(seam)
	for i in range(4):
		var g: CharacterBody3D = gg.new()
		g.configure(i, look, look)
		g.position = look + Vector3(float(i) * 1.4 - 1.6, 0.0, 2.2)
		wake_world.add_child(g)
		spawned.append(g)
	player.global_position = look + Vector3(-3.5, 2.2, -4.5)
	player.rotation_degrees = Vector3(0, 200, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-12, 0, 0)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("enemies.png")
	for menu in get_tree().get_nodes_in_group("craft_menu"):
		if menu.has_method("open_general"):
			menu.open_general()
	await get_tree().create_timer(0.25).timeout
	await _save_shot("craft_menu.png")
	for menu2 in get_tree().get_nodes_in_group("craft_menu"):
		if menu2.has_method("close"):
			menu2.close()
	GameState.day_time = 330.0
	for dc in get_tree().get_nodes_in_group("day_cycle"):
		dc.set("time_of_day", 330.0)
		if dc.has_method("apply_lighting"):
			dc.apply_lighting()
	if GameState.has_method("notify_night_from_time"):
		GameState.notify_night_from_time()
	var torch_cell := Vector3i(int(look.x), 0, int(look.z))
	if GameState.place_wake_block(torch_cell, "torch"):
		wake_voxels.add_block(torch_cell, GameState.wake_blocks[torch_cell])
	player.global_position = Vector3(float(torch_cell.x) - 3.2, 2.4, float(torch_cell.z) - 3.2)
	player.rotation_degrees = Vector3(0, 225, 0)
	if player.has_node("CameraPivot"):
		player.get_node("CameraPivot").rotation_degrees = Vector3(-10, 0, 0)
	await get_tree().create_timer(0.35).timeout
	await _save_shot("night_torch.png")
	player.rotation_degrees = Vector3(0, 300, 0)
	await _save_shot("night_angle.png")
	var report := []
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("collect_collision_issues"):
			var issues: Array = cm.collect_collision_issues()
			report.append("%s issues=%d active=%s" % [cm.name, issues.size(), cm._physics_active() if cm.has_method("_physics_active") else "?"])
			for it in issues:
				report.append("  %s" % str(it))
	var rf := FileAccess.open("/workspace/shots/collision_report.txt", FileAccess.WRITE)
	if rf:
		rf.store_string("\n".join(report))
	print("SHOT report:\n", "\n".join(report))
	get_tree().quit(0)
