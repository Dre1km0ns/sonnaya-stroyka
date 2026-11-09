extends StaticBody3D
## Выпавший блок после кирки: подбирается как реагент (E).

var kind: String = "drift"
var collected: bool = false


func configure(block_kind: String) -> void:
	kind = block_kind


func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 8
	collision_mask = 0
	if kind == "":
		kind = "drift"
	_apply_visual()


func _apply_visual() -> void:
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "Mesh"
	var bt: GDScript = load("res://scripts/block_tex.gd")
	mesh_i.mesh = bt.cube_mesh(kind, Vector3(0.42, 0.42, 0.42))
	mesh_i.rotation_degrees = Vector3(0, randf() * 360.0, 0)
	add_child(mesh_i)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	col.shape = shape
	add_child(col)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.position = Vector3(0, 0.55, 0)
	tag.font_size = 22
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.text = GameState.block_display_name(kind) if GameState.has_method("block_display_name") else kind
	add_child(tag)


func collect() -> void:
	if collected:
		return
	if GameState.has_method("add_mined_block"):
		GameState.add_mined_block(kind, 1)
	elif GameState.has_method("add_item"):
		if GameState.add_item(kind, kind, 1) < 0:
			return
	collected = true
	visible = false
	collision_layer = 0
	queue_free()
