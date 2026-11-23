extends Node3D
## v0.25 (t143u): единый «толстый» процедурный стиль мобов в духе Антона t2x2 — пузо, голова в плечах,
## толстые руки и ноги, оружие в правой руке. Узел называется «Model» и заменяет старые модели:
## enemy_visuals.play_state() зовёт play_state() здесь. Ходьба определяется сама по сдвигу родителя.
## Тот же пресет строит прокси моба у клиента в сетевой игре (net_proxy) — по ключу preset.

const H0 := 3.9   # рост «эталонной» фигуры, потом масштаб под spec.h
const BlockTex := preload("res://scripts/block_tex.gd")

const PRESETS := {
	"seam": {"h": 1.7, "suit": Color(0.55, 0.22, 0.48), "suit2": Color(0.32, 0.1, 0.3), "skin": Color(0.75, 0.4, 0.62), "head": "horns", "weapon": "claws", "eye": Color(1, 0.3, 0.6)},
	"seam_elite": {"h": 2.0, "suit": Color(0.38, 0.08, 0.2), "suit2": Color(0.2, 0.04, 0.1), "skin": Color(0.6, 0.18, 0.3), "head": "horns", "weapon": "club", "eye": Color(1, 0.15, 0.3), "belly": 1.15},
	"ghost0": {"h": 1.65, "suit": Color(0.86, 0.9, 1.0), "suit2": Color(0.6, 0.68, 0.9), "skin": Color(0.92, 0.95, 1.0), "head": "ghost", "weapon": "none", "float": true, "eye": Color(0.2, 0.4, 1.0)},
	"ghost1": {"h": 1.65, "suit": Color(1.0, 0.55, 0.78), "suit2": Color(0.85, 0.3, 0.55), "skin": Color(1.0, 0.7, 0.85), "head": "cap", "weapon": "claws", "eye": Color(1, 0.2, 0.5), "belly": 1.2},
	"ghost2": {"h": 1.65, "suit": Color(0.3, 0.45, 0.95), "suit2": Color(0.15, 0.22, 0.6), "skin": Color(0.45, 0.6, 1.0), "head": "horns", "weapon": "club", "eye": Color(1, 0.9, 0.2)},
	"ghost3": {"h": 1.65, "suit": Color(0.9, 0.86, 0.76), "suit2": Color(0.3, 0.28, 0.26), "skin": Color(0.95, 0.93, 0.86), "head": "skull", "weapon": "dagger", "float": true, "eye": Color(1, 0.4, 0.1)},
	"jumper": {"h": 1.65, "suit": Color(0.45, 0.65, 0.3), "suit2": Color(0.3, 0.45, 0.2), "skin": Color(0.6, 0.8, 0.45), "head": "frog", "weapon": "none", "eye": Color(1, 0.5, 0.15), "belly": 1.25, "legs_k": 1.3},
	"archer": {"h": 1.7, "suit": Color(0.5, 0.52, 0.66), "suit2": Color(0.3, 0.3, 0.42), "skin": Color(0.82, 0.8, 0.92), "head": "hood", "weapon": "bow", "eye": Color(1, 0.4, 0.15), "belly": 0.9},
	"thief": {"h": 1.15, "suit": Color(0.42, 0.34, 0.5), "suit2": Color(0.25, 0.2, 0.3), "skin": Color(0.62, 0.52, 0.68), "head": "mask", "weapon": "dagger", "eye": Color(1, 0.85, 0.3), "belly": 0.9, "sack": true},
	"clown": {"h": 1.35, "suit": Color(1.0, 0.82, 0.2), "suit2": Color(0.95, 0.25, 0.35), "skin": Color(0.93, 0.74, 0.6), "head": "clown", "weapon": "dynamite", "eye": Color(0.05, 0.05, 0.08), "belly": 1.2},
	"clown_shard": {"h": 1.05, "suit": Color(0.75, 0.35, 1.0), "suit2": Color(0.5, 0.2, 0.8), "skin": Color(0.93, 0.74, 0.6), "head": "clown", "weapon": "none", "eye": Color(0.05, 0.05, 0.08), "belly": 1.2},
	"clown_friend": {"h": 1.35, "suit": Color(0.35, 0.9, 0.45), "suit2": Color(0.2, 0.6, 0.3), "skin": Color(0.93, 0.74, 0.6), "head": "clown", "weapon": "none", "eye": Color(0.05, 0.05, 0.08), "belly": 1.2},
	"lizard": {"h": 0.7, "suit": Color(0.35, 0.58, 0.32), "suit2": Color(0.8, 0.88, 0.7), "skin": Color(0.42, 0.66, 0.38), "head": "lizard", "weapon": "claws", "eye": Color(1, 0.6, 0.15), "belly": 1.1, "tail": true},
	"anton": {"h": 3.85, "suit": Color(1.0, 0.82, 0.2), "suit2": Color(0.95, 0.25, 0.35), "skin": Color(0.93, 0.74, 0.6), "head": "clown", "weapon": "none", "eye": Color(0.05, 0.05, 0.08), "arm_r": 1.4},
	"player": {"h": 1.8, "suit": Color(0.3, 0.5, 0.85), "suit2": Color(0.25, 0.3, 0.45), "skin": Color(0.93, 0.76, 0.62), "head": "hair", "weapon": "held", "eye": Color(0.08, 0.08, 0.1), "belly": 0.82},
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
	var bk := float(spec.get("bk", 1.0))
	(rig.belly as Node3D).scale = Vector3(1.2 * bk * (2.0 - breathe), breathe, 1.08 * bk)
	var g := {"bx": 0.15, "bz": 0.0, "by": 0.0, "rx": 0.08 * sin(t * 1.3), "rz": -0.2, "lx": -0.08 * sin(t * 1.3), "lz": 0.2, "er": -0.35, "el": -0.35, "hr": 0.0, "hl": 0.0, "brx": 0.0}
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
			if weapon != "bow":
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
	body.rotation.x = lerpf(body.rotation.x, g.bx, a)
	body.rotation.z = lerpf(body.rotation.z, g.bz, a)
	body.position.y = lerpf(body.position.y, g.by, a)
	shr.rotation.x = lerpf(shr.rotation.x, g.rx, a); shr.rotation.z = lerpf(shr.rotation.z, g.rz, a)
	shl.rotation.x = lerpf(shl.rotation.x, g.lx, a); shl.rotation.z = lerpf(shl.rotation.z, g.lz, a)
	elr.rotation.x = lerpf(elr.rotation.x, g.er, a); ell.rotation.x = lerpf(ell.rotation.x, g.el, a)
	if rig.has("hip_r"):
		(rig.hip_r as Node3D).rotation.x = lerpf((rig.hip_r as Node3D).rotation.x, g.hr, a)
		(rig.hip_l as Node3D).rotation.x = lerpf((rig.hip_l as Node3D).rotation.x, g.hl, a)
