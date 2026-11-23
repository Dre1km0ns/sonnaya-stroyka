extends Node3D
## v0.24: новые телеграфируемые атаки боссов (самостоятельные узлы — телеграф, урон и уборка внутри).
##   pillars — Мать блоков, фаза 2+: «Каменный вал». Красная полоса по земле к игроку 1.0 с, затем из неё
##             волной вырастают каменные столбы (14 урона, подбрасывают). Уйти вбок — спасает.
##   venom   — Анаконда, фаза 2+: «Ядовитый плевок». Голова светится зелёным 0.8 с, на земле зелёные круги
##             там, где упадут 3 сгустка; лужи яда 3 с жгут по 5 урона в секунду.
const BlockTex := preload("res://scripts/block_tex.gd")
const CU := preload("res://scripts/combat_util.gd")
const Sfx := preload("res://scripts/sfx.gd")
const PILLAR_TELE := 1.0
const PILLAR_DMG := 14
const PILLAR_LEN := 14.0
const PILLAR_STEP := 1.1
const VENOM_TELE := 0.8
const VENOM_DMG := 8
const VENOM_PUDDLE_DPS := 5.0
const VENOM_PUDDLE_TIME := 3.0
const VENOM_R := 1.4

var kind := "pillars"
var source := ""
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var points: Array = []
var damage := PILLAR_DMG
var _t := 0.0
var _fx: Array = []
var _hit: Dictionary = {}
var _risen := 0
var _launched := false
var _globs: Array = []
var _puddles: Array = []
var _tick_hit := {}
var head: Node3D = null


static func pillars(host: Node, from: Vector3, toward: Vector3, ground_y: Callable, dmg: int = PILLAR_DMG) -> Node3D:
	var a: Node3D = load("res://scripts/boss_extra_attacks.gd").new()
	a.kind = "pillars"; a.source = "Мать блоков: каменный вал"
	var d := toward - from; d.y = 0
	a.dir = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	a.origin = from
	a.damage = GameState.diff_damage(dmg)
	var n := int(PILLAR_LEN / PILLAR_STEP)
	for i in range(1, n + 1):
		var p: Vector3 = from + a.dir * (float(i) * PILLAR_STEP)
		p.y = float(ground_y.call(p))
		a.points.append(p)
	host.add_child(a)
	return a


static func venom(host: Node, from_head: Node3D, target: Vector3, ground_y: Callable, n: int = 3) -> Node3D:
	var a: Node3D = load("res://scripts/boss_extra_attacks.gd").new()
	a.kind = "venom"; a.source = "Анаконда: ядовитый плевок"
	a.head = from_head
	a.origin = from_head.global_position
	a.damage = GameState.diff_damage(VENOM_DMG)
	for i in range(n):
		var off := Vector3.ZERO if i == 0 else Vector3(cos(i * 2.1) * 2.4, 0, sin(i * 2.1) * 2.4)
		var p := target + off
		p.y = float(ground_y.call(p))
		a.points.append(p)
	host.add_child(a)
	return a


func _mat(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	if emit > 0.0:
		m.emission_enabled = true; m.emission = Color(c.r, c.g, c.b); m.emission_energy_multiplier = emit
	return m


func _ready() -> void:
	add_to_group("boss_attack_fx")
	if kind == "pillars":
		for p in points:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(1.0, 0.04, PILLAR_STEP * 0.92)
			mi.mesh = bm
			mi.material_override = _mat(Color(1.0, 0.2, 0.1, 0.55), 1.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_position = (p as Vector3) + Vector3(0, 0.06, 0)
			mi.look_at(mi.global_position + dir, Vector3.UP)
			_fx.append(mi)
		Sfx.play("slam", get_tree().root, -6.0, 0.7)
	else:
		for p in points:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new(); cm.top_radius = VENOM_R; cm.bottom_radius = VENOM_R; cm.height = 0.04
			mi.mesh = cm
			mi.material_override = _mat(Color(0.3, 1.0, 0.2, 0.45), 1.2)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_position = (p as Vector3) + Vector3(0, 0.06, 0)
			_fx.append(mi)
		if head and is_instance_valid(head):
			_glow_head(true)
		Sfx.play("laser_charge", get_tree().root, -8.0, 0.6)


func _glow_head(on: bool) -> void:
	if head == null or not is_instance_valid(head):
		return
	var light := head.get_node_or_null("VenomGlow") as OmniLight3D
	if on and light == null:
		light = OmniLight3D.new(); light.name = "VenomGlow"; light.light_color = Color(0.4, 1.0, 0.3); light.light_energy = 6.0; light.omni_range = 5.0
		head.add_child(light)
	elif not on and light:
		light.queue_free()


func _physics_process(delta: float) -> void:
	if GameState.is_dream():
		return
	_t += delta
	if kind == "pillars":
		_tick_pillars()
	else:
		_tick_venom(delta)


func _tick_pillars() -> void:
	if _t < PILLAR_TELE:
		for mi in _fx:
			((mi as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.35 + 0.35 * absf(sin(_t * 14.0))
		return
	var want := mini(points.size(), int((_t - PILLAR_TELE) / 0.05) + 1)
	while _risen < want:
		var p: Vector3 = points[_risen]
		var mi: MeshInstance3D = _fx[_risen]
		mi.mesh = BlockTex.cube_mesh("stone", Vector3(0.95, 1.8, 0.95))
		mi.material_override = BlockTex.material()
		mi.global_position = p + Vector3(0, -1.0, 0)
		mi.rotation = Vector3.ZERO
		var tw := create_tween()
		tw.tween_property(mi, "global_position:y", p.y + 0.85, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for pl in CU.players(get_tree()):
			var pp := (pl as Node3D).global_position
			if not _hit.has(pl) and Vector2(pp.x - p.x, pp.z - p.z).length() < 0.95 and absf(pp.y - p.y) < 2.2:
				_hit[pl] = true
				CU.hurt(pl, damage, source, p)
				CU.push(pl, Vector3(0, 8.0, 0) + dir * 2.0)
		if _risen % 3 == 0:
			Sfx.play("slam", get_tree().root, -10.0, 1.3)
			GameState.shake(0.25)
		_risen += 1
	if _t > PILLAR_TELE + points.size() * 0.05 + 1.2:
		queue_free()


func _tick_venom(delta: float) -> void:
	if _t < VENOM_TELE:
		for mi in _fx:
			((mi as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.25 + 0.3 * absf(sin(_t * 10.0))
		return
	if not _launched:
		_launched = true
		_glow_head(false)
		var from := head.global_position if head and is_instance_valid(head) else origin
		for i in range(points.size()):
			var g := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.3; sm.height = 0.6
			g.mesh = sm
			g.material_override = _mat(Color(0.35, 1.0, 0.25), 2.0)
			add_child(g)
			g.global_position = from
			_globs.append({"node": g, "from": from, "to": points[i], "t": 0.0, "dur": 0.75 + 0.1 * i, "done": false})
		Sfx.play("eat", get_tree().root, -4.0, 0.6)
	for gl in _globs:
		if gl.done:
			continue
		gl.t += delta
		var k := clampf(float(gl.t) / float(gl.dur), 0.0, 1.0)
		var pos: Vector3 = (gl.from as Vector3).lerp(gl.to, k) + Vector3(0, sin(k * PI) * 4.0, 0)
		(gl.node as Node3D).global_position = pos
		if k >= 1.0:
			gl.done = true
			(gl.node as Node3D).scale = Vector3(VENOM_R * 2.2, 0.12, VENOM_R * 2.2)
			_puddles.append({"pos": gl.to, "t": 0.0, "node": gl.node})
			for pl in CU.players(get_tree()):
				if (pl as Node3D).global_position.distance_to(gl.to) < VENOM_R + 0.3:
					CU.hurt(pl, damage, source, gl.to)
	var alive := false
	for pd in _puddles:
		pd.t += delta
		if float(pd.t) < VENOM_PUDDLE_TIME:
			alive = true
			for pl in CU.players(get_tree()):
				if (pl as Node3D).global_position.distance_to(pd.pos) < VENOM_R:
					_tick_hit[pl] = float(_tick_hit.get(pl, 0.0)) + VENOM_PUDDLE_DPS * delta
					if float(_tick_hit[pl]) >= 1.0:
						var whole := int(_tick_hit[pl])
						_tick_hit[pl] = float(_tick_hit[pl]) - whole
						CU.hurt(pl, whole, "Анаконда: лужа яда", pd.pos)
		elif is_instance_valid(pd.node):
			(pd.node as Node).queue_free()
	if _launched and not alive and _puddles.size() == _globs.size() and _globs.size() > 0:
		queue_free()
	if _t > 8.0:
		queue_free()


func _exit_tree() -> void:
	_glow_head(false)
