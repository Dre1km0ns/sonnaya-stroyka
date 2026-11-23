extends Node3D
## v0.24: стрела — своя баллистика (гравитация), попадание по мобам/боссам/слабым точкам, втыкается в блоки.
## Воткнутую стрелу можно подобрать (обычная — всегда, стрела детёнышей — с шансом 50 %), через 60 с исчезает.
const BlockTex := preload("res://scripts/block_tex.gd")
const GRAVITY := 11.0
const HIT_PAD := 0.45
const STUCK_LIFE := 60.0
const MAX_FLIGHT := 6.0
var vel := Vector3.ZERO
var damage := 9
var kind := "arrow"
var shooter: Node3D = null
var stuck := false
var hit_target: Node = null
var range_m := 0.0     # v0.25: дальность лука игрока (0 — старая баллистика, у стрелка)
var base_damage := -1
var travelled := 0.0
var hostile := false   # v0.24: стрела моба-стрелка — бьёт игроков, не мобов, не подбирается
var _t := 0.0
var _mesh: MeshInstance3D


func setup(v: Vector3, dmg: int, k: String, who: Node3D) -> void:
	vel = v; damage = dmg; kind = k; shooter = who


func _ready() -> void:
	add_to_group("arrow")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = BlockTex.arrow_mesh(kind == "arrow2")
	_mesh.material_override = BlockTex.material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_orient()


func _orient() -> void:
	if vel.length() > 0.1:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + vel, up) if is_inside_tree() else null


func _physics_process(delta: float) -> void:
	_t += delta
	if GameState.is_dream():
		visible = false
		return
	visible = true
	if stuck:
		if hostile and _t > 6.0:
			queue_free()
			return
		if _t > STUCK_LIFE:
			queue_free()
			return
		if not hostile:
			_try_pickup()
		return
	if _t > MAX_FLIGHT:
		queue_free()
		return
	if range_m > 0.0:
		if base_damage < 0: base_damage = damage
		var straight := range_m * 0.75
		if travelled > straight:
			vel.y -= GRAVITY * 1.6 * delta   # после 75 % дальности — на спад
			damage = maxi(1, int(round(float(base_damage) * lerpf(1.0, 0.8, clampf((travelled - straight) / (range_m - straight), 0.0, 1.0)))))
		travelled += vel.length() * delta
	else:
		vel.y -= GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	if _check_targets(from, to):
		return
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q) if get_world_3d() else {}
	if not hit.is_empty():
		global_position = hit.position - vel.normalized() * 0.15
		stuck = true
		_t = 0.0
		Sfx.play("arrow_hit", get_tree().root)
		return
	global_position = to
	_orient()


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _check_targets(from: Vector3, to: Vector3) -> bool:
	if hostile:
		for p in CU.players(get_tree()):
			var pc: Vector3 = (p as Node3D).global_position + Vector3(0, 0.9, 0)
			if _seg_dist(pc, from, to) <= 0.55:
				CU.hurt(p, damage, "Стрелок", from)
				Sfx.play("arrow_hit", get_tree().root)
				queue_free()
				return true
		return false
	# слабые точки (Бургер) — приоритетнее тела
	for wp in get_tree().get_nodes_in_group("weak_point"):
		if not is_instance_valid(wp) or not (wp as Node3D).is_visible_in_tree():
			continue
		var r := float(wp.get("radius")) if "radius" in wp else 0.6
		if _seg_dist((wp as Node3D).global_position, from, to) <= r + 0.1:
			if wp.has_method("hit_by_arrow"):
				wp.hit_by_arrow(damage, self)
			_hit(wp)
			return true
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		if n.has_method("is_dead_v024") and n.is_dead_v024():
			continue
		var c: Vector3 = n.hit_center() if n.has_method("hit_center") else (n as Node3D).global_position + Vector3(0, 0.8, 0)
		var r := (float(n.get("hit_radius")) if "hit_radius" in n else 0.0) + HIT_PAD
		if _seg_dist(c, from, to) <= r:
			if n.has_method("take_arrow"):
				n.take_arrow(damage, self)
			elif n.has_method("take_damage"):
				n.take_damage(damage)
			GameState.hit_marker.emit("hit")
			_hit(n)
			return true
	return false


func _hit(n: Node) -> void:
	hit_target = n
	GameState.stat_add("arrows_hit")
	Sfx.play("hit", get_tree().root)
	queue_free()


func _try_pickup() -> void:
	if _t < 0.5:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if (p as Node3D).global_position.distance_to(global_position) < 1.8:
			if kind == "arrow" or randf() < 0.5:
				GameState.add_item_count(kind, 1)
			Sfx.play("pickup", get_tree().root)
			queue_free()
			return


const Sfx := preload("res://scripts/sfx.gd")
const CU := preload("res://scripts/combat_util.gd")
