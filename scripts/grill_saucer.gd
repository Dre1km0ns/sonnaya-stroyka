extends Node3D
## v0.24: Гриль-тарелка (дроп Бургера, 20 %) — метательное оружие: ПКМ бросает вращающуюся тарелку,
## она взрывается при попадании (30 урона в радиусе 2.5 м). Тратит 1 прочности за бросок.
const Sfx := preload("res://scripts/sfx.gd")
const BreakFx := preload("res://scripts/break_fx.gd")
const SPEED := 22.0
const DMG := 30
const R := 2.5
var vel := Vector3.ZERO
var _t := 0.0
static var thrown := 0


static func throw_from(build: Node) -> Node3D:
	var player: Node3D = build.player
	var host: Node = build._wake_world()
	if player == null or host == null or GameState.is_dream():
		return null
	var cam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var fwd := -cam.global_transform.basis.z if cam else -player.global_transform.basis.z
	var g: Node3D = load("res://scripts/grill_saucer.gd").new()
	g.vel = fwd * SPEED
	host.add_child(g)
	g.global_position = (cam.global_position if cam else player.global_position + Vector3(0, 1.5, 0)) + fwd * 0.8
	GameState.wear_tool(1)
	thrown += 1
	return g


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.35; cm.bottom_radius = 0.45; cm.height = 0.12
	mi.mesh = cm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.65, 0.68, 0.75); m.metallic = 0.6
	mi.material_override = m
	add_child(mi)


func _physics_process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 20.0
	vel.y -= 4.0 * delta
	var from := global_position
	var to := from + vel * delta
	var hit := false
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and is_instance_valid(e):
			var c: Vector3 = e.hit_center() if e.has_method("hit_center") else (e as Node3D).global_position
			if c.distance_to(to) < 1.2 + (float(e.get("hit_radius")) if "hit_radius" in e else 0.0):
				hit = true
	if not hit and get_world_3d():
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		hit = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	global_position = to
	if hit or _t > 3.0:
		_explode()


func _explode() -> void:
	Sfx.play3d(self, "res://assets/audio/sfx_explosion.ogg", -2.0, 60.0)
	BreakFx.puff(get_parent(), global_position, Color(1, 0.55, 0.2), 20)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and is_instance_valid(e):
			var c: Vector3 = e.hit_center() if e.has_method("hit_center") else (e as Node3D).global_position
			if c.distance_to(global_position) < R + (float(e.get("hit_radius")) if "hit_radius" in e else 0.0):
				if e.has_method("take_damage"):
					e.take_damage(GameState.player_damage_mult(DMG))
	queue_free()
