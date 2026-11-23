extends CharacterBody3D
## v0.23: выброшенный предмет (Q, Ctrl+Q, вынос из окна инвентаря) — как в Minecraft.
## Летит вперёд, падает, крутится; первые DROP_PICKUP_DELAY секунд не подбирается,
## дальше его подбирает обычный автоподбор игрока. Хранится в GameState.dropped_items и в сохранении мира.

const ItemDB := preload("res://scripts/item_db.gd")

var rec: Dictionary = {}
var pickup_delay := 0.0
var collected := false
var _spin := 0.0
var _visual: Node3D
var _sync_t := 0.0
## v0.24: выброшенное и выпавшее пропадает через 5 минут (последние 10 с мигает). Трофеи боссов не пропадают.
const DESPAWN_SEC := 300.0
const KEEP := ["burger_core", "burger_trophy", "stone_heart", "scale_fang", "clown_nose", "grill_saucer", "burger_summoner"]
static var _pick_sfx_ms := 0


func setup(record: Dictionary, vel: Vector3 = Vector3.ZERO, delay: float = 0.0) -> void:
	rec = record
	velocity = vel
	pickup_delay = delay


func item_id() -> String:
	return str(rec.get("id", ""))


func item_count() -> int:
	return int(rec.get("count", 0))


func _ready() -> void:
	add_to_group("pickup")
	add_to_group("dropped_item")
	collision_layer = 8
	collision_mask = 1 | 4
	_spin = randf() * TAU
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	col.shape = shape
	add_child(col)
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var id := item_id()
	var bt: GDScript = load("res://scripts/block_tex.gd")
	if GameState.is_placeable_block(id) and id != "torch":
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = bt.cube_mesh(id, Vector3.ONE * 0.26)
		_visual.add_child(mi)
		if item_count() > 1:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = mi.mesh
			mi2.position = Vector3(0.07, 0.07, 0.06)
			mi2.rotation_degrees = Vector3(0, 25, 0)
			_visual.add_child(mi2)
		return
	var spr := Sprite3D.new()
	spr.name = "Sprite"
	spr.texture = ItemDB.icon(id)
	spr.pixel_size = 0.36 / maxf(1.0, float(spr.texture.get_width())) if spr.texture else 0.01
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	_visual.add_child(spr)


func can_pick_up() -> bool:
	return not collected and pickup_delay <= 0.0


func collect() -> void:
	if not can_pick_up() or GameState.is_dream():
		return
	var got: int = GameState.give_payload(rec)
	if got <= 0:
		return
	GameState.drops_picked += got
	if Time.get_ticks_msec() - _pick_sfx_ms > 90:
		_pick_sfx_ms = Time.get_ticks_msec()
		load("res://scripts/sfx.gd").play("pickup", get_tree().root, -6.0, randf_range(0.95, 1.15))
	rec["count"] = item_count() - got
	if item_count() > 0:
		return
	collected = true
	GameState.unregister_drop(rec)
	visible = false
	collision_layer = 0
	queue_free()


func _physics_process(delta: float) -> void:
	if collected:
		return
	pickup_delay = maxf(0.0, pickup_delay - delta)
	_spin += delta * 1.6
	if _visual:
		_visual.rotation.y = _spin
		_visual.position.y = 0.06 + sin(_spin * 1.5) * 0.04
	if GameState.is_dream():
		return
	velocity.y = maxf(-25.0, velocity.y - 18.0 * delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
	move_and_slide()
	if not str(rec.get("id", "")) in KEEP:
		var age := float(rec.get("age", 0.0)) + delta
		rec["age"] = age
		if age > DESPAWN_SEC - 10.0 and _visual:
			_visual.visible = fmod(age, 0.5) < 0.3
		if age >= DESPAWN_SEC:
			collected = true
			GameState.unregister_drop(rec)
			queue_free()
			return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.25
		rec["pos"] = global_position
		if global_position.y < -60.0:
			GameState.unregister_drop(rec)
			queue_free()
