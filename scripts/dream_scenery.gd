extends Node3D
## v0.21: Сон оживает — летающие острова и ориентиры на горизонте, светлячки вокруг игрока, небо Сна.
## Декор не участвует в физике и сейве. Слой декора следует за камерой (как далёкие горы):
## при любой дальности прогрузки он стоит внутри дальнего плана камеры (масштаб от тумана).

const AUTHOR_R := 45.0          # радиус, на котором острова «нарисованы»
const ISLANDS := 12
const SKY_SHADER := preload("res://shaders/dream_sky.gdshader")

var islands: MeshInstance3D
var motes: CPUParticles3D
var sky_mat: ShaderMaterial
var dream_sky: Sky
var island_count := 0
var cube_count := 0
var _seed := 0
var _cam: Camera3D


func _ready() -> void:
	name = "DreamScenery"
	add_to_group("dream_scenery")
	_seed = int(GameState.world_seed_dream) if GameState.get("world_seed_dream") != null else 1
	sky_mat = ShaderMaterial.new(); sky_mat.shader = SKY_SHADER
	dream_sky = Sky.new(); dream_sky.sky_material = sky_mat
	dream_sky.process_mode = Sky.PROCESS_MODE_REALTIME
	dream_sky.radiance_size = Sky.RADIANCE_SIZE_32
	_build_islands()
	_build_motes()
	apply_palette()
	GameState.world_changed.connect(func(_d: bool) -> void: apply_palette())


func apply_palette() -> void:
	var sky: Array = GameState.dream_sky()
	var top: Color = (sky[0] as Color).darkened(0.25)
	var hor: Color = (sky[2] as Color).lerp(sky[1], 0.35)
	sky_mat.set_shader_parameter("top_color", Vector3(top.r, top.g, top.b))
	sky_mat.set_shader_parameter("horizon_color", Vector3(hor.r, hor.g, hor.b))
	sky_mat.set_shader_parameter("unease", clampf(float(GameState.dream_cracks.size()) / 16.0, 0.0, 1.0))
	if islands and islands.material_override:
		(islands.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1).lerp(hor.lightened(0.2), 0.35)


func _process(_delta: float) -> void:
	if not GameState.is_dream():
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	var k := clampf((GameSettings.fog_end_distance() * 0.82) / AUTHOR_R, 0.25, 4.0)
	islands.global_position = _cam.global_position
	islands.scale = Vector3.ONE * k
	motes.global_position = _cam.global_position


func _rng(i: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = hash(str(_seed) + ":" + str(i)); return r


func _build_islands() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass := Color(0.62, 0.52, 0.95); var rock := Color(0.30, 0.24, 0.46); var glow := Color(0.85, 1.0, 0.95)
	for i in range(ISLANDS):
		var r := _rng(i)
		var ang := TAU * (float(i) + r.randf_range(-0.3, 0.3)) / float(ISLANDS)
		var dist := r.randf_range(34.0, AUTHOR_R)
		var c := Vector3(cos(ang) * dist, r.randf_range(4.0, 22.0), sin(ang) * dist)
		var rad := r.randi_range(2, 5)
		var depth := rad + r.randi_range(1, 4)
		for y in range(depth):
			var rr := float(rad) * (1.0 - float(y) / float(depth + 1)) + 0.4
			for x in range(-rad, rad + 1):
				for z in range(-rad, rad + 1):
					if Vector2(x, z).length() > rr + r.randf_range(-0.4, 0.3): continue
					var col := grass if y == 0 else rock.lerp(Color(0.18, 0.14, 0.3), float(y) / float(depth))
					_cube(st, c + Vector3(x, -y, z), col)
		# ориентир на части островов: кристаллический шпиль или дерево Сна
		if i % 4 == 0:
			var hgt := r.randi_range(6, 11)
			for y in range(1, hgt + 1):
				_cube(st, c + Vector3(0, y, 0), glow.lerp(Color(0.6, 0.85, 1.0), float(y) / float(hgt)))
			_cube(st, c + Vector3(1, 1, 0), glow); _cube(st, c + Vector3(-1, 2, 0), glow); _cube(st, c + Vector3(0, 3, 1), glow)
		elif i % 4 == 2:
			for y in range(1, 4): _cube(st, c + Vector3(0, y, 0), Color(0.42, 0.3, 0.5))
			for x in range(-1, 2):
				for z in range(-1, 2):
					for y in range(4, 6): _cube(st, c + Vector3(x, y, z), Color(0.95, 0.6, 0.85))
		island_count += 1
	# большой ориентир: перевёрнутая башня над горизонтом
	var tr := _rng(999); var ta := tr.randf_range(0.0, TAU)
	var tc := Vector3(cos(ta) * AUTHOR_R * 0.98, 30.0, sin(ta) * AUTHOR_R * 0.98)
	for y in range(14):
		var w := 1 + int(y / 4)
		for x in range(-w, w + 1):
			for z in range(-w, w + 1):
				if abs(x) == w or abs(z) == w or y % 4 == 0:
					_cube(st, tc + Vector3(x, -y, z), Color(0.75, 0.7, 0.98).darkened(float(y) * 0.03))
	st.generate_normals()
	islands = MeshInstance3D.new(); islands.name = "Islands"
	islands.mesh = st.commit()
	islands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	islands.material_override = m
	add_child(islands)


func _cube(st: SurfaceTool, p: Vector3, col: Color) -> void:
	cube_count += 1
	var faces := [
		[Vector3(0, 1, 0), 1.0], [Vector3(0, -1, 0), 0.55], [Vector3(1, 0, 0), 0.8],
		[Vector3(-1, 0, 0), 0.72], [Vector3(0, 0, 1), 0.86], [Vector3(0, 0, -1), 0.66]]
	for f in faces:
		var n: Vector3 = f[0]; var shade: float = f[1]
		var u := Vector3(n.y, n.z, n.x); var v := n.cross(u)
		var o := p + Vector3(0.5, 0.5, 0.5) + n * 0.5
		var a := o - u * 0.5 - v * 0.5; var b := o + u * 0.5 - v * 0.5
		var c := o + u * 0.5 + v * 0.5; var d := o - u * 0.5 + v * 0.5
		var cc := Color(col.r * shade, col.g * shade, col.b * shade)
		st.set_color(cc)
		for q in [a, c, b, a, d, c]:
			st.add_vertex(q)


func _build_motes() -> void:
	motes = CPUParticles3D.new(); motes.name = "Motes"
	motes.amount = 90
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(16, 7, 16)
	motes.direction = Vector3(0, 1, 0); motes.spread = 180.0
	motes.gravity = Vector3(0, 0.08, 0)
	motes.initial_velocity_min = 0.05; motes.initial_velocity_max = 0.25
	motes.scale_amount_min = 0.6; motes.scale_amount_max = 1.4
	var q := QuadMesh.new(); q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.85, 1.0, 0.85)
	q.material = m
	motes.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.9, 1.0, 0.0)); g.set_color(1, Color(1.0, 0.8, 1.0, 0.0))
	g.add_point(0.3, Color(0.85, 0.95, 1.0, 0.9)); g.add_point(0.7, Color(1.0, 0.85, 1.0, 0.8))
	motes.color_ramp = g
	add_child(motes)
