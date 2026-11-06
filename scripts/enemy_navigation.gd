extends Object
## Общее движение врагов: коллизия друг с другом, шаг на холмик, обход воды и стен.

const ENEMY_LAYER := 16
const WORLD_LAYER := 1
const SPEED_SCALE := 0.6
const STEP_HEIGHT := 1.05
const JUMP_VELOCITY := 5.4
const LOOK_AHEAD := 1.35


static func setup_body(body: CharacterBody3D) -> void:
	body.collision_layer = ENEMY_LAYER
	body.collision_mask = WORLD_LAYER | ENEMY_LAYER
	body.floor_max_angle = deg_to_rad(55.0)
	body.floor_snap_length = 0.35
	body.safe_margin = 0.08
	body.max_slides = 6


static func is_water_at(body: Node3D, pos: Vector3) -> bool:
	var tree := body.get_tree()
	if tree == null:
		return false
	for cm in tree.get_nodes_in_group("chunk_manager"):
		if bool(cm.get("is_dream_layer")):
			continue
		if cm.has_method("is_world_in_lake") and cm.is_world_in_lake(pos):
			return true
	return false


static func apply_movement(body: CharacterBody3D, want_dir: Vector3, speed: float, delta: float) -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	want_dir.y = 0.0
	if want_dir.length() > 0.001:
		want_dir = want_dir.normalized()
	else:
		want_dir = Vector3.ZERO

	var chosen := _pick_steer_dir(body, want_dir)

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0
		if chosen.length() > 0.01 and _blocked(body, chosen, 0.42):
			var lifted := body.global_transform
			lifted.origin.y += STEP_HEIGHT
			if not body.test_move(lifted, chosen * 0.55):
				body.velocity.y = JUMP_VELOCITY

	body.velocity.x = chosen.x * speed
	body.velocity.z = chosen.z * speed
	body.move_and_slide()


static func _pick_steer_dir(body: CharacterBody3D, want_dir: Vector3) -> Vector3:
	if want_dir.length() < 0.001:
		return Vector3.ZERO
	var candidates: Array[Vector3] = [want_dir]
	for i in range(8):
		var a := float(i) * PI * 0.25
		candidates.append(Vector3(cos(a), 0.0, sin(a)))
	var best := want_dir
	var best_score := -1000.0
	var in_water := is_water_at(body, body.global_position)
	for raw in candidates:
		var d: Vector3 = raw.normalized()
		var probe := body.global_position + d * LOOK_AHEAD
		var near := body.global_position + d * 0.7
		var water_ahead := is_water_at(body, probe) or is_water_at(body, near)
		if water_ahead and not in_water:
			continue
		var score := d.dot(want_dir)
		if water_ahead:
			score -= 1.4
		elif in_water and not is_water_at(body, probe):
			score += 0.7
		if _blocked(body, d, 0.45):
			score -= 0.9
			var lifted := body.global_transform
			lifted.origin.y += STEP_HEIGHT
			if not body.test_move(lifted, d * 0.5):
				score += 0.55
		if score > best_score:
			best_score = score
			best = d
	return best


static func _blocked(body: CharacterBody3D, dir: Vector3, dist: float) -> bool:
	return body.test_move(body.global_transform, dir * dist)
