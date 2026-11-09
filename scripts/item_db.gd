extends RefCounted
## v0.5: справочник предметов (имя, размер стака, иконка) и «особых» предметов
## для вертикальной полосы (якоря, маяки) — они не лежат в инвентаре.

const ITEMS := {
	"reagent1": {"name": "реагент1", "stack": 64},
	"reagent2": {"name": "реагент2", "stack": 64},
	"reagent3": {"name": "реагент3", "stack": 64},
	"dust": {"name": "Осыпь", "stack": 999},
	"workbench": {"name": "Верстак", "stack": 16},
	"pickaxe": {"name": "Кирка", "stack": 1},
	"sword": {"name": "Меч", "stack": 1},
	"torch": {"name": "Факел", "stack": 64},
	"hill": {"name": "Холм", "stack": 64},
	"ruin": {"name": "Руинный блок", "stack": 64},
	"ground": {"name": "Грунт", "stack": 64},
	"drift": {"name": "Дрейф-блок", "stack": 64},
	"mouth": {"name": "Рот", "stack": 64},
	"log": {"name": "Бревно", "stack": 64},
	"leaves": {"name": "Листва", "stack": 64},
	"planks": {"name": "Доски", "stack": 64},
}

## Особые предметы: только вертикальная полоса справа. key -> поле GameState.
const SPECIAL := [
	{"id": "nail", "name": "Гвоздь", "field": "nails", "anchor": 0},
	{"id": "wedge", "name": "Клин", "field": "wedges", "anchor": 1},
	{"id": "anchor3", "name": "Якорь3", "field": "anchors3", "anchor": 2},
	{"id": "beacon", "name": "Маяк", "field": "beacons", "anchor": -1},
]

static var _icon_cache: Dictionary = {}


static func is_special(id: String) -> bool:
	for s in SPECIAL:
		if str(s["id"]) == id:
			return true
	return false


static func display_name(id: String, fallback: String = "") -> String:
	if ITEMS.has(id):
		return str(ITEMS[id]["name"])
	for s in SPECIAL:
		if str(s["id"]) == id:
			return str(s["name"])
	return fallback if fallback != "" else id


static func max_stack(id: String) -> int:
	if ITEMS.has(id):
		return int(ITEMS[id]["stack"])
	return 64


static func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := "res://assets/icons/%s.png" % id
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and ResourceLoader.exists("res://assets/icons/unknown.png"):
		tex = load("res://assets/icons/unknown.png") as Texture2D
	_icon_cache[id] = tex
	return tex


static func all_icon_ids() -> Array:
	var out: Array = ITEMS.keys()
	for s in SPECIAL:
		out.append(str(s["id"]))
	out.append("unknown")
	return out
