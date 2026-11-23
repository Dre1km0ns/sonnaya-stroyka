extends Node3D
## v0.24/v0.25: моб или босс хоста у клиента. Позиция, здоровье, поза и номер атаки приходят от хоста;
## удары меча и стрелы клиента по нему уходят хосту (NetSession.send_hit). Сам ничего не решает.
## v0.25: настоящие модели — мобы (у каждого своя модель v0.25.1) по пресету chunky_body, Мать — её модель, Анаконда — голова
## и сегменты по точкам хоста, Бургер — тарелка (фаза 1) или Антон (фазы 2–3).
const _Vis := preload("res://scripts/enemy_visuals.gd")
const Chunky := preload("res://scripts/chunky_body.gd")
var remote_id := 0
var kind := "mob"
var preset := ""
var is_boss := false
var hp := 1
var max_hp := 1
var hit_radius := 0.5
var title := ""
var phase := 1
var _target := Vector3.ZERO
var _hc_off := Vector3(0, 0.8, 0)
var _model: Node3D
var _atk := -1
var _segs: Array = []
var _saucer: Node3D
var _anton: Node3D
var _seg_t: Array = []
const DEFAULT_TITLES := {"block_mother": "Мать блоков", "boss_anaconda": "Анаконда", "boss_burger": "Бургер Смерти"}


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("net_proxy")
	if is_boss:
		add_to_group("boss")
	_build()


func _build() -> void:
	match kind:
		"block_mother":
			_model = _Vis.attach_model(self, "res://assets/models/greenblob.glb", 3.2)
		"boss_anaconda":
			var a: Node3D = load("res://scripts/boss_anaconda.gd").new()
			a.call("_build_body")
			for c in a.get_children():
				a.remove_child(c)
				var bar := c.get_node_or_null("HPBar")
				if bar: bar.queue_free()
				c.top_level = true
				add_child(c)
				_segs.append(c)
			a.free()
		"boss_burger":
			var b: Node3D = load("res://scripts/boss_burger.gd").new()
			b.call("_build_saucer")
			_saucer = b.get_node("Saucer")
			b.remove_child(_saucer)
			for wp in _saucer.get_children():
				if wp.get_script() and str(wp.get_script().resource_path).ends_with("weak_point.gd"):
					var glow := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
					glow.mesh = sm
					var m := StandardMaterial3D.new(); m.albedo_color = Color(1, 0.3, 0.2); m.emission_enabled = true; m.emission = Color(1, 0.3, 0.1); m.emission_energy_multiplier = 3.0
					glow.material_override = m; glow.position = wp.position
					_saucer.remove_child(wp); wp.free()
					_saucer.add_child(glow)
			_saucer.scale = Vector3.ONE * float(b.get("SAUCER_SCALE")) if "SAUCER_SCALE" in b else Vector3.ONE
			add_child(_saucer)
			b.free()
			_anton = Chunky.make("anton")
			_anton.name = "Anton"
			_anton.visible = false
			add_child(_anton)
		_:
			var pr := preset if preset != "" else "seam"
			_model = Chunky.make(pr)
			add_child(_model)


func update_from(m: Array) -> void:
	_target = m[2]
	rotation.y = float(m[3])
	hp = int(m[4]); max_hp = maxi(1, int(m[5]))
	title = str(m[7])
	_hc_off = (m[8] as Vector3) - (m[2] as Vector3)
	hit_radius = float(m[9])
	if m.size() > 12:
		var atk := int(m[11])
		var mdl: Node3D = _anton if (kind == "boss_burger" and _anton and _anton.visible) else _model
		if _atk >= 0 and atk != _atk and mdl and mdl.has_method("play_state"):
			mdl.call("play_state", "attack", true)
		elif _atk >= 0 and atk != _atk and kind == "block_mother":
			_Vis.play_state(self, "attack", true)
		_atk = atk
		var ex: Variant = m[12]
		match kind:
			"boss_anaconda":
				if ex is Array: _seg_t = ex
			"boss_burger":
				phase = int(ex)
				if _saucer: _saucer.visible = phase == 1
				if _anton: _anton.visible = phase >= 2
			"block_mother":
				if _model and ex is float and float(ex) > 0.0: _model.scale = Vector3.ONE * float(ex)


func _process(delta: float) -> void:
	visible = not GameState.is_dream()
	if global_position.distance_to(_target) > 10.0:
		global_position = _target
	else:
		global_position = global_position.lerp(_target, clampf(delta * 10.0, 0.0, 1.0))
	var k := clampf(delta * 10.0, 0.0, 1.0)
	for i in range(mini(_segs.size(), _seg_t.size())):
		var s: Node3D = _segs[i]
		var tp: Vector3 = _seg_t[i]
		s.global_position = tp if s.global_position.distance_to(tp) > 8.0 else s.global_position.lerp(tp, k)
		if i + 1 < _seg_t.size():
			var nx: Vector3 = _seg_t[i + 1]
			if nx.distance_to(tp) > 0.05:
				s.look_at(tp + (tp - nx), Vector3.UP)
	if kind == "block_mother":
		_Vis.play_state(self, "walk" if global_position.distance_to(_target) > 0.05 else "idle")


func hit_center() -> Vector3:
	return global_position + _hc_off


func boss_title() -> String:
	return title if title != "" else str(DEFAULT_TITLES.get(kind, "Босс"))


func is_vulnerable() -> bool:
	return false


func is_dead_v024() -> bool:
	return hp <= 0


func take_damage(amount: int) -> void:
	NetSession.send_hit(remote_id, amount, str(GameState.get_selected_item().get("id", "")))


func take_arrow(amount: int, _a: Node) -> void:
	NetSession.send_hit(remote_id, amount, "arrow")


func die_out() -> void:
	if _model and _model.has_method("play_state"):
		_model.call("play_state", "death")
	else:
		load("res://scripts/mob_fx.gd").death(self, Color(0.6, 0.5, 0.6), 0.8)
	for s in _segs:
		if is_instance_valid(s): s.queue_free()
	get_tree().create_timer(0.9).timeout.connect(queue_free)
