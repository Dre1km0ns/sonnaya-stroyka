extends CharacterBody3D
## v0.24: ящерка-детёныш Анаконды. После победы над Анакондой появляется в пещерах (под землёй, y < −4),
## быстрая, кусается. Роняет «Молочный зубок» (70 %, иногда два) видимым предметом.
const BlockTex := preload("res://scripts/block_tex.gd")
const CU := preload("res://scripts/combat_util.gd")
const Sfx := preload("res://scripts/sfx.gd")
const BreakFx := preload("res://scripts/break_fx.gd")
const _Nav := preload("res://scripts/enemy_navigation.gd")
const _Vis := preload("res://scripts/enemy_visuals.gd")
const SPEED := 4.0
const SEEK := 16.0
const BITE := 6
const BITE_CD := 1.1
const HP := 25
const TOOTH_CHANCE := 0.7
const CAP := 4
var hp := HP
var max_hp := HP
var hit_radius := 0.3
var dead := false
var frozen := false
var _cd := 0.0
var _path_cache := {}
var _wander := Vector3.ZERO
var _wt := 0.0
var _legs: Array = []
var _anim_t := 0.0


static func spawn(host: Node, pos: Vector3) -> Node3D:
	if host == null:
		return null
	var l: CharacterBody3D = load("res://scripts/lizard_minion.gd").new()
	l.position = pos
	host.add_child(l)
	return l


func _ready() -> void:
	add_to_group("lizard_minion")
	add_to_group("enemy")
	_Nav.setup_body(self)
	GameState.apply_enemy_scaling(self, HP)
	_build()
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = Vector3(0.5, 0.35, 0.9)
	col.shape = sh; col.position = Vector3(0, 0.2, 0)
	add_child(col)
	_Vis.attach_hp_bar(self, 0.8)
	_Vis.update_hp_bar(self, hp, max_hp)
	GameState.world_changed.connect(func(d: bool) -> void: frozen = d; visible = not d)
	frozen = GameState.is_dream(); visible = not frozen


func _part(kind: String, size: Vector3, pos: Vector3, tint: Color = Color(1, 1, 1)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BlockTex.cube_mesh(kind, size, false, tint)
	mi.material_override = BlockTex.material()
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	## v0.25: ящерка в «толстом» стиле Антона (chunky_body); поворачивает её enemy_navigation.face_dir.
	var m: Node3D = load("res://scripts/chunky_body.gd").make("lizard")
	add_child(m)
	_model_v25 = m


var _model_v25: Node3D


func hit_center() -> Vector3:
	return global_position + Vector3(0, 0.25, 0)


func is_dead_v024() -> bool:
	return dead


func take_damage(amount: int) -> void:
	if dead:
		return
	hp = maxi(0, hp - amount)
	_Vis.update_hp_bar(self, hp, max_hp)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	GameState.lizards_killed += 1
	GameState.reward_kill(false, "Ящерка", self)
	Sfx.play3d(self, "res://assets/audio/sfx_mob_die.ogg", -6.0, 30.0, 1.4)
	BreakFx.puff(get_parent(), hit_center(), Color(0.45, 0.6, 0.35), 12)
	var n := 0
	if randf() < TOOTH_CHANCE:
		n = 2 if randf() < 0.25 else 1
	if n > 0:
		var rec := GameState.register_drop({"id": "milk_tooth", "name": "Молочный зубок", "count": n}, global_position + Vector3(0, 0.4, 0))
		var bc := get_tree().get_first_node_in_group("build_controller")
		if bc: bc.spawn_drop(rec, Vector3(0, 3.0, 0), 0.2)
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", PI, 0.3)
	tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.2, 0.6)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if frozen or dead:
		return
	_cd = maxf(0.0, _cd - delta)
	_anim_t += delta
	var p := CU.nearest_player(get_tree(), global_position)
	if p == null:
		return
	var to := p.global_position - global_position
	var target := p.global_position
	if to.length() > SEEK * GameState.diff_aggro():
		_wt -= delta
		if _wt <= 0.0:
			_wt = 3.0
			_wander = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		target = _wander
	_path_cache["can_break"] = false
	_Nav.follow_target(self, target, SPEED, delta, _path_cache)
	for i in range(_legs.size()):
		(_legs[i] as Node3D).position.y = 0.08 + sin(_anim_t * 18.0 + float(i) * PI) * 0.04
	if to.length() < 1.0 and _cd <= 0.0:
		_cd = BITE_CD
		if _model_v25: _model_v25.call("play_state", "attack", true)
		CU.hurt(p, _Nav.combat_damage(self, BITE), "Ящерка-детёныш", global_position)


## Спавн в пещерах — зовётся из threat_director раз в несколько секунд.
static func try_cave_spawn(tree: SceneTree, host: Node, player: Node3D, chunks: Node) -> Node3D:
	if not GameState.anaconda_defeated or GameState.peaceful or GameState.is_dream() or player == null or chunks == null:
		return null
	if player.global_position.y > -4.0 or tree.get_nodes_in_group("lizard_minion").size() >= CAP:
		return null
	for i in range(12):
		var a := randf() * TAU
		var r := randf_range(6.0, 12.0)
		var c := Vector3i(floori(player.global_position.x + cos(a) * r), floori(player.global_position.y), floori(player.global_position.z + sin(a) * r))
		for dy in [0, 1, -1, 2, -2]:
			var cc := c + Vector3i(0, dy, 0)
			if chunks.terrain_kind_at(cc) == "" and chunks.terrain_kind_at(cc + Vector3i.UP) == "" and chunks.terrain_kind_at(cc + Vector3i.DOWN) != "" and not GameState.wake_blocks.has(cc):
				return spawn(host, Vector3(cc) + Vector3(0.5, 0.1, 0.5))
	return null
