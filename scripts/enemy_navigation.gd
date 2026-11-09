extends Object
## Общее движение врагов: A* до цели, вода замедляет (не запрещает),
## коллизия с игроком/блоками/другими врагами, шаг на холмик.

const ENEMY_LAYER := 16
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const BLOCK_LAYER := 4
const SPEED_SCALE := 0.6
const STEP_HEIGHT := 1.05
const JUMP_VELOCITY := 5.4
const WATER_JUMP_VELOCITY := 7.2
const LOOK_AHEAD := 1.35
const WATER_COST := 2.5
const WATER_SPEED_FACTOR := 0.4
const PATH_MAX_EXTENT := 28
const ATTACK_RANGE := 1.65
const PATH_REBUILD_SEC := 0.7

static var _cm_cache: Node = null

static func setup_body(body: CharacterBody3D) -> void:
	body.collision_layer = ENEMY_LAYER
	body.collision_mask = WORLD_LAYER | PLAYER_LAYER | BLOCK_LAYER | ENEMY_LAYER
	body.floor_max_angle = deg_to_rad(55.0)
	body.floor_snap_length = 0.35
	body.safe_margin = 0.08
	body.max_slides = 6


static func is_water_at(body: Node3D, pos: Vector3) -> bool:
	var cm := _chunk_manager(body)
	return cm != null and cm.is_world_in_lake(pos)


static func _chunk_manager(from: Node) -> Node:
	## v0.5: кэш менеджера чанков яви (раньше — обход группы на каждую клетку A*).
	if _cm_cache != null and is_instance_valid(_cm_cache) and _cm_cache.is_inside_tree():
		return _cm_cache
	_cm_cache = null
	if from == null:
		return null
	var tree := from.get_tree() if from.is_inside_tree() else null
	if tree == null:
		if from.is_in_group("chunk_manager"):
			return from
		return null
	for cm in tree.get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")) or bool(cm.get("panorama_mode")):
			continue
		_cm_cache = cm
		return cm
	return null


static func cell_height(query: Node, wx: int, wz: int) -> int:
	var cm := query if query != null and query.has_method("height_at") else _chunk_manager(query)
	if cm != null and cm.has_method("is_world_in_lake") and cm.is_world_in_lake(Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5)):
		return -1
	if cm != null and cm.has_method("walk_height_at"):
		return int(cm.walk_height_at(wx, wz))
	if cm != null and cm.has_method("height_at"):
		return int(cm.height_at(wx, wz))
	return 0


static func is_solid_cell(query: Node, wx: int, wz: int) -> bool:
	var cm := query if query != null and query.has_method("is_world_wall") else _chunk_manager(query)
	if cm != null and cm.has_method("is_world_wall") and cm.is_world_wall(wx, wz):
		return true
	if GameState.wake_solid(Vector3i(wx, 0, wz)):
		return true
	var h := maxi(cell_height(query, wx, wz), 0)
	if h > 0 and GameState.wake_solid(Vector3i(wx, h, wz)):
		return true
	return false


static func _weight(query: Node, wx: int, wz: int) -> float:
	var cm := query if query != null and query.has_method("is_world_in_lake") else _chunk_manager(query)
	if cm != null and cm.has_method("is_world_in_lake") and cm.is_world_in_lake(Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5)):
		return WATER_COST
	return 1.0


static func _can_step(query: Node, a: Vector2i, b: Vector2i) -> bool:
	var ha := cell_height(query, a.x, a.y)
	var hb := cell_height(query, b.x, b.y)
	var dh := absi(ha - hb)
	if dh <= 1:
		return true
	var water := ha < 0 or hb < 0
	return water and dh <= 2


static func find_path(from: Vector3, to: Vector3, query: Node) -> Array[Vector3]:
	var start := Vector2i(floori(from.x), floori(from.z))
	var goal := Vector2i(floori(to.x), floori(to.z))
	var out: Array[Vector3] = []
	if start == goal:
		out.append(Vector3(float(goal.x) + 0.5, to.y, float(goal.y) + 0.5))
		return out
	if is_solid_cell(query, goal.x, goal.y):
		var adjusted := _nearest_walkable(query, goal, start)
		if adjusted == start and is_solid_cell(query, start.x, start.y):
			return out
		goal = adjusted
	var min_x := mini(start.x, goal.x) - 8
	var max_x := maxi(start.x, goal.x) + 8
	var min_z := mini(start.y, goal.y) - 8
	var max_z := maxi(start.y, goal.y) + 8
	var cx := int((start.x + goal.x) * 0.5)
	var cz := int((start.y + goal.y) * 0.5)
	min_x = clampi(min_x, cx - PATH_MAX_EXTENT, cx + PATH_MAX_EXTENT)
	max_x = clampi(max_x, cx - PATH_MAX_EXTENT, cx + PATH_MAX_EXTENT)
	min_z = clampi(min_z, cz - PATH_MAX_EXTENT, cz + PATH_MAX_EXTENT)
	max_z = clampi(max_z, cz - PATH_MAX_EXTENT, cz + PATH_MAX_EXTENT)

	var memo_h: Dictionary = {}
	var memo_s: Dictionary = {}
	var heap_f: Array[float] = []
	var heap_c: Array[Vector2i] = []
	_heap_push(heap_f, heap_c, float(absi(goal.x - start.x) + absi(goal.y - start.y)), start)
	var came: Dictionary = {}
	var gscore: Dictionary = {start: 0.0}
	var closed: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var guard := 0
	while not heap_c.is_empty() and guard < 1400:
		guard += 1
		var current: Vector2i = _heap_pop(heap_f, heap_c)
		if closed.has(current):
			continue
		if current == goal:
			return _reconstruct(came, current, to.y)
		closed[current] = true
		var hc := _memo_height(query, current, memo_h)
		for d in dirs:
			var nxt := current + d
			if nxt.x < min_x or nxt.x > max_x or nxt.y < min_z or nxt.y > max_z:
				continue
			if closed.has(nxt):
				continue
			if nxt != start:
				var solid: bool
				if memo_s.has(nxt):
					solid = memo_s[nxt]
				else:
					solid = is_solid_cell(query, nxt.x, nxt.y)
					memo_s[nxt] = solid
				if solid:
					continue
			var hn := _memo_height(query, nxt, memo_h)
			var dh := absi(hc - hn)
			if dh > 1 and not ((hc < 0 or hn < 0) and dh <= 2):
				continue
			var step := 1.414 if d.x != 0 and d.y != 0 else 1.0
			var w := WATER_COST if hn < 0 else 1.0
			var tentative := float(gscore[current]) + step * w
			if tentative < float(gscore.get(nxt, 1e12)):
				came[nxt] = current
				gscore[nxt] = tentative
				_heap_push(heap_f, heap_c, tentative + float(absi(goal.x - nxt.x) + absi(goal.y - nxt.y)), nxt)
	return out


static func _memo_height(query: Node, c: Vector2i, memo: Dictionary) -> int:
	if memo.has(c):
		return memo[c]
	var h := cell_height(query, c.x, c.y)
	memo[c] = h
	return h


static func _heap_push(fs: Array[float], cs: Array[Vector2i], f: float, c: Vector2i) -> void:
	fs.append(f)
	cs.append(c)
	var i := fs.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if fs[p] <= fs[i]:
			break
		var tf := fs[p]
		fs[p] = fs[i]
		fs[i] = tf
		var tc := cs[p]
		cs[p] = cs[i]
		cs[i] = tc
		i = p


static func _heap_pop(fs: Array[float], cs: Array[Vector2i]) -> Vector2i:
	var top := cs[0]
	var last := fs.size() - 1
	fs[0] = fs[last]
	cs[0] = cs[last]
	fs.resize(last)
	cs.resize(last)
	var i := 0
	var n := fs.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and fs[l] < fs[m]:
			m = l
		if r < n and fs[r] < fs[m]:
			m = r
		if m == i:
			break
		var tf := fs[m]
		fs[m] = fs[i]
		fs[i] = tf
		var tc := cs[m]
		cs[m] = cs[i]
		cs[i] = tc
		i = m
	return top


static func _nearest_walkable(query: Node, goal: Vector2i, toward: Vector2i) -> Vector2i:
	if not is_solid_cell(query, goal.x, goal.y):
		return goal
	var best := toward
	var best_d := 999
	for r in range(1, 4):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var c := Vector2i(goal.x + dx, goal.y + dz)
				if is_solid_cell(query, c.x, c.y):
					continue
				var d := absi(c.x - toward.x) + absi(c.y - toward.y)
				if d < best_d:
					best_d = d
					best = c
		if best_d < 999:
			return best
	return toward


static func _reconstruct(came: Dictionary, current: Vector2i, y: float) -> Array[Vector3]:
	var cells: Array[Vector2i] = [current]
	while came.has(current):
		current = came[current]
		cells.append(current)
	cells.reverse()
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5))
	return pts


static func apply_movement(body: CharacterBody3D, want_dir: Vector3, speed: float, delta: float) -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	want_dir.y = 0.0
	if want_dir.length() > 0.001:
		want_dir = want_dir.normalized()
	else:
		want_dir = Vector3.ZERO

	var chosen := _pick_steer_dir(body, want_dir)
	var in_water := is_water_at(body, body.global_position)
	if in_water:
		speed *= WATER_SPEED_FACTOR

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0
		if chosen.length() > 0.01 and _blocked(body, chosen, 0.42):
			var lifted := body.global_transform
			lifted.origin.y += STEP_HEIGHT
			if not body.test_move(lifted, chosen * 0.55):
				body.velocity.y = WATER_JUMP_VELOCITY if in_water else JUMP_VELOCITY
			elif in_water:
				var high := body.global_transform
				high.origin.y += 1.45
				if not body.test_move(high, chosen * 0.55):
					body.velocity.y = WATER_JUMP_VELOCITY

	body.velocity.x = chosen.x * speed
	body.velocity.z = chosen.z * speed
	body.move_and_slide()
	if not body.has_meta("face_lock"):
		var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if flat.length() > 0.15:
			face_dir(body, flat, delta)


## v0.6: модели Quaternius смотрят вдоль +Z (проверено скриншотом). Поворачиваем только узел Model,
## плавно (угловая скорость ~10 рад/с), чтобы мобы шли «лицом», а не боком.
const MODEL_FORWARD_YAW := 0.0
const TURN_RATE := 10.0


static func yaw_for(dir: Vector3) -> float:
	return atan2(dir.x, dir.z) + MODEL_FORWARD_YAW


static func face_dir(body: Node3D, dir: Vector3, delta: float, rate: float = TURN_RATE) -> void:
	var model := body.get_node_or_null("Model") as Node3D
	if model == null:
		return
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	# Модель — дочерний узел тела: переводим мировое направление в локальное (тело могло быть повёрнуто).
	var local := body.global_transform.basis.inverse() * dir
	var target := yaw_for(local)
	var k := clampf(1.0 - exp(-rate * delta), 0.0, 1.0)
	model.rotation.y = lerp_angle(model.rotation.y, target, k)


static func face_point(body: Node3D, point: Vector3, delta: float, rate: float = TURN_RATE) -> void:
	face_dir(body, point - body.global_position, delta, rate)


static func model_world_forward(body: Node3D) -> Vector3:
	var model := body.get_node_or_null("Model") as Node3D
	if model == null:
		return Vector3.ZERO
	var f := model.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


static func follow_target(body: CharacterBody3D, target: Vector3, speed: float, delta: float, cache: Dictionary) -> Vector3:
	var now: float = float(cache.get("t", 0.0)) + delta
	cache["t"] = now
	var last_rebuild: float = float(cache.get("rebuild_at", -10.0))
	var last_goal: Vector3 = cache.get("goal", Vector3.INF)
	if not cache.has("jitter"):
		cache["jitter"] = randf() * 0.3
	if now - last_rebuild > PATH_REBUILD_SEC + float(cache["jitter"]) or last_goal.distance_to(target) > 2.5:
		cache["path"] = find_path(body.global_position, target, body)
		cache["rebuild_at"] = now
		cache["goal"] = target
	var path: Array = cache.get("path", [])
	var desired := Vector3.ZERO
	if path.size() >= 2:
		var idx := 1
		while idx < path.size():
			var wp: Vector3 = path[idx]
			var flat := Vector3(wp.x - body.global_position.x, 0.0, wp.z - body.global_position.z)
			if flat.length() > 0.45:
				desired = flat.normalized()
				break
			idx += 1
	if desired.length() < 0.01:
		var fallback := target - body.global_position
		fallback.y = 0.0
		if fallback.length() > 0.15:
			desired = fallback.normalized()
	apply_movement(body, desired, speed, delta)
	return desired


static func nearest_adjacent_block(body: Node3D) -> Variant:
	var best: Variant = null
	var best_d := ATTACK_RANGE
	var origin := body.global_position
	for key in GameState.wake_blocks.keys():
		var c: Vector3i = key
		var wp := Vector3(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5)
		var flat := Vector2(wp.x - origin.x, wp.z - origin.z).length()
		var dy := absf(wp.y - origin.y)
		if flat <= ATTACK_RANGE and dy <= 2.2 and flat < best_d:
			best_d = flat
			best = c
	return best


static func _pick_steer_dir(body: CharacterBody3D, want_dir: Vector3) -> Vector3:
	if want_dir.length() < 0.001:
		return Vector3.ZERO
	# v0.5: прямой путь свободен — без перебора 8 направлений (9 test_move → 1).
	if not _blocked(body, want_dir, 0.45):
		return want_dir
	var candidates: Array[Vector3] = [want_dir]
	for i in range(8):
		var a := float(i) * PI * 0.25
		candidates.append(Vector3(cos(a), 0.0, sin(a)))
	var best := want_dir
	var best_score := -1000.0
	for raw in candidates:
		var d: Vector3 = raw.normalized()
		var score := d.dot(want_dir)
		if _blocked(body, d, 0.45):
			score -= 0.9
			var lifted := body.global_transform
			lifted.origin.y += STEP_HEIGHT
			if not body.test_move(lifted, d * 0.5):
				score += 0.55
		if score > best_score:
			best_score = score
			best = d
	return best


static func _blocked(body: CharacterBody3D, dir: Vector3, dist: float) -> bool:
	return body.test_move(body.global_transform, dir * dist)
