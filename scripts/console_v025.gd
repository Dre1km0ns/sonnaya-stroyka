extends RefCounted
## v0.25: команды DevSeed для новых функций. Регистрируются в console_v024 (extra_help / handlers) из dev_console._ready.
const V24 := preload("res://scripts/console_v024.gd")
const Gear := preload("res://scripts/gear.gd")
const Chunky := preload("res://scripts/chunky_body.gd")

const HELP := {
	"map": "Карта мира v0.25 (слева сверху): ты — стрелка, другие игроки — точки, живые боссы — значки-лица. toggle — скрыть/показать (как Tab); goals — скрыть/показать вехи (как F2); status. Клавиши меняются в настройках. Пример: map status; map toggle; map goals",
	"chunky": "Новый вид мобов v0.25 (толстый стиль Антона). list — все пресеты; spawn <пресет> — поставить неподвижную модель перед игроком; attack — проиграть атаку у всех поставленных; clear — убрать. Пример: chunky list; chunky spawn archer; chunky attack",
	"bowinfo": "Луки v0.25: клик — выстрел, перезарядка между выстрелами; первые 75 % дальности стрела летит ровно со 100 % урона, дальше падает, урон до 80 %. Показывает перезарядку и дальность обоих луков. Пример: bowinfo",
	"dmgtick": "Урон касанием v0.25: контактный урон, снаряды и зоны от одного источника бьют не чаще раза в секунду, пока ты в них. status — интервал и сколько источников сейчас «на перезарядке». Пример: dmgtick",
	"chase": "Погоня Бургера v0.25: если игрок убегает дальше 14 м, тарелка/Антон ускоряются (до ×5), догнав (ближе 9 м) — обычная скорость. Показывает текущий множитель и расстояние. Пример: chase",
	"mpsync": "Проверка общего мира v0.25: подпись мира (сид|хэш рельефа вокруг спавна). Сравни у хоста и клиента — должны совпасть. Пример: mpsync",
}
const COMPLETIONS := ["map status", "map toggle", "map goals", "chunky list", "chunky spawn ", "chunky attack", "chunky clear",
	"bowinfo", "dmgtick", "chase", "mpsync"]


static func register() -> void:
	for k in HELP:
		V24.extra_help[k] = HELP[k]
		V24.handlers[k] = func(c: Node, aa: PackedStringArray) -> String: return run(c, aa)
	for c in COMPLETIONS:
		if not V24.extra_completions.has(c): V24.extra_completions.append(c)
	for p in Chunky.PRESETS:
		var s := "chunky spawn " + str(p)
		if not V24.extra_completions.has(s): V24.extra_completions.append(s)


static func world_sig(tree: SceneTree) -> String:
	var cm: Node = null
	for c in tree.get_nodes_in_group("chunk_manager"):
		if not bool(c.get("is_dream_layer")): cm = c
	var h := 0
	if cm:
		for x in range(-60, 60, 2):
			for z in range(-60, 60, 2):
				h = (h * 31 + int(cm.height_at(x, z)) + (7 if cm.is_world_in_lake(Vector3(x, 0, z)) else 0)) % 1000000007
	return "%d|%d" % [int(GameState.world_seed), h]


static func run(con: Node, a: PackedStringArray) -> String:
	var sub := a[1] if a.size() > 1 else "status"
	var tree := con.get_tree()
	var p: Node3D = tree.get_first_node_in_group("player")
	match a[0]:
		"map":
			var m: Node = tree.get_first_node_in_group("world_map")
			if m == null: return "Карты нет (нужен мир)."
			if sub == "toggle": m.toggle_map()
			elif sub == "goals": m.toggle_goals()
			return "Карта: %s, вехи: %s." % ["видна" if bool(m.get("shown")) else "скрыта", "видны" if bool(m.get("goals_shown")) else "скрыты"]
		"chunky":
			if sub == "list": return "Пресеты: " + ", ".join(PackedStringArray(Chunky.PRESETS.keys()))
			if sub == "clear":
				var n := 0
				for c in tree.get_nodes_in_group("chunky_preview"):
					c.queue_free(); n += 1
				return "Убрано моделей: %d" % n
			if sub == "attack":
				for c in tree.get_nodes_in_group("chunky_preview"):
					c.play_state("attack", true)
				return "Атака проиграна."
			if sub == "spawn":
				var pr := a[2] if a.size() > 2 else "seam"
				if not Chunky.PRESETS.has(pr): return "Нет пресета «%s». chunky list — список." % pr
				if p == null: return "Нет игрока."
				var mdl: Node3D = Chunky.make(pr)
				mdl.add_to_group("chunky_preview")
				tree.current_scene.add_child(mdl)
				var fw := -p.global_transform.basis.z
				fw.y = 0
				mdl.global_position = p.global_position + fw.normalized() * 4.0
				return "Поставлен «%s», рост %.2f м." % [pr, float(mdl.height())]
			return HELP["chunky"]
		"bowinfo":
			var out := PackedStringArray()
			for id in Gear.BOWS:
				var bw: Dictionary = Gear.BOWS[id]
				out.append("%s: перезарядка %.2f с, дальность %d м (ровно до %d м), урон ×%.1f" % [id, float(bw["cd"]), int(bw["range"]), int(float(bw["range"]) * 0.75), float(bw["mult"])])
			return "\n".join(out)
		"dmgtick":
			var hot := 0
			var hits: Dictionary = GameState.get("_src_hit")
			var clk := float(GameState.get("_clock"))
			for s in hits:
				if clk - float(hits[s]) < GameState.DAMAGE_TICK: hot += 1
			return "Интервал урона от источника: %.1f с; на перезарядке: %d" % [GameState.DAMAGE_TICK, hot]
		"chase":
			var bb: Node3D = tree.get_first_node_in_group("burger_boss")
			if bb == null: return "Бургера нет. burger now — вызвать."
			var dist := -1.0
			if p: dist = bb.global_position.distance_to(p.global_position)
			return "Погоня: ×%.2f, до игрока %.1f м (ускорение после %d м, до ×%d)." % [float(bb.get("chase_mult")), dist, int(bb.CHASE_FAR), int(bb.CHASE_MAX)]
		"mpsync":
			var ns: Node = con.get_node_or_null("/root/NetSession")
			var mode := "одиночная"
			if ns and ns.has_method("is_client") and ns.is_client(): mode = "клиент"
			elif ns and ns.has_method("is_host") and ns.is_host(): mode = "хост"
			return "Подпись мира (%s): %s" % [mode, world_sig(tree)]
	return ""
