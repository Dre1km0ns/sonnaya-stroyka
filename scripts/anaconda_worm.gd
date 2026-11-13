extends Node3D
## v0.11.1: «Землеройка» — миньон Анаконды (фаза II+, одновременно не больше 3).
## Сначала 1.5 с выкапывается на месте (телеграф). Цель — ПОСТАВЛЕННЫЕ факелы: ползёт к ближайшему, 2.2 с «гасит» (телеграф: дрожит и пылит), затем факел гаснет,
## а землеройка зарывается. Нет факелов — ползёт к игроку и кусает (5).
## Умирает от меча/кирки (20 HP) или за 1 с в перекрёстном свете (2+ факела). Один факел её не берёт. Живёт 30 с.

const BlockTex := preload("res://scripts/block_tex.gd")
const SPEED := 2.2
const BITE := 5
const BITE_CD := 1.2
const MAX_HP := 20
const LIGHT_KILL := 1.0
const LIFETIME := 30.0
const TORCH_RADIUS := 3.5
const DOUSE_TIME := 2.2
const DOUSE_REACH := 0.9
const EMERGE_TIME := 1.5   # сначала 1.5 с выкапывается на месте (видно и слышно) — время перехватить

var hp: int = MAX_HP
var hit_radius: float = 0.35
var frozen: bool = false
var boss: Node = null
var target_torch := Vector3i(0, -9999, 0)
var dousing := 0.0
var torches_doused := 0
var _cd := 0.0
var _life := 0.0
var _lit := 0.0
var _segs: Array[Node3D] = []
var _trail: Array[Vector3] = []
var _dead := false
var _pos := Vector3.ZERO


func _ready() -> void:
	add_to_group("anaconda_minion")
	add_to_group("enemy")
	for i in range(3):
		var mi := MeshInstance3D.new()
		var k := 1.0 - 0.2 * float(i)
		mi.mesh = BlockTex.cube_mesh("scale_head" if i == 0 else "scale", Vector3(0.42, 0.34, 0.5) * k)
		add_child(mi)
		_segs.append(mi)
	_pos = global_position
	_trail.append(_pos)


func hit_center() -> Vector3:
	return _segs[0].global_position if not _segs.is_empty() else global_position


func take_damage(amount: int) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0:
		crumble()


func crumble() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("anaconda_minion")
	remove_from_group("enemy")
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
		tw.tween_callback(queue_free)


func is_dead() -> bool:
	return _dead


static func _tp(c: Vector3i) -> Vector3:
	return Vector3(float(c.x) + 0.5, float(c.y) + 0.6, float(c.z) + 0.5)


func _pick_torch(from: Vector3) -> Vector3i:
	var best := Vector3i(0, -9999, 0)
	var bd := 30.0
	for c in GameState.torch_cells():
		var d := _tp(c).distance_to(from)
		if d < bd:
			bd = d
			best = c
	return best


func lit_sources(at: Vector3) -> int:
	var n := 0
	for c in GameState.torch_cells():
		if _tp(c).distance_to(at) <= TORCH_RADIUS:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _dead or frozen or GameState.is_dream():
		return
	_life += delta
	_cd = maxf(0.0, _cd - delta)
	if _life > LIFETIME:
		crumble()
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	var pos := _segs[0].global_position if is_inside_tree() else _pos
	if _life < EMERGE_TIME:
		if is_inside_tree():
			_segs[0].global_position = pos + Vector3(sin(_life * 50.0), 0, 0) * 0.008
		return
	if target_torch.y == -9999 or str(GameState.wake_blocks.get(target_torch, {}).get("kind", "")) != "torch":
		target_torch = _pick_torch(pos)
		dousing = 0.0
	var goal := pos
	if target_torch.y != -9999:
		goal = _tp(target_torch)
	elif player:
		goal = player.global_position
	var to := goal - pos
	to.y = 0.0
	if target_torch.y != -9999 and to.length() <= DOUSE_REACH:
		dousing += delta
		pos += Vector3(sin(_life * 40.0), 0, cos(_life * 37.0)) * 0.01   # дрожит — телеграф
		if dousing >= DOUSE_TIME:
			_douse(target_torch)
			return
	elif to.length() > 0.6:
		pos += to.normalized() * SPEED * delta
	if is_inside_tree():
		for cm in get_tree().get_nodes_in_group("chunk_manager"):
			if not bool(cm.get("is_dream_layer")) and cm.has_method("floor_y_below"):
				pos.y = float(cm.floor_y_below(pos + Vector3(0, 1.0, 0), 6)) + 0.17
				break
	_pos = pos
	_segs[0].global_position = pos if is_inside_tree() else pos
	if is_inside_tree() and to.length() > 0.05:
		_segs[0].look_at(pos + to.normalized(), Vector3.UP)
	if _trail.is_empty() or _trail[0].distance_to(pos) > 0.1:
		_trail.push_front(pos)
		if _trail.size() > 20:
			_trail.pop_back()
	if is_inside_tree():
		for i in range(1, _segs.size()):
			_segs[i].global_position = _trail[mini(_trail.size() - 1, i * 4)]
	if player and target_torch.y == -9999:
		var tp := player.global_position - pos
		if Vector2(tp.x, tp.z).length() < 0.9 and _cd <= 0.0:
			_cd = BITE_CD
			GameState.damage_player(BITE, "Землеройка")
	# Перекрёстный свет (2+ поставленных факела) убивает за 1 с; один факел — нет.
	_lit = _lit + delta if lit_sources(pos) >= 2 else 0.0
	if _lit >= LIGHT_KILL:
		crumble()


func _douse(c: Vector3i) -> void:
	torches_doused += 1
	if boss != null and is_instance_valid(boss) and boss.has_method("break_torch"):
		boss.break_torch(c, "землеройка")
	else:
		GameState.remove_torch(c)
	crumble()
