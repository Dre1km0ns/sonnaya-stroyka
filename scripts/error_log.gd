extends Logger
## v0.24: журнал ошибок игры. Каждая ошибка и предупреждение движка/скриптов пишется в user://logs/errors.log
## (старый файл переименовывается в errors.prev.log при запуске). Путь показан в настройках и меню паузы.
const PATH := "user://logs/errors.log"
const MAX_LINES := 4000
var _mutex := Mutex.new()
var _file: FileAccess
var lines := 0
var errors := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	if FileAccess.file_exists(PATH):
		DirAccess.rename_absolute(PATH, "user://logs/errors.prev.log")
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file:
		_file.store_line("Сонная стройка — журнал ошибок, запуск %s" % Time.get_datetime_string_from_system(false, true))
		_file.flush()


static func global_path() -> String:
	return ProjectSettings.globalize_path(PATH)


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if _file == null or lines >= MAX_LINES:
		return
	var kind: String = ["ОШИБКА", "ПРЕДУПРЕЖДЕНИЕ", "СКРИПТ", "ШЕЙДЕР"][clampi(error_type, 0, 3)]
	_mutex.lock()
	errors += 1
	lines += 1
	_file.store_line("[%s] %s: %s %s (%s:%d %s)" % [Time.get_time_string_from_system(), kind, code, rationale, file, line, function])
	for bt in script_backtraces:
		if bt != null and bt.get_frame_count() > 0:
			_file.store_line("    " + bt.format().replace("\n", "\n    "))
			lines += bt.get_frame_count()
	_file.flush()
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
