extends Node
## v0.5: сущности дальше «Дальности сущностей» (настройка, в чанках) не симулируются и не рисуются.

var player: Node3D
var _t := 0.0
const GROUPS := ["enemy", "reagent", "pickup", "block_mother"]
var culled_count: int = 0


func setup(p: Node3D) -> void:
	player = p
	GameState.world_changed.connect(func(_d: bool) -> void:
		for g in GROUPS:
			for n in get_tree().get_nodes_in_group(g):
				if is_instance_valid(n):
					n.remove_meta("_culled"))


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.3:
		return
	_t = 0.0
	if player == null or GameState.is_dream():
		return
	var gsets := get_node_or_null("/root/GameSettings")
	var dist := 48.0 if gsets == null else float(gsets.entity_distance_m())
	var d2 := dist * dist
	var pp := player.global_position
	var culled := 0
	for g in GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var far := (n as Node3D).global_position.distance_squared_to(pp) > d2
			if g == "block_mother":
				far = false
			var was_far := bool(n.get_meta("_culled", false))
			if far == was_far:
				if far:
					culled += 1
				continue
			n.set_meta("_culled", far)
			if far:
				culled += 1
				n.visible = false
				if n is CharacterBody3D:
					n.set_physics_process(false)
			else:
				var frozen := bool(n.get("frozen")) if "frozen" in n else false
				n.visible = not frozen
				if n is CharacterBody3D and not frozen:
					n.set_physics_process(true)
	culled_count = culled
