extends Node3D
## v0.24: другой игрок в сетевой игре — модель Kenney, табличка с именем и полоска здоровья. Группа remote_player:
## мобы и боссы хоста видят его как цель (combat_util.players), урон уходит ему по сети (hurt_remote).
var peer_id := 0
var display_name := "Игрок"
var model_name := "character-b"
var dead := false
var _model: Node3D
var _ap: AnimationPlayer
var _label: Label3D
var _last := Vector3.ZERO


func _ready() -> void:
	add_to_group("remote_player")
	var path := "res://assets/models/kenney_blocky/%s.glb" % model_name
	if not ResourceLoader.exists(path):
		path = "res://assets/models/kenney_blocky/character-a.glb"
	var ps: PackedScene = load(path)
	if ps:
		_model = ps.instantiate()
		_model.rotation.y = PI
		add_child(_model)
		_ap = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.15, 0)
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.outline_size = 10
	_label.modulate = Color(0.85, 0.95, 1.0)
	_label.no_depth_test = true
	add_child(_label)


func _process(delta: float) -> void:
	if has_meta("target"):
		var t: Vector3 = get_meta("target")
		if global_position.distance_to(t) > 8.0:
			global_position = t
		else:
			global_position = global_position.lerp(t, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, float(get_meta("yaw", 0.0)), clampf(delta * 12.0, 0.0, 1.0))
	var sp := (global_position - _last).length() / maxf(delta, 0.001)
	_last = global_position
	_label.text = "%s · %d HP" % [display_name, int(get_meta("hp", 100))] if not dead else "%s · без сознания" % display_name
	if _ap:
		var want := "walk" if sp > 0.6 else "idle"
		if dead and _ap.has_animation("die"): want = "die"
		if _ap.has_animation(want) and _ap.current_animation != want:
			_ap.play(want)
