extends Object
## Примитивные модели врагов (оригинальная сборка из мешей Godot, см. assets/LICENSE.txt).

static func _prim(parent: Node3D, pname: String, mesh: Mesh, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color * emission
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func build_seam(parent: Node3D, elite: bool) -> void:
	var body_col := Color(0.35, 0.08, 0.22) if elite else Color(0.55, 0.22, 0.48)
	var seam_col := Color(1.0, 0.35, 0.25) if elite else Color(1.0, 0.75, 0.4)
	var scale := 1.15 if elite else 1.0
	var cap := CapsuleMesh.new()
	cap.radius = 0.32 * scale
	cap.height = 1.25 * scale
	_prim(parent, "Body", cap, Vector3(0, 0.72 * scale, 0), body_col, 0.35)
	var head := SphereMesh.new()
	head.radius = 0.28 * scale
	head.height = 0.56 * scale
	_prim(parent, "Head", head, Vector3(0, 1.45 * scale, 0.06), body_col.lightened(0.08), 0.2)
	var seam := BoxMesh.new()
	seam.size = Vector3(0.85 * scale, 0.1, 0.18)
	_prim(parent, "Seam", seam, Vector3(0, 1.05 * scale, 0.28 * scale), seam_col, 0.8)
	var arm := CapsuleMesh.new()
	arm.radius = 0.09 * scale
	arm.height = 0.7 * scale
	_prim(parent, "ArmL", arm, Vector3(-0.42 * scale, 0.85 * scale, 0.05), body_col.darkened(0.1), 0.15)
	_prim(parent, "ArmR", arm, Vector3(0.42 * scale, 0.85 * scale, 0.05), body_col.darkened(0.1), 0.15)
	if elite:
		var horn := CylinderMesh.new()
		horn.top_radius = 0.01
		horn.bottom_radius = 0.08
		horn.height = 0.38
		_prim(parent, "HornL", horn, Vector3(-0.14, 1.82, 0.0), Color(0.15, 0.04, 0.08), 0.4)
		_prim(parent, "HornR", horn, Vector3(0.14, 1.82, 0.0), Color(0.15, 0.04, 0.08), 0.4)


static func build_ghost(parent: Node3D, kind: int, color: Color) -> void:
	var head := SphereMesh.new()
	match kind:
		0:
			head.radius = 0.38
			head.height = 0.76
			_prim(parent, "Head", head, Vector3(0, 1.15, 0), color, 0.45)
			var skirt := CylinderMesh.new()
			skirt.top_radius = 0.36
			skirt.bottom_radius = 0.42
			skirt.height = 0.85
			_prim(parent, "Body", skirt, Vector3(0, 0.48, 0), color, 0.4)
			_add_eyes(parent, Vector3(0, 1.18, 0.28), 0.09)
		1:
			head.radius = 0.34
			head.height = 0.68
			_prim(parent, "Head", head, Vector3(0, 1.2, 0), color, 0.45)
			var skirt2 := CylinderMesh.new()
			skirt2.top_radius = 0.3
			skirt2.bottom_radius = 0.4
			skirt2.height = 0.9
			_prim(parent, "Body", skirt2, Vector3(0, 0.5, 0), color, 0.4)
			var ear := SphereMesh.new()
			ear.radius = 0.12
			ear.height = 0.24
			_prim(parent, "EarL", ear, Vector3(-0.22, 1.52, 0.0), color.lightened(0.15), 0.35)
			_prim(parent, "EarR", ear, Vector3(0.22, 1.52, 0.0), color.lightened(0.15), 0.35)
			_add_eyes(parent, Vector3(0, 1.2, 0.26), 0.08)
		2:
			head.radius = 0.3
			head.height = 0.6
			_prim(parent, "Head", head, Vector3(0, 1.22, 0), color, 0.5)
			var slim := CapsuleMesh.new()
			slim.radius = 0.24
			slim.height = 1.05
			_prim(parent, "Body", slim, Vector3(0, 0.55, 0), color, 0.4)
			var fin := BoxMesh.new()
			fin.size = Vector3(0.08, 0.42, 0.28)
			_prim(parent, "Fin", fin, Vector3(0, 1.52, -0.05), color.lightened(0.1), 0.35)
			_add_eyes(parent, Vector3(0, 1.22, 0.24), 0.07)
		_:
			var chubby := SphereMesh.new()
			chubby.radius = 0.48
			chubby.height = 0.96
			_prim(parent, "Body", chubby, Vector3(0, 0.55, 0), color, 0.4)
			head.radius = 0.28
			head.height = 0.56
			_prim(parent, "Head", head, Vector3(0, 1.15, 0.08), color.lightened(0.08), 0.35)
			_add_eyes(parent, Vector3(0, 1.16, 0.3), 0.08)


static func _add_eyes(parent: Node3D, center: Vector3, r: float) -> void:
	var eye := SphereMesh.new()
	eye.radius = r
	eye.height = r * 2.0
	_prim(parent, "EyeL", eye, center + Vector3(-r * 1.3, 0.02, 0.0), Color(0.95, 0.95, 0.98), 0.15)
	_prim(parent, "EyeR", eye, center + Vector3(r * 1.3, 0.02, 0.0), Color(0.95, 0.95, 0.98), 0.15)
	var pupil := SphereMesh.new()
	pupil.radius = r * 0.45
	pupil.height = r * 0.9
	_prim(parent, "PupilL", pupil, center + Vector3(-r * 1.3, 0.0, r * 0.55), Color(0.08, 0.08, 0.1), 0.0)
	_prim(parent, "PupilR", pupil, center + Vector3(r * 1.3, 0.0, r * 0.55), Color(0.08, 0.08, 0.1), 0.0)
