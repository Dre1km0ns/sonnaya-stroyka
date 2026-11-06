extends Node
## Глобальное состояние «Сонная стройка» v0.4.5: копание холмов/руин, модели кирки и меча.

signal world_changed(is_dream: bool)
signal inventory_changed
signal clarity_changed(value: float, max_value: float)
signal hint_changed(text: String)
signal wake_resolved(transferred: int, dust_gained: int, mutations: int)
signal night_changed(is_night: bool)
signal boss_changed(alive: bool)

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
const ANCHOR3_COST_REAGENTS := 5
const ANCHOR3_COST_CLARITY := 30.0
const MUTATION_CHANCE := 0.25
const SAVE_FORMAT := 4
const REAGENT_CAP := 100
const REAGENT_TYPE_COUNT := 3
const REAGENT_NAMES: Array[String] = ["реагент1", "реагент2", "реагент3"]
const ITEM_SLOT_COUNT := 5
const MOBS_UNLOCK_AT_EXITS := 2

var current_world: World = World.WAKE
var clarity: float = CLARITY_MAX
var reagents: int = 0
var reagent_counts: Array = [0, 0, 0]
var dust: int = 0
var nails: int = 3
var wedges: int = 1
var anchors3: int = 0
var item_slots: Array = []
var selected_slot: int = 0
var dream_exit_count: int = 0
var collected_reagent_ids: Dictionary = {}

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
	set_hint("Явь. Собери реагенты (E), колесо — слоты. Кровать (E). F5/F9 — сейв.")


func _init_default_slots() -> void:
	item_slots = [
		{"id": "nail", "name": "Гвоздь", "count": nails},
		{"id": "wedge", "name": "Клин", "count": wedges},
		{"id": "anchor3", "name": "Якорь3", "count": anchors3},
		{"id": "", "name": "", "count": 0},
		{"id": "", "name": "", "count": 0},
	]


func _ensure_inventory() -> void:
	if reagent_counts.size() < REAGENT_TYPE_COUNT:
		reagent_counts = [0, 0, 0]
	if item_slots.size() != ITEM_SLOT_COUNT:
		_init_default_slots()


func reagent_type_name(type_id: int) -> String:
	var i := clampi(type_id - 1, 0, REAGENT_TYPE_COUNT - 1)
	return REAGENT_NAMES[i]


func get_reagent_count(type_id: int) -> int:
	var i := type_id - 1
	if i < 0 or i >= reagent_counts.size():
		return 0
	return int(reagent_counts[i])


func _typed_sum() -> int:
	var s := 0
	for i in range(mini(REAGENT_TYPE_COUNT, reagent_counts.size())):
		s += int(reagent_counts[i])
	return s


func _sync_reagent_total() -> void:
	reagents = _typed_sum()


func _reconcile_reagents() -> void:
	while reagent_counts.size() < REAGENT_TYPE_COUNT:
		reagent_counts.append(0)
	if reagent_counts.size() > REAGENT_TYPE_COUNT:
		reagent_counts.resize(REAGENT_TYPE_COUNT)
	for i in range(REAGENT_TYPE_COUNT):
		reagent_counts[i] = clampi(int(reagent_counts[i]), 0, REAGENT_CAP)
	var typed := _typed_sum()
	if reagents != typed:
		if reagents > typed:
			var extra := reagents - typed
			reagent_counts[0] = clampi(int(reagent_counts[0]) + extra, 0, REAGENT_CAP)
		else:
			var diff := typed - reagents
			for i in range(REAGENT_TYPE_COUNT):
				if diff <= 0:
					break
				var take := mini(int(reagent_counts[i]), diff)
				reagent_counts[i] -= take
				diff -= take
	_sync_reagent_total()


func add_typed_reagent(type_id: int, amount: int) -> int:
	_reconcile_reagents()
	var i := clampi(type_id - 1, 0, REAGENT_TYPE_COUNT - 1)
	var room := REAGENT_CAP - int(reagent_counts[i])
	var add := mini(maxi(amount, 0), room)
	if add <= 0:
		return 0
	reagent_counts[i] = int(reagent_counts[i]) + add
	_sync_reagent_total()
	inventory_changed.emit()
	return add


func spend_reagents(amount: int, emit_changed: bool = true) -> bool:
	_reconcile_reagents()
	if amount <= 0:
		return true
	if reagents < amount:
		return false
	var left := amount
	for i in range(REAGENT_TYPE_COUNT):
		var take := mini(int(reagent_counts[i]), left)
		reagent_counts[i] -= take
		left -= take
		if left <= 0:
			break
	_sync_reagent_total()
	if emit_changed:
		inventory_changed.emit()
	return true


func mobs_unlocked() -> bool:
	return dream_exit_count >= MOBS_UNLOCK_AT_EXITS


func mark_reagent_collected(id: String) -> void:
	if id == "":
		return
	collected_reagent_ids[id] = true


func is_reagent_collected(id: String) -> bool:
	return id != "" and collected_reagent_ids.has(id)


func select_item_slot(index: int) -> void:
	_ensure_inventory()
	selected_slot = clampi(index, 0, ITEM_SLOT_COUNT - 1)
	var item: Dictionary = item_slots[selected_slot]
	var id := str(item.get("id", ""))
	if id == "nail":
		selected_anchor = AnchorType.NAIL
		set_hint("Слот %d: Гвоздь (x%d). Q — заякорить." % [selected_slot + 1, nails])
	elif id == "wedge":
		selected_anchor = AnchorType.WEDGE
		set_hint("Слот %d: Клин (x%d). Q — заякорить." % [selected_slot + 1, wedges])
	elif id == "anchor3":
		selected_anchor = AnchorType.ANCHOR3
		set_hint("Слот %d: Якорь3 (x%d). Q — заякорить большую зону." % [selected_slot + 1, anchors3])
	elif id == "":
		set_hint("Слот %d: пусто." % (selected_slot + 1))
	else:
		set_hint("Слот %d: %s x%d" % [selected_slot + 1, str(item.get("name", id)), int(item.get("count", 0))])
	inventory_changed.emit()


func cycle_item_slot(delta: int) -> void:
	_ensure_inventory()
	select_item_slot(posmod(selected_slot + delta, ITEM_SLOT_COUNT))


func get_selected_item() -> Dictionary:
	_ensure_inventory()
	return item_slots[selected_slot]


func add_item(id: String, item_name: String, count: int = 1) -> int:
	_ensure_inventory()
	if id == "":
		return -1
	for i in range(ITEM_SLOT_COUNT):
		if str(item_slots[i].get("id", "")) == id and id != "nail" and id != "wedge":
			item_slots[i]["count"] = int(item_slots[i].get("count", 0)) + count
			inventory_changed.emit()
			return i
	for i in range(ITEM_SLOT_COUNT):
		if str(item_slots[i].get("id", "")) == "":
			item_slots[i] = {"id": id, "name": item_name, "count": count}
			inventory_changed.emit()
			return i
	return -1


func slot_display_count(index: int) -> int:
	_ensure_inventory()
	if index < 0 or index >= item_slots.size():
		return 0
	var id := str(item_slots[index].get("id", ""))
	if id == "nail":
		return nails
	if id == "wedge":
		return wedges
	if id == "anchor3":
		return anchors3
	return int(item_slots[index].get("count", 0))



func inventory_status_text() -> String:
	var extra := ""
	if not block_stash.is_empty():
		var bits: Array[String] = []
		for k in block_stash.keys():
			bits.append("%s x%d" % [block_display_name(str(k)), int(block_stash[k])])
		extra = "   запасы: " + ", ".join(bits)
	return "Осыпь: %d   Гвозди: %d   Клинья: %d   Якорь3: %d\n%s: %d   %s: %d   %s: %d%s" % [
		dust, nails, wedges, anchors3,
		reagent_type_name(1), get_reagent_count(1),
		reagent_type_name(2), get_reagent_count(2),
		reagent_type_name(3), get_reagent_count(3),
		extra,
	]


func recipe_defs() -> Array:
	return [
		{"id": "nail", "name": "Гвоздь", "where": "dream", "dust": NAIL_CRAFT_DUST, "gives": "nails"},
		{"id": "wedge", "name": "Клин", "where": "dream", "dust": WEDGE_CRAFT_DUST, "gives": "wedges"},
		{"id": "anchor3", "name": "Якорь3", "where": "dream", "dust": ANCHOR3_CRAFT_DUST, "gives": "anchors3"},
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
	if amount <= 0:
		return true
	if get_reagent_count(type_id) < amount:
		return false
	var i := type_id - 1
	reagent_counts[i] = int(reagent_counts[i]) - amount
	_sync_reagent_total()
	inventory_changed.emit()
	return true


func consume_item(id: String, amount: int = 1) -> bool:
	_ensure_inventory()
	if id == "nail":
		if nails < amount:
			return false
		nails -= amount
		inventory_changed.emit()
		return true
	if id == "wedge":
		if wedges < amount:
			return false
		wedges -= amount
		inventory_changed.emit()
		return true
	if id == "anchor3":
		if anchors3 < amount:
			return false
		anchors3 -= amount
		inventory_changed.emit()
		return true
	for i in range(ITEM_SLOT_COUNT):
		if str(item_slots[i].get("id", "")) == id and int(item_slots[i].get("count", 0)) >= amount:
			item_slots[i]["count"] = int(item_slots[i]["count"]) - amount
			if int(item_slots[i]["count"]) <= 0:
				item_slots[i] = {"id": "", "name": "", "count": 0}
			inventory_changed.emit()
			return true
	return false


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
	var item_id := str(rec.get("item", ""))
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
		_:
			return "Блок"


func is_placeable_block(id: String) -> bool:
	return id in ["drift", "mouth", "workbench", "hill", "ruin", "ground"]


func add_mined_block(kind: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	if add_item(kind, block_display_name(kind), amount) >= 0:
		return
	block_stash[kind] = int(block_stash.get(kind, 0)) + amount
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
	if clarity < amount:
		return false
	clarity = maxf(0.0, clarity - amount)
	clarity_changed.emit(clarity, CLARITY_MAX)
	return true


func drain_clarity(delta: float) -> void:
	if not is_dream():
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
	selected_slot = 0 if t == AnchorType.NAIL else 1
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


func can_afford_anchor(t: AnchorType) -> bool:
	_reconcile_reagents()
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
			wedges -= 1
			spend_reagents(WEDGE_COST_REAGENTS, false)
			spend_clarity(WEDGE_COST_CLARITY)
		else:
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
	set_hint("Сон. ЛКМ — блок, ПКМ — снять, 1/2/3 — якорь, Q — заякорить, C — меню крафта, F — проснуться.")


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
		if kind != "workbench" and kind != "torch" and randf() < MUTATION_CHANCE:
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
	var take := maxi(1, amount)
	if dust > 0:
		var got := mini(dust, take)
		dust -= got
		inventory_changed.emit()
		return "dust:%d" % got
	_reconcile_reagents()
	if reagents > 0:
		for i in range(REAGENT_TYPE_COUNT):
			if int(reagent_counts[i]) > 0:
				reagent_counts[i] -= 1
				_sync_reagent_total()
				inventory_changed.emit()
				return "reagent"
	return "none"


func count_enemies_in_tree(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("seam_creature").size()


# --- Save / load serialization ---

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_FORMAT,
		"world": "dream" if is_dream() else "wake",
		"clarity": clarity,
		"reagents": reagents,
		"reagent_counts": [get_reagent_count(1), get_reagent_count(2), get_reagent_count(3)],
		"dust": dust,
		"nails": nails,
		"wedges": wedges,
		"anchors3": anchors3,
		"day_time": day_time,
		"selected_anchor": int(selected_anchor),
		"selected_slot": selected_slot,
		"item_slots": item_slots.duplicate(true),
		"dream_exit_count": dream_exit_count,
		"collected_reagent_ids": collected_reagent_ids.keys(),
		"awake_time": awake_time,
		"world_seed_wake": world_seed_wake,
		"world_seed_dream": world_seed_dream,
		"wake_blocks": _blocks_to_json(wake_blocks),
		"dream_blocks": _blocks_to_json(dream_blocks),
		"pending_anchors": _anchors_to_json(pending_anchors),
		"removed_terrain": _cells_kind_to_json(removed_terrain),
	}


func apply_save_dict(data: Dictionary) -> void:
	dust = int(data.get("dust", 0))
	nails = int(data.get("nails", 3))
	wedges = int(data.get("wedges", 1))
	anchors3 = int(data.get("anchors3", 0))
	clarity = float(data.get("clarity", CLARITY_MAX))
	awake_time = float(data.get("awake_time", 0.0))
	day_time = float(data.get("day_time", 0.0))
	world_seed_wake = int(data.get("world_seed_wake", 1337))
	world_seed_dream = int(data.get("world_seed_dream", 9001))
	selected_anchor = int(data.get("selected_anchor", 0)) as AnchorType
	dream_exit_count = int(data.get("dream_exit_count", data.get("wake_count", 0)))
	selected_slot = clampi(int(data.get("selected_slot", 0)), 0, ITEM_SLOT_COUNT - 1)
	var rc: Variant = data.get("reagent_counts", null)
	reagent_counts = [0, 0, 0]
	if typeof(rc) == TYPE_ARRAY:
		for i in range(mini(REAGENT_TYPE_COUNT, rc.size())):
			reagent_counts[i] = clampi(int(rc[i]), 0, REAGENT_CAP)
		_sync_reagent_total()
	else:
		reagents = int(data.get("reagents", 0))
		_reconcile_reagents()
	var slots: Variant = data.get("item_slots", null)
	if typeof(slots) == TYPE_ARRAY and slots.size() == ITEM_SLOT_COUNT:
		item_slots = []
		for s in slots:
			if typeof(s) != TYPE_DICTIONARY:
				item_slots.append({"id": "", "name": "", "count": 0})
			else:
				item_slots.append({
					"id": str(s.get("id", "")),
					"name": str(s.get("name", "")),
					"count": int(s.get("count", 0)),
				})
	else:
		_init_default_slots()
	_ensure_anchor3_slot()
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
	var w := str(data.get("world", "wake"))
	current_world = World.DREAM if w == "dream" else World.WAKE
	clarity_changed.emit(clarity, CLARITY_MAX)
	inventory_changed.emit()
	world_changed.emit(is_dream())



func _ensure_anchor3_slot() -> void:
	_ensure_inventory()
	var has := false
	for i in range(item_slots.size()):
		if str(item_slots[i].get("id", "")) == "anchor3":
			item_slots[i]["count"] = anchors3
			has = true
	if has:
		return
	if item_slots.size() > 2 and str(item_slots[2].get("id", "")) == "":
		item_slots[2] = {"id": "anchor3", "name": "Якорь3", "count": anchors3}


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

