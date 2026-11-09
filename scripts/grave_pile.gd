extends Node3D
## v0.7: кучка вещей после смерти (всё, кроме гвоздей/якорей/маяков). Подбирается подходом (автоподбор).

const BlockTex := preload("res://scripts/block_tex.gd")

var grave_id: int = -1
var collected: bool = false


func configure(gid: int) -> void:
	grave_id = gid


func _ready() -> void:
	add_to_group("grave_pile")
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BlockTex.cube_mesh("grave", Vector3(0.6, 0.3, 0.6))
	mi.position = Vector3(0, 0.15, 0)
	add_child(mi)
	var n := 0
	var idx := GameState.grave_index(grave_id)
	if idx >= 0:
		for it in GameState.graves[idx]["items"]:
			n += int(it["count"])
	for i in range(mini(5, maxi(1, n / 20))):
		var b := MeshInstance3D.new()
		b.mesh = BlockTex.cube_mesh("planks" if i % 2 == 0 else "stone", Vector3(0.22, 0.22, 0.22))
		b.position = Vector3(randf_range(-0.25, 0.25), 0.4 + 0.12 * i, randf_range(-0.25, 0.25))
		b.rotation_degrees = Vector3(0, randf() * 90.0, 0)
		add_child(b)
	var tag := Label3D.new()
	tag.text = "Твои вещи (%d)" % n
	tag.position = Vector3(0, 1.0, 0)
	tag.font_size = 26
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1.0, 0.85, 0.7)
	add_child(tag)


func collect() -> void:
	if collected:
		return
	GameState.pickup_grave(grave_id)
	if GameState.grave_index(grave_id) < 0:
		collected = true
		queue_free()
