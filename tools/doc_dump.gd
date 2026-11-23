extends SceneTree
## Документация «Всё про всё»: выгрузка данных игры в JSON (ничего не меняет).
func _init() -> void: call_deferred("_go")
func _consts(path: String) -> Dictionary:
	var s: GDScript = load(path)
	var out := {}
	var m := s.get_script_constant_map()
	for k in m:
		var v = m[k]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR]:
			out[k] = var_to_str(v) if typeof(v) in [TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR] else v
	return out
func _go() -> void:
	var G = root.get_node("GameState")
	var DB: GDScript = load("res://scripts/item_db.gd")
	var M: GDScript = load("res://scripts/mining_rules.gd")
	var d := {}
	d["items"] = DB.ITEMS; d["special"] = DB.SPECIAL
	var mining := {}
	for k in M.HARDNESS:
		mining[k] = {"hardness": M.HARDNESS[k], "hand": M.seconds(k, ""), "pickaxe": M.seconds(k, "pickaxe"), "pickaxe2": M.seconds(k, "pickaxe2"), "drop_hand": M.drops(k, ""), "drop_pick": M.drops(k, "pickaxe")}
	d["mining"] = mining
	d["recipes"] = G.recipe_defs()
	d["placeable"] = {}
	for id in DB.ITEMS: d["placeable"][id] = G.is_placeable_block(id)
	var scripts := {}
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd") and f != "smoke_test.gd":
			var c := _consts("res://scripts/" + f)
			if not c.is_empty(): scripts[f] = c
	d["consts"] = scripts
	var con = load("res://scripts/dev_console.gd")
	d["console_help"] = con.COMMAND_HELP
	var cn = con.new(); root.add_child(cn)
	await process_frame
	d["console_completions"] = cn.completion_candidates("")
	var gs = root.get_node("GameSettings")
	var binds := []
	for row in gs.BINDABLE: binds.append([row[0], row[1], gs.key_label(row[0])])
	d["binds"] = binds
	d["sections"] = gs.SECTIONS
	var f := FileAccess.open("/workspace/doc/data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	print("DUMP OK")
	quit()
