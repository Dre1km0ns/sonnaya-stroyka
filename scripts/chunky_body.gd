extends Node3D
## v0.25.1 (t147u): у каждого моба своя стройная модель с пиксельными текстурами (_build_slim); толстый вариант остался только у Антона.
## толстые руки и ноги, оружие в правой руке. Узел называется «Model» и заменяет старые модели:
## enemy_visuals.play_state() зовёт play_state() здесь. Ходьба определяется сама по сдвигу родителя.
## Тот же пресет строит прокси моба у клиента в сетевой игре (net_proxy) — по ключу preset.

const H0 := 3.9   # рост «эталонной» фигуры, потом масштаб под spec.h
const BlockTex := preload("res://scripts/block_tex.gd")

const PRESETS := {
	# v0.25.1 (t147u): у каждого моба своя стройная модель и пиксельные текстуры, приглушённые цвета.
	"seam": {"h": 1.7, "look": "zombie", "suit": Color(0.33, 0.27, 0.22), "suit2": Color(0.24, 0.22, 0.2), "skin": Color(0.47, 0.53, 0.42), "head": "stitch", "weapon": "claws", "eye": Color(0.9, 0.75, 0.35)},
	"seam_elite": {"h": 2.0, "look": "brute", "suit": Color(0.28, 0.22, 0.2), "suit2": Color(0.2, 0.18, 0.17), "skin": Color(0.42, 0.45, 0.38), "head": "horns", "weapon": "club", "eye": Color(1.0, 0.45, 0.25), "plate": true},
	"ghost0": {"h": 1.65, "look": "shroud", "suit": Color(0.62, 0.66, 0.7), "suit2": Color(0.45, 0.49, 0.55), "skin": Color(0.12, 0.13, 0.16), "head": "hoodvoid", "weapon": "none", "float": true, "eye": Color(0.55, 0.8, 1.0)},
	"ghost1": {"h": 1.65, "look": "imp", "suit": Color(0.42, 0.3, 0.34), "suit2": Color(0.3, 0.22, 0.25), "skin": Color(0.55, 0.42, 0.44), "head": "imp", "weapon": "claws", "eye": Color(1.0, 0.6, 0.3)},
	"ghost2": {"h": 1.65, "look": "demon", "suit": Color(0.24, 0.27, 0.34), "suit2": Color(0.16, 0.17, 0.22), "skin": Color(0.33, 0.38, 0.48), "head": "horns", "weapon": "club", "eye": Color(1.0, 0.8, 0.3)},
	"ghost3": {"h": 1.65, "look": "skeleton", "suit": Color(0.3, 0.27, 0.24), "suit2": Color(0.22, 0.2, 0.18), "skin": Color(0.8, 0.77, 0.68), "head": "skull", "weapon": "dagger", "eye": Color(1.0, 0.5, 0.2)},
	"jumper": {"h": 1.65, "look": "frog", "suit": Color(0.36, 0.4, 0.26), "suit2": Color(0.28, 0.26, 0.18), "skin": Color(0.42, 0.5, 0.3), "head": "frog", "weapon": "none", "eye": Color(0.95, 0.7, 0.2)},
	"archer": {"h": 1.7, "look": "ranger", "suit": Color(0.42, 0.31, 0.2), "suit2": Color(0.22, 0.28, 0.2), "skin": Color(0.72, 0.58, 0.46), "head": "hood", "weapon": "bow", "eye": Color(0.12, 0.1, 0.08)},
	"thief": {"h": 1.15, "look": "thief", "suit": Color(0.25, 0.25, 0.27), "suit2": Color(0.17, 0.17, 0.19), "skin": Color(0.7, 0.56, 0.45), "head": "mask", "weapon": "dagger", "eye": Color(0.95, 0.85, 0.5), "sack": true},
	"clown": {"h": 1.35, "look": "clown", "suit": Color(0.66, 0.57, 0.32), "suit2": Color(0.5, 0.21, 0.2), "skin": Color(0.9, 0.86, 0.8), "head": "clown", "weapon": "dynamite", "eye": Color(0.08, 0.08, 0.1)},
	"clown_shard": {"h": 1.05, "look": "clown", "suit": Color(0.5, 0.36, 0.6), "suit2": Color(0.32, 0.24, 0.42), "skin": Color(0.9, 0.86, 0.8), "head": "clown", "weapon": "none", "eye": Color(0.08, 0.08, 0.1)},
	"clown_friend": {"h": 1.35, "look": "clown", "suit": Color(0.4, 0.6, 0.38), "suit2": Color(0.26, 0.4, 0.26), "skin": Color(0.9, 0.86, 0.8), "head": "clown", "weapon": "none", "eye": Color(0.08, 0.08, 0.1)},
	"lizard": {"h": 0.7, "look": "lizard", "suit": Color(0.36, 0.44, 0.28), "suit2": Color(0.62, 0.6, 0.45), "skin": Color(0.4, 0.48, 0.3), "head": "lizard", "weapon": "claws", "eye": Color(1.0, 0.65, 0.2), "tail": true},
	"anton": {"h": 3.85, "suit": Color(1.0, 0.82, 0.2), "suit2": Color(0.95, 0.25, 0.35), "skin": Color(0.93, 0.74, 0.6), "head": "clown", "weapon": "none", "eye": Color(0.05, 0.05, 0.08), "arm_r": 1.4},
	"player": {"h": 1.8, "look": "human", "suit": Color(0.3, 0.4, 0.55), "suit2": Color(0.3, 0.25, 0.2), "skin": Color(0.86, 0.68, 0.54), "head": "hair", "weapon": "held", "eye": Color(0.1, 0.1, 0.12)},
}

var preset := "seam"
var spec: Dictionary = {}
var state := "idle"
var net_state := 0          # счётчик атак — для сети (прокси повторяет удар)
var dead := false
var rig: Dictionary = {}
var _t := 0.0
var _pt := 0.0
var _last_pos := Vector3.INF
var _speed := 0.0
var _hold := 0.0             # сколько ещё держать позу атаки/прыжка
var _root: Node3D
var _held: Node3D


static func make(p: String, override: Dictionary = {}) -> Node3D:
	var b: Node3D = load("res://scripts/chunky_body.gd").new()
	b.name = "Model"
	b.preset = p if PRESETS.has(p) else "seam"
	var s: Dictionary = (PRESETS[b.preset] as Dictionary).duplicate()
	for k in override: s[k] = override[k]
	b.spec = s
	b._build()
	return b


func _mat(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	if emit > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _part(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var n := Node3D.new(); n.name = nm; n.position = pos
	parent.add_child(n)
	return n


func _ball(parent: Node3D, nm: String, r: float, pos: Vector3, col: Color, sc: Vector3 = Vector3.ONE, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = nm
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 14; sm.rings = 7
	mi.mesh = sm; mi.material_override = _mat(col, emit); mi.position = pos; mi.scale = sc
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, col: Color, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = nm
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = _mat(col, emit); mi.position = pos
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, nm: String, r: float, h: float, pos: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = nm
	var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = r; cm.height = h; cm.radial_segments = 10
	mi.mesh = cm; mi.material_override = _mat(col); mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi


func height() -> float:
	return float(spec.get("h", 1.7))


func _build() -> void:
	if preset != "anton":
		_build_slim()
		return
	var suit: Color = spec.suit; var suit2: Color = spec.suit2; var skin: Color = spec.skin
	var eye: Color = spec.get("eye", Color(0.05, 0.05, 0.08))
	var bk := float(spec.get("belly", 1.0)) * (1.0 if preset == "anton" else 0.8)   # мобы стройнее Антона
	spec["bk"] = bk
	var floaty := bool(spec.get("float", false))
	_root = _part(self, "Scaled", Vector3.ZERO)
	_root.scale = Vector3.ONE * (height() / H0)
	var body := _part(_root, "Body", Vector3.ZERO)
	rig["body"] = body
	rig["belly"] = _ball(body, "Belly", 1.55, Vector3(0, 2.0, 0.05), suit, Vector3(1.2 * bk, 1.0, 1.08 * bk))
	_ball(body, "Band", 1.58, Vector3(0, 1.55, 0.05), suit2, Vector3(1.22 * bk, 0.32, 1.1 * bk))
	_ball(body, "Shoulders", 1.0, Vector3(0, 3.0, -0.05), suit, Vector3(1.45 + 0.55 * bk, 0.75, 1.1))
	var head := _part(body, "Head", Vector3(0, 3.25, 0.6))
	head.scale = Vector3.ONE * float(spec.get("head_k", 1.0 if preset == "anton" else 1.4))
	rig["head"] = head
	var hk: String = str(spec.get("head", "none"))
	var face_r := 0.62 if hk in ["frog", "lizard"] else 0.55
	_ball(head, "Face", face_r, Vector3(0, 0.15, 0), skin, Vector3(1.1 if hk == "frog" else 1.0, 0.85 if hk == "frog" else 1.0, 1.25 if hk == "lizard" else 1.0))
	for sd in [-1.0, 1.0]:
		_ball(head, "Eye", 0.1, Vector3(sd * 0.22, 0.3 if hk != "frog" else 0.62, 0.48), eye, Vector3.ONE, 2.0 if eye.v > 0.5 else 0.0)
	match hk:
		"horns":
			for sd in [-1.0, 1.0]:
				_cone(head, "Horn", 0.14, 0.6, Vector3(sd * 0.34, 0.7, -0.05), suit2.lightened(0.5), Vector3(0, 0, -sd * 0.45))
			_ball(head, "Jaw", 0.3, Vector3(0, -0.12, 0.42), suit2, Vector3(1.6, 0.5, 0.6))
		"ghost":
			_ball(head, "Mouth", 0.14, Vector3(0, -0.08, 0.5), Color(0.1, 0.1, 0.2), Vector3(1.4, 1.0, 0.4))
		"skull":
			_ball(head, "Mouth", 0.2, Vector3(0, -0.18, 0.44), Color(0.2, 0.18, 0.16), Vector3(1.5, 0.45, 0.5))
			_box(head, "Teeth", Vector3(0.4, 0.08, 0.05), Vector3(0, -0.12, 0.6), Color(1, 1, 0.95))
		"cap":
			_ball(head, "Cap", 0.56, Vector3(0, 0.42, -0.04), suit2, Vector3(1.05, 0.55, 1.05))
			_box(head, "Visor", Vector3(0.6, 0.06, 0.35), Vector3(0, 0.42, 0.55), suit2)
		"frog":
			_ball(head, "Mouth", 0.3, Vector3(0, 0.0, 0.42), suit2, Vector3(1.6, 0.25, 0.6))
		"hood":
			_ball(head, "Hood", 0.68, Vector3(0, 0.25, -0.12), suit2, Vector3(1.0, 1.05, 1.0))
			_box(head, "Scarf", Vector3(0.9, 0.18, 0.7), Vector3(0, -0.28, 0.08), suit)
		"mask":
			_box(head, "Mask", Vector3(0.95, 0.2, 0.2), Vector3(0, 0.3, 0.42), Color(0.1, 0.08, 0.12))
			_ball(head, "Beanie", 0.56, Vector3(0, 0.42, -0.04), Color(0.2, 0.18, 0.25), Vector3(1.05, 0.6, 1.05))
		"clown":
			_ball(head, "ClownNose", 0.2, Vector3(0, 0.12, 0.55), Color(1, 0.08, 0.1), Vector3.ONE, 0.6)
			for sd in [-1.0, 1.0]:
				_ball(head, "Wig", 0.3, Vector3(sd * 0.5, 0.3, -0.05), Color(1.0, 0.45, 0.1), Vector3(1, 0.85, 1))
			_ball(head, "Mouth", 0.16, Vector3(0, -0.14, 0.48), Color(0.75, 0.05, 0.1), Vector3(1.8, 0.6, 0.6))
			_cone(head, "Hat", 0.32, 0.8, Vector3(0, 0.95, -0.05), Color(0.3, 0.5, 1.0), Vector3(-0.25, 0, 0))
			_ball(head, "Ruff", 0.6, Vector3(0, -0.34, -0.05), Color(1, 1, 1), Vector3(1.3, 0.35, 1.2))
		"lizard":
			_ball(head, "Snout", 0.36, Vector3(0, 0.02, 0.6), skin, Vector3(1.0, 0.6, 1.2))
			_box(head, "Crest", Vector3(0.08, 0.3, 0.7), Vector3(0, 0.62, -0.05), suit2)
		"hair":
			_ball(head, "Hair", 0.58, Vector3(0, 0.36, -0.08), Color(0.3, 0.2, 0.12), Vector3(1.02, 0.62, 1.02))
			_ball(head, "Mouth", 0.08, Vector3(0, -0.12, 0.5), Color(0.6, 0.25, 0.25), Vector3(2.0, 0.5, 0.5))
	# руки
	var ark := float(spec.get("arm_r", 1.15))
	for sd in [1.0, -1.0]:
		var right: bool = sd > 0.0
		var k: float = ark if right else 1.0
		var sh := _part(body, "ShoulderR" if right else "ShoulderL", Vector3(-sd * (1.45 + 0.65 * bk), 2.95, 0.15))
		_ball(sh, "Upper", 0.52 * k, Vector3(0, -0.52 * k, 0), suit, Vector3(1, 1.5, 1))
		var el := _part(sh, "Elbow", Vector3(0, -1.1 * k, 0))
		_ball(el, "Fore", 0.47 * k, Vector3(0, -0.42 * k, 0.1), skin, Vector3(1, 1.4, 1))
		var fist := _ball(el, "Fist", 0.5 * k, Vector3(0, -0.95 * k, 0.15), skin, Vector3(1.1, 0.95, 1.1))
		rig["sh_r" if right else "sh_l"] = sh
		rig["el_r" if right else "el_l"] = el
		rig["fist_r" if right else "fist_l"] = fist
		if str(spec.weapon) == "claws":
			for i in 3:
				_cone(fist, "Claw", 0.09, 0.45, Vector3((i - 1) * 0.2, -0.35, 0.3), Color(0.95, 0.92, 0.85), Vector3(0.6, 0, 0))
	_build_weapon(rig.fist_r)
	if bool(spec.get("sack", false)):
		_ball(body, "Sack", 0.9, Vector3(0, 2.4, -1.4), Color(0.6, 0.48, 0.3), Vector3(1, 1.1, 0.8))
	# ноги или хвост-облачко
	var lk := float(spec.get("legs_k", 1.0))
	if floaty:
		_ball(body, "Tail", 1.1, Vector3(0, 0.8, 0), suit2, Vector3(1.1 * bk, 0.9, 1.0 * bk))
		_ball(body, "Tail2", 0.6, Vector3(0, 0.15, -0.1), suit2, Vector3(1.0, 0.9, 1.0))
	else:
		for sd in [-1.0, 1.0]:
			var hip := _part(_root, "HipR" if sd < 0 else "HipL", Vector3(sd * 0.75, 0.95, 0))
			_ball(hip, "Leg", 0.48 * lk, Vector3(0, -0.35, 0), suit2, Vector3(1, 1.1, 1))
			_ball(hip, "Boot", 0.43 * lk, Vector3(0, -0.78, 0.2), suit2.darkened(0.45), Vector3(1.1, 0.55, 1.5))
			rig["hip_r" if sd < 0 else "hip_l"] = hip
	if bool(spec.get("tail", false)):
		_cone(body, "LizTail", 0.6, 2.4, Vector3(0, 1.1, -1.9), suit, Vector3(-1.35, 0, 0))
	body.rotation.x = 0.15


func _build_weapon(fist: Node3D) -> void:
	var w := str(spec.weapon)
	var hold := _part(fist, "Hold", Vector3(0, -0.1, 0.35))
	match w:
		"club":
			var c := _box(hold, "Club", Vector3(0.35, 0.35, 2.2), Vector3(0, 0, 1.0), Color(0.45, 0.3, 0.18))
			_ball(c, "Knob", 0.4, Vector3(0, 0, 1.0), Color(0.4, 0.28, 0.16))
		"dagger":
			_box(hold, "Hilt", Vector3(0.16, 0.16, 0.5), Vector3(0, 0, 0.2), Color(0.3, 0.2, 0.1))
			_box(hold, "Blade", Vector3(0.08, 0.22, 1.0), Vector3(0, 0, 0.9), Color(0.85, 0.87, 0.9), 0.3)
		"dynamite":
			var d := MeshInstance3D.new(); d.name = "Dynamite"
			var cm := CylinderMesh.new(); cm.top_radius = 0.22; cm.bottom_radius = 0.22; cm.height = 1.1
			d.mesh = cm; d.material_override = _mat(Color(0.85, 0.12, 0.1)); d.position = Vector3(0, 0.55, 0.05)
			hold.add_child(d)
			_box(d, "Band", Vector3(0.47, 0.18, 0.47), Vector3(0, 0.0, 0), Color(0.95, 0.9, 0.7))
			_box(d, "Fuse", Vector3(0.05, 0.4, 0.05), Vector3(0, 0.72, 0), Color(0.25, 0.2, 0.15))
			rig["spark"] = _ball(d, "Spark", 0.12, Vector3(0, 0.95, 0), Color(1, 0.75, 0.2), Vector3.ONE, 4.0)
		"bow":
			var bow := MeshInstance3D.new(); bow.name = "Bow"
			bow.mesh = BlockTex.bow_mesh(false); bow.material_override = BlockTex.material()
			bow.scale = Vector3.ONE * 2.6
			bow.rotation = Vector3(0, PI * 0.5, 0)
			bow.position = Vector3(0, 0.1, 0.2)
			hold.add_child(bow)
		"held":
			_held = hold
	rig["hold"] = hold


const ARMOR_COLORS := {"wood": Color(0.62, 0.44, 0.24), "metal": Color(0.74, 0.77, 0.84), "scale": Color(0.3, 0.62, 0.42)}
var armor_ids: Array = []


func set_armor(ids: Array) -> void:
	## v0.25: броня на модели (сеть): шлем, нагрудник, поножи, ботинки — по материалу (дерево/металл/чешуя).
	if ids == armor_ids:
		return
	armor_ids = ids.duplicate()
	for key in ["head", "body", "hip_r", "hip_l"]:
		var host: Node3D = rig.get(key)
		if host == null: continue
		for c in host.get_children():
			if str(c.name).begins_with("Armor"): c.queue_free()
	if rig.has("lean"):
		_armor_slim(ids)
		return
	for raw in ids:
		var id := str(raw)
		if id == "": continue
		var mat := id.get_slice("_", 0)
		var col: Color = ARMOR_COLORS.get(mat, Color(0.6, 0.6, 0.6))
		var emit := 0.0
		var m := _mat(col, emit)
		if mat == "metal": m.metallic = 0.8; m.roughness = 0.35
		if id.ends_with("_helmet"):
			var h := _ball(rig.head, "ArmorHelmet", 0.62, Vector3(0, 0.3, -0.03), col, Vector3(1.05, 0.75, 1.05))
			h.material_override = m
			_box(rig.head, "ArmorVisor", Vector3(1.0, 0.1, 0.1), Vector3(0, 0.12, 0.58), col.darkened(0.3))
		elif id.ends_with("_chest"):
			var c2 := _ball(rig.body, "ArmorChest", 1.6, Vector3(0, 2.15, 0.05), col, Vector3(1.24 * float(spec.get("bk", 1.0)), 0.85, 1.12 * float(spec.get("bk", 1.0))))
			c2.material_override = m
			var sp := _ball(rig.body, "ArmorPads", 1.03, Vector3(0, 3.02, -0.05), col, Vector3(2.08, 0.72, 1.14))
			sp.material_override = m
		elif id.ends_with("_legs") and rig.has("hip_r"):
			for k in ["hip_r", "hip_l"]:
				var l := _ball(rig[k], "ArmorLeg", 0.53, Vector3(0, -0.3, 0), col, Vector3(1, 1.05, 1))
				l.material_override = m
		elif id.ends_with("_boots") and rig.has("hip_r"):
			for k in ["hip_r", "hip_l"]:
				var b := _ball(rig[k], "ArmorBoot", 0.47, Vector3(0, -0.78, 0.2), col, Vector3(1.12, 0.6, 1.55))
				b.material_override = m


func set_held(node: Node3D) -> void:
	## Игроки в сети: предмет в руке (меш блока/инструмента).
	if _held == null:
		return
	for c in _held.get_children(): c.queue_free()
	if node:
		_held.add_child(node)


func play_state(st: String, restart: bool = false) -> String:
	if dead and st != "death":
		return st
	match st:
		"attack":
			if state != "attack" or restart or _hold <= 0.1:
				state = "attack"; _pt = 0.0; _hold = 0.55; net_state += 1
		"jump", "crouch", "draw", "hurt", "place":
			if state != st or restart:
				state = st; _pt = 0.0; _hold = 0.45 if st in ["hurt", "place"] else 9.0
		"death":
			if not dead:
				dead = true; state = "death"; _pt = 0.0
		"walk", "idle":
			if _hold <= 0.0:
				state = st
	return st


func release(st: String) -> void:
	## Закончить длительную позу (прыжок/натяжение/присед).
	if state == st:
		_hold = 0.0; state = "idle"


func _process(delta: float) -> void:
	if not is_visible_in_tree() or rig.is_empty():
		return
	_t += delta; _pt += delta
	var gp := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var v := Vector3(gp.x - _last_pos.x, 0, gp.z - _last_pos.z).length() / delta
		_speed = lerpf(_speed, v, clampf(delta * 8.0, 0.0, 1.0))
	_last_pos = gp
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0 and state in ["attack", "hurt", "place"]:
			state = "idle"
	if state in ["idle", "walk"]:
		state = "walk" if _speed > 0.35 else "idle"
	_pose(delta)


func _pose(delta: float) -> void:
	var body: Node3D = rig.body
	var shr: Node3D = rig.sh_r; var shl: Node3D = rig.sh_l
	var elr: Node3D = rig.el_r; var ell: Node3D = rig.el_l
	var t := _t
	var breathe := 1.0 + 0.03 * sin(t * 2.4)
	var slim := rig.has("lean")
	if not slim:
		var bk := float(spec.get("bk", 1.0))
		(rig.belly as Node3D).scale = Vector3(1.2 * bk * (2.0 - breathe), breathe, 1.08 * bk)
	var g := {"bx": 0.15, "bz": 0.0, "by": 0.0, "rx": 0.08 * sin(t * 1.3), "rz": -0.2, "lx": -0.08 * sin(t * 1.3), "lz": 0.2, "er": -0.35, "el": -0.35, "hr": 0.0, "hl": 0.0, "brx": 0.0}
	if slim:
		g.bx = float(spec.get("lean", 0.05)); g.rz = -0.05; g.lz = 0.05; g.er = -0.15; g.el = -0.15
		var lk2 := str(spec.get("look", ""))
		if lk2 == "zombie":
			g.rx = -1.35 + 0.06 * sin(t * 1.7); g.lx = -1.25 - 0.06 * sin(t * 1.7); g.er = -0.1; g.el = -0.1
		elif lk2 in ["imp", "frog", "brute"]:
			g.er = -0.5; g.el = -0.5
	if bool(spec.get("float", false)):
		g.by = 0.25 + 0.15 * sin(t * 2.2)
	var weapon := str(spec.weapon)
	if weapon == "bow" and state != "death":
		g.rx = -1.45; g.lx = -1.5; g.er = -0.1; g.el = -0.1; g.rz = 0.25; g.lz = -0.35
	match state:
		"walk":
			var w := sin(_pt * clampf(_speed * 2.2, 5.0, 12.0))
			g.bz = 0.12 * w
			g.by += absf(w) * 0.12
			g.hr = 0.6 * w; g.hl = -0.6 * w
			if weapon != "bow" and str(spec.get("look", "")) != "zombie":
				g.rx = -0.5 * w; g.lx = 0.5 * w
		"attack":
			var k := _pt / 0.5
			if weapon == "bow":
				g.er = -0.1 - 0.6 * clampf(1.0 - absf(k - 0.4) * 3.0, 0.0, 1.0)
			elif k < 0.38:
				var a := k / 0.38
				g.rx = lerpf(0.0, 2.6, a); g.er = lerpf(-0.35, -1.4, a); g.bx = 0.05; g.bz = 0.12
			else:
				var b := clampf((k - 0.38) / 0.3, 0.0, 1.0)
				g.rx = lerpf(2.6, -1.4, b); g.er = lerpf(-1.4, -0.1, b); g.bx = lerpf(0.05, 0.45, b); g.bz = -0.15 * b
		"jump":
			g.rx = -2.6; g.lx = -2.6; g.rz = -0.7; g.lz = 0.7; g.hr = -0.7; g.hl = -0.7
		"crouch":
			g.by = -0.5; g.bx = 0.5; g.rx = 0.6; g.lx = 0.6; g.hr = -0.9; g.hl = -0.9
		"draw":
			g.er = -0.75
		"hurt":
			g.bx = -0.35; g.rz = -0.9; g.lz = 0.9
		"place":
			var c := clampf(_pt / 0.35, 0.0, 1.0)
			g.rx = -1.3 * sin(c * PI); g.er = -0.3
		"death":
			var dk := clampf(_pt / 0.7, 0.0, 1.0)
			_root.rotation.x = lerpf(0.0, -PI * 0.5, dk * dk)
			_root.position.y = lerpf(0.0, height() * 0.15, dk)
			if _pt > 0.8:
				_root.scale = _root.scale.lerp(Vector3.ONE * 0.001, clampf(delta * 3.0, 0.0, 1.0))
			return
	if rig.has("spark"):
		(rig.spark as Node3D).scale = Vector3.ONE * (0.8 + 0.5 * absf(sin(t * 23.0)))
	var a := clampf(delta * (22.0 if state == "attack" else 10.0), 0.0, 1.0)
	var ln: Node3D = rig.get("lean", body)
	ln.rotation.x = lerpf(ln.rotation.x, g.bx, a)
	ln.rotation.z = lerpf(ln.rotation.z, g.bz, a)
	body.position.y = lerpf(body.position.y, g.by, a)
	shr.rotation.x = lerpf(shr.rotation.x, g.rx, a); shr.rotation.z = lerpf(shr.rotation.z, g.rz, a)
	shl.rotation.x = lerpf(shl.rotation.x, g.lx, a); shl.rotation.z = lerpf(shl.rotation.z, g.lz, a)
	elr.rotation.x = lerpf(elr.rotation.x, g.er, a); ell.rotation.x = lerpf(ell.rotation.x, g.el, a)
	if rig.has("hip_r"):
		(rig.hip_r as Node3D).rotation.x = lerpf((rig.hip_r as Node3D).rotation.x, g.hr, a)
		(rig.hip_l as Node3D).rotation.x = lerpf((rig.hip_l as Node3D).rotation.x, g.hl, a)


# ---------------------------------------------------------------- v0.25.1: стройные модели (t147u)
static var _tex_cache: Dictionary = {}


static func pixel_tex(kind: String, base: Color) -> ImageTexture:
	## Пиксельная текстура 16×16 под стиль Kenney/блоков: ткань, кожа, кожа-доспех, металл, кость, лохмотья, чешуя.
	var key := "%s|%s" % [kind, base.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in 16:
		for x in 16:
			var c := base
			var n := rng.randf_range(-0.035, 0.035)
			match kind:
				"cloth":
					if y % 4 == 3: n -= 0.07
					if (x + y * 3) % 7 == 0: n += 0.04
				"leather":
					n *= 1.3
					if x == 0 or y == 0: n -= 0.1
					if (x == 2 or x == 13) and y % 3 == 1: n += 0.14
				"skin":
					n *= 0.6
					if rng.randf() < 0.04: n -= 0.08
				"metal":
					n *= 0.7
					if x == 0 or y == 0: n += 0.16
					if x == 15 or y == 15: n -= 0.16
					if (x == 2 or x == 13) and (y == 2 or y == 13): n += 0.25
				"bone":
					n *= 0.8
					if (x * 5 + y * 3) % 23 == 0: n -= 0.18
				"rag":
					if rng.randf() < 0.1: n -= 0.16
					if y % 5 == 2 and x % 6 < 4: n -= 0.08
				"scale":
					var cx := (x + (4 if (y / 4) % 2 == 1 else 0)) % 8
					if y % 4 == 3 or cx == 0: n -= 0.12
					elif y % 4 == 0: n += 0.06
				"wood":
					if x % 5 == 0: n -= 0.1
					n += 0.04 * sin(float(y) * 1.3 + float(x))
				"stitch":
					if x == 7 and y % 2 == 0: n -= 0.25
					elif (x == 6 or x == 8) and y % 4 == 1: n -= 0.15
			img.set_pixel(x, y, Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1)))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


func _tmat(kind: String, c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = pixel_tex(kind, c)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.25
	m.roughness = 0.9
	if kind == "metal":
		m.metallic = 0.55; m.roughness = 0.45
	if emit > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m


func _tb(parent: Node3D, nm: String, size: Vector3, pos: Vector3, kind: String, col: Color, rot := Vector3.ZERO, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = nm
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = _tmat(kind, col, emit); mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_slim() -> void:
	## Стройная фигура ростом H0 (3.9 ед.), потом масштаб под spec.h. Таз — узел «Lean» (наклон корпуса).
	var look := str(spec.get("look", "human"))
	var suit: Color = spec.suit; var suit2: Color = spec.suit2; var skin: Color = spec.skin
	var eye: Color = spec.get("eye", Color(0.1, 0.1, 0.1))
	var eye_e := 1.6 if eye.v > 0.5 else 0.0
	var skin_k := "bone" if look == "skeleton" else ("scale" if look in ["lizard", "frog"] else "skin")
	var top_k: String = {"zombie": "rag", "brute": "leather", "shroud": "rag", "imp": "rag", "demon": "leather", "skeleton": "rag", "frog": "leather", "ranger": "leather", "thief": "cloth", "clown": "cloth", "human": "cloth"}.get(look, "cloth")
	_root = _part(self, "Scaled", Vector3.ZERO)
	_root.scale = Vector3.ONE * (height() / H0)
	var body := _part(_root, "Body", Vector3.ZERO)
	rig["body"] = body
	if look == "lizard":
		_build_lizard(body, suit, suit2, skin, eye, eye_e)
		return
	var bulky := look == "brute"
	var tw := 1.25 if bulky else (0.86 if look in ["skeleton", "imp"] else 1.0)
	var leg_h := 1.95 if look == "frog" else 1.75
	var lean := _part(body, "Lean", Vector3(0, leg_h, 0))
	rig["lean"] = lean
	spec["lean"] = {"zombie": 0.18, "imp": 0.32, "frog": 0.3, "brute": 0.12, "thief": 0.15}.get(look, 0.04)
	# корпус
	if look == "skeleton":
		_tb(lean, "Spine", Vector3(0.2, 1.3, 0.2), Vector3(0, 0.65, -0.05), "bone", skin)
		for i in 4:
			_tb(lean, "Rib", Vector3(0.8 - i * 0.08, 0.1, 0.42), Vector3(0, 0.6 + i * 0.18, 0), "bone", skin)
		_tb(lean, "Pelvis", Vector3(0.75, 0.25, 0.35), Vector3(0, 0.1, 0), "bone", skin)
		_tb(lean, "Cloak", Vector3(0.95, 1.2, 0.12), Vector3(0, 0.7, -0.32), "rag", suit)
	else:
		_tb(lean, "Torso", Vector3(1.0 * tw, 1.3, 0.56 * tw), Vector3(0, 0.65, 0), top_k, suit)
		_tb(lean, "Belt", Vector3(1.04 * tw, 0.16, 0.6 * tw), Vector3(0, 0.12, 0), "leather", suit2.darkened(0.3))
		if look == "zombie":
			_tb(lean, "Stitches", Vector3(0.2, 1.0, 0.04), Vector3(0.18, 0.75, 0.29), "stitch", skin)
			_tb(lean, "Tear", Vector3(0.36, 0.3, 0.04), Vector3(-0.22, 0.4, 0.29), "skin", skin.darkened(0.15))
		if look == "ranger":
			_tb(lean, "Cloak", Vector3(1.1, 1.45, 0.1), Vector3(0, 0.62, -0.34), "cloth", suit2)
			_tb(lean, "Quiver", Vector3(0.28, 0.9, 0.28), Vector3(0.28, 0.95, -0.45), "leather", Color(0.35, 0.24, 0.14), Vector3(0, 0, 0.35))
			_tb(lean, "Strap", Vector3(0.14, 1.4, 0.04), Vector3(0, 0.7, 0.29), "leather", Color(0.3, 0.2, 0.12), Vector3(0, 0, 0.6))
		if look == "clown":
			_tb(lean, "Ruff", Vector3(1.3, 0.22, 0.8), Vector3(0, 1.32, 0), "cloth", Color(0.88, 0.86, 0.82))
			for i in 3:
				_tb(lean, "Button", Vector3(0.14, 0.14, 0.05), Vector3(0, 0.35 + i * 0.32, 0.29), "cloth", suit2)
		if look == "shroud":
			for i in 5:
				_tb(lean, "Tatter", Vector3(0.24, 1.2 + 0.25 * (i % 2), 0.5), Vector3(-0.44 + i * 0.22, -0.6 - 0.12 * (i % 2), 0), "rag", suit2)
		if bool(spec.get("plate", false)):
			_tb(lean, "Plate", Vector3(0.55, 0.22, 0.75), Vector3(-0.55 * tw, 1.3, 0), "metal", Color(0.45, 0.45, 0.47), Vector3(0, 0, -0.3))
		if bool(spec.get("sack", false)):
			_tb(lean, "Sack", Vector3(0.75, 0.85, 0.5), Vector3(0, 0.75, -0.55), "rag", Color(0.5, 0.42, 0.3))
	# голова
	var head := _part(lean, "Head", Vector3(0, 1.32, 0))
	rig["head"] = head
	var hk := str(spec.get("head", "hair"))
	var hs := Vector3(0.8, 0.8, 0.8)
	if hk == "frog": hs = Vector3(1.0, 0.62, 0.85)
	if hk == "imp": hs = Vector3(0.75, 0.7, 0.8)
	var face_k := "bone" if hk == "skull" else skin_k
	if hk != "hoodvoid":
		_tb(head, "Face", hs, Vector3(0, hs.y * 0.5 + 0.02, 0), face_k, skin)
	var ey := hs.y * 0.62
	var ez := hs.z * 0.5 + 0.015
	if hk == "frog": ey = hs.y + 0.05
	for sd in [-1.0, 1.0]:
		var es := Vector3(0.16, 0.12, 0.04) if hk != "frog" else Vector3(0.22, 0.22, 0.22)
		if hk == "skull": es = Vector3(0.2, 0.2, 0.04)
		_tb(head, "Eye", es, Vector3(sd * 0.19, ey, ez - (0.06 if hk == "frog" else 0.0)), "skin", eye, Vector3.ZERO, eye_e)
	match hk:
		"stitch":
			_tb(head, "Scar", Vector3(0.06, 0.5, 0.03), Vector3(-0.2, 0.45, ez), "stitch", skin.darkened(0.2))
			_tb(head, "Hair", Vector3(0.84, 0.16, 0.84), Vector3(0, 0.82, -0.02), "rag", Color(0.18, 0.16, 0.14))
			_tb(head, "Mouth", Vector3(0.36, 0.06, 0.03), Vector3(0.04, 0.22, ez), "skin", Color(0.2, 0.15, 0.12))
		"horns":
			for sd in [-1.0, 1.0]:
				_tb(head, "Horn", Vector3(0.12, 0.42, 0.12), Vector3(sd * 0.36, 0.95, 0.0), "bone", Color(0.62, 0.58, 0.5), Vector3(0, 0, -sd * 0.45))
			_tb(head, "Jaw", Vector3(0.62, 0.16, 0.08), Vector3(0, 0.18, ez), "skin", suit2)
		"hoodvoid":
			_tb(head, "Hood", Vector3(0.95, 0.95, 0.9), Vector3(0, 0.45, -0.05), "rag", suit)
			_tb(head, "Void", Vector3(0.66, 0.6, 0.06), Vector3(0, 0.4, 0.41), "skin", skin)
		"imp":
			for sd in [-1.0, 1.0]:
				_tb(head, "Ear", Vector3(0.08, 0.4, 0.22), Vector3(sd * 0.42, 0.62, -0.05), face_k, skin, Vector3(0, 0, -sd * 0.6))
			_tb(head, "Teeth", Vector3(0.4, 0.07, 0.03), Vector3(0, 0.16, ez), "bone", Color(0.85, 0.82, 0.72))
		"skull":
			_tb(head, "Nose", Vector3(0.1, 0.12, 0.03), Vector3(0, 0.36, ez), "skin", Color(0.12, 0.1, 0.08))
			_tb(head, "Teeth", Vector3(0.46, 0.1, 0.03), Vector3(0, 0.14, ez), "bone", skin.lightened(0.15))
		"frog":
			_tb(head, "Mouth", Vector3(0.9, 0.06, 0.03), Vector3(0, 0.2, ez), "skin", Color(0.2, 0.14, 0.1))
		"hood":
			_tb(head, "Hood", Vector3(0.94, 0.94, 0.62), Vector3(0, 0.46, -0.16), "cloth", suit2)
			_tb(head, "HoodTop", Vector3(0.94, 0.14, 0.9), Vector3(0, 0.88, 0.0), "cloth", suit2)
			for sd2 in [-1.0, 1.0]:
				_tb(head, "HoodSide", Vector3(0.08, 0.8, 0.9), Vector3(sd2 * 0.46, 0.45, 0.0), "cloth", suit2)
			_tb(head, "Scarf", Vector3(0.84, 0.24, 0.84), Vector3(0, 0.08, 0.02), "cloth", suit2.darkened(0.2))
		"mask":
			_tb(head, "Mask", Vector3(0.84, 0.16, 0.06), Vector3(0, ey, ez + 0.01), "cloth", Color(0.1, 0.1, 0.11))
			_tb(head, "Beanie", Vector3(0.86, 0.3, 0.86), Vector3(0, 0.8, 0), "cloth", Color(0.22, 0.2, 0.2))
			_tb(head, "Scarf", Vector3(0.84, 0.26, 0.84), Vector3(0, 0.12, 0.02), "cloth", suit2)
		"clown":
			_tb(head, "ClownNose", Vector3(0.18, 0.18, 0.16), Vector3(0, 0.38, ez + 0.06), "skin", Color(0.75, 0.12, 0.12))
			for sd in [-1.0, 1.0]:
				_tb(head, "Wig", Vector3(0.26, 0.4, 0.6), Vector3(sd * 0.5, 0.58, -0.05), "rag", Color(0.72, 0.38, 0.16))
			_tb(head, "Mouth", Vector3(0.4, 0.08, 0.03), Vector3(0, 0.18, ez), "skin", Color(0.6, 0.12, 0.14))
			_tb(head, "Hat", Vector3(0.3, 0.5, 0.3), Vector3(0, 1.05, 0), "cloth", suit2)
		"hair":
			_tb(head, "Hair", Vector3(0.86, 0.2, 0.86), Vector3(0, 0.84, -0.01), "rag", Color(0.28, 0.2, 0.13))
			_tb(head, "HairBack", Vector3(0.86, 0.5, 0.12), Vector3(0, 0.55, -0.42), "rag", Color(0.28, 0.2, 0.13))
			_tb(head, "Mouth", Vector3(0.24, 0.05, 0.03), Vector3(0, 0.2, ez), "skin", Color(0.5, 0.3, 0.26))
	# руки
	var aw := 0.4 * (1.25 if bulky else (0.7 if look == "skeleton" else 1.0))
	var al := 1.25 if look in ["imp", "zombie"] else 1.0
	var sleeve_k: String = "bone" if look == "skeleton" else top_k
	var sleeve_c: Color = skin if look == "skeleton" else suit
	for sd in [1.0, -1.0]:
		var right: bool = sd > 0.0
		var sh := _part(lean, "ShoulderR" if right else "ShoulderL", Vector3(-sd * (0.5 * tw + aw * 0.5 + 0.02), 1.2, 0))
		_tb(sh, "Upper", Vector3(aw, 0.7 * al, aw), Vector3(0, -0.3 * al, 0), sleeve_k, sleeve_c)
		var el := _part(sh, "Elbow", Vector3(0, -0.66 * al, 0))
		_tb(el, "Fore", Vector3(aw * 0.95, 0.56 * al, aw * 0.95), Vector3(0, -0.26 * al, 0), skin_k if look != "ranger" else "leather", skin if look != "ranger" else Color(0.3, 0.22, 0.14))
		var fist := _tb(el, "Fist", Vector3(aw * 0.95, 0.24, aw * 0.95), Vector3(0, -0.66 * al, 0), "bone" if look == "skeleton" else skin_k, skin)
		rig["sh_r" if right else "sh_l"] = sh
		rig["el_r" if right else "el_l"] = el
		rig["fist_r" if right else "fist_l"] = fist
		if str(spec.weapon) == "claws":
			for i in 3:
				_tb(fist, "Claw", Vector3(0.05, 0.22, 0.05), Vector3((i - 1) * 0.11, -0.2, 0.1), "bone", Color(0.82, 0.78, 0.68), Vector3(0.5, 0, 0))
	_build_weapon_slim(rig.fist_r)
	# ноги
	if bool(spec.get("float", false)):
		return
	var lw := 0.46 * (1.2 if bulky else (0.6 if look == "skeleton" else 1.0))
	for sd in [-1.0, 1.0]:
		var hip := _part(_root, "HipR" if sd < 0 else "HipL", Vector3(sd * 0.25 * tw, leg_h, 0))
		var pants_k: String = "bone" if look == "skeleton" else ("scale" if look == "frog" else "cloth")
		_tb(hip, "Leg", Vector3(lw, leg_h - 0.32, lw), Vector3(0, -(leg_h - 0.32) * 0.5, 0), pants_k, skin if look in ["skeleton", "frog"] else suit2)
		var boot_c: Color = Color(0.2, 0.15, 0.11) if look in ["ranger", "human", "thief", "brute"] else (skin.darkened(0.1) if look in ["frog", "skeleton", "imp", "demon"] else suit2.darkened(0.35))
		var boot_sz := Vector3(lw + 0.06, 0.34, lw + 0.12) if look != "frog" else Vector3(0.62, 0.18, 0.95)
		_tb(hip, "Boot", boot_sz, Vector3(0, -(leg_h - 0.17), 0.06 if look != "frog" else 0.22), "leather" if look in ["ranger", "human", "thief", "brute", "zombie"] else skin_k, boot_c)
		rig["hip_r" if sd < 0 else "hip_l"] = hip


func _build_weapon_slim(fist: Node3D) -> void:
	var w := str(spec.weapon)
	var hold := _part(fist, "Hold", Vector3(0, -0.08, 0.12))
	match w:
		"club":
			var c := _tb(hold, "Club", Vector3(0.16, 0.16, 1.3), Vector3(0, 0, 0.55), "wood", Color(0.38, 0.27, 0.17))
			_tb(c, "Head", Vector3(0.3, 0.3, 0.45), Vector3(0, 0, 0.55), "wood", Color(0.33, 0.24, 0.15))
			if bool(spec.get("plate", false)):
				_tb(c, "Spikes", Vector3(0.36, 0.08, 0.3), Vector3(0, 0, 0.55), "metal", Color(0.5, 0.5, 0.52))
		"dagger":
			_tb(hold, "Hilt", Vector3(0.08, 0.08, 0.26), Vector3(0, 0, 0.1), "leather", Color(0.25, 0.17, 0.1))
			_tb(hold, "Guard", Vector3(0.24, 0.06, 0.06), Vector3(0, 0, 0.24), "metal", Color(0.45, 0.42, 0.38))
			_tb(hold, "Blade", Vector3(0.05, 0.12, 0.55), Vector3(0, 0, 0.52), "metal", Color(0.7, 0.72, 0.74))
		"dynamite":
			_tb(hold, "Dynamite", Vector3(0.2, 0.55, 0.2), Vector3(0, 0.25, 0.02), "cloth", Color(0.62, 0.18, 0.14))
			_tb(hold, "Band", Vector3(0.23, 0.08, 0.23), Vector3(0, 0.25, 0.02), "cloth", Color(0.8, 0.76, 0.6))
			_tb(hold, "Fuse", Vector3(0.03, 0.2, 0.03), Vector3(0, 0.62, 0.02), "cloth", Color(0.25, 0.2, 0.15))
			rig["spark"] = _ball(hold, "Spark", 0.06, Vector3(0, 0.74, 0.02), Color(1, 0.75, 0.2), Vector3.ONE, 4.0)
		"bow":
			var bow := MeshInstance3D.new(); bow.name = "Bow"
			bow.mesh = BlockTex.bow_mesh(false); bow.material_override = BlockTex.material()
			bow.scale = Vector3.ONE * 1.7
			bow.rotation = Vector3(0, PI * 0.5, 0)
			bow.position = Vector3(0, 0.05, 0.1)
			hold.add_child(bow)
		"held":
			_held = hold
	rig["hold"] = hold


func _build_lizard(body: Node3D, suit: Color, suit2: Color, skin: Color, eye: Color, eye_e: float) -> void:
	## Ящерка — на четырёх лапах: передние лапы — «руки» (атака укусом/когтями), задние — «ноги».
	var lean := _part(body, "Lean", Vector3(0, 1.3, 0))
	rig["lean"] = lean
	spec["lean"] = 0.0
	_tb(lean, "Torso", Vector3(1.3, 0.9, 2.6), Vector3(0, 0.35, 0), "scale", suit)
	_tb(lean, "Belly", Vector3(1.1, 0.12, 2.3), Vector3(0, -0.12, 0.05), "scale", suit2)
	var head := _part(lean, "Head", Vector3(0, 0.55, 1.35))
	rig["head"] = head
	_tb(head, "Face", Vector3(1.0, 0.75, 1.2), Vector3(0, 0.1, 0.5), "scale", skin)
	_tb(head, "Jaw", Vector3(0.9, 0.2, 1.0), Vector3(0, -0.35, 0.55), "scale", suit2)
	for sd in [-1.0, 1.0]:
		_tb(head, "Eye", Vector3(0.06, 0.2, 0.2), Vector3(sd * 0.51, 0.3, 0.75), "skin", eye, Vector3.ZERO, eye_e)
	var tail := _tb(lean, "Tail", Vector3(0.6, 0.45, 1.6), Vector3(0, 0.2, -2.0), "scale", suit, Vector3(0.12, 0, 0))
	_tb(tail, "TailTip", Vector3(0.34, 0.26, 1.2), Vector3(0, -0.05, -1.3), "scale", suit, Vector3(0.1, 0, 0))
	for sd in [1.0, -1.0]:
		var right: bool = sd > 0.0
		var sh := _part(lean, "ShoulderR" if right else "ShoulderL", Vector3(-sd * 0.8, 0.2, 0.9))
		_tb(sh, "Upper", Vector3(0.36, 0.7, 0.36), Vector3(0, -0.3, 0), "scale", skin)
		var el := _part(sh, "Elbow", Vector3(0, -0.6, 0))
		var fist := _tb(el, "Fist", Vector3(0.42, 0.18, 0.55), Vector3(0, -0.28, 0.12), "scale", skin)
		for i in 3:
			_tb(fist, "Claw", Vector3(0.05, 0.05, 0.2), Vector3((i - 1) * 0.13, -0.05, 0.35), "bone", Color(0.8, 0.76, 0.66))
		rig["sh_r" if right else "sh_l"] = sh
		rig["el_r" if right else "el_l"] = el
		rig["fist_r" if right else "fist_l"] = fist
		var hip := _part(_root, "HipR" if sd < 0 else "HipL", Vector3(sd * 0.8, 1.4, -0.9))
		_tb(hip, "Leg", Vector3(0.42, 1.0, 0.42), Vector3(0, -0.5, 0), "scale", skin)
		_tb(hip, "Boot", Vector3(0.48, 0.18, 0.65), Vector3(0, -1.2, 0.12), "scale", skin.darkened(0.15))
		rig["hip_r" if sd < 0 else "hip_l"] = hip
	rig["hold"] = rig.fist_r


const ARMOR_KIND := {"wood": "wood", "stone": "metal", "metal": "metal", "scale": "scale"}
const ARMOR_SLIM_COLORS := {"wood": Color(0.5, 0.36, 0.22), "stone": Color(0.5, 0.5, 0.5), "metal": Color(0.68, 0.7, 0.74), "scale": Color(0.3, 0.46, 0.34)}


func _armor_slim(ids: Array) -> void:
	for key in ["head", "lean", "hip_r", "hip_l", "sh_r", "sh_l"]:
		var host: Node3D = rig.get(key)
		if host == null: continue
		for c in host.get_children():
			if str(c.name).begins_with("Armor"): c.queue_free()
	for raw in ids:
		var id := str(raw)
		if id == "": continue
		var mt := id.get_slice("_", 0)
		var col: Color = ARMOR_SLIM_COLORS.get(mt, Color(0.6, 0.6, 0.6))
		var kd: String = ARMOR_KIND.get(mt, "metal")
		if id.ends_with("_helmet"):
			_tb(rig.head, "ArmorHelmet", Vector3(0.9, 0.42, 0.9), Vector3(0, 0.66, 0), kd, col)
			_tb(rig.head, "ArmorBrim", Vector3(0.94, 0.08, 0.94), Vector3(0, 0.45, 0), kd, col.darkened(0.2))
		elif id.ends_with("_chest"):
			_tb(rig.lean, "ArmorChest", Vector3(1.1, 1.0, 0.66), Vector3(0, 0.78, 0), kd, col)
			for k in ["sh_r", "sh_l"]:
				_tb(rig[k], "ArmorPad", Vector3(0.5, 0.3, 0.5), Vector3(0, -0.05, 0), kd, col.darkened(0.1))
		elif id.ends_with("_legs") and rig.has("hip_r"):
			for k in ["hip_r", "hip_l"]:
				_tb(rig[k], "ArmorLeg", Vector3(0.54, 0.95, 0.54), Vector3(0, -0.5, 0), kd, col)
		elif id.ends_with("_boots") and rig.has("hip_r"):
			for k in ["hip_r", "hip_l"]:
				_tb(rig[k], "ArmorBoot", Vector3(0.56, 0.4, 0.66), Vector3(0, -1.55, 0.06), kd, col.darkened(0.1))
