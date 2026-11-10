extends CanvasLayer
## DevSeed-only command console. All world/scene work is main-thread only.
const DB := preload("res://scripts/item_db.gd")
const Armor := preload("res://scripts/armor_rules.gd")
const Mining := preload("res://scripts/mining_rules.gd")
const MOB_IDS := ["seam","elite","ghost","enemy1","enemy2","enemy3","enemy4","mother","anaconda","minion"]
const HELP := """help · seed · give <item> [count] · armor give wood|scale
spawn <seam|elite|ghost|enemy1..4|mother|anaconda|minion> [count] (явь)
mob hp|damage|speed <value> [nearest|all|type] · kill all
mob tool <hand|pickaxe|pickaxe2> [nearest|all|type]
time day|night|<hour> · moon <0..10> · tp spawn · tp <x y z> · god · fly · heal · hp <value>
world wake|dream · cooldown reset · sword2 [on|off|toggle]
hardness <block> [hand|pickaxe|pickaxe2] · armor give wood|scale
setblock <block|air> [x y z] (без координат — блок под прицелом)
fill <block|air> x1 y1 z1 x2 y2 z2 · fill <block|air> <radius>
fill: не более 4096 клеток, радиус ≤7; заменяет блоки и хранилища.
↑/↓ история · Tab дополнение (повтор — следующий вариант) · ~ / Esc закрыть"""
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
	var all: Array[String] = ["help","seed","moon ","kill all","god","fly","heal","hp ","time day","time night","time ","tp spawn","tp ","world wake","world dream","cooldown reset","sword2 on","sword2 off","sword2 toggle","armor give wood","armor give scale","mob hp ","mob damage ","mob speed ","mob tool hand","mob tool pickaxe","mob tool pickaxe2"]
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
		"help": return HELP
		"seed": return "Сид: %d · явь %d · сон %d" % [GameState.world_seed,GameState.world_seed_wake,GameState.world_seed_dream]
		"give":
			if a.size()<2 or (not DB.ITEMS.has(a[1]) and not DB.is_special(a[1])): return "Ошибка: give <item> [count]; Tab — предметы."
			if a.size()>2 and not a[2].is_valid_int(): return "Ошибка: количество — целое число."
			var count := clampi(int(a[2]) if a.size()>2 else 1,1,10000)
			var added := GameState.add_item_count(a[1],count)
			GameState.inventory_changed.emit()
			return "Выдано %s: %d/%d (в DevSeed имеющиеся предметы бесконечны)." % [DB.display_name(a[1]),added,count]
		"armor":
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
			return "Яркость луны: %.3f (пиковая энергия; базовая v0.9 — 0.47, была 0.78)." % GameState.moon_energy
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
		"sword2":
			var mode := a[1] if a.size()>1 else "toggle"
			if mode not in ["on","off","toggle"]: return "Ошибка: sword2 on|off|toggle"
			GameState.set_sword2_flag(not GameState.sword2_crafted if mode=="toggle" else mode=="on")
			return "Флаг Меч2: %s · обычные ×3.75, Мать ×3 при включении." % GameState.sword2_crafted
		"hardness","mining":
			if a.size()<2: return "Ошибка: hardness <block> [hand|pickaxe|pickaxe2]"
			var tool := a[2] if a.size()>2 and a[2]!="hand" else ""
			return "%s: твёрдость %.2f · %s: %.3f с · дроп %s" % [a[1],Mining.hardness(a[1]),"рука" if tool=="" else tool,Mining.seconds(a[1],tool),Mining.drops(a[1],tool)]
		"setblock","fill": return _edit_blocks(a)
	return "Ошибка: неизвестная команда. help — список."
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
						if GameState.is_dream(): GameState.removed_dream_terrain[c] = terrain
						else: GameState.remove_terrain_cell_silent(c,terrain)
						changed[cm.world_to_chunk(Vector3(c))] = true
				if kind!="air" and GameState.can_place_shape(source,c,kind):
					source[c] = {"kind":kind,"mutant":false,"anchored":false}
					GameState.add_shape_parts(source,c,kind)
					count += 1
				elif kind=="air": count += 1
	if cm:
		cm._generation_epoch += 1
		for coord in changed: cm.rebuild_chunk(coord)
	var vox := _voxels()
	if vox: vox._rebuild_from_state()
	GameState.inventory_changed.emit()
	return "Изменено клеток: %d · %s · %s → %s" % [count,kind,lo,hi]
