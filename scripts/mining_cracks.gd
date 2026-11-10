extends MeshInstance3D
var stage := -1
var progress := 0.0
var _mat := StandardMaterial3D.new()
var _textures: Array[Texture2D] = []
func _ready() -> void:
	var tex := preload("res://scripts/block_tex.gd")
	var stream := tex.new_stream()
	tex.emit_box(stream,-Vector3.ONE*0.504,Vector3.ONE*1.008,Color.WHITE,0,[0,0,0,0,0,0],true)
	mesh = tex.stream_to_mesh(stream,_mat)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.28,0.22,0.17,0.94)
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = 1
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in range(10): _textures.append(load("res://assets/textures/crack_%d.png" % i))
	visible = false
func show_progress(cell: Vector3i,fraction: float) -> void:
	progress = clampf(fraction,0.0,1.0)
	stage = clampi(floori(progress*10.0),0,9)
	_mat.albedo_texture = _textures[stage]
	global_position = Vector3(cell)+Vector3.ONE*0.5
	visible = true
