extends Node3D
## Быстрый разрыв-шов: вспышка, разлетающиеся фрагменты, исчезновение за 0.8 с.
const Sfx := preload("res://scripts/sfx.gd")
static func spawn(host: Node3D, at: Vector3) -> Node3D:
	if not host:
		return null
	var effect := Node3D.new()
	effect.position = at
	host.add_child(effect)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6,0.25,1)
	light.light_energy = 2.0
	light.omni_range = 5.0
	effect.add_child(light)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65,0.3,1)
	mat.emission_enabled = true
	mat.emission = Color(0.5,0.2,1)
	for i in range(12):
		var m := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.6 if i % 2 == 0 else 0.12, 0.08)
		m.mesh = mesh
		m.material_override = mat
		m.position.y = 0.3 + float(i % 4) * 0.25
		effect.add_child(m)
		var t := effect.create_tween()
		t.tween_property(m,"position",Vector3(randf_range(-1.5,1.5),randf_range(0.2,2),randf_range(-1.5,1.5)),0.7)
		t.parallel().tween_property(m,"scale",Vector3.ZERO,0.7)
	Sfx.play("seam", effect)
	var tw := effect.create_tween()
	tw.tween_property(light,"light_energy",0.0,0.7)
	tw.tween_callback(effect.queue_free)
	return effect
