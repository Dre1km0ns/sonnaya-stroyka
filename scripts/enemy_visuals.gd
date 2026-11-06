extends Object
## Реальные CC0-модели Quaternius (см. assets/LICENSE.txt).

const PATH_SEAM := "res://assets/models/demon.glb"
const PATH_GHOST := [
	"res://assets/models/ghost.glb",
	"res://assets/models/pinkblob.glb",
	"res://assets/models/bluedemon.glb",
	"res://assets/models/ghost_skull.glb",
]


static func build_seam(parent: Node3D, elite: bool) -> void:
	var h := 2.0 if elite else 1.7
	attach_model(parent, PATH_SEAM, h)


static func build_ghost(parent: Node3D, kind: int, _color: Color) -> void:
	var path: String = PATH_GHOST[clampi(kind, 0, 3)]
	attach_model(parent, path, 1.65)


static func attach_model(parent: Node3D, path: String, target_h: float) -> Node3D:
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("Missing enemy model: %s" % path)
		return null
	var inst: Node3D = (packed as PackedScene).instantiate()
	inst.name = "Model"
	parent.add_child(inst)
	_fit_to_height(inst, target_h)
	parent.set_meta("has_real_model", true)
	apply_night(inst, _is_night())
	return inst


static func _fit_to_height(inst: Node3D, target_h: float) -> void:
	var aabb := _combined_aabb(inst)
	if aabb.size.y < 0.05:
		return
	inst.scale = Vector3.ONE * (target_h / aabb.size.y)
	aabb = _combined_aabb(inst)
	inst.position.y -= aabb.position.y


static func _combined_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for mi in _meshes_under(root):
		if mi.mesh == null:
			continue
		var local: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var world_a := xf * local
		if first:
			acc = world_a
			first = false
		else:
			acc = acc.merge(world_a)
	return acc


static func _meshes_under(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_meshes_under(ch))
	return out


static func apply_night(root: Node, night: bool) -> void:
	for mi in _meshes_under(root):
		if mi.mesh == null:
			continue
		var sc: int = mi.mesh.get_surface_count()
		for i in range(sc):
			var src: Material = mi.get_active_material(i)
			if src == null:
				continue
			var mat: Material = src.duplicate()
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if night:
					bm.emission_enabled = false
					bm.emission_energy_multiplier = 0.0
					if bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
						bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mi.set_surface_override_material(i, mat)


static func _is_night() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs != null and gs.has_method("is_night"):
		return bool(gs.call("is_night"))
	return false
