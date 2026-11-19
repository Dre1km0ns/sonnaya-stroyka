extends Node3D
## v0.17 «Инструменты сновидца»: то, чего нет в Minecraft-выживании — Сон как редактор.
## Z/U — отмена/возврат, K — рамка, L/Shift+L — залить/очистить, X — зеркало,
## B — рамку в чертёж, N — выбрать чертёж, P — вставить у прицела, O — повернуть.
## Вся логика — в GameState (тестируется в смоуке); здесь ввод, контуры и строка статуса.

var player: Node = null
var dream_voxels: Node = null
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _label: Label
var _layer: CanvasLayer
var _aim_t := 0.0
var _drawn_sig := ""


func setup(p: Node, voxels: Node) -> void:
	player = p
	dream_voxels = voxels


func _ready() -> void:
	name = "DreamTools"
	add_to_group("dream_tools")
	_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	_lines.material_override = mat
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_label = Label.new()
	# v0.21 c2: справа внизу — слева строка налезала на чат и уведомления целей
	_label.anchor_left = 1.0; _label.anchor_right = 1.0; _label.anchor_top = 1.0; _label.anchor_bottom = 1.0
	_label.offset_left = -420; _label.offset_right = -16; _label.offset_top = -46; _label.offset_bottom = -18
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_layer.add_child(_label)
	# Мир Сна отключает обработку при пробуждении — прячем HUD по сигналу, а не в _process.
	GameState.world_changed.connect(func(d: bool) -> void:
		_label.visible = d; _lines.visible = d)
	_label.visible = GameState.is_dream(); _lines.visible = _label.visible


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func aim_cells() -> Dictionary:
	## {"place": клетка для установки, "hit": клетка блока под прицелом} или пусто.
	if player == null or not player.has_method("get_look_ray") or dream_voxels == null: return {}
	var aim: Dictionary = player.get_look_ray()
	if not aim.get("hit", false): return {}
	var place: Vector3i = dream_voxels.world_to_cell(aim["position"] + aim["normal"] * 0.51)
	return {"place": place, "hit": GameState.ray_cell(aim)}


func _process(delta: float) -> void:
	var dream := GameState.is_dream()
	_lines.visible = dream
	_label.visible = dream
	if not dream:
		return
	if not (GameState.ui_blocked() or GameState.transfer_ui_open):
		_handle_input()
	_aim_t -= delta
	if _aim_t <= 0.0 and GameState.blueprint_shown >= 0:
		_aim_t = 0.1
		var a := aim_cells()
		if not a.is_empty() and GameState.set_paste_origin(a.place):
			var ghost := get_tree().get_first_node_in_group("blueprint_ghost")
			if ghost: ghost.rebuild()
	_redraw()
	_label.text = status_text()


func _handle_input() -> void:
	var shift := Input.is_action_pressed("sprint")
	if _just("dream_undo"): GameState.dream_undo()
	if _just("dream_redo"): GameState.dream_redo()
	if _just("dream_frame"):
		var a := aim_cells()
		if a.is_empty(): GameState.set_hint("Наведи прицел на блок или землю Сна.", false)
		else: GameState.frame_mark(a.hit if shift else a.place)
	if _just("dream_fill"):
		if shift: GameState.dream_clear()
		else: GameState.dream_fill()
	if _just("dream_mirror"):
		var a := aim_cells()
		var at: Vector3i = a.get("place", Vector3i(player.global_position.floor()) if player else Vector3i.ZERO)
		GameState.cycle_mirror(at)
	if _just("dream_trial"): GameState.run_trial() # v0.19
	if _just("blueprint_rotate"): GameState.rotate_paste(-1 if shift else 1)
	if _just("blueprint_paste"):
		var a := aim_cells()
		if a.is_empty(): GameState.set_hint("Наведи прицел туда, куда вставить чертёж.", false)
		else: GameState.paste_blueprint(a.place)


func status_text() -> String:
	var parts: Array = []
	if GameState.frame_points == 1: parts.append("Рамка: угол A — K для угла B")
	elif GameState.frame_complete(): parts.append("Рамка %s (%d)" % [GameState.frame_dims_text(), GameState.frame_volume()])
	if GameState.mirror_axis != 0: parts.append("Зеркало %s" % ("X" if GameState.mirror_axis == 1 else "Z"))
	if GameState.blueprint_shown >= 0 and GameState.blueprint_shown < GameState.blueprints.size():
		parts.append("Чертёж «%s» %d°" % [GameState.blueprints[GameState.blueprint_shown].name, GameState.paste_rot * 90])
	if GameState.undo_size() > 0 or GameState.redo_size() > 0: # v0.21: пустой счётчик не занимает экран
		if not GameState.tutorial_focus() or GameState.tutorial_step_id() == "build":
			parts.append("Z — отмена (%d) · U — возврат (%d)" % [GameState.undo_size(), GameState.redo_size()])
	return "  ·  ".join(parts)


func _redraw() -> void:
	var sig := "%d|%s|%s|%d|%s" % [GameState.frame_points, GameState.frame_a, GameState.frame_b, GameState.mirror_axis, GameState.mirror_at]
	if sig == _drawn_sig: return
	_drawn_sig = sig
	_mesh.clear_surfaces()
	var any := false
	if GameState.frame_points >= 1:
		var lo: Vector3; var hi: Vector3
		if GameState.frame_complete():
			var b := GameState.frame_box(); lo = Vector3(b[0]); hi = Vector3(b[1]) + Vector3.ONE
		else:
			lo = Vector3(GameState.frame_a); hi = lo + Vector3.ONE
		_begin(any); any = true
		_box(lo - Vector3.ONE * 0.02, hi + Vector3.ONE * 0.02, Color(1.0, 0.85, 0.3))
	if GameState.mirror_axis != 0:
		_begin(any); any = true
		var m := GameState.mirror_at
		var col := Color(0.55, 0.8, 1.0)
		for i in range(-12, 13, 3):
			if GameState.mirror_axis == 1:
				var x := m.x + 0.5
				_seg(Vector3(x, m.y - 12, m.z + i), Vector3(x, m.y + 12, m.z + i), col)
				_seg(Vector3(x, m.y + i, m.z - 12), Vector3(x, m.y + i, m.z + 12), col)
			else:
				var z := m.z + 0.5
				_seg(Vector3(m.x + i, m.y - 12, z), Vector3(m.x + i, m.y + 12, z), col)
				_seg(Vector3(m.x - 12, m.y + i, z), Vector3(m.x + 12, m.y + i, z), col)
	if any: _mesh.surface_end()


func _begin(already: bool) -> void:
	if not already: _mesh.surface_begin(Mesh.PRIMITIVE_LINES)


func _seg(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c); _mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c); _mesh.surface_add_vertex(b)


func _box(lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		_seg(p[e[0]], p[e[1]], c)
