extends CharacterBody3D
## FPS-контроллер: ходьба в яви, полёт во сне (V).

const SPEED := 6.0
const SPRINT := 10.0
const JUMP_VELOCITY := 5.5
const FLY_SPEED := 10.0
const MOUSE_SENS_DEFAULT := 0.001
const MOUSE_SENS_MIN := 0.0002
const MOUSE_SENS_MAX := 0.004
const MOUSE_SENS_STEP := 0.0002
const LAKE_SPEED_FACTOR := 0.4
## v0.7: автоподбор ресурсов/блоков/кучек смерти в радиусе, плавание в текучей воде.
const PICKUP_RADIUS := 1.7
const SWIM_UP := 3.2
var _step_t := 0.0
var _pickup_t := 0.0
var auto_picked := 0
var auto_pickup_enabled:=true
var pickup_last_usec:=0
var pickup_last_candidates:=0
var _pickup_query: PhysicsShapeQueryParameters3D
const PICKUP_MAX_PER_TICK:=64
const PICKUP_BUDGET_USEC:=1500

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/Camera3D/InteractRay

var flying: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sens: float = MOUSE_SENS_DEFAULT


func _ready() -> void:
	ray.collision_mask = 1|4|8|16|32
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	var gsets := get_node_or_null("/root/GameSettings")
	if gsets:
		mouse_sens = MOUSE_SENS_DEFAULT * float(gsets.mouse_sensitivity)
		gsets.settings_changed.connect(func() -> void:
			mouse_sens = MOUSE_SENS_DEFAULT * float(gsets.mouse_sensitivity))
	collision_mask = 1 | 4 | 16
	GameState.world_changed.connect(_on_world_changed)


func _on_world_changed(is_dream: bool) -> void:
	flying = is_dream
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if GameState.ui_blocked():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)
		pivot.rotate_x(-event.relative.y * mouse_sens)
		pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("toggle_fly") and GameState.is_dream():
		flying = not flying
		GameState.set_hint("Полёт: %s" % ("вкл" if flying else "выкл"))
	if event.is_action_pressed("cycle_anchor"):
		GameState.cycle_anchor(1)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.cycle_item_slot(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.cycle_item_slot(1)
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("sens_down"):
		_adjust_mouse_sens(-MOUSE_SENS_STEP)
	elif event.is_action_pressed("sens_up"):
		_adjust_mouse_sens(MOUSE_SENS_STEP)
	for i in range(9):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			GameState.select_item_slot(i)
			break


func _adjust_mouse_sens(delta: float) -> void:
	mouse_sens = clampf(mouse_sens + delta, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	var pct := int(round((mouse_sens / MOUSE_SENS_DEFAULT) * 100.0))
	GameState.set_hint("Чувствительность мыши: %d%%" % pct)


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if GameState.ui_blocked():
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := (SPRINT if Input.is_action_pressed("sprint") else SPEED) * _move_factor()

	if flying:
		var y_move := 0.0
		if Input.is_action_pressed("jump") and not GameState.ui_blocked():
			y_move += 1.0
		if Input.is_action_pressed("fly_down") and not GameState.ui_blocked():
			y_move -= 1.0
		velocity.x = direction.x * FLY_SPEED
		velocity.z = direction.z * FLY_SPEED
		velocity.y = y_move * FLY_SPEED
	else:
		if not is_on_floor():
			velocity.y -= gravity * delta
		if Input.is_action_just_pressed("jump") and is_on_floor() and not GameState.ui_blocked():
			velocity.y = JUMP_VELOCITY
		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)

	if not flying and _in_water():
		# Плавание: медленнее тонем, прыжок — всплыть.
		velocity.y = maxf(velocity.y, -2.0)
		if Input.is_action_pressed("jump") and not GameState.ui_blocked():
			velocity.y = SWIM_UP
	move_and_slide()
	_step_t -= delta
	if not flying and is_on_floor() and direction.length() > 0.1 and _step_t <= 0.0:
		_step_t = 0.32 if Input.is_action_pressed("sprint") else 0.5
		load("res://scripts/sfx.gd").play("step", self)
	_pickup_t -= delta
	if _pickup_t <= 0.0 and auto_pickup_enabled:
		_pickup_t = 0.1
		auto_pickup()


func auto_pickup() -> int:
	if GameState.is_dream() or GameState.player_hp<=0: return 0
	var started:=Time.get_ticks_usec()
	if _pickup_query==null:
		_pickup_query=PhysicsShapeQueryParameters3D.new();var shape:=SphereShape3D.new();shape.radius=PICKUP_RADIUS
		_pickup_query.shape=shape;_pickup_query.collision_mask=8;_pickup_query.collide_with_areas=false
	var me:=global_position+Vector3(0,0.6,0)
	_pickup_query.transform=Transform3D(Basis.IDENTITY,me)
	var hits:=get_world_3d().direct_space_state.intersect_shape(_pickup_query,128)
	pickup_last_candidates=hits.size()
	var nearby: Array[Node3D]=[];var seen: Dictionary={}
	for hit in hits:
		var node: Node3D=hit.collider
		if node.has_meta("pickup_owner"): node=node.get_meta("pickup_owner")
		if seen.has(node.get_instance_id()) or not node.has_method("collect") or node.is_queued_for_deletion(): continue
		seen[node.get_instance_id()]=true
		if not node.is_visible_in_tree() or node.global_position.distance_squared_to(me)>PICKUP_RADIUS*PICKUP_RADIUS: continue
		if "collected" in node and node.collected: continue
		nearby.append(node)
	nearby.sort_custom(func(a:Node3D,b:Node3D)->bool:return a.global_position.distance_squared_to(me)<b.global_position.distance_squared_to(me))
	var count:=0;var attempts:=0;GameState.begin_inventory_batch()
	for node in nearby:
		node.collect();attempts+=1
		if node.is_queued_for_deletion() or ("collected" in node and node.collected): count+=1
		if attempts>=PICKUP_MAX_PER_TICK or Time.get_ticks_usec()-started>=PICKUP_BUDGET_USEC: break
	GameState.end_inventory_batch();auto_picked+=count;pickup_last_usec=Time.get_ticks_usec()-started
	return count


func _in_water() -> bool:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("panorama_mode")) or bool(cm.get("is_dream_layer")):
			continue
		if cm.has_method("is_world_in_water") and cm.is_world_in_water(global_position + Vector3(0, 0.3, 0)):
			return true
	return false


func get_look_ray() -> Dictionary:
	## Возвращает {hit, position, normal, collider} из raycast камеры.
	ray.force_raycast_update()
	if ray.is_colliding():
		return {
			"hit": true,
			"position": ray.get_collision_point(),
			"normal": ray.get_collision_normal(),
			"collider": ray.get_collider(),
		}
	return {"hit": false}


func _move_factor() -> float:
	if flying:
		return 1.0
	if _is_in_lake() or _in_water():
		return LAKE_SPEED_FACTOR
	return 1.0


func _is_in_lake() -> bool:
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if bool(cm.get("panorama_mode")):
			continue
		if not cm.has_method("is_world_in_lake"):
			continue
		var dream_cm := bool(cm.get("is_dream_layer"))
		if dream_cm != GameState.is_dream():
			continue
		if cm.is_world_in_lake(global_position):
			return true
	return false
