extends CanvasLayer
## DevSeed-only command console. All world/scene work is main-thread only.
const DB := preload("res://scripts/item_db.gd")
const Armor := preload("res://scripts/armor_rules.gd")
const Mining := preload("res://scripts/mining_rules.gd")
const MOB_IDS := ["seam","elite","ghost","enemy1","enemy2","enemy3","enemy4","mother","anaconda","minion"]
const COMMAND_HELP := {
"help":"Справка обо всех командах или одной. Пример: help armor",
"seed":"Сиды яви/сна и DevSeed. Пример: seed",
"give":"Выдать любой предмет/блок/реагент/якорь в текущий инвентарь. Пример: give heal2 10; give beacon 4",
"spawn":"Создать врагов в Яви (seam/elite/ghost/enemy1..4/mother/anaconda/minion). Пример: spawn enemy1 7",
"mob":"Изменить HP/урон/скорость/инструмент nearest|all|тип. Пример: mob hp 250 nearest; mob tool pickaxe all",
"kill":"Удалить врагов без награды. Пример: kill all",
"time":"Часы суток (0..24), day/night. Пример: time 18.5",
"moon":"Энергия луны 0..10, сохраняется. Пример: moon 0.56",
"tp":"К кровати/спавну или XYZ. Пример: tp spawn; tp 10 8 -5",
"god":"Переключить бессмертие. Пример: god",
"fly":"Переключить полёт. Пример: fly",
"heal":"Полное лечение и сброс кулдауна зелий. Пример: heal",
"hp":"Текущее HP игрока 1..100. Пример: hp 35",
"world":"Сменить мир штатным переходом. Пример: world dream; world wake",
"cooldown":"Сбросить кулдаун Матери блоков. Пример: cooldown reset",
"sword3":"Флаг чешуйчатого меча (HP врагов не меняет). Пример: sword3 on; sword3 off; sword3 toggle (sword2 — старый alias)",
"hardness":"Твёрдость/время добычи/дроп. Пример: hardness stone pickaxe; mining dirt hand",
"armor":"Комплект надеть/снять/починить/статистика. Пример: armor give scale; armor clear; armor repair; armor stats",
"sword":"Выдать меч wood|stone|scale. Пример: sword give scale",
"potion":"Выдать/выпить Хилку1/2; auto использует первый слот, cooldown reset. Пример: potion give 2 10; potion use 2; potion use auto; potion cooldown reset",
"transfer":"Атомарный перенос: plan — проверить, wake — пробудиться, cancel — вернуть резерв, abort — в Явь с сохранением черновика, risk — шанс/предел. Пример: transfer plan; transfer cancel; transfer wake; transfer abort; transfer risk",
"anchor":"Выдать/выбрать/применить якорь под прицелом, preview. Пример: anchor give wedge 5; anchor select nail; anchor place; anchor preview",
"beacon":"Выдать маяки. Пример: beacon give 3",
"reagents":"Добавить каждый тип реагента. Пример: reagents give 100",
"dust":"Установить осыпь. Пример: dust 500",
"sleep":"Войти в сон (dev, без требования кровати). Пример: sleep",
"bed":"Кровать под прицелом назначить спавном или показать текущий спавн. Пример: bed setspawn; bed spawn",
"chunks":"Статистика очереди/worker/локальных snapshots, радиус 1..8, ревизии. Пример: chunks stats; chunks radius 3; chunks revisions",
"water":"Статистика текучей воды/mesh и ручной шаг (только Явь). Пример: water stats; water step 10",
"pickup":"Локальный подбор: статистика бюджета или ручной проход. Пример: pickup stats; pickup collect",
"ai":"Кооперативный A*: статистика и общий бюджет 500..8000µs. Пример: ai stats; ai budget 2000",
"mapping":"Система координат сна: parallel (новые миры) или legacy_workshop (старый сон у нуля). Пример: mapping parallel",
"debug":"F3 overlay вкл/выкл. Пример: debug on; debug toggle",
"craft":"Штатный крафт с доступом ко всем станциям (ресурсы/разблокировки проверяются). Пример: craft sword3",
"setblock":"Один блок/air под прицелом либо XYZ. Пример: setblock door 10 5 10",
"fill":"Область или радиус вокруг игрока (≤4096 клеток, радиус ≤7). Пример: fill planks 10 5 10 19 5 19; fill air 2",
"door":"Открыть/повернуть под прицелом или XYZ. Пример: door toggle; door rotate 10 5 10",
"clarity":"Осознанность Сна (v0.16): показать, задать число или max. Пример: clarity; clarity 25; clarity max",
"imprint":"Отпечатки материалов (v0.16): список, выучить один или все. Пример: imprint list; imprint stone; imprint all",
"palette":"Материал палитры Сна (T): показать или выбрать. Пример: palette; palette stone",
"frame":"Рамка Сна (K): углы по XYZ, у игрока, показать или снять. Пример: frame 0 5 0 6 8 6; frame here 3; frame show; frame clear",
"dreamfill":"Залить/очистить рамку Сна (L / Shift+L). Пример: dreamfill; dreamfill stone; dreamfill clear",
"crack":"Трещины Сна (v0.18): список, добавить под прицелом/у игрока N штук, залатать, убрать. Пример: crack list; crack add 3; crack patch; crack clear",
"nightmare":"Ночь кошмаров у трещин сейчас (как на рассвете) и итог прошлой. Пример: nightmare now; nightmare last",
"garden":"Сады Сна (v0.18): список, открыть сад, сбросить. Пример: garden list; garden stone; garden light; garden reset",
"request":"Просьба Сна (J): показать, новая, выдать нужное в Явь, исполнить. Пример: request; request new; request fill; request offer",
"trial":"Испытание фантомами (M, v0.19) для текущей рамки: run, last — итог, grade — оценка без запуска. Пример: trial run; trial last; trial grade",
"tutorial":"Обучение во Сне (v0.20): статус, старт заново, пропуск, засчитать шаг. Пример: tutorial; tutorial start; tutorial skip; tutorial next; tutorial step frame",
"blueprint":"Архив Снов (B/N/P/O, v0.17): список, сохранить рамку, показать N, вставить под прицелом, повернуть, стереть все. Пример: blueprint list; blueprint save; blueprint show 1; blueprint paste; blueprint rotate; blueprint clear",
"undo":"Отмена/возврат правок Сна (Z/U), N раз. Пример: undo 5; undo redo 2",
"mirror":"Зеркало Сна (X): переключить ось у игрока или выключить. Пример: mirror; mirror off",
"dreamdecor":"Декор Сна v0.21: острова, флора на земле (кристаллы, кочки, пятна света), пылинки. status — счётчики; rebuild — пересобрать флору вокруг; island — телепорт на ближайший остров (острова закреплены в мире, на них можно встать, текстуры как у земли Сна); home — на точку старта лицом к острову старта (он всегда виден из начала игры); off/on — спрятать/показать весь декор (для сравнения и замера FPS). Пример: dreamdecor; dreamdecor rebuild; dreamdecor home; dreamdecor off",
"bosscam":"Камера боя v0.21: у боссов FOV шире (до +10°), вплотную Мать блоков полупрозрачная. on/off — включить/выключить, status — текущие FOV и прозрачность. Пример: bosscam; bosscam off; bosscam on",
"economy":"Экономика осыпи v0.22: цены крафта, осыпь за убийство, усталость фарма, шанс кражи воров. Пример: economy; economy steal 1000",
"fall":"Урон от падения v0.22: 3 блока бесплатно, дальше 5 HP за блок, в воду без урона. status, on/off, test N — сколько снимет падение с N блоков. Пример: fall; fall test 8; fall off",
"torch":"Опора факелов v0.22: факел держится на верхней грани или на стене, на факел и на потолок нельзя; без опоры падает предметом. status — факелы без опоры, drop — уронить их. Пример: torch; torch drop",
"frameclear":"Очистить рамку Сна целиком, любой размер, бесплатно; Z отменяет. Пример: frame here 10; frameclear",
"timeskip":"Время Яви во Сне v0.22: 1 с во Сне = N с в Яви, по умолчанию 4. Проспанная ночь не даёт +25 осознанности. status, x N — множитель 1–16, night — счётчики ночи. Пример: timeskip; timeskip x 8; timeskip night",
"dayspawn":"Дневной спавн v0.22: днём мобов на 75 % меньше — интервал ×4, призраки возрождаются ×4 дольше. Пример: dayspawn",
"knockback":"Откидывание мобов от удара v0.22: сила по оружию, боссов не откидывает; отдача руки. status, on/off. Пример: knockback; knockback off",
"aggro":"Агрессия Анаконды на факелы v0.22: больше 3 факелов рядом — она злится и ломает их; стана от света нет. Пример: aggro",
"arms":"Руки от первого лица v0.22, модель Kenney Blocky Characters CC0. status, play attack|break|place|use|jump|sleep|wake. Пример: arms; arms play attack",
"mouse":"Кнопки мыши v0.22.1: ЛКМ — нажать: поставить, удерживать: сломать, с мечом — удар; ПКМ — только использовать; переназначаются в настройках. Пример: mouse",
"stamina":"Стамина v0.22.1: в Яви бег 10 с, восстановление с нуля до полной 20 с, устал — бег снова с 25 %; полоска над HP. status, full, zero, inf on|off. Пример: stamina; stamina zero; stamina inf on",
"walltorch":"Настенные факелы v0.22.1: факел на боковой грани блока стоит наискосок, как в Minecraft; без опоры падает. status — сколько настенных; test — поставить блок и факел на него рядом с тобой. Пример: walltorch; walltorch test",
"chatlog":"Чат v0.22.1: в чате только сообщения боссов, призыв яйцом, зелья под подушкой и подсказки строительства во Сне. chatlog — последние скрытые сообщения, chatlog 30 — больше. Пример: chatlog; chatlog 30",
"stations":"Станции v0.22.1: верстак, кровать, станки, сундук, дверь, маяк, ловец идей копируются в Явь, оригинал остаётся во Сне. Первая копия оплачена предметом, поставленным во Сне, следующие стоят 1 такой предмет из инвентаря Яви. Пример: stations",
"camp":"Стартовый лагерь v0.22.1: стоит на земле, у спавна нет озёр. status — сколько блоков висит; lower — опустить висящие на 1. Пример: camp; camp lower",
"land":"Земля v0.22.1: холм, грунт и земля — один блок «Земля» (dirt), сверху трава, под блоком — земля. Светоблоки и светильник удалены, в сейвах стали факелами. status — алиасы; migrate — перевести мир ещё раз. Пример: land; land migrate",
"hudfocus":"Фокус HUD обучения v0.21: что сейчас скрыто (цели, якорная панель, колонка Гвоздь/Клин/Якорь3/Маяк, цена якоря). Пример: hudfocus",
}
var history: Array[String] = []
var history_index := 0
var _draft := ""
var _matches: Array[String] = []
var _match_index := 0
var _last_completion := ""
var _lines: Array[String] = []
var panel: PanelContainer
var entry: LineEdit
var output: RichTextLabel
func _ready() -> void:
	layer = 40
	add_to_group("dev_console")
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 18
	panel.offset_right = -18
	panel.offset_top = 18
	panel.offset_bottom = 380
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.038,0.055,0.94)
	style.border_color = Color(0.3,0.7,0.62,0.8)
	style.set_border_width_all(1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "КОНСОЛЬ РАЗРАБОТЧИКА  /  DevSeed 6767676767"
	title.add_theme_color_override("font_color",Color(0.54,0.94,0.78))
	title.add_theme_font_size_override("font_size",18)
	box.add_child(title)
	output = RichTextLabel.new()
	output.custom_minimum_size.y = 255
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.scroll_following = true
	output.add_theme_font_size_override("normal_font_size",15)
	box.add_child(output)
	entry = LineEdit.new()
	entry.placeholder_text = "help — команды   ·   ↑/↓ история   ·   Tab дополнение"
	entry.add_theme_font_size_override("font_size",17)
	entry.text_submitted.connect(_submit)
	box.add_child(entry)
	panel.hide()
	_print("Только DevSeed. Команды меняют текущий мир. Введите help.")
func allowed() -> bool:
	return GameState.dev_mode and GameState.world_seed==GameState.DEV_SEED
func open() -> bool:
	if not allowed() or GameState.ui_blocked(): return false
	GameState.console_open = true
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	entry.grab_focus()
	return true
func close() -> void:
	panel.hide()
	entry.release_focus()
	GameState.console_open = false
	if not GameState.ui_blocked(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _exit_tree() -> void:
	GameState.console_open = false
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode==KEY_QUOTELEFT or event.keycode==KEY_QUOTELEFT:
		if GameState.console_open: close()
		elif allowed(): open()
		else: return
		get_viewport().set_input_as_handled()
	elif GameState.console_open:
		match event.keycode:
			KEY_ESCAPE: close()
			KEY_UP: history_step(-1)
			KEY_DOWN: history_step(1)
			KEY_TAB: autocomplete()
			_: return
		get_viewport().set_input_as_handled()
func _process(_delta: float) -> void:
	if GameState.console_open and not allowed(): close()
func _print(text: String) -> void:
	_lines.append(text)
	if _lines.size()>100: _lines.pop_front()
	output.text = "\n".join(_lines)
func _submit(line: String) -> void:
	execute(line)
	entry.clear()
	if GameState.console_open: entry.grab_focus()
func history_step(direction: int) -> void:
	if history_index==history.size(): _draft = entry.text
	history_index = clampi(history_index+direction,0,history.size())
	entry.text = history[history_index] if history_index<history.size() else _draft
	entry.caret_column = entry.text.length()
func completion_candidates(prefix: String) -> Array[String]:
	var all: Array[String] = ["door toggle","door rotate","help","seed","moon ","kill all","god","fly","heal","hp ","time day","time night","time ","tp spawn","tp ","world wake","world dream","cooldown reset","sword2 on","sword2 off","sword2 toggle","armor give wood","armor give scale","mob hp ","mob damage ","mob speed ","mob tool hand","mob tool pickaxe","mob tool pickaxe2"]
	for command in ["sword3 on","sword3 off","sword3 toggle","sword give wood","sword give stone","sword give scale","armor stats","armor repair","armor clear","potion give 1","potion give 2","potion use auto","potion use 1","potion use 2","potion cooldown reset","anchor give nail","anchor give wedge","anchor give anchor3","anchor select nail","anchor select wedge","anchor select anchor3","anchor place","anchor preview","transfer plan","transfer wake","transfer cancel","transfer abort","transfer risk","beacon give ","reagents give ","dust ","sleep","bed spawn","bed setspawn","chunks stats","chunks radius ","debug on","debug off","debug toggle","craft sword3","chunks revisions","water stats","water step ","mapping parallel","mapping legacy_workshop","pickup stats","pickup collect","ai stats","ai budget "]: all.append(command)
	for cmd in COMMAND_HELP: all.append("help "+cmd)
	for id in MOB_IDS: all.append("spawn "+id)
	for id in DB.all_icon_ids():
		if id=="unknown": continue
		all.append("give "+id)
		if GameState.is_placeable_block(id) or id in ["torch","beacon"]:
			all.append("setblock "+id)
			all.append("fill "+id)
			all.append("hardness "+id)
	for command in ["clarity","clarity max","clarity ","imprint list","imprint all","imprint ","palette","palette ","frame show","frame clear","frame here ","frame ","dreamfill","dreamfill clear","dreamfill ","crack list","crack add ","crack patch","crack clear","nightmare now","nightmare last","garden list","garden stone","garden light","garden reset","request","request new","request fill","request offer","trial run","trial last","trial grade","tutorial","tutorial start","tutorial skip","tutorial next","tutorial step ","blueprint list","blueprint save","blueprint show ","blueprint paste","blueprint rotate","blueprint clear","undo ","undo redo ","mirror","mirror off","dreamdecor","dreamdecor status","dreamdecor rebuild","dreamdecor off","dreamdecor on","dreamdecor island","dreamdecor home","hudfocus","bosscam","bosscam on","bosscam off","bosscam status"]: all.append(command)
	for command in ["stamina","stamina full","stamina zero","stamina inf on","stamina inf off","walltorch","walltorch test","chatlog","chatlog 30","stations","camp","camp lower","land","land migrate"]: all.append(command)
	for command in ["economy","economy steal ","fall","fall status","fall on","fall off","fall test ","torch","torch status","torch drop","frameclear","timeskip","timeskip status","timeskip x ","timeskip night","dayspawn","knockback","knockback status","knockback on","knockback off","aggro","arms","arms status","arms play attack","arms play break","arms play place","arms play use","arms play jump","arms play sleep","arms play wake","mouse"]: all.append(command)
	all.append("setblock air")
	all.append("fill air")
	var found: Array[String] = []
	for command in all:
		if command.begins_with(prefix.to_lower()): found.append(command)
	return found
func autocomplete() -> void:
	if entry.text!=_last_completion or _matches.is_empty():
		_matches = completion_candidates(entry.text)
		_match_index = 0
	else: _match_index = (_match_index+1)%_matches.size()
	if _matches.is_empty(): return
	entry.text = _matches[_match_index]
	entry.caret_column = entry.text.length()
	_last_completion = entry.text
func execute(line: String) -> String:
	if not allowed(): return "Ошибка: консоль доступна только в DevSeed."
	line = line.strip_edges()
	if line=="": return ""
	history.append(line)
	if history.size()>100: history.pop_front()
	history_index = history.size()
	_print("> "+line)
	var result := _execute(line.to_lower().split(" ",false))
	_print(result)
	return result
func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
func _chunks() -> Node:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not cm.panorama_mode and cm.is_dream_layer==GameState.is_dream(): return cm
	return null
func _voxels() -> Node:
	for vox in get_tree().get_nodes_in_group("voxel_world"):
		if vox.is_dream_layer==GameState.is_dream(): return vox
	return null
func _mob_name(mob: Node) -> String:
	if mob.is_in_group("anaconda"): return "anaconda"
	if mob.is_in_group("block_mother"): return "mother"
	if mob.is_in_group("anaconda_minion"): return "minion"
	if mob.is_in_group("enemy_ghost"): return "enemy%d" % (int(mob.kind)+1)
	return "elite" if mob.is_in_group("seam_elite") else "seam"
func _mobs(which: String) -> Array[Node]:
	var found: Array[Node] = []
	for mob in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(mob) or mob.is_queued_for_deletion(): continue
		if which in ["all","nearest"] or _mob_name(mob)==which or (which=="ghost" and mob.is_in_group("enemy_ghost")):
			found.append(mob)
	if which=="nearest" and _player():
		found.sort_custom(func(a: Node,b: Node) -> bool: return a.global_position.distance_squared_to(_player().global_position)<b.global_position.distance_squared_to(_player().global_position))
		if found.size()>1: found.resize(1)
	return found
func _execute(a: PackedStringArray) -> String:
	var p := _player()
	match a[0]:
		"help":
			if a.size()>1: return COMMAND_HELP.get(a[1],"Ошибка: такой команды нет; help")
			var lines: Array[String]=[]
			for cmd in COMMAND_HELP: lines.append(cmd+" — "+COMMAND_HELP[cmd])
			return "\n".join(lines)+"\n↑/↓ история · Tab дополнение · ~ / Esc закрыть"
		"seed": return "Сид: %d · явь %d · сон %d" % [GameState.world_seed,GameState.world_seed_wake,GameState.world_seed_dream]
		"give":
			if a.size()<2 or (not DB.ITEMS.has(a[1]) and not DB.is_special(a[1])): return "Ошибка: give <item> [count]; Tab — предметы."
			if a.size()>2 and not a[2].is_valid_int(): return "Ошибка: количество — целое число."
			var count := clampi(int(a[2]) if a.size()>2 else 1,1,10000)
			var added := GameState.add_item_count(a[1],count)
			GameState.inventory_changed.emit()
			return "Выдано %s: %d/%d (в DevSeed имеющиеся предметы бесконечны)." % [DB.display_name(a[1]),added,count]
		"armor":
			if a.size()==2 and a[1] in ["stats","clear","repair"]: return _v010_command(a)
			if a.size()!=3 or a[1]!="give" or a[2] not in ["wood","scale"]: return "Ошибка: armor give wood|scale"
			for i in range(4):
				var id: String = a[2]+"_"+Armor.PARTS[i]
				GameState.armor[i] = {"id":id,"count":1,"durability":Armor.durability(id)}
			GameState.inventory_changed.emit()
			return "Выдан и надет комплект: %s, защита %d." % [a[2],GameState.armor_points()]
		"spawn": return _spawn(a)
		"mob":
			if a.size()<3 or a[1] not in ["hp","damage","speed","tool"]: return "Ошибка: mob hp|damage|speed <value> [nearest|all|type]"
			var which := a[3] if a.size()>3 else "nearest"
			var mobs := _mobs(which)
			if mobs.is_empty(): return "Ошибка: враги не найдены: "+which
			if a[1]=="tool":
				if a[2] not in ["hand","pickaxe","pickaxe2"]: return "Ошибка: hand|pickaxe|pickaxe2"
			else:
				if not a[2].is_valid_float() or float(a[2])<0 or float(a[2])>100000: return "Ошибка: значение 0..100000."
			for mob in mobs:
				match a[1]:
					"hp":
						if int(a[2])<1: return "Ошибка: hp минимум 1; для удаления kill all."
						mob.hp = int(a[2]); mob.max_hp = int(a[2])
						preload("res://scripts/enemy_visuals.gd").update_hp_bar(mob,mob.hp,mob.max_hp)
					"damage": mob.set_meta("damage_override",int(a[2]))
					"speed": mob.set_meta("speed_override",float(a[2]))
					"tool": mob.set_meta("mining_tool","" if a[2]=="hand" else a[2])
			return "Изменено %d: %s = %s (%s)." % [mobs.size(),a[1],a[2],which]
		"kill":
			if a.size()!=2 or a[1]!="all": return "Ошибка: kill all"
			var mobs := _mobs("all")
			for mob in mobs:
				if mob.has_method("leave"): mob.leave()
				else: mob.queue_free()
			return "Удалено врагов без наград: %d." % mobs.size()
		"time":
			if a.size()!=2: return "Ошибка: time day|night|<hour>"
			var hour := 12.0 if a[1]=="day" else (0.0 if a[1]=="night" else -1.0)
			if a[1].is_valid_float(): hour = fposmod(float(a[1]),24.0)
			if hour<0: return "Ошибка: time day|night|<hour>"
			GameState.day_time = fposmod(hour-6.0,24.0)*60.0
			for day in get_tree().get_nodes_in_group("day_cycle"): day.set_time(GameState.day_time)
			return "Время: %.2f ч." % hour
		"moon":
			if a.size()!=2 or not a[1].is_valid_float() or float(a[1])<0 or float(a[1])>10: return "Ошибка: moon <0..10>"
			GameState.moon_energy = float(a[1])
			for day in get_tree().get_nodes_in_group("day_cycle"):
				day.moon_energy = GameState.moon_energy
				day.apply_lighting()
			return "Яркость луны: %.3f (пиковая энергия; по умолчанию 0.56)." % GameState.moon_energy
		"tp":
			if not p: return "Ошибка: игрок не найден."
			var dest := GameState.spawn_point
			if a.size()==4:
				for i in range(1,4):
					if not a[i].is_valid_float() or absf(float(a[i]))>100000: return "Ошибка: координаты ±100000."
				dest = Vector3(float(a[1]),float(a[2]),float(a[3]))
			elif a.size()!=2 or a[1]!="spawn": return "Ошибка: tp spawn | tp x y z"
			p.global_position = dest; p.velocity = Vector3.ZERO
			var cm := _chunks()
			if cm: cm.ensure_chunk_loaded(cm.world_to_chunk(dest))
			return "Телепорт: %s" % dest
		"god":
			GameState.god_mode = not GameState.god_mode
			return "Бессмертие: "+str(GameState.god_mode)
		"fly":
			if not p: return "Ошибка: игрок не найден."
			p.flying = not p.flying
			GameState.dev_fly = p.flying
			p.velocity = Vector3.ZERO
			return "Полёт: "+str(p.flying)
		"heal":
			GameState.player_hp = GameState.PLAYER_MAX_HP; GameState.heal_cd = 0
			GameState.player_hp_changed.emit(GameState.player_hp,GameState.PLAYER_MAX_HP)
			return "HP восстановлено, кулдаун хилки сброшен."
		"hp":
			if a.size()!=2 or not a[1].is_valid_int(): return "Ошибка: hp <1..100>"
			GameState.player_hp = clampi(int(a[1]),1,GameState.PLAYER_MAX_HP)
			GameState.player_hp_changed.emit(GameState.player_hp,GameState.PLAYER_MAX_HP)
			return "HP: %d" % GameState.player_hp
		"world":
			if a.size()!=2 or a[1] not in ["wake","dream"]: return "Ошибка: world wake|dream"
			var switcher := get_tree().get_first_node_in_group("world_switcher")
			if not switcher: return "Ошибка: переключатель мира не найден."
			if (a[1]=="dream")!=GameState.is_dream():
				if a[1]=="dream": switcher.enter_dream()
				else: switcher.wake_up()
			return "Мир: "+a[1]
		"cooldown":
			if a.size()!=2 or a[1]!="reset": return "Ошибка: cooldown reset"
			GameState.mother_cooldown = 0; GameState.boss_next_mine = false
			return "Кулдаун Матери блоков сброшен."
		"sword3","sword2":
			var mode := a[1] if a.size()>1 else "toggle"
			if mode not in ["on","off","toggle"]: return "Ошибка: sword3 on|off|toggle"
			GameState.set_sword3_flag(not GameState.sword2_crafted if mode=="toggle" else mode=="on")
			return "Флаг чешуйчатого меча: %s (v0.11+: HP врагов от него не зависит, у Матери фиксированные 620)." % GameState.sword2_crafted
		"hardness","mining":
			if a.size()<2: return "Ошибка: hardness <block> [hand|pickaxe|pickaxe2]"
			var tool := a[2] if a.size()>2 and a[2]!="hand" else ""
			return "%s: твёрдость %.2f · %s: %.3f с · дроп %s" % [a[1],Mining.hardness(a[1]),"рука" if tool=="" else tool,Mining.seconds(a[1],tool),Mining.drops(a[1],tool)]
		"door": return _edit_door(a)
		"setblock","fill": return _edit_blocks(a)
	return _v010_command(a)
func _spawn(a: PackedStringArray) -> String:
	if a.size()<2 or a[1] not in MOB_IDS: return "Ошибка: spawn <mob> [count]; Tab — типы."
	if GameState.is_dream(): return "Ошибка: враги Яви; сначала world wake."
	var p := _player()
	if not p: return "Ошибка: игрок не найден."
	if a.size()>2 and not a[2].is_valid_int(): return "Ошибка: количество — целое."
	var count := clampi(int(a[2]) if a.size()>2 else 1,1,32)
	var host := get_tree().current_scene.get_node_or_null("WakeWorld")
	if not host: return "Ошибка: WakeWorld не найден."
	var created := 0
	for i in range(count):
		var angle := float(i)*TAU/maxi(1,count)
		var pos := p.global_position+Vector3(cos(angle)*5,0,sin(angle)*5)
		var cm := _chunks()
		if cm: pos.y = float(cm.walk_height_at(floori(pos.x),floori(pos.z)))+0.1
		var mob: Node3D
		match a[1]:
			"mother": mob = preload("res://scripts/block_mother.gd").spawn_near(host,Vector3i(pos))
			"anaconda": mob = preload("res://scripts/boss_anaconda.gd").spawn_at(host,pos,"console")
			"seam","elite","minion":
				mob = preload("res://scripts/seam_creature.gd").new()
				mob.elite = a[1]=="elite"
				mob.position = pos; host.add_child(mob)
				if a[1]=="minion": mob.add_to_group("anaconda_minion")
			_:
				mob = preload("res://scripts/enemy_ghost.gd").new()
				var k := 0 if a[1]=="ghost" else int(a[1].trim_prefix("enemy"))-1
				mob.configure(k,pos,pos+Vector3(10,0,10))
				mob.position = pos; host.add_child(mob)
		if mob: created += 1
	return "Создано %s: %d (каждый босс — один одновременно)." % [a[1],created]
func _edit_blocks(a: PackedStringArray) -> String:
	if a.size()<2: return "Ошибка: setblock <block> [x y z] | fill <block> <radius|x1 y1 z1 x2 y2 z2>"
	var kind := a[1]
	if not GameState.is_placeable_block(kind) and kind not in ["air","torch","beacon"]: return "Ошибка: неизвестный блок; Tab — список."
	var p := _player()
	if not p: return "Ошибка: игрок не найден."
	var start := Vector3i(floori(p.global_position.x),floori(p.global_position.y),floori(p.global_position.z))
	var finish := start
	if a[0]=="setblock" and a.size()==2:
		var aim: Dictionary = p.get_look_ray()
		var point: Vector3 = aim.position-aim.normal*0.02 if aim.get("hit",false) else p.global_position-p.global_transform.basis.z*3.0
		start = Vector3i(floori(point.x),floori(point.y),floori(point.z)); finish = start
	elif a[0]=="fill" and a.size()==3:
		if not a[2].is_valid_int() or int(a[2])<0 or int(a[2])>7: return "Ошибка: радиус 0..7."
		var radius := Vector3i.ONE*int(a[2]); finish = start+radius; start -= radius
	else:
		var needed := 5 if a[0]=="setblock" else 8
		if a.size()!=needed: return "Ошибка: неверное число координат."
		for i in range(2,needed):
			if not a[i].is_valid_int() or absi(int(a[i]))>100000: return "Ошибка: координаты — целые, ±100000."
		start = Vector3i(int(a[2]),int(a[3]),int(a[4])); finish = start
		if a[0]=="fill": finish = Vector3i(int(a[5]),int(a[6]),int(a[7]))
	var lo := Vector3i(mini(start.x,finish.x),mini(start.y,finish.y),mini(start.z,finish.z))
	var hi := Vector3i(maxi(start.x,finish.x),maxi(start.y,finish.y),maxi(start.z,finish.z))
	var size := hi-lo+Vector3i.ONE
	if size.x*size.y*size.z>4096 or lo.y < -31 or hi.y>128: return "Ошибка: максимум 4096 клеток, высота -31..128."
	var source: Dictionary = GameState.dream_blocks if GameState.is_dream() else GameState.wake_blocks
	var cm := _chunks()
	var changed := {}
	var count := 0
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1):
				var c := Vector3i(x,y,z)
				if source.has(c):
					var root := GameState.root_cell(source,c)
					GameState.world_storage.erase(GameState.cell_key(root))
					GameState.remove_shape(source,root)
				if cm:
					var terrain := str(cm.terrain_kind_at(c))
					if terrain!="":
						if GameState.is_dream():
							GameState.removed_dream_terrain[c] = terrain
							GameState.snapshot_note("removed_dream_terrain",c)
						else: GameState.remove_terrain_cell_silent(c,terrain)
						changed[cm.world_to_chunk(Vector3(c))] = true
				if kind!="air" and GameState.can_place_shape(source,c,kind):
					source[c] = {"kind":kind,"mutant":false,"anchored":false}
					GameState.add_shape_parts(source,c,kind)
					count += 1
				elif kind=="air": count += 1
	if cm:
		for coord in changed: cm.rebuild_chunk(coord)
	var vox := _voxels()
	if vox: vox._rebuild_from_state()
	GameState.inventory_changed.emit()
	return "Изменено клеток: %d · %s · %s → %s" % [count,kind,lo,hi]

func _edit_door(a: PackedStringArray) -> String:
	if a.size() not in [2,5] or a[1] not in ["toggle","rotate"]: return "Ошибка: door toggle|rotate [x y z]"
	var cell := Vector3i.ZERO
	if a.size()==5:
		for i in range(2,5):
			if not a[i].is_valid_int(): return "Ошибка: координаты — целые."
		cell = Vector3i(int(a[2]),int(a[3]),int(a[4]))
	else:
		var aim: Dictionary = _player().get_look_ray()
		var collider: Object = aim.get("collider")
		if not collider or not collider.has_meta("voxel_cell"): return "Ошибка: наведи прицел на дверь."
		cell = collider.get_meta("voxel_cell")
	var ok: bool = GameState.toggle_door(cell) if a[1]=="toggle" else GameState.rotate_door(cell)
	return "Дверь: "+a[1] if ok else "Ошибка: здесь нет двери."

func _v010_command(a: PackedStringArray) -> String:
	match a[0]:
		"debug","f3":
			var mode:=a[1] if a.size()>1 else "toggle"
			if mode not in ["on","off","toggle"]: return "Ошибка: debug on|off|toggle"
			var hud=get_tree().current_scene.get_node_or_null("HUD")
			return "F3: "+str(hud.set_debug(mode)) if hud else "Ошибка: HUD не найден."
		"sword":
			if a.size()!=3 or a[1]!="give" or a[2] not in ["wood","stone","scale"]: return "Ошибка: sword give wood|stone|scale"
			return _execute(PackedStringArray(["give",{"wood":"sword","stone":"sword2","scale":"sword3"}[a[2]],"1"]))
		"armor":
			if a[1]=="stats": return "Защита %d / 20 · %s" % [GameState.armor_points(),str(GameState.armor)]
			if a[1]=="repair":
				for slot in GameState.armor:
					if not slot.is_empty(): slot.durability=Armor.durability(slot.id)
			else:
				for i in range(4):
					var slot: Dictionary=GameState.armor[i]
					if slot.is_empty(): continue
					var index: int=-1
					for j in range(GameState.ITEM_SLOT_COUNT):
						if GameState.get_slot(j).get("id","")=="": index=j;break
					if index<0: return "Ошибка: инвентарь полон, оставшаяся броня не снята."
					GameState.set_slot(index,slot.duplicate(true));GameState.armor[i]={}
			GameState.inventory_changed.emit();return "Броня: "+a[1]
		"potion":
			if a.size()==3 and a[1]=="cooldown" and a[2]=="reset": GameState.heal_cd=0;return "Кулдаун зелий: 0"
			if a.size()>=3 and a[1]=="give" and a[2] in ["1","2"]: return _execute(PackedStringArray(["give","heal"+a[2],a[3] if a.size()>3 else "1"]))
			if a.size()==3 and a[1]=="use" and a[2] in ["1","2","auto"]: return "Зелье выпито: "+str(GameState.use_heal("" if a[2]=="auto" else "heal"+a[2]))
			return "Ошибка: potion give 1|2 [count] | potion use 1|2|auto | potion cooldown reset"
		"reagents":
			if a.size()!=3 or a[1]!="give" or not a[2].is_valid_int(): return "Ошибка: reagents give <count>"
			for i in range(1,4): GameState.add_typed_reagent(i,clampi(int(a[2]),0,100000))
			return "Добавлено каждого реагента: "+a[2]
		"dust":
			if a.size()!=2 or not a[1].is_valid_int(): return "Ошибка: dust <count>"
			GameState.pouch.dust=clampi(int(a[1]),0,10000000);GameState.inventory_changed.emit();return "Осыпь: %d (в DevSeed отображается ∞)"%int(GameState.pouch.dust)
		"anchor","beacon":
			if a.size()>=3 and a[1]=="give":
				var id:=a[2] if a[0]=="anchor" else "beacon"
				if not DB.is_special(id): return "Ошибка: nail|wedge|anchor3|beacon"
				var count:=a[3] if a.size()>3 else (a[2] if a[0]=="beacon" else "1")
				return _execute(PackedStringArray(["give",id,count]))
			if a.size()==3 and a[1]=="select" and a[2] in ["nail","wedge","anchor3"]:
				GameState.select_anchor(["nail","wedge","anchor3"].find(a[2]));return "Выбран якорь: "+a[2]
			var p:=_player()
			if not p: return "Ошибка: нет игрока."
			var aim: Dictionary=p.get_look_ray()
			if not aim.get("hit",false): return "Ошибка: наведитесь на блок."
			var cell:=GameState.ray_cell(aim)
			if a.size()==2 and a[1]=="place": return "Якорь: "+str(GameState.try_place_anchor(cell))
			if a.size()==2 and a[1]=="preview": return "План якоря: "+str(GameState.anchor_preview(cell))
			return "Ошибка: anchor give|select|place|preview; beacon give <count>"
		"transfer":
			if a.size()!=2: return "Ошибка: transfer plan|wake|cancel|abort|risk"
			match a[1]:
				"plan": return "План: "+str(GameState.transfer_plan())+" · preflight %.3fms / apply %.3fms"%[GameState.last_transfer_preflight_usec/1000.0,GameState.last_transfer_apply_usec/1000.0]
				"cancel": return "Возвращено: "+str(GameState.cancel_anchors())
				"risk": return "Мутация: бросок7% на блок; cap floor(3% всех объектов структуры); маяк куб±10, +5 осыпи за предотвращённый бросок."
				"wake","abort":
					var sw:=get_tree().get_first_node_in_group("world_switcher")
					if not GameState.is_dream() or not sw: return "Ошибка: сначала войдите в Сон."
					return "Перенос: "+str(sw.wake_up(a[1]=="abort"))
			return "Ошибка: transfer plan|wake|cancel|abort|risk"
		"sleep": return _execute(PackedStringArray(["world","dream"]))
		"bed":
			if a.size()==2 and a[1]=="spawn": return "Спавн: %s · кровать %s"%[GameState.spawn_point,GameState.active_bed]
			if a.size()==2 and a[1]=="setspawn" and _player():
				var aim: Dictionary=_player().get_look_ray();var cell:=GameState.root_cell(GameState.wake_blocks,GameState.ray_cell(aim))
				if GameState.wake_blocks.get(cell,{}).get("kind","")!="bed": return "Ошибка: наведитесь на поставленную кровать в Яви."
				GameState.active_bed=GameState.cell_key(cell);GameState.spawn_point=Vector3(cell)+Vector3(0.5,1,1);return "Спавн кровати: "+str(GameState.spawn_point)
			return "Ошибка: bed spawn|setspawn"
		"pickup":
			var player:=_player()
			if not player: return "Ошибка: нет игрока."
			if a.size()>1 and a[1]=="collect": player.auto_pickup()
			return "Подбор: %d за всё время · кандидатов %d · %.3f ms · максимум64/tick, soft budget1.5ms"%[player.auto_picked,player.pickup_last_candidates,player.pickup_last_usec/1000.0]
		"ai":
			var nav=load("res://scripts/enemy_navigation.gd")
			if a.size()==3 and a[1]=="budget" and a[2].is_valid_int(): nav.ai_budget_usec=clampi(int(a[2]),500,8000)
			return "AI: бюджет%dµs · кадр%dµs / max%dµs · путей%d · узловA*%d"%[nav.ai_budget_usec,nav.ai_frame_usec,nav.ai_max_frame_usec,nav.ai_paths_completed,nav.ai_search_nodes]
		"mapping":
			if a.size()!=2 or a[1] not in ["parallel","legacy_workshop"]: return "Ошибка: mapping parallel|legacy_workshop"
			GameState.dream_mapping=a[1];return "Координаты сна: "+a[1]
		"water":
			var cm:=_chunks()
			if GameState.is_dream() or not cm: return "Ошибка: вода симулируется только в Яви."
			if a.size()>1 and a[1]=="step":
				var count:=clampi(int(a[2]) if a.size()>2 else 1,1,200)
				for i in range(count): cm.water_step()
				cm._rebuild_water_meshes(2,1500)
			return "Вода: %d клеток · очередь %d · dirty %d · mesh rebuilds %d · %.3f ms"%[cm.water_cell_count(),cm._wq.size(),cm._water_dirty.size(),cm.water_mesh_builds,cm.water_mesh_last_usec/1000.0]
		"chunks":
			var cm:=_chunks()
			if not cm: return "Ошибка: менеджер чанков не найден."
			if a.size()==2 and a[1]=="revisions": return "Сессия %d · ревизии %s"%[cm._generation_epoch,cm._chunk_revisions]
			if a.size()==3 and a[1]=="radius" and a[2].is_valid_int():
				get_node("/root/GameSettings").set_value("render_distance",clampi(int(a[2]),1,8))
			return "Чанки: %d · очередь %d · worker готово %d · активных %d · вставка %.3f ms"%[cm.get_loaded_count(),cm.get_pending_count(),cm.worker_chunk_count,cm._jobs.size(),cm.last_insert_usec/1000.0]+" · snapshot %.3f ms/%d cells · stale %d · water meshes %d"%[cm.last_snapshot_usec/1000.0,cm.snapshot_cells_copied,cm.stale_jobs_discarded,cm.water_mesh_builds]
		"craft":
			if a.size()!=2: return "Ошибка: craft <recipe>"
			var recipe: Dictionary=GameState.find_recipe(a[1]);var where: String=recipe.get("where","")
			var ctx: Dictionary={"at_workbench":where=="workbench","at_lathe":where=="lathe"}
			if where in ["sawmill","sawmill_plus"]: ctx={"station":"sawmill","upgraded":true}
			if where=="alchemy": ctx={"station":"alchemy"}
			return "Крафт: "+str(GameState.craft_recipe(a[1],ctx))
		"clarity","imprint","palette","frame","dreamfill","crack","nightmare","garden","request","trial","tutorial","blueprint","undo","mirror","dreamdecor","hudfocus","bosscam":
			return _dream_cmd(a, _player())
		"economy","fall","torch","frameclear","timeskip","dayspawn","knockback","aggro","arms","mouse":
			return _v022_cmd(a, _player())
		"stamina","walltorch","chatlog","stations","camp","land":
			return _v0221_cmd(a, _player())
	return "Ошибка: неизвестная команда. help — список."


## v0.22.1: команды правок владельца.
func _v0221_cmd(a: PackedStringArray, p: Node3D) -> String:
	var G := GameState
	var sub := a[1] if a.size() > 1 else "status"
	var b := _build()
	match a[0]:
		"stamina":
			match sub:
				"full": G.stamina = 1.0; G.stamina_tired = false
				"zero": G.stamina = 0.0; G.stamina_tired = true
				"inf":
					if a.size() < 3 or not a[2] in ["on", "off"]: return "Ошибка: stamina inf on|off"
					G.stamina_infinite = a[2] == "on"
				"status": pass
				_: return "Ошибка: stamina [status|full|zero|inf on|off]"
			G.stamina_changed.emit(G.stamina, G.stamina_tired)
			return "Стамина %d%%%s%s · бег %d с, восстановление %d с" % [roundi(G.stamina * 100.0), " · устал" if G.stamina_tired else "", " · бесконечная" if G.stamina_infinite else "", int(G.STAMINA_RUN_SECONDS), int(G.STAMINA_RECOVER_SECONDS)]
		"walltorch":
			if sub == "test":
				if p == null or b == null or G.is_dream(): return "Ошибка: только в Яви."
				var base := Vector3i(floori(p.global_position.x) + 2, floori(p.global_position.y), floori(p.global_position.z))
				if G.wake_blocks.has(base) or G.wake_blocks.has(base + Vector3i(-1, 0, 0)): return "Ошибка: место занято."
				if not G.place_wake_block(base, "planks"): return "Ошибка: блок не встал."
				var tc := base + Vector3i(-1, 0, 0)
				if not G.place_wake_block(tc, "torch"): return "Ошибка: факел не встал."
				G.wake_blocks[tc]["attach"] = [base.x, base.y, base.z]
				var vox: Node = b._wake_voxels()
				if vox: vox.sync_cells([base, tc])
				return "Блок %s и настенный факел %s" % [base, tc]
			var n := 0; var total := 0
			for c in G.wake_blocks:
				if str(G.wake_blocks[c].get("kind", "")) == "torch":
					total += 1
					if preload("res://scripts/voxel_world.gd").wall_dir(c, G.wake_blocks[c]) != Vector3i.ZERO: n += 1
			return "Факелов: %d · на стенах: %d · наклон %d°" % [total, n, roundi(rad_to_deg(preload("res://scripts/voxel_world.gd").WALL_TORCH_TILT))]
		"chatlog":
			var k := int(sub) if sub.is_valid_int() else 10
			var tail := G.muted_chat.slice(maxi(0, G.muted_chat.size() - k))
			return "Скрыто сообщений: %d\n%s" % [G.muted_chat.size(), "\n".join(tail)]
		"stations":
			var paid := 0; var unpaid := 0
			for c in G.dream_blocks:
				var d: Dictionary = G.dream_blocks[c]
				if G.UNIQUE_KINDS.has(str(d.get("kind", ""))) and not d.has("root"):
					if d.get("paid", false): paid += 1
					else: unpaid += 1
			return "Станций во Сне: %d · первая копия оплачена: %d · копия за предмет Яви: %d" % [paid + unpaid, paid, unpaid]
		"camp":
			var floating := 0
			for c in G.wake_blocks:
				if G.wake_blocks[c].get("camp", false) and not G.wake_blocks.has(c + Vector3i.DOWN) and c.y > 0: floating += 1
			if sub == "lower":
				var m := G.lower_floating_camp()
				var vw: Node = b._wake_voxels() if b else null
				if vw: vw.sync_from_state()
				return "Опущено блоков лагеря: %d" % m
			return "Блоков лагеря: %d · висят: %d" % [G.wake_blocks.keys().filter(func(c): return G.wake_blocks[c].get("camp", false)).size(), floating]
		"land":
			if sub == "migrate":
				return "Переведено записей: %d" % G.migrate_v0221()
			return "Алиасы: %s · отпечатки: %s" % [str(G.KIND_ALIASES), ", ".join(G.imprints.keys())]
	return "Ошибка: " + a[0]


## v0.22: команды новых систем.
func _build() -> Node:
	return get_tree().current_scene.get_node_or_null("Systems/BuildController") if get_tree().current_scene else null


func _v022_cmd(a: PackedStringArray, p: Node3D) -> String:
	var G := GameState
	var sub := a[1] if a.size() > 1 else "status"
	var b := _build()
	match a[0]:
		"economy":
			if sub == "steal":
				var n := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 1000, 1, 100000)
				var hits := 0
				for i in range(n):
					if randf() < G.DUST_STEAL_CHANCE: hits += 1
				return "Бросков кражи: %d · удачных %d · %.1f %% · ожидаемо %.0f %%" % [n, hits, 100.0 * hits / n, G.DUST_STEAL_CHANCE * 100.0]
			return "Осыпь за моба %d–%d · усталость фарма −%.0f %% за убийство, не ниже ×%.1f · босс %d / Анаконда %d\nЦены: гвоздь %d · клин %d · якорь3 %d · маяк %d · кровать %d · хилка1 %d\nВоры крадут с шансом %.0f %% за удар" % [G.DUST_PER_KILL_MIN, G.DUST_PER_KILL_MAX, G.KILL_FATIGUE_STEP * 100.0, G.KILL_FATIGUE_MIN, G.DUST_PER_BOSS_KILL, G.DUST_PER_ANACONDA_KILL, G.NAIL_CRAFT_DUST, G.WEDGE_CRAFT_DUST, G.ANCHOR3_CRAFT_DUST, G.BEACON_CRAFT_DUST, G.BED_CRAFT_DUST, G.HEAL1_DUST, G.DUST_STEAL_CHANCE * 100.0]
		"fall":
			if sub == "on" or sub == "off":
				G.fall_damage_enabled = sub == "on"
			elif sub == "test":
				if a.size() < 3 or not a[2].is_valid_float(): return "Ошибка: fall test <блоков>"
				return "Падение с %s блоков: −%d HP из %d" % [a[2], G.fall_damage_for(float(a[2])), G.PLAYER_MAX_HP]
			elif sub != "status": return "Ошибка: fall [status|on|off|test N]"
			return "Урон от падения: %s · бесплатно %d блока, дальше %d HP за блок · последнее падение %.1f блока, −%d" % ["вкл" if G.fall_damage_enabled else "выкл", int(G.FALL_SAFE_BLOCKS), G.FALL_DMG_PER_BLOCK, G.last_fall_height, G.last_fall_damage]
		"torch":
			if b == null: return "Ошибка: нет мира."
			var loose: Array = []
			for c in G.wake_blocks:
				if str(G.wake_blocks[c].get("kind", "")) == "torch" and not b.torch_supported(c): loose.append(c)
			if sub == "drop":
				var n := 0
				for c in loose:
					if G.remove_torch(c):
						var vox: Node = b._wake_voxels()
						if vox: vox.remove_block(c)
						b._spawn_block_pickup(c, "torch"); n += 1
				return "Уронено факелов без опоры: %d" % n
			return "Факелов: %d · без опоры: %d%s" % [G.wake_kind_count("torch"), loose.size(), (" · " + str(loose.slice(0, 4))) if not loose.is_empty() else ""]
		"frameclear":
			var e := _need_dream(); if e != "": return e
			if not G.frame_complete(): return "Ошибка: сначала рамка, frame ... или K, K."
			return "Очищено клеток: %d · Z — отменить" % G.dream_clear()
		"timeskip":
			if sub == "x":
				if a.size() < 3 or not a[2].is_valid_float(): return "Ошибка: timeskip x <1–16>"
				G.dream_time_scale = clampf(float(a[2]), 1.0, 16.0)
			elif sub == "night":
				return "Эта ночь: в Яви %.0f с · проспано во Сне %.0f с · засчитается: %s · ночей пережито %d" % [G.night_awake, G.night_dreamt, "да" if G.night_counts() else "нет", G.nights_survived]
			elif sub != "status": return "Ошибка: timeskip [status|x N|night]"
			return "Во Сне время Яви ×%.1f · сейчас ×%.1f · последний сон промотал %.0f с · %s" % [G.dream_time_scale, G.wake_time_scale(), G.wake_time_skipped, G.clock_text(G.day_time)]
		"dayspawn":
			var td: GDScript = load("res://scripts/threat_director.gd")
			return "Интервал спавна при 0 с бодрствования: день %.0f с · ночь %.0f с · дневной множитель %.2f, это −%d %% · призраки днём ×%.0f дольше" % [td.spawn_interval(0.0, false), td.spawn_interval(0.0, true), td.DAY_SPAWN_RATE, roundi((1.0 - td.DAY_SPAWN_RATE) * 100.0), 1.0 / td.DAY_SPAWN_RATE]
		"knockback":
			if b == null: return "Ошибка: нет мира."
			if sub == "on" or sub == "off": b.knockback_enabled = sub == "on"
			elif sub != "status": return "Ошибка: knockback [status|on|off]"
			var vm: Node = b.viewmodel
			return "Откидывание: %s · сила %s · последнее %.1f м/с · отдач руки %d" % ["вкл" if b.knockback_enabled else "выкл", str(b.KNOCKBACK), b.last_knockback.length(), int(vm.recoil_count) if vm else 0]
		"aggro":
			var ana: Node = get_tree().get_first_node_in_group("anaconda")
			if ana == null: return "Анаконды нет. spawn anaconda — призвать. Злится, если рядом больше %d факелов." % 3
			ana.update_torch_aggro()
			return "Анаконда: факелов рядом %d · агрессия %s · сломано в ярости %d" % [ana.torches_near(ana._head.global_position, ana.TORCH_AGGRO_RADIUS).size(), "да" if ana.has_torch_aggro() else "нет", int(ana.torches_broken_aggro)]
		"arms":
			if b == null: return "Ошибка: нет мира."
			b._ensure_hand_tools()
			var arms: Node = b.viewmodel.arms if b.viewmodel else null
			if arms == null: return "Ошибка: руки не созданы."
			if sub == "play":
				var k := a[2] if a.size() > 2 else "attack"
				return "Анимация %s: %s" % [k, "ок" if arms.play_action(k) else "нет такой"]
			return "Руки: Kenney Blocky Characters, CC0 · клип %s · последнее действие %s · сыграно %s" % [arms.current_clip(), arms.last_action, str(arms.actions_played)]
		"mouse":
			var gs := get_node_or_null("/root/GameSettings")
			if gs == null: return "Ошибка: нет настроек."
			return "Поставить / сломать / удар: %s · Использовать: %s · порог удержания %.2f с · менять в Настройках → Управление" % [gs.key_label("attack_break"), gs.key_label("use_place"), preload("res://scripts/build_controller.gd").TAP_TIME]
	return "Ошибка: help " + a[0]


## v0.21: команды для систем Сна v0.16–v0.20 (осознанность, отпечатки, рамка, трещины, кошмары, сады,
## просьбы, испытание, обучение, Архив Снов, отмена, зеркало).
func _need_dream() -> String:
	return "" if GameState.is_dream() else "Ошибка: команда работает во Сне; сначала world dream."
func _aim_cell(p: Node3D) -> Vector3i:
	if p and p.has_method("get_look_ray"):
		var aim: Dictionary = p.get_look_ray()
		if aim.get("hit", false): return GameState.ray_cell(aim)
	return Vector3i(p.global_position.floor()) if p else Vector3i.ZERO
func _xyz(a: PackedStringArray, from: int) -> Variant:
	if a.size() < from + 3: return null
	for i in range(from, from + 3):
		if not a[i].is_valid_int(): return null
	return Vector3i(int(a[from]), int(a[from + 1]), int(a[from + 2]))
func _dream_cmd(a: PackedStringArray, p: Node3D) -> String:
	var G := GameState
	var sub := a[1] if a.size() > 1 else ""
	match a[0]:
		"clarity":
			if sub == "max": G.clarity = G.dream_clarity_max()
			elif sub.is_valid_float(): G.clarity = clampf(float(sub), 0.0, G.dream_clarity_max())
			elif sub != "": return "Ошибка: clarity [число|max]"
			G.clarity_changed.emit(G.clarity, G.dream_clarity_max())
			return "Осознанность: %.0f / %.0f" % [G.clarity, G.dream_clarity_max()]
		"imprint":
			if sub == "" or sub == "list":
				var have: Array = G.IMPRINT_KINDS.filter(func(k): return G.has_imprint(k))
				return "Отпечатки %d/%d: %s" % [have.size(), G.IMPRINT_KINDS.size(), ", ".join(have) if not have.is_empty() else "—"]
			if sub == "all":
				var n := 0
				for k in G.IMPRINT_KINDS: if G.learn_imprint(k, true): n += 1
				return "Выучено новых отпечатков: %d (все %d)" % [n, G.IMPRINT_KINDS.size()]
			if not G.IMPRINT_KINDS.has(sub): return "Ошибка: нет такого отпечатка. Есть: " + ", ".join(G.IMPRINT_KINDS)
			return "Отпечаток «%s»: %s" % [G.block_display_name(sub), "выучен" if G.learn_imprint(sub, true) else "уже был"]
		"palette":
			if sub == "": return "Палитра: %s · доступно: %s" % [G.dream_material, ", ".join(G.dream_palette())]
			if not G.dream_palette().has(sub): return "Ошибка: «%s» нет в палитре (сначала imprint %s)." % [sub, sub]
			G.dream_material = sub; G.clarity_changed.emit(G.clarity, G.dream_clarity_max())
			return "Материал палитры: " + G.block_display_name(sub)
		"frame":
			var e := _need_dream(); if e != "": return e
			if sub == "clear": G.frame_points = 0; return "Рамка снята."
			if sub == "show" or sub == "":
				return "Рамка: нет." if not G.frame_complete() else "Рамка %s (%d клеток) %s–%s" % [G.frame_dims_text(), G.frame_volume(), G.frame_box()[0], G.frame_box()[1]]
			if sub == "here":
				var r := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 2, 0, 20)
				var c := Vector3i(p.global_position.floor()) if p else Vector3i.ZERO
				G.frame_points = 0; G.frame_mark(c - Vector3i(r, 1, r)); G.frame_mark(c + Vector3i(r, r, r))
				return "Рамка %s у игрока." % G.frame_dims_text()
			var lo: Variant = _xyz(a, 1); var hi: Variant = _xyz(a, 4)
			if lo == null or hi == null: return "Ошибка: frame x1 y1 z1 x2 y2 z2 | here N | show | clear"
			G.frame_points = 0; G.frame_mark(lo); G.frame_mark(hi)
			return "Рамка %s (%d клеток)." % [G.frame_dims_text(), G.frame_volume()]
		"dreamfill":
			var e2 := _need_dream(); if e2 != "": return e2
			if not G.frame_complete(): return "Ошибка: сначала рамка (frame ... или K, K)."
			if sub == "clear": return "Очищено клеток: %d" % G.dream_clear()
			if sub != "" and not G.dream_palette().has(sub): return "Ошибка: «%s» нет в палитре." % sub
			return "Залито клеток: %d" % G.dream_fill(sub)
		"crack":
			if sub == "" or sub == "list":
				return "Трещин: %d/%d%s" % [G.dream_cracks.size(), G.CRACK_MAX, (" · " + ", ".join(G.dream_cracks.keys().slice(0, 8))) if not G.dream_cracks.is_empty() else ""]
			if sub == "clear": G.dream_cracks.clear(); G.cracks_changed.emit(); return "Трещины убраны (без награды)."
			if sub == "patch": return "Залатано трещин: %d" % G.patch_cracks()
			if sub == "add":
				var n := clampi(int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 1, 1, 64)
				var at := Vector3(p.global_position) if p else Vector3.ZERO
				var cells: Array = G.dream_blocks.keys().filter(func(c): return not G.dream_blocks[c].has("root"))
				cells.sort_custom(func(x, y): return Vector3(x).distance_squared_to(at) < Vector3(y).distance_squared_to(at))
				var added := 0
				for c in cells:
					if added >= n: break
					if G.add_crack(c, str(G.dream_blocks[c].get("kind", "drift"))): added += 1
				return "Добавлено трещин: %d (всего %d). Ближайшие блоки Сна к игроку." % [added, G.dream_cracks.size()] if added > 0 else "Ошибка: рядом нет блоков Сна для трещин."
			return "Ошибка: crack list|add N|patch|clear"
		"nightmare":
			if sub == "last": return "Прошлая ночь кошмаров: " + str(G.last_nightmare)
			var r2: Dictionary = G.nightmare_tick()
			return "Кошмары: сгрызено %d блоков дрейфа, защищено светом/маяком %d, трещин %d." % [int(r2.get("eaten", 0)), int(r2.get("guarded", 0)), int(r2.get("cracks", 0))]
		"garden":
			if sub == "" or sub == "list":
				var rows: Array = []
				for id in G.ZONES: rows.append("%s (%s)%s" % [id, G.ZONES[id].name, " — открыт" if G.dream_zones.has(id) else ""])
				return "Сады Сна: " + "; ".join(rows)
			if sub == "reset": G.dream_zones.clear(); G.world_changed.emit(G.is_dream()); return "Сады сброшены (отпечатки остаются)."
			var id2 := {"stone": "stone_garden", "light": "light_garden"}.get(sub, sub) as String
			if not G.ZONES.has(id2): return "Ошибка: garden stone|light|list|reset"
			var ok := G.unlock_zone(id2)
			G.world_changed.emit(G.is_dream())
			return ("Открыт " if ok else "Уже открыт ") + str(G.ZONES[id2].name)
		"request":
			G.ensure_request()
			if sub == "new": G.dream_request = {}; G.ensure_request()
			elif sub == "fill":
				G._give_items(G.inv_wake, [{"id": str(G.dream_request.kind), "name": G.block_display_name(str(G.dream_request.kind)), "count": int(G.dream_request.n)}]); G.notify_inventory()
			elif sub == "offer":
				var e3 := _need_dream(); if e3 != "": return e3
				return "Просьба исполнена (+осознанность, Архив больше)." if G.offer_request() else "Не исполнена: " + G.request_text()
			elif sub != "": return "Ошибка: request [new|fill|offer]"
			return G.request_text()
		"trial":
			if sub == "last": return "Последнее испытание: " + (str(G.last_trial) if not G.last_trial.is_empty() else "ещё не было")
			if sub == "grade": return "Оценка рамки: " + (G.trial_grade_for_frame() if G.trial_grade_for_frame() != "" else "не испытана")
			var e4 := _need_dream(); if e4 != "": return e4
			var t: Dictionary = G.run_trial()
			if t.is_empty(): return "Ошибка: нужна рамка (frame here 3 или K, K)."
			return "Испытание: %s · оценка %s · фантомов %s" % ["выдержала" if t.get("held", false) else "провал", str(t.get("grade", "?")), str(t.get("total", t.get("phantoms", "?")))]
		"tutorial":
			if sub == "start": G.start_tutorial(); return "Обучение начато: " + str(G.tutorial_current().get("title", ""))
			if sub == "skip": G.skip_tutorial(); return "Обучение пропущено."
			if sub == "next" or sub == "step":
				var id3: String = a[2] if sub == "step" and a.size() > 2 else G.tutorial_step_id()
				if id3 == "": return "Обучение не активно (tutorial start)."
				G.tutorial_event(id3)
			elif sub != "": return "Ошибка: tutorial [start|skip|next|step id]"
			if not G.tutorial_active: return "Обучение: не активно · пройдено %d/%d" % [G.tutorial_done.size(), G.TUTORIAL.size()]
			return "Обучение %d/%d — %s (id %s) · заранее сделано: %s" % [G.tutorial_index() + 1, G.TUTORIAL.size(), G.tutorial_current().title, G.tutorial_step_id(), ", ".join(G.tutorial_early.keys()) if not G.tutorial_early.is_empty() else "—"]
		"blueprint":
			if sub == "" or sub == "list":
				var names: Array = G.blueprints.map(func(b): return str(b.name))
				return "Архив Снов %d/%d: %s" % [G.blueprints.size(), G.blueprint_cap(), ", ".join(names) if not names.is_empty() else "пусто"]
			if sub == "clear": G.blueprints.clear(); G.blueprint_shown = -1; return "Архив Снов очищен."
			var e5 := _need_dream(); if e5 != "": return e5
			if sub == "save": return "Чертёж сохранён." if G.save_blueprint() else "Ошибка: чертёж не сохранён (нет постройки/архив полон)."
			if sub == "show":
				if a.size() > 2 and a[2].is_valid_int(): G.blueprint_shown = clampi(int(a[2]) - 1, -1, G.blueprints.size() - 1)
				else: G.cycle_blueprint()
				return "Показан чертёж: %d" % (G.blueprint_shown + 1)
			if sub == "rotate": return "Поворот: %d°" % (G.rotate_paste(1) * 90)
			if sub == "paste":
				if G.blueprint_shown < 0: return "Ошибка: сначала blueprint show N."
				return "Вставлено блоков: %d" % G.paste_blueprint(_aim_cell(p))
			return "Ошибка: blueprint list|save|show N|rotate|paste|clear"
		"undo":
			var e6 := _need_dream(); if e6 != "": return e6
			var redo := sub == "redo"
			var cnt_s: String = a[2] if redo and a.size() > 2 else sub
			var cnt := clampi(int(cnt_s) if cnt_s.is_valid_int() else 1, 1, 200)
			var done := 0
			for i in range(cnt):
				if (G.dream_redo() if redo else G.dream_undo()) <= 0: break
				done += 1
			return "%s: %d · осталось отмен %d, возвратов %d" % ["Возврат" if redo else "Отмена", done, G.undo_size(), G.redo_size()]
		"mirror":
			var e7 := _need_dream(); if e7 != "": return e7
			if sub == "off": G.mirror_axis = 0; return "Зеркало выключено."
			var ax := G.cycle_mirror(Vector3i(p.global_position.floor()) if p else Vector3i.ZERO)
			return ["Зеркало выключено.", "Зеркало по X", "Зеркало по Z"][ax]
		"dreamdecor":
			var sc := get_tree().get_first_node_in_group("dream_scenery")
			if sc == null: return "Ошибка: декора Сна нет в сцене."
			if sub == "off" or sub == "on":
				sc.visible = sub == "on"
				return "Декор Сна: %s." % ("показан" if sc.visible else "спрятан")
			if sub == "rebuild":
				var cam := get_viewport().get_camera_3d()
				var c := Vector3i(cam.global_position.floor()) if cam else Vector3i.ZERO
				var t0 := Time.get_ticks_usec()
				sc.rebuild_flora(Vector2i(c.x, c.z))
				return "Флора пересобрана за %.1f мс · кристаллов %d, кочек %d, пятен %d" % [(Time.get_ticks_usec() - t0) / 1000.0, sc.flora_counts[0], sc.flora_counts[1], sc.flora_counts[2]]
			elif sub == "island":
				var e9 := _need_dream(); if e9 != "": return e9
				if p == null: return "Ошибка: нет игрока."
				sc.update_islands(p.global_position)
				var best: Node3D = null
				for isl in sc.islands.get_children():
					if isl == sc.landmark: continue
					if best == null or isl.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position): best = isl
				if best == null: return "Островов рядом нет."
				# встаём на верх острова, а не в шпиль/дерево в центре: ищем свободную клетку лучом сверху
				var space := p.get_world_3d().direct_space_state
				var spot := best.global_position + Vector3(0.5, 1.2, 0.5)
				for off in [Vector3(2.5, 0, 0.5), Vector3(-1.5, 0, 0.5), Vector3(0.5, 0, 2.5), Vector3(0.5, 0, -1.5), Vector3(1.5, 0, 1.5)]:
					var q := PhysicsRayQueryParameters3D.create(best.global_position + off + Vector3(0, 3.0, 0), best.global_position + off + Vector3(0, -2.0, 0), 1)
					var hit := space.intersect_ray(q)
					if not hit.is_empty() and absf(float(hit.position.y) - (best.global_position.y + 1.0)) < 0.1:
						spot = hit.position + Vector3(0, 0.05, 0); break
				p.global_position = spot
				return "Телепорт на остров %s (%.0f, %.0f, %.0f)." % [best.name, best.global_position.x, best.global_position.y, best.global_position.z]
			elif sub == "home":
				var e10 := _need_dream(); if e10 != "": return e10
				if p == null: return "Ошибка: нет игрока."
				p.global_position = Vector3(0.5, 1.05, 0.5)
				if "velocity" in p: p.velocity = Vector3.ZERO
				p.rotation.y = 0.0
				var hc := p.get_node_or_null("Head")
				if hc: hc.rotation.x = 0.0
				sc.update_islands(p.global_position)
				var si = sc._sectors.get(sc.SPAWN_SECTOR)
				return "На точке старта, лицом на север (−Z). Остров старта: %s." % (("%s (%.0f, %.0f, %.0f)" % [si.name, si.position.x, si.position.y, si.position.z]) if si else "нет")
			elif sub != "" and sub != "status": return "Ошибка: dreamdecor [status|rebuild|island|home|off|on]"
			return "Декор Сна: %s · островов %d (кубов %d, в очереди %d) · флора: кристаллов %d, кочек %d, пятен %d · пылинок %d" % ["виден" if sc.visible else "спрятан", sc.island_count, sc.cube_count, sc._pending.size(), sc.flora_counts[0], sc.flora_counts[1], sc.flora_counts[2], sc.motes.amount]
		"bosscam":
			var bc := get_tree().get_first_node_in_group("boss_camera")
			if bc == null: return "Ошибка: камеры боя нет в сцене."
			if sub == "on" or sub == "off": bc.enabled = sub == "on"
			elif sub != "" and sub != "status": return "Ошибка: bosscam [on|off|status]"
			return bc.status_text()
		"hudfocus":
			var hud := get_tree().get_first_node_in_group("hud")
			var hide_tools: bool = hud.tutorial_hides_wake_tools() if hud and hud.has_method("tutorial_hides_wake_tools") else false
			return "Обучение: %s (шаг «%s») · цели и подсказки Сна скрыты: %s · колонка якорей и цена скрыты: %s" % ["идёт" if G.tutorial_active else "нет", G.tutorial_step_id(), "да" if G.tutorial_focus() else "нет", "да" if hide_tools else "нет"]
	return "Ошибка: неизвестная команда Сна."
