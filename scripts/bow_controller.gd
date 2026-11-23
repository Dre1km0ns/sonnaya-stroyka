extends Node
## v0.24: лук. ЛКМ удерживать — натяжение (рука с луком отходит назад), отпустить — выстрел.
## Стрелы тратятся из инвентаря, сначала лучшие (Gear.ARROWS). Сила и урон растут с натяжением.
const Gear := preload("res://scripts/gear.gd")
const MIN_CHARGE := 0.15
const ARROW_SCRIPT := preload("res://scripts/arrow.gd")
var build: Node
var charge := 0.0
var drawing := false
var shots := 0
var last_arrow: Node3D = null
var last_damage := 0
var _no_arrow_t := 0.0


func tick(delta: float, sel: String) -> bool:
	_no_arrow_t = maxf(0.0, _no_arrow_t - delta)
	if not Gear.is_bow(sel):
		if drawing: _release_visual()
		drawing = false
		charge = 0.0
		return false
	var cfg: Dictionary = Gear.BOWS[sel]
	if Input.is_action_pressed("attack_break"):
		if not drawing:
			if arrow_kind() == "":
				if _no_arrow_t <= 0.0:
					GameState.set_hint("Нет стрел: скрафти их на верстаке.", false)
					_no_arrow_t = 1.5
				return true
			drawing = true
			charge = 0.0
			Sfx.play("bow_draw", build.get_tree().root if build else null)
		charge = minf(1.0, charge + delta / float(cfg.draw))
		_pull_visual()
	elif drawing:
		fire(sel, charge)
	return true


func arrow_kind() -> String:
	for a in Gear.ARROWS:
		if GameState.count_item(a) > 0 or (GameState.dev_mode and GameState.raw_count(a) > 0):
			return a
	return ""


func fire(sel: String, ch: float) -> Node3D:
	drawing = false
	_release_visual()
	if ch < MIN_CHARGE:
		charge = 0.0
		return null
	var kind := arrow_kind()
	if kind == "" or not GameState.consume_item(kind, 1):
		charge = 0.0
		return null
	var cfg: Dictionary = Gear.BOWS.get(sel, Gear.BOWS["bow"])
	var player: Node3D = build.player if build else null
	if player == null:
		return null
	var cam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var fwd := -player.global_transform.basis.z
	var origin := player.global_position + Vector3(0, 1.5, 0)
	if cam:
		fwd = -cam.global_transform.basis.z
		origin = cam.global_position
	var dmg := int(round(float(Gear.ARROW_DAMAGE[kind]) * float(cfg.mult) * (0.3 + 0.7 * ch)))
	dmg = GameState.player_damage_mult(dmg)
	last_damage = dmg
	var a := spawn_arrow(origin + fwd * 0.6, fwd * float(cfg.speed) * (0.35 + 0.65 * ch), dmg, kind, player)
	shots += 1
	charge = 0.0
	GameState.wear_tool(1)
	GameState.stat_add("arrows_shot")
	Sfx.play("bow_shot", build.get_tree().root if build else null)
	var vm: Node = build.viewmodel if build else null
	if vm and vm.has_method("_do_recoil"):
		vm._do_recoil(true)   # короткий толчок руки, без клипа «use» (он уводит руку из кадра)
	return a


func spawn_arrow(pos: Vector3, vel: Vector3, dmg: int, kind: String, shooter: Node3D) -> Node3D:
	var host: Node = build._wake_world() if build else null
	if host == null:
		return null
	var a: Node3D = ARROW_SCRIPT.new()
	a.setup(vel, dmg, kind, shooter)
	host.add_child(a)
	a.global_position = pos
	last_arrow = a
	return a


func _pull_visual() -> void:
	var vm: Node = build.viewmodel if build else null
	if vm and "kick_offset" in vm:
		vm.kick_offset = Vector3(0.10, 0.04, 0.03) * charge   # натяжение: лук к центру и чуть вверх


func _release_visual() -> void:
	var vm: Node = build.viewmodel if build else null
	if vm and "kick_offset" in vm:
		vm.kick_offset = Vector3.ZERO


const Sfx := preload("res://scripts/sfx.gd")
