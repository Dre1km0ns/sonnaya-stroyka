extends Object
## Реальные CC0-модели Quaternius + клипы AnimationPlayer + полоска HP.

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
	attach_hp_bar(parent, 2.2)


static func build_ghost(parent: Node3D, kind: int, _color: Color) -> void:
	var path: String = PATH_GHOST[clampi(kind, 0, 3)]
	attach_model(parent, path, 1.65)
	attach_hp_bar(parent, 2.25)


static func attach_model(parent: Node3D, path: String, target_h: float) -> Node3D:
	var packed: Resource = load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("Missing enemy model: %s" % path)
		return null
	var inst: Node3D = (packed as PackedScene).instantiate()
	inst.name = "Model"
	parent.add_child(inst)
	_fit_to_height(inst, target_h)
	parent.set_meta("has_real_model", true)
	parent.set_meta("model_path", path)
	apply_night(inst, _is_night())
	play_state(parent, "idle", true)
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
		var world_a: AABB = xf * local
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
				var bm: BaseMaterial3D = mat as BaseMaterial3D
				if night:
					bm.emission_enabled = false
					bm.emission_energy_multiplier = 0.0
					if bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
						bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mi.set_surface_override_material(i, mat)


static func find_anim_player(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for ch in n.get_children():
		var found: AnimationPlayer = find_anim_player(ch)
		if found:
			return found
	return null


static func clips_for(path: String) -> Dictionary:
	var p: String = path.get_file().to_lower()
	if "ghost" in p:
		return {"walk": "Fast_Flying", "idle": "Flying_Idle", "attack": "Punch", "death": "Death", "jump": "Fast_Flying"}
	if "blob" in p:
		return {"walk": "Walk", "idle": "Idle", "attack": "Bite_Front", "death": "Death", "jump": "Jump"}
	return {"walk": "Walk", "idle": "Idle", "attack": "Weapon", "death": "Death", "jump": "Jump"}


static func resolve_clip(ap: AnimationPlayer, state: String, path: String) -> String:
	if ap == null:
		return ""
	var wanted: String = str(clips_for(path).get(state, ""))
	if wanted != "" and ap.has_animation(wanted):
		return wanted
	var fallbacks: Array[String] = []
	if state == "attack":
		fallbacks = ["Weapon", "Punch", "Bite_Front", "Headbutt", "Jump"]
	elif state == "walk":
		fallbacks = ["Walk", "Run", "Fast_Flying", "Flying_Idle"]
	elif state == "idle":
		fallbacks = ["Idle", "Flying_Idle", "Walk"]
	elif state == "death":
		fallbacks = ["Death"]
	elif state == "jump":
		fallbacks = ["Jump", "Walk"]
	for name in fallbacks:
		if ap.has_animation(name):
			return name
	var list: PackedStringArray = ap.get_animation_list()
	if list.size() > 0:
		return list[0]
	return ""


static func play_state(parent: Node, state: String, restart: bool = false) -> String:
	var model: Node = parent.get_node_or_null("Model") if parent else null
	var ap: AnimationPlayer = find_anim_player(model if model else parent)
	if ap == null:
		return ""
	var path: String = str(parent.get_meta("model_path", "")) if parent else ""
	var clip: String = resolve_clip(ap, state, path)
	if clip == "":
		return ""
	if not restart and ap.current_animation == clip and ap.is_playing():
		return clip
	ap.play(clip)
	return clip


static func has_clip(parent: Node, state: String) -> bool:
	var model: Node = parent.get_node_or_null("Model") if parent else null
	var ap: AnimationPlayer = find_anim_player(model if model else parent)
	if ap == null:
		return false
	var path: String = str(parent.get_meta("model_path", "")) if parent else ""
	return resolve_clip(ap, state, path) != ""


static func attach_hp_bar(parent: Node3D, height: float) -> void:
	if parent.has_node("HPBar"):
		return
	var root := Node3D.new()
	root.name = "HPBar"
	root.position = Vector3(0, height, 0)
	var bg := MeshInstance3D.new()
	bg.name = "BG"
	var q := QuadMesh.new()
	q.size = Vector2(1.05, 0.12)
	bg.mesh = q
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.08, 0.08, 0.09, 0.82)
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = bmat
	root.add_child(bg)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.0, 0.09)
	fill.mesh = q2
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(0.86, 0.18, 0.16)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill.material_override = fmat
	fill.position = Vector3(0, 0, 0.012)
	root.add_child(fill)
	parent.add_child(root)
	update_hp_bar(parent, 50, 50)


static func update_hp_bar(parent: Node3D, hp: int, max_hp: int) -> void:
	var fill: MeshInstance3D = parent.get_node_or_null("HPBar/Fill") as MeshInstance3D
	if fill == null:
		return
	var r: float = clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	fill.scale = Vector3(maxi(r, 0.001), 1.0, 1.0)
	fill.position.x = (r - 1.0) * 0.5
	var root: Node3D = parent.get_node_or_null("HPBar") as Node3D
	if root:
		root.visible = hp > 0


static func _is_night() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs != null and gs.has_method("is_night"):
		return bool(gs.call("is_night"))
	return false
