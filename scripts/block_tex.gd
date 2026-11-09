extends RefCounted
## v0.6: общий атлас текстур блоков (assets/textures/atlas.png, генерирует tools/make_textures.py),
## материалы и кубы с правильными UV для всех блоков/дропов.

const TILES := ["grass_top", "grass_side", "dirt", "stone", "brick", "brick_mossy", "log_side", "log_top",
	"leaves", "sand", "water", "dream_top", "dream_side", "dream_dirt", "drift", "drift_dream",
	"drift_anchored", "mouth", "bench_top", "bench_side", "beacon", "planks", "dream_brick", "torch"]

static var _mat: ShaderMaterial = null
static var _water: Dictionary = {}
static var _cubes: Dictionary = {}
static var _idx: Dictionary = {}


static func tile(name: String) -> int:
	if _idx.is_empty():
		for i in range(TILES.size()):
			_idx[TILES[i]] = i
	return int(_idx.get(name, 2))


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
		"stone":
			return _all(tile("stone"))
		"ruin":
			if dream:
				return _all(tile("dream_brick"))
			return _all(tile("brick_mossy") if variant % 3 == 0 else tile("brick"))
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
