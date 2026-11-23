extends Node3D
## v0.24: моб или босс хоста у клиента. Видимость, позиция и здоровье приходят от хоста;
## удары меча и стрелы клиента по нему уходят хосту (NetSession.send_hit). Сам ничего не решает.
var remote_id := 0
var kind := "mob"
var is_boss := false
var hp := 1
var max_hp := 1
var hit_radius := 0.5
var title := ""
var _target := Vector3.ZERO
var _hc_off := Vector3(0, 0.8, 0)
var _body: MeshInstance3D
var _label: Label3D
const COLORS := {"seam_creature": Color(0.4, 0.3, 0.55), "enemy_ghost": Color(0.8, 0.85, 1.0), "wake_mob": Color(0.55, 0.6, 0.4),
	"lizard_minion": Color(0.4, 0.6, 0.35), "blockling": Color(0.55, 0.45, 0.35), "block_mother": Color(0.6, 0.5, 0.45),
	"boss_anaconda": Color(0.3, 0.5, 0.3), "boss_burger": Color(0.85, 0.55, 0.25), "clown_bomb": Color(1.0, 0.4, 0.4)}


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("net_proxy")
	if is_boss:
		add_to_group("boss")
	_body = MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sz := 2.6 if is_boss else 0.8
	bm.size = Vector3(sz, sz * 1.1, sz)
	_body.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = COLORS.get(kind, Color(0.6, 0.5, 0.6))
	_body.material_override = m
	_body.position = Vector3(0, sz * 0.55, 0)
	add_child(_body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, sz * 1.25 + 0.3, 0)
	_label.pixel_size = 0.005; _label.font_size = 40; _label.outline_size = 8
	add_child(_label)


func update_from(m: Array) -> void:
	_target = m[2]
	rotation.y = float(m[3])
	hp = int(m[4]); max_hp = maxi(1, int(m[5]))
	title = str(m[7])
	_hc_off = (m[8] as Vector3) - (m[2] as Vector3)
	hit_radius = float(m[9])
	if _label:
		_label.text = "%s %d/%d" % [title, hp, max_hp] if title != "" else "%d/%d" % [hp, max_hp]
		_label.visible = not is_boss


func _process(delta: float) -> void:
	visible = not GameState.is_dream()
	if global_position.distance_to(_target) > 10.0:
		global_position = _target
	else:
		global_position = global_position.lerp(_target, clampf(delta * 10.0, 0.0, 1.0))


func hit_center() -> Vector3:
	return global_position + _hc_off


func boss_title() -> String:
	return title


func is_vulnerable() -> bool:
	return false


func is_dead_v024() -> bool:
	return hp <= 0


func take_damage(amount: int) -> void:
	NetSession.send_hit(remote_id, amount, str(GameState.get_selected_item().get("id", "")))


func take_arrow(amount: int, _a: Node) -> void:
	NetSession.send_hit(remote_id, amount, "arrow")


func die_out() -> void:
	load("res://scripts/mob_fx.gd").death(self, (_body.material_override as StandardMaterial3D).albedo_color if _body else Color.WHITE, 0.8)
	get_tree().create_timer(0.9).timeout.connect(queue_free)
