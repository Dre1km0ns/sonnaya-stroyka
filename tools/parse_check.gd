extends SceneTree
## Проверка компиляции всех скриптов: godot --headless -s res://tools/parse_check.gd
func _init():
	call_deferred("_run")
func _run():
	var bad := 0
	for d in ["res://scripts", "res://tools"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and f != "parse_check.gd":
				var s = load(d + "/" + f)
				if s == null:
					bad += 1
					print("FAIL ", f)
	print("PARSE DONE bad=", bad)
	quit()
