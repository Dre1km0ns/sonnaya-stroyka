extends Node
## Глобальное состояние «Сонная стройка» v0.5: миры с сидом, инвентарь 9+27,
## вертикальная полоса якорей/маяков, дев-сид 6767676767 (бесконечные ресурсы).

const ItemDB := preload("res://scripts/item_db.gd")

signal world_changed(is_dream: bool)
signal inventory_changed
signal clarity_changed(value: float, max_value: float)
signal hint_changed(text: String)
signal wake_resolved(transferred: int, dust_gained: int, mutations: int)
signal night_changed(is_night: bool)
signal boss_changed(alive: bool)
signal anchor_selected(t: int)
## Короткое всплывающее сообщение над хотбаром (подсказки внизу скрыты по просьбе игрока).
signal toast(text: String)

enum World { WAKE, DREAM }
enum AnchorType { NAIL, WEDGE, ANCHOR3 }

const CLARITY_MAX := 100.0
const CLARITY_DRAIN_PER_SEC := 1.25
const NAIL_COST_REAGENTS := 1
const NAIL_COST_CLARITY := 5.0
const WEDGE_COST_REAGENTS := 3
const WEDGE_COST_CLARITY := 20.0
const WEDGE_SIZE := 5
const ANCHOR3_SIZE := 9
const DUST_PER_BLOCK := 1
const NAIL_CRAFT_DUST := 10
const WEDGE_CRAFT_DUST := 100
const ANCHOR3_CRAFT_DUST := 250
const BEACON_CRAFT_DUST := 30
## Осыпь за убийство моба = 1/5 стоимости клина; босс «Мать блоков» даёт стоимость Якоря3.
const DUST_PER_KILL := WEDGE_CRAFT_DUST / 5
const DUST_PER_BOSS_KILL := ANCHOR3_CRAFT_DUST
const ANCHOR3_COST_REAGENTS := 5
const ANCHOR3_COST_CLARITY := 30.0
const MUTATION_CHANCE := 0.25
const SAVE_FORMAT := 5
const REAGENT_CAP := 100
const REAGENT_TYPE_COUNT := 3
const REAGENT_NAMES: Array[String] = ["реагент1", "реагент2", "реагент3"]
const HOTBAR_SIZE := 9
const MAIN_INV_SIZE := 27
const ITEM_SLOT_COUNT := 36
const MOBS_UNLOCK_AT_EXITS := 2
const DEV_SEED := 6767676767
const INF_COUNT := 999999
const RESOURCE_IDS: Array[String] = ["reagent1", "reagent2", "reagent3", "dust"]

var current_world: World = World.WAKE
var clarity: float = CLARITY_MAX
var nails: int = 3
var wedges: int = 1
var anchors3: int = 0
var beacons: int = 0
var item_slots: Array = []
var selected_slot: int = 0
var dream_exit_count: int = 0
var collected_reagent_ids: Dictionary = {}

## Мир (v0.5): имя, папка сейва, сид, дев-режим, мирный режим.
var world_name: String = ""
var world_folder: String = ""
var seed_text: String = ""
var world_seed: int = 1337
var dev_mode: bool = false
var peaceful: bool = false

## Осыпь и реагенты теперь лежат в инвентаре; свойства оставлены для совместимости.
var dust: int:
	get:
		return count_item("dust")
	set(v):
		_set_item_total("dust", maxi(v, 0))
var reagents: int:
	get:
		return _typed_sum()
	set(v):
		_set_reagent_total(maxi(v, 0))
var reagent_counts: Array:
	get:
		return [get_reagent_count(1), get_reagent_count(2), get_reagent_count(3)]
	set(v):
		if dev_mode:
			return
		for i in range(REAGENT_TYPE_COUNT):
			var want := 0
			if typeof(v) == TYPE_ARRAY and i < v.size():
				want = clampi(int(v[i]), 0, REAGENT_CAP)
			_set_item_total("reagent%d" % (i + 1), want, false)
		inventory_changed.emit()

## Блоки сна: ключ Vector3i → словарь {kind, anchored, mutant}
var dream_blocks: Dictionary = {}
## Блоки яви: ключ Vector3i → словарь {kind, mutant}
var wake_blocks: Dictionary = {}
## Ожидающие якоря: массив словарей {type, origin, cells}
var pending_anchors: Array = []

var selected_anchor: AnchorType = AnchorType.NAIL
var last_hint: String = ""
var awake_time: float = 0.0
var day_time: float = 0.0
var craft_menu_open: bool = false
var inventory_open: bool = false
var paused: bool = false
var _night_flag: bool = false
var boss_alive: bool = false
var last_mined_kind: String = ""
var last_mined_cell: Vector3i = Vector3i.ZERO
var block_stash: Dictionary = {}
const DAY_LENGTH := 300.0
const NIGHT_LENGTH := 300.0
var world_seed_wake: int = 1337
var world_seed_dream: int = 9001
## Снятые клетки процедурного террейна яви: Vector3i -> kind ("hill"/"ruin"/"ground").
var removed_terrain: Dictionary = {}


func _init() -> void:
	_init_default_slots()


func _ready() -> void:
	_ensure_inventory()


func ui_blocked() -> bool:
	return craft_menu_open or inventory_open or paused


# --- Сид и мир ---

static func seed_from_text(text: String) -> int:
	## Пусто → случайный; целое число → как есть; иначе — хеш строки (как в Minecraft).
	var t := text.strip_edges()
	if t == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		return (int(rng.randi()) << 16) ^ int(rng.randi())
	if t.is_valid_int():
		return t.to_int()
	return int(t.hash())


static func derive_dream_seed(s: int) -> int:
	var n := s * 6364136223846793005 + 1442695040888963407
	n = n ^ (n >> 29)
	return n & 0x7fffffffffff


func reset_state() -> void:
	## Полный сброс перед входом в другой мир.
	current_world = World.WAKE
	clarity = CLARITY_MAX
	nails = 3
	wedges = 1
	anchors3 = 0
	beacons = 0
	selected_slot = 0
	dream_exit_count = 0
	collected_reagent_ids = {}
	dream_blocks = {}
	wake_blocks = {}
	pending_anchors = []
	selected_anchor = AnchorType.NAIL
	last_hint = ""
	awake_time = 0.0
	day_time = 0.0
	craft_menu_open = false
	inventory_open = false
	paused = false
	_night_flag = false
	boss_alive = false
	last_mined_kind = ""
	last_mined_cell = Vector3i.ZERO
	block_stash = {}
	removed_terrain = {}
	_init_default_slots()


func begin_world(wname: String, folder: String, stext: String, sv: int, is_peaceful: bool = false) -> void:
	reset_state()
	world_name = wname
	world_folder = folder
	seed_text = stext
	world_seed = sv
	world_seed_wake = sv
	world_seed_dream = derive_dream_seed(sv)
	dev_mode = sv == DEV_SEED
	peaceful = is_peaceful
	if dev_mode:
		_fill_dev_inventory()


func is_dev() -> bool:
	return dev_mode


func _fill_dev_inventory() -> void:
	## Дев-сид: по стаку всего, количество бесконечное (∞, не уменьшается).
	_init_default_slots()
	var ids := ["pickaxe", "sword", "torch", "workbench", "reagent1", "reagent2", "reagent3", "dust", "hill",
		"ruin", "ground", "drift", "mouth"]
	for i in range(ids.size()):
		item_slots[i] = {"id": ids[i], "name": ItemDB.display_name(ids[i]), "count": 1}
	inventory_changed.emit()


func _init_default_slots() -> void:
	item_slots = []
	for i in range(ITEM_SLOT_COUNT):
		item_slots.append(_empty_slot())


func _empty_slot() -> Dictionary:
	return {"id": "", "name": "", "count": 0}


func _ensure_inventory() -> void:
	if item_slots.size() != ITEM_SLOT_COUNT:
		var old := item_slots.duplicate(true)
		_init_default_slots()
		for i in range(mini(old.size(), ITEM_SLOT_COUNT)):
			if typeof(old[i]) == TYPE_DICTIONARY:
				item_slots[i] = old[i]


func reagent_type_name(type_id: int) -> String:
	var i := clampi(type_id - 1, 0, REAGENT_TYPE_COUNT - 1)
	return REAGENT_NAMES[i]


# --- Инвентарь 9+27 ---

func raw_count(id: String) -> int:
	var n := 0
	for s in item_slots:
		if str(s.get("id", "")) == id:
			n += int(s.get("count", 0))
	return n


func count_item(id: String) -> int:
	if dev_mode and (id in RESOURCE_IDS or raw_count(id) > 0):
		return INF_COUNT
	return raw_count(id)


func is_infinite_slot(index: int) -> bool:
	if not dev_mode or index < 0 or index >= item_slots.size():
		return false
	return str(item_slots[index].get("id", "")) != ""


func add_item_count(id: String, count: int) -> int:
	## Кладёт count штук: сначала в существующие стаки, потом в пустые (хотбар первым). Возвращает сколько вошло.
	_ensure_inventory()
	if id == "" or count <= 0:
		return 0
	if ItemDB.is_special(id):
		_add_special(id, count)
		return count
	var left := count
	var cap := ItemDB.max_stack(id)
	for i in range(ITEM_SLOT_COUNT):
		if left <= 0:
			break
		var s: Dictionary = item_slots[i]
		if str(s.get("id", "")) == id and int(s.get("count", 0)) < cap:
			var put := mini(cap - int(s.get("count", 0)), left)
			s["count"] = int(s.get("count", 0)) + put
			left -= put
	for i in range(ITEM_SLOT_COUNT):
		if left <= 0:
			break
		if str(item_slots[i].get("id", "")) == "":
			var put2 := mini(cap, left)
			item_slots[i] = {"id": id, "name": ItemDB.display_name(id, id), "count": put2}
			left -= put2
	if left != count:
		inventory_changed.emit()
	return count - left



func remove_item(id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if dev_mode and (id in RESOURCE_IDS or raw_count(id) > 0):
		return true
	if raw_count(id) < amount:
		return false
	var left := amount
	# Сначала с конца инвентаря, чтобы хотбар оставался.
	for i in range(ITEM_SLOT_COUNT - 1, -1, -1):
		if left <= 0:
			break
		var s: Dictionary = item_slots[i]
		if str(s.get("id", "")) != id:
			continue
		var take := mini(int(s.get("count", 0)), left)
		s["count"] = int(s.get("count", 0)) - take
		left -= take
		if int(s["count"]) <= 0:
			item_slots[i] = _empty_slot()
	inventory_changed.emit()
	return true


func _set_item_total(id: String, value: int, emit: bool = true) -> void:
	if dev_mode:
		return
	var cur := raw_count(id)
	if value > cur:
		add_item_count(id, value - cur)
	elif value < cur:
		var left := cur - value
		for i in range(ITEM_SLOT_COUNT - 1, -1, -1):
			if left <= 0:
				break
			var s: Dictionary = item_slots[i]
			if str(s.get("id", "")) != id:
				continue
			var take := mini(int(s.get("count", 0)), left)
			s["count"] = int(s.get("count", 0)) - take
			left -= take
			if int(s["count"]) <= 0:
				item_slots[i] = _empty_slot()
	if emit:
		inventory_changed.emit()


func _set_reagent_total(v: int) -> void:
	if dev_mode:
		return
	var typed := _typed_sum()
	if v > typed:
		var extra := v - typed
		_set_item_total("reagent1", mini(get_reagent_count(1) + extra, REAGENT_CAP))
	elif v < typed:
		var diff := typed - v
		for i in range(REAGENT_TYPE_COUNT):
			if diff <= 0:
				break
			var have := get_reagent_count(i + 1)
			var take := mini(have, diff)
			_set_item_total("reagent%d" % (i + 1), have - take, false)
			diff -= take
		inventory_changed.emit()


func swap_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= ITEM_SLOT_COUNT or b >= ITEM_SLOT_COUNT or a == b:
		return
	var t: Dictionary = item_slots[a]
	item_slots[a] = item_slots[b]
	item_slots[b] = t
	inventory_changed.emit()


func set_slot(i: int, data: Dictionary) -> void:
	if i < 0 or i >= ITEM_SLOT_COUNT:
		return
	if data.is_empty() or str(data.get("id", "")) == "" or int(data.get("count", 0)) <= 0:
		item_slots[i] = _empty_slot()
	else:
		item_slots[i] = {"id": str(data["id"]), "name": str(data.get("name", ItemDB.display_name(str(data["id"])))), "count": int(data["count"])}
	inventory_changed.emit()


func get_slot(i: int) -> Dictionary:
	if i < 0 or i >= item_slots.size():
		return _empty_slot()
	return item_slots[i]


func quick_move(i: int) -> void:
	## Shift+клик: хотбар ↔ основной инвентарь.
	var s: Dictionary = get_slot(i)
	var id := str(s.get("id", ""))
	if id == "":
		return
	var range_from := HOTBAR_SIZE if i < HOTBAR_SIZE else 0
	var range_to := ITEM_SLOT_COUNT if i < HOTBAR_SIZE else HOTBAR_SIZE
	var cap := ItemDB.max_stack(id)
	var left := int(s.get("count", 0))
	for j in range(range_from, range_to):
		if left <= 0:
			break
		var t: Dictionary = item_slots[j]
		if str(t.get("id", "")) == id and int(t.get("count", 0)) < cap:
			var put := mini(cap - int(t["count"]), left)
			t["count"] = int(t["count"]) + put
			left -= put
	for j in range(range_from, range_to):
		if left <= 0:
			break
		if str(item_slots[j].get("id", "")) == "":
			var put2 := mini(cap, left)
			item_slots[j] = {"id": id, "name": str(s.get("name", id)), "count": put2}
			left -= put2
	if left <= 0:
		item_slots[i] = _empty_slot()
	else:
		item_slots[i]["count"] = left
	inventory_changed.emit()


func special_count(id: String) -> int:
	match id:
		"nail":
			return nails
		"wedge":
			return wedges
		"anchor3":
			return anchors3
		"beacon":
			return beacons
	return 0


func _add_special(id: String, count: int) -> void:
	match id:
		"nail":
			nails += count
		"wedge":
			wedges += count
		"anchor3":
			anchors3 += count
		"beacon":
			beacons += count
	inventory_changed.emit()


func get_reagent_count(type_id: int) -> int:
	if type_id < 1 or type_id > REAGENT_TYPE_COUNT:
		return 0
	if dev_mode:
		return INF_COUNT
	return raw_count("reagent%d" % type_id)


func _typed_sum() -> int:
	var s := 0
	for i in range(REAGENT_TYPE_COUNT):
		s += get_reagent_count(i + 1)
	return s


func _sync_reagent_total() -> void:
	pass


func _reconcile_reagents() -> void:
	pass


func add_typed_reagent(type_id: int, amount: int) -> int:
	var i := clampi(type_id - 1, 0, REAGENT_TYPE_COUNT - 1)
	if dev_mode:
		return maxi(amount, 0)
	var have := raw_count("reagent%d" % (i + 1))
	var room := REAGENT_CAP - have
	var add := mini(maxi(amount, 0), room)
	if add <= 0:
		return 0
	return add_item_count("reagent%d" % (i + 1), add)


func spend_reagents(amount: int, emit_changed: bool = true) -> bool:
	if amount <= 0 or dev_mode:
		return true
	if reagents < amount:
		return false
	var left := amount
	for i in range(REAGENT_TYPE_COUNT):
		var have := get_reagent_count(i + 1)
		var take := mini(have, left)
		if take > 0:
			_set_item_total("reagent%d" % (i + 1), have - take, false)
		left -= take
		if left <= 0:
			break
	if emit_changed:
		inventory_changed.emit()
	return true


func mobs_unlocked() -> bool:
	if peaceful:
		return false
	return dream_exit_count >= MOBS_UNLOCK_AT_EXITS


func mark_reagent_collected(id: String) -> void:
	if id == "":
		return
	collected_reagent_ids[id] = true


func is_reagent_collected(id: String) -> bool:
	return id != "" and collected_reagent_ids.has(id)


func select_item_slot(index: int) -> void:
	_ensure_inventory()
	selected_slot = clampi(index, 0, HOTBAR_SIZE - 1)
	var item: Dictionary = item_slots[selected_slot]
	var id := str(item.get("id", ""))
	if id == "":
		set_hint("Слот %d: пусто." % (selected_slot + 1))
	else:
		set_hint("Слот %d: %s" % [selected_slot + 1, ItemDB.display_name(id, str(item.get("name", id)))])
	inventory_changed.emit()


func cycle_item_slot(delta: int) -> void:
	_ensure_inventory()
	select_item_slot(posmod(selected_slot + delta, HOTBAR_SIZE))


func get_selected_item() -> Dictionary:
	_ensure_inventory()
	return item_slots[selected_slot]


func add_item(id: String, item_name: String, count: int = 1) -> int:
	## Совместимость: возвращает индекс слота, куда лёг предмет, или -1 (нет места).
	_ensure_inventory()
	if id == "":
		return -1
	if ItemDB.is_special(id):
		_add_special(id, count)
		return 0
	var cap := ItemDB.max_stack(id)
	var target := -1
	for i in range(ITEM_SLOT_COUNT):
		var s: Dictionary = item_slots[i]
		if str(s.get("id", "")) == id and int(s.get("count", 0)) + count <= cap:
			target = i
			break
	if target < 0:
		for i in range(ITEM_SLOT_COUNT):
			if str(item_slots[i].get("id", "")) == "":
				target = i
				break
	if target < 0:
		var added := add_item_count(id, count)
		return 0 if added == count else -1
	if str(item_slots[target].get("id", "")) == "":
		var nm := item_name if item_name != "" else id
		if ItemDB.ITEMS.has(id):
			nm = ItemDB.display_name(id)
		item_slots[target] = {"id": id, "name": nm, "count": mini(count, cap)}
		if count > cap:
			add_item_count(id, count - cap)
	else:
		item_slots[target]["count"] = int(item_slots[target].get("count", 0)) + count
	inventory_changed.emit()
	return target


func slot_display_count(index: int) -> int:
	_ensure_inventory()
	if index < 0 or index >= item_slots.size():
		return 0
	if is_infinite_slot(index):
		return INF_COUNT
	return int(item_slots[index].get("count", 0))


func count_text(n: int) -> String:
	return "∞" if n >= INF_COUNT else str(n)


func inventory_status_text() -> String:
	var extra := ""
	if not block_stash.is_empty():
		var bits: Array[String] = []
		for k in block_stash.keys():
			bits.append("%s x%d" % [block_display_name(str(k)), int(block_stash[k])])
		extra = "   запасы: " + ", ".join(bits)
	return "Осыпь: %s   Гвозди: %s   Клинья: %s   Якорь3: %s   Маяки: %s\n%s: %s   %s: %s   %s: %s%s" % [
		count_text(dust), count_text(_sp(nails)), count_text(_sp(wedges)), count_text(_sp(anchors3)), count_text(_sp(beacons)),
		reagent_type_name(1), count_text(get_reagent_count(1)),
		reagent_type_name(2), count_text(get_reagent_count(2)),
		reagent_type_name(3), count_text(get_reagent_count(3)),
		extra,
	]


func _sp(n: int) -> int:
	return INF_COUNT if dev_mode else n


func special_display_count(id: String) -> int:
	return _sp(special_count(id))


func recipe_defs() -> Array:
	return [
		{"id": "nail", "name": "Гвоздь", "where": "dream", "dust": NAIL_CRAFT_DUST, "gives": "nails"},
		{"id": "wedge", "name": "Клин", "where": "dream", "dust": WEDGE_CRAFT_DUST, "gives": "wedges"},
		{"id": "anchor3", "name": "Якорь3", "where": "dream", "dust": ANCHOR3_CRAFT_DUST, "gives": "anchors3"},
		{"id": "beacon", "name": "Маяк", "where": "dream", "dust": BEACON_CRAFT_DUST, "reagent3": 1, "gives": "beacons"},
		{"id": "workbench", "name": "Верстак", "where": "dream", "reagent1": 10, "item": "workbench", "item_name": "Верстак"},
		{"id": "pickaxe", "name": "Кирка", "where": "workbench", "reagent2": 2, "reagent3": 3, "item": "pickaxe", "item_name": "Кирка"},
		{"id": "torch", "name": "Факел", "where": "workbench", "reagent1": 1, "reagent2": 1, "item": "torch", "item_name": "Факел"},
		{"id": "sword", "name": "Меч", "where": "workbench", "reagent1": 5, "reagent2": 2, "item": "sword", "item_name": "Меч"},
	]


func find_recipe(rid: String) -> Dictionary:
	for rec in recipe_defs():
		if str(rec.get("id", "")) == rid:
			return rec
	return {}


func recipe_available(rec: Dictionary, ctx: Dictionary = {}) -> bool:
	if rec.is_empty():
		return false
	var where := str(rec.get("where", "anywhere"))
	var dreaming := bool(ctx.get("is_dream", is_dream()))
	var bench := bool(ctx.get("at_workbench", false))
	# Верстак показывает только верстачные рецепты (без якорей).
	if bench:
		return where == "workbench"
	if where == "workbench":
		return false
	if where == "dream":
		return dreaming
	return true


func get_visible_recipes(ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for rec in recipe_defs():
		if recipe_available(rec, ctx):
			out.append(rec)
	return out


func can_afford_recipe(rec: Dictionary) -> bool:
	if rec.is_empty():
		return false
	if dust < int(rec.get("dust", 0)):
		return false
	if get_reagent_count(1) < int(rec.get("reagent1", 0)):
		return false
	if get_reagent_count(2) < int(rec.get("reagent2", 0)):
		return false
	if get_reagent_count(3) < int(rec.get("reagent3", 0)):
		return false
	return true


func recipe_cost_text(rec: Dictionary) -> String:
	var parts: Array[String] = []
	if int(rec.get("dust", 0)) > 0:
		parts.append("%d осыпи" % int(rec.get("dust", 0)))
	if int(rec.get("reagent1", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent1", 0)), reagent_type_name(1)])
	if int(rec.get("reagent2", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent2", 0)), reagent_type_name(2)])
	if int(rec.get("reagent3", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent3", 0)), reagent_type_name(3)])
	return ", ".join(parts) if not parts.is_empty() else "бесплатно"


func recipe_label(rec: Dictionary) -> String:

	var parts: Array[String] = []
	if int(rec.get("dust", 0)) > 0:
		parts.append("%d осыпи" % int(rec.get("dust", 0)))
	if int(rec.get("reagent1", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent1", 0)), reagent_type_name(1)])
	if int(rec.get("reagent2", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent2", 0)), reagent_type_name(2)])
	if int(rec.get("reagent3", 0)) > 0:
		parts.append("%d %s" % [int(rec.get("reagent3", 0)), reagent_type_name(3)])
	var cost := ", ".join(parts) if not parts.is_empty() else "бесплатно"
	return "%s  (%s)" % [str(rec.get("name", rec.get("id", "?"))), cost]


func spend_typed_reagent(type_id: int, amount: int) -> bool:
	if amount <= 0 or dev_mode:
		return true
	if get_reagent_count(type_id) < amount:
		return false
	return remove_item("reagent%d" % type_id, amount)


func consume_item(id: String, amount: int = 1) -> bool:
	_ensure_inventory()
	if ItemDB.is_special(id):
		if dev_mode:
			return true
		var have := special_count(id)
		if have < amount:
			return false
		_add_special(id, -amount)
		return true
	# Сначала выбранный слот хотбара, затем остальные.
	if dev_mode:
		return raw_count(id) > 0 or id in RESOURCE_IDS
	var sel: Dictionary = item_slots[selected_slot]
	if str(sel.get("id", "")) == id and int(sel.get("count", 0)) >= amount:
		sel["count"] = int(sel["count"]) - amount
		if int(sel["count"]) <= 0:
			item_slots[selected_slot] = _empty_slot()
		inventory_changed.emit()
		return true
	return remove_item(id, amount)


func selected_is(id: String) -> bool:
	return str(get_selected_item().get("id", "")) == id


func mine_wake_block(cell: Vector3i) -> bool:
	if is_dream():
		set_hint("Киркой пользуются в яви.")
		return false
	if not selected_is("pickaxe"):
		set_hint("Чтобы ломать блоки яви, возьми кирку.")
		return false
	if not wake_blocks.has(cell):
		return false
	var data: Dictionary = wake_blocks[cell]
	var kind := str(data.get("kind", "drift"))
	wake_blocks.erase(cell)
	last_mined_kind = kind
	last_mined_cell = cell
	inventory_changed.emit()
	set_hint("Кирка: выпал блок «%s»." % block_display_name(kind))
	return true


func is_terrain_removed(cell: Vector3i) -> bool:
	return removed_terrain.has(cell)


func terrain_removed_kind(cell: Vector3i) -> String:
	return str(removed_terrain.get(cell, ""))


func remove_terrain_cell(cell: Vector3i, kind: String) -> bool:
	if removed_terrain.has(cell):
		return false
	var k := kind if kind != "" else "hill"
	removed_terrain[cell] = k
	last_mined_kind = k
	last_mined_cell = cell
	set_hint("Кирка: выпал блок «%s»." % block_display_name(k))
	return true


func craft_recipe(rid: String, ctx: Dictionary = {}) -> bool:
	var rec := find_recipe(rid)
	if rec.is_empty():
		return false
	if not recipe_available(rec, ctx):
		set_hint("Этот рецепт здесь недоступен.")
		return false
	if not can_afford_recipe(rec):
		set_hint("Не хватает ресурсов для «%s»." % str(rec.get("name", rid)))
		return false
	dust -= int(rec.get("dust", 0))
	if int(rec.get("reagent1", 0)) > 0:
		spend_typed_reagent(1, int(rec.get("reagent1", 0)))
	if int(rec.get("reagent2", 0)) > 0:
		spend_typed_reagent(2, int(rec.get("reagent2", 0)))
	if int(rec.get("reagent3", 0)) > 0:
		spend_typed_reagent(3, int(rec.get("reagent3", 0)))
	var gives := str(rec.get("gives", ""))
	if gives == "nails":
		nails += 1
	elif gives == "wedges":
		wedges += 1
	elif gives == "anchors3":
		anchors3 += 1
	elif gives == "beacons":
		beacons += 1
	var item_id := str(rec.get("item", ""))
	if item_id != "" and dev_mode and raw_count(item_id) > 0:
		item_id = ""
	if item_id != "":
		if add_item(item_id, str(rec.get("item_name", item_id)), 1) < 0:
			set_hint("Нет свободного слота для «%s»." % str(rec.get("item_name", item_id)))
			return false
	inventory_changed.emit()
	set_hint("Скрафчено: %s." % str(rec.get("name", rid)))
	return true



func is_night() -> bool:
	var cycle := DAY_LENGTH + NIGHT_LENGTH
	if cycle <= 0.0:
		return false
	var t := fmod(day_time, cycle)
	if t < 0.0:
		t += cycle
	return t >= DAY_LENGTH


func notify_night_from_time() -> void:
	var n := is_night()
	if n != _night_flag:
		_night_flag = n
		night_changed.emit(n)



func set_boss_alive(on: bool) -> void:
	if boss_alive == on:
		return
	boss_alive = on
	boss_changed.emit(on)


func block_display_name(kind: String) -> String:
	match kind:
		"workbench":
			return "Верстак"
		"torch":
			return "Факел"
		"mouth":
			return "Рот"
		"sword":
			return "Меч"
		"pickaxe":
			return "Кирка"
		"hill":
			return "Холм"
		"ruin":
			return "Руинный блок"
		"ground":
			return "Грунт"
		"drift":
			return "Дрейф-блок"
		"beacon":
			return "Маяк"
		_:
			return "Блок"


func is_placeable_block(id: String) -> bool:
	return id in ["drift", "mouth", "workbench", "hill", "ruin", "ground"]


func add_mined_block(kind: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	if ItemDB.is_special(kind):
		_add_special(kind, amount)
		return
	var added := add_item_count(kind, amount)
	if added >= amount:
		return
	block_stash[kind] = int(block_stash.get(kind, 0)) + (amount - added)
	inventory_changed.emit()


func consume_placeable(kind: String) -> bool:
	if consume_item(kind, 1):
		return true
	if int(block_stash.get(kind, 0)) > 0:
		block_stash[kind] = int(block_stash[kind]) - 1
		inventory_changed.emit()
		return true
	return false

func place_wake_block(cell: Vector3i, kind: String) -> bool:
	if is_dream():
		return false
	if wake_blocks.has(cell):
		return false
	wake_blocks[cell] = {"kind": kind, "mutant": false}
	inventory_changed.emit()
	return true


func is_dream() -> bool:
	return current_world == World.DREAM


func set_hint(text: String) -> void:
	last_hint = text
	hint_changed.emit(text)


func add_reagents(amount: int) -> void:
	add_typed_reagent(1, amount)


func spend_clarity(amount: float) -> bool:
	if dev_mode:
		return true
	if clarity < amount:
		return false
	clarity = maxf(0.0, clarity - amount)
	clarity_changed.emit(clarity, CLARITY_MAX)
	return true


func drain_clarity(delta: float) -> void:
	if not is_dream():
		return
	if dev_mode:
		return
	clarity = maxf(0.0, clarity - CLARITY_DRAIN_PER_SEC * delta)
	clarity_changed.emit(clarity, CLARITY_MAX)
	if clarity <= 0.0:
		set_hint("Ясность иссякла — принудительное пробуждение!")


func craft_nail_from_dust() -> bool:
	return craft_recipe("nail")


func craft_wedge_from_dust() -> bool:
	return craft_recipe("wedge")


func craft_anchor3_from_dust() -> bool:
	return craft_recipe("anchor3")


func craft_selected_from_dust() -> bool:
	if selected_anchor == AnchorType.WEDGE:
		return craft_wedge_from_dust()
	if selected_anchor == AnchorType.ANCHOR3:
		return craft_anchor3_from_dust()
	return craft_nail_from_dust()


func select_anchor(t: AnchorType) -> void:
	selected_anchor = t
	anchor_selected.emit(int(t))
	inventory_changed.emit()
	if t == AnchorType.NAIL:
		set_hint("Выбран Гвоздь (1 блок). Q — заякорить. C — меню крафта (%d осыпи)." % NAIL_CRAFT_DUST)
	elif t == AnchorType.WEDGE:
		set_hint("Выбран Клин (~%dx%dx%d). Q — заякорить. C — меню крафта (%d осыпи)." % [
			WEDGE_SIZE, WEDGE_SIZE, WEDGE_SIZE, WEDGE_CRAFT_DUST
		])
	else:
		set_hint("Выбран Якорь3 (~%dx%dx%d). Q — заякорить. C — меню крафта (%d осыпи)." % [
			ANCHOR3_SIZE, ANCHOR3_SIZE, ANCHOR3_SIZE, ANCHOR3_CRAFT_DUST
		])


func cycle_anchor(delta: int = 1) -> void:
	select_anchor(posmod(int(selected_anchor) + delta, 3) as AnchorType)


func can_afford_anchor(t: AnchorType) -> bool:
	if dev_mode:
		return true
	if t == AnchorType.NAIL:
		return nails >= 1 and reagents >= NAIL_COST_REAGENTS and clarity >= NAIL_COST_CLARITY
	if t == AnchorType.WEDGE:
		return wedges >= 1 and reagents >= WEDGE_COST_REAGENTS and clarity >= WEDGE_COST_CLARITY
	return anchors3 >= 1 and reagents >= ANCHOR3_COST_REAGENTS and clarity >= ANCHOR3_COST_CLARITY


func try_place_anchor(origin: Vector3i) -> bool:
	if not is_dream():
		set_hint("Якоря ставятся только во сне.")
		return false
	var t := selected_anchor
	if not can_afford_anchor(t):
		set_hint("Не хватает ресурсов/ясности для якоря.")
		return false

	var cells: Array[Vector3i] = []
	if t == AnchorType.NAIL:
		if not dream_blocks.has(origin):
			set_hint("Гвоздь: целься в существующий блок.")
			return false
		cells.append(origin)
		if not dev_mode:
			nails -= 1
		spend_reagents(NAIL_COST_REAGENTS, false)
		spend_clarity(NAIL_COST_CLARITY)
	else:
		var zone := WEDGE_SIZE if t == AnchorType.WEDGE else ANCHOR3_SIZE
		var half := zone / 2
		for x in range(origin.x - half, origin.x - half + zone):
			for y in range(origin.y - half, origin.y - half + zone):
				for z in range(origin.z - half, origin.z - half + zone):
					var c := Vector3i(x, y, z)
					if dream_blocks.has(c):
						cells.append(c)
		if cells.is_empty():
			set_hint("Якорь: в зоне нет блоков.")
			return false
		if t == AnchorType.WEDGE:
			if not dev_mode:
				wedges -= 1
			spend_reagents(WEDGE_COST_REAGENTS, false)
			spend_clarity(WEDGE_COST_CLARITY)
		else:
			if not dev_mode:
				anchors3 -= 1
			spend_reagents(ANCHOR3_COST_REAGENTS, false)
			spend_clarity(ANCHOR3_COST_CLARITY)

	for c in cells:
		var data: Dictionary = dream_blocks[c]
		data["anchored"] = true
		dream_blocks[c] = data

	pending_anchors.append({"type": t, "origin": origin, "cells": cells})
	inventory_changed.emit()
	var aname := "Гвоздь"
	if t == AnchorType.WEDGE:
		aname = "Клин"
	elif t == AnchorType.ANCHOR3:
		aname = "Якорь3"
	set_hint("%s: заякорено %d блок(ов). F — проснуться." % [aname, cells.size()])
	return true


func enter_dream() -> void:
	current_world = World.DREAM
	clarity = CLARITY_MAX
	awake_time = 0.0
	clarity_changed.emit(clarity, CLARITY_MAX)
	world_changed.emit(true)
	set_hint("Сон. ЛКМ — блок, ПКМ — снять, R — сменить якорь, Q — заякорить, C — меню крафта, F — проснуться.")


func resolve_wake() -> Dictionary:
	## Переносит новые якоря в явь с тем же Vector3i (высота совпадает).
	## Незаякоренные блоки сна остаются — стройку можно продолжать в следующих сессиях.
	var transferred := 0
	var dust_gained := 0
	var mutations := 0
	var newly: Dictionary = {}

	for a in pending_anchors:
		for c in a["cells"]:
			newly[c] = true

	for key in newly.keys():
		var cell: Vector3i = key
		if not dream_blocks.has(cell):
			continue
		if wake_blocks.has(cell):
			continue
		var data: Dictionary = dream_blocks[cell]
		var kind := str(data.get("kind", "drift"))
		var mutant := false
		if kind != "workbench" and kind != "torch" and kind != "beacon" and randf() < MUTATION_CHANCE:
			mutant = true
			mutations += 1
			kind = "mouth"
		wake_blocks[cell] = {
			"kind": kind,
			"mutant": mutant,
		}
		transferred += 1

	dust += dust_gained
	pending_anchors.clear()
	current_world = World.WAKE
	dream_exit_count += 1
	clarity = CLARITY_MAX
	clarity_changed.emit(clarity, CLARITY_MAX)
	inventory_changed.emit()
	world_changed.emit(false)
	wake_resolved.emit(transferred, dust_gained, mutations)
	var msg := "Пробуждение: +%d блоков в явь (сон сохранён)" % transferred
	if mutations > 0:
		msg += ", мутаций: %d (блок «рот»)" % mutations
	set_hint(msg)
	return {"transferred": transferred, "dust": dust_gained, "mutations": mutations}


func place_dream_block(cell: Vector3i, kind: String = "drift") -> bool:
	if dream_blocks.has(cell):
		return false
	dream_blocks[cell] = {"kind": kind, "anchored": false, "mutant": false}
	return true


func remove_dream_block(cell: Vector3i) -> bool:
	if not dream_blocks.has(cell):
		return false
	dream_blocks.erase(cell)
	for a in pending_anchors:
		var cells: Array = a["cells"]
		var idx := cells.find(cell)
		if idx >= 0:
			cells.remove_at(idx)
	return true


func steal_resource_hardcore(amount: int = 1) -> String:
	## Шовник: сначала осыпь (до amount), иначе реагент. amount>1 — элита/хардкор.
	## Дев-сид: ресурсы бесконечны, украсть нечего.
	var take := maxi(1, amount)
	if dev_mode:
		return "none"
	var d := dust
	if d > 0:
		var got := mini(d, take)
		dust = d - got
		return "dust:%d" % got
	for i in range(REAGENT_TYPE_COUNT):
		if get_reagent_count(i + 1) > 0:
			remove_item("reagent%d" % (i + 1), 1)
			return "reagent"
	return "none"


func reward_kill(is_boss: bool = false, who: String = "") -> int:
	var amount := DUST_PER_BOSS_KILL if is_boss else DUST_PER_KILL
	if not dev_mode:
		add_item_count("dust", amount)
	var prefix := (who + " повержен: ") if who != "" else ""
	set_hint("%s+%d осыпи" % [prefix, amount])
	toast.emit("%s+%d осыпи" % [prefix, amount])
	return amount


func count_enemies_in_tree(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("seam_creature").size()


# --- Save / load serialization ---

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_FORMAT,
		"world": "dream" if is_dream() else "wake",
		"world_name": world_name,
		"seed_text": seed_text,
		"world_seed": str(world_seed),
		"dev_mode": dev_mode,
		"peaceful": peaceful,
		"clarity": clarity,
		"nails": nails,
		"wedges": wedges,
		"anchors3": anchors3,
		"beacons": beacons,
		"day_time": day_time,
		"selected_anchor": int(selected_anchor),
		"selected_slot": selected_slot,
		"item_slots": item_slots.duplicate(true),
		"reagent_counts": [raw_count("reagent1"), raw_count("reagent2"), raw_count("reagent3")],
		"dust": raw_count("dust"),
		"block_stash": block_stash.duplicate(),
		"dream_exit_count": dream_exit_count,
		"collected_reagent_ids": collected_reagent_ids.keys(),
		"awake_time": awake_time,
		"world_seed_wake": str(world_seed_wake),
		"world_seed_dream": str(world_seed_dream),
		"wake_blocks": _blocks_to_json(wake_blocks),
		"dream_blocks": _blocks_to_json(dream_blocks),
		"pending_anchors": _anchors_to_json(pending_anchors),
		"removed_terrain": _cells_kind_to_json(removed_terrain),
	}


static func _seed_val(v: Variant, fallback: int) -> int:
	if v == null:
		return fallback
	if typeof(v) == TYPE_STRING:
		var s := str(v)
		return s.to_int() if s.is_valid_int() else fallback
	return int(v)


func apply_save_dict(data: Dictionary) -> void:
	var fmt := int(data.get("version", 4))
	nails = int(data.get("nails", 3))
	wedges = int(data.get("wedges", 1))
	anchors3 = int(data.get("anchors3", 0))
	beacons = int(data.get("beacons", 0))
	clarity = float(data.get("clarity", CLARITY_MAX))
	awake_time = float(data.get("awake_time", 0.0))
	day_time = float(data.get("day_time", 0.0))
	world_seed_wake = _seed_val(data.get("world_seed_wake", null), world_seed_wake if world_folder != "" else 1337)
	world_seed_dream = _seed_val(data.get("world_seed_dream", null), world_seed_dream if world_folder != "" else 9001)
	if data.has("world_seed"):
		world_seed = _seed_val(data["world_seed"], world_seed)
	selected_anchor = clampi(int(data.get("selected_anchor", 0)), 0, 2) as AnchorType
	dream_exit_count = int(data.get("dream_exit_count", data.get("wake_count", 0)))
	selected_slot = clampi(int(data.get("selected_slot", 0)), 0, HOTBAR_SIZE - 1)
	_init_default_slots()
	var slots: Variant = data.get("item_slots", null)
	if fmt >= 5 and typeof(slots) == TYPE_ARRAY:
		for i in range(mini(slots.size(), ITEM_SLOT_COUNT)):
			var s: Variant = slots[i]
			if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) != "" and int(s.get("count", 0)) > 0:
				item_slots[i] = {"id": str(s["id"]), "name": str(s.get("name", "")), "count": int(s["count"])}
	else:
		# Сейв v4 и старше: 5 слотов + отдельные счётчики реагентов/осыпи. Якоря уходят в полосу.
		var dev_was := dev_mode
		dev_mode = false
		if typeof(slots) == TYPE_ARRAY:
			for s2 in slots:
				if typeof(s2) != TYPE_DICTIONARY:
					continue
				var sid := str(s2.get("id", ""))
				if sid == "" or sid == "nail" or sid == "wedge" or sid == "anchor3":
					continue
				add_item_count(sid, maxi(1, int(s2.get("count", 1))))
		var rc: Variant = data.get("reagent_counts", null)
		if typeof(rc) == TYPE_ARRAY:
			for i2 in range(mini(REAGENT_TYPE_COUNT, rc.size())):
				add_item_count("reagent%d" % (i2 + 1), clampi(int(rc[i2]), 0, REAGENT_CAP))
		elif data.has("reagents"):
			add_item_count("reagent1", clampi(int(data["reagents"]), 0, REAGENT_CAP))
		add_item_count("dust", maxi(0, int(data.get("dust", 0))))
		dev_mode = dev_was
	block_stash = {}
	var bs: Variant = data.get("block_stash", {})
	if typeof(bs) == TYPE_DICTIONARY:
		for k in bs.keys():
			block_stash[str(k)] = int(bs[k])
	collected_reagent_ids = {}
	var col: Variant = data.get("collected_reagent_ids", [])
	if typeof(col) == TYPE_ARRAY:
		for cid in col:
			collected_reagent_ids[str(cid)] = true
	elif typeof(col) == TYPE_DICTIONARY:
		for cid2 in col.keys():
			collected_reagent_ids[str(cid2)] = true
	wake_blocks = _blocks_from_json(data.get("wake_blocks", {}))
	dream_blocks = _blocks_from_json(data.get("dream_blocks", {}))
	pending_anchors = _anchors_from_json(data.get("pending_anchors", []))
	removed_terrain = _cells_kind_from_json(data.get("removed_terrain", {}))
	if dev_mode:
		_ensure_dev_items()
	var w := str(data.get("world", "wake"))
	current_world = World.DREAM if w == "dream" else World.WAKE
	clarity_changed.emit(clarity, CLARITY_MAX)
	inventory_changed.emit()
	world_changed.emit(is_dream())


func _ensure_dev_items() -> void:
	var any := false
	for s in item_slots:
		if str(s.get("id", "")) != "":
			any = true
			break
	if not any:
		_fill_dev_inventory()


func _ensure_anchor3_slot() -> void:
	_ensure_inventory()


func _blocks_to_json(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		var c: Vector3i = k
		var key := "%d,%d,%d" % [c.x, c.y, c.z]
		var d: Dictionary = src[k]
		out[key] = {
			"kind": str(d.get("kind", "drift")),
			"anchored": bool(d.get("anchored", false)),
			"mutant": bool(d.get("mutant", false)),
		}
	return out


func _blocks_from_json(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for key in src.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 3:
			continue
		var c := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var d: Dictionary = src[key]
		out[c] = {
			"kind": str(d.get("kind", "drift")),
			"anchored": bool(d.get("anchored", false)),
			"mutant": bool(d.get("mutant", false)),
		}
	return out


func _anchors_to_json(src: Array) -> Array:
	var out: Array = []
	for a in src:
		var cells_out: Array = []
		for c in a.get("cells", []):
			var cell: Vector3i = c
			cells_out.append([cell.x, cell.y, cell.z])
		var origin: Vector3i = a.get("origin", Vector3i.ZERO)
		out.append({
			"type": int(a.get("type", 0)),
			"origin": [origin.x, origin.y, origin.z],
			"cells": cells_out,
		})
	return out


func _anchors_from_json(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for a in src:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var cells: Array[Vector3i] = []
		for arr in a.get("cells", []):
			if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
				cells.append(Vector3i(int(arr[0]), int(arr[1]), int(arr[2])))
		var o: Array = a.get("origin", [0, 0, 0])
		var origin := Vector3i(int(o[0]), int(o[1]), int(o[2])) if o.size() >= 3 else Vector3i.ZERO
		out.append({"type": int(a.get("type", 0)), "origin": origin, "cells": cells})
	return out

func _cells_kind_to_json(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		var c: Vector3i = k
		out["%d,%d,%d" % [c.x, c.y, c.z]] = str(src[k])
	return out


func _cells_kind_from_json(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for key in src.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 3:
			continue
		out[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = str(src[key])
	return out

