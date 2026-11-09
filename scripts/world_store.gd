extends RefCounted
## v0.5: список миров в user://worlds/<папка>/ (world.json — описание, save.json — сейв).

const ROOT := "user://worlds"
const META := "world.json"
const SAVE := "save.json"
const LEGACY_FILE := "sonnaya_save.json"


static func ensure_root() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


static func world_dir(folder: String) -> String:
	return "%s/%s" % [ROOT, folder]


static func save_path(folder: String) -> String:
	return "%s/%s" % [world_dir(folder), SAVE]


static func list_worlds() -> Array:
	ensure_root()
	import_legacy_save()
	var out: Array = []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for folder in d.get_directories():
		var meta := read_meta(folder)
		if meta.is_empty():
			continue
		out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


static func read_meta(folder: String) -> Dictionary:
	var p := "%s/%s" % [world_dir(folder), META]
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var m: Dictionary = parsed
	m["folder"] = folder
	m["seed"] = str(m.get("seed", "0"))
	return m


static func write_meta(folder: String, meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(world_dir(folder))
	var m := meta.duplicate()
	m["folder"] = folder
	m["seed"] = str(m.get("seed", "0"))
	var f := FileAccess.open("%s/%s" % [world_dir(folder), META], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m, "\t"))


static func sanitize(wname: String) -> String:
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_-абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
	var out := ""
	for ch in wname.strip_edges().to_lower():
		if ch == " ":
			out += "_"
		elif allowed.contains(ch):
			out += ch
	if out == "":
		out = "mir"
	return out.substr(0, 40)


static func unique_folder(wname: String) -> String:
	ensure_root()
	var base := sanitize(wname)
	var folder := base
	var n := 2
	while DirAccess.dir_exists_absolute(world_dir(folder)):
		folder = "%s_%d" % [base, n]
		n += 1
	return folder


static func create_world(wname: String, stext: String, seed_value: int, peaceful: bool) -> Dictionary:
	var nm := wname.strip_edges()
	if nm == "":
		nm = "Новый мир"
	var folder := unique_folder(nm)
	var now := Time.get_unix_time_from_system()
	var meta := {
		"name": nm,
		"seed_text": stext,
		"seed": str(seed_value),
		"dev": seed_value == 6767676767,
		"peaceful": peaceful,
		"created": now,
		"last_played": now,
		"version": "0.5",
	}
	write_meta(folder, meta)
	meta["folder"] = folder
	return meta


static func touch(folder: String) -> void:
	var m := read_meta(folder)
	if m.is_empty():
		return
	m["last_played"] = Time.get_unix_time_from_system()
	write_meta(folder, m)


static func delete_world(folder: String) -> bool:
	if folder == "" or folder.contains("..") or folder.contains("/"):
		return false
	var dir_path := world_dir(folder)
	var d := DirAccess.open(dir_path)
	if d == null:
		return false
	for f in d.get_files():
		d.remove(f)
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path)) == OK


static func meta_seed(meta: Dictionary) -> int:
	var s := str(meta.get("seed", "0"))
	return s.to_int() if s.is_valid_int() else 0


static func import_legacy_save() -> void:
	## Сейв v0.4.x (user://sonnaya_save.json в папке «Сонная стройка v0.4.x») → мир «Старый мир».
	var marker := "%s/.legacy_checked" % ROOT
	if FileAccess.file_exists(marker):
		return
	var found := ""
	var candidates: Array[String] = ["user://%s" % LEGACY_FILE]
	var data_dir := OS.get_data_dir()
	for vendor in ["godot", "Godot"]:
		for v in ["v0.4.5", "v0.4.4", "v0.4.3", "v0.4.2", "v0.4.1", "v0.4"]:
			candidates.append("%s/%s/app_userdata/Сонная стройка %s/%s" % [data_dir, vendor, v, LEGACY_FILE])
	for c in candidates:
		if FileAccess.file_exists(c):
			found = c
			break
	var mf := FileAccess.open(marker, FileAccess.WRITE)
	if mf:
		mf.store_string("1")
	if found == "":
		return
	var src := FileAccess.open(found, FileAccess.READ)
	if src == null:
		return
	var text := src.get_as_text()
	var meta := create_world("Старый мир", "1337", 1337, false)
	var dst := FileAccess.open(save_path(str(meta["folder"])), FileAccess.WRITE)
	if dst:
		dst.store_string(text)
