extends RefCounted
## v0.24: команды DevSeed для новых функций. Подключены в dev_console._execute и help.
const Gear := preload("res://scripts/gear.gd")
const DB := preload("res://scripts/item_db.gd")

const HELP := {
	"difficulty": "Сложность мира v0.24: «Нормальный» или «Эксперт» (+75 % HP всем мобам и боссам, больнее, быстрее, раньше замечают, реже отстают). status — текущая; normal / expert — переключить в этом мире. Пример: difficulty; difficulty expert",
	"ore": "Металлическая руда v0.24: гнёзда в камне на глубине −7…−26, добывается только каменной киркой или лучше. find — ближайшая руда у игрока; here — поставить руду под прицел; rules — время добычи по киркам. Пример: ore find; ore here; ore rules",
	"bow": "Луки v0.24: ЛКМ удерживать — натянуть, отпустить — выстрел. give wood / give metal — дать лук и 32 стрелы; shoot [0..1] — выстрел с натяжением; status. Пример: bow give metal; bow shoot 1",
	"arrows": "Стрелы v0.24: give [n] — обычные; best [n] — стрелы из детёнышей анаконды; status. Пример: arrows give 64; arrows best 16",
	"burger": "Бургер Смерти v0.24 — финальный босс. summon — призывалка с отсчётом 60 с; now — прилёт сразу; phase 2 / phase 3 — перейти к Антону / ярости; shards — смерть и осколки; weak — сбить слабую точку; hp <n>; kill; leave; status. Пример: burger now; burger phase 2; burger status",
	"summoner": "Призывалка бургера v0.24: give — дать призывалку; tokens — дать Каменное сердце и Чешуйчатый клык; roll mother|anaconda — проверить шанс 35 %. Пример: summoner give; summoner roll mother",
	"speedpotion": "Зелье скорости v0.24 (алхимический стол): 60 с бег не тратит стамину и чуть быстрее. give [n]; drink; status. Пример: speedpotion give 3; speedpotion drink",
	"lizards": "Ящерки-детёныши Анаконды v0.24: после её смерти появляются в пещерах, роняют молочные зубки. spawn [n] — рядом; status. Пример: lizards spawn 3; lizards status",
	"weather": "Погода Яви v0.24: ясно / дождь / туман, меняется сама каждые 4–9 минут. clear / rain / fog — включить сразу; status — текущая и сколько до смены. Пример: weather rain; weather status",
	"mobs": "Новые мобы Яви v0.24: jumper — Прыгун (приседает и прыгает), archer — Стрелок (держит дистанцию, стреляет), thief — Воришка (крадёт до 4 штук материала и убегает, при смерти роняет). spawn <вид> [n]; status. Пример: mobs spawn archer; mobs spawn thief 2",
	"bossatk": "Новые атаки боссов v0.24: pillars — «Каменный вал» Матери (полоса 1 с, затем столбы); venom — «Ядовитый плевок» Анаконды (круги 0.8 с, лужи яда 3 с). Ставит атаку прямо на игрока для проверки. Пример: bossatk pillars; bossatk venom",
	"drops": "Выброшенные предметы v0.24: пропадают через 5 минут (последние 10 с мигают), трофеи боссов — нет. age <сек> — состарить все дропы; status. Пример: drops status; drops age 295",
	"camfx": "Камера v0.24: покачивание при ходьбе и тряска от ударов (выключаются в настройках). shake [0..1] — встряхнуть; status. Пример: camfx shake 0.8",
	"errlog": "Журнал ошибок v0.24: путь к файлу user://logs/errors.log и число ошибок с запуска. Пример: errlog",
	"explain": "Пояснения v0.24 при первом нажатии M (испытание) и J (просьба Сна). reset — показать снова; status. Пример: explain reset",
	"kit": "Набор v0.24 для проверки: металлическая кирка, металлический меч, металлический лук, стрелы, призывалка, зелья скорости, руда. Пример: kit",
}
const COMPLETIONS := ["difficulty", "difficulty status", "difficulty normal", "difficulty expert", "ore find", "ore here", "ore rules",
	"bow give wood", "bow give metal", "bow shoot ", "bow status", "arrows give ", "arrows best ", "arrows status",
	"burger summon", "burger now", "burger phase 2", "burger phase 3", "burger shards", "burger weak", "burger hp ", "burger kill", "burger leave", "burger status",
	"summoner give", "summoner tokens", "summoner roll mother", "summoner roll anaconda", "speedpotion give ", "speedpotion drink", "speedpotion status",
	"lizards spawn ", "lizards status", "kit", "weather clear", "weather rain", "weather fog", "weather status",
	"mobs spawn jumper", "mobs spawn archer", "mobs spawn thief", "mobs status", "bossatk pillars", "bossatk venom",
	"drops status", "drops age ", "camfx shake ", "camfx status", "errlog", "explain reset", "explain status"]
static var extra_help: Dictionary = {}
static var extra_completions: Array = []
static var handlers: Dictionary = {}   # имя → Callable(console, a) -> String (регистрируют следующие этапы)


static func help_for(cmd: String) -> String:
	return str(HELP.get(cmd, extra_help.get(cmd, "")))


static func completions() -> Array:
	return COMPLETIONS + extra_completions


static func handles(cmd: String) -> bool:
	return HELP.has(cmd) or handlers.has(cmd)


static func _boss(con: Node) -> Node:
	return con.get_tree().get_first_node_in_group("burger_boss")


static func _give(id: String, n: int) -> void:
	if Gear.durability(id) > 0:
		for i in range(n):
			GameState.add_item_count(id, 1)
	else:
		GameState.add_item_count(id, n)


static func run(con: Node, a: PackedStringArray) -> String:
	var sub := a[1] if a.size() > 1 else "status"
	var p: Node3D = con.get_tree().get_first_node_in_group("player")
	var b: Node = con.get_tree().get_first_node_in_group("build_controller")
	if handlers.has(a[0]):
		return str((handlers[a[0]] as Callable).call(con, a))
	match a[0]:
		"difficulty":
			if sub in ["normal", "expert"]:
				GameState.set_difficulty(sub)
			return "Сложность: %s · HP мобов ×%.2f · урон ×%.2f · скорость ×%.2f · обзор ×%.2f · поводок ×%.2f" % [GameState.difficulty_name(), GameState.diff_hp_mult(), float(GameState.diff_damage(100)) / 100.0, GameState.diff_speed(), GameState.diff_aggro(), GameState.diff_leash()]
		"ore":
			var cm: Node = null
			for c in con.get_tree().get_nodes_in_group("chunk_manager"):
				if not bool(c.get("is_dream_layer")) and not bool(c.get("panorama_mode")): cm = c
			if sub == "rules":
				var M := preload("res://scripts/mining_rules.gd")
				return "Руда: рука — нельзя · деревянная кирка — нельзя · каменная %.1f с · металлическая %.1f с · дроп только с каменной и лучше" % [M.seconds("metal_ore", "pickaxe2"), M.seconds("metal_ore", "pickaxe3")]
			if sub == "here":
				var aim: Dictionary = p.get_look_ray() if p else {}
				if not aim.get("hit", false): return "Ошибка: смотри на блок."
				var cell: Vector3i = Vector3i((aim.position + aim.normal * 0.5).floor())
				GameState.place_wake_block(cell, "metal_ore")
				for v in con.get_tree().get_nodes_in_group("voxel_world"):
					if not bool(v.get("is_dream_layer")): v.sync_cells([cell])
				return "Руда поставлена: %s" % str(cell)
			if cm == null or p == null: return "Ошибка: нет мира."
			var Ore := preload("res://scripts/ore_rules.gd")
			var c0 := Vector3i(p.global_position.floor())
			var best := Vector3i(0, 999, 0); var bd := 1e9
			for x in range(-24, 25):
				for z in range(-24, 25):
					for y in range(Ore.ORE_BOTTOM, Ore.ORE_TOP + 1):
						var c := Vector3i(c0.x + x, y, c0.z + z)
						if Ore.is_ore(c, int(cm.get("_seed"))):
							var d := float(x * x + z * z + (y - c0.y) * (y - c0.y))
							if d < bd: bd = d; best = c
			return "Ближайшая руда: %s (≈%.0f м)" % [str(best), sqrt(bd)] if best.y != 999 else "Руды в радиусе 24 нет."
		"bow":
			if sub == "give":
				var id := "bow2" if a.size() > 2 and a[2] == "metal" else "bow"
				_give(id, 1); _give("arrow", 32)
				return "Выдан %s и 32 стрелы." % DB.display_name(id)
			if sub == "shoot":
				var ch := clampf(float(a[2]) if a.size() > 2 else 1.0, 0.0, 1.0)
				var sel := str(GameState.get_selected_item().get("id", ""))
				if not Gear.is_bow(sel): return "Ошибка: возьми лук в руку."
				var arrow: Node3D = b.bow.fire(sel, ch) if b and b.bow else null
				return "Выстрел: натяжение %.2f · урон %d" % [ch, b.bow.last_damage] if arrow else "Ошибка: нет стрел или слабое натяжение."
			return "Лук: в руке %s · натяжение %.2f · выстрелов %d · стрел %d / %d" % [str(GameState.get_selected_item().get("id", "")), b.bow.charge if b else 0.0, b.bow.shots if b else 0, GameState.raw_count("arrow"), GameState.raw_count("arrow2")]
		"arrows":
			var n := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 32, 1, 999)
			if sub == "give": _give("arrow", n); return "Выдано стрел: %d" % n
			if sub == "best": _give("arrow2", n); return "Выдано стрел из детёнышей анаконды: %d" % n
			return "Стрелы: %d обычных, %d из детёнышей · выпущено %d, попаданий %d" % [GameState.raw_count("arrow"), GameState.raw_count("arrow2"), int(GameState.v024_stats.get("arrows_shot", 0)), int(GameState.v024_stats.get("arrows_hit", 0))]
		"burger":
			var boss := _boss(con)
			match sub:
				"summon":
					var s: Node = load("res://scripts/burger_summon.gd").start(b.get_parent(), 60.0)
					return "Призывалка запущена: 60 с." if s else "Ошибка."
				"now":
					var bs := load("res://scripts/burger_summon.gd")
					var pend: Node = bs.pending(con.get_tree())
					if pend == null: pend = bs.start(b.get_parent(), 0.0)
					var boss2: Node = pend.arrive()
					return "Бургер Смерти здесь." if boss2 else "Ошибка: другой босс уже в бою."
				"phase":
					if boss == null: return "Ошибка: босса нет."
					var ph := int(a[2]) if a.size() > 2 else 2
					if ph >= 2 and int(boss.phase) == 1:
						boss.hp = int(boss.max_hp * 0.66); boss._start_transition1(); boss._t = 3.0
					if ph >= 3:
						if int(boss.phase) == 1: boss._drop_anton()
						boss.hp = int(boss.max_hp * 0.33); boss._start_transition2(); boss._t = 2.5
					return "Фаза → %d" % ph
				"shards":
					if boss == null: return "Ошибка: босса нет."
					if int(boss.phase) == 1: boss._drop_anton()
					boss.phase = 3; boss.hp = 0; boss._start_shards()
					return "Осколки: %d, 12 с." % int(boss.shards_left)
				"weak":
					if boss == null or int(boss.phase) != 1: return "Ошибка: слабые точки есть только у тарелки."
					for wp in boss._weak:
						if is_instance_valid(wp) and int(wp.hp) > 0: wp.take_hit(999); return "Слабая точка сбита · осталось %d" % boss.weak_points_alive()
					return "Все слабые точки уже сбиты."
				"hp":
					if boss == null: return "Ошибка: босса нет."
					boss.hp = clampi(int(a[2]) if a.size() > 2 else boss.max_hp, 1, boss.max_hp)
					return "HP %d/%d" % [boss.hp, boss.max_hp]
				"kill":
					if boss == null: return "Ошибка: босса нет."
					boss._die(); return "Бургер Смерти повержен."
				"leave":
					if boss == null: return "Ошибка: босса нет."
					boss.leave("Бургер Смерти улетел."); return "Улетает."
			var pend2: Node = load("res://scripts/burger_summon.gd").pending(con.get_tree())
			if boss == null: return "Бургера нет · отсчёт: %s · побед %d" % [("%.0f с" % pend2.left) if pend2 else "нет", GameState.burger_kills]
			return "%s %d/%d · фаза %d · состояние %d · слабых точек %d · клоунов %d · атаки %s" % [boss.boss_title(), boss.hp, boss.max_hp, boss.phase, boss.state, boss.weak_points_alive(), boss._alive_clowns(), str(boss.attacks_used)]
		"summoner":
			if sub == "give": _give("burger_summoner", 1); return "Выдана призывалка бургера."
			if sub == "tokens": _give("stone_heart", 1); _give("scale_fang", 1); return "Выданы Каменное сердце и Чешуйчатый клык."
			if sub == "roll":
				var who := a[2] if a.size() > 2 else "mother"
				var got := 0
				for i in range(1000):
					if GameState.roll_boss_token(who) != "": got += 1
				return "%s: из 1000 побед трофей выпал %d раз (≈%.1f %%)" % [who, got, got / 10.0]
			return "Ошибка: summoner give|tokens|roll mother|anaconda"
		"speedpotion":
			if sub == "give": var n2 := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 1, 1, 99); _give("speed_potion", n2); return "Выдано зелий скорости: %d" % n2
			if sub == "drink":
				if GameState.raw_count("speed_potion") <= 0: _give("speed_potion", 1)
				return "Выпито: 60 с бега без стамины." if GameState.drink_speed_potion() else "Ошибка: во Сне не пьётся."
			return "Зелье скорости: осталось %.0f с · в инвентаре %d" % [GameState.speed_potion_t, GameState.raw_count("speed_potion")]
		"lizards":
			var L: GDScript = load("res://scripts/lizard_minion.gd")
			if sub == "spawn":
				var n3 := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 1, 1, 10)
				for i in range(n3): L.spawn(b._wake_world(), p.global_position + Vector3(3 + i, 0.5, 2))
				return "Ящерок: %d" % n3
			return "Ящерки: живых %d · убито %d · спавн в пещерах %s" % [con.get_tree().get_nodes_in_group("lizard_minion").size(), GameState.lizards_killed, "включён" if GameState.anaconda_defeated else "после победы над Анакондой"]
		"kit":
			for id in ["pickaxe3", "metal_sword", "bow2", "burger_summoner"]: _give(id, 1)
			_give("arrow", 64); _give("arrow2", 16); _give("speed_potion", 2); _give("metal_ore", 8); _give("metal_ingot", 6)
			return "Набор v0.24 выдан."
		"weather":
			var w: Node = con.get_tree().get_first_node_in_group("weather")
			if sub in ["clear", "rain", "fog"] and w:
				w.set_weather(sub, true)
				return "Погода: %s." % w.NAMES[sub]
			return "Погода: %s · до смены %d с · дождь %.2f · туман %.2f" % [str({"clear": "ясно", "rain": "дождь", "fog": "туман"}.get(GameState.weather, "?")), int(GameState.weather_left), GameState.weather_rain_k, GameState.weather_fog_k]
		"mobs":
			var WM: GDScript = load("res://scripts/wake_mob.gd")
			if sub == "spawn":
				var k := a[2] if a.size() > 2 else "jumper"
				if not k in WM.KINDS: return "Ошибка: вид jumper, archer или thief."
				var n4 := clampi(int(a[3]) if a.size() > 3 and a[3].is_valid_int() else 1, 1, 6)
				var fwd := -p.global_transform.basis.z
				for i in range(n4): WM.spawn(b._wake_world(), p.global_position + fwd * (6.0 + i * 1.5) + Vector3(0, 0.5, 0), k)
				return "Вызвано: %s ×%d" % [WM.NAMES[k], n4]
			var cnt := {}
			for m in con.get_tree().get_nodes_in_group("wake_mob"): cnt[m.kind] = int(cnt.get(m.kind, 0)) + 1
			return "Новые мобы рядом: прыгунов %d, стрелков %d, воришек %d" % [int(cnt.get("jumper", 0)), int(cnt.get("archer", 0)), int(cnt.get("thief", 0))]
		"bossatk":
			var BA: GDScript = load("res://scripts/boss_extra_attacks.gd")
			var gy := func(q: Vector3) -> float: return p.global_position.y
			if sub == "pillars":
				BA.pillars(b._wake_world(), p.global_position - (-p.global_transform.basis.z) * 8.0, p.global_position, gy)
				return "Каменный вал: полоса к тебе, столбы через 1 с — отойди вбок."
			if sub == "venom":
				var hd := Node3D.new(); b._wake_world().add_child(hd); hd.global_position = p.global_position + Vector3(0, 4, -8)
				BA.venom(b._wake_world(), hd, p.global_position, gy)
				con.get_tree().create_timer(3.0).timeout.connect(hd.queue_free)
				return "Ядовитый плевок: круги на земле, сгустки через 0.8 с."
			return "Ошибка: bossatk pillars или bossatk venom."
		"drops":
			if sub == "age" and a.size() > 2 and a[2].is_valid_float():
				for r in GameState.dropped_items: r["age"] = float(a[2])
				return "Возраст дропов: %s с (пропадут на 300 с)." % a[2]
			return "Дропов в мире: %d · пропадают через 300 с" % GameState.dropped_items.size()
		"camfx":
			if sub == "shake":
				GameState.shake(float(a[2]) if a.size() > 2 and a[2].is_valid_float() else 0.8)
				return "Тряска."
			var gs2 := con.get_node_or_null("/root/GameSettings")
			return "Покачивание: %s · тряска: %s · обзор %d°" % ["вкл" if gs2.head_bob else "выкл", "вкл" if gs2.camera_shake else "выкл", int(gs2.fov)]
		"errlog":
			var gs3 := con.get_node_or_null("/root/GameSettings")
			return "Журнал ошибок: %s · ошибок с запуска: %d" % [gs3.error_log_path(), int(gs3.error_logger.errors) if gs3.error_logger else 0]
		"explain":
			if sub == "reset":
				GameState.explained = {}
				return "Пояснения M и J покажутся снова."
			return "Показаны пояснения: %s" % (", ".join(GameState.explained.keys()) if not GameState.explained.is_empty() else "ещё нет")
	return "Ошибка: неизвестная команда v0.24."
