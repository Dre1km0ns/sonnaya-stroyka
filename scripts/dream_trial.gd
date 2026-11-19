extends RefCounted
## v0.19 «Испытание Сна»: детерминированная осада рамки фантомами (DREAM_CORE_PLAN.md §4.6).
## Работает на КОПИИ блоков — Сон не меняется. Фантомы идут к сердцу рамки по полю расстояний
## (Дейкстра; цена клетки с блоком = 1 + его прочность), грызут самое слабое место, сгорают у света.
## Результат: выдержала ли постройка, оценка S–D, слабые места, функции (убежище, световое кольцо, крепость).

const MARGIN := 4
const PHANTOMS := 12
const PHANTOM_HP := 6
const MAX_TICKS := 240           # 24 с при 10 тиках/с
const LIGHT_R := 2
const LIGHT_KINDS := ["lumen", "lumen_cold", "lamp", "torch"]
## Как и кошмары v0.18, фантомы грызут только дрейф и листву — настоящие материалы им не по зубам.
## Испытание проверяет щели, высоту стен (≥ 2), слабые места из дрейфа и свет.
const HP := {"drift": 6, "leaves": 3}
const SOLID := 1 << 20
const GRADE_BONUS := {"S": 20.0, "A": 15.0, "B": 10.0}

var blocks: Dictionary = {}      # Vector3i -> kind (копия)
var hp: Dictionary = {}          # Vector3i -> оставшаяся прочность
var lo: Vector3i
var hi: Vector3i
var y0 := 0
var core := Vector2i.ZERO
var gx0 := 0; var gz0 := 0; var gw := 0; var gd := 0
var dist := PackedInt32Array()
var lights: Array = []


static func run(source: Dictionary, box_lo: Vector3i, box_hi: Vector3i, phantoms: int = PHANTOMS) -> Dictionary:
	var t = load("res://scripts/dream_trial.gd").new()
	return t._simulate(source, box_lo, box_hi, phantoms)


func _kind_at(c: Vector3i) -> String:
	return str(blocks.get(c, ""))


func _solid(c: Vector3i) -> bool:
	return blocks.has(c)


func _passable(x: int, z: int) -> bool:
	var a := Vector3i(x, y0, z); var b := Vector3i(x, y0 + 1, z); var c := Vector3i(x, y0 + 2, z)
	if not _solid(a) and not _solid(b): return true
	return _solid(a) and not _solid(b) and not _solid(c)   # перешагнуть блок высотой 1: стены должны быть ≥ 2


func _block_cost(x: int, z: int) -> int:
	## Цена «прогрызть» колонку: сумма прочности того, что мешает пройти (уровни y0 и y0+1).
	var s := 0
	for y in [y0, y0 + 1]:
		var c := Vector3i(x, y, z)
		if hp.has(c):
			if int(hp[c]) >= SOLID: return -1   # настоящий материал — не прогрызть
			s += int(hp[c])
	return s


func _enterable(x: int, z: int) -> bool:
	return _passable(x, z) or _block_cost(x, z) >= 0


func _idx(x: int, z: int) -> int:
	return (z - gz0) * gw + (x - gx0)


func _in(x: int, z: int) -> bool:
	return x >= gx0 and z >= gz0 and x < gx0 + gw and z < gz0 + gd


func _field() -> void:
	## Дейкстра от сердца рамки; простая очередь по корзинам (цены — маленькие целые).
	var INF := 1 << 29
	dist.resize(gw * gd); dist.fill(INF)
	var buckets := {}
	dist[_idx(core.x, core.y)] = 0
	buckets[0] = [core]
	var cur := 0; var maxd := 0
	while cur <= maxd:
		if buckets.has(cur):
			var lst: Array = buckets[cur]
			var i := 0
			while i < lst.size():
				var p: Vector2i = lst[i]; i += 1
				if dist[_idx(p.x, p.y)] != cur: continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + d
					if not _in(n.x, n.y) or not _enterable(n.x, n.y): continue
					# шаг «из n в p»: фантом в n идёт в p — платит за p; поле строим как цену добраться до сердца
					var bc := 0 if _passable(p.x, p.y) else _block_cost(p.x, p.y)
					if bc < 0: continue
					var nd := cur + 1 + bc
					if nd < dist[_idx(n.x, n.y)]:
						dist[_idx(n.x, n.y)] = nd
						if not buckets.has(nd): buckets[nd] = []
						buckets[nd].append(n)
						maxd = maxi(maxd, nd)
			buckets.erase(cur)
		cur += 1


func _near_light(x: int, z: int) -> bool:
	for l in lights:
		var c: Vector3i = l
		if absi(c.x - x) <= LIGHT_R and absi(c.z - z) <= LIGHT_R and c.y >= y0 - 1 and c.y <= y0 + 2: return true
	return false


func _simulate(source: Dictionary, box_lo: Vector3i, box_hi: Vector3i, n_ph: int) -> Dictionary:
	lo = box_lo; hi = box_hi
	var cx := (lo.x + hi.x) / 2; var cz := (lo.z + hi.z) / 2
	core = Vector2i(cx, cz)
	gx0 = lo.x - MARGIN; gz0 = lo.z - MARGIN; gw = hi.x - lo.x + 1 + 2 * MARGIN; gd = hi.z - lo.z + 1 + 2 * MARGIN
	# копия блоков области (+3 по высоте)
	for c in source:
		if c.x >= gx0 and c.z >= gz0 and c.x < gx0 + gw and c.z < gz0 + gd and c.y >= lo.y - 1 and c.y <= hi.y + 3:
			var d: Variant = source[c]
			var k: String = str(d.get("kind", "drift")) if d is Dictionary else str(d)
			if d is Dictionary and d.has("root"): k = "door" if str(source.get(GameState.key_cell(str(d.root)), {}).get("kind", "")) == "door" else k
			blocks[c] = k
			hp[c] = int(HP.get(k, SOLID))
			if LIGHT_KINDS.has(k): lights.append(c)
	# уровень, на котором ходят фантомы: первая пустая клетка колонки сердца снизу рамки
	y0 = lo.y + 1
	for y in range(lo.y, hi.y + 1):
		if not blocks.has(Vector3i(cx, y, cz)):
			y0 = y; break
	var total_blocks := 0
	for c in blocks:
		if c.x >= lo.x and c.x <= hi.x and c.z >= lo.z and c.z <= hi.z and c.y >= lo.y and c.y <= hi.y: total_blocks += 1
	_field()
	# фантомы — равномерно по периметру области
	var perim: Array = []
	for x in range(gx0, gx0 + gw): perim.append(Vector2i(x, gz0))
	for z in range(gz0 + 1, gz0 + gd): perim.append(Vector2i(gx0 + gw - 1, z))
	for x in range(gx0 + gw - 2, gx0 - 1, -1): perim.append(Vector2i(x, gz0 + gd - 1))
	for z in range(gz0 + gd - 2, gz0, -1): perim.append(Vector2i(gx0, z))
	var ph: Array = []
	for i in range(n_ph):
		ph.append({"p": perim[(i * perim.size()) / n_ph], "hp": PHANTOM_HP, "alive": true})
	var breaches := 0; var burned := 0; var broken: Array = []; var broken_t: Array = []; var timeline: Array = []
	var dirty := false
	var ticks := 0
	for t in range(MAX_TICKS):
		ticks = t + 1
		var any := false
		var frame: Array = []
		for f in ph:
			if not f.alive: continue
			any = true
			var p: Vector2i = f.p
			if _near_light(p.x, p.y):
				f.hp -= 1
				if f.hp <= 0:
					f.alive = false; burned += 1; continue
			if p == core:
				f.alive = false; breaches += 1; continue
			var best := p; var bd := dist[_idx(p.x, p.y)]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = p + d
				if _in(n.x, n.y) and dist[_idx(n.x, n.y)] < bd and _enterable(n.x, n.y):
					bd = dist[_idx(n.x, n.y)]; best = n
			if best != p:
				if _passable(best.x, best.y):
					f.p = best
				else:
					# грызём самый нижний мешающий блок
					for y in [y0, y0 + 1]:
						var c := Vector3i(best.x, y, best.y)
						if hp.has(c) and int(hp[c]) < SOLID:
							hp[c] = int(hp[c]) - 1
							if int(hp[c]) <= 0:
								hp.erase(c); blocks.erase(c); broken.append(c); broken_t.append(t); dirty = true
								if LIGHT_KINDS.has(_kind_at(c)): lights.erase(c)
								lights = lights.filter(func(l): return blocks.has(l))
							break
			frame.append(f.p)
		timeline.append(frame)
		if dirty:
			_field(); dirty = false
		if not any: break
	var held := breaches == 0
	var grade := "D"
	if held and broken.is_empty(): grade = "S"
	elif held and broken.size() <= 3: grade = "A"
	elif held: grade = "B"
	elif breaches <= 3: grade = "C"
	# функции постройки
	var kinds := {}
	for c in source:
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y and c.z >= lo.z and c.z <= hi.z:
			var d2: Variant = source[c]
			if d2 is Dictionary and not d2.has("root"): kinds[str(d2.get("kind", ""))] = int(kinds.get(str(d2.get("kind", "")), 0)) + 1
	var light_n := 0
	for k in LIGHT_KINDS: light_n += int(kinds.get(k, 0))
	var functions: Array = []
	if held and kinds.has("door") and kinds.has("bed"): functions.append("shelter")
	if light_n >= 3: functions.append("light_ring")
	if grade == "S" and total_blocks >= 50: functions.append("fortress")
	return {"held": held, "grade": grade, "breaches": breaches, "burned": burned, "broken": broken,
		"phantoms": n_ph, "ticks": ticks, "broken_t": broken_t, "timeline": timeline, "y0": y0, "core": Vector3i(core.x, y0, core.y),
		"functions": functions, "blocks_in_frame": total_blocks}
