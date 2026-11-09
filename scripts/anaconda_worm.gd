extends Node3D
## v0.7: «Землеройка» — миньон Анаконды (фаза 2+). 3 сегмента, ползёт по полу к игроку, кусает (5).
## Умирает от меча (20 HP) или за 1 с в свете факела. Живёт 30 с.

const BlockTex := preload("res://scripts/block_tex.gd")
const SPEED := 3.4
const BITE := 5
const BITE_CD := 1.2
const MAX_HP := 20
const LIGHT_KILL := 1.0
const LIFETIME := 30.0
const TORCH_RADIUS := 3.5

var hp: int = MAX_HP
var hit_radius: float = 0.35
var frozen: bool = false
var _cd := 0.0
var _life := 0.0
var _lit := 0.0
var _segs: Array[Node3D] = []
var _trail: Array[Vector3] = []
var _dead := false


func _ready() -> void:
	add_to_group("anaconda_minion")
	add_to_group("enemy")
	for i in range(3):
		var mi := MeshInstance3D.new()
		var k := 1.0 - 0.2 * float(i)
		mi.mesh = BlockTex.cube_mesh("scale_head" if i == 0 else "scale", Vector3(0.42, 0.34, 0.5) * k)
		add_child(mi)
		_segs.append(mi)
	_trail.append(global_position)


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
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if _dead or frozen or GameState.is_dream():
		return
	_life += delta
	_cd = maxf(0.0, _cd - delta)
	if _life > LIFETIME:
		crumble()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var head := _segs[0]
	var to := player.global_position - head.global_position
	to.y = 0.0
	var pos := head.global_position
	if to.length() > 0.6:
		pos += to.normalized() * SPEED * delta
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not bool(cm.get("is_dream_layer")) and cm.has_method("floor_y_below"):
			pos.y = float(cm.floor_y_below(pos + Vector3(0, 1.0, 0), 6)) + 0.17
			break
	head.global_position = pos
	if to.length() > 0.05:
		head.look_at(pos + to.normalized(), Vector3.UP)
	if _trail.is_empty() or _trail[0].distance_to(pos) > 0.1:
		_trail.push_front(pos)
		if _trail.size() > 20:
			_trail.pop_back()
	for i in range(1, _segs.size()):
		_segs[i].global_position = _trail[mini(_trail.size() - 1, i * 4)]
	if to.length() < 0.9 and _cd <= 0.0:
		_cd = BITE_CD
		GameState.damage_player(BITE, "Землеройка")
	# Свет убивает.
	var lit := false
	for c in GameState.wake_blocks.keys():
		if str((GameState.wake_blocks[c] as Dictionary).get("kind", "")) == "torch":
			var cell: Vector3i = c
			if Vector3(float(cell.x) + 0.5, float(cell.y) + 0.6, float(cell.z) + 0.5).distance_to(pos) <= TORCH_RADIUS:
				lit = true
				break
	if not lit and GameState.selected_is("torch") and player.global_position.distance_to(pos) <= 2.5:
		lit = true
	_lit = _lit + delta if lit else 0.0
	if _lit >= LIGHT_KILL:
		crumble()
