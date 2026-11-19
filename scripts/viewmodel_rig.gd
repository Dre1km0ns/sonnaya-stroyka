extends Node3D
## v0.11: единый first-person rig для инструментов.
## Camera3D → ViewModelRoot (этот узел) → HandRoot → GripPivot → SwingPivot → ToolModel (+ рука).
## HandRoot  — где в кадре держится предмет (позиция/поворот/масштаб из TOOL_CONFIG, + bob и отвод от стен).
## GripPivot — точка хвата: модель смещена так, что рукоять лежит в нуле пивота (grip_offset).
## SwingPivot — анимируется ТОЛЬКО он; после удара всегда возвращается в ноль.

const BlockTex := preload("res://scripts/block_tex.gd")

## pos/rot — HandRoot в пространстве камеры; scale — модели; grip — смещение модели (в её координатах),
## swing_time — длительность удара, swing — пик поворота SwingPivot (градусы), wind — замах, speed — множитель.
const TOOL_CONFIG := {
	"pickaxe":  {"pos": Vector3(0.31, -0.33, -0.52), "rot": Vector3(-18, -12, 12), "scale": 0.46, "grip": Vector3(0.0, -0.13, 0.0),
		"swing_time": 0.30, "wind": Vector3(22, 6, -6), "swing": Vector3(-68, 10, 10), "speed": 1.0},
	"pickaxe2": {"pos": Vector3(0.31, -0.33, -0.52), "rot": Vector3(-18, -12, 12), "scale": 0.46, "grip": Vector3(0.0, -0.13, 0.0),
		"swing_time": 0.24, "wind": Vector3(22, 6, -6), "swing": Vector3(-68, 10, 10), "speed": 1.25},
	"sword":    {"pos": Vector3(0.30, -0.31, -0.50), "rot": Vector3(-34, -8, 22), "scale": 0.44, "grip": Vector3(0.0, -0.28, 0.0),
		"swing_time": 0.26, "wind": Vector3(18, -18, -14), "swing": Vector3(-62, 34, 30), "speed": 1.0},
	"sword2":   {"pos": Vector3(0.30, -0.31, -0.50), "rot": Vector3(-34, -8, 22), "scale": 0.46, "grip": Vector3(0.0, -0.28, 0.0),
		"swing_time": 0.26, "wind": Vector3(18, -18, -14), "swing": Vector3(-62, 34, 30), "speed": 1.0},
	# v0.13: у объёмной 3D-модели (v0.11.1) рукоять на y 0.04…0.28, а grip был скопирован со спрайтового меча (−0.28):
	# кулак оказывался на 0.25 ед. модели НИЖЕ навершия, и меч «висел в воздухе». Хват — центр рукояти.
	"sword3":   {"pos": Vector3(0.30, -0.31, -0.50), "rot": Vector3(-34, -8, 22), "scale": 0.46, "grip": Vector3(0.0, 0.16, 0.0),
		"swing_time": 0.24, "wind": Vector3(18, -18, -14), "swing": Vector3(-64, 36, 32), "speed": 1.1},
	"torch":    {"pos": Vector3(0.30, -0.36, -0.48), "rot": Vector3(-14, 0, 10), "scale": 0.55, "grip": Vector3(0.0, -0.16, 0.0),
		"swing_time": 0.22, "wind": Vector3(10, 0, 0), "swing": Vector3(-30, 0, 6), "speed": 1.0},
}
## v0.13: диапазон рукояти по Y в координатах модели (проверяется smoke: grip обязан лежать внутри).
const HANDLE_Y := {
	"pickaxe": Vector2(-0.28, 0.35), "pickaxe2": Vector2(-0.28, 0.35),
	"sword": Vector2(-0.40, -0.17), "sword2": Vector2(-0.40, -0.17),
	"sword3": Vector2(0.04, 0.28),
	"torch": Vector2(-0.40, 0.10),
}
const WALL_PROBE := 0.85
const BOB_AMOUNT := 0.012

var hand_root: Node3D
var grip_pivot: Node3D
var swing_pivot: Node3D
var models: Dictionary = {}       # id -> Node3D (ToolModel)
var current := ""
var swinging := false
var swing_count := 0
var recoil_count := 0
var retract := 0.0
var _tween: Tween
var _bob_t := 0.0
var _light: OmniLight3D
var player: Node3D
var arms: Node3D


func _ready() -> void:
	name = "ViewModelRoot"
	hand_root = Node3D.new(); hand_root.name = "HandRoot"; add_child(hand_root)
	grip_pivot = Node3D.new(); grip_pivot.name = "GripPivot"; hand_root.add_child(grip_pivot)
	swing_pivot = Node3D.new(); swing_pivot.name = "SwingPivot"; grip_pivot.add_child(swing_pivot)
	for id in TOOL_CONFIG.keys():
		var m := _build_model(id)
		m.name = "ToolModel_" + id
		m.visible = false
		swing_pivot.add_child(m)
		models[id] = m
	var arm := _build_arm()
	arm.name = "Arm"
	arm.visible = false
	swing_pivot.add_child(arm)
	# v0.22: настоящая рука от первого лица (Kenney Blocky Characters, CC0) вместо кубика-кулака
	arms = load("res://scripts/fp_arms.gd").new()
	arms.player = player
	add_child(arms)
	_light = OmniLight3D.new()
	_light.name = "HeldLight"
	_light.light_color = Color(1.0, 0.72, 0.4)
	_light.omni_range = 7.0
	_light.light_energy = 1.3
	_light.shadow_enabled = false
	_light.visible = false
	swing_pivot.add_child(_light)
	set_tool("")


static func is_viewmodel_tool(id: String) -> bool:
	return TOOL_CONFIG.has(id)


static func grip_in_handle(id: String) -> bool:
	## Кулак (ноль GripPivot) должен попадать в рукоять модели, а не висеть рядом.
	if not TOOL_CONFIG.has(id) or not HANDLE_Y.has(id):
		return false
	var g: float = Vector3(TOOL_CONFIG[id].grip).y
	var r: Vector2 = HANDLE_Y[id]
	return g >= r.x and g <= r.y


func config(id: String) -> Dictionary:
	return TOOL_CONFIG.get(id, {})


func set_tool(id: String) -> void:
	if id == current and hand_root.visible == TOOL_CONFIG.has(id):
		return
	current = id if TOOL_CONFIG.has(id) else ""
	for k in models:
		(models[k] as Node3D).visible = k == current
	hand_root.visible = current != ""
	var arm := swing_pivot.get_node_or_null("Arm") as Node3D
	if arm: arm.visible = false # v0.22: кулак заменён рукой модели (FirstPersonArms)
	_light.visible = current == "torch"
	_light.omni_range = 7.0
	if current == "":
		return
	var c: Dictionary = TOOL_CONFIG[current]
	hand_root.position = c.pos
	hand_root.rotation_degrees = c.rot
	var m: Node3D = models[current]
	m.scale = Vector3.ONE * float(c.scale)
	m.position = -Vector3(c.grip) * float(c.scale)
	if _tween and _tween.is_valid(): _tween.kill()
	swing_pivot.rotation = Vector3.ZERO
	swing_pivot.position = Vector3.ZERO
	swinging = false
	_light.position = Vector3(0, 0.30 if current == "torch" else 0.02, 0)


func play_recoil(solid_hit: bool = true) -> void:
	## Короткая отдача после попадания. Не трясёт камеру.
	## v0.22: отдача прерывает замах (раньше во время замаха её просто пропускали — удар не ощущался).
	recoil_count += 1
	if current == "":
		return
	if swinging and is_inside_tree():
		# попадание считается сразу, а отдача — в момент удара замаха (≈60 % его длительности)
		var c: Dictionary = TOOL_CONFIG[current]
		var t := float(c.swing_time) / maxf(0.1, float(c.speed)) * 0.6
		get_tree().create_timer(t).timeout.connect(func() -> void: _do_recoil(solid_hit))
		return
	_do_recoil(solid_hit)


func _do_recoil(solid_hit: bool) -> void:
	if current == "" or not is_inside_tree():
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	swinging = false
	var back := 0.07 if solid_hit else 0.035
	var kick := Vector3(16 if solid_hit else 7, -4, -6 if solid_hit else -2)
	_tween = create_tween()
	_tween.tween_property(swing_pivot, "position", Vector3(0, -0.01, back), 0.05).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(swing_pivot, "rotation_degrees", kick, 0.05)
	_tween.tween_property(swing_pivot, "position", Vector3.ZERO, 0.10).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(swing_pivot, "rotation_degrees", Vector3.ZERO, 0.10)


func play_action(kind: String) -> void:
	if arms and arms.has_method("play_action"):
		arms.play_action(kind)


func play_swing(kind: String = "attack") -> void:
	play_action(kind)
	if current == "":
		return
	var c: Dictionary = TOOL_CONFIG[current]
	var t := float(c.swing_time) / maxf(0.1, float(c.speed))
	if _tween and _tween.is_valid(): _tween.kill()
	swing_pivot.rotation = Vector3.ZERO
	swinging = true
	swing_count += 1
	_tween = create_tween()
	_tween.tween_property(swing_pivot, "rotation_degrees", Vector3(c.wind), t * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(swing_pivot, "rotation_degrees", Vector3(c.swing), t * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(swing_pivot, "rotation_degrees", Vector3.ZERO, t * 0.40).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void: swinging = false)


func _process(delta: float) -> void:
	if current == "" or not is_inside_tree():
		return
	var c: Dictionary = TOOL_CONFIG[current]
	# Отвод от стен: короткий луч из камеры; ближе WALL_PROBE — рука уходит назад и вниз.
	var cam := get_parent() as Node3D
	var want := 0.0
	if cam and get_world_3d():
		var from := cam.global_position
		var to := from - cam.global_transform.basis.z * WALL_PROBE
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
		if player is CollisionObject3D: q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = clampf(1.0 - from.distance_to(hit.position) / WALL_PROBE, 0.0, 1.0)
	retract = lerpf(retract, want, clampf(delta * 14.0, 0.0, 1.0))
	var bob := Vector3.ZERO
	if player and "velocity" in player:
		var v: Vector3 = player.get("velocity")
		var sp := Vector2(v.x, v.z).length()
		if sp > 0.5 and not bool(player.get("flying") if "flying" in player else false):
			_bob_t += delta * sp * 1.6
			bob = Vector3(cos(_bob_t) * BOB_AMOUNT, absf(sin(_bob_t)) * BOB_AMOUNT, 0.0)
	hand_root.position = Vector3(c.pos) + bob + Vector3(-0.04, -0.10, 0.26) * retract
	hand_root.rotation_degrees = Vector3(c.rot) + Vector3(18, 0, 0) * retract


# ---------------------------------------------------------------- модели

func _build_model(id: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match id:
		"torch":
			# v0.11.1: тот же факел, что и в мире: рукоять, обмотка, обугленный верх и язык пламени.
			mi.mesh = BlockTex.torch_mesh()
			mi.position = Vector3(0, -0.04, 0)
			root.add_child(mi)
			var fl := MeshInstance3D.new()
			fl.name = "Flame"
			fl.mesh = BlockTex.torch_flame_mesh()
			fl.position = mi.position
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(fl)
		_:
			mi.mesh = BlockTex.tool_mesh(id)
			root.add_child(mi)
	return root


func _flame(at: Vector3, r: float) -> MeshInstance3D:
	var f := MeshInstance3D.new()
	f.name = "Flame"
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.2
	f.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.7, 0.25)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.12)
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.material_override = m
	f.position = at
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return f


func _build_arm() -> Node3D:
	## Простая «рука» в стиле блоков: кулак на рукояти (рукав убран — перекрывал угол кадра).
	var arm := Node3D.new()
	var skin := StandardMaterial3D.new(); skin.albedo_color = Color(0.86, 0.66, 0.52)
	var fist := MeshInstance3D.new()
	var fb := BoxMesh.new(); fb.size = Vector3(0.085, 0.085, 0.085); fist.mesh = fb
	fist.material_override = skin
	fist.position = Vector3(0.0, 0.0, 0.0)
	fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(fist)
	return arm
