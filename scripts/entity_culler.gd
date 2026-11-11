extends Node
## Entity draw/process/physics culling. Inactive-world sleep belongs to WorldSwitcher.
var player: Node3D
var _t:=0.0
const GROUPS: Array[String]=["enemy","reagent","pickup","grave_pile"]
var culled_count:=0
func setup(p:Node3D)->void:
	player=p
	GameState.world_changed.connect(func(_dream:bool)->void:_t=0.3)
func _process(delta:float)->void:
	_t+=delta
	if _t<0.3 or not is_instance_valid(player) or GameState.is_dream(): return
	_t=0.0
	var settings:=get_node_or_null("/root/GameSettings")
	var distance:float=48.0 if not settings else settings.entity_distance_m()
	var limit:=distance*distance;var position:=player.global_position;var culled:=0
	var seen:Dictionary={}
	for group in GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if not node is Node3D or node.is_queued_for_deletion() or seen.has(node.get_instance_id()): continue
			seen[node.get_instance_id()]=true
			var boss:bool=node.is_in_group("block_mother") or node.is_in_group("anaconda")
			var far:bool=not boss and node.global_position.distance_squared_to(position)>limit
			var was_far:bool=node.get_meta("_culled",false)
			if far: culled+=1
			if far==was_far: continue
			node.set_meta("_culled",far)
			if far:
				node.set_meta("_culled_restore",{"visible":node.visible,"process":node.is_processing(),"physics":node.is_physics_processing()})
				node.visible=false;node.set_process(false);node.set_physics_process(false)
			else:
				var saved:Dictionary=node.get_meta("_culled_restore",{"visible":true,"process":true,"physics":true})
				var frozen:bool=node.frozen if "frozen" in node else false
				node.visible=saved.visible and not frozen
				node.set_process(saved.process and not frozen);node.set_physics_process(saved.physics and not frozen)
				node.remove_meta("_culled_restore")
	culled_count=culled
