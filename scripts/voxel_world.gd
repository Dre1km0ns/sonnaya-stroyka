extends Node3D
## Ordinary blocks: hidden-face chunk meshes + merged X collision regions.
## Interactives: one cached mesh/body per root. Dirty cells coalesce until flush.
@export var is_dream_layer := false
@export var block_size := 1.0
const BlockTex := preload("res://scripts/block_tex.gd")
const SPECIAL := ["torch","beacon","bed","workbench","lathe","sawmill","alchemy","idea_catcher","chest","door"]
const PARTS := ["bed_foot","door_top","catcher_top"]
var _meshes: Dictionary = {}
var _bodies: Dictionary = {}
var _data: Dictionary = {}
var _ordinary: Dictionary = {}
var _placed_chunks: Dictionary = {}
var _dirty_cells: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var sync_count := 0
var mesh_rebuild_count := 0
var cells_changed := 0
var flush_usec := 0
static var _shapes: Dictionary = {}
func _ready() -> void:
	add_to_group("voxel_world")
	GameState.world_changed.connect(_on_world)
	GameState.placed_cells_changed.connect(_changed)
	sync_from_state()
func _on_world(_dream: bool) -> void:
	if _active() or (is_dream_layer and GameState.dream_blocks.is_empty()): sync_from_state()
func _active() -> bool:
	return GameState.is_dream()==is_dream_layer
func _state_at(c: Vector3i) -> Dictionary:
	if not is_dream_layer: return GameState.wake_blocks.get(c,{})
	if GameState.dream_blocks.has(c): return GameState.dream_blocks[c]
	var d: Dictionary = GameState.wake_blocks.get(c,{})
	return d if d.get("kind","") in ["idea_catcher","catcher_top"] else {}
func _changed(dream: bool,cells: Array) -> void:
	for c in cells:
		if dream==is_dream_layer or (is_dream_layer and (_data.get(c,{}).get("kind","") in ["idea_catcher","catcher_top"] or GameState.wake_blocks.get(c,{}).get("kind","") in ["idea_catcher","catcher_top"])):
			if _state_at(c).get("kind","") in SPECIAL or _data.get(c,{}).get("kind","") in SPECIAL:
				_apply_cell(c) # interactions update immediately, no delayed physics catch-up
			else: _dirty_cells[c] = true
func _process(_dt: float) -> void:
	if _active(): flush_dirty(3000)
func _rebuild_from_state() -> void:
	# Compatibility/resync entry point. Never destroy unchanged objects.
	sync_from_state()
func sync_from_state() -> void:
	sync_count += 1
	var keys := {}
	for c in _data: keys[c]=true
	var source: Dictionary = GameState.dream_blocks if is_dream_layer else GameState.wake_blocks
	for c in source: keys[c]=true
	if is_dream_layer:
		for c in GameState.wake_blocks:
			if GameState.wake_blocks[c].get("kind","") in ["idea_catcher","catcher_top"]: keys[c]=true
	for c in keys: _dirty_cells[c]=true
	flush_dirty()
func _clear_all() -> void:
	for c in _meshes.keys(): _remove_visual(c)
	for root in _placed_chunks.values(): root.queue_free()
	_placed_chunks.clear();_ordinary.clear();_data.clear();_dirty_cells.clear();_dirty_chunks.clear()
func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c)*block_size+Vector3.ONE*block_size*0.5
func world_to_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x/block_size),floori(p.y/block_size),floori(p.z/block_size))
func _chunk(c: Vector3i) -> Vector2i:
	return Vector2i(floori(float(c.x)/16),floori(float(c.z)/16))
func _mark(c: Vector3i) -> void:
	var ck := _chunk(c);_dirty_chunks[ck]=true
	for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var nb := _chunk(c+d)
		if nb!=ck and _ordinary.has(nb): _dirty_chunks[nb]=true
func has_block(c: Vector3i) -> bool:
	return _data.has(c) or not _state_at(c).is_empty()
func add_block(c: Vector3i,_d: Dictionary) -> void:
	_dirty_cells[c]=true
func refresh_block(c: Vector3i,_d: Dictionary) -> void:
	sync_cells([c])
func remove_block(c: Vector3i) -> void:
	# Called after GameState mutation; consult old cache to remove multi-cell roots.
	sync_cells([c])
func sync_cells(cells: Array) -> void:
	for c in cells:
		_dirty_cells[c]=true
		var old: Dictionary = _data.get(c,{})
		if old.has("root"): _dirty_cells[GameState.key_cell(old.root)]=true
		var now := _state_at(c)
		if now.has("root"): _dirty_cells[GameState.key_cell(now.root)]=true
		for kind in [old.get("kind",""),now.get("kind","")]:
			if GameState.shape_part(kind)!="": _dirty_cells[c+GameState.part_offset(kind)]=true
	flush_dirty(3000)
func _remove_visual(c: Vector3i) -> void:
	if _meshes.has(c):
		_meshes[c].queue_free();_meshes.erase(c)
	if _bodies.has(c):
		_bodies[c].collision_layer=0;_bodies[c].queue_free();_bodies.erase(c)
	var ck := _chunk(c)
	if _ordinary.has(ck) and _ordinary[ck].erase(c): _mark(c)
func _apply_cell(c: Vector3i) -> void:
	var d := _state_at(c)
	if d==_data.get(c,{}): return
	if d.get("kind","")=="door" and _data.get(c,{}).get("kind","")=="door" and _bodies.has(c):
		_data[c]=d.duplicate(true)
		_meshes[c].transform=door_transform(c,d);_bodies[c].transform=_meshes[c].transform
		cells_changed+=1;return
	_remove_visual(c)
	_data.erase(c)
	if d.is_empty(): return
	_data[c]=d.duplicate(true);cells_changed+=1
	var kind: String = d.get("kind","drift")
	if kind in PARTS: return
	if kind in SPECIAL:
		_spawn_visual(c,d)
	else:
		var ck := _chunk(c)
		if not _ordinary.has(ck): _ordinary[ck]={}
		_ordinary[ck][c]=d.duplicate(true);_mark(c)
func flush_dirty(budget_us: int=0) -> void:
	var start := Time.get_ticks_usec()
	for c in _dirty_cells.keys(): _apply_cell(c)
	_dirty_cells.clear()
	for ck in _dirty_chunks.keys():
		_build_placed_chunk(ck);_dirty_chunks.erase(ck)
		if budget_us>0 and Time.get_ticks_usec()-start>=budget_us: break
	flush_usec=Time.get_ticks_usec()-start
func _build_placed_chunk(ck: Vector2i) -> void:
	if _placed_chunks.has(ck):
		var old: Node3D = _placed_chunks[ck]
		for child in old.get_children():
			if child is CollisionObject3D: child.collision_layer=0
		old.queue_free();_placed_chunks.erase(ck)
	var cells: Dictionary = _ordinary.get(ck,{})
	if cells.is_empty(): _ordinary.erase(ck);return
	var base := Vector3(ck.x*16,0,ck.y*16)
	var stream := BlockTex.new_stream()
	for c in cells:
		var d: Dictionary = cells[c]
		var kind: String = d.get("kind","drift")
		if kind=="drift" and is_dream_layer: kind="drift_anchored" if d.get("anchored",false) else "drift_dream"
		if d.get("mutant",false): kind="mouth"
		var mask := 0
		for i in range(6):
			var nb: Vector3i = c+Vector3i(BlockTex.FACES[i][0])
			var nd: Dictionary = _data.get(nb,{})
			if not nd.is_empty() and nd.get("kind","") not in SPECIAL+PARTS: mask|=1<<i
		var tint := Color(0.6,1,0.85) if is_dream_layer and d.get("anchored",false) else Color.WHITE
		BlockTex.emit_box(stream,Vector3(c)-base,Vector3.ONE,tint,mask,BlockTex.faces_for(kind))
	var root := Node3D.new();root.position=base;root.name="Placed_%d_%d"%[ck.x,ck.y];add_child(root)
	var mesh := MeshInstance3D.new();mesh.mesh=BlockTex.stream_to_mesh(stream);root.add_child(mesh)
	var body := StaticBody3D.new();body.collision_layer=4 if _active() else 0;body.collision_mask=0
	body.set_meta("_saved_layer",4);body.set_meta("placed_chunk",ck);body.set_meta("is_dream",is_dream_layer);root.add_child(body)
	# Merge contiguous horizontal solids into collision regions; no per-cube Node.
	var visited := {}
	for c in cells:
		if visited.has(c): continue
		var low: Vector3i=c
		while cells.has(low+Vector3i.LEFT) and not visited.has(low+Vector3i.LEFT): low+=Vector3i.LEFT
		var length := 0
		while cells.has(low+Vector3i.RIGHT*length): visited[low+Vector3i.RIGHT*length]=true;length+=1
		var size := Vector3(length,1,1)
		if not _shapes.has(size):
			var shape := BoxShape3D.new();shape.size=size;_shapes[size]=shape
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_set_transform(owner_id,Transform3D(Basis.IDENTITY,Vector3(low)-base+Vector3(length*0.5,0.5,0.5)))
		body.shape_owner_add_shape(owner_id,_shapes[size])
	_placed_chunks[ck]=root;mesh_rebuild_count+=1

func _spawn_visual(cell: Vector3i, data: Dictionary) -> void:
	## v0.6: пиксельные текстуры из общего атласа (BlockTex) вместо однотонных цветов.
	var kind: String = str(data.get("kind", "drift"))
	if kind in ["bed_foot", "door_top", "catcher_top"]:
		return
	var mi := MeshInstance3D.new()
	var anchored: bool = bool(data.get("anchored", false))
	var mutant: bool = bool(data.get("mutant", false)) or kind == "mouth"
	var tex_kind := kind
	var size := Vector3.ONE * (block_size * 0.98)
	var tint := Color(1, 1, 1)
	if kind == "torch":
		size = Vector3(0.12, 0.72, 0.12)
	elif kind == "beacon":
		size = Vector3(0.8, 0.5, 0.8)
	elif kind == "drift" or kind == "":
		if is_dream_layer:
			tex_kind = "drift_anchored" if anchored else "drift_dream"
		elif mutant:
			tex_kind = "mouth"
	elif mutant:
		tex_kind = "mouth"
	if kind == "torch":
		mi.mesh = BlockTex.torch_mesh()
	elif kind == "bed":
		mi.mesh = BlockTex.bed_mesh(1.0 if data.get("legacy_compact",false) else 2.0)
	elif kind in ["lathe", "sawmill", "alchemy", "idea_catcher", "chest", "door"]:
		mi.mesh = BlockTex.station_mesh(kind)
	else:
		mi.mesh = BlockTex.cube_mesh(tex_kind, size, is_dream_layer, tint)
	mi.position = cell_to_world(cell)
	if kind == "bed" and not data.get("legacy_compact",false):
		mi.position.z += 0.5
	if kind == "door": mi.transform=door_transform(cell,data)
	add_child(mi)
	_meshes[cell] = mi
	if kind == "chest":
		# v0.11: крышка на шарнире — анимируется при открытии сундука (set_chest_open).
		var pivot := Node3D.new()
		pivot.name = "LidPivot"
		pivot.position = BlockTex.CHEST_HINGE
		mi.add_child(pivot)
		var lid := MeshInstance3D.new()
		lid.name = "Lid"
		lid.mesh = BlockTex.chest_lid_mesh()
		pivot.add_child(lid)
	if kind == "torch":
		# v0.11.1: общий меш пламени (кешируется в BlockTex) вместо сферы.
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		flame.mesh = BlockTex.torch_flame_mesh()
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(flame)
		var light := OmniLight3D.new()
		light.name = "TorchLight"
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 1.55
		light.omni_range = 8.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.position = Vector3(0, 0.45, 0)
		mi.add_child(light)
	if kind == "beacon":
		mi.position = cell_to_world(cell) + Vector3(0, -0.25, 0)
		var core := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = 0.22
		cs.height = 0.44
		core.mesh = cs
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.45, 0.95, 1.0)
		cmat.emission_enabled = true
		cmat.emission = Color(0.35, 0.9, 1.0)
		cmat.emission_energy_multiplier = 2.0
		core.material_override = cmat
		core.position = Vector3(0, 0.45, 0)
		mi.add_child(core)
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		var bm := CylinderMesh.new()
		bm.top_radius = 0.18
		bm.bottom_radius = 0.18
		bm.height = 48.0
		bm.radial_segments = 8
		bm.rings = 1
		beam.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(0.45, 0.95, 1.0, 0.35)
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bmat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, 24.5, 0)
		mi.add_child(beam)
	if kind == "workbench":
		# Столешница — дочерний узел блока: враг/кирка снимают верстак целиком.
		var top := MeshInstance3D.new()
		top.mesh = BlockTex.cube_mesh("workbench", Vector3(1.16, 0.14, 1.16))
		top.position = Vector3(0, 0.50, 0)
		mi.add_child(top)

	var body := StaticBody3D.new()
	body.collision_layer = 4 if _active() else 0 # blocks
	body.set_meta("_saved_layer",4)
	body.collision_mask = 0
	body.position = mi.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if kind == "torch":
		body.collision_layer = 32 if _active() else 0
		body.set_meta("_saved_layer",32)
		shape.size = Vector3(0.28,0.85,0.28)
	elif kind == "workbench":
		shape.size = Vector3(block_size, block_size * 1.2, block_size)
		body.position = mi.position + Vector3(0, 0.10, 0)
	elif kind == "bed":
		shape.size = Vector3(block_size,0.56,block_size*(1.0 if data.get("legacy_compact",false) else 2.0))
		body.position = mi.position + Vector3(0, -0.22, 0)
	elif kind == "door":
		shape.size = Vector3(1,2,0.125)
		if not _shapes.has(shape.size): _shapes[shape.size]=shape
		shape=_shapes[shape.size]
		body.rotation = mi.rotation
		# The opened leaf remains physical and ray-selectable at its hinged position.
	elif kind == "idea_catcher":
		shape.size = Vector3(0.9, 2.0, 0.9)
		body.position.y += 0.5
	else:
		shape.size = Vector3.ONE * block_size
	col.shape = shape
	body.add_child(col)
	body.set_meta("voxel_cell", cell)
	body.set_meta("is_dream", is_dream_layer)
	body.set_meta("kind", kind)
	if kind == "workbench":
		body.add_to_group("workbench")
	if kind == "torch":
		body.add_to_group("torch")
	if kind == "bed":
		body.add_to_group("bed")
		body.add_to_group("placed_bed")
	if kind == "lathe":
		body.add_to_group("lathe")
	if kind == "beacon":
		body.add_to_group("beacon")
	add_child(body)
	_bodies[cell] = body

static func door_transform(cell: Vector3i,data: Dictionary) -> Transform3D:
	var facing:=int(data.get("facing",0))*PI/2.0
	var basis:=Basis(Vector3.UP,facing)
	var center:=Vector3(cell)+Vector3(0.5,1,0.5)+basis*Vector3(0,0,0.5)
	if data.get("open",false):
		var side: float=1.0 if data.get("hinge_right",false) else -1.0
		var hinge:=center+basis*Vector3(side*0.5,0,0)
		basis=Basis(Vector3.UP,facing-side*PI/2.0)
		center=hinge-basis*Vector3(side*0.5,0,0)
	return Transform3D(basis,center)


const CHEST_OPEN_DEG := -72.0
const CHEST_ANIM_SEC := 0.22


func chest_lid(cell: Vector3i) -> Node3D:
	var mi: Node = _meshes.get(cell)
	if mi == null or not is_instance_valid(mi):
		return null
	return mi.get_node_or_null("LidPivot") as Node3D


func set_chest_open(cell: Vector3i, open: bool, animate: bool = true) -> bool:
	var pivot := chest_lid(cell)
	if pivot == null:
		return false
	var target := deg_to_rad(CHEST_OPEN_DEG) if open else 0.0
	if pivot.has_meta("tween"):
		var old: Tween = pivot.get_meta("tween")
		if old and old.is_valid(): old.kill()
	if not animate or not is_inside_tree():
		pivot.rotation.x = target
		return true
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "rotation:x", target, CHEST_ANIM_SEC).set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pivot.set_meta("tween", tw)
	return true
