extends RefCounted
## v0.6: общий атлас текстур блоков (assets/textures/atlas.png, генерирует tools/make_textures.py),
## материалы и кубы с правильными UV для всех блоков/дропов.

const TILES := ["grass_top", "grass_side", "dirt", "stone", "brick", "brick_mossy", "log_side", "log_top",
	"leaves", "sand", "water", "dream_top", "dream_side", "dream_dirt", "drift", "drift_dream",
	"drift_anchored", "mouth", "bench_top", "bench_side", "beacon", "planks", "dream_brick", "torch",
	"bedrock", "nest", "egg", "bed_top", "bed_side", "deep_stone", "grave", "lathe_top", "lathe_side", "blanket", "mattress",
	"blade2", "scale", "scale_head", "tool_wood", "tool_stone"]

static var _mat: ShaderMaterial = null
static var _water: Dictionary = {}
static var _cubes: Dictionary = {}
static var _idx: Dictionary = {}


static func tile(name: String) -> int:
	var i := TILES.find(name)
	return i if i >= 0 else 2


static func atlas() -> Texture2D:
	return load("res://assets/textures/atlas.png") as Texture2D


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/terrain.gdshader")
		_mat.set_shader_parameter("atlas", atlas())
	return _mat


static func water_material(dream: bool) -> ShaderMaterial:
	if _water.has(dream):
		return _water[dream]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("atlas", atlas())
	m.set_shader_parameter("tile", tile("water"))
	m.set_shader_parameter("tint", Vector3(0.62, 0.48, 1.0) if dream else Vector3(1, 1, 1))
	m.set_shader_parameter("alpha", 0.66)
	_water[dream] = m
	return m


## Тайлы граней куба: [+X, -X, +Y, -Y, +Z, -Z]
static func faces_for(kind: String, dream: bool = false, exposed_top: bool = true, variant: int = 0) -> Array:
	match kind:
		"hill", "ground":
			if dream:
				if exposed_top:
					return _f(tile("dream_side"), tile("dream_top"), tile("dream_dirt"))
				return _all(tile("dream_dirt"))
			if exposed_top:
				return _f(tile("grass_side"), tile("grass_top"), tile("dirt"))
			return _all(tile("dirt"))
		"dirt":
			return _all(tile("dirt"))
		"tool_wood", "tool_stone":
			return _all(tile(kind))
		"stone":
			return _all(tile("stone"))
		"deep_stone":
			return _all(tile("deep_stone"))
		"bedrock":
			return _all(tile("bedrock"))
		"nest":
			return _all(tile("nest"))
		"egg":
			return _all(tile("egg"))
		"bed":
			return _f(tile("bed_side"), tile("bed_top"), tile("planks"))
		"blanket":
			return _all(tile("blanket"))
		"mattress":
			return _all(tile("mattress"))
		"lathe":
			return _f(tile("lathe_side"), tile("lathe_top"), tile("planks"))
		"grave":
			return _all(tile("grave"))
		"blade2":
			return _all(tile("blade2"))
		"scale":
			return _all(tile("scale"))
		"scale_head":
			return [tile("scale"), tile("scale"), tile("scale"), tile("scale"), tile("scale"), tile("scale_head")]
		"mossy_ruin":
			return _all(tile("brick_mossy"))
		"ruin":
			if dream:
				return _all(tile("dream_brick"))
			return _all(tile("brick"))
		"log":
			return _f(tile("log_side"), tile("log_top"), tile("log_top"))
		"leaves":
			return _all(tile("leaves"))
		"planks":
			return _all(tile("planks"))
		"workbench":
			return _f(tile("bench_side"), tile("bench_top"), tile("planks"))
		"beacon":
			return _all(tile("beacon"))
		"mouth":
			return _all(tile("mouth"))
		"torch":
			return _all(tile("torch"))
		"drift_dream":
			return _all(tile("drift_dream"))
		"drift_anchored":
			return _all(tile("drift_anchored"))
		"sand":
			return _all(tile("sand"))
		_:
			return _all(tile("drift"))


static func _all(t: int) -> Array:
	return [t, t, t, t, t, t]


static func _f(side: int, top: int, bottom: int) -> Array:
	return [side, side, top, bottom, side, side]


const FACES := [
	[Vector3(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
	[Vector3(0, -1, 0), [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]],
	[Vector3(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]],
	[Vector3(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
]


static func emit_box(st: Dictionary, mn: Vector3, size: Vector3, col: Color, skip_mask: int, tiles: Array, norm_uv: bool = false) -> void:
	## st: {v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array}
	var verts: PackedVector3Array = st["v"]
	var norms: PackedVector3Array = st["n"]
	var cols: PackedColorArray = st["c"]
	var uvs: PackedVector2Array = st["uv"]
	var uv2s: PackedVector2Array = st["uv2"]
	for fi in range(6):
		if skip_mask & (1 << fi):
			continue
		var f: Array = FACES[fi]
		var n: Vector3 = f[0]
		var cs: Array = f[1]
		var shade := 1.0
		if n.y < -0.5:
			shade = 0.55
		elif absf(n.x) > 0.5:
			shade = 0.80
		elif absf(n.z) > 0.5:
			shade = 0.90
		var cc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		var t := Vector2(float(tiles[fi]), 0.0)
		var p: Array = []
		var u: Array = []
		for k in range(4):
			var lc: Vector3 = (cs[k] as Vector3) * size
			p.append(mn + lc)
			var q: Vector3 = (cs[k] as Vector3) if norm_uv else lc
			var qs: Vector3 = Vector3.ONE if norm_uv else size
			if absf(n.x) > 0.5:
				u.append(Vector2(qs.z - q.z if n.x > 0 else q.z, qs.y - q.y))
			elif absf(n.z) > 0.5:
				u.append(Vector2(q.x if n.z > 0 else qs.x - q.x, qs.y - q.y))
			else:
				u.append(Vector2(q.x, q.z))
		for k2 in [0, 2, 1, 0, 3, 2]:
			verts.append(p[k2])
			uvs.append(u[k2])
			uv2s.append(t)
			norms.append(n)
			cols.append(cc)


static func new_stream() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
		"uv": PackedVector2Array(), "uv2": PackedVector2Array()}


static func stream_to_mesh(st: Dictionary, mat: Material = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = st["v"]
	arrays[Mesh.ARRAY_NORMAL] = st["n"]
	arrays[Mesh.ARRAY_COLOR] = st["c"]
	arrays[Mesh.ARRAY_TEX_UV] = st["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = st["uv2"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat if mat != null else material())
	return mesh


static func cube_mesh(kind: String, size: Vector3 = Vector3.ONE, dream: bool = false, tint: Color = Color(1, 1, 1)) -> ArrayMesh:
	## Куб с центром в нуле, текстуры по граням. Кэшируется.
	var key := "%s|%s|%s|%s" % [kind, str(size), str(dream), tint.to_html()]
	if _cubes.has(key):
		return _cubes[key]
	var st := new_stream()
	emit_box(st, -size * 0.5, size, tint, 0, faces_for(kind, dream, true, 1), true)
	var m := stream_to_mesh(st)
	_cubes[key] = m
	return m


static func bed_mesh(length: float = 1.0) -> ArrayMesh:
	## v0.7: процедурная кровать (рама из досок, матрас, красное одеяло, подушка, изголовье по -Z).
	## Центр по XZ в нуле, низ на y=-0.5 (как у куба-блока). length — вдоль Z (спавн-кровать = 2).
	var key := "bed|%s" % str(length)
	if _cubes.has(key):
		return _cubes[key]
	var st := new_stream()
	var w := 0.96
	var l := length - 0.04
	var z0 := -l * 0.5
	var white := Color(1, 1, 1)
	emit_box(st, Vector3(-w * 0.5, -0.5, z0), Vector3(w, 0.26, l), white, 0, faces_for("planks"), true)
	for lx in [-w * 0.5, w * 0.5 - 0.1]:
		for lz in [z0, z0 + l - 0.1]:
			emit_box(st, Vector3(lx, -0.5, lz), Vector3(0.1, 0.1, 0.1), white.darkened(0.2), 0, faces_for("log"), true)
	emit_box(st, Vector3(-w * 0.5 + 0.03, -0.24, z0 + 0.03), Vector3(w - 0.06, 0.14, l - 0.06), white, 0, faces_for("mattress"), true)
	var bl := l * 0.64
	emit_box(st, Vector3(-w * 0.5 + 0.01, -0.12, z0 + l - bl), Vector3(w - 0.02, 0.07, bl), white, 0, faces_for("blanket"), true)
	emit_box(st, Vector3(-w * 0.32, -0.12, z0 + 0.06), Vector3(w * 0.64, 0.12, minf(0.26, l * 0.22)), white, 0, faces_for("mattress"), true)
	emit_box(st, Vector3(-w * 0.5, -0.5, z0 - 0.02), Vector3(w, 0.72, 0.08), white, 0, faces_for("planks"), true)
	var m := stream_to_mesh(st)
	_cubes[key] = m
	return m


static func lathe_mesh() -> ArrayMesh:
	## v0.7: Станок — каменно-деревянный стол со шпинделем и диском.
	if _cubes.has("lathe_mesh"):
		return _cubes["lathe_mesh"]
	var st := new_stream()
	var white := Color(1, 1, 1)
	emit_box(st, Vector3(-0.49, -0.5, -0.49), Vector3(0.98, 0.78, 0.98), white, 0, faces_for("lathe"), true)
	emit_box(st, Vector3(-0.42, 0.28, -0.12), Vector3(0.18, 0.2, 0.24), white.darkened(0.1), 0, faces_for("stone"), true)
	emit_box(st, Vector3(0.24, 0.28, -0.12), Vector3(0.18, 0.2, 0.24), white.darkened(0.1), 0, faces_for("stone"), true)
	emit_box(st, Vector3(-0.24, 0.34, -0.04), Vector3(0.48, 0.08, 0.08), Color(0.75, 0.8, 0.9), 0, faces_for("beacon"), true)
	emit_box(st, Vector3(-0.06, 0.24, -0.2), Vector3(0.12, 0.28, 0.4), white, 0, faces_for("stone"), true)
	var m := stream_to_mesh(st)
	_cubes["lathe_mesh"] = m
	return m


static func sword2_mesh() -> ArrayMesh:
	## v0.7: Меч2 — кристаллический клинок (своя текстура blade2), латунная гарда, рукоять из бревна.
	if _cubes.has("sword2_mesh"):
		return _cubes["sword2_mesh"]
	var st := new_stream()
	var w := Color(1, 1, 1)
	emit_box(st, Vector3(-0.05, 0.0, -0.025), Vector3(0.10, 0.18, 0.05), w, 0, faces_for("log"), true)
	emit_box(st, Vector3(-0.06, -0.04, -0.03), Vector3(0.12, 0.05, 0.06), Color(1.0, 0.85, 0.4), 0, faces_for("egg"), true)
	emit_box(st, Vector3(-0.17, 0.18, -0.035), Vector3(0.34, 0.06, 0.07), Color(1.0, 0.8, 0.3), 0, faces_for("torch"), true)
	emit_box(st, Vector3(-0.055, 0.24, -0.02), Vector3(0.11, 0.62, 0.04), w, 0, faces_for("blade2"), true)
	emit_box(st, Vector3(-0.035, 0.86, -0.018), Vector3(0.07, 0.12, 0.036), w, 0, faces_for("blade2"), true)
	emit_box(st, Vector3(-0.015, 0.98, -0.015), Vector3(0.03, 0.06, 0.03), Color(0.9, 1.0, 1.0), 0, faces_for("blade2"), true)
	var m := stream_to_mesh(st)
	_cubes["sword2_mesh"] = m
	return m


static func station_mesh(kind: String) -> ArrayMesh:
	if kind == "lathe":
		return lathe_mesh()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "door":
		_mesh_part(st, "planks", Vector3(-0.5,-1,-0.08), Vector3(1,2,0.16))
		_mesh_part(st, "beacon", Vector3(0.32,-0.12,-0.13), Vector3(0.1,0.12,0.08))
	elif kind == "chest":
		_mesh_part(st, "planks", Vector3(-0.45,-0.5,-0.45), Vector3(0.9,0.75,0.9))
		_mesh_part(st, "log", Vector3(-0.47,0.24,-0.47), Vector3(0.94,0.15,0.94))
		_mesh_part(st, "beacon", Vector3(-0.08,0.05,0.46), Vector3(0.16,0.18,0.04))
	else:
		for x in [-0.35,0.25]:
			for z in [-0.35,0.25]:
				_mesh_part(st,"log",Vector3(x,-0.5,z),Vector3(0.1,0.7,0.1))
		_mesh_part(st,"workbench",Vector3(-0.48,0.08,-0.48),Vector3(0.96,0.18,0.96))
		if kind == "sawmill":
			_mesh_part(st,"stone",Vector3(-0.08,0.26,-0.3),Vector3(0.16,0.38,0.6))
			_mesh_part(st,"log",Vector3(-0.4,0.26,0.15),Vector3(0.8,0.2,0.2))
		elif kind == "alchemy":
			_mesh_part(st,"stone",Vector3(-0.5,0.24,-0.5),Vector3(1,0.09,1))
			_mesh_part(st,"mouth",Vector3(-0.2,0.33,-0.2),Vector3(0.18,0.35,0.18))
			_mesh_part(st,"beacon",Vector3(0.15,0.33,0.1),Vector3(0.22,0.25,0.22))
		elif kind == "idea_catcher":
			_mesh_part(st,"planks",Vector3(-0.42,-0.45,-0.42),Vector3(0.84,0.6,0.84))
			# Левитирующее кольцо из 12 сегментов, с нитью в центре.
			for i in range(12):
				var a := float(i)*TAU/12.0
				_mesh_part(st,"drift_dream",Vector3(cos(a)*0.34-0.05,0.95+sin(a)*0.34,-0.05),Vector3(0.1,0.1,0.1))
			_mesh_part(st,"beacon",Vector3(-0.02,0.58,-0.02),Vector3(0.04,0.75,0.04))
	st.set_material(material())
	return st.commit()

static func _mesh_part(st: SurfaceTool, kind: String, mn: Vector3, size: Vector3) -> void:
	# Кубы используют тот же атлас/UV, без новых материалов.
	var mesh := cube_mesh(kind,size)
	var xf := Transform3D(Basis.IDENTITY,mn+size*0.5)
	st.append_from(mesh,0,xf)

static func tool_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := "stone" if kind.ends_with("2") else "planks"
	if kind.begins_with("pickaxe"):
		return _kenney_pickaxe_mesh(kind.ends_with("2"))

	else:
		_mesh_part(st,"log",Vector3(-0.04,-0.4,-0.04),Vector3(0.08,0.24,0.08))
		_mesh_part(st,"planks",Vector3(-0.18,-0.17,-0.06),Vector3(0.36,0.07,0.12))
		_mesh_part(st,head,Vector3(-0.065,-0.1,-0.035),Vector3(0.13,0.65,0.07))
		_mesh_part(st,head,Vector3(-0.045,0.55,-0.035),Vector3(0.09,0.06,0.07))
		_mesh_part(st,head,Vector3(-0.025,0.61,-0.035),Vector3(0.05,0.06,0.07))
	st.set_material(material())
	return st.commit()


# Ready-made CC0 geometry: Kenney / Survival Kit, original GLB kept in assets/models.
# Only UV/material adaptation and scale/grip translation; no hand-made replacement mesh.
static func _kenney_pickaxe_mesh(stone: bool) -> ArrayMesh:
	var source: PackedScene = load("res://assets/models/kenney/pickaxe.glb")
	var model := source.instantiate()
	var parts := model.find_children("*","MeshInstance3D",true,false)
	var source_mesh: Mesh = (model as MeshInstance3D).mesh if model is MeshInstance3D else parts[0].mesh
	var result := ArrayMesh.new()
	for surface in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs := PackedVector2Array()
		for i in range(vertices.size()):
			var v := vertices[i]
			uvs.append(Vector2((v.x+0.013)/0.026,(0.20-v.y)/0.20) if surface==0 else Vector2((v.x+0.09)/0.18,(0.24-v.y)/0.08))
			vertices[i] = (v-Vector3(0,0.07,0))*4.0
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var mat := StandardMaterial3D.new()
		var name := "handle" if surface==0 else ("stone_head" if stone else "wood_head")
		mat.albedo_texture = load("res://assets/textures/pickaxe_%s.png" % name)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.albedo_color = Color(0.83,0.83,0.83) if surface==0 else (Color(0.72,0.72,0.72) if stone else Color(0.82,0.82,0.82))
		mat.roughness = 1.0
		result.surface_set_material(surface,mat)
	model.free()
	return result
