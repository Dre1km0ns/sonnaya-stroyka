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
static var ai_budget_usec:=2000
static var ai_frame_usec:=0
static var ai_max_frame_usec:=0
static var ai_paths_completed:=0
static var ai_search_nodes:=0
static var _ai_frame: int=-1
const NAV_DIRS: Array[Vector2i]=[Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]

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
	if _cm_cache != null and is_instance_valid(_cm_cache) and _cm_cache.is_inside_tree() and (_cm_cache.get_parent()==from.get_tree().root or _cm_cache.get_parent().is_ancestor_of(from)):
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
		if cm.get_parent().is_ancestor_of(from) and cm.get_parent()!=tree.root:
			_cm_cache=cm;return cm
		if tree.current_scene and tree.current_scene.is_ancestor_of(from) and not tree.current_scene.is_ancestor_of(cm): continue
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
	speed = movement_speed(body,speed)
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


static func follow_target(body: CharacterBody3D,target: Vector3,speed: float,delta: float,cache: Dictionary)->Vector3:
	var now:float=float(cache.get("t",0.0))+delta;cache.t=now
	var elapsed:float=float(cache.get("probe_elapsed",0.0))+delta;cache.probe_elapsed=elapsed
	if cache.get("can_break",true) and elapsed>=0.10:
		cache.obstructed=try_mine_obstruction(body,target,elapsed,cache);cache.probe_elapsed=0.0
	if not cache.get("can_break",true):
		cache.obstructed=false;cache.erase("mine_cell");cache.mine_t=0.0;body.set_meta("mining_progress",0.0)
	if cache.get("obstructed",false):
		apply_movement(body,Vector3.ZERO,0.0,delta);return Vector3.ZERO
	var frame:=Engine.get_physics_frames()
	if frame!=_ai_frame: _ai_frame=frame;ai_frame_usec=0
	var phase:=int(body.get_instance_id()%3)
	if posmod(frame+phase,3)==0 and ai_frame_usec<ai_budget_usec:
		var start:=Time.get_ticks_usec()
		var last:float=float(cache.get("rebuild_at",-10.0))
		var last_goal:Vector3=cache.get("goal",Vector3.INF)
		if not cache.has("search") and (now-last>PATH_REBUILD_SEC+phase*0.1 or last_goal.distance_to(target)>2.5):
			cache.search=_new_search(body.global_position,target,body);cache.goal=target
		if cache.has("search"):
			_advance_search(cache.search,body,mini(500,ai_budget_usec-ai_frame_usec))
			if cache.search.done:
				cache.path=cache.search.out;cache.erase("search");cache.rebuild_at=now;ai_paths_completed+=1
		ai_frame_usec+=Time.get_ticks_usec()-start;ai_max_frame_usec=maxi(ai_max_frame_usec,ai_frame_usec)
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
	var center:=Vector3i(floori(origin.x),floori(origin.y),floori(origin.z))
	for dx in range(-2,3):
		for dy in range(-2,3):
			for dz in range(-2,3):
				var c:=center+Vector3i(dx,dy,dz)
				if not GameState.wake_blocks.has(c): continue
				var wp:=Vector3(c)+Vector3.ONE*0.5
				var flat:=Vector2(wp.x-origin.x,wp.z-origin.z).length()
				if flat<=ATTACK_RANGE and absf(wp.y-origin.y)<=2.2 and flat<best_d: best_d=flat;best=c
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


static func combat_damage(body: Node,base: int) -> int:
	return maxi(0,int(body.get_meta("damage_override",base)))

static func movement_speed(body: Node,base: float) -> float:
	return maxf(0.0,float(body.get_meta("speed_override",base))) if base>0.0 else 0.0

static func try_mine_obstruction(body: CharacterBody3D,target: Vector3,delta: float,cache: Dictionary) -> bool:
	var flat := target-body.global_position
	flat.y = 0.0
	if flat.length()<0.3: return false
	var origin := body.global_position+Vector3(0,0.8,0)
	var q := PhysicsRayQueryParameters3D.create(origin,origin+flat.normalized()*1.6,1|4,[body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		cache.erase("mine_cell")
		cache["mine_t"] = 0.0
		body.set_meta("mining_progress",0.0)
		return false
	var point: Vector3 = hit.position-hit.normal*0.03
	var cell := Vector3i(floori(point.x),floori(point.y),floori(point.z))
	var cm := _chunk_manager(body)
	var kind := ""
	if GameState.wake_blocks.has(cell):
		cell = GameState.root_cell(GameState.wake_blocks,cell)
		kind = GameState.wake_blocks[cell].get("kind","")
	elif cm and cm.has_method("terrain_kind_at"):
		kind = str(cm.terrain_kind_at(cell))
	if kind=="" or kind=="bedrock": return false
	return advance_mob_mining(body,cell,kind,delta,cache,cm)

static func advance_mob_mining(body: Node,cell: Vector3i,kind: String,delta: float,cache: Dictionary,cm: Node = null) -> bool:
	var duration := preload("res://scripts/mining_rules.gd").seconds(kind,str(body.get_meta("mining_tool","")))*2.0
	if not is_finite(duration): return false
	if cache.get("mine_cell",Vector3i(99999,99999,99999))!=cell:
		cache["mine_cell"] = cell
		cache["mine_t"] = 0.0
	cache["mine_t"] = float(cache.get("mine_t",0.0))+delta
	body.set_meta("mining_progress",minf(1.0,cache["mine_t"]/duration))
	if cache["mine_t"]>=duration:
		if GameState.wake_blocks.has(cell):
			GameState.destroy_wake_structure(cell)
		elif GameState.remove_terrain_cell(cell,kind) and cm:
			cm.rebuild_chunk_at_world(cell.x,cell.z)
		cache["mine_t"] = 0.0
		cache.erase("mine_cell")
		cache["rebuild_at"] = -10.0
		cache.erase("search")
	return true

static func _new_search(from:Vector3,to:Vector3,query:Node)->Dictionary:
	var start:=Vector2i(floori(from.x),floori(from.z));var goal:=Vector2i(floori(to.x),floori(to.z))
	var out:Array[Vector3]=[]
	if start==goal: out.append(Vector3(goal.x+0.5,to.y,goal.y+0.5));return {"done":true,"out":out}
	if is_solid_cell(query,goal.x,goal.y): goal=_nearest_walkable(query,goal,start)
	var cx:=int((start.x+goal.x)*0.5);var cz:=int((start.y+goal.y)*0.5)
	var heap_f:Array[float]=[];var heap_c:Array[Vector2i]=[]
	_heap_push(heap_f,heap_c,float(absi(goal.x-start.x)+absi(goal.y-start.y)),start)
	return {"start":start,"goal":goal,"y":to.y,"out":out,"done":false,"hf":heap_f,"hc":heap_c,"mh":{},"ms":{},"came":{},"g":{start:0.0},"closed":{},"guard":0,
		"x0":clampi(mini(start.x,goal.x)-8,cx-PATH_MAX_EXTENT,cx+PATH_MAX_EXTENT),"x1":clampi(maxi(start.x,goal.x)+8,cx-PATH_MAX_EXTENT,cx+PATH_MAX_EXTENT),
		"z0":clampi(mini(start.y,goal.y)-8,cz-PATH_MAX_EXTENT,cz+PATH_MAX_EXTENT),"z1":clampi(maxi(start.y,goal.y)+8,cz-PATH_MAX_EXTENT,cz+PATH_MAX_EXTENT)}

static func _advance_search(state:Dictionary,query:Node,budget_us:int=500)->void:
	if state.done: return
	var started:=Time.get_ticks_usec();var processed:=0
	var heap_f:Array[float]=state.hf;var heap_c:Array[Vector2i]=state.hc
	while not heap_c.is_empty() and state.guard<1400:
		state.guard+=1;processed+=1;ai_search_nodes+=1
		var current:=_heap_pop(heap_f,heap_c)
		if state.closed.has(current): continue
		if current==state.goal:
			state.out=_reconstruct(state.came,current,state.y);state.done=true;return
		state.closed[current]=true
		var hc:=_memo_height(query,current,state.mh)
		for d in NAV_DIRS:
			var next:=current+d
			if next.x<state.x0 or next.x>state.x1 or next.y<state.z0 or next.y>state.z1 or state.closed.has(next): continue
			if next!=state.start:
				if not state.ms.has(next): state.ms[next]=is_solid_cell(query,next.x,next.y)
				if state.ms[next]: continue
			var hn:=_memo_height(query,next,state.mh);var dh:=absi(hc-hn)
			if dh>1 and not ((hc<0 or hn<0) and dh<=2): continue
			var step:=1.414 if d.x!=0 and d.y!=0 else 1.0
			var cost:=float(state.g[current])+step*(WATER_COST if hn<0 else 1.0)
			if cost<float(state.g.get(next,1e12)):
				state.came[next]=current;state.g[next]=cost
				_heap_push(heap_f,heap_c,cost+absi(state.goal.x-next.x)+absi(state.goal.y-next.y),next)
		if processed>=32 or Time.get_ticks_usec()-started>=budget_us: break
	if heap_c.is_empty() or state.guard>=1400: state.done=true
