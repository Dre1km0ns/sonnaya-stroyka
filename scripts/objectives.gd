extends RefCounted
## v0.11: цепочка целей/вех. Состояние — в GameState.milestones (сохраняется).
## Показывается только текущая рекомендация + ближайшая крупная веха.

const LIST := [
	{"id":"reagents","title":"Собери реагенты у лагеря","how":"Светящиеся кристаллы и травы вокруг разрушенного лагеря. Подойди — автоподбор. Они нужны для крафта во Сне.","stage":0},
	{"id":"first_dream","title":"Ляг на кровать и усни","how":"Кровать — в центре лагеря. E — уснуть. Во Сне ты можешь построить то, что пока невозможно в Яви.","stage":0},
	{"id":"dream_build","title":"Построй во Сне 5+ блоков","how":"ЛКМ — дрейф-блок (бесплатно). В инвентаре Сна лежит Верстак: выбери его в хотбаре и поставь рядом.","stage":0},
	{"id":"first_anchor","title":"Закрепи постройку якорем","how":"R — выбрать Клин (зона 5×5×5), наведись на постройку и нажми Q. Только закреплённое перейдёт в Явь — остальное растворится.","stage":0},
	{"id":"first_transfer","title":"Проснись и найди постройку в Яви","how":"F — проснуться. Закреплённые блоки появятся в Яви на тех же координатах.","stage":0,"big":true},
	{"id":"workbench","title":"Верстак в Яви","how":"Перенеси верстак из Сна (поставь его во Сне и закрепи). E у верстака — кирка, меч, факелы.","stage":1},
	{"id":"pickaxe","title":"Скрафти кирку","how":"Верстак: 2 реагент1 + 1 реагент2. Кирка добывает камень; без неё камень не выпадает.","stage":1},
	{"id":"torch","title":"Сделай факелы","how":"Добудь бревно (ЛКМ по дереву, можно рукой). Верстак: 1 бревно + 1 реагент1 = 4 факела. Ночью свет спасает.","stage":1},
	{"id":"sawmill","title":"Лесопилка в Яви","how":"Во Сне C → Лесопилка (4 р1 + 3 р2 + 2 р3). Поставь, закрепи, проснись. На ней — доски, сундук, дверь.","stage":1},
	{"id":"chest","title":"Поставь сундук","how":"Лесопилка: 6 досок → Сундук на 27 ячеек. Хранилище Яви и Сна — раздельное; заякоренный сундук переносит содержимое.","stage":1},
	{"id":"shelter","title":"Убежище: 30+ блоков и дверь или кровать","how":"Построй дом — во Сне быстрее (бесплатные блоки, перенос якорем) или руками в Яви. Нужны стены, дверь или своя кровать.","stage":1,"big":true},
	{"id":"cave_prep","title":"Подготовься к глубине: Кирка2 и 8 факелов","how":"Во Сне — Станок (5 р3 + 2 р2 + 20 осыпи). На станке: Кирка2 = кирка + 6 камня + 1 р2. Меч2 — тоже там.","stage":2},
	{"id":"mother_signs","title":"Спустись ниже y −6 — найди следы Матери","how":"Копай под землёй: каждый блок глубины поднимает «угрозу глубин». На 40% и 70% будут предупреждения, на 100% придёт Мать блоков.","stage":3},
	{"id":"mother","title":"Победи Мать блоков","how":"Следи за тенью удара и волнами. Между фазами она уязвима (×1.5 урона). H — автолечение. Награда: алхимия, Ловец идей, Архив Снов.","stage":3,"big":true},
	{"id":"alchemy","title":"Алхимический стол → Хилка2","how":"Во Сне C → Алхимический стол (4 р2 + 4 р3 + 60 осыпи). Хилка2 = хилка1 + 2 р3, лечит 40.","stage":3},
	{"id":"nest","title":"Найди гнездо Анаконды","how":"Гнёзда — тёмные круги с яйцом в дальних землях. Анаконда приходит ночью. Меч её почти не берёт — нужен СВЕТ: факелы вокруг и в руке.","stage":4},
	{"id":"anaconda","title":"Победи Анаконду светом","how":"Урон наносят только поставленные факелы: окружи её светом с разных сторон (2–3 источника). Её тело ломает факелы — держи запасные. Награда: чешуя → Меч3, броня, Сердце света.","stage":4,"big":true},
	{"id":"catcher","title":"Ловец идей: продли Сон","how":"Ловец (во Сне C) ставь рядом с кроватью в Яви. Положи 50+ блоков одного типа — Сон станет длиннее навсегда (до +60 с).","stage":5},
	{"id":"archive","title":"Сохрани чертёж в Архиве Снов","how":"Во Сне B — сохранить постройку (до 3 чертежей), N — показать контур. Блоки всё равно ставишь ты.","stage":5},
]

const FINAL := {"id":"","title":"Свободная стройка","how":"Все вехи пройдены. Строй невозможное во Сне — и доказывай, что способен этим воспользоваться в Яви.","stage":5}


static func title(id: String) -> String:
	for o in LIST:
		if o.id == id: return o.title
	return ""


static func index_of(id: String) -> int:
	for i in range(LIST.size()):
		if LIST[i].id == id: return i
	return -1


static func current(gs: Node) -> Dictionary:
	## Первая невыполненная цель ПОСЛЕ самой поздней выполненной: если игрок перескочил шаг
	## (например, лёг спать без реагентов), панель не застревает на пройденном этапе. Большие ★-этапы
	## (первый перенос, убежище, Мать, Анаконда) не пропускаются никогда.
	var last := -1
	for i in range(LIST.size()):
		if gs.milestones.has(LIST[i].id): last = i
	for i in range(0, last):
		if LIST[i].get("big", false) and not gs.milestones.has(LIST[i].id): return LIST[i]  # ★-этапы не пропускаем
	for i in range(last + 1, LIST.size()):
		if not gs.milestones.has(LIST[i].id): return LIST[i]
	for o in LIST:
		if not gs.milestones.has(o.id): return o
	return FINAL


static func next_big(gs: Node) -> Dictionary:
	var cur := current(gs)
	var start := index_of(str(cur.get("id","")))
	if start < 0: return {}
	for i in range(start + 1, LIST.size()):
		if LIST[i].get("big", false) and not gs.milestones.has(LIST[i].id): return LIST[i]
	return {}


static func done_count(gs: Node) -> int:
	var n := 0
	for o in LIST:
		if gs.milestones.has(o.id): n += 1
	return n


static func check_all(gs: Node) -> Array:
	## Условия, которые можно проверить по состоянию (вехи-события ставятся напрямую в GameState).
	var out: Array = []
	var m: Dictionary = gs.milestones
	var want := func(id: String, cond: bool) -> void:
		if cond and not m.has(id): out.append(id)
	want.call("reagents", gs.collected_reagent_ids.size() >= 2 or gs.dream_exit_count > 0)
	want.call("dream_build", gs.is_dream() and gs._dream_session_blocks >= 5)
	want.call("first_transfer", gs._transfers_done > 0)
	want.call("workbench", gs.wake_kind_count("workbench") > 0)
	want.call("pickaxe", gs.wake_has_item("pickaxe") + gs.wake_has_item("pickaxe2") > 0)
	want.call("torch", gs.wake_has_item("torch") > 0 or gs.wake_kind_count("torch") > 0)
	want.call("sawmill", gs.wake_kind_count("sawmill") > 0)
	want.call("chest", gs.wake_kind_count("chest") > 0)
	want.call("shelter", gs.wake_build_count() >= 30 and (gs.wake_kind_count("door") > 0 or gs.wake_kind_count("bed") > 0))
	want.call("cave_prep", gs.wake_has_item("pickaxe2") > 0 and gs.wake_has_item("torch") + gs.wake_kind_count("torch") >= 8)
	want.call("mother_signs", gs.deep_threat >= gs.DEEP_THREAT_WARN1 or gs.mother_defeated)
	want.call("mother", gs.mother_defeated)
	want.call("alchemy", gs.wake_kind_count("alchemy") > 0)
	want.call("nest", gs.nest_found or gs.anaconda_defeated)
	want.call("anaconda", gs.anaconda_defeated)
	want.call("catcher", gs.dream_bonus_seconds > 0.0)
	want.call("archive", not gs.blueprints.is_empty())
	return out
