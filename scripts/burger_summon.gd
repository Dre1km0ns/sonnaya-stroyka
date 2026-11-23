extends Node
## v0.24: Призывалка бургера — ПКМ в Яви. Предупреждение в чате, ровно через 60 с прилетает Бургер Смерти.
const DELAY := 60.0
const BOSS := preload("res://scripts/boss_burger.gd")
var left := DELAY
var warned_10 := false
var target_player: Node3D = null


static func pending(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("burger_summon") if tree else null


static func can_summon(tree: SceneTree) -> String:
	if GameState.is_dream():
		return "Призывалка работает только в Яви."
	if pending(tree) != null:
		return "Бургер Смерти уже летит."
	for o in tree.get_nodes_in_group("boss"):
		if is_instance_valid(o) and not o.is_queued_for_deletion():
			return "Сначала закончи бой с другим боссом."
	return ""


static func use_summoner(build: Node) -> bool:
	var tree := build.get_tree()
	var why := can_summon(tree)
	if why != "":
		GameState.set_hint(why, false)
		return false
	if not GameState.consume_item("burger_summoner", 1):
		return false
	return start(build.get_parent() if build.get_parent() else tree.current_scene, DELAY) != null


static func start(host: Node, delay: float = DELAY) -> Node:
	if host == null:
		return null
	var s: Node = load("res://scripts/burger_summon.gd").new()
	s.left = delay
	s.name = "BurgerSummon"
	host.add_child(s)
	GameState.chat("Призывалка сработала. Бургер Смерти прилетит через минуту — готовь арену!", Color(1.0, 0.55, 0.3), true)
	Sfx.play("summon", host.get_tree().root, -6.0)
	return s


func _ready() -> void:
	add_to_group("burger_summon")


func _process(delta: float) -> void:
	if GameState.is_dream():
		return
	left -= delta
	if left <= 10.0 and not warned_10:
		warned_10 = true
		GameState.chat("Бургер Смерти совсем близко: 10 секунд!", Color(1.0, 0.45, 0.3), true)
	if left <= 0.0:
		arrive()


func arrive() -> Node:
	var tree := get_tree()
	var p := CombatUtil.nearest_player(tree, Vector3.ZERO) if target_player == null else target_player
	var host: Node3D = null
	var bc := tree.get_first_node_in_group("build_controller")
	if bc and bc.has_method("_wake_world"):
		host = bc._wake_world()
	if host == null:
		host = get_parent() as Node3D
	var boss: Node = null
	if p != null and host != null:
		boss = BOSS.spawn_at(host, (p as Node3D).global_position)
	queue_free()
	return boss


const Sfx := preload("res://scripts/sfx.gd")
const CombatUtil := preload("res://scripts/combat_util.gd")
