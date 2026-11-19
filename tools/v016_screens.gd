extends SceneTree
## Кадры для отчёта v0.16 «Сон помнит». Пишет в /tmp/v016shots/.
## xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v016_screens.gd
const OUT := "/tmp/v016shots/"
var gs; var main; var player

func _init() -> void: call_deferred("_go")
func _wait(n: int) -> void:
	for i in range(n): await process_frame
func _shot(name: String) -> void:
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
	print("SHOT ", name)
func _look(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos; player.rotation.y = yaw
	player.get_node("CameraPivot").rotation.x = pitch

var B: Vector3i
func _house_cells() -> Dictionary:
	## Домик 7×5: пол и крыша — доски, стены — камень, углы — брёвна, дверной проём спереди, окна.
	var out := {}
	for x in range(7):
		for z in range(5):
			out[B + Vector3i(x, 0, z)] = "planks"
			out[B + Vector3i(x, 4, z)] = "planks"
			for y in range(1, 4):
				var edge := x == 0 or x == 6 or z == 0 or z == 4
				if not edge: continue
				var corner := (x == 0 or x == 6) and (z == 0 or z == 4)
				if z == 4 and x == 3 and y <= 2: continue
				if z == 4 and (x == 1 or x == 5) and y == 2: continue
				out[B + Vector3i(x, y, z)] = "log" if corner else "stone"
	return out

func _ready_preview(c: Vector3i) -> Dictionary:
	var p: Dictionary = gs.anchor_preview(c)
	for i in range(200):
		if p.ready: break
		await process_frame; p = gs.anchor_preview(c)
	return p

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	gs = root.get_node("GameState")
	gs.begin_world("shots016", "", "1606", 1606, true)
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(90)
	main = current_scene; player = main.get_node("Player")
	player.set_physics_process(false)
	for dc in get_nodes_in_group("day_cycle"): dc.set_time(9.0 * 60.0)
	gs.tutorial_enabled = false
	gs.add_item_count("planks", 120); gs.add_item_count("stone", 90); gs.add_item_count("log", 30)
	gs.pouch.reagent1 = 20; gs.anchors3 = 1; gs.clarity = gs.dream_clarity_max()
	var sp: Vector3 = gs.spawn_point
	var sx := int(floor(sp.x)) - 3; var sz := int(floor(sp.z)) - 14
	var top := -999
	for x in range(-1, 12):
		for z in range(-1, 6):
			top = maxi(top, int(main.wake_chunks.height_at(sx + x, sz + z)))
			top = maxi(top, int(main.dream_chunks.height_at(sx + x, sz + z)))
	B = Vector3i(sx, top + 2, sz)
	print("BASE ", B)
	main.switcher.enter_dream()
	await _wait(30)
	var cells := _house_cells()
	for c in cells: gs.place_dream_block(c, cells[c])
	gs.dream_material = "stone"
	gs.placed_cells_changed.emit(true, cells.keys())
	gs.clarity_changed.emit(gs.clarity, gs.dream_clarity_max())
	var eye := Vector3(B.x + 3.5, B.y + 3.2, B.z + 12.5)
	_look(eye, 0.0, -0.2)
	await _wait(60)
	await _shot("01_dream_house_palette.png")
	gs.select_anchor(gs.AnchorType.ANCHOR3)
	_look(Vector3(B.x + 3.5, B.y + 2.6, B.z + 9.0), 0.0, -0.12)
	await _wait(40)
	print("PREVIEW ", main.anchors.last_preview.get("materials", {}), " ok=", main.anchors.last_preview.get("ok"))
	await _shot("02_anchor_preview_cost.png")
	var ac: Vector3i = B + Vector3i(3, 2, 2)
	var pv: Dictionary = await _ready_preview(ac)
	print("ANCHOR ", gs.try_place_anchor(ac), " ", pv.materials)
	await _wait(20)
	_look(eye, 0.0, -0.2)
	await _wait(30)
	await _shot("03_anchored_dream.png")
	main.switcher.wake_up()
	await _wait(20)
	await _shot("04_wake_result_panel.png")
	for ui in get_nodes_in_group("transfer_result_ui"): ui.close()
	player.set_physics_process(false)
	_look(eye, 0.0, -0.2)
	await _wait(60)
	await _shot("05_wake_house_copy.png")
	main.switcher.enter_dream()
	await _wait(20)
	var ext: Array = []
	for x in range(7, 11):
		for z in range(0, 5):
			var c := B + Vector3i(x, 0, z); gs.place_dream_block(c, "planks"); ext.append(c)
		for y in range(1, 3):
			var c2 := B + Vector3i(x, y, 0); gs.place_dream_block(c2, "stone"); ext.append(c2)
	gs.placed_cells_changed.emit(true, ext)
	main.dream_voxels.sync_from_state()
	var from := Vector3(B.x + 9.0, B.y + 5.5, B.z + 13.0)
	var d: Vector3 = Vector3(ac) + Vector3(0.5, 0.5, 0.5) - from
	_look(from, atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await _wait(60)
	main.anchors.set_process(false); main.anchors.info.visible = false; main.anchors.preview.visible = false
	await _shot("06_dream_echo_gold.png")
	main.anchors.set_process(true)
	main.switcher.show_result_ui = false
	main.switcher.wake_up(); await _wait(10)
	player.set_physics_process(false)
	var broken := [B + Vector3i(2, 1, 4), B + Vector3i(2, 2, 4), B + Vector3i(4, 1, 4), B + Vector3i(4, 2, 4), B + Vector3i(4, 3, 4), B + Vector3i(2, 3, 4)]
	for c in broken: gs.remove_shape(gs.wake_blocks, c)
	gs.placed_cells_changed.emit(false, broken)
	_look(eye, 0.0, -0.2)
	await _wait(50)
	await _shot("07_repair_before.png")
	gs.add_item_count("stone", 10)
	main.switcher.enter_dream(); await _wait(20)
	gs.select_anchor(gs.AnchorType.ANCHOR3)
	var hole := Vector3(B.x + 2.5, B.y + 2.5, B.z + 4.5)
	var from2 := hole + Vector3(0.6, 0.3, 3.6)
	var d2: Vector3 = Vector3(B.x + 3.0, B.y + 2.0, B.z + 0.5) - from2
	_look(from2, atan2(-d2.x, -d2.z), atan2(d2.y, Vector2(d2.x, d2.z).length()))
	await _wait(50)
	print("OVERLAY new=", main.anchors.last_preview.get("new_roots", []).size(), " same=", main.anchors.last_preview.get("same"), " mats=", main.anchors.last_preview.get("materials"))
	await _shot("07b_repair_overlay.png")
	var pr: Dictionary = await _ready_preview(ac)
	print("REPAIR new=", pr.new_roots.size(), " same=", pr.same, " mats=", pr.materials, " ok=", gs.try_place_anchor(ac))
	main.switcher.wake_up(); await _wait(10)
	player.set_physics_process(false)
	_look(eye, 0.0, -0.2)
	await _wait(50)
	await _shot("08_repair_after.png")
	print("SHOTS DONE")
	quit(0)
