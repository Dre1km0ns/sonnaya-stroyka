extends RefCounted
## Чистый генератор: собственные кеши + неизменяемый снимок данных. Ни одного Node/SceneTree.
const BlockTex = preload("res://scripts/block_tex.gd")
const LAKE_DEPTH := 1.0
const LAKE_SURFACE_Y := -0.08
const FIELD_REAGENT_RATE := 0.2
const RUIN_HASH_THRESHOLD := 0.95
const RUIN_CLUSTER_TARGET := 3
const TREE_SAFE_RADIUS := 6.0
const SETTLEMENT_THRESHOLD := 0.999
const DEV_SETTLEMENT := Vector2i(2,1)
const BEDROCK_Y := -31
const MIN_DIG_Y := -30
const CAVE_ENTRANCE_THRESHOLD := 0.95
const CAVE_DEEP_THRESHOLD := 0.94
const CAVE_NEST_CHANCE := 0.22
const DOME_THRESHOLD := 0.9925
const CAVE_REACH_CHUNKS := 3
const DEV_NEST_FLOOR := Vector3i(21,-8,11)
const DEV_CAVE_PATH := [Vector3(16.5,0.4,2.5),Vector3(17.5,-1.2,4.0),Vector3(19,-3.4,5.8),Vector3(20.2,-5.4,8),Vector3(21.2,-6.6,10.2)]
var chunk_size := 16
var _seed := 1337
var is_dream_layer := false
var panorama_mode := false
var dev_mode := false
var removed: Dictionary = {}
var eggs: Dictionary = {}
var collected: Dictionary = {}
var _lake_plan_cache: Dictionary = {}
var _cave_sys_cache: Dictionary = {}
var _carve_cache: Dictionary = {}
var _nest_cache: Dictionary = {}
var _lake_world_cells: Dictionary = {}
var _lakes_by_chunk: Dictionary = {}
var _ruin_centers: Dictionary = {}
var _wall_world_cells: Dictionary = {}
var _walls_by_chunk: Dictionary = {}
var _trees_by_chunk: Dictionary = {}
var _solid_by_chunk: Dictionary = {}
var coord := Vector2i.ZERO
var epoch := 0
var revision:=0
var _air_for_result: Dictionary={}
var result: Dictionary = {}

func configure(data: Dictionary) -> void:
	_seed = data.seed
	coord = data.coord
	is_dream_layer = data.dream
	panorama_mode = data.panorama
	dev_mode = data.dev
	removed = data.removed
	eggs = data.eggs
	collected = data.collected
	epoch = data.epoch
	revision=int(data.get("revision",0))
	_cave_sys_cache = data.get("caves",{})
	_carve_cache = data.get("carve",{})
	_nest_cache = data.get("nests",{})

func run() -> void:
	_run_data(true)

func run_plan_only() -> void:
	_run_data(false)

func _run_data(with_mesh:bool) -> void:
	var start := Time.get_ticks_usec()
	var occupied := {}
	var solids := {}
	var lake := _plan_lake(coord)
	if not lake.is_empty(): _register_lake(coord,lake,occupied)
	if chunk_has_ruin(coord): _plan_ruin(coord,occupied,solids)
	var reagents: Array = []
	_add_reagents(reagents,coord,occupied)
	_plan_hills(coord,occupied,solids)
	if not is_dream_layer: _plan_trees(coord,occupied,solids)
	_plan_nest_blocks(coord,solids)
	_solid_by_chunk[coord] = solids
	var geometry:Dictionary=_build_chunk_geometry(coord,lake,solids) if with_mesh else {"air":underground_air_cells(coord,lake)}
	freeze_value(_cave_sys_cache);freeze_value(_carve_cache);freeze_value(_nest_cache)
	result = {"coord":coord,"epoch":epoch,"revision":revision,"solids":solids,"lake":lake,"reagents":reagents,"geometry":geometry,
		"trees":_trees_by_chunk.get(coord,[]),"walls":_walls_by_chunk.get(coord,[]),"ruin":_ruin_centers.get(coord),
		"caves":_cave_sys_cache,"carve":_carve_cache,"nests":_nest_cache,
		"worker_id":OS.get_thread_caller_id(),"generation_us":Time.get_ticks_usec()-start}

func is_cell_removed(wx: int,y: int,wz: int) -> bool:
	return not panorama_mode and removed.has(Vector3i(wx,y,wz))

func _dev_nest_enabled() -> bool:
	return _caves_enabled() and dev_mode

func _add_box_shape(body: Array,center: Vector3,size: Vector3) -> int:
	body.append({"center":center,"size":size,"solid_owner":false})
	return body.size()-1


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

func chunk_has_lake(coord: Vector2i) -> bool:
	if _is_settlement(coord):
		return false
	return maxi(absi(coord.x), absi(coord.y)) >= 1 and _chunk_hash(coord, 11) > 0.82

func chunk_has_ruin(coord: Vector2i) -> bool:
	if _is_settlement(coord):
		return true
	return maxi(absi(coord.x), absi(coord.y)) >= 1 and _chunk_hash(coord, 29) > RUIN_HASH_THRESHOLD

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

func _register_lake(coord: Vector2i, lake_cells: Dictionary, occupied: Dictionary) -> void:
	var locals: Array[Vector2i] = []
	for key in lake_cells.keys():
		var cell: Vector2i = key
		occupied[cell] = "lake"
		locals.append(cell)
		_lake_world_cells[Vector2i(coord.x * chunk_size + cell.x, coord.y * chunk_size + cell.y)] = true
	_lakes_by_chunk[coord] = locals

func _is_settlement(coord: Vector2i) -> bool:
	if is_dream_layer or maxi(absi(coord.x), absi(coord.y)) < 2:
		return false
	return (_seed == 6767676767 and coord == DEV_SETTLEMENT) or _chunk_hash(coord, 8127) > SETTLEMENT_THRESHOLD

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

func _build_chunk_geometry(coord: Vector2i, lake_cells: Dictionary, solids: Dictionary) -> Dictionary:
	## v0.6: пиксельные текстуры из атласа (BlockTex), UV в блоках, вершинный цвет = тень/оттенок.
	var st: Dictionary = BlockTex.new_stream()
	var body: Array = []
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
		var col := grass_tint(c.x,c.z) if kind in ["hill","ground","leaves"] else Color(tint+noise,tint+noise,tint+noise)
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
				body[oid]["solid_owner"] = true
	return {"stream":st,"boxes":body,"water":water_arrays(lake_cells),"air":_air_for_result}

func _add_reagents(root: Array, coord: Vector2i, occupied: Dictionary) -> void:
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

func _add_ruin_reagent_cluster(root: Array, coord: Vector2i, occupied: Dictionary) -> void:
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
		if spawned >= (settlement_reagent_target(coord) if _is_settlement(coord) else RUIN_CLUSTER_TARGET):
			break
		var pick := _hash01(coord.x * 17 + cell.x + salt, coord.y * 13 + cell.y)
		if pick < 0.35 and spawned > 0:
			salt += 1
			continue
		if _try_spawn_reagent_at(root, coord, occupied, cell.x, cell.y, salt):
			spawned += 1
		salt += 1

func _try_spawn_reagent_at(root: Array, coord: Vector2i, occupied: Dictionary, lx: int, lz: int, salt: int) -> bool:
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
	if not panorama_mode and collected.has(rid):
		return false
	var type_id := 1 + int(_hash01(coord.x + lx * 3 + salt, coord.y + lz * 5) * 3.0)
	type_id = (1 + salt % 3) if _is_settlement(coord) else clampi(type_id, 1, 3)
	occupied[key] = "reagent"
	root.append({"pos":Vector3(float(lx)+0.5,float(h)+0.35,float(lz)+0.5),"type":type_id,"id":rid})
	return true

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
	if str(d[c]) == "egg" and eggs.has("nest:%d,%d,%d" % [c.x, c.y, c.z]):
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
	for raw in removed.keys():
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

func _build_underground(st: Dictionary, body: Array, coord: Vector2i, lake_cells: Dictionary, base_col: Color, ground_tiles: Array) -> void:
	var origin := chunk_origin(coord)
	var air := underground_air_cells(coord, lake_cells)
	_air_for_result=air
	# 1) Трава сверху (y=0) — где верхняя клетка грунта цела.
	for lz in range(chunk_size):
		var x := 0
		while x < chunk_size:
			var solid := _ug_solid(Vector3i(coord.x * chunk_size + x, -1, coord.y * chunk_size + lz))
			var x0 := x
			while x < chunk_size and _ug_solid(Vector3i(coord.x * chunk_size + x, -1, coord.y * chunk_size + lz)) == solid:
				x += 1
			if solid:
				# Keep greedy ground strips; colour shared world-coordinate vertices rather than
				# exploding each flat strip into 16 separate blocks (important on integrated GPUs).
				var first: int = st.c.size()
				BlockTex.emit_box(st,Vector3(x0,-1,lz),Vector3(x-x0,1,1),Color.WHITE,63 & ~(1<<2),ground_tiles)
				var colours: PackedColorArray = st.c
				var vertices: PackedVector3Array = st.v
				for vi in range(first,colours.size()):
					var wp := origin+vertices[vi]
					colours[vi] = grass_tint(floori(wp.x),floori(wp.z))
				st.c = colours
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

func grass_tint(wx: int,wz: int) -> Color:
	var n := _value_noise(wx*0.055+271,wz*0.055-113)
	var fine := _hash01(wx,wz)-0.5
	return Color(0.91+n*0.07+fine*0.02,0.98+n*0.035,0.87+n*0.06)

func settlement_reagent_target(c: Vector2i) -> int:
	return 13 if _chunk_hash(c,9871)<0.75 else 12

func water_arrays(cells: Dictionary) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	for c in cells:
		for q in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
			v.append(Vector3(c.x+q.x,LAKE_SURFACE_Y,c.y+q.y))
			n.append(Vector3.UP)
			uv.append(Vector2(c.x+q.x,c.y+q.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=v
	arrays[Mesh.ARRAY_NORMAL]=n
	arrays[Mesh.ARRAY_TEX_UV]=uv
	return arrays

static func freeze_value(value: Variant) -> void:
	# Published procedural cache entries are immutable, safely shared by readers.
	# Every job still owns its top-level maps and all new generation output.
	if value is Dictionary:
		if value.is_read_only(): return
		for child in value.values(): freeze_value(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only(): return
		for child in value: freeze_value(child)
		value.make_read_only()
