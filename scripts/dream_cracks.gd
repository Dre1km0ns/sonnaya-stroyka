extends MultiMeshInstance3D
## v0.18 «Живой Сон»: трещины во Сне — там, где чудовища Яви сломали материализованную копию.
## Тёмно-красная пульсирующая оболочка вокруг клетки. Только показ; логика — в GameState.

var shown := 0
var _t := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	name = "DreamCracks"
	add_to_group("dream_cracks")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.08
	mm.mesh = box
	multimesh = mm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.04, 0.08, 0.5)
	_mat.emission_enabled = true
	_mat.emission = Color(0.9, 0.1, 0.15)
	_mat.emission_energy_multiplier = 1.2
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameState.cracks_changed.connect(rebuild)
	GameState.world_changed.connect(func(_d: bool) -> void: rebuild())
	rebuild()


func rebuild() -> void:
	var cells: Array = GameState.crack_cells()
	visible = not cells.is_empty()
	multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		var c: Vector3i = cells[i]
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(c) + Vector3(0.5, 0.5, 0.5)))
	shown = cells.size()


func _process(delta: float) -> void:
	if not visible: return
	_t += delta
	_mat.emission_energy_multiplier = 0.8 + 0.6 * absf(sin(_t * 2.2))
