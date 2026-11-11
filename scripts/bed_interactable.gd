extends StaticBody3D
## Кровать у спавна / ритуальная точка входа в сон. v0.7: процедурная модель (как крафтовая, длина 2).

const BlockTex := preload("res://scripts/block_tex.gd")


func _ready() -> void:
	add_to_group("bed")
	collision_layer = 8 # interactable
	collision_mask = 0
	var col := get_node_or_null("Collision") as CollisionShape3D
	if col and col.shape is BoxShape3D:
		col.shape = col.shape.duplicate()
		col.shape.size = Vector3(2, 0.56, 1)
	var old := get_node_or_null("Mesh") as MeshInstance3D
	if old:
		old.visible = false
	if get_node_or_null("BedModel") == null:
		var mi := MeshInstance3D.new()
		mi.name = "BedModel"
		mi.mesh = BlockTex.bed_mesh(2.0)
		mi.rotation_degrees = Vector3(0, 90, 0)
		mi.scale = Vector3.ONE
		mi.position = Vector3(0, 0.2, 0)
		add_child(mi)
	var lbl := get_node_or_null("Label3D") as Label3D
	if lbl:
		lbl.visible = false
