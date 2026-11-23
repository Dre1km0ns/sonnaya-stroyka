extends Node3D
## v0.24: слабая точка тарелки Бургера — светящийся гриль на ободе. Сбивается стрелами (и мечом, если достать).
## Сбитая точка наносит боссу WEAK_BONUS и оглушает тарелку; через 35 с отрастает.
var boss: Node = null
var hp := 45
var max_hp := 45
var radius := 0.6
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _pulse := 0.0


func _ready() -> void:
	add_to_group("weak_point")
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.42; sm.height = 0.84
	_mesh.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.3, 0.9, 1.0)
	_mat.emission_enabled = true
	_mat.emission = Color(0.2, 0.85, 1.0)
	_mat.emission_energy_multiplier = 3.0
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(delta: float) -> void:
	_pulse += delta * 5.0
	if hp > 0:
		_mesh.scale = Vector3.ONE * (1.0 + 0.12 * sin(_pulse))


func hit_by_arrow(dmg: int, _arrow: Node = null) -> void:
	take_hit(dmg)


func take_hit(dmg: int) -> void:
	if hp <= 0 or dmg <= 0:
		return
	hp = maxi(0, hp - dmg)
	_mat.emission = Color(1.0, 0.4, 0.2) if hp < max_hp / 2 else Color(0.2, 0.85, 1.0)
	if hp <= 0:
		visible = false
		remove_from_group("weak_point")
		if boss and is_instance_valid(boss) and boss.has_method("weak_point_destroyed"):
			boss.weak_point_destroyed(self)


func regrow() -> void:
	hp = max_hp
	visible = true
	_mat.emission = Color(0.2, 0.85, 1.0)
	if not is_in_group("weak_point"):
		add_to_group("weak_point")
