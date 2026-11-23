extends Node3D
## v0.24/v0.25: другой игрок в сетевой игре. v0.25 (t143u): стройный человечек v0.25.1 (chunky_body,
## пресет player) ростом 1,75 м — глаза на уровне камеры игрока; видно предмет в руке, удар, установку блока,
## выстрел из лука и надетую броню. Табличка с именем и HP. Группа remote_player: мобы хоста видят его как цель.
const Chunky := preload("res://scripts/chunky_body.gd")
const BlockTex := preload("res://scripts/block_tex.gd")
const SUITS := [Color(0.3, 0.4, 0.55), Color(0.55, 0.28, 0.24), Color(0.3, 0.45, 0.3), Color(0.55, 0.47, 0.25)]   # v0.25.1: приглушённые рубашки
const HEIGHT := 1.75
var peer_id := 0
var display_name := "Игрок"
var model_name := "character-b"
var idx := 1
var dead := false
var actions_seen := 0
var _model: Node3D
var _label: Label3D
var _item := "-"
var _act := -1


func _ready() -> void:
	add_to_group("remote_player")
	_model = Chunky.make("player", {"h": HEIGHT, "suit": SUITS[idx % SUITS.size()]})
	add_child(_model)
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, HEIGHT + 0.35, 0)
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.outline_size = 10
	_label.modulate = Color(0.85, 0.95, 1.0)
	_label.no_depth_test = true
	add_child(_label)


static func held_mesh(id: String) -> Node3D:
	if id == "":
		return null
	var mi := MeshInstance3D.new()
	mi.material_override = BlockTex.material()
	if "sword" in id or id.begins_with("pickaxe") or id in ["bow", "bow2"]:
		mi.mesh = BlockTex.tool_mesh(id)
		mi.scale = Vector3.ONE * 2.2
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	elif id == "torch":
		mi.mesh = BlockTex.torch_mesh()
		mi.scale = Vector3.ONE * 2.0
	elif BlockTex.tile(id) >= 0:
		mi.mesh = BlockTex.cube_mesh(id, Vector3.ONE * 0.75)
		mi.position = Vector3(0, 0, 0.25)
	else:
		mi.free()
		return null
	return mi


func _process(delta: float) -> void:
	if has_meta("target"):
		var t: Vector3 = get_meta("target")
		if global_position.distance_to(t) > 8.0:
			global_position = t
		else:
			global_position = global_position.lerp(t, clampf(delta * 12.0, 0.0, 1.0))
		# модель смотрит по +Z, игрок — по −Z
		rotation.y = lerp_angle(rotation.y, float(get_meta("yaw", 0.0)) + PI, clampf(delta * 12.0, 0.0, 1.0))
	_label.text = "%s · %d HP" % [display_name, int(get_meta("hp", 100))] if not dead else "%s · без сознания" % display_name
	var item := str(get_meta("item", ""))
	if item != _item:
		_item = item
		_model.call("set_held", held_mesh(item))
	_model.call("set_armor", get_meta("armor", []))
	var act := int(get_meta("act_n", 0))
	if _act >= 0 and act != _act:
		actions_seen += 1
		var kind := str(get_meta("act", "attack"))
		_model.call("play_state", "place" if kind in ["place", "use"] else "attack", true)
	_act = act
	if dead:
		_model.call("play_state", "death")
