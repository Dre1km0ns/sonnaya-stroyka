extends Node
## Глобальное состояние «Сонная стройка» v0.4: типы реагентов, инвентарь, wake-count.

signal world_changed(is_dream: bool)
signal inventory_changed
signal clarity_changed(value: float, max_value: float)
signal hint_changed(text: String)
signal wake_resolved(transferred: int, dust_gained: int, mutations: int)

enum World { WAKE, DREAM }
enum AnchorType { NAIL, WEDGE }

const CLARITY_MAX := 100.0
const CLARITY_DRAIN_PER_SEC := 2.5
const NAIL_COST_REAGENTS := 1
const NAIL_COST_CLARITY := 5.0
const WEDGE_COST_REAGENTS := 3
const WEDGE_COST_CLARITY := 20.0
const WEDGE_SIZE := 5
const DUST_PER_BLOCK := 1
const NAIL_CRAFT_DUST := 5
const WEDGE_CRAFT_DUST := 15
const MUTATION_CHANCE := 0.25
const SAVE_FORMAT := 2
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
var world_seed_wake: int = 1337
var world_seed_dream: int = 9001


func _init() -> void:
	_init_default_slots()


func _ready() -> void:
	_ensure_inventory()
	set_hint("Явь. Собери реагенты (E), колесо — слоты. Кровать (E). F5/F9 — сейв.")


func _init_default_slots() -> void:
	item_slots = [
		{"id": "nail", "name": "Гвоздь", "count": nails},
		{"id": "wedge", "name": "Клин", "count": wedges},
		{"id": "", "name": "", "count": 0},
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
	return int(item_slots[index].get("count", 0))


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
	if dust < NAIL_CRAFT_DUST:
		set_hint("Нужно %d осыпи для Гвоздя." % NAIL_CRAFT_DUST)
		return false
	dust -= NAIL_CRAFT_DUST
	nails += 1
	inventory_changed.emit()
	set_hint("Скрафчен Гвоздь из осыпи (+1).")
	return true


func craft_wedge_from_dust() -> bool:
	if dust < WEDGE_CRAFT_DUST:
		set_hint("Нужно %d осыпи для Клины (дефицит!)." % WEDGE_CRAFT_DUST)
		return false
	dust -= WEDGE_CRAFT_DUST
	wedges += 1
	inventory_changed.emit()
	set_hint("Скрафчен Клин из осыпи (+1). Дорого — береги.")
	return true


func craft_selected_from_dust() -> bool:
	if selected_anchor == AnchorType.WEDGE:
		return craft_wedge_from_dust()
	return craft_nail_from_dust()


func select_anchor(t: AnchorType) -> void:
	selected_anchor = t
	selected_slot = 0 if t == AnchorType.NAIL else 1
	if t == AnchorType.NAIL:
		set_hint("Выбран Гвоздь (1 блок). Q — заякорить. C — крафт (%d осыпи)." % NAIL_CRAFT_DUST)
	else:
		set_hint("Выбран Клин (~%dx%dx%d). Q — заякорить. C — крафт (%d осыпи)." % [
			WEDGE_SIZE, WEDGE_SIZE, WEDGE_SIZE, WEDGE_CRAFT_DUST
		])


func can_afford_anchor(t: AnchorType) -> bool:
	_reconcile_reagents()
	if t == AnchorType.NAIL:
		return nails >= 1 and reagents >= NAIL_COST_REAGENTS and clarity >= NAIL_COST_CLARITY
	return wedges >= 1 and reagents >= WEDGE_COST_REAGENTS and clarity >= WEDGE_COST_CLARITY


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
		var half := WEDGE_SIZE / 2
		for x in range(origin.x - half, origin.x - half + WEDGE_SIZE):
			for y in range(origin.y - half, origin.y - half + WEDGE_SIZE):
				for z in range(origin.z - half, origin.z - half + WEDGE_SIZE):
					var c := Vector3i(x, y, z)
					if dream_blocks.has(c):
						cells.append(c)
		if cells.is_empty():
			set_hint("Клин: в зоне нет блоков.")
			return false
		wedges -= 1
		spend_reagents(WEDGE_COST_REAGENTS, false)
		spend_clarity(WEDGE_COST_CLARITY)

	for c in cells:
		var data: Dictionary = dream_blocks[c]
		data["anchored"] = true
		dream_blocks[c] = data

	pending_anchors.append({"type": t, "origin": origin, "cells": cells})
	inventory_changed.emit()
	var aname := "Гвоздь" if t == AnchorType.NAIL else "Клин"
	set_hint("%s: заякорено %d блок(ов). F — проснуться." % [aname, cells.size()])
	return true


func enter_dream() -> void:
	current_world = World.DREAM
	clarity = CLARITY_MAX
	awake_time = 0.0
	clarity_changed.emit(clarity, CLARITY_MAX)
	world_changed.emit(true)
	set_hint("Сон. ЛКМ — блок, ПКМ — снять, 1/2 — якорь, Q — заякорить, C — крафт, F — проснуться.")


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
		var mutant := false
		if randf() < MUTATION_CHANCE:
			mutant = true
			mutations += 1
		wake_blocks[cell] = {
			"kind": "mouth" if mutant else data.get("kind", "drift"),
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
	}


func apply_save_dict(data: Dictionary) -> void:
	dust = int(data.get("dust", 0))
	nails = int(data.get("nails", 3))
	wedges = int(data.get("wedges", 1))
	clarity = float(data.get("clarity", CLARITY_MAX))
	awake_time = float(data.get("awake_time", 0.0))
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
	var w := str(data.get("world", "wake"))
	current_world = World.DREAM if w == "dream" else World.WAKE
	clarity_changed.emit(clarity, CLARITY_MAX)
	inventory_changed.emit()
	world_changed.emit(is_dream())


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
