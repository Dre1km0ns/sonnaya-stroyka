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
## v0.21 c2: «флора Сна» на земле — кристаллы, кочки, светящиеся пятна (MultiMesh, без физики).
const FLORA_R := 34
const FLORA_SNAP := 8
var flora: Array[MultiMeshInstance3D] = []
var flora_counts := [0, 0, 0]
var _flora_center := Vector2i(2147483647, 0)
var _chunks: Node = null
var _flora_dirty := false
var _flora_t := 0.0


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
	_build_flora()
	apply_palette()
	GameState.world_changed.connect(func(_d: bool) -> void: apply_palette())
	# постройка поверх флоры — пересобрать (не чаще 2 раз в секунду)
	GameState.placed_cells_changed.connect(func(dream, _cells) -> void:
		if bool(dream): _flora_dirty = true)


func apply_palette() -> void:
	var sky: Array = GameState.dream_sky()
	var top: Color = (sky[0] as Color).darkened(0.25)
	var hor: Color = (sky[2] as Color).lerp(sky[1], 0.35)
	sky_mat.set_shader_parameter("top_color", Vector3(top.r, top.g, top.b))
	sky_mat.set_shader_parameter("horizon_color", Vector3(hor.r, hor.g, hor.b))
	sky_mat.set_shader_parameter("unease", clampf(float(GameState.dream_cracks.size()) / 16.0, 0.0, 1.0))
	if islands and islands.material_override:
		(islands.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1).lerp(hor.lightened(0.2), 0.35)


func _process(delta: float) -> void:
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
	var fc := Vector2i(floori(_cam.global_position.x / FLORA_SNAP), floori(_cam.global_position.z / FLORA_SNAP))
	_flora_t -= delta
	if _flora_dirty and _flora_t <= 0.0:
		_flora_dirty = false; _flora_t = 0.5; _flora_center = Vector2i(2147483647, 0)
	if fc != _flora_center:
		_flora_center = fc
		rebuild_flora(Vector2i(fc.x * FLORA_SNAP, fc.y * FLORA_SNAP))


func _rng(i: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = hash(str(_seed) + ":" + str(i)); return r


func _build_islands() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# v0.21 c2: светлее — на фоне неба острова читались тёмными силуэтами.
	var grass := Color(0.82, 0.72, 1.0); var rock := Color(0.50, 0.42, 0.70); var glow := Color(0.85, 1.0, 0.95)
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
					var col := grass if y == 0 else rock.lerp(Color(0.32, 0.26, 0.5), float(y) / float(depth))
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


func _flora_mat(unshaded: bool, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, alpha)
	return m


func _build_flora() -> void:
	var crystal := PrismMesh.new(); crystal.size = Vector3(0.22, 0.95, 0.22); crystal.material = _flora_mat(true, 1.0)
	var tuft := BoxMesh.new(); tuft.size = Vector3(0.42, 0.18, 0.42); tuft.material = _flora_mat(false, 1.0)
	var patch := PlaneMesh.new(); patch.size = Vector2(1.0, 1.0); patch.material = _flora_mat(true, 0.3)
	var names := ["FloraCrystals", "FloraTufts", "FloraPatches"]
	var meshes: Array[Mesh] = [crystal, tuft, patch]
	for i in range(3):
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = meshes[i]
		var mi := MultiMeshInstance3D.new(); mi.name = names[i]; mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi); flora.append(mi)


static func _h(x: int, z: int, salt: int) -> float:
	var n := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float(posmod(n ^ (n >> 16), 100000)) / 100000.0


## Пересобрать флору вокруг точки (x,z). Детерминированно от клетки; пропускает озёра, руины, постройки игрока.
func rebuild_flora(center: Vector2i) -> void:
	if _chunks == null:
		_chunks = get_parent().get_node_or_null("DreamChunks") if get_parent() else null
	var lists := [[], [], []]
	for x in range(center.x - FLORA_R, center.x + FLORA_R):
		for z in range(center.y - FLORA_R, center.y + FLORA_R):
			var r := _h(x, z, _seed)
			var kind := 0 if r < 0.022 else (1 if r < 0.075 else (2 if r < 0.11 else -1))
			if kind < 0: continue
			var h := 0
			if _chunks:
				if _chunks.has_method("chunk_has_ruin") and _chunks.chunk_has_ruin(Vector2i(floori(x / 16.0), floori(z / 16.0))): continue
				if _chunks.has_method("is_world_in_lake") and _chunks.is_world_in_lake(Vector3(x, 0, z)): continue
				if _chunks.has_method("height_at"): h = int(_chunks.height_at(x, z))
			if GameState.dream_blocks.has(Vector3i(x, h, z)) or GameState.dream_blocks.has(Vector3i(x, h + 1, z)): continue
			lists[kind].append(Vector3(x, h, z))
	for i in range(3):
		var mm: MultiMesh = flora[i].multimesh
		var pts: Array = lists[i]
		mm.instance_count = pts.size()
		flora_counts[i] = pts.size()
		for j in range(pts.size()):
			var p: Vector3 = pts[j]
			var a := _h(int(p.x), int(p.z), 7); var b := _h(int(p.x), int(p.z), 11)
			var t := Transform3D()
			var col := Color.WHITE
			if i == 0:
				t.basis = Basis(Vector3.UP, a * TAU) * Basis(Vector3.RIGHT, (b - 0.5) * 0.5)
				t.basis = t.basis.scaled(Vector3.ONE * (0.7 + b * 0.9))
				t.origin = p + Vector3(0.2 + a * 0.6, 0.42, 0.2 + b * 0.6)
				col = Color(0.55, 0.95, 1.0).lerp(Color(1.0, 0.65, 0.95), b)
			elif i == 1:
				t.basis = Basis(Vector3.UP, a * TAU)
				t.origin = p + Vector3(0.5, 0.09, 0.5)
				col = Color(0.62, 0.5, 0.92).lerp(Color(0.48, 0.72, 0.9), a)
			else:
				t.basis = Basis(Vector3.UP, a * TAU).scaled(Vector3(0.6 + a * 0.7, 1.0, 0.6 + b * 0.7))
				t.origin = p + Vector3(0.5, 0.025, 0.5)
				col = Color(0.78, 0.6, 1.0).lerp(Color(0.62, 0.85, 1.0), b)
			mm.set_instance_transform(j, t)
			mm.set_instance_color(j, col)
