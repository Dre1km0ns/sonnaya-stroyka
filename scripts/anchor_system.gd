extends Node
## Инструмент якоря: Гвоздь / Клин, затраты, превью зоны.

var player: CharacterBody3D
var dream_voxels: Node3D
var preview: MeshInstance3D


func setup(p: CharacterBody3D, dream_layer: Node3D) -> void:
	player = p
	dream_voxels = dream_layer
	_make_preview()


func _make_preview() -> void:
	preview = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	preview.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.material_override = mat
	preview.visible = false
	add_child(preview)


func _process(_delta: float) -> void:
	if player == null or dream_voxels == null:
		return
	if not GameState.is_dream():
		preview.visible = false
		return

	if GameState.craft_menu_open:
		preview.visible = false
		return
	if Input.is_action_just_pressed("select_nail"):
		GameState.select_anchor(GameState.AnchorType.NAIL)
	if Input.is_action_just_pressed("select_wedge"):
		GameState.select_anchor(GameState.AnchorType.WEDGE)

	_update_preview()

	if Input.is_action_just_pressed("anchor_place"):
		_try_anchor()


func _target_cell() -> Vector3i:
	var aim: Dictionary = player.get_look_ray() if player.has_method("get_look_ray") else {"hit": false}
	if aim.get("hit", false):
		var collider = aim["collider"]
		if collider != null and collider.has_meta("voxel_cell") and bool(collider.get_meta("is_dream")):
			return collider.get_meta("voxel_cell")
		var hit_pos: Vector3 = aim["position"]
		var normal: Vector3 = aim["normal"]
		return dream_voxels.world_to_cell(hit_pos - normal * 0.1)
	var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
	var forward := -cam.global_transform.basis.z
	return dream_voxels.world_to_cell(cam.global_position + forward * 4.0)


func _update_preview() -> void:
	var cell := _target_cell()
	var size := 1.0
	if GameState.selected_anchor == GameState.AnchorType.WEDGE:
		size = float(GameState.WEDGE_SIZE)
	elif GameState.selected_anchor == GameState.AnchorType.ANCHOR3:
		size = float(GameState.ANCHOR3_SIZE)
	preview.scale = Vector3.ONE * size
	preview.global_position = dream_voxels.cell_to_world(cell)
	preview.visible = true


func _try_anchor() -> void:
	var cell := _target_cell()
	if GameState.try_place_anchor(cell):
		# Обновить визуал заякоренных
		for a in GameState.pending_anchors:
			for c in a["cells"]:
				if GameState.dream_blocks.has(c):
					dream_voxels.refresh_block(c, GameState.dream_blocks[c])
