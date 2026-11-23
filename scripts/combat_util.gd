extends RefCounted
## v0.24: общие помощники боя — список игроков (в сети их несколько), ближайший игрок, урон игроку.
## Урон локальному игроку идёт через GameState.damage_player; удалённому — через сеть (net_session.gd).

static func players(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and (p as Node3D).is_inside_tree():
			out.append(p)
	for p2 in tree.get_nodes_in_group("remote_player"):
		if is_instance_valid(p2) and (p2 as Node3D).is_inside_tree() and not bool(p2.get("dead")):
			out.append(p2)
	return out


static func nearest_player(tree: SceneTree, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in players(tree):
		var d := (p as Node3D).global_position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


static func is_local(p: Node) -> bool:
	return p != null and p.is_in_group("player")


static func hurt(p: Node, amount: int, source: String, origin: Vector3 = Vector3.INF) -> int:
	if p == null or amount <= 0:
		return 0
	if is_local(p):
		if origin != Vector3.INF:
			GameState.hit_from(origin)
		return GameState.damage_player(amount, source)
	var net := p.get_tree().get_first_node_in_group("net_session") if p.is_inside_tree() else null
	if net and net.has_method("hurt_remote"):
		net.hurt_remote(p, amount, source, origin)
		return amount
	return 0


static func push(p: Node, v: Vector3) -> void:
	if p != null and is_local(p) and "velocity" in p:
		p.velocity += v
