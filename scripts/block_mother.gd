extends CharacterBody3D
## «Мать блоков» v0.11.1 (BOSS REDESIGN). Дизайн-док: docs/boss_mother_of_blocks.md, docs/boss_redesign_v0.11.md.
## Броня: 3 пластины по 6 прочности. Кирка снимает 2, Кирка2 — 6; мечи броню не берут (отскок, 0 урона).
## Цикл: SPAWN → IDLE ⇄ WINDUP → AIR → (LAND) → PLATE_OPEN (одна пластина светится 3.5 с) →
##   пластина разбита → CORE (оранжевое ядро открыто, Мать оглушена, меч ×1.25, 3 с) → IDLE
##   не успел → пластина снова закрывается → IDLE.   Все пластины разбиты → после слэма STAGGER (меч ×1).
## Фаза II (66%): ударная волна + носильщики (до 2) несут осколки — доставка чинит пластину, убийство отменяет.
## Фаза III (33%): кирпичный дождь 4–6 блоков с тенями, интервалами и временным укрытием → долгое CORE_LONG (5 с).
##   В фазе III броня не восстанавливается. Пересборка (антикемп) — с видимой зоной и 1.6 с, чтобы выйти.
## Скрытого лечения деревьями больше нет.
const _Vis := preload("res://scripts/enemy_visuals.gd")
const _Nav := preload("res://scripts/enemy_navigation.gd")
const BlockTex := preload("res://scripts/block_tex.gd")
const Sfx := preload("res://scripts/sfx.gd")
var healed_from_blocks: int = 0   # v0.11.1: лечение деревьями удалено, всегда 0 (поле для старых отчётов)

enum S { SPAWN, IDLE, WINDUP, AIR, STAGGER, TRANSITION, SCATTER, MARKER, RAIN_WINDUP, RAIN, DEAD, LEAVING, PLATE_OPEN, CORE, CORE_LONG }
const STATE_NAMES := ["SPAWN", "IDLE", "WINDUP", "AIR", "STAGGER", "TRANSITION", "SCATTER", "MARKER", "RAIN_WINDUP", "RAIN", "DEAD", "LEAVING", "PLATE_OPEN", "CORE", "CORE_LONG"]

# --- числовая база (см. дизайн-док, раздел 3) ---
const MAX_HP := 620          # v0.11.1: фиксировано, без масштабирования от Меча3
const P2_AT := 409           # 66%
const P3_AT := 205           # 33%
# --- броня (v0.11.1)
const PLATE_COUNT := 3
const PLATE_DURABILITY := 6
const PICK_PLATE_DAMAGE := {"pickaxe": 2, "pickaxe2": 6}
const PLATE_OPEN_TIME := 3.5         # пластина светится и ждёт кирку
const CORE_TIME := 2.6               # оглушение + усиленное окно меча
const CORE_LONG_TIME := 4.5          # фаза III: долгое открытие ядра после кирпичного дождя
const CORE_MULT := 1.25
const NAKED_MULT := 1.0              # все пластины разбиты: меч бьёт в окна STAGGER ×1
const CARRIER_MAX := 2
const CARRIER_CD := 9.0
const COVER_TIME := 4.2              # укрытие из блоков живёт дольше дождя
const COVER_HALF := 1.1
const MODEL_PATH := "res://assets/models/greenblob.glb"
const MODEL_HEIGHT := 3.0
const HIT_RADIUS := 1.3
const BODY_HEIGHT := 2.6
const SPAWN_TIME := 1.6
const WINDUP := [0.6, 0.5, 0.45]        # по фазам (телеграф прыжка ≥0.45 с + тень весь полёт)
const STAGGER := [1.2, 1.0, 0.8]        # окно уязвимости после приземления
const JUMP_Y := [7.0, 7.4, 7.8]         # вертикальная скорость: полёт ≈1.43 / 1.51 / 1.59 с
const JUMP_H_MAX := 8.5                 # макс. горизонтальная скорость прыжка, м/с
const SLAM_RADIUS := 3.0
const SLAM_DAMAGE := 30
const CONTACT_DAMAGE := 5
const CONTACT_CD := 1.0
const WAVE_DAMAGE := 12
const WAVE_SPEED := 7.0
const WAVE_START := 3.0
const WAVE_END := 10.0
const WAVE_HEIGHT := 0.55
const TP_RANGE := 14.0                  # дальше — пересборка рядом с игроком
const TP_HEIGHT := 2.5
const TP_CD := [12.0, 9.0, 9.0]
const SCATTER_TIME := 0.8
const MARKER_TIME := 1.6             # v0.11.1: зона пересборки видна 1.6 с — успеть выйти
const REASSEMBLE_RADIUS := 2.6
const REASSEMBLE_DAMAGE := 25
const REASSEMBLE_STAGGER := 1.5
const TRANSITION_TIME := 1.6
const TRANSITION_WINDOW := 2.0
const ROAR_PUSH_RADIUS := 4.0
const RAIN_CD := 9.0
const RAIN_WINDUP := 0.6
const RAIN_BRICKS_MIN := 4
const RAIN_BRICKS_MAX := 6
const RAIN_INTERVAL := 0.45             # между кирпичами — безопасные интервалы
const RAIN_SPREAD := 2.7                # максимум 6 × 0.45
const BRICK_SHADOW := 1.0               # тень-телеграф каждого кирпича
const BRICK_DAMAGE := 12
const BRICK_RADIUS := 0.9
const RAIN_STAGGER := 1.2
const VULN_MULT := 1.5
const MINION_SPAWN := [1, 2, 2]           # v0.11.1: меньше — во II фазе есть носильщики
const MINION_CAP := [2, 3, 4]
const MINION_HARD_CAP := 4
const MINION_CHANCE := 0.3
const MINION_PITY := 3                  # 3 приземления без детей → гарантированно
const MINION_LOCKOUT := 2               # после спавна 2 приземления без спавна
const LEASH_DIST := 40.0
const LEASH_TIME := 6.0
const REWARD_R3 := 3
const REWARD_R2 := 2

var plates: Array = []          # [{dur, broken, node, spot}]
var open_plate := -1
var plate_log := {"opened": 0, "broken": 0, "closed": 0, "restored": 0, "carriers": 0, "carriers_killed": 0, "bounces": 0, "cover": 0, "reassemble_telegraph": 0}
var damage_by_weapon := {}
var _carrier_cd := 2.0
var _covers: Array = []
var hp: int = MAX_HP
var max_hp: int = MAX_HP
var hit_radius: float = HIT_RADIUS
var phase: int = 1
var state: int = S.SPAWN
var frozen: bool = false
var attack_log: Dictionary = {"slam": 0, "slam_hit": 0, "shockwave": 0, "wave_hit": 0, "teleport": 0, "reassemble_hit": 0,
	"brick_rain": 0, "brick": 0, "brick_hit": 0, "minion_spawn": 0, "minions": 0, "transition": 0, "contact": 0}
var state_log: Array = []
var damage_dealt: int = 0

var _t: float = 0.0
var _stagger_len: float = 1.0
var _contact_cd: float = 0.0
var _tp_cd: float = 6.0
var _rain_cd: float = 3.0
var _landings_since_spawn: int = 0
var _lockout: int = 0
var _pending_transition: int = 0
var _leash_t: float = 0.0
var _air_t: float = 0.0
var _target: Vector3 = Vector3.ZERO
var _marker_pos: Vector3 = Vector3.ZERO
var _no_progress: int = 0
var _last_dist: float = 999.0
var _bricks: Array = [] # [{node, shadow, pos, t, hit}]
var _waves: Array = []  # [{node, r, center, hit}]
var _shadow: MeshInstance3D = null
var _marker: Node3D = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()


static func try_spawn_from_mine(host: Node3D, cell: Vector3i) -> Node:
	## Совместимость: решение о спавне теперь в GameState.on_block_mined() (бросок на следующий блок).
	if host == null or host.get_tree() == null:
		return null
	if GameState != null and bool(GameState.get("boss_alive")):
		return null
	if not GameState.on_block_mined():
		return null
	return spawn_near(host, cell)


const ARENA_CLEAR_RADIUS := 11.0


static func spawn_near(host: Node3D, cell: Vector3i) -> Node:
	if host == null or host.get_tree() == null:
		return null
	if host.get_tree().get_nodes_in_group("block_mother").size() > 0:
		return null
	for an in host.get_tree().get_nodes_in_group("anaconda"):
		if is_instance_valid(an) and an.has_method("is_fight_active") and an.is_fight_active():
			return null  # v0.11.1: никогда два босса одновременно
	var pos := Vector3(float(cell.x) + 4.5, 0.15, float(cell.z) + 2.0)
	for cm in host.get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("walk_height_at") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			pos.y = float(cm.call("walk_height_at", int(pos.x), int(pos.z))) + 0.15
			break
	for cm2 in host.get_tree().get_nodes_in_group("chunk_manager"):
		if cm2.has_method("absorb_trees_near") and not bool(cm2.get("is_dream_layer")):
			var eaten := int(cm2.call("absorb_trees_near", pos, ARENA_CLEAR_RADIUS))
			if eaten > 0:
				GameState.chat("Мать блоков втягивает в себя деревья вокруг (%d) — арена расчищена." % eaten)
	var script: GDScript = load("res://scripts/block_mother.gd")
	var boss: CharacterBody3D = script.new()
	boss.position = pos
	host.add_child(boss)
	return boss


func set_seed(v: int) -> void:
	_rng.seed = v
	set_meta("seeded", true)


func _ready() -> void:
	if not has_meta("seeded"):
		_rng.randomize()
	add_to_group("block_mother")
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 16
	collision_mask = 1 | 4
	_Vis.attach_model(self, MODEL_PATH, MODEL_HEIGHT)
	_Vis.attach_hp_bar(self, MODEL_HEIGHT + 0.4)
	var hpbar := get_node_or_null("HPBar") as Node3D
	if hpbar:
		hpbar.scale = Vector3(2.2, 2.2, 2.2)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = HIT_RADIUS
	shape.height = BODY_HEIGHT
	col.shape = shape
	col.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	add_child(col)
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(true)
	if GameState.has_signal("world_changed"):
		GameState.world_changed.connect(_on_world)
	_on_world(GameState.is_dream())
	hp = MAX_HP
	max_hp = MAX_HP
	_build_plates()
	_Vis.update_hp_bar(self, hp, max_hp)
	_enter(S.SPAWN)
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.set_meta("base_scale", model.scale)
		model.scale *= 0.2
		var tw := create_tween()
		tw.tween_property(model, "scale", model.scale * 5.0, SPAWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	GameState.chat("Мать блоков собирается из камня! Меч не берёт броню: после прыжка разбей светящуюся пластину КИРКОЙ, затем руби ядро.", Color(1.0, 0.45, 0.4))
	roar(true)


func _on_world(is_dream: bool) -> void:
	frozen = is_dream
	visible = not is_dream
	set_physics_process(not is_dream)


# ---------------------------------------------------------------- урон по боссу

func hit_center() -> Vector3:
	return global_position + Vector3(0, BODY_HEIGHT * 0.5, 0)


func is_vulnerable() -> bool:
	## Окна урона мечом: открытое ядро (CORE/CORE_LONG) или STAGGER без брони.
	if state == S.CORE or state == S.CORE_LONG:
		return true
	return state == S.STAGGER and _t < _stagger_len and intact_plates() == 0


func is_invulnerable() -> bool:
	return state in [S.SPAWN, S.TRANSITION, S.SCATTER, S.MARKER, S.DEAD, S.LEAVING]


func boss_hint() -> String:
	match state:
		S.PLATE_OPEN: return "   — ПЛАСТИНА ОТКРЫТА: бей КИРКОЙ!"
		S.CORE, S.CORE_LONG: return "   — ЯДРО ОТКРЫТО: меч ×1.25!"
		S.MARKER, S.SCATTER: return "   — пересборка: уйди из круга!"
	if is_vulnerable():
		return "   — УЯЗВИМА!"
	return "   — броня %d/%d" % [intact_plates(), PLATE_COUNT]


func intact_plates() -> int:
	var n := 0
	for p in plates:
		if not bool(p["broken"]):
			n += 1
	return n


func take_damage(amount: int) -> void:
	## Совместимость: старые вызовы (консоль, прочие системы) — как удар мечом.
	receive_weapon_hit(amount, "")


func receive_weapon_hit(amount: int, weapon_id: String = "") -> Dictionary:
	## v0.11.1: единая точка урона по Матери. Кирки бьют открытую пластину, мечи — только открытое ядро.
	var res := {"dealt": 0, "target": "none", "bounce": false, "plate": -1}
	if state == S.DEAD or state == S.LEAVING or is_invulnerable() or amount <= 0:
		return res
	if weapon_id in PICK_PLATE_DAMAGE:
		if state == S.PLATE_OPEN and open_plate >= 0:
			var pl: Dictionary = plates[open_plate]
			pl["dur"] = maxi(0, int(pl["dur"]) - int(PICK_PLATE_DAMAGE[weapon_id]))
			res.target = "plate"
			res.plate = open_plate
			res.dealt = int(PICK_PLATE_DAMAGE[weapon_id])
			_flash()
			if int(pl["dur"]) <= 0:
				_break_plate(open_plate)
			return res
		res.target = "armor"
		res.bounce = true
		_bounce_feedback(weapon_id)
		return res
	# мечи (и неизвестное оружие)
	var mult := 0.0
	if state == S.CORE or state == S.CORE_LONG:
		mult = CORE_MULT
	elif is_vulnerable():
		mult = NAKED_MULT
	if mult <= 0.0:
		res.target = "armor"
		res.bounce = true
		_bounce_feedback(weapon_id)
		return res
	res.dealt = _apply_core_damage(int(round(float(amount) * mult)), weapon_id)
	res.target = "core"
	return res


func _apply_core_damage(dmg: int, weapon_id: String) -> int:
	var floor_hp := 0
	if phase == 1:
		floor_hp = P2_AT
	elif phase == 2:
		floor_hp = P3_AT
	var before := hp
	hp = maxi(floor_hp, hp - dmg)
	var dealt := before - hp
	damage_dealt += dealt
	var key := weapon_id if weapon_id != "" else "sword"
	damage_by_weapon[key] = int(damage_by_weapon.get(key, 0)) + dealt
	_Vis.update_hp_bar(self, hp, max_hp)
	_flash()
	if phase == 1 and hp <= P2_AT:
		_pending_transition = 2
	elif phase == 2 and hp <= P3_AT:
		_pending_transition = 3
	if hp <= 0:
		_die()
		return dealt
	if _pending_transition > 0 and state in [S.IDLE, S.STAGGER, S.WINDUP, S.RAIN_WINDUP, S.CORE, S.CORE_LONG, S.PLATE_OPEN]:
		_start_transition()
	return dealt


func _bounce_feedback(weapon_id: String) -> void:
	plate_log["bounces"] += 1
	if plate_log["bounces"] == 1 or plate_log["bounces"] % 6 == 0:
		var what := "Кирка звенит о закрытую броню — жди светящуюся пластину." if weapon_id in PICK_PLATE_DAMAGE else "Меч отскакивает от брони! Разбей светящуюся пластину киркой — ядро откроется."
		GameState.set_hint(what, plate_log["bounces"] == 1)
	var model := get_node_or_null("Model") as Node3D
	if model:
		var base: Vector3 = model.get_meta("base_scale", model.scale)
		model.set_meta("base_scale", base)
		model.scale = base * Vector3(0.96, 1.04, 0.96)
		var tw := create_tween()
		tw.tween_property(model, "scale", base, 0.1)
	var pl := _player()
	if pl:
		var away := pl.global_position - global_position
		away.y = 0.0
		if away.length() > 0.05:
			pl.velocity += away.normalized() * 2.5   # отдача: оружие отскакивает


func heal_from_blocks(_blocks: int) -> int:
	## v0.11.1: скрытое лечение деревьями удалено (см. BOSS REDESIGN §5).
	return 0


# ---------------------------------------------------------------- броня: пластины и ядро

const PLATE_ANGLES := [0.0, 2.094, 4.189]

func _build_plates() -> void:
	plates.clear()
	for i in range(PLATE_COUNT):
		var ang: float = PLATE_ANGLES[i]
		var dir := Vector3(sin(ang), 0, cos(ang))
		var holder := Node3D.new()
		holder.name = "Plate%d" % i
		holder.position = dir * (HIT_RADIUS * 0.92) + Vector3(0, 1.35, 0)
		holder.rotation.y = ang
		add_child(holder)
		var mi := MeshInstance3D.new()
		mi.name = "Armor"
		mi.mesh = BlockTex.cube_mesh("deep_stone", Vector3(1.05, 1.15, 0.26))
		holder.add_child(mi)
		var rim := MeshInstance3D.new()
		rim.name = "Glow"
		var rm := BoxMesh.new()
		rm.size = Vector3(1.17, 1.27, 0.2)
		rim.mesh = rm
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.0, 0.85, 0.25)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.75, 0.2)
		gm.emission_energy_multiplier = 2.5
		rim.material_override = gm
		rim.visible = false
		holder.add_child(rim)
		var core := MeshInstance3D.new()
		core.name = "Core"
		var cm := BoxMesh.new()
		cm.size = Vector3(0.7, 0.8, 0.12)
		core.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color(1.0, 0.5, 0.1)
		cmat.emission_enabled = true
		cmat.emission = Color(1.0, 0.42, 0.08)
		cmat.emission_energy_multiplier = 3.0
		core.material_override = cmat
		core.position = Vector3(0, 0, -0.06)
		core.visible = false
		holder.add_child(core)
		plates.append({"dur": PLATE_DURABILITY, "broken": false, "node": holder})


func _plate_visual(i: int) -> void:
	if i < 0 or i >= plates.size():
		return
	var holder: Node3D = plates[i]["node"]
	if holder == null or not is_instance_valid(holder):
		return
	var broken := bool(plates[i]["broken"])
	(holder.get_node("Armor") as Node3D).visible = not broken
	(holder.get_node("Glow") as Node3D).visible = (i == open_plate and state == S.PLATE_OPEN)
	(holder.get_node("Core") as Node3D).visible = broken


func _refresh_plates() -> void:
	for i in range(plates.size()):
		_plate_visual(i)


func _open_plate() -> bool:
	## После слэма открывается одна целая пластина (та, что ближе к игроку — читаемо).
	var best := -1
	var bd := 1e9
	var pl := _player()
	for i in range(plates.size()):
		if bool(plates[i]["broken"]):
			continue
		var holder: Node3D = plates[i]["node"]
		var d := 0.0
		if pl and holder and is_instance_valid(holder) and holder.is_inside_tree():
			d = holder.global_position.distance_to(pl.global_position)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return false
	open_plate = best
	plate_log["opened"] += 1
	_enter(S.PLATE_OPEN)
	_refresh_plates()
	return true


func _break_plate(i: int) -> void:
	plates[i]["broken"] = true
	plates[i]["dur"] = 0
	plate_log["broken"] += 1
	open_plate = -1
	_debris(hit_center(), 10, 5.0)
	roar(false)
	GameState.set_hint("Пластина разбита — ядро открыто! Руби мечом (×1.25)!", false)
	_enter(S.CORE)
	_set_crack_glow(true)
	_refresh_plates()


func _close_plate() -> void:
	plate_log["closed"] += 1
	open_plate = -1
	_enter(S.IDLE)
	_refresh_plates()


func restore_plate() -> bool:
	if phase >= 3:
		return false   # в фазе III броня не восстанавливается
	for i in range(plates.size()):
		if bool(plates[i]["broken"]):
			plates[i]["broken"] = false
			plates[i]["dur"] = PLATE_DURABILITY
			plate_log["restored"] += 1
			_refresh_plates()
			GameState.chat("Носильщик донёс осколок — Мать блоков нарастила пластину!", Color(1.0, 0.6, 0.4))
			return true
	return false


func on_carrier_delivered(_c: Node) -> void:
	restore_plate()


func alive_carriers() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("mother_carrier"):
		if is_instance_valid(m) and int(m.get("hp")) > 0:
			n += 1
	return n


func _tick_carriers(delta: float) -> void:
	## Фаза II: пока есть разбитые пластины — до 2 носильщиков бегут за осколками.
	if phase != 2 or intact_plates() >= PLATE_COUNT:
		return
	_carrier_cd -= delta
	if _carrier_cd > 0.0 or alive_carriers() >= CARRIER_MAX:
		return
	_carrier_cd = CARRIER_CD
	var a := _rng.randf() * TAU
	var frag := global_position + Vector3(cos(a) * 7.0, 0, sin(a) * 7.0)
	frag.y = _ground_y_at(frag)
	var script: GDScript = load("res://scripts/blockling.gd")
	var c: CharacterBody3D = script.new()
	c.configure("carrier", self, frag)
	_world().add_child(c)
	c.global_position = global_position + Vector3(cos(a) * 2.0, 0.6, sin(a) * 2.0)
	plate_log["carriers"] += 1
	if plate_log["carriers"] == 1:
		GameState.chat("Носильщики бегут за осколками брони — убей их, пока не донесли!", Color(1.0, 0.7, 0.4))


func roar(loud: bool = true) -> void:
	Sfx.play3d(self, Sfx.MOTHER_ROAR if loud else Sfx.MOTHER_GROWL, 2.0 if loud else -2.0, 80.0, _rng.randf_range(0.92, 1.05))


func _flash() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	model.set_meta("base_scale", base)
	if state in [S.WINDUP, S.AIR, S.SPAWN]:
		return
	model.scale = base * Vector3(1.08, 0.92, 1.08)
	var tw := create_tween()
	tw.tween_property(model, "scale", base, 0.12)


# ---------------------------------------------------------------- машина состояний

func _enter(s: int) -> void:
	state = s
	_t = 0.0
	state_log.append([STATE_NAMES[s], phase, hp])
	if state_log.size() > 400:
		state_log.remove_at(0)


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player") as CharacterBody3D


func _physics_process(delta: float) -> void:
	if frozen or state == S.DEAD or state == S.LEAVING:
		return
	_t += delta
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_tp_cd = maxf(0.0, _tp_cd - delta)
	_rain_cd = maxf(0.0, _rain_cd - delta)
	var player := _player()
	_tick_bricks(delta, player)
	_tick_waves(delta, player)
	_tick_carriers(delta)
	_tick_covers(delta)
	if player == null:
		return
	var to_p := player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	# Поводок: игрок убежал далеко — Мать уходит без награды.
	if flat.length() > LEASH_DIST:
		_leash_t += delta
		if _leash_t > LEASH_TIME:
			leave("Мать блоков потеряла тебя из виду и ушла под землю.")
			return
	else:
		_leash_t = 0.0
	match state:
		S.SPAWN:
			_ground_move(delta)
			if _t >= SPAWN_TIME:
				_enter(S.IDLE)
		S.IDLE:
			_ground_move(delta)
			_face(flat, delta)
			_decide(player, flat)
		S.WINDUP:
			_ground_move(delta)
			_face(flat, delta)
			if _t >= float(WINDUP[phase - 1]):
				_jump(player)
		S.AIR:
			_air_t += delta
			velocity.y -= _gravity * delta
			if has_meta("speed_override"):
				var override_flat := Vector3(velocity.x,0,velocity.z).normalized()*float(get_meta("speed_override"))
				velocity.x = override_flat.x
				velocity.z = override_flat.z
			move_and_slide()
			_update_shadow()
			if is_on_floor() and _air_t > 0.15:
				_land(player)
			elif _air_t > 4.0:
				_land(player)
		S.STAGGER:
			_ground_move(delta)
			if _t >= _stagger_len:
				_enter(S.IDLE)
		S.PLATE_OPEN:
			_ground_move(delta)
			if _pending_transition > 0:
				open_plate = -1
				_start_transition()
			elif _t >= PLATE_OPEN_TIME:
				_close_plate()
		S.CORE:
			_ground_move(delta)
			if _t >= CORE_TIME:
				_set_crack_glow(false)
				_enter(S.IDLE)
				_refresh_plates()
		S.CORE_LONG:
			_ground_move(delta)
			if _t >= CORE_LONG_TIME:
				_set_crack_glow(false)
				_enter(S.IDLE)
		S.TRANSITION:
			_ground_move(delta)
			if _t >= TRANSITION_TIME:
				_stagger_len = TRANSITION_WINDOW
				_set_crack_glow(true)
				_enter(S.STAGGER)
				_Vis.play_state(self, "idle", true)
		S.SCATTER:
			if _t >= SCATTER_TIME:
				_show_marker(player)
				_enter(S.MARKER)
		S.MARKER:
			if _t >= MARKER_TIME:
				_reassemble(player)
		S.RAIN_WINDUP:
			_ground_move(delta)
			if _t >= RAIN_WINDUP:
				_start_rain(player)
				_enter(S.RAIN)
		S.RAIN:
			_ground_move(delta)
			if _t >= _rain_len + BRICK_SHADOW:
				# После дождя — долгое открытие ядра (меч ×1.25), броня в фазе III не чинится.
				_set_crack_glow(true)
				_enter(S.CORE_LONG)
				GameState.set_hint("Ядро открыто надолго — руби!", false)
	# Касание: только когда она стоит (не в полёте и не рассыпана).
	if state in [S.IDLE, S.WINDUP, S.STAGGER, S.RAIN, S.RAIN_WINDUP, S.PLATE_OPEN] and _contact_cd <= 0.0:
		if flat.length() <= HIT_RADIUS + 0.55 and absf(to_p.y) < BODY_HEIGHT:
			_hurt(player, CONTACT_DAMAGE, "касание", 7.0)
			attack_log["contact"] += 1
			_contact_cd = CONTACT_CD
	if state not in [S.STAGGER, S.CORE, S.CORE_LONG]:
		_set_crack_glow(false)


func _ground_move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	move_and_slide()


func _face(flat: Vector3, delta: float) -> void:
	if flat.length() > 0.1:
		_Nav.face_dir(self, flat, delta, 6.0)


func _decide(player: CharacterBody3D, flat: Vector3) -> void:
	## Приоритеты мувмент-ИИ (док, раздел 6):
	## 1) отложенный переход фазы; 2) пересборка рядом с игроком, если далеко/высоко/застряла;
	## 3) фаза 3: кирпичный дождь по КД; 4) иначе — прыжок-слэм.
	if _pending_transition > 0:
		_start_transition()
		return
	var dy := player.global_position.y - global_position.y
	var far := flat.length() > TP_RANGE or absf(dy) > TP_HEIGHT or _no_progress >= 3
	if far and _tp_cd <= 0.0:
		_start_scatter()
		return
	if phase >= 3 and _rain_cd <= 0.0 and flat.length() < TP_RANGE:
		_rain_cd = RAIN_CD
		_enter(S.RAIN_WINDUP)
		roar(true)
		_Vis.play_state(self, "attack", true)
		_squash(Vector3(1.0, 1.25, 1.0), RAIN_WINDUP)
		return
	_enter(S.WINDUP)
	_Vis.play_state(self, "idle", true)
	_squash(Vector3(1.22, 0.7, 1.22), float(WINDUP[phase - 1]))


func _squash(k: Vector3, time: float) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	model.set_meta("base_scale", base)
	var tw := create_tween()
	tw.tween_property(model, "scale", base * k, time * 0.85).set_trans(Tween.TRANS_SINE)


func _unsquash(time: float = 0.15) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		return
	var base: Vector3 = model.get_meta("base_scale", model.scale)
	var tw := create_tween()
	tw.tween_property(model, "scale", base, time)


# ---------------------------------------------------------------- прыжок-слэм

func predicted_landing(player: CharacterBody3D) -> Vector3:
	var target := player.global_position
	if phase >= 3:
		var lead := Vector3(player.velocity.x, 0, player.velocity.z) * 0.3
		target += lead.limit_length(2.5)
	return target


func _jump(player: CharacterBody3D) -> void:
	_target = predicted_landing(player)
	var vy: float = JUMP_Y[phase - 1]
	var t_air := 2.0 * vy / _gravity
	var d := Vector3(_target.x - global_position.x, 0, _target.z - global_position.z)
	var vh := d / t_air
	vh = vh.limit_length(JUMP_H_MAX)
	velocity = Vector3(vh.x, vy, vh.z)
	_air_t = 0.0
	_last_dist = d.length()
	_enter(S.AIR)
	_unsquash(0.1)
	_squash(Vector3(0.85, 1.25, 0.85), 0.3)
	_Vis.play_state(self, "jump", true)
	_make_shadow()


func _make_shadow() -> void:
	_free_node(_shadow)
	_shadow = _disc(SLAM_RADIUS, Color(0.95, 0.12, 0.1, 0.38))
	_update_shadow()


func _update_shadow() -> void:
	if _shadow == null or not is_instance_valid(_shadow):
		return
	# Тень показывает точку приземления по баллистике (с учётом текущей скорости).
	var vy := velocity.y
	var y0 := global_position.y
	var ground := _ground_y_at(_target)
	var a := 0.5 * _gravity
	var b := -vy
	var c := ground - y0
	var disc := b * b - 4.0 * a * c
	var t_rem := 0.0
	if disc > 0.0:
		t_rem = maxf(0.0, (-b + sqrt(disc)) / (2.0 * a))
	var p := global_position + Vector3(velocity.x, 0, velocity.z) * t_rem
	_shadow.global_position = Vector3(p.x, ground + 0.04, p.z)
	var k := clampf(1.0 - t_rem / 1.5, 0.25, 1.0)
	var inner := _shadow.get_node_or_null("Inner") as Node3D
	if inner:
		inner.scale = Vector3(k, 1, k)


func _land(player: CharacterBody3D) -> void:
	velocity = Vector3.ZERO
	_free_node(_shadow)
	_shadow = null
	attack_log["slam"] += 1
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")):
			cm.call("absorb_trees_near", global_position, 4.5)   # прыжок сносит деревья (без лечения)
	_unsquash(0.06)
	_squash(Vector3(1.3, 0.72, 1.3), 0.08)
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_unsquash(0.25))
	_debris(global_position + Vector3(0, 0.3, 0), 8, 5.0)
	var to_p := player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	if flat.length() <= SLAM_RADIUS and to_p.y < 2.2 and to_p.y > -1.0:
		if _hurt(player, SLAM_DAMAGE, "слэм", 11.0) > 0:
			attack_log["slam_hit"] += 1
	if phase >= 2:
		_spawn_wave()
	# Прогресс сближения (для «застряла» → пересборка).
	if flat.length() > 6.0 and flat.length() >= _last_dist - 1.0:
		_no_progress += 1
	else:
		_no_progress = 0
	_maybe_spawn_minions()
	_Vis.play_state(self, "idle", true)
	if _pending_transition > 0:
		_start_transition()
		return
	# v0.11.1: после слэма — одна пластина светится (окно кирки); без брони — обычный STAGGER (меч ×1).
	if not _open_plate():
		_stagger_len = float(STAGGER[phase - 1])
		_set_crack_glow(true)
		_enter(S.STAGGER)


# ---------------------------------------------------------------- ударная волна (фаза 2+)

func _spawn_wave() -> void:
	attack_log["shockwave"] += 1
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = WAVE_HEIGHT
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 40
	cm.rings = 1
	ring.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.75)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world().add_child(ring)
	var center := global_position
	ring.global_position = center + Vector3(0, WAVE_HEIGHT * 0.5, 0)
	ring.scale = Vector3(WAVE_START, 1, WAVE_START)
	_waves.append({"node": ring, "r": WAVE_START, "center": center, "hit": false})


func _tick_waves(delta: float, player: CharacterBody3D) -> void:
	var i := 0
	while i < _waves.size():
		var w: Dictionary = _waves[i]
		var r: float = float(w["r"]) + WAVE_SPEED * delta
		w["r"] = r
		var node: MeshInstance3D = w["node"]
		if is_instance_valid(node):
			node.scale = Vector3(r, 1, r)
			var mat := node.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = 0.75 * clampf((WAVE_END - r) / 3.0, 0.0, 1.0)
		if player and not bool(w["hit"]):
			var c: Vector3 = w["center"]
			var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
			var above := player.global_position.y - c.y
			# Волна бьёт только стоящих на земле: перепрыгни кольцо (прыжок 1.5 м > 0.55 м).
			if absf(d - r) < 0.45 and above < WAVE_HEIGHT and player.is_on_floor():
				w["hit"] = true
				if _hurt(player, WAVE_DAMAGE, "ударная волна", 6.0) > 0:
					attack_log["wave_hit"] += 1
		if r >= WAVE_END:
			_free_node(node)
			_waves.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- пересборка (телепорт)

func _start_scatter() -> void:
	_tp_cd = float(TP_CD[phase - 1])
	_no_progress = 0
	attack_log["teleport"] += 1
	_enter(S.SCATTER)
	_debris(global_position + Vector3(0, 1.2, 0), 16, 6.5)
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.visible = false
	var bar := get_node_or_null("HPBar") as Node3D
	if bar:
		bar.visible = false
	collision_layer = 0


func _show_marker(player: CharacterBody3D) -> void:
	plate_log["reassemble_telegraph"] += 1
	GameState.set_hint("Мать пересобирается под тобой — уйди из оранжевого круга!", false)
	_marker_pos = player.global_position
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("absorb_trees_near") and not bool(cm.get("is_dream_layer")):
			cm.call("absorb_trees_near", _marker_pos, 5.0)
	_marker_pos.y = _ground_y_at(_marker_pos)
	_free_node(_marker)
	_marker = _disc(REASSEMBLE_RADIUS, Color(1.0, 0.55, 0.1, 0.42))
	_marker.global_position = _marker_pos + Vector3(0, 0.05, 0)
	var pillar := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.35
	pm.bottom_radius = 0.6
	pm.height = 7.0
	pillar.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.3)
	pillar.material_override = m
	pillar.position = Vector3(0, 3.5, 0)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(pillar)
	# Блоки слетаются к маркеру.
	for i in range(10):
		var a := float(i) / 10.0 * TAU
		var from := _marker_pos + Vector3(cos(a) * 6.0, 4.0 + _rng.randf() * 2.0, sin(a) * 6.0)
		var cube := _mini_block(from)
		var tw := cube.create_tween()
		tw.tween_property(cube, "global_position", _marker_pos + Vector3(0, 1.2, 0), MARKER_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(cube.queue_free)


func _reassemble(player: CharacterBody3D) -> void:
	_free_node(_marker)
	_marker = null
	global_position = _marker_pos + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	collision_layer = 16
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.visible = true
	var bar := get_node_or_null("HPBar") as Node3D
	if bar:
		bar.visible = true
	_debris(global_position + Vector3(0, 0.5, 0), 10, 4.0)
	var d := Vector2(player.global_position.x - _marker_pos.x, player.global_position.z - _marker_pos.z).length()
	if d <= REASSEMBLE_RADIUS and absf(player.global_position.y - _marker_pos.y) < 2.5:
		if _hurt(player, REASSEMBLE_DAMAGE, "пересборка", 10.0) > 0:
			attack_log["reassemble_hit"] += 1
	_stagger_len = REASSEMBLE_STAGGER
	_set_crack_glow(true)
	_enter(S.STAGGER)
	_Vis.play_state(self, "idle", true)
	_refresh_plates()


# ---------------------------------------------------------------- кирпичный дождь (фаза 3)

var _rain_len := RAIN_SPREAD


func rain_plan(center: Vector3, count: int) -> Array:
	## 4–6 кирпичей: первый — прицельно в игрока, остальные кольцом 2–6 м, не ближе 1.9 м друг к другу;
	## интервал 0.45 с. Возвращает [{pos, delay}].
	var out: Array = []
	for i in range(count):
		var p := center
		if i > 0:
			for attempt in range(12):
				var a := _rng.randf() * TAU
				var r := 2.0 + _rng.randf() * 4.0
				p = center + Vector3(cos(a) * r, 0, sin(a) * r)
				var ok := true
				for q in out:
					if Vector2(p.x - q.pos.x, p.z - q.pos.z).length() < 1.9:
						ok = false
				if ok:
					break
		out.append({"pos": p, "delay": float(i) * RAIN_INTERVAL})
	return out


func _start_rain(player: CharacterBody3D) -> void:
	attack_log["brick_rain"] += 1
	var center := player.global_position
	var count := _rng.randi_range(RAIN_BRICKS_MIN, RAIN_BRICKS_MAX)
	_rain_len = float(count - 1) * RAIN_INTERVAL
	_spawn_cover(center)
	for b in rain_plan(center, count):
		var p: Vector3 = b.pos
		p.y = _ground_y_at(p)
		var delay: float = b.delay
		if delay <= 0.0:
			_spawn_brick(p)
			continue
		get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if is_instance_valid(self) and state != S.DEAD:
				_spawn_brick(p))


func _spawn_cover(center: Vector3) -> void:
	## Временное укрытие: каменный навес из блоков в 3 м от игрока. Под ним кирпичи не бьют.
	var a := _rng.randf() * TAU
	var at := center + Vector3(cos(a) * 3.0, 0, sin(a) * 3.0)
	at.y = _ground_y_at(at)
	var body := StaticBody3D.new()
	body.name = "MotherCover"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COVER_HALF * 2.0, 0.3, COVER_HALF * 2.0)
	cs.shape = box
	cs.position = Vector3(0, 2.15, 0)
	body.add_child(cs)
	var roof := MeshInstance3D.new()
	roof.mesh = BlockTex.cube_mesh("ruin", Vector3(COVER_HALF * 2.0, 0.3, COVER_HALF * 2.0))
	roof.position = Vector3(0, 2.15, 0)
	body.add_child(roof)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			leg.mesh = BlockTex.cube_mesh("ruin", Vector3(0.22, 2.0, 0.22))
			leg.position = Vector3(sx * (COVER_HALF - 0.11), 1.0, sz * (COVER_HALF - 0.11))
			body.add_child(leg)
	_world().add_child(body)
	body.global_position = at
	_covers.append({"node": body, "pos": at, "t": COVER_TIME})
	plate_log["cover"] += 1
	GameState.set_hint("Кирпичный дождь! Прячься под каменный навес или уходи с красных теней.", false)


func under_cover(p: Vector3) -> bool:
	for c in _covers:
		var cp: Vector3 = c["pos"]
		if absf(p.x - cp.x) <= COVER_HALF and absf(p.z - cp.z) <= COVER_HALF and p.y < cp.y + 2.0:
			return true
	return false


func _tick_covers(delta: float) -> void:
	var keep: Array = []
	for c in _covers:
		c["t"] = float(c["t"]) - delta
		if float(c["t"]) <= 0.0:
			_free_node(c["node"])
		else:
			keep.append(c)
	_covers = keep


func _spawn_brick(p: Vector3) -> void:
	attack_log["brick"] += 1
	var shadow := _disc(BRICK_RADIUS, Color(0.6, 0.05, 0.05, 0.5))
	shadow.global_position = p + Vector3(0, 0.04, 0)
	var brick := MeshInstance3D.new()
	brick.mesh = BlockTex.cube_mesh("ruin", Vector3(0.9, 0.9, 0.9))
	_world().add_child(brick)
	brick.global_position = p + Vector3(0, 14.0, 0)
	_bricks.append({"node": brick, "shadow": shadow, "pos": p, "t": 0.0, "done": false})


func _tick_bricks(delta: float, player: CharacterBody3D) -> void:
	var i := 0
	while i < _bricks.size():
		var b: Dictionary = _bricks[i]
		b["t"] = float(b["t"]) + delta
		var t: float = b["t"]
		var node: Node3D = b["node"]
		var p: Vector3 = b["pos"]
		if not bool(b["done"]):
			var k := clampf(t / BRICK_SHADOW, 0.0, 1.0)
			if is_instance_valid(node):
				node.global_position = p + Vector3(0, 0.45 + 14.0 * (1.0 - k * k), 0)
			var sh: Node3D = b["shadow"]
			if is_instance_valid(sh):
				var inner := sh.get_node_or_null("Inner") as Node3D
				if inner:
					inner.scale = Vector3(maxf(k, 0.2), 1, maxf(k, 0.2))
			if t >= BRICK_SHADOW:
				b["done"] = true
				_free_node(b["shadow"])
				if player:
					var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
					var dy := player.global_position.y - p.y
					if d <= BRICK_RADIUS + 0.35 and dy < 2.0 and dy > -0.5 and not under_cover(player.global_position):
						if _hurt(player, BRICK_DAMAGE, "кирпич", 3.0) > 0:
							attack_log["brick_hit"] += 1
		elif t > BRICK_SHADOW + 1.6:
			_free_node(node)
			_bricks.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- выводок (блоклинги)

func alive_minions() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("blockling"):
		if is_instance_valid(m) and int(m.get("hp")) > 0:
			n += 1
	return n


func minion_roll(roll: float) -> bool:
	## RNG с защитой от серий: локаут 2 приземления после спавна; гарантия после 3 пустых.
	if _lockout > 0:
		_lockout -= 1
		_landings_since_spawn += 1
		return false
	_landings_since_spawn += 1
	if _landings_since_spawn >= MINION_PITY or roll < MINION_CHANCE:
		_landings_since_spawn = 0
		_lockout = MINION_LOCKOUT
		return true
	return false


func _maybe_spawn_minions() -> void:
	var cap: int = mini(MINION_HARD_CAP, int(MINION_CAP[phase - 1]))
	var room := cap - alive_minions()
	if room <= 0:
		return
	if not minion_roll(_rng.randf()):
		return
	var n := mini(room, int(MINION_SPAWN[phase - 1]))
	var script: GDScript = load("res://scripts/blockling.gd")
	for i in range(n):
		var a := _rng.randf() * TAU
		var m: CharacterBody3D = script.new()
		_world().add_child(m)
		m.global_position = global_position + Vector3(cos(a) * 2.2, 1.0, sin(a) * 2.2)
		m.velocity = Vector3(cos(a) * 3.0, 4.0, sin(a) * 3.0)
	attack_log["minion_spawn"] += 1
	attack_log["minions"] += n
	GameState.chat("Мать блоков рожает блоклингов (%d)." % n, Color(1.0, 0.75, 0.5))


# ---------------------------------------------------------------- переходы, смерть, уход

func _start_transition() -> void:
	var to := _pending_transition
	_pending_transition = 0
	if to <= phase:
		return
	phase = to
	open_plate = -1
	_refresh_plates()
	attack_log["transition"] += 1
	_enter(S.TRANSITION)
	velocity = Vector3.ZERO
	_free_node(_shadow)
	_shadow = null
	_Vis.play_state(self, "attack", true)
	_squash(Vector3(1.35, 0.6, 1.35), TRANSITION_TIME * 0.6)
	get_tree().create_timer(TRANSITION_TIME * 0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and state == S.TRANSITION:
			_unsquash(0.3)
			roar(true)
			_roar_push())
	var what := "Ударная волна и носильщики брони!" if phase == 2 else "Кирпичный дождь: тени, интервалы и навес-укрытие. Броня больше не чинится."
	GameState.chat("Мать блоков в ярости — фаза %d. %s" % [phase, what], Color(1.0, 0.5, 0.35))


func _roar_push() -> void:
	## Рёв: без урона, отталкивает игрока (контрплей — отойти заранее/принять толчок).
	var player := _player()
	_debris(global_position + Vector3(0, 1.0, 0), 12, 6.0)
	if player == null:
		return
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() < ROAR_PUSH_RADIUS:
		var dir := d.normalized() if d.length() > 0.05 else Vector3(1, 0, 0)
		player.velocity += dir * 9.0 + Vector3(0, 3.5, 0)


## v0.11.1: «пощада» — суммарный урон Матери за скользящие 3 с ограничен (комбо слэм+пересборка не ваншотит).
const MERCY_WINDOW := 3.0
const MERCY_CAP := 55
var _mercy: Array = []   # [[time_ms, dealt], ...]


func _mercy_room() -> int:
	var now := Time.get_ticks_msec() if not has_meta("sim_clock") else int(get_meta("sim_clock"))
	var keep: Array = []
	var used := 0
	for e in _mercy:
		if now - int(e[0]) <= int(MERCY_WINDOW * 1000.0):
			keep.append(e)
			used += int(e[1])
	_mercy = keep
	return maxi(0, MERCY_CAP - used)


func _hurt(player: CharacterBody3D, amount: int, source: String, knock: float) -> int:
	var amt: int = mini(_Nav.combat_damage(self, amount), _mercy_room())
	if amt <= 0:
		return 0
	var dealt: int = GameState.damage_player(amt, "Мать блоков: " + source)
	if dealt > 0:
		var now := Time.get_ticks_msec() if not has_meta("sim_clock") else int(get_meta("sim_clock"))
		_mercy.append([now, dealt])
	if dealt > 0:
		var push := player.global_position - global_position
		push.y = 0.0
		if push.length() < 0.05:
			push = Vector3(1, 0, 0)
		player.velocity += push.normalized() * knock + Vector3(0, 2.0, 0)
	return dealt


func _die() -> void:
	_enter(S.DEAD)
	_cleanup_fx()
	roar(false)
	if GameState.has_method("on_mother_killed"):
		GameState.on_mother_killed()
	GameState.reward_kill(true, "Мать блоков")
	if not GameState.dev_mode:
		GameState.add_item_count("reagent3", REWARD_R3)
		GameState.add_item_count("reagent2", REWARD_R2)
	GameState.chat("Мать блоков рассыпалась. Сердце структуры твоё! Награда: %d осыпи," % GameState.DUST_PER_BOSS_KILL + " %d реагент3, %d реагент2. Сутки она не вернётся сама." % [REWARD_R3, REWARD_R2], Color(0.6, 1.0, 0.6))
	for grp in ["blockling", "mother_carrier"]:
		for m in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(m) and m.has_method("crumble"):
				m.crumble()
	_Vis.play_state(self, "death", true)
	_debris(global_position + Vector3(0, 1.2, 0), 20, 7.0)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(false)
	var tree: SceneTree = get_tree()
	if tree:
		await tree.create_timer(1.7).timeout
	if is_instance_valid(self):
		queue_free()


func leave(msg: String = "") -> void:
	if state == S.DEAD or state == S.LEAVING:
		return
	_enter(S.LEAVING)
	_cleanup_fx()
	if msg != "":
		GameState.chat(msg, Color(1.0, 0.75, 0.5))
	for grp in ["blockling", "mother_carrier"]:
		for m in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(m) and m.has_method("crumble"):
				m.crumble()
	if GameState and GameState.has_method("set_boss_alive"):
		GameState.set_boss_alive(false)
	collision_layer = 0
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + Vector3(0, -4, 0), 1.2)
	tw.tween_callback(queue_free)


func _cleanup_fx() -> void:
	_free_node(_shadow)
	_free_node(_marker)
	_shadow = null
	_marker = null
	for b in _bricks:
		_free_node(b["node"])
		_free_node(b["shadow"])
	_bricks.clear()
	for w in _waves:
		_free_node(w["node"])
	_waves.clear()
	for c in _covers:
		_free_node(c["node"])
	_covers.clear()


func _exit_tree() -> void:
	_cleanup_fx()
	if GameState and state != S.DEAD and state != S.LEAVING and bool(GameState.get("boss_alive")):
		GameState.set_boss_alive(false)


# ---------------------------------------------------------------- вспомогательное

func _world() -> Node:
	return get_parent() if get_parent() != null else get_tree().current_scene


func _ground_y_at(p: Vector3) -> float:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if cm.has_method("walk_height_at") and not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			return float(cm.call("walk_height_at", floori(p.x), floori(p.z)))
	return 0.0


func _disc(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := MeshInstance3D.new()
	inner.name = "Inner"
	var cm2 := CylinderMesh.new()
	cm2.top_radius = radius
	cm2.bottom_radius = radius
	cm2.height = 0.05
	cm2.radial_segments = 32
	cm2.rings = 1
	inner.mesh = cm2
	var m2 := m.duplicate() as StandardMaterial3D
	m2.albedo_color = Color(col.r, col.g * 0.6, col.b * 0.6, minf(1.0, col.a + 0.25))
	inner.material_override = m2
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.scale = Vector3(0.2, 1, 0.2)
	mi.add_child(inner)
	_world().add_child(mi)
	return mi


func _mini_block(at: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BlockTex.cube_mesh("hill" if _rng.randf() < 0.5 else "ruin", Vector3(0.45, 0.45, 0.45))
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world().add_child(cube)
	cube.global_position = at
	return cube


func _debris(at: Vector3, count: int, speed: float) -> void:
	## Разлёт блоков-осколков (чисто визуально).
	for i in range(count):
		var cube := _mini_block(at)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.2), _rng.randf_range(-1, 1)).normalized()
		var end := at + dir * speed * 0.5 + Vector3(0, -1.0, 0)
		var tw := cube.create_tween()
		tw.set_parallel(true)
		tw.tween_property(cube, "global_position", end, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(cube, "scale", Vector3(0.1, 0.1, 0.1), 0.6)
		tw.chain().tween_callback(cube.queue_free)


func _set_crack_glow(on: bool) -> void:
	## Окно уязвимости: модель светится жёлтым («трещины»), HUD пишет «УЯЗВИМА».
	var model := get_node_or_null("Model")
	if model == null or bool(get_meta("glow", false)) == on:
		return
	set_meta("glow", on)
	for mi in _Vis._meshes_under(model):
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(i)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				bm.emission_enabled = on
				bm.emission = Color(1.0, 0.8, 0.2)
				bm.emission_energy_multiplier = 0.9 if on else 0.0


func _free_node(n: Variant) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()


func debug_snapshot() -> Dictionary:
	return {"state": STATE_NAMES[state], "phase": phase, "hp": hp, "log": attack_log.duplicate(), "plates": intact_plates(), "armor": plate_log.duplicate()}
