extends Node
## v0.24 (п.20): вехи прогресса — общие для всех миров, хранятся в user://progress.cfg, видны в главном меню («Прогресс»).
## Узел «Milestones» в мире раз в 2 с проверяет условия и отмечает новые вехи (с сообщением в чат).
const PATH := "user://progress.cfg"
const LIST := [
	["night1", "Первая ночь", "Пережить первую ночь в Яви"],
	["stone_pick", "Каменная кирка", "Сделать каменную кирку — теперь можно добывать руду"],
	["metal", "Металл", "Сделать металлическую кирку"],
	["bow", "Лучник", "Сделать любой лук"],
	["armor", "В броне", "Надеть любую броню"],
	["night5", "Пять ночей", "Пережить пять ночей"],
	["mother", "Мать блоков", "Победить Мать блоков"],
	["anaconda", "Анаконда", "Победить Анаконду"],
	["burger", "Бургер Смерти", "Победить финального босса"],
	["expert", "Эксперт", "Победить Бургера Смерти на сложности «Эксперт»"],
	["coop", "Вместе", "Сыграть сетевую игру с другом"],
]
var _t := 0.0


static func load_all() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {}
	if cfg.load(PATH) == OK:
		for k in cfg.get_section_keys("done") if cfg.has_section("done") else PackedStringArray():
			out[k] = str(cfg.get_value("done", k, ""))
	return out


static func mark(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if cfg.has_section_key("done", id):
		return false
	cfg.set_value("done", id, Time.get_date_string_from_system())
	cfg.save(PATH)
	return true


static func title_of(id: String) -> String:
	for m in LIST:
		if m[0] == id: return m[1]
	return id


static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func current_conditions() -> Array:
	var g := GameState
	var out: Array = []
	if g.nights_survived >= 1: out.append("night1")
	if g.nights_survived >= 5: out.append("night5")
	if g.count_item("pickaxe2") > 0 or g.count_item("pickaxe3") > 0: out.append("stone_pick")
	if g.count_item("pickaxe3") > 0: out.append("metal")
	if g.count_item("bow") > 0 or g.count_item("bow2") > 0: out.append("bow")
	for a in g.armor:
		if a is Dictionary and not (a as Dictionary).is_empty():
			out.append("armor"); break
	if g.mother_defeated: out.append("mother")
	if g.anaconda_defeated: out.append("anaconda")
	if g.burger_defeated:
		out.append("burger")
		if g.is_expert(): out.append("expert")
	if g.net_players > 1: out.append("coop")
	return out


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 2.0
	if GameState.world_folder == "" and not NetSession.is_client():
		return   # кадры и тесты без мира
	for id in current_conditions():
		if mark(id):
			GameState.chat("Новая веха: «%s». Все вехи — в главном меню, «Прогресс»." % title_of(id), Color(1.0, 0.85, 0.45), true)
