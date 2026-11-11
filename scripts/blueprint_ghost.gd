extends MultiMeshInstance3D
## v0.11 Архив Снов: полупрозрачный контур сохранённого чертежа во Сне.
## Только подсказка — блоков не создаёт и в Явь ничего не переносит.

var shown_cells := 0


func _ready() -> void:
	name = "BlueprintGhost"
	add_to_group("blueprint_ghost")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.9
	mm.mesh = box
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameState.objective_changed.connect(rebuild)
	GameState.world_changed.connect(func(_d: bool) -> void: rebuild())
	GameState.placed_cells_changed.connect(func(is_dream: bool, _c: Array) -> void:
		if is_dream and GameState.blueprint_shown >= 0: rebuild())
	rebuild()


func rebuild() -> void:
	var cells: Array = GameState.blueprint_ghost_cells()
	visible = not cells.is_empty()
	multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		var c: Vector3i = cells[i]
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(c) + Vector3(0.5, 0.5, 0.5)))
	shown_cells = cells.size()
