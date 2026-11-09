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

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var ray: RayCast3D = $CameraPivot/Camera3D/InteractRay

var flying: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sens: float = MOUSE_SENS_DEFAULT


func _ready() -> void:
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:
			_adjust_mouse_sens(-MOUSE_SENS_STEP)
		elif event.keycode == KEY_BRACKETRIGHT:
			_adjust_mouse_sens(MOUSE_SENS_STEP)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			GameState.select_item_slot(event.keycode - KEY_1)


func _adjust_mouse_sens(delta: float) -> void:
	mouse_sens = clampf(mouse_sens + delta, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	var pct := int(round((mouse_sens / MOUSE_SENS_DEFAULT) * 100.0))
	GameState.set_hint("Чувствительность мыши: %d%%" % pct)


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if GameState.ui_blocked():
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := (SPRINT if Input.is_key_pressed(KEY_SHIFT) else SPEED) * _move_factor()

	if flying:
		var y_move := 0.0
		if Input.is_action_pressed("jump"):
			y_move += 1.0
		if Input.is_key_pressed(KEY_CTRL):
			y_move -= 1.0
		velocity.x = direction.x * FLY_SPEED
		velocity.z = direction.z * FLY_SPEED
		velocity.y = y_move * FLY_SPEED
	else:
		if not is_on_floor():
			velocity.y -= gravity * delta
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()


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
	if _is_in_lake():
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
