extends Node3D
## Бесконечный чанковый пол (softclay) для Яви или Сна.
## Игрок ходит бесконечно; билды/якоря живут в GameState и VoxelWorld.

@export var is_dream_layer: bool = false
@export var chunk_size: int = 16
@export var load_radius: int = 2
@export var unload_radius: int = 3
@export var block_size: float = 1.0

const COLOR_WAKE := Color(0.55, 0.62, 0.48)
const COLOR_WAKE_BUMP := Color(0.48, 0.55, 0.40)
const COLOR_DREAM := Color(0.28, 0.24, 0.42)
const COLOR_DREAM_BUMP := Color(0.42, 0.35, 0.58)

var _loaded: Dictionary = {} # Vector2i -> Node3D
var _player: Node3D = null
var _seed: int = 1337
var _tick: float = 0.0
var _lakes_by_chunk: Dictionary = {} # Vector2i -> Array[Vector2i] local cells
var _lake_world_cells: Dictionary = {} # Vector2i world XZ -> true
var _ruin_centers: Dictionary = {} # Vector2i -> Vector3
var _wall_world_cells: Dictionary = {} # Vector2i world XZ -> true

const LAKE_DEPTH := 1.25
const LAKE_SURFACE_Y := -0.08
const FIELD_REAGENT_RATE := 0.2
const RUIN_HASH_THRESHOLD := 0.95
const RUIN_CLUSTER_TARGET := 3
const HILL_MAX := 4


func _ready() -> void:
	add_to_group("chunk_manager")
	set_meta("is_dream", is_dream_layer)


func setup(player: Node3D, world_seed: int = 1337) -> void:
	_player = player
	_seed = world_seed
	_update_chunks(true)


func get_loaded_count() -> int:
	return _loaded.size()


func world_to_chunk(pos: Vector3) -> Vector2i:
	var cx := floori(pos.x / float(chunk_size))
	var cz := floori(pos.z / float(chunk_size))
	return Vector2i(cx, cz)


func chunk_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)


func height_at(wx: int, wz: int) -> int:
	## Плоская зона спавна, дальше холмы 1..4 уровней.
	if absi(wx) <= 14 and absi(wz) <= 14:
		return 0
	var n := _value_noise(float(wx) * 0.07, float(wz) * 0.07)
	if n > 0.62:
		return 4
	if n > 0.42:
		return 3
	if n > 0.22:
		return 2
	if n > 0.05:
		return 1
	return 0


func is_world_wall(wx: int, wz: int) -> bool:
	return _wall_world_cells.has(Vector2i(wx, wz))


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	if _player == null:
		return
	# Чанки яви всегда поддерживаем (после пробуждения игрок падает на пол).
	# Сон — только пока мы во сне (экономия).
	if is_dream_layer and not GameState.is_dream():
		return
	_update_chunks(false)


func _update_chunks(force: bool) -> void:
	if _player == null:
		return
	var center := world_to_chunk(_player.global_position)
	var needed: Dictionary = {}
	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			needed[Vector2i(center.x + dx, center.y + dz)] = true

	# unload
	var to_unload: Array[Vector2i] = []
	for key in _loaded.keys():
		var c: Vector2i = key
		var dist := maxi(absi(c.x - center.x), absi(c.y - center.y))
		if dist > unload_radius and not needed.has(c):
			to_unload.append(c)
	for c2 in to_unload:
		_unload_chunk(c2)

	# load
	for key2 in needed.keys():
		var c3: Vector2i = key2
		if not _loaded.has(c3):
			_load_chunk(c3)
		elif force:
			pass


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
	if _lakes_by_chunk.has(coord):
		for raw in _lakes_by_chunk[coord]:
			var local: Vector2i = raw
			var wx := coord.x * chunk_size + local.x
			var wz := coord.y * chunk_size + local.y
			_lake_world_cells.erase(Vector2i(wx, wz))
		_lakes_by_chunk.erase(coord)
	for lx in range(chunk_size):
		for lz in range(chunk_size):
			_wall_world_cells.erase(Vector2i(coord.x * chunk_size + lx, coord.y * chunk_size + lz))
	_ruin_centers.erase(coord)
	if is_instance_valid(node):
		node.queue_free()


func _load_chunk(coord: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root.position = chunk_origin(coord)
	add_child(root)

	var occupied: Dictionary = {} # Vector2i local -> String tag
	var lake_cells := _plan_lake(coord)
	_build_terrain(root, coord, lake_cells)
	if not lake_cells.is_empty():
		_realize_lake(root, coord, lake_cells, occupied)
	if chunk_has_ruin(coord):
		_add_ruin(root, coord, occupied)
	_add_reagents(root, coord, occupied)

	_add_hills(root, coord, occupied)

	_loaded[coord] = root


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
	return cells


func _build_terrain(root: Node3D, coord: Vector2i, lake_cells: Dictionary) -> void:
	if lake_cells.is_empty():
		_add_floor_slab(root, coord, 0, 0, chunk_size, chunk_size, 0.0)
		return
	for lz in range(chunk_size):
		var x := 0
		while x < chunk_size:
			var is_lake := lake_cells.has(Vector2i(x, lz))
			var x0 := x
			while x < chunk_size and lake_cells.has(Vector2i(x, lz)) == is_lake:
				x += 1
			var width := x - x0
			if is_lake:
				_add_floor_slab(root, coord, x0, lz, width, 1, -LAKE_DEPTH)
			else:
				_add_floor_slab(root, coord, x0, lz, width, 1, 0.0)


func _add_floor_slab(root: Node3D, coord: Vector2i, lx: int, lz: int, w: int, d: int, top_y: float) -> void:
	var thickness := 1.0 if top_y < -0.01 else (LAKE_DEPTH + 1.0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(float(lx) + float(w) * 0.5, top_y - thickness * 0.5, float(lz) + float(d) * 0.5)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(float(w), thickness, float(d))
	floor_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var colr := COLOR_DREAM if is_dream_layer else COLOR_WAKE
	if top_y < -0.01:
		colr = colr.darkened(0.18)
	var tint := 0.04 * float((coord.x * 3 + coord.y * 7) % 5 - 2)
	mat.albedo_color = colr.lightened(tint)
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(w), thickness, float(d))
	col.shape = shape
	floor_body.add_child(col)
	root.add_child(floor_body)


func _realize_lake(root: Node3D, coord: Vector2i, lake_cells: Dictionary, occupied: Dictionary) -> void:
	var locals: Array[Vector2i] = []
	for key in lake_cells.keys():
		var cell: Vector2i = key
		occupied[cell] = "lake"
		locals.append(cell)
		var wx := coord.x * chunk_size + cell.x
		var wz := coord.y * chunk_size + cell.y
		_lake_world_cells[Vector2i(wx, wz)] = true
	_lakes_by_chunk[coord] = locals
	# Тонкая поверхность воды (без боковых «стенок» объёма) + берега со всех сторон.
	var water_h := 0.07
	for lz in range(chunk_size):
		var x := 0
		while x < chunk_size:
			if not lake_cells.has(Vector2i(x, lz)):
				x += 1
				continue
			var x0 := x
			while x < chunk_size and lake_cells.has(Vector2i(x, lz)):
				x += 1
			var width := x - x0
			var water := MeshInstance3D.new()
			water.name = "LakeWater"
			var box := BoxMesh.new()
			box.size = Vector3(float(width), water_h, 1.0)
			water.mesh = box
			water.position = Vector3(float(x0) + float(width) * 0.5, LAKE_SURFACE_Y - water_h * 0.5, float(lz) + 0.5)
			var mat := StandardMaterial3D.new()
			if is_dream_layer:
				mat.albedo_color = Color(0.22, 0.18, 0.48, 0.52)
			else:
				mat.albedo_color = Color(0.20, 0.42, 0.66, 0.52)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.12
			mat.metallic = 0.18
			water.material_override = mat
			root.add_child(water)
	_add_lake_banks(root, coord, lake_cells)
	var area := Area3D.new()
	area.name = "LakeArea"
	area.add_to_group("lake")
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	root.add_child(area)


func _add_ruin(root: Node3D, coord: Vector2i, occupied: Dictionary) -> void:
	var w := 5
	var d := 5
	var ox := 3 + int(_hash01(coord.x + 3, coord.y) * 6.0)
	var oz := 3 + int(_hash01(coord.x, coord.y + 3) * 6.0)
	ox = clampi(ox, 1, chunk_size - w - 1)
	oz = clampi(oz, 1, chunk_size - d - 1)
	# Не ставим дом прямо в озеро — сдвигаем, если клетка занята.
	if occupied.has(Vector2i(ox + 2, oz + 2)) and str(occupied[Vector2i(ox + 2, oz + 2)]) == "lake":
		ox = 1
		oz = 1
	var door_side := int(_hash01(coord.x * 9, coord.y * 9) * 4.0) % 4
	var wall_color := Color(0.46, 0.38, 0.31) if not is_dream_layer else Color(0.34, 0.26, 0.42)
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
			_wall_world_cells[Vector2i(coord.x * chunk_size + lx, coord.y * chunk_size + lz)] = true
			var height := 2 if decay > 0.35 else 3
			for y in range(height):
				_place_box(
					root,
					Vector3(float(lx) + 0.5, float(y) + 0.5, float(lz) + 0.5),
					Vector3(0.95, 1.0, 0.95),
					wall_color
				)


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
	if GameState.has_method("is_reagent_collected") and GameState.is_reagent_collected(rid):
		return false
	var type_id := 1 + int(_hash01(coord.x + lx * 3 + salt, coord.y + lz * 5) * 3.0)
	type_id = clampi(type_id, 1, 3)
	occupied[key] = "reagent"
	var node_script: GDScript = load("res://scripts/reagent_node.gd")
	var node: StaticBody3D = node_script.new()
	node.position = Vector3(float(lx) + 0.5, float(h) + 0.35, float(lz) + 0.5)
	if node.has_method("configure"):
		node.configure(type_id, rid, 1)
	else:
		node.set("reagent_type", type_id)
		node.set("world_id", rid)
	root.add_child(node)
	return true


func _place_box(root: Node3D, local_pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = local_pos
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.88
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	root.add_child(body)


func _add_hills(root: Node3D, coord: Vector2i, occupied: Dictionary) -> void:
	for lx in range(chunk_size):
		for lz in range(chunk_size):
			var wx := coord.x * chunk_size + lx
			var wz := coord.y * chunk_size + lz
			var cell := Vector2i(lx, lz)
			if occupied.has(cell):
				var tag := str(occupied[cell])
				if tag == "lake" or tag == "wall" or tag == "ruin_floor" or tag == "door" or tag == "gap":
					continue
			var h := height_at(wx, wz)
			if h <= 0:
				continue
			occupied[cell] = occupied.get(cell, "hill")
			var bump := StaticBody3D.new()
			bump.name = "Hill"
			bump.collision_layer = 1
			bump.collision_mask = 0
			bump.position = Vector3(float(lx) + 0.5, float(h) * 0.5, float(lz) + 0.5)
			var bmi := MeshInstance3D.new()
			var bbox := BoxMesh.new()
			bbox.size = Vector3(0.98, float(h), 0.98)
			bmi.mesh = bbox
			var bmat := StandardMaterial3D.new()
			bmat.roughness = 0.9
			bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var base := COLOR_DREAM_BUMP if is_dream_layer else COLOR_WAKE_BUMP
			bmat.albedo_color = base.darkened(0.06 * float(h - 1))
			bmi.material_override = bmat
			bump.add_child(bmi)
			var bcol := CollisionShape3D.new()
			var bshape := BoxShape3D.new()
			bshape.size = Vector3(1.0, float(h), 1.0)
			bcol.shape = bshape
			bump.add_child(bcol)
			root.add_child(bump)


func _world_is_lake_cell(wx: int, wz: int) -> bool:
	var c := Vector2i(floori(float(wx) / float(chunk_size)), floori(float(wz) / float(chunk_size)))
	if not chunk_has_lake(c):
		return false
	var planned := _plan_lake(c)
	var lx := wx - c.x * chunk_size
	var lz := wz - c.y * chunk_size
	return planned.has(Vector2i(lx, lz))


func _add_lake_banks(root: Node3D, coord: Vector2i, lake_cells: Dictionary) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var bank_h := LAKE_DEPTH
	var colr := (COLOR_DREAM if is_dream_layer else COLOR_WAKE).darkened(0.12)
	for key in lake_cells.keys():
		var cell: Vector2i = key
		var wx := coord.x * chunk_size + cell.x
		var wz := coord.y * chunk_size + cell.y
		for d in dirs:
			var n := cell + d
			var n_is_lake := lake_cells.has(n)
			if not n_is_lake:
				var nwx := wx + d.x
				var nwz := wz + d.y
				if _world_is_lake_cell(nwx, nwz):
					continue
			else:
				continue
			var wall := MeshInstance3D.new()
			wall.name = "LakeBank"
			var box := BoxMesh.new()
			if d.x != 0:
				box.size = Vector3(0.12, bank_h, 1.0)
			else:
				box.size = Vector3(1.0, bank_h, 0.12)
			wall.mesh = box
			var mid := Vector3(float(cell.x) + 0.5 + float(d.x) * 0.44, -bank_h * 0.5, float(cell.y) + 0.5 + float(d.y) * 0.44)
			wall.position = mid
			var mat := StandardMaterial3D.new()
			mat.roughness = 0.95
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = colr
			wall.material_override = mat
			root.add_child(wall)
