extends Node
## Диск-сейв v0.5: у каждого мира свой файл user://worlds/<папка>/save.json.
## Авто: после пробуждения, при выходе, раз в 2 минуты; F5 сохранить / F9 загрузить.

const WorldStore := preload("res://scripts/world_store.gd")
const AUTOSAVE_SEC := 120.0
var SAVE_PATH: String:
	get:
		return WorldStore.save_path(GameState.world_folder) if GameState.world_folder != "" else ""
var _autosave_t := 0.0
const SAVE_VERSION := 1

signal save_completed(ok: bool)
signal load_completed(ok: bool)

var _main: Node3D = null
var _player: CharacterBody3D = null
var _wake_voxels: Node3D = null
var _dream_voxels: Node3D = null
var _threat: Node = null


func setup(main: Node3D, player: CharacterBody3D, wake_vox: Node3D, dream_vox: Node3D, threat: Node = null) -> void:
	_main = main
	_player = player
	_wake_voxels = wake_vox
	_dream_voxels = dream_vox
	_threat = threat
	GameState.wake_resolved.connect(_on_wake_resolved)


func _on_wake_resolved(_t: int, _d: int, _m: int) -> void:
	save_game("auto-wake")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game("quit")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save_game("manual")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			load_game()
			get_viewport().set_input_as_handled()


func has_save() -> bool:
	return SAVE_PATH != "" and FileAccess.file_exists(SAVE_PATH)


func _process(delta: float) -> void:
	if GameState.world_folder == "":
		return
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_SEC:
		_autosave_t = 0.0
		save_game("auto")


func save_game(reason: String = "manual") -> bool:
	if SAVE_PATH == "":
		return false
	var data := GameState.to_save_dict()
	if _player:
		data["player_pos"] = [_player.global_position.x, _player.global_position.y, _player.global_position.z]
	if _threat and _threat.has_method("to_save_dict"):
		data["threat"] = _threat.to_save_dict()
	data["reason"] = reason
	var json := JSON.stringify(data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		GameState.set_hint("Сохранение не удалось (%s)." % reason)
		save_completed.emit(false)
		return false
	f.store_string(json)
	f.close()
	WorldStore.touch(GameState.world_folder)
	GameState.set_hint("Сохранено (%s). F9 — загрузка." % reason)
	save_completed.emit(true)
	print("SAVE OK reason=", reason, " path=", SAVE_PATH)
	return true


func load_game() -> bool:
	if not has_save():
		GameState.set_hint("Нет файла сохранения.")
		load_completed.emit(false)
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		load_completed.emit(false)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		GameState.set_hint("Сейв повреждён.")
		load_completed.emit(false)
		return false
	var data: Dictionary = parsed
	GameState.apply_save_dict(data)
	# Восстановить визуалы блоков
	if _wake_voxels and _wake_voxels.has_method("_rebuild_from_state"):
		_wake_voxels.call("_rebuild_from_state")
	if _dream_voxels and _dream_voxels.has_method("_rebuild_from_state"):
		_dream_voxels.call("_rebuild_from_state")
	# Позиция
	if _player and data.has("player_pos"):
		var pp: Array = data["player_pos"]
		if pp.size() >= 3:
			_player.global_position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
	# Мир видимость
	if _main and _main.has_method("apply_world_visibility"):
		_main.apply_world_visibility(GameState.is_dream())
	elif _main:
		var sw = _main.get_node_or_null("Systems/WorldSwitcher")
		if sw and sw.has_method("_apply_visibility"):
			sw.call("_apply_visibility", GameState.is_dream())
			if sw.has_method("_tint_dream"):
				sw.call("_tint_dream", GameState.is_dream())
	if _threat and _threat.has_method("apply_save_dict") and data.has("threat"):
		_threat.apply_save_dict(data["threat"])
	# Чанки к игроку
	if _player:
		for cm in get_tree().get_nodes_in_group("chunk_manager"):
			if cm.has_method("setup"):
				var seed_v := GameState.world_seed_wake if not bool(cm.get("is_dream_layer")) else GameState.world_seed_dream
				cm.setup(_player, seed_v)
	GameState.set_hint("Загружено. F5 — сохранить.")
	load_completed.emit(true)
	print("LOAD OK path=", SAVE_PATH)
	return true
