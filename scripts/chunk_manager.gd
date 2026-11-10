extends Node3D
## Бесконечный чанковый мир (Явь или Сон), v0.7: 30 уровней вниз + бедрок (y=-31), пещеры со входами,
## гнёзда Анаконды (в пещерах и закрытые купола), текучая вода (клеточный автомат как в Minecraft).
## Оптимизация: каждый чанк = 1 общий меш террейна (вершинные цвета, скрытые грани не рисуются)
## + 1 меш воды + 1 StaticBody3D с коробками коллизии без отдельных узлов.
## Чанки догружаются постепенно (бюджет времени на кадр), радиус — из настроек.

@export var is_dream_layer: bool = false
@export var chunk_size: int = 16
@export var load_radius: int = 2
@export var unload_radius: int = 3
@export var block_size: float = 1.0
## Меню: игнорировать настройки и GameState (панорама).
@export var panorama_mode: bool = false

const COLOR_WAKE := Color(0.55, 0.62, 0.48)
const COLOR_WAKE_BUMP := Color(0.48, 0.55, 0.40)
const COLOR_DREAM := Color(0.28, 0.24, 0.42)
const COLOR_DREAM_BUMP := Color(0.42, 0.35, 0.58)

var _loaded: Dictionary = {} # Vector2i -> Node3D
var _solid_by_chunk: Dictionary = {} # Vector2i -> {Vector3i world cell: kind}
var _player: Node3D = null
var _seed: int = 1337
var _tick: float = 0.0
var _lakes_by_chunk: Dictionary = {} # Vector2i -> Array[Vector2i] local cells
var _lake_world_cells: Dictionary = {} # Vector2i world XZ -> true
var _ruin_centers: Dictionary = {} # Vector2i -> Vector3
var _wall_world_cells: Dictionary = {} # Vector2i world XZ -> true
var _pending: Array[Vector2i] = []
var _center: Vector2i = Vector2i(999999, 999999)
var _has_seed: bool = false

const LAKE_DEPTH := 1.0
const LAKE_SURFACE_Y := -0.08
const FIELD_REAGENT_RATE := 0.2
const RUIN_HASH_THRESHOLD := 0.95
const RUIN_CLUSTER_TARGET := 3
const HILL_MAX := 6
const FRAME_BUDGET_USEC := 4000

static var _mat_cache: Dictionary = {}
const BlockTex := preload("res://scripts/block_tex.gd")
const TREE_SAFE_RADIUS := 6.0
const LEAF_DECAY_MIN := 0.6
const LEAF_DECAY_SPREAD := 9.0
var _trees_by_chunk: Dictionary = {} # Vector2i -> Array[{logs: Array[Vector3i], leaves: Array[Vector3i]}]
var _walls_by_chunk: Dictionary = {} # Vector2i -> Array[Vector2i] (стены руин + стволы — для навигации)
var _decay_queue: Dictionary = {} # Vector3i leaf -> время распада (сек, _clock)
var _clock: float = 0.0
var _dirty_chunks: Dictionary = {}
var _dirty_t: float = 0.0
static var _reagent_script: GDScript = null


func _ready() -> void:
	add_to_group("chunk_manager")
	set_meta("is_dream", is_dream_layer)
	if panorama_mode:
		return
	if GameState and GameState.has_signal("world_changed"):
		if not GameState.world_changed.is_connected(_on_world_changed):
			GameState.world_changed.connect(_on_world_changed)
	if not GameState.terrain_cell_changed.is_connected(_terrain_edited):
		GameState.terrain_cell_changed.connect(_terrain_edited)
	if not is_dream_layer and GameState.has_signal("terrain_cell_changed"):
		if not GameState.terrain_cell_changed.is_connected(water_notify):
			GameState.terrain_cell_changed.connect(water_notify)
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets and gsets.has_signal("settings_changed"):
		gsets.settings_changed.connect(_on_settings_changed)
		_apply_radius(int(gsets.render_distance))


func _on_settings_changed() -> void:
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		_apply_radius(int(gsets.render_distance))
		_center = Vector2i(999999, 999999)


func _apply_radius(r: int) -> void:
	load_radius = clampi(r, 1, 12)
	unload_radius = load_radius + 1


func setup(player: Node3D, world_seed: int = 1337) -> void:
	_player = player
	if _has_seed and world_seed != _seed:
		clear_all()
	if world_seed != _seed or not _has_seed:
		_lake_plan_cache.clear()
		_cave_sys_cache.clear()
		_carve_cache.clear()
		_nest_cache.clear()
	_seed = world_seed
	_has_seed = true
	_center = Vector2i(999999, 999999)
	# Сразу (синхронно) — только чанки вокруг игрока, остальное догрузится по кадрам.
	if panorama_mode or _physics_active():
		var c := world_to_chunk(_player.global_position)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				ensure_chunk_loaded(Vector2i(c.x + dx, c.y + dz))
		_update_chunks(true)


func clear_all() -> void:
	_generation_epoch += 1
	_wait_jobs(false)
	for key in _loaded.keys():
		_unload_chunk(key)
	_pending.clear()


func get_loaded_count() -> int:
	return _loaded.size()


func get_pending_count() -> int:
	return _pending.size()+_jobs.size()


func world_to_chunk(pos: Vector3) -> Vector2i:
	var cx := floori(pos.x / float(chunk_size))
	var cz := floori(pos.z / float(chunk_size))
	return Vector2i(cx, cz)


func chunk_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)


func height_at(wx: int, wz: int) -> int:
	## Редкие холмы, v0.7 — до 6 уровней (чуть выше). Зависит от сида мира.
	if absi(wx) <= 14 and absi(wz) <= 14:
		return 0
	if _is_settlement(world_to_chunk(Vector3(wx, 0, wz))):
		return 0
	var n := _value_noise(float(wx) * 0.07, float(wz) * 0.07)
	if n > 0.93:
		return 6
	if n > 0.88:
		return 5
	if n > 0.82:
		return 4
	if n > 0.75:
		return 3
	if n > 0.67:
		return 2
	if n > 0.58:
		return 1
	return 0


func walk_height_at(wx: int, wz: int) -> int:
	## Высота для навигации: генерируемый холм минус снятые клетки сверху.
	var h := height_at(wx, wz)
	while h > 0 and (is_cell_removed(wx, h - 1, wz) or is_carved(Vector3i(wx, h - 1, wz))):
		h -= 1
	return h


func is_cell_removed(wx: int, y: int, wz: int) -> bool:
	if panorama_mode: return false
	if is_dream_layer: return GameState.removed_dream_terrain.has(Vector3i(wx,y,wz))
	if GameState and GameState.has_method("is_terrain_removed"):
		return bool(GameState.is_terrain_removed(Vector3i(wx, y, wz)))
	return false


func rebuild_chunk(coord: Vector2i) -> void:
	if _loaded.has(coord):
		_unload_chunk(coord)
	_load_chunk(coord)


func rebuild_chunk_at_world(wx: int, wz: int) -> void:
	## v0.7: грани подземных клеток рисует чанк воздушной клетки — на границе чанка пересобираем и соседа.
	var c := world_to_chunk(Vector3(float(wx), 0.0, float(wz)))
	rebuild_chunk(c)
	var lx := wx - c.x * chunk_size
	var lz := wz - c.y * chunk_size
	if lx == 0 and _loaded.has(c + Vector2i(-1, 0)):
		rebuild_chunk(c + Vector2i(-1, 0))
	if lx == chunk_size - 1 and _loaded.has(c + Vector2i(1, 0)):
		rebuild_chunk(c + Vector2i(1, 0))
	if lz == 0 and _loaded.has(c + Vector2i(0, -1)):
		rebuild_chunk(c + Vector2i(0, -1))
	if lz == chunk_size - 1 and _loaded.has(c + Vector2i(0, 1)):
		rebuild_chunk(c + Vector2i(0, 1))


func terrain_kind_at(cell: Vector3i) -> String:
	## «hill» / «ruin» / «ground» / «stone» / «bedrock» / «nest» / «egg» / "" — что за клетка террейна (для кирки).
	var coord := world_to_chunk(Vector3(cell.x, 0, cell.z))
	if _solid_by_chunk.has(coord):
		var d: Dictionary = _solid_by_chunk[coord]
		if d.has(cell):
			return str(d[cell])
	if cell.y < 0 and not is_dream_layer:
		if cell.y < BEDROCK_Y:
			return ""
		if cell.y == BEDROCK_Y:
			return "bedrock"
		var ek := _extra_solid_kind(cell)
		if ek != "":
			return "" if is_cell_removed(cell.x, cell.y, cell.z) else ek
		if _ug_solid(cell):
			return depth_kind(cell.y)
		return ""
	if cell.y == -1 and _loaded.has(coord) and not is_world_in_lake(Vector3(cell.x + 0.5, 0, cell.z + 0.5)):
		if not is_cell_removed(cell.x, -1, cell.z):
			return "ground"
	return ""


func has_terrain_visual(cell: Vector3i) -> bool:
	var coord := world_to_chunk(Vector3(cell.x, 0, cell.z))
	if not _solid_by_chunk.has(coord):
		return false
	return (_solid_by_chunk[coord] as Dictionary).has(cell)


func find_first_terrain(kind: String) -> Vector3i:
	for key in _solid_by_chunk.keys():
		var d: Dictionary = _solid_by_chunk[key]
		for c in d.keys():
			if str(d[c]) == kind:
				return c
	return Vector3i(0, -999, 0)


func mine_terrain_at(cell: Vector3i, kind: String = "") -> bool:
	var k := kind
	if cell.y <= BEDROCK_Y or k == "bedrock":
		return false
	if k == "":
		k = terrain_kind_at(cell)
		if k == "bedrock":
			return false
		if k == "":
			if cell.y < 0:
				k = depth_kind(cell.y)
			elif height_at(cell.x, cell.z) > cell.y:
				k = "hill"
			else:
				k = "ruin"
	if GameState and GameState.has_method("remove_terrain_cell"):
		if not GameState.remove_terrain_cell(cell, k):
			return false
	else:
		return false
	rebuild_chunk_at_world(cell.x, cell.z)
	return true


func ray_query_terrain(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit == null or hit.is_empty():
		return {}
	var p: Vector3 = hit.position - hit.normal * 0.05
	if hit.normal.length_squared() < 0.01:
		p = hit.position + (to - from).normalized() * 0.05
	hit["cell"] = Vector3i(floori(p.x), floori(p.y), floori(p.z))
	hit["kind"] = terrain_kind_at(hit["cell"])
	return hit


func is_world_wall(wx: int, wz: int) -> bool:
	return _wall_world_cells.has(Vector2i(wx, wz))


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# Сон — только пока мы во сне (экономия). Явь — всегда.
	if not panorama_mode and is_dream_layer and not GameState.is_dream():
		return
	_tick += delta
	_clock += delta
	if not _decay_queue.is_empty() or not _dirty_chunks.is_empty():
		_process_leaf_decay(delta)
	if _tick >= 0.2:
		_tick = 0.0
		_update_chunks(false)
	_drain_pending()
	if not is_dream_layer and not panorama_mode:
		_water_process(delta)


func _drain_legacy() -> void:
	if _pending.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var built := 0
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if _loaded.has(c):
			continue
		_load_chunk_legacy(c)
		built += 1
		if Time.get_ticks_usec() - t0 > FRAME_BUDGET_USEC:
			break


func _drain_pending() -> void:
	if legacy_generation:
		_drain_legacy()
		return
	_poll_jobs(1)
	while _jobs.size() < MAX_CHUNK_JOBS and not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not _loaded.has(c) and not _jobs.has(c):
			_queue_job(c)


func _update_chunks(force: bool) -> void:
	if _player == null:
		return
	var center := world_to_chunk(_player.global_position)
	if center == _center and not force:
		return
	_center = center
	var to_unload: Array[Vector2i] = []
	for key in _loaded.keys():
		var c: Vector2i = key
		var dist := maxi(absi(c.x - center.x), absi(c.y - center.y))
		if dist > unload_radius:
			to_unload.append(c)
	for c2 in to_unload:
		_unload_chunk(c2)
	_pending.clear()
	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			# Nearest possible distance from ANY point in the current chunk to this chunk.
			# Using centre-to-centre distance incorrectly omitted diagonals near chunk edges.
			var gap_x := maxi(absi(dx)-1,0)*chunk_size
			var gap_z := maxi(absi(dz)-1,0)*chunk_size
			if circular_loading and gap_x*gap_x+gap_z*gap_z > pow(maxf(12.0,load_radius*16.0-8.0),2): continue
			var c3 := Vector2i(center.x + dx, center.y + dz)
			if not _loaded.has(c3):
				_pending.append(c3)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())


func load_all_pending() -> void:
	_wait_jobs(true)
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not _loaded.has(c):
			_load_chunk(c)


func chunk_has_lake(coord: Vector2i) -> bool:
	if _is_settlement(coord):
		return false
	return maxi(absi(coord.x), absi(coord.y)) >= 1 and _chunk_hash(coord, 11) > 0.82


func chunk_has_ruin(coord: Vector2i) -> bool:
	if _is_settlement(coord):
		return true
	return maxi(absi(coord.x), absi(coord.y)) >= 1 and _chunk_hash(coord, 29) > RUIN_HASH_THRESHOLD


func is_world_in_lake(pos: Vector3) -> bool:
	var key := Vector2i(floori(pos.x), floori(pos.z))
	return _lake_world_cells.has(key)


func count_loaded_lakes() -> int:
	return _lakes_by_chunk.size()


func count_loaded_ruins() -> int:
	return _ruin_centers.size()


func count_loaded_reagents() -> int:
	var n := 0
	for key in _loaded.keys():
		var node: Node = _loaded[key]
		if not is_instance_valid(node):
			continue
		n += _count_named_group(node, "reagent")
	return n


func get_any_lake_sample_point() -> Vector3:
	for key in _lake_world_cells.keys():
		var c: Vector2i = key
		return Vector3(float(c.x) + 0.5, -LAKE_DEPTH * 0.5, float(c.y) + 0.5)
	return Vector3.ZERO


func count_reagents_in_chunk(coord: Vector2i) -> int:
	if not _loaded.has(coord):
		return 0
	return _count_named_group(_loaded[coord], "reagent")


func lake_cell_count(coord: Vector2i) -> int:
	if not _lakes_by_chunk.has(coord):
		return 0
	var cells: Array = _lakes_by_chunk[coord]
	return cells.size()


func lake_bbox_area(coord: Vector2i) -> int:
	if not _lakes_by_chunk.has(coord):
		return 0
	var cells: Array = _lakes_by_chunk[coord]
	if cells.is_empty():
		return 0
	var min_x := 999
	var max_x := -999
	var min_z := 999
	var max_z := -999
	for raw in cells:
		var c: Vector2i = raw
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
	return (max_x - min_x + 1) * (max_z - min_z + 1)


func ensure_chunk_loaded(coord: Vector2i) -> void:
	if not _loaded.has(coord):
		_load_chunk(coord)


func _count_named_group(node: Node, group: String) -> int:
	var n := 1 if node.is_in_group(group) else 0
	for ch in node.get_children():
		n += _count_named_group(ch, group)
	return n


func _unload_chunk(coord: Vector2i) -> void:
	if not _loaded.has(coord):
		return
	var node: Node = _loaded[coord]
	_loaded.erase(coord)
	_solid_by_chunk.erase(coord)
	if _lakes_by_chunk.has(coord):
		for raw in _lakes_by_chunk[coord]:
			var local: Vector2i = raw
			_lake_world_cells.erase(Vector2i(coord.x * chunk_size + local.x, coord.y * chunk_size + local.y))
		_lakes_by_chunk.erase(coord)
	if _walls_by_chunk.has(coord):
		for w in _walls_by_chunk[coord]:
			_wall_world_cells.erase(w)
		_walls_by_chunk.erase(coord)
	_ruin_centers.erase(coord)
	_trees_by_chunk.erase(coord)
	_water_unload_chunk(coord)
	if _carve_cache.size() > 600:
		_carve_cache.clear()
		_nest_cache.clear()
	if is_instance_valid(node):
		node.queue_free()


# ---------------------------------------------------------------- генерация

func terrain_signature(radius_chunks: int = 4) -> int:
	## Хеш генерации (холмы, озёра, руины, реагенты) — для проверки детерминизма сида.
	var acc := PackedInt64Array()
	for cx in range(-radius_chunks, radius_chunks + 1):
		for cz in range(-radius_chunks, radius_chunks + 1):
			var coord := Vector2i(cx, cz)
			acc.append(1 if chunk_has_lake(coord) else 0)
			acc.append(1 if chunk_has_ruin(coord) else 0)
			acc.append(_plan_lake(coord).size())
			for lx in range(0, chunk_size, 3):
				for lz in range(0, chunk_size, 3):
					acc.append(height_at(coord.x * chunk_size + lx, coord.y * chunk_size + lz))
	return hash(acc)


func _load_chunk_legacy(coord: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root.position = chunk_origin(coord)
	add_child(root)

	var occupied: Dictionary = {} # Vector2i local -> String tag
	var solids: Dictionary = {}   # Vector3i world -> kind (кубы холмов/руин)
	var lake_cells := _plan_lake(coord)
	if not lake_cells.is_empty():
		_register_lake(coord, lake_cells, occupied)
	if chunk_has_ruin(coord):
		_plan_ruin(coord, occupied, solids)
	_add_reagents(root, coord, occupied)
	_plan_hills(coord, occupied, solids)
	if not is_dream_layer:
		_plan_trees(coord, occupied, solids)
	_plan_nest_blocks(coord, solids)
	_solid_by_chunk[coord] = solids
	_build_chunk_geometry(root, coord, lake_cells, solids)
	var fresh := not _loaded.has(coord)
	_loaded[coord] = root
	if not panorama_mode:
		_sync_physics_tree(root, _physics_active())
		_check_orphan_leaves(coord)
		if not is_dream_layer:
			_water_on_chunk_loaded(coord, lake_cells, fresh)


func _value_noise(x: float, z: float) -> float:
	## Дешёвый value-noise 0..1 → возвращаем -1..1.
	var x0 := floori(x)
	var z0 := floori(z)
	var fx := x - float(x0)
	var fz := z - float(z0)
	var v00 := _hash01(x0, z0)
	var v10 := _hash01(x0 + 1, z0)
	var v01 := _hash01(x0, z0 + 1)
	var v11 := _hash01(x0 + 1, z0 + 1)
	var ix0 := lerpf(v00, v10, _smooth(fx))
	var ix1 := lerpf(v01, v11, _smooth(fx))
	return lerpf(ix0, ix1, _smooth(fz)) * 2.0 - 1.0


func _hash01(x: int, z: int) -> float:
	var n := x * 374761393 + z * 668265263 + _seed * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / float(0x7fffffff)


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _chunk_hash(coord: Vector2i, salt: int = 0) -> float:
	return _hash01(coord.x * 131 + salt, coord.y * 173 + salt * 7)


func _plan_lake(coord: Vector2i) -> Dictionary:
	var cells := {}
	if not chunk_has_lake(coord):
		return cells
	var cx := 4 + int(_hash01(coord.x, coord.y + 50) * 8.0)
	var cz := 4 + int(_hash01(coord.x + 50, coord.y) * 8.0)
	var radius := 2.8 + _hash01(coord.x, 99) * 4.4
	var stretch_x := 0.72 + _hash01(coord.x + 3, coord.y + 11) * 0.75
	var stretch_z := 0.72 + _hash01(coord.x + 11, coord.y + 3) * 0.75
	cx = clampi(cx, 3, chunk_size - 4)
	cz = clampi(cz, 3, chunk_size - 4)
	for lx in range(chunk_size):
		for lz in range(chunk_size):
			var dx := (float(lx) - float(cx)) / stretch_x
			var dz := (float(lz) - float(cz)) / stretch_z
			var dist := sqrt(dx * dx + dz * dz)
			var n := _hash01(coord.x * 40 + lx, coord.y * 40 + lz)
			var edge := radius * (0.58 + 0.62 * n)
			if dist < edge:
				cells[Vector2i(lx, lz)] = true
	if cells.size() < 6:
		for i in range(-1, 2):
			for j in range(-1, 2):
				cells[Vector2i(clampi(cx + i, 1, chunk_size - 2), clampi(cz + j, 1, chunk_size - 2))] = true
	var flat := {}
	for key in cells.keys():
		var cell: Vector2i = key
		var wx := coord.x * chunk_size + cell.x
		var wz := coord.y * chunk_size + cell.y
		if height_at(wx, wz) == 0:
			flat[cell] = true
	if flat.size() < 6:
		return {}
	return flat


func _ground_tag(coord: Vector2i, lx: int, lz: int, lake_cells: Dictionary) -> String:
	if lake_cells.has(Vector2i(lx, lz)):
		return "lake"
	var wx := coord.x * chunk_size + lx
	var wz := coord.y * chunk_size + lz
	if is_cell_removed(wx, -1, wz):
		return "pit"
	return "ground"


func _terrain_material() -> StandardMaterial3D:
	var key := "terrain"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_mat_cache[key] = mat
	return mat


func _water_material() -> StandardMaterial3D:
	var key := "water_dream" if is_dream_layer else "water_wake"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	if is_dream_layer:
		mat.albedo_color = Color(0.22, 0.18, 0.48, 0.46)
	else:
		mat.albedo_color = Color(0.20, 0.42, 0.66, 0.46)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.roughness = 0.38
	mat.metallic = 0.04
	_mat_cache[key] = mat
	return mat


func _register_lake(coord: Vector2i, lake_cells: Dictionary, occupied: Dictionary) -> void:
	var locals: Array[Vector2i] = []
	for key in lake_cells.keys():
		var cell: Vector2i = key
		occupied[cell] = "lake"
		locals.append(cell)
		_lake_world_cells[Vector2i(coord.x * chunk_size + cell.x, coord.y * chunk_size + cell.y)] = true
	_lakes_by_chunk[coord] = locals


const SETTLEMENT_THRESHOLD := 0.999
const DEV_SETTLEMENT := Vector2i(2, 1)

func _is_settlement(coord: Vector2i) -> bool:
	if is_dream_layer or maxi(absi(coord.x), absi(coord.y)) < 2:
		return false
	return (_seed == GameState.DEV_SEED and coord == DEV_SETTLEMENT) or _chunk_hash(coord, 8127) > SETTLEMENT_THRESHOLD

func ruin_plan(coord: Vector2i) -> Array:
	var rng := _rng_for(coord, 8421)
	var out: Array = []
	if _is_settlement(coord):
		var count := 3 + rng.randi_range(0, 2)
		for i in range(count):
			out.append({"x": 1 + (i % 3) * 5, "z": 1 + (i / 3) * 8, "w": rng.randi_range(3, 4), "d": rng.randi_range(4, 6), "h": 6 if i % 2 == 0 else 3, "shape": i % 2})
	else:
		# Крупная форма выпадает гораздо реже маленькой.
		var roll := rng.randf()
		var w := 10 if roll > 0.96 else (7 if roll > 0.80 else rng.randi_range(4, 5))
		out.append({"x": rng.randi_range(1, 15-w), "z": 2, "w": w, "d": rng.randi_range(4, mini(w+1, 10)), "h": 6 if roll > 0.96 else rng.randi_range(2, 4), "shape": rng.randi_range(0, 2)})
	return out

func _plan_ruin(coord: Vector2i, occupied: Dictionary, solids: Dictionary) -> void:
	_ruin_centers[coord] = chunk_origin(coord) + Vector3(8, 0, 8)
	for house in ruin_plan(coord):
		var ox := int(house.x)
		var oz := int(house.z)
		var w := int(house.w)
		var d := int(house.d)
		for lx in range(ox, mini(16, ox+w)):
			for lz in range(oz, mini(16, oz+d)):
				var wall := lx == ox or lx == ox+w-1 or lz == oz or lz == oz+d-1
				var door := lz == oz and lx == ox + w/2
				var wp := Vector3i(coord.x*16+lx, 0, coord.y*16+lz)
				occupied[Vector2i(lx,lz)] = "door" if door else ("wall" if wall else "ruin_floor")
				for y in range(int(house.h)):
					var c := wp + Vector3i(0,y,0)
					var floor2 := y == 3 and int(house.h) > 4 and not (lx == ox+1 and lz == oz+1)
					if not wall and not floor2:
						continue
					if door and y < 2:
						continue
					if int(house.shape) == 1 and lx >= ox+w-2 and lz >= oz+d-2:
						continue
					if y > 1 and _hash01(c.x+y*23,c.z-y*17) > 0.78:
						continue
					if not is_cell_removed(c.x,c.y,c.z):
						solids[c] = "mossy_ruin" if _hash01(c.x+y*71,c.z+y*37) < 0.15 else "ruin"
				if wall and not door:
					_add_wall(coord, Vector2i(wp.x,wp.z))


func _plan_hills(coord: Vector2i, occupied: Dictionary, solids: Dictionary) -> void:
	for lx in range(chunk_size):
		for lz in range(chunk_size):
			var cell := Vector2i(lx, lz)
			if occupied.has(cell):
				var tag := str(occupied[cell])
				if tag == "lake" or tag == "wall" or tag == "ruin_floor" or tag == "door" or tag == "gap":
					continue
			var wx := coord.x * chunk_size + lx
			var wz := coord.y * chunk_size + lz
			var h := height_at(wx, wz)
			if h <= 0:
				continue
			occupied[cell] = occupied.get(cell, "hill")
			for y in range(h):
				if is_cell_removed(wx, y, wz) or is_carved(Vector3i(wx, y, wz)):
					continue
				solids[Vector3i(wx, y, wz)] = "stone" if y < height_at(wx, wz) - 2 else ("hill" if y == height_at(wx,wz)-1 else "dirt")


func _add_wall(coord: Vector2i, w: Vector2i) -> void:
	_wall_world_cells[w] = true
	if not _walls_by_chunk.has(coord):
		_walls_by_chunk[coord] = []
	(_walls_by_chunk[coord] as Array).append(w)


# ---------------------------------------------------------------- деревья (v0.6)

func tree_plan(coord: Vector2i) -> Array:
	## Детерминированные позиции деревьев чанка (зависят от сида): [{base: Vector2i local, h: int}].
	## Деревья целиком внутри чанка (ствол 3..12 + крона r=2) и не ближе 5 клеток друг к другу.
	var out: Array = []
	var density := (_value_noise(float(coord.x) * 0.31 + 100.0, float(coord.y) * 0.31 - 50.0) + 1.0) * 0.5
	var tries := 2 + int(density * 7.0)
	for i in range(tries):
		var lx := 3 + int(_hash01(coord.x * 71 + i * 13, coord.y * 37 - i * 7) * 10.0)
		var lz := 3 + int(_hash01(coord.x * 19 - i * 5, coord.y * 83 + i * 29) * 10.0)
		lx = clampi(lx, 3, 12)
		lz = clampi(lz, 3, 12)
		var chance := _hash01(coord.x * 7 + i * 101, coord.y * 11 - i * 53)
		if chance > 0.18 + density * 0.62:
			continue
		var ok := true
		for t in out:
			var b: Vector2i = t["base"]
			if absi(b.x - lx) < 5 and absi(b.y - lz) < 5:
				ok = false
				break
		if not ok:
			continue
		var h := 4 + (1 if _hash01(coord.x + i * 3, coord.y * 2 + i) > 0.55 else 0)
		out.append({"base": Vector2i(lx, lz), "h": h, "salt": i})
	return out


func _plan_trees(coord: Vector2i, occupied: Dictionary, solids: Dictionary) -> void:
	var trees: Array = []
	for t in tree_plan(coord):
		var b: Vector2i = t["base"]
		var wx := coord.x * chunk_size + b.x
		var wz := coord.y * chunk_size + b.y
		if Vector2(float(wx), float(wz)).length() < TREE_SAFE_RADIUS:
			continue
		if occupied.has(b) or height_at(wx, wz) != 0:
			continue
		if is_cell_removed(wx, -1, wz) or is_carved(Vector3i(wx, -1, wz)) or is_carved(Vector3i(wx, -2, wz)):
			continue
		var h: int = int(t["h"])
		var logs: Array = []
		var leaves: Array = []
		var trunk_left := false
		for y in range(h):
			var lc := Vector3i(wx, y, wz)
			logs.append(lc)
			if is_cell_removed(wx, y, wz):
				continue
			solids[lc] = "log"
			if y == 0:
				trunk_left = true
		if trunk_left:
			_add_wall(coord, Vector2i(wx, wz))
		occupied[b] = "tree"
		for y2 in range(h - 2, h + 2):
			var r := 2 if y2 < h else 1
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if y2 >= h and r == 1 and y2 == h + 1 and absi(dx) + absi(dz) > 1:
						continue
					if r == 2 and absi(dx) == 2 and absi(dz) == 2:
						if _hash01(wx * 13 + dx + y2 * 7, wz * 17 + dz) > 0.35:
							continue
					var c := Vector3i(wx + dx, y2, wz + dz)
					if solids.has(c) and str(solids[c]) == "log":
						continue
					if dx == 0 and dz == 0 and y2 < h:
						continue
					leaves.append(c)
					if is_cell_removed(c.x, c.y, c.z):
						continue
					if not solids.has(c):
						solids[c] = "leaves"
		trees.append({"logs": logs, "leaves": leaves})
	_trees_by_chunk[coord] = trees


func count_loaded_trees() -> int:
	var n := 0
	for k in _trees_by_chunk.keys():
		n += (_trees_by_chunk[k] as Array).size()
	return n


func get_trees(coord: Vector2i) -> Array:
	return _trees_by_chunk.get(coord, [])


func find_first_tree() -> Dictionary:
	## Ближайшее к центру дерево среди загруженных чанков.
	var best: Dictionary = {}
	var best_d := INF
	for k in _trees_by_chunk.keys():
		for t in _trees_by_chunk[k]:
			var base: Vector3i = (t["logs"] as Array)[0]
			var d := Vector2(base.x, base.z).length()
			if d < best_d:
				best_d = d
				best = t
	return best


func _tree_has_logs(t: Dictionary) -> bool:
	for raw in t["logs"]:
		var c: Vector3i = raw
		if not is_cell_removed(c.x, c.y, c.z):
			return true
	return false


func _check_orphan_leaves(coord: Vector2i) -> void:
	## Все брёвна дерева сломаны → его листва постепенно опадает (как в Minecraft).
	if is_dream_layer or not _trees_by_chunk.has(coord):
		return
	for t in _trees_by_chunk[coord]:
		if _tree_has_logs(t):
			continue
		var n := 0
		for raw in t["leaves"]:
			var c: Vector3i = raw
			if is_cell_removed(c.x, c.y, c.z) or _decay_queue.has(c):
				continue
			n += 1
			_decay_queue[c] = _clock + LEAF_DECAY_MIN + randf() * LEAF_DECAY_SPREAD
	

var last_absorbed_blocks: int = 0


func absorb_trees_near(center: Vector3, radius: float) -> int:
	## Мать блоков расчищает арену: брёвна деревьев рядом исчезают, листва затем опадает.
	if is_dream_layer:
		return 0
	var n := 0
	last_absorbed_blocks = 0
	var touched: Dictionary = {}
	for k in _trees_by_chunk.keys():
		for t in _trees_by_chunk[k]:
			var base: Vector3i = (t["logs"] as Array)[0]
			if Vector2(float(base.x) + 0.5 - center.x, float(base.z) + 0.5 - center.z).length() > radius:
				continue
			if not _tree_has_logs(t):
				continue
			for raw in t["logs"]:
				var c: Vector3i = raw
				if GameState.remove_terrain_cell_silent(c, "log"):
					last_absorbed_blocks += 1
			touched[k] = true
			n += 1
	for k2 in touched.keys():
		if _loaded.has(k2):
			rebuild_chunk(k2)
		_check_orphan_leaves(k2)
	return n


func pending_leaf_decay() -> int:
	return _decay_queue.size()


func _process_leaf_decay(delta: float) -> void:
	var due: Array = []
	for k in _decay_queue.keys():
		if float(_decay_queue[k]) <= _clock:
			due.append(k)
	for raw in due:
		var c: Vector3i = raw
		_decay_queue.erase(c)
		if GameState.has_method("remove_terrain_cell_silent"):
			GameState.remove_terrain_cell_silent(c, "leaves")
		_dirty_chunks[world_to_chunk(Vector3(c.x, 0, c.z))] = true
		if randf() < 0.06:
			_spawn_pickup(c, "leaves")
	_dirty_t -= delta
	if _dirty_t <= 0.0 and not _dirty_chunks.is_empty():
		_dirty_t = 0.25
		for ch in _dirty_chunks.keys():
			if _loaded.has(ch):
				rebuild_chunk(ch)
		_dirty_chunks.clear()


func force_leaf_decay_tick(seconds: float) -> void:
	## Для тестов: прокрутить время распада.
	_clock += seconds
	_process_leaf_decay(1.0)
	_dirty_t = 0.0
	_process_leaf_decay(1.0)


func _spawn_pickup(c: Vector3i, kind: String) -> void:
	var host := get_parent()
	if host == null or panorama_mode:
		return
	var script: GDScript = load("res://scripts/block_pickup.gd")
	var drop: CharacterBody3D = script.new()
	drop.configure(kind)
	drop.position = Vector3(float(c.x) + 0.5, maxf(float(c.y) * 0.0 + 0.55, 0.55), float(c.z) + 0.5)
	host.add_child(drop)


func _neighbor_solid(solids: Dictionary, c: Vector3i) -> bool:
	if solids.has(c):
		return true
	if c.y < 0:
		if is_dream_layer:
			return c.y == -1 and not _lake_world_cells.has(Vector2i(c.x, c.z))
		return _ug_solid(c)
	# Соседний чанк: холмы — чистая функция от сида (руины не касаются края чанка).
	var coord := world_to_chunk(Vector3(c.x, 0, c.z))
	if _solid_by_chunk.has(coord):
		return (_solid_by_chunk[coord] as Dictionary).has(c)
	return c.y < height_at(c.x, c.z) and not is_cell_removed(c.x, c.y, c.z) and not _world_is_lake_cell(c.x, c.z) and not is_carved(c)


const _FACES := [
	# normal, 4 corners (CCW снаружи) в единичном кубе
	[Vector3(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
	[Vector3(0, -1, 0), [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]],
	[Vector3(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]],
	[Vector3(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
]


func _emit_box(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, mn: Vector3, size: Vector3, col: Color, skip_mask: int) -> void:
	for fi in range(6):
		if skip_mask & (1 << fi):
			continue
		var f: Array = _FACES[fi]
		var n: Vector3 = f[0]
		var cs: Array = f[1]
		var shade := 1.0
		if n.y < -0.5:
			shade = 0.6
		elif absf(n.x) > 0.5:
			shade = 0.86
		elif absf(n.z) > 0.5:
			shade = 0.93
		var cc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		var p0: Vector3 = mn + (cs[0] as Vector3) * size
		var p1: Vector3 = mn + (cs[1] as Vector3) * size
		var p2: Vector3 = mn + (cs[2] as Vector3) * size
		var p3: Vector3 = mn + (cs[3] as Vector3) * size
		# Godot: передняя грань — по часовой стрелке при взгляде снаружи.
		verts.append_array([p0, p2, p1, p0, p3, p2])
		for _k in range(6):
			norms.append(n)
			cols.append(cc)


func _build_chunk_geometry(root: Node3D, coord: Vector2i, lake_cells: Dictionary, solids: Dictionary) -> void:
	## v0.6: пиксельные текстуры из атласа (BlockTex), UV в блоках, вершинный цвет = тень/оттенок.
	var st: Dictionary = BlockTex.new_stream()
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain_chunk", coord)
	root.add_child(body)
	var tint := 1.0 + 0.025 * float(posmod(coord.x * 3 + coord.y * 7, 5) - 2)
	var base_col := Color(tint, tint, tint)
	var ground_tiles: Array = BlockTex.faces_for("ground", is_dream_layer, true)
	var dirt_tiles: Array = BlockTex.faces_for("ground", is_dream_layer, false)
	var bed_tiles: Array = BlockTex.faces_for("sand") if not is_dream_layer else dirt_tiles
	if is_dream_layer or panorama_mode:
		# Сон/панорама: прежний тонкий пол (полосы вдоль X), глубины нет.
		for lz in range(chunk_size):
			var x := 0
			while x < chunk_size:
				var tag := _ground_tag(coord, x, lz, lake_cells)
				var x0 := x
				while x < chunk_size and _ground_tag(coord, x, lz, lake_cells) == tag:
					x += 1
				var width := x - x0
				var top_y := 0.0
				if tag == "lake":
					top_y = -LAKE_DEPTH
				elif tag == "pit":
					top_y = -1.0
				var thickness := 1.0 if top_y < -0.01 else (LAKE_DEPTH + 1.0)
				var mn := Vector3(float(x0), top_y - thickness, float(lz))
				var sz := Vector3(float(width), thickness, 1.0)
				if tag == "ground":
					BlockTex.emit_box(st, Vector3(float(x0), top_y - 1.0, float(lz)), Vector3(float(width), 1.0, 1.0), base_col, 1 << 3, ground_tiles)
					BlockTex.emit_box(st, mn, Vector3(float(width), thickness - 1.0, 1.0), base_col, (1 << 3) | (1 << 2), dirt_tiles)
				elif tag == "lake":
					BlockTex.emit_box(st, mn, sz, base_col.darkened(0.08), 1 << 3, bed_tiles)
				else:
					BlockTex.emit_box(st, mn, sz, base_col.darkened(0.1), 1 << 3, dirt_tiles)
				_add_box_shape(body, mn + sz * 0.5, sz)
	else:
		_build_underground(st, body, coord, lake_cells, base_col, ground_tiles)
	# Кубы холмов, руин, деревьев: рисуем только открытые грани.
	var origin := chunk_origin(coord)
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for key in solids.keys():
		var c: Vector3i = key
		var kind := str(solids[c])
		var mask := 0
		for fi in range(6):
			if _neighbor_solid(solids, c + dirs[fi]):
				mask |= 1 << fi
		if mask == 63:
			continue
		var noise := (_hash01(c.x * 7 + c.y * 13, c.z * 11 - c.y) - 0.5) * 0.10
		var col := Color(tint + noise, tint + noise, tint + noise)
		var variant := int(_hash01(c.x * 3 + c.y, c.z * 5 - c.y * 2) * 9.0)
		var exposed := not (mask & (1 << 2))
		if kind == "hill" and c.y < height_at(c.x, c.z) - 2:
			kind = "stone"
		elif kind == "nest" or kind == "egg":
			col = Color(1, 1, 1)
		var tiles: Array = BlockTex.faces_for(kind, is_dream_layer, exposed, variant)
		var mn := Vector3(c) - origin
		BlockTex.emit_box(st, mn, Vector3.ONE, col, mask, tiles)
	# Коллизия кубов: вертикальные колонны непрерывных клеток.
	var columns: Dictionary = {}
	for key2 in solids.keys():
		var c2: Vector3i = key2
		var ck := Vector2i(c2.x, c2.z)
		if not columns.has(ck):
			columns[ck] = []
		(columns[ck] as Array).append(c2.y)
	for ck2 in columns.keys():
		var ys: Array = columns[ck2]
		ys.sort()
		var i := 0
		while i < ys.size():
			var y0: int = ys[i]
			var y1: int = y0
			while i + 1 < ys.size() and int(ys[i + 1]) == y1 + 1:
				i += 1
				y1 = int(ys[i])
			i += 1
			var lp := Vector3(float(ck2.x) - origin.x, float(y0), float(ck2.y) - origin.z)
			var sz2 := Vector3(1.0, float(y1 - y0 + 1), 1.0)
			var oid := _add_box_shape(body, lp + sz2 * 0.5, sz2)
			if y0 < 0:
				body.set_meta("solid_owner_%d" % oid, true)
	if (st["v"] as PackedVector3Array).size() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "TerrainMesh"
		mi.mesh = BlockTex.stream_to_mesh(st)
		root.add_child(mi)
	if not lake_cells.is_empty():
		_build_water(root, lake_cells)


func _add_box_shape(body: StaticBody3D, center: Vector3, size: Vector3) -> int:
	var shape := BoxShape3D.new()
	shape.size = size
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, shape)
	body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, center))
	return owner_id


func _build_water(root: Node3D, lake_cells: Dictionary) -> void:
	## Вода — только горизонтальные квадраты (без боковых граней), один меш на чанк.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for key in lake_cells.keys():
		var c: Vector2i = key
		var y := LAKE_SURFACE_Y
		var p0 := Vector3(c.x, y, c.y)
		var p1 := Vector3(c.x + 1, y, c.y)
		var p2 := Vector3(c.x + 1, y, c.y + 1)
		var p3 := Vector3(c.x, y, c.y + 1)
		verts.append_array([p0, p1, p2, p0, p2, p3])
		for pp in [p0, p1, p2, p0, p2, p3]:
			uvs.append(Vector2(pp.x, pp.z))
		for _k in range(6):
			norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, BlockTex.water_material(is_dream_layer))
	var water := MeshInstance3D.new()
	water.name = "LakeWater"
	water.mesh = mesh
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)


func _add_reagents(root: Node3D, coord: Vector2i, occupied: Dictionary) -> void:
	if is_dream_layer:
		return
	var has_ruin := _ruin_centers.has(coord)
	if has_ruin:
		_add_ruin_reagent_cluster(root, coord, occupied)
		return
	var far := maxi(absi(coord.x), absi(coord.y)) >= 1
	if not far:
		return
	# Поле: 20% от прежней частоты, без гарантированного спавна.
	var attempts := 6
	var max_spawn := 1
	var spawned := 0
	var threshold := 0.42 * FIELD_REAGENT_RATE
	for i in range(attempts):
		if spawned >= max_spawn:
			break
		var lx := clampi(int(_hash01(coord.x * 13 + i * 17, coord.y * 19 + i * 23) * float(chunk_size)), 1, chunk_size - 2)
		var lz := clampi(int(_hash01(coord.x * 29 + i * 7, coord.y * 31 + i * 11) * float(chunk_size)), 1, chunk_size - 2)
		var chance := _hash01(coord.x + i * 3, coord.y - i * 5)
		if chance < threshold:
			continue
		if _try_spawn_reagent_at(root, coord, occupied, lx, lz, i + 2):
			spawned += 1


func _add_ruin_reagent_cluster(root: Node3D, coord: Vector2i, occupied: Dictionary) -> void:
	var center: Vector3 = _ruin_centers[coord]
	var spawned := 0
	var locals: Array[Vector2i] = []
	for lx in range(chunk_size):
		for lz in range(chunk_size):
			var key := Vector2i(lx, lz)
			var tag := str(occupied.get(key, ""))
			var wp := chunk_origin(coord) + Vector3(float(lx) + 0.5, 0.0, float(lz) + 0.5)
			var dist := Vector2(wp.x - center.x, wp.z - center.z).length()
			if tag == "ruin_floor" or tag == "door" or tag == "gap" or (dist <= 2.4 and tag != "wall" and tag != "lake"):
				locals.append(key)
	locals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := chunk_origin(coord) + Vector3(float(a.x), 0.0, float(a.y))
		var pb := chunk_origin(coord) + Vector3(float(b.x), 0.0, float(b.y))
		return pa.distance_to(center) < pb.distance_to(center)
	)
	var salt := 1
	for cell in locals:
		if spawned >= (13 if _is_settlement(coord) else RUIN_CLUSTER_TARGET):
			break
		var pick := _hash01(coord.x * 17 + cell.x + salt, coord.y * 13 + cell.y)
		if pick < 0.35 and spawned > 0:
			salt += 1
			continue
		if _try_spawn_reagent_at(root, coord, occupied, cell.x, cell.y, salt):
			spawned += 1
		salt += 1


func _try_spawn_reagent_at(root: Node3D, coord: Vector2i, occupied: Dictionary, lx: int, lz: int, salt: int) -> bool:
	var key := Vector2i(lx, lz)
	if occupied.has(key):
		var tag := str(occupied[key])
		if tag == "wall" or tag == "lake" or tag == "reagent":
			return false
	var wx := coord.x * chunk_size + lx
	var wz := coord.y * chunk_size + lz
	if absi(wx) <= 14 and absi(wz) <= 14:
		return false
	var h := height_at(wx, wz)
	var rid := "%d,%d,%d" % [wx, h, wz]
	if not panorama_mode and GameState.has_method("is_reagent_collected") and GameState.is_reagent_collected(rid):
		return false
	var type_id := 1 + int(_hash01(coord.x + lx * 3 + salt, coord.y + lz * 5) * 3.0)
	type_id = (1 + salt % 3) if _is_settlement(coord) else clampi(type_id, 1, 3)
	occupied[key] = "reagent"
	if _reagent_script == null:
		_reagent_script = load("res://scripts/reagent_node.gd")
	var node: StaticBody3D = _reagent_script.new()
	node.position = Vector3(float(lx) + 0.5, float(h) + 0.35, float(lz) + 0.5)
	if node.has_method("configure"):
		node.configure(type_id, rid, 1)
	else:
		node.set("reagent_type", type_id)
		node.set("world_id", rid)
	root.add_child(node)
	return true


var _lake_plan_cache: Dictionary = {}


func _world_is_lake_cell(wx: int, wz: int) -> bool:
	if _lake_world_cells.has(Vector2i(wx, wz)):
		return true
	var c := Vector2i(floori(float(wx) / float(chunk_size)), floori(float(wz) / float(chunk_size)))
	if not chunk_has_lake(c):
		return false
	if _lakes_by_chunk.has(c):
		return false
	if not _lake_plan_cache.has(c):
		if _lake_plan_cache.size() > 256:
			_lake_plan_cache.clear()
		_lake_plan_cache[c] = _plan_lake(c)
	return (_lake_plan_cache[c] as Dictionary).has(Vector2i(wx - c.x * chunk_size, wz - c.y * chunk_size))


func _on_world_changed(_is_dream: bool) -> void:
	_sync_all_physics()
	_center = Vector2i(999999, 999999)


func _physics_active() -> bool:
	if panorama_mode:
		return true
	return GameState.is_dream() == is_dream_layer


func _sync_all_physics() -> void:
	var on := _physics_active()
	for key in _loaded.keys():
		var node: Node = _loaded[key]
		if is_instance_valid(node):
			_sync_physics_tree(node, on)


func _sync_physics_tree(n: Node, on: bool) -> void:
	if n is CollisionObject3D:
		var co := n as CollisionObject3D
		if co.collision_layer != 0:
			co.set_meta("_saved_layer", co.collision_layer)
		if on:
			if co.has_meta("_saved_layer") and int(co.get_meta("_saved_layer")) != 0:
				co.collision_layer = int(co.get_meta("_saved_layer"))
		else:
			co.collision_layer = 0
	for ch in n.get_children():
		_sync_physics_tree(ch, on)


func collect_collision_issues() -> Array:
	## v0.5: коллизия и меш строятся из одного набора клеток. Проверяем, что каждая
	## твёрдая клетка покрыта коробкой коллизии, а каждая коробка — только твёрдыми клетками.
	var issues: Array = []
	for coord in _loaded.keys():
		var root: Node = _loaded[coord]
		if not is_instance_valid(root):
			continue
		var body := root.get_node_or_null("TerrainBody") as StaticBody3D
		if body == null:
			issues.append({"type": "missing_body", "chunk": coord})
			continue
		var solids: Dictionary = _solid_by_chunk.get(coord, {})
		var covered: Dictionary = {}
		var origin := chunk_origin(coord)
		for owner_id in body.get_shape_owners():
			var xf: Transform3D = body.shape_owner_get_transform(owner_id)
			var shp := body.shape_owner_get_shape(owner_id, 0) as BoxShape3D
			if shp == null:
				continue
			var mn: Vector3 = xf.origin - shp.size * 0.5 + origin
			if mn.y < -0.01 and not body.has_meta("solid_owner_%d" % owner_id):
				continue # пол / подземная толща
			for x in range(roundi(shp.size.x)):
				for y in range(roundi(shp.size.y)):
					for z in range(roundi(shp.size.z)):
						var c := Vector3i(roundi(mn.x) + x, roundi(mn.y) + y, roundi(mn.z) + z)
						if not solids.has(c):
							issues.append({"type": "invisible_collision", "cell": c})
						covered[c] = true
		for c2 in solids.keys():
			if not covered.has(c2):
				issues.append({"type": "no_collision", "cell": c2})
		if root.get_node_or_null("TerrainMesh") == null:
			issues.append({"type": "missing_mesh", "chunk": coord})
	return issues


func lake_water_is_planar() -> bool:
	for key in _loaded.keys():
		var node: Node = _loaded[key]
		if not is_instance_valid(node):
			continue
		var w := node.get_node_or_null("LakeWater") as MeshInstance3D
		if w == null:
			continue
		if w.mesh == null or w.mesh.get_aabb().size.y > 0.001:
			return false
	return true


func lake_has_no_hills(coord: Vector2i) -> bool:
	if not _lakes_by_chunk.has(coord):
		return true
	for raw in _lakes_by_chunk[coord]:
		var cell: Vector2i = raw
		var wx := coord.x * chunk_size + cell.x
		var wz := coord.y * chunk_size + cell.y
		if height_at(wx, wz) > 0:
			return false
	return true


func count_render_nodes() -> int:
	var n := 0
	for key in _loaded.keys():
		n += _count_all(_loaded[key])
	return n


func _count_all(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_all(ch)
	return c


# ================================================================ v0.7: глубина, пещеры, гнёзда, вода

const BEDROCK_Y := -31
const MIN_DIG_Y := -30
## Входы в пещеры — ~5% чанков (как руины). Глухие тоннели — ещё ~6%, их находят только копая.
const CAVE_ENTRANCE_THRESHOLD := 0.95
const CAVE_DEEP_THRESHOLD := 0.94
## Гнёзда Анаконды ≈ в 3 раза реже руин: доля входных пещер с гнездом + закрытые купола.
const CAVE_NEST_CHANCE := 0.22
const DOME_THRESHOLD := 0.9925
const CAVE_REACH_CHUNKS := 3
## Дев-сид: гарантированная пещера с гнездом у спавна (вход ~16 м, гнездо ~24 м).
const DEV_NEST_FLOOR := Vector3i(21, -8, 11)
const DEV_CAVE_PATH := [Vector3(16.5, 0.4, 2.5), Vector3(17.5, -1.2, 4.0), Vector3(19.0, -3.4, 5.8), Vector3(20.2, -5.4, 8.0), Vector3(21.2, -6.6, 10.2)]

var _cave_sys_cache: Dictionary = {}  # Vector2i src -> Array[system]
var _carve_cache: Dictionary = {}     # Vector2i -> Dictionary{Vector3i: true}
var _nest_cache: Dictionary = {}      # Vector2i -> Dictionary{Vector3i: "nest"/"egg"}


static func depth_kind(y: int) -> String:
	if y <= BEDROCK_Y:
		return "bedrock"
	if y >= -1:
		return "ground"
	if y > -6:
		return "dirt"
	return "stone" if y > -18 else "deep_stone"


func _caves_enabled() -> bool:
	return not is_dream_layer and not panorama_mode


func _dev_nest_enabled() -> bool:
	return _caves_enabled() and GameState != null and bool(GameState.dev_mode)


func _rng_for(src: Vector2i, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed, src.x, src.y, salt])
	return r


func cave_systems_from(src: Vector2i) -> Array:
	## Детерминированные (по сиду) пещерные системы, которые «начинаются» в чанке src.
	if _cave_sys_cache.has(src):
		return _cave_sys_cache[src]
	var out: Array = []
	if _caves_enabled():
		var near_spawn := maxi(absi(src.x), absi(src.y)) <= 1
		if src == Vector2i(1, 0) and _dev_nest_enabled():
			out.append(_gen_dev_cave())
		if not near_spawn:
			out.append_array(_gen_systems_for(src))
	_cave_sys_cache[src] = out
	return out


func _gen_systems_for(src: Vector2i) -> Array:
	var out: Array = []
	var blocked := chunk_has_lake(src) or chunk_has_ruin(src)
	if not blocked and _chunk_hash(src, 41) > CAVE_ENTRANCE_THRESHOLD:
		out.append(_gen_worm(src, true, _chunk_hash(src, 43) < CAVE_NEST_CHANCE))
	elif _chunk_hash(src, 53) > CAVE_DEEP_THRESHOLD:
		out.append(_gen_worm(src, false, false))
	if _chunk_hash(src, 47) > DOME_THRESHOLD:
		out.append(_gen_dome(src))
	return out


func _gen_worm(src: Vector2i, entrance: bool, with_nest: bool) -> Dictionary:
	var r := _rng_for(src, 7)
	var lx := r.randi_range(3, 12)
	var lz := r.randi_range(3, 12)
	var wx := src.x * chunk_size + lx
	var wz := src.y * chunk_size + lz
	var pos: Vector3
	if entrance:
		pos = Vector3(float(wx) + 0.5, float(height_at(wx, wz)) + 0.4, float(wz) + 0.5)
	else:
		pos = Vector3(float(wx) + 0.5, r.randf_range(-22.0, -8.0), float(wz) + 0.5)
	var yaw := r.randf() * TAU
	var pitch := -0.62 if entrance else r.randf_range(-0.15, 0.15)
	var target_y := r.randf_range(-22.0, -9.0)
	var steps := r.randi_range(28, 42)
	var shapes: Array = []
	for i in range(steps):
		var rad := r.randf_range(1.45, 2.1)
		if entrance and i < 3:
			rad = 1.7
		shapes.append({"t": "s", "c": pos, "r": rad})
		var dir := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
		pos += dir * 1.1
		yaw += r.randf_range(-0.32, 0.32)
		if pos.y > target_y + 1.0:
			pitch = lerpf(pitch, -0.62, 0.25)
		elif pos.y < target_y - 1.0:
			pitch = lerpf(pitch, 0.3, 0.25)
		else:
			pitch = lerpf(pitch, r.randf_range(-0.12, 0.12), 0.4)
		pos.y = clampf(pos.y, -25.0, 8.0)
	var sys := {"kind": "entrance" if entrance else "deep", "shapes": shapes, "entrance": (shapes[0] as Dictionary)["c"], "nest": {}, "src": src}
	if with_nest:
		_add_nest(sys, pos, "cave", 5.0)
	_finish_aabb(sys)
	return sys


func _gen_dome(src: Vector2i) -> Dictionary:
	## Закрытый купол: полость-полусфера с гнездом и яйцом, без связи с поверхностью. Находят, копая.
	var r := _rng_for(src, 13)
	var wx := src.x * chunk_size + r.randi_range(4, 11)
	var wz := src.y * chunk_size + r.randi_range(4, 11)
	var fy := r.randi_range(-24, -13)
	var sys := {"kind": "dome", "shapes": [], "entrance": Vector3.ZERO, "nest": {}, "src": src}
	_add_nest(sys, Vector3(float(wx) + 0.5, float(fy) + 1.0, float(wz) + 0.5), "dome", 6.5)
	_finish_aabb(sys)
	return sys


func _gen_dev_cave() -> Dictionary:
	var shapes: Array = []
	for i in range(DEV_CAVE_PATH.size() - 1):
		var a: Vector3 = DEV_CAVE_PATH[i]
		var b: Vector3 = DEV_CAVE_PATH[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.7)))
		for k in range(n):
			shapes.append({"t": "s", "c": a.lerp(b, float(k) / float(n)), "r": 1.75})
	var sys := {"kind": "entrance", "shapes": shapes, "entrance": DEV_CAVE_PATH[0], "nest": {}, "src": Vector2i(1, 0), "dev": true}
	_add_nest(sys, Vector3(float(DEV_NEST_FLOOR.x) + 0.5, float(DEV_NEST_FLOOR.y) + 1.0, float(DEV_NEST_FLOOR.z) + 0.5), "cave", 5.0)
	_finish_aabb(sys)
	return sys


func _add_nest(sys: Dictionary, at: Vector3, kind: String, radius: float) -> void:
	var fy := clampi(floori(at.y) - 1, -26, -6)
	var cx := floori(at.x)
	var cz := floori(at.z)
	var center := Vector3(float(cx) + 0.5, float(fy), float(cz) + 0.5)
	(sys["shapes"] as Array).append({"t": "dome", "c": center, "r": radius, "h": radius * 0.72})
	var egg := Vector3i(cx, fy + 1, cz)
	sys["nest"] = {"id": "nest:%d,%d,%d" % [egg.x, egg.y, egg.z], "egg": egg, "floor_y": fy, "center": center, "kind": kind, "radius": radius}


func _finish_aabb(sys: Dictionary) -> void:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for sh in sys["shapes"]:
		var c: Vector3 = sh["c"]
		var rr: float = float(sh["r"]) + 1.0
		mn = mn.min(c - Vector3(rr, rr, rr))
		mx = mx.max(c + Vector3(rr, rr, rr))
	sys["min"] = mn
	sys["max"] = mx


func _carve_allowed(c: Vector3i) -> bool:
	if c.y < MIN_DIG_Y + 1:
		return false
	if absi(c.x) <= 12 and absi(c.z) <= 12 and c.y >= -6:
		return false   # стартовая площадка и кровать — без провалов
	var ck := Vector2i(floori(float(c.x) / float(chunk_size)), floori(float(c.z) / float(chunk_size)))
	if c.y >= -3 and chunk_has_lake(ck):
		return false   # озёра не протекают в пещеры
	if c.y >= 0 and chunk_has_ruin(ck):
		return false
	return true


func _carved_cells(coord: Vector2i) -> Dictionary:
	if _carve_cache.has(coord):
		return _carve_cache[coord]
	var out: Dictionary = {}
	var nests: Dictionary = {}
	if _caves_enabled():
		var x0 := coord.x * chunk_size
		var z0 := coord.y * chunk_size
		var x1 := x0 + chunk_size
		var z1 := z0 + chunk_size
		for sx in range(coord.x - CAVE_REACH_CHUNKS, coord.x + CAVE_REACH_CHUNKS + 1):
			for sz in range(coord.y - CAVE_REACH_CHUNKS, coord.y + CAVE_REACH_CHUNKS + 1):
				for sys in cave_systems_from(Vector2i(sx, sz)):
					var mn: Vector3 = sys["min"]
					var mx: Vector3 = sys["max"]
					if mx.x < x0 or mn.x > x1 or mx.z < z0 or mn.z > z1:
						continue
					for sh in sys["shapes"]:
						_rasterize(sh, x0, z0, x1, z1, out)
					var nest: Dictionary = sys["nest"]
					if not nest.is_empty():
						var egg: Vector3i = nest["egg"]
						for dx in range(-1, 2):
							for dz in range(-1, 2):
								var nc := Vector3i(egg.x + dx, egg.y - 1, egg.z + dz)
								if nc.x >= x0 and nc.x < x1 and nc.z >= z0 and nc.z < z1:
									nests[nc] = "nest"
						if egg.x >= x0 and egg.x < x1 and egg.z >= z0 and egg.z < z1:
							nests[egg] = "egg"
		for nc2 in nests.keys():
			out.erase(nc2)
	_carve_cache[coord] = out
	_nest_cache[coord] = nests
	return out


func _rasterize(sh: Dictionary, x0: int, z0: int, x1: int, z1: int, out: Dictionary) -> void:
	var c: Vector3 = sh["c"]
	var r: float = float(sh["r"])
	var ax := maxi(x0, floori(c.x - r))
	var bx := mini(x1 - 1, floori(c.x + r))
	var az := maxi(z0, floori(c.z - r))
	var bz := mini(z1 - 1, floori(c.z + r))
	if ax > bx or az > bz:
		return
	if str(sh["t"]) == "dome":
		var h: float = float(sh["h"])
		var fy := int(c.y)
		for x in range(ax, bx + 1):
			for z in range(az, bz + 1):
				var dx := float(x) + 0.5 - c.x
				var dz := float(z) + 0.5 - c.z
				for y in range(fy, fy + int(ceil(h)) + 1):
					var dy := (float(y - fy) + 0.5) / h * r
					if dx * dx + dz * dz + dy * dy <= r * r:
						var cell := Vector3i(x, y, z)
						if _carve_allowed(cell):
							out[cell] = true
		return
	var ay := floori(c.y - r)
	var by := floori(c.y + r)
	for x2 in range(ax, bx + 1):
		for z2 in range(az, bz + 1):
			var ex := float(x2) + 0.5 - c.x
			var ez := float(z2) + 0.5 - c.z
			var top := height_at(x2, z2)
			for y2 in range(ay, mini(by, top - 1) + 1):
				var ey := (float(y2) + 0.5 - c.y) * 1.15
				if ex * ex + ey * ey + ez * ez <= r * r:
					var cell2 := Vector3i(x2, y2, z2)
					if _carve_allowed(cell2):
						out[cell2] = true


func is_carved(c: Vector3i) -> bool:
	if not _caves_enabled():
		return false
	var ck := Vector2i(floori(float(c.x) / float(chunk_size)), floori(float(c.z) / float(chunk_size)))
	return _carved_cells(ck).has(c)


func _extra_solid_kind(c: Vector3i) -> String:
	## Блоки гнёзд (гнездо/яйцо) — генерируемые «солиды» под землёй.
	if not _caves_enabled():
		return ""
	var ck := Vector2i(floori(float(c.x) / float(chunk_size)), floori(float(c.z) / float(chunk_size)))
	_carved_cells(ck)
	var d: Dictionary = _nest_cache.get(ck, {})
	if not d.has(c):
		return ""
	if str(d[c]) == "egg" and GameState != null and GameState.collected_eggs.has("nest:%d,%d,%d" % [c.x, c.y, c.z]):
		return ""
	return str(d[c])


func _ug_solid(c: Vector3i) -> bool:
	## Подземная клетка (y<0) твёрдая? Ниже бедрока — «твёрдо» (граней не нужно).
	if c.y < BEDROCK_Y:
		return true
	if c.y == BEDROCK_Y:
		return true
	if c.y >= 0:
		return false
	if is_cell_removed(c.x, c.y, c.z):
		return false
	if _extra_solid_kind(c) != "":
		return true
	if is_carved(c):
		return false
	var ck := Vector2i(floori(float(c.x) / float(chunk_size)), floori(float(c.z) / float(chunk_size)))
	if _carve_cache.has(ck) and (_nest_cache.get(ck, {}) as Dictionary).has(c):
		return false   # яйцо забрано
	if c.y == -1 and _world_is_lake_cell(c.x, c.z):
		return false
	return true


func _plan_nest_blocks(coord: Vector2i, solids: Dictionary) -> void:
	if not _caves_enabled():
		return
	_carved_cells(coord)
	var d: Dictionary = _nest_cache.get(coord, {})
	for k in d.keys():
		var c: Vector3i = k
		if is_cell_removed(c.x, c.y, c.z):
			continue
		if _extra_solid_kind(c) == "":
			continue
		solids[c] = str(d[c])


func _ug_tiles(n: Vector3i, lake_col: bool) -> Array:
	if n.y <= BEDROCK_Y:
		return BlockTex.faces_for("bedrock")
	if lake_col and n.y == -2:
		return BlockTex.faces_for("sand")
	if n.y == -1:
		return BlockTex.faces_for("ground", false, true)
	if n.y > -6:
		return BlockTex.faces_for("dirt")
	if n.y <= -18:
		return BlockTex.faces_for("deep_stone")
	return BlockTex.faces_for("stone")


func underground_air_cells(coord: Vector2i, lake_cells: Dictionary = {}) -> Dictionary:
	## Воздух под землёй в чанке: снятые игроком клетки, пещеры, вода озёр (y=-1).
	var air: Dictionary = {}
	for raw in GameState.removed_in_chunk(coord):
		var c: Vector3i = raw
		if c.y < 0 and c.y > BEDROCK_Y:
			air[c] = true
	for k in _carved_cells(coord).keys():
		var c2: Vector3i = k
		if c2.y < 0:
			air[c2] = true
	for k2 in lake_cells.keys():
		var l: Vector2i = k2
		air[Vector3i(coord.x * chunk_size + l.x, -1, coord.y * chunk_size + l.y)] = true
	# Забранное яйцо — тоже воздух.
	var nd: Dictionary = _nest_cache.get(coord, {})
	for k3 in nd.keys():
		var e: Vector3i = k3
		if str(nd[e]) == "egg" and _extra_solid_kind(e) == "" and not air.has(e):
			air[e] = true
	return air


func _build_underground(st: Dictionary, body: StaticBody3D, coord: Vector2i, lake_cells: Dictionary, base_col: Color, ground_tiles: Array) -> void:
	var origin := chunk_origin(coord)
	var air := underground_air_cells(coord, lake_cells)
	# 1) Трава сверху (y=0) — где верхняя клетка грунта цела.
	for lz in range(chunk_size):
		var x := 0
		while x < chunk_size:
			var solid := _ug_solid(Vector3i(coord.x * chunk_size + x, -1, coord.y * chunk_size + lz))
			var x0 := x
			while x < chunk_size and _ug_solid(Vector3i(coord.x * chunk_size + x, -1, coord.y * chunk_size + lz)) == solid:
				x += 1
			if solid:
				BlockTex.emit_box(st, Vector3(float(x0), -1.0, float(lz)), Vector3(float(x - x0), 1.0, 1.0), base_col, 63 & ~(1 << 2), ground_tiles)
	# 2) Грани подземных клеток, смотрящие в воздух (пещеры, ямы, дно озёр).
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var col_air: Dictionary = {}
	for k in air.keys():
		var a: Vector3i = k
		var ck := Vector2i(a.x, a.z)
		if not col_air.has(ck):
			col_air[ck] = []
		(col_air[ck] as Array).append(a.y)
		for fi in range(6):
			var n: Vector3i = a + dirs[fi]
			if n.y >= 0 or n.y < BEDROCK_Y:
				continue
			if air.has(n) or not _ug_solid(n):
				continue
			if _extra_solid_kind(n) != "":
				continue
			var opp: int = fi ^ 1
			var shade := 1.0 + (_hash01(n.x * 7 + n.y * 13, n.z * 11 - n.y) - 0.5) * 0.10
			if n.y < -8:
				shade *= 0.92
			var lake_col := _lake_world_cells.has(Vector2i(n.x, n.z)) or lake_cells.has(Vector2i(n.x - coord.x * chunk_size, n.z - coord.y * chunk_size))
			BlockTex.emit_box(st, Vector3(n) - origin, Vector3.ONE, Color(shade, shade, shade), 63 & ~(1 << opp), _ug_tiles(n, lake_col))
	# 3) Коллизия толщи: колонна = набор сплошных участков [-31..-1]; одинаковые соседние колонны склеиваем.
	for lz2 in range(chunk_size):
		var xs := 0
		while xs < chunk_size:
			var key := _column_key(col_air, coord, xs, lz2)
			var xs0 := xs
			while xs < chunk_size and _column_key(col_air, coord, xs, lz2) == key:
				xs += 1
			for run in _column_runs(col_air, coord, xs0, lz2):
				var y0: int = run[0]
				var y1: int = run[1]
				var sz := Vector3(float(xs - xs0), float(y1 - y0 + 1), 1.0)
				var mn := Vector3(float(xs0), float(y0), float(lz2))
				_add_box_shape(body, mn + sz * 0.5, sz)


func _column_key(col_air: Dictionary, coord: Vector2i, lx: int, lz: int) -> String:
	var ck := Vector2i(coord.x * chunk_size + lx, coord.y * chunk_size + lz)
	if not col_air.has(ck):
		return "u"
	var ys: Array = (col_air[ck] as Array).duplicate()
	ys.sort()
	return str(ys)


func _column_runs(col_air: Dictionary, coord: Vector2i, lx: int, lz: int) -> Array:
	var ck := Vector2i(coord.x * chunk_size + lx, coord.y * chunk_size + lz)
	if not col_air.has(ck):
		return [[BEDROCK_Y, -1]]
	var holes: Dictionary = {}
	for y in col_air[ck]:
		holes[int(y)] = true
	var runs: Array = []
	var y := BEDROCK_Y
	while y <= -1:
		if holes.has(y):
			y += 1
			continue
		var y0 := y
		while y <= -1 and not holes.has(y):
			y += 1
		runs.append([y0, y - 1])
	return runs


# ---------------------------------------------------------------- гнёзда: поиск и статистика

func nests_near(pos: Vector3, radius: float) -> Array:
	## Все гнёзда (по сиду), чьи центры ближе radius к pos. [{id, egg, center, kind, taken}]
	var out: Array = []
	if not _caves_enabled():
		return out
	var c := world_to_chunk(pos)
	var rc := int(ceil(radius / float(chunk_size))) + CAVE_REACH_CHUNKS
	for sx in range(c.x - rc, c.x + rc + 1):
		for sz in range(c.y - rc, c.y + rc + 1):
			for sys in cave_systems_from(Vector2i(sx, sz)):
				var n: Dictionary = sys["nest"]
				if n.is_empty():
					continue
				var center: Vector3 = n["center"]
				if center.distance_to(pos) > radius:
					continue
				var d := n.duplicate()
				d["taken"] = GameState.collected_eggs.has(str(n["id"]))
				d["system"] = str(sys["kind"])
				d["entrance"] = sys["entrance"]
				out.append(d)
	return out


func nearest_nest(pos: Vector3, radius: float = 200.0) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for n in nests_near(pos, radius):
		var d := (n["center"] as Vector3).distance_to(pos)
		if d < bd:
			bd = d
			best = n
	return best


func generation_stats(radius_chunks: int) -> Dictionary:
	## Частоты по чанкам (без загрузки мешей): руины, входы в пещеры, гнёзда (пещерные + купола).
	var total := 0
	var ruins := 0
	var entrances := 0
	var deep := 0
	var nests_cave := 0
	var nests_dome := 0
	var nest_chunks := 0
	for cx in range(-radius_chunks, radius_chunks + 1):
		for cz in range(-radius_chunks, radius_chunks + 1):
			var src := Vector2i(cx, cz)
			if maxi(absi(cx), absi(cz)) <= 1:
				continue
			total += 1
			if chunk_has_ruin(src):
				ruins += 1
			var had_nest := false
			for sys in _gen_systems_for(src):
				var k := str(sys["kind"])
				if k == "entrance":
					entrances += 1
				elif k == "deep":
					deep += 1
				if not (sys["nest"] as Dictionary).is_empty():
					had_nest = true
					if k == "dome":
						nests_dome += 1
					else:
						nests_cave += 1
			if had_nest:
				nest_chunks += 1
	return {"chunks": total, "ruins": ruins, "entrances": entrances, "deep": deep,
		"nests_cave": nests_cave, "nests_dome": nests_dome, "nest_chunks": nest_chunks,
		"ruin_pct": 100.0 * float(ruins) / maxf(1.0, float(total)),
		"entrance_pct": 100.0 * float(entrances) / maxf(1.0, float(total)),
		"nest_pct": 100.0 * float(nests_cave + nests_dome) / maxf(1.0, float(total))}


func floor_y_below(pos: Vector3, max_down: int = 40) -> float:
	## Высота пола (верх твёрдой клетки) под точкой — для существ под землёй и в пещерах.
	var x := floori(pos.x)
	var z := floori(pos.z)
	var y := floori(pos.y)
	for i in range(max_down):
		var c := Vector3i(x, y - i, z)
		if _cell_solid_any(c):
			return float(c.y + 1)
	return float(BEDROCK_Y + 1)


func _cell_solid_any(c: Vector3i) -> bool:
	if GameState.wake_solid(c):
		return true
	var ck := world_to_chunk(Vector3(c.x, 0, c.z))
	if _solid_by_chunk.has(ck) and (_solid_by_chunk[ck] as Dictionary).has(c):
		return true
	if c.y < 0:
		return _ug_solid(c)
	if not _solid_by_chunk.has(ck):
		return c.y < height_at(c.x, c.z) and not is_cell_removed(c.x, c.y, c.z) and not is_carved(c)
	return false


func is_cell_solid(c: Vector3i) -> bool:
	return _cell_solid_any(c)


# ---------------------------------------------------------------- текучая вода (клеточный автомат)

const WATER_TICK := 0.25
const WATER_BUDGET := 1500
const WATER_MAX_CELLS := 12000
const WATER_FULL := 8
var _water: Dictionary = {}          # Vector3i -> level 1..8 (8 — полная/падающая)
var _water_src: Dictionary = {}      # Vector3i -> true (озёрные источники)
var _water_by_chunk: Dictionary = {} # Vector2i -> Dictionary{Vector3i: true}
var _wq: Dictionary = {}
var _water_t: float = 0.0
var _water_dirty: Dictionary = {}
var water_updates_total: int = 0


func water_level(c: Vector3i) -> int:
	if _water_src.has(c):
		return WATER_FULL
	return int(_water.get(c, 0))


func water_cell_count() -> int:
	return _water.size()


func is_world_in_water(pos: Vector3) -> bool:
	var c := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	return _water.has(c) or _water_src.has(c) or is_world_in_lake(pos) and pos.y < 0.2


func _water_open(c: Vector3i) -> bool:
	if c.y < MIN_DIG_Y or c.y >= 0:
		return false
	var ck := world_to_chunk(Vector3(c.x, 0, c.z))
	if not _loaded.has(ck):
		return false
	if GameState.wake_solid(c):
		return false
	if (_solid_by_chunk.get(ck, {}) as Dictionary).has(c):
		return false
	return not _ug_solid(c)


func _water_desired(c: Vector3i) -> int:
	if _water_src.has(c):
		return WATER_FULL
	if not _water_open(c):
		return 0
	var up := c + Vector3i.UP
	if _water.has(up) or _water_src.has(up):
		return WATER_FULL
	var best := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + d
		var lvl := water_level(n)
		if lvl <= 1:
			continue
		var below := n + Vector3i.DOWN
		# Растекается только вода, стоящая на твёрдом (как в Minecraft); падающая вниз — не растекается.
		if _water_src.has(n) or not _water_open(below) and not _water.has(below):
			best = maxi(best, lvl - 1)
	return best


func water_notify(c: Vector3i) -> void:
	if is_dream_layer or panorama_mode:
		return
	_wq[c] = true
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		_wq[c + d] = true


func _water_set(c: Vector3i, lvl: int) -> void:
	var ck := world_to_chunk(Vector3(c.x, 0, c.z))
	if lvl <= 0:
		_water.erase(c)
		if _water_by_chunk.has(ck):
			(_water_by_chunk[ck] as Dictionary).erase(c)
	else:
		_water[c] = lvl
		if not _water_by_chunk.has(ck):
			_water_by_chunk[ck] = {}
		(_water_by_chunk[ck] as Dictionary)[c] = true
	_water_dirty[ck] = true
	# Грани соседних чанков (вода у границы)
	var lx := c.x - ck.x * chunk_size
	var lz := c.z - ck.y * chunk_size
	if lx == 0:
		_water_dirty[ck + Vector2i(-1, 0)] = true
	elif lx == chunk_size - 1:
		_water_dirty[ck + Vector2i(1, 0)] = true
	if lz == 0:
		_water_dirty[ck + Vector2i(0, -1)] = true
	elif lz == chunk_size - 1:
		_water_dirty[ck + Vector2i(0, 1)] = true


func water_step() -> int:
	## Один шаг автомата: обрабатываем очередь (снимок), изменения ставят соседей в следующий шаг.
	if _wq.is_empty():
		return 0
	var batch: Array = _wq.keys()
	_wq.clear()
	if batch.size() > WATER_BUDGET:
		for i in range(WATER_BUDGET, batch.size()):
			_wq[batch[i]] = true
		batch.resize(WATER_BUDGET)
	var changed := 0
	for raw in batch:
		var c: Vector3i = raw
		if _water_src.has(c):
			continue
		var want := _water_desired(c)
		var have := int(_water.get(c, 0))
		if want == have:
			continue
		if have == 0 and _water.size() >= WATER_MAX_CELLS:
			continue
		_water_set(c, want)
		changed += 1
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			_wq[c + d] = true
	water_updates_total += changed
	return changed


func water_settle(max_steps: int = 200) -> int:
	## Для тестов: прогнать автомат до покоя.
	var steps := 0
	while not _wq.is_empty() and steps < max_steps:
		water_step()
		steps += 1
	_rebuild_water_meshes()
	return steps


func _water_process(delta: float) -> void:
	_water_t += delta
	if _water_t < WATER_TICK:
		return
	_water_t = 0.0
	water_step()
	_rebuild_water_meshes()


func _water_on_chunk_loaded(coord: Vector2i, lake_cells: Dictionary, _fresh: bool) -> void:
	for k in lake_cells.keys():
		var l: Vector2i = k
		var c := Vector3i(coord.x * chunk_size + l.x, -1, coord.y * chunk_size + l.y)
		_water_src[c] = true
	# Источники рядом с вырытым/пещерой и вода у границы с соседями — в очередь.
	var air := underground_air_cells(coord, {})
	for k2 in air.keys():
		var a: Vector3i = k2
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = a + d
			if _water_src.has(n) or _water.has(n):
				_wq[a] = true
				break
	for k3 in lake_cells.keys():
		var l2: Vector2i = k3
		var c2 := Vector3i(coord.x * chunk_size + l2.x, -1, coord.y * chunk_size + l2.y)
		for d2 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n2: Vector3i = c2 + d2
			if not _water_src.has(n2) and air.has(n2):
				_wq[n2] = true
	for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var wc: Dictionary = _water_by_chunk.get(coord + nb, {})
		for k4 in wc.keys():
			water_notify(k4)
	_water_dirty[coord] = true


func _water_unload_chunk(coord: Vector2i) -> void:
	var wc: Dictionary = _water_by_chunk.get(coord, {})
	for k in wc.keys():
		_water.erase(k)
	_water_by_chunk.erase(coord)
	var x0 := coord.x * chunk_size
	var z0 := coord.y * chunk_size
	for k2 in _water_src.keys():
		var c: Vector3i = k2
		if c.x >= x0 and c.x < x0 + chunk_size and c.z >= z0 and c.z < z0 + chunk_size:
			_water_src.erase(c)
	_water_dirty.erase(coord)


func _rebuild_water_meshes() -> void:
	if _water_dirty.is_empty():
		return
	for ck in _water_dirty.keys():
		if _loaded.has(ck):
			_build_flow_water(ck)
	_water_dirty.clear()


func _build_flow_water(coord: Vector2i) -> void:
	var root: Node3D = _loaded[coord]
	if not is_instance_valid(root):
		return
	var old := root.get_node_or_null("FlowWater")
	if old:
		old.free()
	var wc: Dictionary = _water_by_chunk.get(coord, {})
	if wc.is_empty():
		return
	var origin := chunk_origin(coord)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for k in wc.keys():
		var c: Vector3i = k
		var lvl := int(_water.get(c, 0))
		if lvl <= 0:
			continue
		var full := _water.has(c + Vector3i.UP) or _water_src.has(c + Vector3i.UP)
		var h := 1.0 if full else clampf(float(lvl) / float(WATER_FULL) * 0.92, 0.12, 0.92)
		var mn := Vector3(c) - origin
		for fi in range(6):
			var n: Vector3i = c + dirs[fi]
			var bottom := 0.0
			if _water.has(n) or _water_src.has(n):
				if fi == 2 or fi == 3:
					continue
				bottom = 1.0 if water_level(n + Vector3i.UP) > 0 else clampf(float(water_level(n)) / WATER_FULL * 0.92, 0.12, 0.92)
				if bottom >= h:
					continue
			if fi != 2 and _cell_solid_any(n):
				continue
			var f: Array = BlockTex.FACES[fi]
			var nn: Vector3 = f[0]
			var cs: Array = f[1]
			var p: Array = []
			for q in cs:
				var v: Vector3 = q
				p.append(mn + Vector3(v.x, lerpf(bottom, h, v.y), v.z))
			for idx in [0, 2, 1, 0, 3, 2]:
				var pv: Vector3 = p[idx]
				verts.append(pv)
				norms.append(nn)
				uvs.append(Vector2(pv.x + pv.y, pv.z + pv.y))
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, BlockTex.water_material(false))
	var mi := MeshInstance3D.new()
	mi.name = "FlowWater"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ---------------- v0.9: jobs own all mutable generation state. Scene tree is main-thread only.
const ChunkJob := preload("res://scripts/chunk_job.gd")
const MAX_CHUNK_JOBS := 3
var circular_loading := true
var legacy_generation := false # Only explicit benchmark comparison; normal gameplay always workers.
var _jobs: Dictionary = {}
var _generation_epoch := 0
var worker_chunk_count := 0
var last_worker_id := -1
var generation_usec := 0
var last_insert_usec := 0

func _terrain_edited(_cell: Vector3i) -> void:
	_generation_epoch += 1

func _job_for(c: Vector2i) -> RefCounted:
	var removed := {}
	for dx in range(-1,2):
		for dz in range(-1,2):
			for k in GameState.removed_in_chunk(c+Vector2i(dx,dz)):
				removed[k] = true
	if is_dream_layer: removed = GameState.removed_dream_terrain.duplicate()
	var caves := {}
	var carve := {}
	var nests := {}
	for dx in range(-4,5):
		for dz in range(-4,5):
			var near := c+Vector2i(dx,dz)
			if _cave_sys_cache.has(near): caves[near] = _cave_sys_cache[near]
			if abs(dx)<=1 and abs(dz)<=1:
				if _carve_cache.has(near): carve[near] = _carve_cache[near]
				if _nest_cache.has(near): nests[near] = _nest_cache[near]
	var job := ChunkJob.new()
	job.configure({"seed":_seed,"coord":c,"dream":is_dream_layer,"panorama":panorama_mode,
		"dev":GameState.dev_mode,"removed":removed,"eggs":GameState.collected_eggs.duplicate(),
		"collected":GameState.collected_reagent_ids.duplicate(),"epoch":_generation_epoch,
		"caves":caves,"carve":carve,"nests":nests})
	return job

func _queue_job(c: Vector2i) -> void:
	var job := _job_for(c)
	var id := WorkerThreadPool.add_task(job.run,false,"Chunk %s" % c)
	_jobs[c] = {"job":job,"id":id}

func _poll_jobs(max_insert: int) -> void:
	var inserted := 0
	for c in _jobs.keys():
		var entry: Dictionary = _jobs[c]
		if not WorkerThreadPool.is_task_completed(entry.id): continue
		WorkerThreadPool.wait_for_task_completion(entry.id)
		_jobs.erase(c)
		var data: Dictionary = entry.job.result
		if data.is_empty():
			push_error("Chunk job returned no data: %s" % c)
			continue
		if data.epoch != _generation_epoch:
			if not _loaded.has(c) and not c in _pending: _pending.append(c)
			continue
		if not _loaded.has(c) and maxi(abs(c.x-_center.x),abs(c.y-_center.y)) <= unload_radius:
			_insert_chunk_data(data)
			inserted += 1
		if inserted >= max_insert: break

func _wait_jobs(insert: bool) -> void:
	for c in _jobs.keys():
		var entry: Dictionary = _jobs[c]
		WorkerThreadPool.wait_for_task_completion(entry.id)
		if insert and not _loaded.has(c) and not entry.job.result.is_empty():
			if entry.job.result.epoch == _generation_epoch:
				_insert_chunk_data(entry.job.result)
			elif not c in _pending:
				_pending.append(c)
	_jobs.clear()

func _exit_tree() -> void:
	_wait_jobs(false)

func _load_chunk(c: Vector2i) -> void:
	if _loaded.has(c): return
	if legacy_generation:
		_load_chunk_legacy(c)
		return
	var job: RefCounted
	if _jobs.has(c):
		var entry: Dictionary = _jobs[c]
		WorkerThreadPool.wait_for_task_completion(entry.id)
		job = entry.job
		_jobs.erase(c)
		if job.epoch != _generation_epoch: job = null
	if job == null:
		job = _job_for(c)
		var id := WorkerThreadPool.add_task(job.run,true,"Priority chunk")
		WorkerThreadPool.wait_for_task_completion(id)
	_insert_chunk_data(job.result)

func _insert_chunk_data(data: Dictionary) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	if data.is_empty(): return
	var t0 := Time.get_ticks_usec()
	var c: Vector2i = data.coord
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [c.x,c.y]
	node.position = chunk_origin(c)
	add_child(node)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("terrain_chunk",c)
	node.add_child(body)
	for box in data.geometry.boxes:
		var oid := _add_box_shape(body,box.center,box.size)
		if box.solid_owner: body.set_meta("solid_owner_%d" % oid,true)
	var stream: Dictionary = data.geometry.stream
	if not stream.v.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "TerrainMesh"
		mi.mesh = BlockTex.stream_to_mesh(stream)
		node.add_child(mi)
	if not data.lake.is_empty():
		var water := MeshInstance3D.new()
		water.name = "LakeWater"
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.geometry.water)
		mesh.surface_set_material(0,BlockTex.water_material(is_dream_layer))
		water.mesh = mesh
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(water)
		var occupied := {}
		_register_lake(c,data.lake,occupied)
	for r in data.reagents:
		if GameState.is_reagent_collected(r.id): continue
		if _reagent_script == null: _reagent_script = load("res://scripts/reagent_node.gd")
		var reagent: Node3D = _reagent_script.new()
		reagent.position = r.pos
		reagent.configure(r.type,r.id,1)
		node.add_child(reagent)
	_trees_by_chunk[c] = data.trees
	for wall in data.walls: _add_wall(c,wall)
	if data.ruin != null: _ruin_centers[c] = data.ruin
	_solid_by_chunk[c] = data.solids
	_cave_sys_cache.merge(data.caves,true)
	_carve_cache.merge(data.carve,true)
	_nest_cache.merge(data.nests,true)
	_loaded[c] = node
	if not panorama_mode:
		_sync_physics_tree(node,_physics_active())
		_check_orphan_leaves(c)
		if not is_dream_layer: _water_on_chunk_loaded(c,data.lake,true)
	worker_chunk_count += 1
	last_worker_id = data.worker_id
	generation_usec += data.generation_us
	last_insert_usec = Time.get_ticks_usec()-t0
