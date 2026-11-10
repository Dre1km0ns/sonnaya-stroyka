extends Node
## Глобальное состояние «Сонная стройка» v0.7: миры с сидом, ДВА инвентаря 9+27 (явь / сон),
## общий «кошель» ресурсов (реагенты, осыпь), вертикальная полоса якорей/маяков,
## «под подушкой» (хилки), смерть с выпадением, кулдаун босса, дев-сид 6767676767.

const ItemDB := preload("res://scripts/item_db.gd")

signal placed_cells_changed(is_dream: bool, cells: Array)
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
signal chat_message(text: String, color: Color)
signal player_hp_changed(hp: int, max_hp: int)
signal player_died
signal day_phase_changed(phase: String)
signal heal_used(cd: float)
signal terrain_cell_changed(cell: Vector3i)
signal egg_taken(nest_id: String, cell: Vector3i)
signal pillow_changed

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
const BED_CRAFT_DUST := 40
const BED_CRAFT_R1 := 3
## Осыпь за убийство моба = 1/5 стоимости клина; босс «Мать блоков» даёт стоимость Якоря3.
const DUST_PER_KILL_MIN := 5
const DUST_PER_KILL_MAX := 8
const DUST_PER_BOSS_KILL := ANCHOR3_CRAFT_DUST
const ANCHOR3_COST_REAGENTS := 5
const ANCHOR3_COST_CLARITY := 30.0
const MUTATION_CHANCE := 0.07
const NO_MUTATION_KINDS := ["sawmill", "alchemy", "idea_catcher", "chest", "door", "bed_foot", "catcher_top","workbench", "torch", "beacon", "bed", "lathe"]
const SAVE_FORMAT := 9
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
## v0.7: раздельные инвентари яви и сна; item_slots указывает на инвентарь текущего мира.
var inv_wake: Array = []
var inv_dream: Array = []
## Кошель (общий для обоих миров): реагенты и осыпь — валюта для якорей/крафта.
var pouch: Dictionary = {"reagent1": 0, "reagent2": 0, "reagent3": 0, "dust": 0}
## «Под подушкой»: 27 слотов, только забирать. Хилки, скрафченные во сне, кладутся сюда.
const PILLOW_SIZE := 27
var pillow: Array = []
## Хилки: «хилка1» = 50 осыпи, +20 HP, кулдаун 15 с.
const HEAL1_DUST := 50
const HEAL1_AMOUNT := 20
const HEAL_COOLDOWN := 15.0
var heal_cd: float = 0.0
## Босс «Мать блоков»: после убийства не появляется одни игровые сутки (24 мин).
const MOTHER_COOLDOWN := 1440.0
var mother_cooldown: float = 0.0
## Анаконда: кулдауна после убийства НЕТ (её призывают яйцом); anaconda_seen — гнёзда, уже «разбуженные» этой ночью.
var anaconda_seen: Dictionary = {}
## Яйца Анаконды, уже взятые из гнёзд (id гнезда), и где игрок возрождается (последняя кровать).
var collected_eggs: Dictionary = {}
const DEFAULT_SPAWN := Vector3(0, 2, 6)
var spawn_point: Vector3 = DEFAULT_SPAWN
var graves: Array = [] # [{pos: Vector3, items: Array[{id,count}]}]
var death_open: bool = false
var _boss_count: int = 0
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
var moon_energy := 0.56
var craft_menu_open: bool = false
var inventory_open: bool = false
var paused: bool = false
var _night_flag: bool = false
var boss_alive: bool:
	get:
		return _boss_count > 0
	set(v):
		_boss_count = 1 if v else 0
var last_mined_kind: String = ""
var last_mined_cell: Vector3i = Vector3i.ZERO
var block_stash: Dictionary = {}
## v0.6: игровые сутки = 24 реальные минуты: утро 3 мин, день 11, вечер 3, ночь 7 (1 мин = 1 игровой час).
const DAY_CYCLE := 1440.0
const PHASE_MORNING_END := 180.0
const PHASE_DAY_END := 840.0
const PHASE_EVENING_END := 1020.0
const NEW_WORLD_TIME := 120.0
const PHASE_NAMES := {"morning": "Утро", "day": "День", "evening": "Вечер", "night": "Ночь"}
## Игрок (v0.7): HP 100, мобы бьют. Реген 1 HP/с, если 15 с не получал урона.
const PLAYER_MAX_HP := 100
const PLAYER_REGEN_DELAY := 15.0
const PLAYER_REGEN_PER_SEC := 1.0
const PLAYER_IFRAMES := 0.5
const COMBO_WINDOW := 3.0
const COMBO_CAP := 70
## Босс: шанс на добытый блок. Решение заранее бросается на СЛЕДУЮЩИЙ блок.
const BOSS_CHANCE_NORMAL := 0.01
const BOSS_CHANCE_DEV := 0.25
const BOSS_OMEN_TEXT := "Вы слышите разъярённые крики убитой горем матери"
var player_hp: int = PLAYER_MAX_HP
var _hp_regen_cd: float = 0.0
var _hp_regen_acc: float = 0.0
var _iframes: float = 0.0
var _combo_log: Array = [] # [[time, amount]]
var _clock: float = 0.0
var boss_next_mine: bool = false
var _phase: String = ""
var world_seed_wake: int = 1337
var world_seed_dream: int = 9001
## Снятые клетки процедурного террейна яви: Vector3i -> kind ("hill"/"ruin"/"ground").
var removed_terrain: Dictionary = {}
var removed_dream_terrain: Dictionary = {}
## Индекс снятых клеток по чанкам 16×16 (Vector2i → Array[Vector3i]) — генерации не нужно перебирать всё.
var removed_by_chunk: Dictionary = {}


func _init() -> void:
	_init_default_slots()


func _ready() -> void:
	_ensure_inventory()


func ui_blocked() -> bool:
	if console_open: return true
	return Engine.get_process_frames() <= modal_closed_frame + 1 or storage_open or craft_menu_open or inventory_open or paused or death_open or pillow_open

var pillow_open: bool = false
var storage_open := false
var modal_closed_frame := -100
var _mouth_t := 30.0
var mother_defeated := false
var dream_bonus_seconds := 0.0
var idea_eaten: Dictionary = {}
var world_storage: Dictionary = {} # String cell key -> 27 slots; shared catcher storage across worlds.
const ArmorRules := preload("res://scripts/armor_rules.gd")
var armor: Array = [{},{},{},{}]
var sword3_crafted := false
var sword2_crafted: bool:
	get: return sword3_crafted
	set(value): sword3_crafted=value
var console_open := false
var god_mode := false
var dev_fly := false
var active_bed := ""
var creation_spawn := DEFAULT_SPAWN
var tutorial_enabled := true
var tutorial_step := 0



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
	armor = [{},{},{},{}]
	sword2_crafted = false
	console_open = false
	god_mode = false
	dev_fly = false
	storage_open = false
	mother_defeated = false
	dream_bonus_seconds = 0.0
	idea_eaten = {}
	world_storage = {}
	active_bed = ""
	creation_spawn = DEFAULT_SPAWN
	tutorial_enabled = true
	tutorial_step = 0
	## Полный сброс перед входом в другой мир.
	current_world = World.WAKE
	clarity = dream_clarity_max()
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
	removed_dream_terrain = {}
	removed_terrain = {}
	removed_by_chunk = {}
	pouch = {"reagent1": 0, "reagent2": 0, "reagent3": 0, "dust": 0}
	heal_cd = 0.0
	mother_cooldown = 0.0
	anaconda_seen = {}
	collected_eggs = {}
	spawn_point = DEFAULT_SPAWN
	graves = []
	death_open = false
	pillow_open = false
	_boss_count = 0
	_hp_regen_cd = 0.0
	moon_energy = 0.56
	day_time = NEW_WORLD_TIME
	player_hp = PLAYER_MAX_HP
	_combo_log = []
	_iframes = 0.0
	boss_next_mine = false
	_phase = ""
	_init_default_slots()
	_init_pillow()


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


const DEV_WAKE_ITEMS := ["sword3","pickaxe2", "sawmill", "alchemy", "idea_catcher", "chest", "door", "heal2", "deep_stone", "mossy_ruin","pickaxe", "sword", "sword2", "torch", "heal1", "anaconda_egg", "workbench", "lathe", "bed",
	"hill", "ruin", "ground", "stone", "sand", "log", "planks", "leaves", "nest", "drift", "mouth", "anaconda_scale", "bedrock"]
const DEV_DREAM_ITEMS := ["bed", "workbench", "drift"]


func _fill_dev_inventory() -> void:
	## Дев-сид: по стаку всего в обоих инвентарях, количество бесконечное (∞, не уменьшается).
	_init_default_slots()
	for i in range(DEV_WAKE_ITEMS.size()):
		inv_wake[i] = {"id": DEV_WAKE_ITEMS[i], "name": ItemDB.display_name(DEV_WAKE_ITEMS[i]), "count": 1}
	for j in range(DEV_DREAM_ITEMS.size()):
		inv_dream[j] = {"id": DEV_DREAM_ITEMS[j], "name": ItemDB.display_name(DEV_DREAM_ITEMS[j]), "count": 1}
	inventory_changed.emit()


static func _new_slots(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"id": "", "name": "", "count": 0})
	return out


func _init_default_slots() -> void:
	inv_wake = _new_slots(ITEM_SLOT_COUNT)
	inv_dream = _new_slots(ITEM_SLOT_COUNT)
	_bind_inventory()


func _bind_inventory() -> void:
	## item_slots — ссылка на массив инвентаря текущего мира (оба инвентаря живут независимо).
	item_slots = inv_dream if current_world == World.DREAM else inv_wake


func inventory_for(dream: bool) -> Array:
	return inv_dream if dream else inv_wake


func _init_pillow() -> void:
	pillow = _new_slots(PILLOW_SIZE)


func _empty_slot() -> Dictionary:
	return {"id": "", "name": "", "count": 0}


func _ensure_inventory() -> void:
	if inv_wake.size() != ITEM_SLOT_COUNT:
		inv_wake = _new_slots(ITEM_SLOT_COUNT)
	if inv_dream.size() != ITEM_SLOT_COUNT:
		inv_dream = _new_slots(ITEM_SLOT_COUNT)
	if pillow.size() != PILLOW_SIZE:
		_init_pillow()
	var want: Array = inv_dream if current_world == World.DREAM else inv_wake
	if not is_same(item_slots, want):
		_bind_inventory()


func reagent_type_name(type_id: int) -> String:
	var i := clampi(type_id - 1, 0, REAGENT_TYPE_COUNT - 1)
	return REAGENT_NAMES[i]


# --- Инвентарь 9+27 ---

func is_pouch_id(id: String) -> bool:
	return pouch.has(id)


func raw_count(id: String) -> int:
	if pouch.has(id):
		return int(pouch[id])
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
	if pouch.has(id):
		var room := count
		if id != "dust":
			room = mini(count, maxi(0, REAGENT_CAP - int(pouch[id])))
		pouch[id] = int(pouch[id]) + room
		if room > 0:
			inventory_changed.emit()
		return room
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
			if tool_max(id) > 0:
				item_slots[i]["durability"] = tool_max(id)
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
	if pouch.has(id):
		pouch[id] = int(pouch[id]) - amount
		inventory_changed.emit()
		return true
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
	if pouch.has(id):
		pouch[id] = maxi(0, value if id == "dust" else mini(value, REAGENT_CAP))
		if emit:
			inventory_changed.emit()
		return
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
		item_slots[i] = data.duplicate(true)
		if tool_max(str(data["id"])) > 0:
			item_slots[i]["durability"] = int(data.get("durability", tool_max(str(data["id"]))))
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
			item_slots[j] = s.duplicate(true)
			item_slots[j]["count"] = put2
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
	if pouch.has(id):
		add_item_count(id, count)
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
	var recipes := [
		{"id": "nail", "name": "Гвоздь", "where": "dream", "dust": NAIL_CRAFT_DUST, "gives": "nails"},
		{"id": "wedge", "name": "Клин", "where": "dream", "dust": WEDGE_CRAFT_DUST, "gives": "wedges"},
		{"id": "anchor3", "name": "Якорь3", "where": "dream", "dust": ANCHOR3_CRAFT_DUST, "gives": "anchors3"},
		{"id": "beacon", "name": "Маяк", "where": "dream", "dust": BEACON_CRAFT_DUST, "reagent3": 1, "gives": "beacons"},
		{"id": "workbench", "name": "Верстак", "where": "dream", "reagent1": 10, "item": "workbench", "item_name": "Верстак"},
		{"id": "pickaxe", "name": "Кирка", "where": "workbench", "reagent2": 2, "reagent3": 3, "item": "pickaxe", "item_name": "Кирка"},
		{"id": "torch", "name": "Факел ×2", "count": 2, "where": "workbench", "reagent1": 1, "reagent2": 1, "item": "torch", "item_name": "Факел"},
		{"id": "sword", "name": "Меч", "where": "workbench", "reagent1": 5, "reagent2": 2, "item": "sword", "item_name": "Меч"},
		{"id": "planks", "name": "Доски ×4", "where": "sawmill", "log": 1, "item": "planks", "item_name": "Доски", "count": 4},
		# v0.7
		{"id": "bed", "name": "Кровать", "where": "dream", "dust": BED_CRAFT_DUST, "reagent1": BED_CRAFT_R1, "item": "bed", "item_name": "Кровать"},
		{"id": "heal1", "name": "хилка1 (под подушку)", "where": "dream", "dust": HEAL1_DUST, "pillow": "heal1"},
		{"id": "lathe", "name": "Станок", "where": "dream", "items": {"workbench": 1}, "reagent3": 7, "item": "lathe", "item_name": "Станок"},
		{"id":"sword3","name":"Чешуйчатый меч (23 урона)","where":"lathe","items":{"sword2":1,"anaconda_scale":5},"item":"sword3"},
		{"id": "sword2", "name": "Меч2 (улучшить Меч)", "where": "lathe", "items": {"sword": 1}, "reagent1": 2, "reagent2": 2, "reagent3": 2, "item": "sword2", "item_name": "Меч2"},
		{"id": "pickaxe2", "name": "Кирка2 (каменная)", "where": "lathe", "items": {"pickaxe": 1}, "reagent1": 2, "reagent2": 2, "reagent3": 2, "item": "pickaxe2"},
		{"id": "sawmill", "name": "Лесопилка", "where": "dream", "items": {"workbench": 1}, "reagent3": 10, "reagent2": 3, "item": "sawmill"},
		{"id": "door", "name": "Дверь", "where": "sawmill_plus", "items": {"planks": 10}, "item": "door"},
		{"id": "chest", "name": "Сундук (27 ячеек)", "where": "sawmill_plus", "items": {"planks": 8}, "item": "chest"},
		{"id": "alchemy", "name": "Алхимический стол", "where": "dream", "unlock": "mother", "items": {"workbench": 1, "stone": 8, "heal1": 1}, "reagent2": 3, "item": "alchemy"},
		{"id": "heal2", "name": "Хилка2 (+40 HP)", "where": "alchemy", "items": {"heal1": 1}, "reagent3": 3, "item": "heal2"},
		{"id": "idea_catcher", "name": "Ловец идей", "where": "dream", "unlock": "mother", "reagent1": 6, "dust": 400, "item": "idea_catcher"},
	]
	for tier in ["wood","scale"]:
		for i in range(4):
			var id: String = tier+"_"+ArmorRules.PARTS[i]
			recipes.append({"id":id,"name":ItemDB.display_name(id),"where":"sawmill_plus" if tier=="wood" else "lathe",
				"items":{"planks" if tier=="wood" else "anaconda_scale":ArmorRules.COST[i]},"item":id})
	return recipes


func find_recipe(rid: String) -> Dictionary:
	for rec in recipe_defs():
		if str(rec.get("id", "")) == rid:
			return rec
	return {}


func recipe_available(rec: Dictionary, ctx: Dictionary = {}) -> bool:
	if rec.is_empty():
		return false
	if rec.get("unlock", "") == "mother" and not mother_defeated and not dev_mode:
		return false
	var where := str(rec.get("where", "anywhere"))
	var dreaming := bool(ctx.get("is_dream", is_dream()))
	var station_id := str(ctx.get("station", ""))
	if station_id == "sawmill":
		return where == "sawmill" or (where == "sawmill_plus" and bool(ctx.get("upgraded", false)))
	if station_id == "alchemy":
		return where == "alchemy"
	if bool(ctx.get("at_lathe", false)):
		return where == "lathe"
	if bool(ctx.get("at_workbench", false)):
		return where == "workbench"
	return where == "dream" and dreaming


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
	if count_item("log") < int(rec.get("log", 0)):
		return false
	var need: Dictionary = rec.get("items", {})
	for iid in need.keys():
		if count_item(str(iid)) + (pillow_count("heal1") if str(iid) == "heal1" and is_dream() else 0) < int(need[iid]):
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
	if int(rec.get("log", 0)) > 0:
		parts.append("%d бревно" % int(rec.get("log", 0)))
	var need: Dictionary = rec.get("items", {})
	for iid in need.keys():
		parts.insert(0, "%d %s" % [int(need[iid]), ItemDB.display_name(str(iid))])
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
	if int(rec.get("log", 0)) > 0:
		parts.append("%d бревно" % int(rec.get("log", 0)))
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
	if not selected_is("pickaxe") and not selected_is("pickaxe2") and get_selected_item().get("id","")!="":
		set_hint("Чтобы ломать блоки яви, возьми кирку.")
		return false
	if not wake_blocks.has(cell):
		return false
	var data: Dictionary = wake_blocks[cell]
	var kind := str(data.get("kind", "drift"))
	cell = root_cell(wake_blocks, cell)
	kind = str(wake_blocks.get(cell, {}).get("kind", kind))
	if not break_storage(cell):
		return false
	remove_shape(wake_blocks, cell)
	last_mined_kind = kind
	last_mined_cell = cell
	if active_bed == cell_key(cell):
		active_bed = ""
		spawn_point = creation_spawn
	terrain_cell_changed.emit(cell)
	inventory_changed.emit()
	set_hint(("Добыт блок «%s»." if Mining.drops(kind,str(get_selected_item().get("id",""))) else "Блок «%s» разрушен без кирки: дропа нет.") % block_display_name(kind),false)
	return true


func is_terrain_removed(cell: Vector3i) -> bool:
	return removed_terrain.has(cell)


func terrain_removed_kind(cell: Vector3i) -> String:
	return str(removed_terrain.get(cell, ""))


func remove_terrain_cell_silent(cell: Vector3i, kind: String) -> bool:
	if removed_terrain.has(cell):
		return false
	removed_terrain[cell] = kind
	_index_removed(cell)
	terrain_cell_changed.emit(cell)
	return true


static func chunk_of_cell(cell: Vector3i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / 16.0), floori(float(cell.z) / 16.0))


func _index_removed(cell: Vector3i) -> void:
	var ck := chunk_of_cell(cell)
	if not removed_by_chunk.has(ck):
		removed_by_chunk[ck] = []
	(removed_by_chunk[ck] as Array).append(cell)


func removed_in_chunk(ck: Vector2i) -> Array:
	return removed_by_chunk.get(ck, [])



func _rebuild_removed_index() -> void:
	removed_by_chunk = {}
	for c in removed_terrain.keys():
		_index_removed(c)


const BEDROCK_Y := -31


func remove_terrain_cell(cell: Vector3i, kind: String) -> bool:
	if removed_terrain.has(cell):
		return false
	if kind == "bedrock" or cell.y <= BEDROCK_Y:
		set_hint("Бедрок не ломается — глубже копать нельзя.", false)
		return false
	var k := kind if kind != "" else "hill"
	removed_terrain[cell] = k
	last_mined_kind = k
	last_mined_cell = cell
	_index_removed(cell)
	if k == "egg":
		var nid := "nest:%d,%d,%d" % [cell.x, cell.y, cell.z]
		collected_eggs[nid] = true
		egg_taken.emit(nid, cell)
	terrain_cell_changed.emit(cell)
	set_hint("Кирка: выпал блок «%s»." % block_display_name(k), false)
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
	var before_slots := item_slots.duplicate(true)
	var before_pouch := pouch.duplicate(true)
	var before_pillow := pillow.duplicate(true)
	dust -= int(rec.get("dust", 0))
	if int(rec.get("reagent1", 0)) > 0:
		spend_typed_reagent(1, int(rec.get("reagent1", 0)))
	if int(rec.get("reagent2", 0)) > 0:
		spend_typed_reagent(2, int(rec.get("reagent2", 0)))
	if int(rec.get("reagent3", 0)) > 0:
		spend_typed_reagent(3, int(rec.get("reagent3", 0)))
	if int(rec.get("log", 0)) > 0 and not dev_mode:
		remove_item("log", int(rec.get("log", 0)))
	var need: Dictionary = rec.get("items", {})
	if not dev_mode:
		for iid in need.keys():
			if str(iid) == "heal1" and is_dream() and count_item("heal1") < int(need[iid]):
				var left := int(need[iid])
				for j in range(pillow.size()):
					if pillow[j].get("id", "") == "heal1" and left > 0:
						var take := mini(left, int(pillow[j]["count"]))
						pillow[j]["count"] -= take
						left -= take
						if int(pillow[j]["count"]) == 0:
							pillow[j] = {}
			else:
				remove_item(str(iid), int(need[iid]))
	var to_pillow := str(rec.get("pillow", ""))
	if to_pillow != "":
		if add_to_pillow(to_pillow,int(rec.get("count",1))) < int(rec.get("count",1)):
			_restore_craft(before_slots,before_pouch,before_pillow)
			set_hint("Под подушкой нет свободного места.")
			return false
		inventory_changed.emit()
		set_hint("Скрафчено: %s — лежит под подушкой кровати в яви." % str(rec.get("name", rid)))
		return true
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
		if add_item_count(item_id,int(rec.get("count",1))) < int(rec.get("count",1)):
			_restore_craft(before_slots,before_pouch,before_pillow)
			set_hint("Нет свободного слота для «%s»." % str(rec.get("item_name", item_id)))
			return false
	inventory_changed.emit()
	if rid == "sword3": set_sword3_flag(true)
	set_hint("Скрафчено: %s." % str(rec.get("name", rid)))
	return true



static func cycle_time(t: float) -> float:
	var m := fmod(t, DAY_CYCLE)
	if m < 0.0:
		m += DAY_CYCLE
	return m


static func phase_at(t: float) -> String:
	var c := cycle_time(t)
	if c < PHASE_MORNING_END:
		return "morning"
	if c < PHASE_DAY_END:
		return "day"
	if c < PHASE_EVENING_END:
		return "evening"
	return "night"


static func clock_text(t: float) -> String:
	## 0 c цикла = 06:00, 1 реальная минута = 1 игровой час.
	var hours := 6.0 + cycle_time(t) / 60.0
	var hh := int(floor(hours)) % 24
	var mm := int(floor((hours - floor(hours)) * 60.0))
	return "%02d:%02d" % [hh, mm]


func night_index() -> int:
	return floori(day_time / DAY_CYCLE)


func day_phase() -> String:
	return phase_at(day_time)


func is_night() -> bool:
	return day_phase() == "night"


func notify_night_from_time() -> void:
	var n := is_night()
	if n != _night_flag:
		_night_flag = n
		night_changed.emit(n)
	var ph := day_phase()
	if ph != _phase:
		var first := _phase == ""
		_phase = ph
		day_phase_changed.emit(ph)
		if not first:
			chat("Наступает %s." % str(PHASE_NAMES.get(ph, ph)).to_lower(), Color(1.0, 0.9, 0.6))


# --- Чат / журнал сообщений (v0.6) ---

func chat(text: String, color: Color = Color(1, 1, 1)) -> void:
	chat_message.emit(text, color)


# --- HP игрока (v0.6) ---

func _process(delta: float) -> void:
	if not is_dream() and not paused:
		_mouth_t -= delta
		if _mouth_t <= 0:
			_mouth_t = 30.0
			spread_mouth_once()
	_clock += delta
	_iframes = maxf(0.0, _iframes - delta)
	if heal_cd > 0.0:
		heal_cd = maxf(0.0, heal_cd - delta)
	if mother_cooldown > 0.0:
		mother_cooldown = maxf(0.0, mother_cooldown - delta)
	if player_hp < PLAYER_MAX_HP and player_hp > 0:
		_hp_regen_cd -= delta
		if _hp_regen_cd <= 0.0:
			_hp_regen_acc += PLAYER_REGEN_PER_SEC * delta
			if _hp_regen_acc >= 1.0:
				var add := int(_hp_regen_acc)
				_hp_regen_acc -= float(add)
				player_hp = mini(PLAYER_MAX_HP, player_hp + add)
				player_hp_changed.emit(player_hp, PLAYER_MAX_HP)


func combo_damage_recent() -> int:
	var total := 0
	for e in _combo_log:
		if _clock - float(e[0]) <= COMBO_WINDOW:
			total += int(e[1])
	return total


func damage_player(amount: int, source: String = "", ignore_iframes: bool = false) -> int:
	## Возвращает фактический урон. i-frames 0.5 с после удара ≥10; за любые 3 с — не больше 70 (запрет ваншот-цепочек).
	if god_mode or amount <= 0 or player_hp <= 0:
		return 0
	if _iframes > 0.0 and not ignore_iframes:
		return 0
	var filtered: Array = []
	for e in _combo_log:
		if _clock - float(e[0]) <= COMBO_WINDOW:
			filtered.append(e)
	_combo_log = filtered
	var allowed := maxi(0, COMBO_CAP - combo_damage_recent())
	var dmg := mini(ArmorRules.reduce(amount,armor_points()),allowed)
	if dmg <= 0:
		return 0
	wear_armor(amount)
	_combo_log.append([_clock, dmg])
	player_hp = maxi(0, player_hp - dmg)
	_hp_regen_cd = PLAYER_REGEN_DELAY
	_hp_regen_acc = 0.0
	if dmg >= 10:
		_iframes = PLAYER_IFRAMES
	player_hp_changed.emit(player_hp, PLAYER_MAX_HP)
	if player_hp <= 0:
		player_died.emit()
	return dmg


func regen_delay_left() -> float:
	return maxf(0.0, _hp_regen_cd)


# --- Хилки и «под подушкой» (v0.7) ---

func add_to_pillow(id: String, count: int) -> int:
	var left := count
	var cap := ItemDB.max_stack(id)
	for i in range(pillow.size()):
		if left <= 0:
			break
		var sl: Dictionary = pillow[i]
		if str(sl.get("id", "")) == id and int(sl.get("count", 0)) < cap:
			var add := mini(left, cap - int(sl["count"]))
			sl["count"] = int(sl["count"]) + add
			left -= add
	for j in range(pillow.size()):
		if left <= 0:
			break
		if str(pillow[j].get("id", "")) == "":
			var add2 := mini(left, cap)
			pillow[j] = {"id": id, "name": ItemDB.display_name(id), "count": add2}
			left -= add2
	pillow_changed.emit()
	return count - left


func pillow_count(id: String) -> int:
	var n := 0
	for sl in pillow:
		if str(sl.get("id", "")) == id:
			n += int(sl.get("count", 0))
	return n


func take_from_pillow(i: int) -> bool:
	## Только забирать: весь стак слота уходит в инвентарь яви (что не влезло — остаётся).
	if i < 0 or i >= pillow.size():
		return false
	var sl: Dictionary = pillow[i]
	var id := str(sl.get("id", ""))
	var n := int(sl.get("count", 0))
	if id == "" or n <= 0:
		return false
	var saved := item_slots
	item_slots = inv_wake
	var got := add_item_count(id, n)
	item_slots = saved
	if got <= 0:
		set_hint("Инвентарь яви полон.", false)
		return false
	if got >= n:
		pillow[i] = _empty_slot()
	else:
		sl["count"] = n - got
	pillow_changed.emit()
	inventory_changed.emit()
	return true


func can_use_heal() -> bool:
	return heal_cd <= 0.0 and player_hp > 0 and player_hp < PLAYER_MAX_HP and (count_item("heal1") > 0 or count_item("heal2") > 0)


func first_heal_slot(id: String="") -> int:
	for i in range(item_slots.size()):
		var slot: Dictionary=item_slots[i]
		if slot.get("id","") in ["heal1","heal2"] and int(slot.get("count",0))>0 and (id=="" or slot.id==id): return i
	return -1

func use_heal(id: String="") -> bool:
	if heal_cd>0.0:
		set_hint("Зелье: перезарядка %.0f с" % ceilf(heal_cd),false);return false
	if player_hp<=0 or player_hp>=PLAYER_MAX_HP: return false
	var slot:=first_heal_slot(id)
	if slot<0:
		set_hint("Нет лечебных зелий в инвентаре.",false);return false
	var potion: String=item_slots[slot].id
	if not is_infinite_slot(slot):
		item_slots[slot].count-=1
		if item_slots[slot].count<=0: item_slots[slot]=_empty_slot()
	inventory_changed.emit()
	Sfx.play("drink",get_tree().root)
	var amount:=40 if potion=="heal2" else HEAL1_AMOUNT
	player_hp=mini(PLAYER_MAX_HP,player_hp+amount);heal_cd=HEAL_COOLDOWN
	player_hp_changed.emit(player_hp,PLAYER_MAX_HP);heal_used.emit(HEAL_COOLDOWN)
	set_hint("%s: +%d HP" % [ItemDB.display_name(potion),amount],false)
	return true


# --- Смерть (v0.7): выпадает всё, кроме гвоздей/якорей/маяков ---

func collect_death_drop() -> Array:
	## Забирает из инвентаря яви и кошеля всё, что выпадает. Дев-сид — ничего (ресурсы бесконечны).
	var out: Array = []
	if dev_mode:
		return out
	for i in range(inv_wake.size()):
		var sl: Dictionary = inv_wake[i]
		if str(sl.get("id", "")) != "" and int(sl.get("count", 0)) > 0:
			out.append(sl.duplicate(true))
			inv_wake[i] = _empty_slot()
	for i in range(4):
		if not armor[i].is_empty():
			out.append(armor[i].duplicate(true))
			armor[i] = {}
	for pid in pouch.keys():
		if int(pouch[pid]) > 0:
			out.append({"id": str(pid), "count": int(pouch[pid])})
			pouch[pid] = 0
	for k in block_stash.keys():
		if int(block_stash[k]) > 0:
			out.append({"id": str(k), "count": int(block_stash[k])})
	block_stash = {}
	inventory_changed.emit()
	return out


var _grave_seq: int = 0


func add_grave(pos: Vector3, items: Array) -> int:
	if items.is_empty():
		return -1
	_grave_seq += 1
	graves.append({"id": _grave_seq, "pos": pos, "items": items.duplicate(true)})
	return _grave_seq


func grave_index(gid: int) -> int:
	for i in range(graves.size()):
		if int(graves[i].get("id", -1)) == gid:
			return i
	return -1


func pickup_grave(gid: int) -> int:
	## Подбирает кучку: всё, что влезло. Возвращает число подобранных предметов.
	var idx := grave_index(gid)
	if idx < 0:
		return 0
	var g: Dictionary = graves[idx]
	var rest: Array = []
	var got_total := 0
	var saved := item_slots
	item_slots = inv_wake
	for it in g["items"]:
		var n := int(it["count"])
		var got := 0
		if tool_max(str(it["id"])) > 0:
			for j in range(ITEM_SLOT_COUNT):
				if get_slot(j).get("id", "") == "":
					set_slot(j, it)
					got = n
					break
		else:
			got = add_item_count(str(it["id"]), n)
		got_total += got
		if got < n:
			var remaining: Dictionary = it.duplicate(true)
			remaining["count"] = n - got
			rest.append(remaining)
	item_slots = saved
	if rest.is_empty():
		graves.remove_at(idx)
	else:
		g["items"] = rest
	inventory_changed.emit()
	return got_total


func heal_player_full() -> void:
	player_hp = PLAYER_MAX_HP
	_combo_log = []
	_iframes = 1.5
	player_hp_changed.emit(player_hp, PLAYER_MAX_HP)


# --- Босс: шанс и предвестие (v0.6) ---

func boss_spawn_chance() -> float:
	return BOSS_CHANCE_DEV if dev_mode else BOSS_CHANCE_NORMAL


func on_block_mined(rng_value: float = -1.0) -> bool:
	## Вызывается после каждого добытого блока. true → босс появляется СЕЙЧАС (решение было брошено
	## на прошлом блоке и объявлено в чате). Затем бросаем решение на следующий блок.
	## v0.7: после убийства Мать не появляется одни игровые сутки (mother_cooldown).
	if mother_cooldown > 0.0:
		boss_next_mine = false
		return false
	var spawn_now := false
	if boss_next_mine and not boss_alive and not peaceful:
		spawn_now = true
		boss_next_mine = false
	if not boss_next_mine and not peaceful:
		var r := rng_value if rng_value >= 0.0 else randf()
		if r < boss_spawn_chance():
			boss_next_mine = true
			chat(BOSS_OMEN_TEXT, Color(1.0, 0.35, 0.35))
	return spawn_now


func set_boss_alive(on: bool) -> void:
	## Счётчик живых боссов (Мать + Анаконда могут жить одновременно).
	var was := _boss_count > 0
	_boss_count = maxi(0, _boss_count + (1 if on else -1))
	if was != (_boss_count > 0):
		boss_changed.emit(_boss_count > 0)


func on_mother_killed() -> void:
	mother_defeated = true
	mother_cooldown = MOTHER_COOLDOWN
	boss_next_mine = false


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
		"log":
			return "Бревно"
		"leaves":
			return "Листва"
		"planks":
			return "Доски"
		"stone":
			return "Камень"
		"sand":
			return "Песок"
		"nest":
			return "Гнездо"
		"bed":
			return "Кровать"
		"lathe":
			return "Станок"
		"bedrock":
			return "Бедрок"
		"heal1":
			return "хилка1"
		"anaconda_egg":
			return "Яйцо Анаконды"
		"sword2":
			return "Меч2"
		_:
			return ItemDB.display_name(kind, "Блок")


func is_placeable_block(id: String) -> bool:
	return id in ["bedrock", "drift", "mouth", "workbench", "hill", "ruin", "ground", "log", "leaves", "planks",
		"stone", "deep_stone", "dirt", "sand", "nest", "bed", "lathe", "sawmill", "alchemy", "idea_catcher", "chest", "door", "mossy_ruin"]


func add_mined_block(kind: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	if kind == "egg":
		kind = "anaconda_egg"
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

func place_wake_block(cell: Vector3i, kind: String, facing: int=0) -> bool:
	if is_dream():
		return false
	if not can_place_shape(wake_blocks, cell, kind):
		return false
	wake_blocks[cell] = {"kind": kind, "mutant": false}
	if kind=="door":
		wake_blocks[cell]["facing"]=posmod(facing,4)
		wake_blocks[cell]["hinge_right"]=door_hinge_right(wake_blocks,cell,facing)
	add_shape_parts(wake_blocks, cell, kind)
	terrain_cell_changed.emit(cell)
	inventory_changed.emit()
	return true


func is_dream() -> bool:
	return current_world == World.DREAM


func set_hint(text: String, to_chat: bool = true) -> void:
	if to_chat and text != last_hint and not text.begins_with("Слот") and not text.begins_with("Чувствительность"):
		chat(text)
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
	clarity_changed.emit(clarity, dream_clarity_max())
	return true


func drain_clarity(delta: float) -> void:
	if not is_dream():
		return
	if dev_mode:
		return
	clarity = maxf(0.0, clarity - CLARITY_DRAIN_PER_SEC * delta)
	clarity_changed.emit(clarity, dream_clarity_max())
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
	_bind_inventory()
	clarity = dream_clarity_max()
	awake_time = 0.0
	clarity_changed.emit(clarity, dream_clarity_max())
	world_changed.emit(true)
	set_hint("Сон. ЛКМ — блок, ПКМ — снять, R — сменить якорь, Q — заякорить, C — меню крафта, F — проснуться.",false)


func resolve_wake() -> Dictionary:
	## Переносит новые якоря в явь с тем же Vector3i (высота совпадает).
	## v0.7: после пробуждения ВСЕ поставленные во сне блоки исчезают — в следующий сон строить заново.
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
		if data.has("root"):
			continue
		var kind := str(data.get("kind", "drift"))
		if not can_place_shape(wake_blocks,cell,kind):
			continue
		var mutant := false
		if not (kind in NO_MUTATION_KINDS) and randf() < MUTATION_CHANCE and not suppress_mutation(cell):
			mutant = true
			mutations += 1
			kind = "mouth"
		wake_blocks[cell] = {
			"kind": kind,
			"mutant": mutant,
		}
		if kind=="door":
			wake_blocks[cell]["facing"] = int(data.get("facing",0))
			wake_blocks[cell]["open"] = bool(data.get("open",false))
			wake_blocks[cell]["hinge_right"] = bool(data.get("hinge_right",false))
		add_shape_parts(wake_blocks, cell, kind)
		transferred += 1

	var dream_roots := 0
	for block in dream_blocks.values():
		if not block.has("root"):
			dream_roots += 1
	dust_gained += maxi(0,dream_roots-transferred)/5
	dust += dust_gained
	pending_anchors.clear()
	var wiped := dream_blocks.size()
	dream_blocks.clear()
	current_world = World.WAKE
	_bind_inventory()
	dream_exit_count += 1
	clarity = dream_clarity_max()
	clarity_changed.emit(clarity, dream_clarity_max())
	inventory_changed.emit()
	world_changed.emit(false)
	wake_resolved.emit(transferred, dust_gained, mutations)
	var msg := "Пробуждение: +%d блоков в явь (сон рассеялся: %d блок(ов))" % [transferred, wiped]
	if mutations > 0:
		msg += ", мутаций: %d (блок «рот»)" % mutations
	set_hint(msg)
	return {"transferred": transferred, "dust": dust_gained, "mutations": mutations}


func place_dream_block(cell: Vector3i, kind: String = "drift", facing: int = 0) -> bool:
	if not can_place_shape(dream_blocks, cell, kind):
		return false
	dream_blocks[cell] = {"kind": kind, "anchored": false, "mutant": false}
	if kind=="door":
		dream_blocks[cell]["facing"] = posmod(facing,4)
		dream_blocks[cell]["hinge_right"] = door_hinge_right(dream_blocks,cell,facing)
	add_shape_parts(dream_blocks, cell, kind)
	return true


func remove_dream_block(cell: Vector3i) -> bool:
	if not dream_blocks.has(cell):
		return false
	cell = root_cell(dream_blocks, cell)
	remove_shape(dream_blocks, cell)
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
	var amount := DUST_PER_BOSS_KILL if is_boss else randi_range(DUST_PER_KILL_MIN,DUST_PER_KILL_MAX)
	if not dev_mode:
		add_item_count("dust", amount)
	var prefix := (who + " повержен: ") if who != "" else ""
	set_hint("%s+%d осыпи" % [prefix, amount], is_boss)
	toast.emit("%s+%d осыпи" % [prefix, amount])
	return amount


func count_enemies_in_tree(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("seam_creature").size()


# --- Save / load serialization ---

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_FORMAT,
		"armor":armor.duplicate(true),
		"sword2_crafted":sword3_crafted, # legacy alias
		"sword3_crafted":sword3_crafted,
		"progression_revision":10,
		"mother_defeated": mother_defeated,
		"dream_bonus_seconds": dream_bonus_seconds,
		"idea_eaten": idea_eaten,
		"world_storage": world_storage,
		"active_bed": active_bed,
		"creation_spawn": [creation_spawn.x, creation_spawn.y, creation_spawn.z],
		"tutorial_enabled": tutorial_enabled,
		"tutorial_step": tutorial_step,
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
		"moon_energy":moon_energy,
		"moon_revision":1,
		"selected_anchor": int(selected_anchor),
		"selected_slot": selected_slot,
		"item_slots": inv_wake.duplicate(true),
		"inv_dream": inv_dream.duplicate(true),
		"pillow": pillow.duplicate(true),
		"reagent_counts": [raw_count("reagent1"), raw_count("reagent2"), raw_count("reagent3")],
		"dust": raw_count("dust"),
		"mother_cooldown": mother_cooldown,
		"heal_cd": heal_cd,
		"collected_eggs": collected_eggs.keys(),
		"spawn_point": [spawn_point.x, spawn_point.y, spawn_point.z],
		"graves": _graves_to_json(),
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
		"removed_dream_terrain":_cells_kind_to_json(removed_dream_terrain),
		"boss_next_mine": boss_next_mine,
		"player_hp": player_hp,
	}


static func _seed_val(v: Variant, fallback: int) -> int:
	if v == null:
		return fallback
	if typeof(v) == TYPE_STRING:
		var s := str(v)
		return s.to_int() if s.is_valid_int() else fallback
	return int(v)


func apply_save_dict(data: Dictionary) -> void:
	armor = [{},{},{},{}]
	var saved_armor: Array = data.get("armor",[])
	for i in range(mini(4,saved_armor.size())):
		if ArmorRules.slot(saved_armor[i].get("id",""))==i: armor[i]=saved_armor[i].duplicate(true)
	sword3_crafted = bool(data.get("sword3_crafted",false)) # v0.9.1 sword2 inflation is intentionally cleared.
	mother_defeated = bool(data.get("mother_defeated", false))
	dream_bonus_seconds = maxf(0.0, float(data.get("dream_bonus_seconds", 0.0)))
	idea_eaten = data.get("idea_eaten", {}).duplicate(true)
	world_storage = data.get("world_storage", {}).duplicate(true)
	active_bed = str(data.get("active_bed", ""))
	var cs: Array = data.get("creation_spawn", [DEFAULT_SPAWN.x, DEFAULT_SPAWN.y, DEFAULT_SPAWN.z])
	creation_spawn = Vector3(float(cs[0]), float(cs[1]), float(cs[2]))
	tutorial_enabled = bool(data.get("tutorial_enabled", true))
	tutorial_step = int(data.get("tutorial_step", 0))
	storage_open = false
	var fmt := int(data.get("version", 4))
	nails = int(data.get("nails", 3))
	wedges = int(data.get("wedges", 1))
	anchors3 = int(data.get("anchors3", 0))
	beacons = int(data.get("beacons", 0))
	clarity = float(data.get("clarity", CLARITY_MAX))
	awake_time = float(data.get("awake_time", 0.0))
	day_time = float(data.get("day_time", 0.0))
	moon_energy = clampf(float(data.get("moon_energy",0.56)),0.0,10.0)
	# Migrate the old default once. Explicit console values in v0.9.1 remain saved.
	if int(data.get("moon_revision",0))<1 and is_equal_approx(moon_energy,0.47): moon_energy = 0.56
	world_seed_wake = _seed_val(data.get("world_seed_wake", null), world_seed_wake if world_folder != "" else 1337)
	world_seed_dream = _seed_val(data.get("world_seed_dream", null), world_seed_dream if world_folder != "" else 9001)
	if data.has("world_seed"):
		world_seed = _seed_val(data["world_seed"], world_seed)
	selected_anchor = clampi(int(data.get("selected_anchor", 0)), 0, 2) as AnchorType
	dream_exit_count = int(data.get("dream_exit_count", data.get("wake_count", 0)))
	selected_slot = clampi(int(data.get("selected_slot", 0)), 0, HOTBAR_SIZE - 1)
	current_world = World.WAKE
	_init_default_slots()
	_init_pillow()
	pouch = {"reagent1": 0, "reagent2": 0, "reagent3": 0, "dust": 0}
	var slots: Variant = data.get("item_slots", null)
	if fmt >= 7 and typeof(slots) == TYPE_ARRAY:
		_slots_into(slots, inv_wake)
		_slots_into(data.get("inv_dream", []), inv_dream)
		_slots_into(data.get("pillow", []), pillow)
		var rc7: Variant = data.get("reagent_counts", [])
		if typeof(rc7) == TYPE_ARRAY:
			for i7 in range(mini(REAGENT_TYPE_COUNT, rc7.size())):
				pouch["reagent%d" % (i7 + 1)] = clampi(int(rc7[i7]), 0, REAGENT_CAP)
		pouch["dust"] = maxi(0, int(data.get("dust", 0)))
	elif fmt >= 5 and typeof(slots) == TYPE_ARRAY:
		# v0.5–0.6: один инвентарь → инвентарь яви; реагенты/осыпь из слотов → кошель.
		var dev_was5 := dev_mode
		dev_mode = false
		for i in range(mini(slots.size(), ITEM_SLOT_COUNT)):
			var s: Variant = slots[i]
			if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) != "" and int(s.get("count", 0)) > 0:
				var sid5 := str(s["id"])
				if pouch.has(sid5):
					add_item_count(sid5, int(s["count"]))
				else:
					inv_wake[i] = {"id": sid5, "name": str(s.get("name", "")), "count": int(s["count"])}
		dev_mode = dev_was5
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
	if fmt < 8:
		_migrate_beds(wake_blocks)
		_migrate_beds(dream_blocks)
	pending_anchors = _anchors_from_json(data.get("pending_anchors", []))
	removed_terrain = _cells_kind_from_json(data.get("removed_terrain", {}))
	removed_dream_terrain = _cells_kind_from_json(data.get("removed_dream_terrain",{}))
	_rebuild_removed_index()
	boss_next_mine = bool(data.get("boss_next_mine", false))
	mother_cooldown = maxf(0.0, float(data.get("mother_cooldown", 0.0)))
	anaconda_seen = {}
	heal_cd = maxf(0.0, float(data.get("heal_cd", 0.0)))
	collected_eggs = {}
	var ce: Variant = data.get("collected_eggs", [])
	if typeof(ce) == TYPE_ARRAY:
		for e in ce:
			collected_eggs[str(e)] = true
	var sp: Variant = data.get("spawn_point", null)
	spawn_point = Vector3(float(sp[0]), float(sp[1]), float(sp[2])) if typeof(sp) == TYPE_ARRAY and sp.size() >= 3 else DEFAULT_SPAWN
	if active_bed == "" or (active_bed != "starter" and wake_blocks.get(key_cell(active_bed),{}).get("kind","") != "bed"):
		active_bed = ""
		spawn_point = creation_spawn
	_graves_from_json(data.get("graves", []))
	_boss_count = 0
	death_open = false
	pillow_open = false
	player_hp = clampi(int(data.get("player_hp", PLAYER_MAX_HP)), 1, PLAYER_MAX_HP)
	player_hp_changed.emit(player_hp, PLAYER_MAX_HP)
	if dev_mode:
		_ensure_dev_items()
	var w := str(data.get("world", "wake"))
	current_world = World.DREAM if w == "dream" else World.WAKE
	_bind_inventory()
	clarity_changed.emit(clarity, dream_clarity_max())
	inventory_changed.emit()
	world_changed.emit(is_dream())


func _ensure_dev_items() -> void:
	var any := false
	for s in inv_wake:
		if str(s.get("id", "")) != "":
			any = true
			break
	if not any:
		_fill_dev_inventory()
	# v0.7: в старых дев-сейвах нет новых предметов — докладываем.
	for id in DEV_WAKE_ITEMS:
		_dev_ensure(inv_wake, id)
	for id2 in DEV_DREAM_ITEMS:
		_dev_ensure(inv_dream, id2)


func _dev_ensure(inv: Array, id: String) -> void:
	for s in inv:
		if str(s.get("id", "")) == id:
			return
	for i in range(inv.size()):
		if str(inv[i].get("id", "")) == "":
			inv[i] = {"id": id, "name": ItemDB.display_name(id), "count": 1}
			return


func _slots_into(src: Variant, dst: Array) -> void:
	if typeof(src) != TYPE_ARRAY:
		return
	for i in range(mini(src.size(), dst.size())):
		var s: Variant = src[i]
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) != "" and int(s.get("count", 0)) > 0:
			dst[i] = s.duplicate(true)


func _graves_to_json() -> Array:
	var out: Array = []
	for g in graves:
		var p: Vector3 = g["pos"]
		out.append({"pos": [p.x, p.y, p.z], "items": (g["items"] as Array).duplicate(true)})
	return out


func _graves_from_json(src: Variant) -> void:
	graves = []
	if typeof(src) != TYPE_ARRAY:
		return
	for g in src:
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var pa: Array = g.get("pos", [0, 0, 0])
		var items: Array = []
		for it in g.get("items", []):
			if typeof(it) == TYPE_DICTIONARY and int(it.get("count", 0)) > 0:
				items.append(it.duplicate(true))
		if not items.is_empty() and pa.size() >= 3:
			_grave_seq += 1
			graves.append({"id": _grave_seq, "pos": Vector3(float(pa[0]), float(pa[1]), float(pa[2])), "items": items})


func _ensure_anchor3_slot() -> void:
	_ensure_inventory()


func _blocks_to_json(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		var c: Vector3i = k
		var key := "%d,%d,%d" % [c.x, c.y, c.z]
		var d: Dictionary = src[k]
		out[key] = d.duplicate(true)
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
		out[c] = d.duplicate(true)
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


# ================================================================ v0.8
const Mining := preload("res://scripts/mining_rules.gd")
const Sfx := preload("res://scripts/sfx.gd")

func dream_clarity_max() -> float:
	return CLARITY_MAX + dream_bonus_seconds * CLARITY_DRAIN_PER_SEC

static func tool_max(id: String) -> int:
	if ArmorRules.slot(id)>=0: return ArmorRules.durability(id)
	return 700 if id=="sword3" else (100 if id in ["pickaxe", "sword"] else (500 if id in ["pickaxe2", "sword2"] else 0))

func wear_tool(amount: int) -> bool:
	if str(get_selected_item().get("id","")) not in ["pickaxe","pickaxe2","sword","sword2","sword3"]: return false
	var d := get_selected_item()
	var id := str(d.get("id", ""))
	if dev_mode or tool_max(id) == 0:
		return false
	d["durability"] = maxi(0, int(d.get("durability", tool_max(id))) - amount)
	var broken := int(d["durability"]) == 0
	if broken:
		item_slots[selected_slot] = _empty_slot()
		set_hint("%s сломалась / сломался." % ItemDB.display_name(id))
	inventory_changed.emit()
	return broken

static func cell_key(c: Vector3i) -> String:
	return "%d,%d,%d" % [c.x, c.y, c.z]

static func key_cell(k: String) -> Vector3i:
	var p := k.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2])) if p.size() == 3 else Vector3i.ZERO

func beacon_protects(c: Vector3i) -> bool:
	for b in wake_blocks:
		if wake_blocks[b].get("kind", "") == "beacon":
			var d: Vector3i = c - b
			if maxi(absi(d.x), maxi(absi(d.y), absi(d.z))) <= 10:
				return true
	return false

func suppress_mutation(c: Vector3i) -> bool:
	if not beacon_protects(c):
		return false
	dust += 5
	return true

func station_upgraded(c: Vector3i, neighbor: String = "workbench") -> bool:
	var source := dream_blocks if is_dream() else wake_blocks
	for d in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		if source.get(c + d, {}).get("kind", "") == neighbor or (neighbor == "bed" and source.get(c+d,{}).get("kind", "") == "bed_foot"):
			return true
	# Стартовая кровать — тоже сосед для Ловца, только в яви.
	if neighbor == "bed" and not is_dream():
		for b in get_tree().get_nodes_in_group("bed"):
			if not b.has_meta("voxel_cell"):
				var bc := Vector3i(floori(b.global_position.x), floori(b.global_position.y), floori(b.global_position.z))
				if (c - bc).abs().x + (c - bc).abs().y + (c - bc).abs().z == 1:
					return true
	return false

static func part_offset(kind: String) -> Vector3i:
	return Vector3i.BACK if kind == "bed" else Vector3i.UP

static func shape_part(kind: String) -> String:
	return {"bed": "bed_foot", "door": "door_top", "idea_catcher": "catcher_top"}.get(kind, "")

func can_place_shape(source: Dictionary, c: Vector3i, kind: String) -> bool:
	return not source.has(c) and (shape_part(kind) == "" or not source.has(c + part_offset(kind)))

func add_shape_parts(source: Dictionary,c: Vector3i,kind: String) -> void:
	var cells: Array = [c]
	if shape_part(kind)!="":
		source[c+part_offset(kind)]={"kind":shape_part(kind),"root":cell_key(c)}
		cells.append(c+part_offset(kind))
	placed_cells_changed.emit(is_same(source,dream_blocks),cells)

func root_cell(source: Dictionary, c: Vector3i) -> Vector3i:
	return key_cell(str(source[c]["root"])) if source.has(c) and source[c].has("root") else c

func remove_shape(source: Dictionary, c: Vector3i) -> void:
	var kind: String = source.get(c, {}).get("kind", "")
	if shape_part(kind) != "" and source.get(c+part_offset(kind),{}).get("root", "") == cell_key(c):
		source.erase(c + part_offset(kind))
	source.erase(c)
	placed_cells_changed.emit(is_same(source,dream_blocks),[c,c+part_offset(kind)])

func storage_slots(c: Vector3i) -> Array:
	var k := cell_key(c)
	if not world_storage.has(k):
		world_storage[k] = _new_slots(27)
	return world_storage[k]

func catcher_eat(c: Vector3i) -> int:
	var bonus := 0
	var slots := storage_slots(c)
	for i in range(slots.size()):
		var d: Dictionary = slots[i]
		var id := str(d.get("id", ""))
		if int(d.get("count", 0)) == 100 and not idea_eaten.has(id):
			var seconds := Mining.idea_seconds(id)
			idea_eaten[id] = true
			dream_bonus_seconds += seconds
			bonus += seconds
			slots[i] = {}
	if bonus > 0:
		set_hint("Ловец идей: +%d с сна навсегда!" % bonus)
	return bonus

func storage_deposit(c: Vector3i, i: int, catcher: bool) -> int:
	if catcher and is_dream():
		return 0
	var d := get_slot(i).duplicate(true)
	var id := str(d.get("id", ""))
	if id == "" or (catcher and not is_placeable_block(id)):
		return 0
	var slots := storage_slots(c)
	var left := int(d.get("count", 0))
	var start := left
	for j in range(27):
		var old: Dictionary = slots[j]
		if old.get("id", "") != id or tool_max(id) > 0:
			continue
		var add := mini(left, ItemDB.max_stack(id) - int(old.get("count", 0)))
		old["count"] = int(old.get("count", 0)) + add
		left -= add
	for j in range(27):
		if left <= 0:
			break
		if str(slots[j].get("id", "")) == "":
			var add := mini(left, ItemDB.max_stack(id))
			slots[j] = d.duplicate(true)
			slots[j]["count"] = add
			left -= add
	# Даже на дев-сиде перенос не клонирует предметы.
	d["count"] = left
	set_slot(i, d)
	if catcher:
		catcher_eat(c)
	return start - left

func storage_take(c: Vector3i, i: int, catcher: bool) -> bool:
	if catcher and not is_dream():
		set_hint("Забрать из Ловца можно только во сне.")
		return false
	var slots := storage_slots(c)
	var d: Dictionary = slots[i]
	var id := str(d.get("id", ""))
	if id == "":
		return false
	# Инструменты не теряют индивидуальную прочность при переносе.
	if tool_max(id) > 0:
		for j in range(ITEM_SLOT_COUNT):
			if get_slot(j).get("id", "") == "":
				set_slot(j, d)
				slots[i] = {}
				return true
		return false
	var added := add_item_count(id, int(d.get("count", 0)))
	d["count"] = int(d.get("count", 0)) - added
	if int(d["count"]) <= 0:
		slots[i] = {}
	return added > 0

func break_storage(c: Vector3i) -> bool:
	if world_storage.has(cell_key(c)):
		for s in storage_slots(c):
			if s.get("id", "") != "":
				set_hint("Сначала опустоши хранилище.")
				return false
		world_storage.erase(cell_key(c))
	return true

func rotate_door(c: Vector3i) -> bool:
	var source := dream_blocks if is_dream() else wake_blocks
	c = root_cell(source,c)
	if source.get(c,{}).get("kind","")!="door": return false
	source[c]["facing"] = posmod(int(source[c].get("facing",0))+1,4)
	placed_cells_changed.emit(is_dream(),[c])
	return true

func toggle_door(c: Vector3i) -> bool:
	var source := dream_blocks if is_dream() else wake_blocks
	c = root_cell(source, c)
	if source.get(c, {}).get("kind", "") != "door":
		return false
	source[c]["open"] = not bool(source[c].get("open", false))
	placed_cells_changed.emit(is_dream(),[c])
	Sfx.play("door", get_tree().root)
	return true


func wake_solid(c: Vector3i) -> bool:
	if wake_blocks.get(c,{}).get("kind","")=="torch": return false
	if not wake_blocks.has(c):
		return false
	var root_at := root_cell(wake_blocks,c)
	var data: Dictionary = wake_blocks.get(root_at,{})
	return not (data.get("kind", "") == "door" and bool(data.get("open", false)))


func spread_mouth_once() -> bool:
	for c in wake_blocks.keys():
		if wake_blocks[c].get("kind", "") != "mouth" or beacon_protects(c):
			continue
		for d in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD, Vector3i.UP, Vector3i.DOWN]:
			var target: Vector3i = c+d
			var old: Dictionary = wake_blocks.get(target,{})
			var kind: String = old.get("kind", "")
			if kind == "" or kind == "mouth" or kind in NO_MUTATION_KINDS or old.has("root") or beacon_protects(target):
				continue
			old["kind"] = "mouth"
			old["mutant"] = true
			for vox in get_tree().get_nodes_in_group("voxel_world"):
				if not vox.is_dream_layer:
					vox.refresh_block(target,old)
			return true
	return false


func destroy_wake_structure(c: Vector3i, respect_beacon: bool = false) -> bool:
	c = root_cell(wake_blocks,c)
	if not wake_blocks.has(c):
		return false
	var kind: String = wake_blocks[c].get("kind", "")
	if respect_beacon and (beacon_protects(c) or (shape_part(kind) != "" and beacon_protects(c+part_offset(kind)))):
		return false
	if not break_storage(c):
		return false
	remove_shape(wake_blocks,c)
	if active_bed == cell_key(c):
		active_bed = ""
		spawn_point = creation_spawn
	inventory_changed.emit()
	return true


func _restore_craft(slots: Array, wallet: Dictionary, under_pillow: Array) -> void:
	item_slots.assign(slots)
	pouch = wallet
	pillow.assign(under_pillow)
	inventory_changed.emit()
	pillow_changed.emit()

func _migrate_beds(source: Dictionary) -> void:
	for c in source.keys():
		if source[c].get("kind", "") != "bed":
			continue
		var other: Vector3i = c+Vector3i.BACK
		if not source.has(other):
			add_shape_parts(source,c,"bed")
		elif source[other].get("root", "") != cell_key(c):
			# Не перезаписывать соседнюю постройку при загрузке старого одноклеточного ложа.
			source[c]["legacy_compact"] = true


func armor_points() -> int:
	var total := 0
	for d in armor:
		if not d.is_empty() and int(d.get("durability",tool_max(d.get("id",""))))>0:
			total += ArmorRules.points(d.get("id",""))
	return total

func equip_armor_from_slot(index: int) -> bool:
	var d := get_slot(index).duplicate(true)
	var a := ArmorRules.slot(d.get("id",""))
	if a<0: return false
	var old: Dictionary = armor[a].duplicate(true)
	armor[a] = d
	set_slot(index,old)
	inventory_changed.emit()
	return true

func wear_armor(raw_damage: int) -> void:
	if dev_mode: return
	for i in range(4):
		var d: Dictionary = armor[i]
		if d.is_empty(): continue
		d["durability"] = int(d.get("durability",tool_max(d.id)))-maxi(1,raw_damage/20)
		if int(d.durability)<=0:
			set_hint("Сломалась броня: "+ItemDB.display_name(d.id),false)
			armor[i] = {}
	inventory_changed.emit()

func set_sword2_flag(on: bool) -> void:
	set_sword3_flag(on) # console compatibility

func set_sword3_flag(on: bool) -> void:
	sword3_crafted = on
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.is_in_group("anaconda"): continue
		var base := int(enemy.get_meta("base_max_hp",enemy.get("max_hp")))
		apply_enemy_scaling(enemy,base,enemy.is_in_group("block_mother"))

func apply_enemy_scaling(enemy: Node,base: int,mother: bool = false) -> void:
	var fraction := float(enemy.get("hp"))/maxf(1.0,float(enemy.get("max_hp")))
	enemy.set_meta("base_max_hp",base)
	var mult := (3.0 if mother else 3.75) if sword3_crafted else 1.0
	var hp_max := ceili(base*mult)
	enemy.set("max_hp",hp_max)
	enemy.set("hp",maxi(0,ceili(hp_max*fraction)))
	load("res://scripts/enemy_visuals.gd").update_hp_bar(enemy,enemy.get("hp"),hp_max)

static func ray_cell(aim: Dictionary) -> Vector3i:
	var collider: Object = aim.get("collider")
	if collider and collider.has_meta("voxel_cell"): return collider.get_meta("voxel_cell")
	var inside: Vector3 = aim.get("position",Vector3.ZERO)-aim.get("normal",Vector3.UP)*0.02
	return Vector3i(floori(inside.x),floori(inside.y),floori(inside.z))

static func door_hinge_right(source: Dictionary,c: Vector3i,facing: int) -> bool:
	var right:=Vector3i((Basis(Vector3.UP,facing*PI/2)*Vector3.RIGHT).round())
	return source.get(c+right,{}).get("kind","") not in ["","torch","beacon"] and source.get(c-right,{}).get("kind","") in ["","torch","beacon"]
