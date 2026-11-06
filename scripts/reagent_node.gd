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


func _apply_visual() -> void:
	var colr: Color = TYPE_COLORS[reagent_type - 1]
	var mesh_i := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_i == null:
		mesh_i = MeshInstance3D.new()
		mesh_i.name = "Mesh"
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh_i.mesh = sphere
		add_child(mesh_i)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colr
	mat.emission_enabled = true
	mat.emission = colr
	mat.emission_energy_multiplier = 0.65
	mesh_i.material_override = mat
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
		tag.position = Vector3(0, 0.55, 0)
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
		GameState.set_hint("%s: счётчик полный (%d)." % [GameState.reagent_type_name(reagent_type), cap])
		return
	collected = true
	if GameState.has_method("mark_reagent_collected"):
		GameState.mark_reagent_collected(world_id)
	GameState.set_hint("Собран %s (+%d). Всего: %d" % [
		GameState.reagent_type_name(reagent_type), added, GameState.get_reagent_count(reagent_type)
	])
	visible = false
	collision_layer = 0
	queue_free()


func _on_night(night: bool) -> void:
	var mesh_i := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_i == null or mesh_i.material_override == null:
		return
	var mat := mesh_i.material_override as StandardMaterial3D
	if mat == null:
		return
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
