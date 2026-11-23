extends RefCounted
## v0.5: справочник предметов (имя, размер стака, иконка) и «особых» предметов
## для вертикальной полосы (якоря, маяки) — они не лежат в инвентаре.

## v0.7: стак — 100 предметов (инструменты — 1). Реагенты и осыпь лежат в «кошеле» (общий для яви и сна).
const ITEMS := {
	"bedrock":{"name":"Бедрок","stack":100},
	"anaconda_scale":{"name":"Чешуя Анаконды","stack":100},
	"wood_helmet":{"name":"Деревянный шлем","stack":1},
	"wood_chest":{"name":"Деревянный нагрудник","stack":1},
	"wood_legs":{"name":"Деревянные поножи","stack":1},
	"wood_boots":{"name":"Деревянные ботинки","stack":1},
	"scale_helmet":{"name":"Чешуйчатый шлем","stack":1},
	"scale_chest":{"name":"Чешуйчатый нагрудник","stack":1},
	"scale_legs":{"name":"Чешуйчатые поножи","stack":1},
	"scale_boots":{"name":"Чешуйчатые ботинки","stack":1},
	"dirt": {"name":"Земля", "stack":100},
	"pickaxe2": {"name": "Каменная кирка", "stack": 1},
	"deep_stone": {"name": "Глубинный камень", "stack": 100},
	"mossy_ruin": {"name": "Заросший руинный блок", "stack": 100},
	"sawmill": {"name": "Лесопилка", "stack": 100},
	"alchemy": {"name": "Алхимический стол", "stack": 100},
	"idea_catcher": {"name": "Ловец идей", "stack": 100},
	"door": {"name": "Дверь", "stack": 100},
	"chest": {"name": "Сундук", "stack": 100},
	"heal2": {"name": "Хилка2", "stack": 100},
	"reagent1": {"name": "реагент1", "stack": 100},
	"reagent2": {"name": "реагент2", "stack": 100},
	"reagent3": {"name": "реагент3", "stack": 100},
	"dust": {"name": "Осыпь", "stack": 100000},
	"workbench": {"name": "Верстак", "stack": 100},
	"pickaxe": {"name": "Деревянная кирка", "stack": 1},
	"sword": {"name": "Деревянный меч", "stack": 1},
	"torch": {"name": "Факел", "stack": 100},
	"ruin": {"name": "Руинный блок", "stack": 100},
	"drift": {"name": "Дрейф-блок", "stack": 100},
	"mouth": {"name": "Рот", "stack": 100},
	"log": {"name": "Бревно", "stack": 100},
	"leaves": {"name": "Листва", "stack": 100},
	"planks": {"name": "Доски", "stack": 100},
	"stone": {"name": "Камень", "stack": 100},
	"sand": {"name": "Песок", "stack": 100},
	"nest": {"name": "Гнездо", "stack": 100},
	"bed": {"name": "Кровать", "stack": 100},
	"lathe": {"name": "Станок", "stack": 100},
	"sword3": {"name":"Чешуйчатый меч","stack":1},
	"sword2": {"name": "Каменный меч", "stack": 1},
	"heal1": {"name": "хилка1", "stack": 100},
	"anaconda_egg": {"name": "Яйцо Анаконды", "stack": 100},
	"strut": {"name": "Подпорка", "stack": 100},
	# v0.24: металл, луки, стрелы, лут боссов, финальный босс, зелье скорости
	"metal_ore": {"name": "Металлическая руда", "stack": 100},
	"metal_ingot": {"name": "Металлический слиток", "stack": 100},
	"pickaxe3": {"name": "Металлическая кирка", "stack": 1},
	"metal_sword": {"name": "Металлический меч", "stack": 1},
	"metal_helmet": {"name": "Металлический шлем", "stack": 1},
	"metal_chest": {"name": "Металлический нагрудник", "stack": 1},
	"metal_legs": {"name": "Металлические поножи", "stack": 1},
	"metal_boots": {"name": "Металлические ботинки", "stack": 1},
	"bow": {"name": "Деревянный лук", "stack": 1},
	"bow2": {"name": "Металлический лук", "stack": 1},
	"arrow": {"name": "Стрела", "stack": 100},
	"arrow2": {"name": "Стрела из детёнышей анаконды", "stack": 100},
	"milk_tooth": {"name": "Молочный зубок", "stack": 100},
	"stone_heart": {"name": "Каменное сердце", "stack": 100},
	"scale_fang": {"name": "Чешуйчатый клык", "stack": 100},
	"burger_summoner": {"name": "Призывалка бургера", "stack": 100},
	"burger_core": {"name": "Ядро бургера", "stack": 100},
	"clown_nose": {"name": "Нос клоуна", "stack": 100},
	"grill_saucer": {"name": "Гриль-тарелка", "stack": 1},
	"burger_trophy": {"name": "Трофей Бургера Смерти", "stack": 100},
	"speed_potion": {"name": "Зелье скорости", "stack": 100},
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
	return 100


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
