extends Node
## Угрозы Яви: рост Шовников от времени/дистанции, элита, нестабильный шов.

const BASE_SPAWN_SPOTS: Array[Vector3] = [
	Vector3(18, 1.0, 16),
	Vector3(-20, 1.0, 10),
	Vector3(14, 1.0, -22),
]

var wake_root: Node3D
var bed: Node3D
var player: CharacterBody3D
var awake_time: float = 0.0
var _spawn_budget: int = 3
const MAX_ENEMIES := 7
## v0.7: пока жив любой босс, обычных врагов (Шовники + призраки) не больше двух.
const BOSS_ENEMY_CAP := 2


func enemy_cap() -> int:
	return BOSS_ENEMY_CAP if bool(GameState.get("boss_alive")) else MAX_ENEMIES
const NIGHT_SPAWN_FACTOR := 0.6
var _next_spawn_at: float = 45.0
var _unstable_cd: float = 18.0
var _enemy_script: GDScript
var _ghost_respawn_at: Dictionary = {}
var _ghost_present: Dictionary = {}
const GHOST_RESPAWN_DELAY := 60.0 # v0.11: было 25 с — бесконечный фарм осыпи
const MAX_GHOSTS_PER_SPOT := 3
var _ghost_script: GDScript
const MODE_CHASE := 0
const MODE_SCATTER := 1
const GHOST_CORNERS: Array[Vector3] = [
	Vector3(42, 1.0, 42),
	Vector3(-42, 1.0, 42),
	Vector3(42, 1.0, -42),
	Vector3(-42, 1.0, -42),
]
const GHOST_SPOTS: Array[Vector3] = [
	Vector3(22, 1.0, 18),
	Vector3(-24, 1.0, 14),
	Vector3(16, 1.0, -26),
	Vector3(-18, 1.0, -20),
]
var ghost_mode: int = MODE_SCATTER
var _mode_timer: float = 7.0


func setup(p: CharacterBody3D, wake: Node3D, bed_node: Node3D) -> void:
	player = p
	wake_root = wake
	bed = bed_node
	add_to_group("threat_director")
	_enemy_script = load("res://scripts/seam_creature.gd")
	_ghost_script = load("res://scripts/enemy_ghost.gd")
	if not GameState.wake_resolved.is_connected(_on_player_woke):
		GameState.wake_resolved.connect(_on_player_woke)
	_ensure_all_spawns()


func _on_player_woke(_t: int, _d: int, _m: int) -> void:
	_ensure_all_spawns()


func mobs_can_spawn() -> bool:
	return GameState.mobs_unlocked()


func is_ghost_scatter() -> bool:
	return ghost_mode == MODE_SCATTER


func _ensure_all_spawns() -> void:
	if not mobs_can_spawn():
		return
	_ensure_base_spawns()
	_ensure_ghosts()


func to_save_dict() -> Dictionary:
	return {
		"awake_time": awake_time,
		"spawn_budget": _spawn_budget,
		"next_spawn_at": _next_spawn_at,
		"unstable_cd": _unstable_cd,
		"enemy_count": _count_enemies(),
		"ghost_count": _count_ghosts(),
		"ghost_respawn_at": _ghost_respawn_at.duplicate(),
		"ghost_present": _ghost_present.duplicate(),
		"ghost_mode": ghost_mode,
		"mode_timer": _mode_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	awake_time = float(d.get("awake_time", 0.0))
	_spawn_budget = int(d.get("spawn_budget", 3))
	_next_spawn_at = float(d.get("next_spawn_at", 45.0))
	_unstable_cd = float(d.get("unstable_cd", 18.0))
	ghost_mode = int(d.get("ghost_mode", MODE_SCATTER))
	_mode_timer = float(d.get("mode_timer", 7.0))
	_ghost_respawn_at.clear()
	_ghost_present.clear()
	for k in d.get("ghost_respawn_at",{}):
		_ghost_respawn_at[int(k)] = float(d.ghost_respawn_at[k])
	for k in d.get("ghost_present",{}):
		_ghost_present[int(k)] = bool(d.ghost_present[k])
	if not mobs_can_spawn():
		return
	# Добить до сохранённого числа врагов (сессия могла быть пустой)
	var want := mini(MAX_ENEMIES, maxi(3, int(d.get("enemy_count", 3))))
	# Несколько маяков могут перекрыть всю зону спавна: загрузка не должна зависать.
	var attempts := 0
	while _count_all_enemies() < MAX_ENEMIES and _count_enemies() < want and attempts < 32:
		attempts += 1
		_spawn_one(false if _count_enemies() < 3 else true)
	_ensure_ghosts()


var _anaconda_t := 0.0


func _process(delta: float) -> void:
	if GameState.is_dream():
		return
	if player == null or wake_root == null:
		return
	_anaconda_t -= delta
	if _anaconda_t <= 0.0:
		_anaconda_t = 0.5
		_tick_anaconda()
	awake_time += delta
	GameState.awake_time = awake_time
	_unstable_cd = maxf(0.0, _unstable_cd - delta)
	if not mobs_can_spawn():
		return
	_update_ghost_mode(delta)
	if bool(GameState.get("boss_alive")):
		_cull_to_cap()
		return
	_ensure_all_spawns()

	var bed_pos := bed.global_position if bed else Vector3.ZERO
	var dist := player.global_position.distance_to(bed_pos)

	# Дальше от кровати / дольше не спишь → больше шовников
	var target := 3 + int(awake_time / 50.0) + int(dist / 35.0)
	# v0.6: ночь (фаза «Ночь» 24-минутных суток) — на одного Шовника больше и спавн чаще.
	var night := GameState.is_night()
	if night:
		target += 1
	target = mini(target, enemy_cap())
	while _count_all_enemies() < enemy_cap() and _count_enemies() < target and awake_time >= _next_spawn_at:
		var elite := _count_enemies() >= 5 or dist > 50.0
		_spawn_one(elite)
		_next_spawn_at = awake_time + maxf(20.0, 55.0 - awake_time * 0.05) * (NIGHT_SPAWN_FACTOR if night else 1.0)
		GameState.set_hint("Шов расползается… ещё Шовник%s!" % ("-тяжёлый" if elite else ""), false)

	if _unstable_cd <= 0.0 and dist > 8.0:
		_pulse_unstable_seam()
		_unstable_cd = 14.0 + randf() * 10.0


func _tick_anaconda() -> Node:
	## v0.7: Анаконда — ночью у гнезда с яйцом (≤12 м) или если яйцо в кармане под землёй.
	var chunks: Node = null
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not bool(cm.get("is_dream_layer")) and not bool(cm.get("panorama_mode")):
			chunks = cm
	_warn_nests(chunks)
	var script: GDScript = load("res://scripts/boss_anaconda.gd")
	return script.try_spawn(wake_root, player, chunks)


var _nest_warned: Dictionary = {}


func _warn_nests(chunks: Node) -> void:
	## v0.11: гнездо видно заранее — предупреждение за 20 м, до того как Анаконда сможет прийти.
	if chunks == null or player == null or GameState.is_dream() or not chunks.has_method("nests_near"):
		return
	for n in chunks.nests_near(player.global_position, 20.0):
		if bool(n["taken"]) or _nest_warned.has(str(n["id"])):
			continue
		_nest_warned[str(n["id"])] = true
		GameState.nest_found = true
		GameState.chat("Гнездо Анаконды рядом. Ночью она выйдет к тому, кто подойдёт к яйцу ближе 12 м. Меч бесполезен — её жгут только ПОСТАВЛЕННЫЕ факелы, лучше 2–3 с разных сторон. Её тело ломает факелы — бери запас.", Color(1.0, 0.7, 0.35))


func _cull_to_cap() -> int:
	## Босс появился — лишние обычные враги (самые дальние) рассеиваются.
	var all: Array = []
	for e in get_tree().get_nodes_in_group("seam_creature"):
		if not e.is_queued_for_deletion():
			all.append(e)
	for g in get_tree().get_nodes_in_group("enemy_ghost"):
		if not g.is_queued_for_deletion():
			all.append(g)
	var extra := all.size() - BOSS_ENEMY_CAP
	if extra <= 0:
		return 0
	var ppos := player.global_position if player else Vector3.ZERO
	all.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node3D).global_position.distance_squared_to(ppos) > (b as Node3D).global_position.distance_squared_to(ppos))
	for i in range(extra):
		var n: Node = all[i]
		n.remove_from_group("seam_creature")
		n.remove_from_group("enemy_ghost")
		n.queue_free()
	return extra


func _ensure_base_spawns() -> void:
	if _count_enemies() > 0:
		return
	for i in range(BASE_SPAWN_SPOTS.size()):
		_spawn_at(BASE_SPAWN_SPOTS[i], false)


func _count_all_enemies() -> int:
	return _count_enemies() + _count_ghosts()


func _count_enemies() -> int:
	var n := 0
	for _e in get_tree().get_nodes_in_group("seam_creature"):
		n += 1
	return n


func _spawn_one(elite: bool) -> void:
	var bed_pos := bed.global_position if bed else Vector3.ZERO
	var ang := randf() * TAU
	var rad := 22.0 + randf() * 28.0
	var pos := bed_pos + Vector3(cos(ang) * rad, 1.0, sin(ang) * rad)
	_spawn_at(pos, elite)


func _spawn_at(pos: Vector3, elite: bool) -> void:
	if _enemy_script == null or wake_root == null:
		return
	if _count_all_enemies() >= enemy_cap():
		return
	if GameState.beacon_protects(Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))):
		return
	if try_spawn_blockolith(pos) != null:
		return
	var e: CharacterBody3D = _enemy_script.new()
	e.position = pos
	if elite and e.has_method("configure_elite"):
		e.configure_elite(true)
	elif elite:
		e.set("elite", true)
	wake_root.add_child(e)
	load("res://scripts/seam_effect.gd").spawn(wake_root, pos)


var blockoliths_spawned := 0


func try_spawn_blockolith(pos: Vector3, roll: float = -1.0) -> Node:
	## v0.11.1: после первой победы над Матерью обычный спавн с шансом 1/120 заменяется нейтральным Блоколитом
	## (не больше одного одновременно). Его убийство вызывает Мать блоков.
	if wake_root == null or get_tree().get_nodes_in_group("blockolith").size() > 0:
		return null
	if not GameState.blockolith_roll(roll):
		return null
	var b: CharacterBody3D = load("res://scripts/blockling.gd").new()
	b.configure("blockolith")
	b.position = pos
	wake_root.add_child(b)
	blockoliths_spawned += 1
	return b


func _pulse_unstable_seam() -> void:
	## Краткий «нестабильный шов»: рвёт до 2 блоков яви рядом с игроком.
	if player == null:
		return
	var ripped := 0
	var victims: Array[Vector3i] = []
	for cell in GameState.wake_blocks.keys():
		var c: Vector3i = cell
		var wp := Vector3(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5)
		if player.global_position.distance_to(wp) <= 6.0 and not GameState.beacon_protects(c):
			victims.append(c)
	victims.shuffle()
	for c2 in victims:
		if ripped >= 2:
			break
		if not GameState.destroy_wake_structure(c2,true):
			continue
		load("res://scripts/seam_effect.gd").spawn(wake_root, Vector3(c2) + Vector3.ONE*0.5)
		# Нестабильный шов НЕ даёт осыпь — чистая потеря (хардкор)
		ripped += 1
		for vox in get_tree().get_nodes_in_group("voxel_world"):
			if vox.has_method("remove_block") and not bool(vox.get("is_dream_layer")):
				vox.remove_block(c2)
	if ripped > 0:
		GameState.inventory_changed.emit()
		GameState.set_hint("Нестабильный шов! Потеряно блоков яви: %d" % ripped)
	else:
		GameState.set_hint("Нестабильный шов дрожит… построек рядом нет.", false)


func _update_ghost_mode(delta: float) -> void:
	_mode_timer = maxf(0.0, _mode_timer - delta)
	if _mode_timer > 0.0:
		return
	if ghost_mode == MODE_CHASE:
		ghost_mode = MODE_SCATTER
		_mode_timer = 7.0
	else:
		ghost_mode = MODE_CHASE
		_mode_timer = 20.0


func _count_ghosts() -> int:
	return get_tree().get_nodes_in_group("enemy_ghost").size()


func _ensure_ghosts() -> void:
	if not mobs_can_spawn():
		return
	if _ghost_script == null or wake_root == null:
		return
	var counts: Dictionary = {}
	for n in get_tree().get_nodes_in_group("enemy_ghost"):
		if not bool(n.get("_dead")):
			var k := int(n.get("kind"))
			counts[k] = int(counts.get(k, 0)) + 1
	for i in range(4):
		var have := int(counts.get(i, 0))
		if _ghost_can_spawn(i,have):
			_spawn_ghost(i,GHOST_SPOTS[i],GHOST_CORNERS[i])


func _ghost_can_spawn(i: int, have: int) -> bool:
	if have > 0:
		_ghost_present[i] = true
		return false
	if bool(_ghost_present.get(i,false)):
		_ghost_present[i] = false
		_ghost_respawn_at[i] = awake_time+GHOST_RESPAWN_DELAY
	return have < MAX_GHOSTS_PER_SPOT and awake_time >= float(_ghost_respawn_at.get(i,0.0))


func _spawn_ghost(kind: int, pos: Vector3, corner: Vector3) -> void:
	if _ghost_script == null or wake_root == null:
		return
	if _count_all_enemies() >= enemy_cap():
		return
	var e: CharacterBody3D = _ghost_script.new()
	e.position = pos
	if e.has_method("configure"):
		e.configure(kind, pos, corner)
	else:
		e.set("kind", kind)
		e.set("home", pos)
		e.set("corner", corner)
	wake_root.add_child(e)
