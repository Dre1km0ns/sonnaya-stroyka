extends StaticBody3D
## Собираемый реагент в яви. Типы: реагент1 / реагент2 / реагент3.

const TYPE_COLORS: Array[Color] = [
	Color(0.90, 0.75, 0.28),
	Color(0.22, 0.76, 0.68),
	Color(0.68, 0.32, 0.88),
]

@export var amount: int = 1
@export var reagent_type: int = 1
var collected: bool = false
var world_id: String = ""


func configure(type_id: int, id: String, amt: int = 1) -> void:
	reagent_type = clampi(type_id, 1, 3)
	world_id = id
	amount = amt


func _ready() -> void:
	add_to_group("reagent")
	collision_layer = 8
	collision_mask = 0
	reagent_type = clampi(reagent_type, 1, 3)
	if world_id == "":
		world_id = "%d,%d,%d" % [
			int(round(global_position.x)),
			int(round(global_position.y)),
			int(round(global_position.z)),
		]
	if GameState.has_method("is_reagent_collected") and GameState.is_reagent_collected(world_id):
		queue_free()
		return
	_apply_visual()
	if GameState.has_signal("night_changed") and not GameState.night_changed.is_connected(_on_night):
		GameState.night_changed.connect(_on_night)
	_on_night(GameState.is_night() if GameState.has_method("is_night") else false)


const MODEL_PATHS := [
	"res://assets/models/reagent_crystal.glb",
	"res://assets/models/reagent_herb.glb",
	"res://assets/models/reagent_ore.glb",
]


func _model_path() -> String:
	return MODEL_PATHS[clampi(reagent_type, 1, 3) - 1]


func _fit_model(inst: Node3D, target_h: float) -> void:
	var acc := AABB()
	var first := true
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var local: AABB = mi.mesh.get_aabb()
			var xf: Transform3D = inst.global_transform.affine_inverse() * mi.global_transform
			var world_a: AABB = xf * local
			if first:
				acc = world_a
				first = false
			else:
				acc = acc.merge(world_a)
		for ch in n.get_children():
			stack.append(ch)
	if acc.size.y < 0.01:
		return
	inst.scale = Vector3.ONE * (target_h / acc.size.y)
	# повторный сдвиг после масштаба
	acc = AABB(acc.position * inst.scale, acc.size * inst.scale)
	inst.position.y -= acc.position.y


func _apply_visual() -> void:
	var colr: Color = TYPE_COLORS[reagent_type - 1]
	if get_node_or_null("Model") == null:
		var packed: Resource = load(_model_path())
		if packed is PackedScene:
			var inst: Node3D = (packed as PackedScene).instantiate()
			inst.name = "Model"
			add_child(inst)
			_fit_model(inst, 0.55)
		else:
			var mesh_i := MeshInstance3D.new()
			mesh_i.name = "Mesh"
			var sphere := SphereMesh.new()
			sphere.radius = 0.25
			sphere.height = 0.5
			mesh_i.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = colr
			mat.emission_enabled = true
			mat.emission = colr
			mat.emission_energy_multiplier = 0.65
			mesh_i.material_override = mat
			add_child(mesh_i)
	var old_mesh := get_node_or_null("Mesh") as Node3D
	if old_mesh and get_node_or_null("Model") != null:
		old_mesh.visible = false   # v0.6: жёлтая сфера из сцены под моделью больше не торчит
	if get_node_or_null("Collision") == null:
		var col := CollisionShape3D.new()
		col.name = "Collision"
		var shape := SphereShape3D.new()
		shape.radius = 0.35
		col.shape = shape
		add_child(col)
	var tag := get_node_or_null("Tag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "Tag"
		tag.position = Vector3(0, 0.7, 0)
		tag.font_size = 28
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(tag)
	tag.text = GameState.reagent_type_name(reagent_type)
	tag.modulate = colr.lightened(0.25)


func collect() -> void:
	if collected:
		return
	var added := 0
	if GameState.has_method("add_typed_reagent"):
		added = int(GameState.add_typed_reagent(reagent_type, amount))
	else:
		GameState.add_reagents(amount)
		added = amount
	if added <= 0:
		var cap := 100
		if "REAGENT_CAP" in GameState:
			cap = int(GameState.REAGENT_CAP)
		GameState.set_hint("%s: счётчик полный (%d)." % [GameState.reagent_type_name(reagent_type), cap], false)
		return
	collected = true
	if GameState.has_method("mark_reagent_collected"):
		GameState.mark_reagent_collected(world_id)
	GameState.set_hint("Собран %s (+%d). Всего: %d" % [
		GameState.reagent_type_name(reagent_type), added, GameState.get_reagent_count(reagent_type)
	], false)
	visible = false
	collision_layer = 0
	queue_free()


func _on_night(night: bool) -> void:
	var mesh_i := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_i and mesh_i.material_override:
		var mat := mesh_i.material_override as StandardMaterial3D
		if mat:
			if night:
				mat.emission_enabled = false
				mat.emission_energy_multiplier = 0.0
			else:
				mat.emission_enabled = true
				mat.emission = TYPE_COLORS[clampi(reagent_type, 1, 3) - 1]
				mat.emission_energy_multiplier = 0.65
	var tag := get_node_or_null("Tag") as Label3D
	if tag:
		tag.modulate.a = 0.25 if night else 1.0


func _process(_delta: float) -> void:
	for child in get_children():
		if child is Label3D:
			child.visible = false
