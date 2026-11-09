extends Node3D
## Бесконечный чанковый мир (Явь или Сон), v0.5.
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

const LAKE_DEPTH := 1.25
const LAKE_SURFACE_Y := -0.08
const FIELD_REAGENT_RATE := 0.2
const RUIN_HASH_THRESHOLD := 0.95
const RUIN_CLUSTER_TARGET := 3
const HILL_MAX := 4
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
	for key in _loaded.keys():
		_unload_chunk(key)
	_pending.clear()


func get_loaded_count() -> int:
	return _loaded.size()


func get_pending_count() -> int:
	return _pending.size()


func world_to_chunk(pos: Vector3) -> Vector2i:
	var cx := floori(pos.x / float(chunk_size))
	var cz := floori(pos.z / float(chunk_size))
	return Vector2i(cx, cz)


func chunk_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)


func height_at(wx: int, wz: int) -> int:
	## Редкие холмы, до 4 уровней. Зависит от сида мира.
	if absi(wx) <= 14 and absi(wz) <= 14:
		return 0
	var n := _value_noise(float(wx) * 0.07, float(wz) * 0.07)
	if n > 0.88:
		return 4
	if n > 0.80:
		return 3
	if n > 0.70:
		return 2
	if n > 0.58:
		return 1
	return 0


func walk_height_at(wx: int, wz: int) -> int:
	## Высота для навигации: генерируемый холм минус снятые клетки сверху.
	var h := height_at(wx, wz)
	while h > 0 and is_cell_removed(wx, h - 1, wz):
		h -= 1
	return h


func is_cell_removed(wx: int, y: int, wz: int) -> bool:
	if is_dream_layer or panorama_mode:
		return false
	if GameState and GameState.has_method("is_terrain_removed"):
		return bool(GameState.is_terrain_removed(Vector3i(wx, y, wz)))
	return false


func rebuild_chunk(coord: Vector2i) -> void:
	if _loaded.has(coord):
		_unload_chunk(coord)
	_load_chunk(coord)


func rebuild_chunk_at_world(wx: int, wz: int) -> void:
	rebuild_chunk(world_to_chunk(Vector3(float(wx), 0.0, float(wz))))


func terrain_kind_at(cell: Vector3i) -> String:
	## «hill» / «ruin» / «ground» / "" — что за клетка террейна (для кирки).
	var coord := world_to_chunk(Vector3(cell.x, 0, cell.z))
	if _solid_by_chunk.has(coord):
		var d: Dictionary = _solid_by_chunk[coord]
		if d.has(cell):
			return str(d[cell])
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
	if k == "":
		k = terrain_kind_at(cell)
		if k == "":
			if cell.y < 0:
				k = "ground"
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


func _drain_pending() -> void:
	if _pending.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var built := 0
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if _loaded.has(c):
			continue
		_load_chunk(c)
		built += 1
		if Time.get_ticks_usec() - t0 > FRAME_BUDGET_USEC:
			break


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
			var c3 := Vector2i(center.x + dx, center.y + dz)
			if not _loaded.has(c3):
				_pending.append(c3)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())


func load_all_pending() -> void:
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not _loaded.has(c):
			_load_chunk(c)


func chunk_has_lake(coord: Vector2i) -> bool:
	return maxi(absi(coord.x), absi(coord.y)) >= 1 and _chunk_hash(coord, 11) > 0.82


func chunk_has_ruin(coord: Vector2i) -> bool:
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


func _load_chunk(coord: Vector2i) -> void:
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
	_solid_by_chunk[coord] = solids
	_build_chunk_geometry(root, coord, lake_cells, solids)
	_loaded[coord] = root
	if not panorama_mode:
		_sync_physics_tree(root, _physics_active())
		_check_orphan_leaves(coord)


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


func _plan_ruin(coord: Vector2i, occupied: Dictionary, solids: Dictionary) -> void:
	var w := 5
	var d := 5
	var ox := 3 + int(_hash01(coord.x + 3, coord.y) * 6.0)
	var oz := 3 + int(_hash01(coord.x, coord.y + 3) * 6.0)
	ox = clampi(ox, 1, chunk_size - w - 1)
	oz = clampi(oz, 1, chunk_size - d - 1)
	if occupied.has(Vector2i(ox + 2, oz + 2)) and str(occupied[Vector2i(ox + 2, oz + 2)]) == "lake":
		ox = 1
		oz = 1
	var door_side := int(_hash01(coord.x * 9, coord.y * 9) * 4.0) % 4
	_ruin_centers[coord] = chunk_origin(coord) + Vector3(float(ox) + float(w) * 0.5, 0.0, float(oz) + float(d) * 0.5)
	var mx := ox + w / 2
	var mz := oz + d / 2
	for lx in range(ox, ox + w):
		for lz in range(oz, oz + d):
			var is_wall := lx == ox or lx == ox + w - 1 or lz == oz or lz == oz + d - 1
			if not is_wall:
				if not occupied.has(Vector2i(lx, lz)):
					occupied[Vector2i(lx, lz)] = "ruin_floor"
				continue
			var is_door := false
			if door_side == 0 and lz == oz and lx == mx:
				is_door = true
			elif door_side == 1 and lz == oz + d - 1 and lx == mx:
				is_door = true
			elif door_side == 2 and lx == ox and lz == mz:
				is_door = true
			elif door_side == 3 and lx == ox + w - 1 and lz == mz:
				is_door = true
			if is_door:
				occupied[Vector2i(lx, lz)] = "door"
				continue
			var decay := _hash01(coord.x * 40 + lx, coord.y * 40 + lz)
			if decay > 0.72:
				occupied[Vector2i(lx, lz)] = "gap"
				continue
			if occupied.has(Vector2i(lx, lz)) and str(occupied[Vector2i(lx, lz)]) == "lake":
				continue
			occupied[Vector2i(lx, lz)] = "wall"
			var height := 2 if decay > 0.35 else 3
			var wx := coord.x * chunk_size + lx
			var wz := coord.y * chunk_size + lz
			var any_left := false
			for y in range(height):
				if is_cell_removed(wx, y, wz):
					continue
				any_left = true
				solids[Vector3i(wx, y, wz)] = "ruin"
			if any_left:
				_add_wall(coord, Vector2i(wx, wz))


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
				if is_cell_removed(wx, y, wz):
					continue
				solids[Vector3i(wx, y, wz)] = "hill"


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
		if is_cell_removed(wx, -1, wz):
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
	

func absorb_trees_near(center: Vector3, radius: float) -> int:
	## Мать блоков расчищает арену: брёвна деревьев рядом исчезают, листва затем опадает.
	if is_dream_layer:
		return 0
	var n := 0
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
				GameState.remove_terrain_cell_silent(c, "log")
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
	var drop: StaticBody3D = script.new()
	drop.configure(kind)
	drop.position = Vector3(float(c.x) + 0.5, maxf(float(c.y) * 0.0 + 0.55, 0.55), float(c.z) + 0.5)
	host.add_child(drop)


func _neighbor_solid(solids: Dictionary, c: Vector3i) -> bool:
	if solids.has(c):
		return true
	if c.y < 0:
		return c.y == -1 and not _lake_world_cells.has(Vector2i(c.x, c.z)) and not is_cell_removed(c.x, -1, c.z)
	# Соседний чанк: холмы — чистая функция от сида (руины не касаются края чанка).
	var coord := world_to_chunk(Vector3(c.x, 0, c.z))
	if _solid_by_chunk.has(coord):
		return (_solid_by_chunk[coord] as Dictionary).has(c)
	return c.y < height_at(c.x, c.z) and not is_cell_removed(c.x, c.y, c.z) and not _world_is_lake_cell(c.x, c.z)


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
	# Пол: полосы вдоль X с одинаковым тегом, верх + боковины.
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
				# Верхний блок — трава, ниже — земля (на срезах у озёр и ям).
				BlockTex.emit_box(st, Vector3(float(x0), top_y - 1.0, float(lz)), Vector3(float(width), 1.0, 1.0), base_col, 1 << 3, ground_tiles)
				BlockTex.emit_box(st, mn, Vector3(float(width), thickness - 1.0, 1.0), base_col, (1 << 3) | (1 << 2), dirt_tiles)
			elif tag == "lake":
				BlockTex.emit_box(st, mn, sz, base_col.darkened(0.08), 1 << 3, bed_tiles)
			else:
				BlockTex.emit_box(st, mn, sz, base_col.darkened(0.1), 1 << 3, dirt_tiles)
			_add_box_shape(body, mn + sz * 0.5, sz)
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
			_add_box_shape(body, lp + sz2 * 0.5, sz2)
	if (st["v"] as PackedVector3Array).size() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "TerrainMesh"
		mi.mesh = BlockTex.stream_to_mesh(st)
		root.add_child(mi)
	if not lake_cells.is_empty():
		_build_water(root, lake_cells)


func _add_box_shape(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, shape)
	body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, center))


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
		if spawned >= RUIN_CLUSTER_TARGET:
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
	type_id = clampi(type_id, 1, 3)
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


func _world_is_lake_cell(wx: int, wz: int) -> bool:
	if _lake_world_cells.has(Vector2i(wx, wz)):
		return true
	var c := Vector2i(floori(float(wx) / float(chunk_size)), floori(float(wz) / float(chunk_size)))
	if _loaded.has(c) or not chunk_has_lake(c):
		return false
	var planned := _plan_lake(c)
	return planned.has(Vector2i(wx - c.x * chunk_size, wz - c.y * chunk_size))


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
			if mn.y < -0.01:
				continue # пол
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
