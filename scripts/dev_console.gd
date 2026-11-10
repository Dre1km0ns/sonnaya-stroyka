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
"sword3":"Тест усиления HP: обычные ×3.75 / Мать ×3 (Анаконда без изменений). Пример: sword3 on; sword3 off; sword3 toggle (sword2 — старый alias)",
"hardness":"Твёрдость/время добычи/дроп. Пример: hardness stone pickaxe; mining dirt hand",
"armor":"Комплект надеть/снять/починить/статистика. Пример: armor give scale; armor clear; armor repair; armor stats",
"sword":"Выдать меч wood|stone|scale. Пример: sword give scale",
"potion":"Выдать/выпить Хилку1/2; auto использует первый слот, cooldown reset. Пример: potion give 2 10; potion use 2; potion use auto; potion cooldown reset",
"anchor":"Выдать/выбрать/применить якорь под прицелом, preview. Пример: anchor give wedge 5; anchor select nail; anchor place; anchor preview",
"beacon":"Выдать маяки. Пример: beacon give 3",
"reagents":"Добавить каждый тип реагента. Пример: reagents give 100",
"dust":"Установить осыпь. Пример: dust 500",
"sleep":"Войти в сон (dev, без требования кровати). Пример: sleep",
"bed":"Кровать под прицелом назначить спавном или показать текущий спавн. Пример: bed setspawn; bed spawn",
"chunks":"Статистика очереди/worker/локальных snapshots, радиус 1..8, ревизии. Пример: chunks stats; chunks radius 3; chunks revisions",
"water":"Статистика текучей воды/mesh и ручной шаг (только Явь). Пример: water stats; water step 10",
"mapping":"Система координат сна: parallel (новые миры) или legacy_workshop (старый сон у нуля). Пример: mapping parallel",
"debug":"F3 overlay вкл/выкл. Пример: debug on; debug toggle",
"craft":"Штатный крафт с доступом ко всем станциям (ресурсы/разблокировки проверяются). Пример: craft sword3",
"setblock":"Один блок/air под прицелом либо XYZ. Пример: setblock door 10 5 10",
"fill":"Область или радиус вокруг игрока (≤4096 клеток, радиус ≤7). Пример: fill planks 10 5 10 19 5 19; fill air 2",
"door":"Открыть/повернуть под прицелом или XYZ. Пример: door toggle; door rotate 10 5 10",
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
	entry.grab_focus()
func history_step(direction: int) -> void:
	if history_index==history.size(): _draft = entry.text
	history_index = clampi(history_index+direction,0,history.size())
	entry.text = history[history_index] if history_index<history.size() else _draft
	entry.caret_column = entry.text.length()
func completion_candidates(prefix: String) -> Array[String]:
	var all: Array[String] = ["door toggle","door rotate","help","seed","moon ","kill all","god","fly","heal","hp ","time day","time night","time ","tp spawn","tp ","world wake","world dream","cooldown reset","sword2 on","sword2 off","sword2 toggle","armor give wood","armor give scale","mob hp ","mob damage ","mob speed ","mob tool hand","mob tool pickaxe","mob tool pickaxe2"]
	for command in ["sword3 on","sword3 off","sword3 toggle","sword give wood","sword give stone","sword give scale","armor stats","armor repair","armor clear","potion give 1","potion give 2","potion use auto","potion use 1","potion use 2","potion cooldown reset","anchor give nail","anchor give wedge","anchor give anchor3","anchor select nail","anchor select wedge","anchor select anchor3","anchor place","anchor preview","beacon give ","reagents give ","dust ","sleep","bed spawn","bed setspawn","chunks stats","chunks radius ","debug on","debug off","debug toggle","craft sword3","chunks revisions","water stats","water step ","mapping parallel","mapping legacy_workshop"]: all.append(command)
	for cmd in COMMAND_HELP: all.append("help "+cmd)
	for id in MOB_IDS: all.append("spawn "+id)
	for id in DB.all_icon_ids():
		if id=="unknown": continue
		all.append("give "+id)
		if GameState.is_placeable_block(id) or id in ["torch","beacon"]:
			all.append("setblock "+id)
			all.append("fill "+id)
			all.append("hardness "+id)
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
			return "Флаг чешуйчатого меча: %s · обычные ×3.75, Мать ×3 при включении." % GameState.sword2_crafted
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
			if a.size()==2 and a[1]=="preview": return "Якорь %s · клетка %s · %s" % [GameState.selected_anchor,cell,GameState.last_hint]
			return "Ошибка: anchor give|select|place|preview; beacon give <count>"
		"sleep": return _execute(PackedStringArray(["world","dream"]))
		"bed":
			if a.size()==2 and a[1]=="spawn": return "Спавн: %s · кровать %s"%[GameState.spawn_point,GameState.active_bed]
			if a.size()==2 and a[1]=="setspawn" and _player():
				var aim: Dictionary=_player().get_look_ray();var cell:=GameState.root_cell(GameState.wake_blocks,GameState.ray_cell(aim))
				if GameState.wake_blocks.get(cell,{}).get("kind","")!="bed": return "Ошибка: наведитесь на поставленную кровать в Яви."
				GameState.active_bed=GameState.cell_key(cell);GameState.spawn_point=Vector3(cell)+Vector3(0.5,1,1);return "Спавн кровати: "+str(GameState.spawn_point)
			return "Ошибка: bed spawn|setspawn"
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
	return "Ошибка: неизвестная команда. help — список."
