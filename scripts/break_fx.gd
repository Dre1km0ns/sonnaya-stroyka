extends RefCounted
## v0.24: частицы при добыче и разрушении блока — цвет материала (средний цвет тайла атласа).
const BlockTex := preload("res://scripts/block_tex.gd")
static var _colors: Dictionary = {}
static var spawned := 0
static var last_color := Color.WHITE

static func color_of(kind: String) -> Color:
	if _colors.has(kind):
		return _colors[kind]
	if kind.begins_with("__"):
		return Color.WHITE
	var c := Color(0.5, 0.45, 0.4)
	var tex := BlockTex.atlas()
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed(): img.decompress()
			var faces: Array = BlockTex.faces_for(kind)
			var tile := int(faces[0]) if faces.size() > 0 else 2
			var r := 0.0; var g := 0.0; var b := 0.0; var n := 0
			for y in range(0, 16, 2):
				for x in range(0, 16, 2):
					var p := img.get_pixel(tile * 16 + x, y)
					r += p.r; g += p.g; b += p.b; n += 1
			c = Color(r / n, g / n, b / n)
	_colors[kind] = c
	return c


static func _emit(host: Node, pos: Vector3, kind: String, amount: int, speed: float, size: float, life: float) -> CPUParticles3D:
	spawned += 1
	if host == null or not host.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3.ONE * 0.35
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	last_color = color_of(kind)
	mat.albedo_color = last_color
	mat.roughness = 1.0
	m.material = mat
	p.mesh = m
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func burst(host: Node, cell: Vector3i, kind: String) -> CPUParticles3D:
	return _emit(host, Vector3(cell) + Vector3.ONE * 0.5, kind, 18, 4.5, 0.12, 0.8)


static func chips(host: Node, cell: Vector3i, kind: String, amount: int = 4) -> CPUParticles3D:
	return _emit(host, Vector3(cell) + Vector3.ONE * 0.5, kind, amount, 2.5, 0.07, 0.45)


static func puff(host: Node, pos: Vector3, col: Color, amount: int = 16) -> CPUParticles3D:
	## Облачко смерти моба / клоуна.
	_colors["__puff"] = col
	return _emit(host, pos, "__puff", amount, 3.0, 0.16, 0.7)
