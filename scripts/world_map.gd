extends Control
## v0.25 (t143u): карта мира слева сверху (на месте панели вех; вехи — под ней).
## Рельеф Яви вокруг игрока (озёра, рощи, холмы, постройки), сам игрок — стрелка, другие игроки в сети —
## цветные точки с именем, живые боссы — значки их лиц. Tab — скрыть или показать, F2 — вехи (переназначаются).
const SIZE := 184.0
const CELLS := 92            # пикселей карты по стороне
const METERS_PER_CELL := 2.0
const SUITS := [Color(0.3, 0.5, 0.85), Color(0.85, 0.35, 0.3), Color(0.35, 0.75, 0.4), Color(0.8, 0.65, 0.25)]

var shown := true
var goals_shown := true
var _img: Image
var _tex: ImageTexture
var _center := Vector2i(999999, 999999)
var _row := 0
var _hint: Label
var _cm: Node
var bosses_drawn := 0
var players_drawn := 0


func _ready() -> void:
	name = "WorldMap"
	add_to_group("world_map")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(10, 136)
	size = Vector2(SIZE, SIZE + 18)
	_img = Image.create(CELLS, CELLS, false, Image.FORMAT_RGB8)
	_img.fill(Color(0.12, 0.16, 0.12))
	_tex = ImageTexture.create_from_image(_img)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 3)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var gs := get_node_or_null("/root/GameSettings")
	if gs:
		shown = bool(gs.get("show_map")) if "show_map" in gs else true
		goals_shown = bool(gs.get("show_goals")) if "show_goals" in gs else true
	_layout()


func _key(action: String, fallback: String) -> String:
	var gs := get_node_or_null("/root/GameSettings")
	return str(gs.call("key_label", action)) if gs and gs.has_method("key_label") else fallback


func _layout() -> void:
	_hint.text = ("%s — скрыть карту" % _key("world_map", "Tab")) if shown else ("%s — карта" % _key("world_map", "Tab"))
	if not goals_shown:
		_hint.text += "   %s — вехи" % _key("goals_panel", "F2")
	_hint.position = Vector2(2, SIZE + 1) if shown else Vector2(2, 0)
	var op := get_tree().get_first_node_in_group("objective_panel") as Control if is_inside_tree() else null
	if op:
		op.position = Vector2(10, 136 + (SIZE + 22 if shown else 18))
		op.set_meta("goals_hidden", not goals_shown)
	queue_redraw()


func toggle_map() -> void:
	shown = not shown
	_save()
	_layout()


func toggle_goals() -> void:
	goals_shown = not goals_shown
	_save()
	_layout()


func _save() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs and "show_map" in gs:
		gs.set("show_map", shown); gs.set("show_goals", goals_shown)
		if gs.has_method("save_settings"): gs.call("save_settings")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if GameState.ui_blocked():
		return
	if event.is_action("world_map"):
		toggle_map(); get_viewport().set_input_as_handled()
	elif event.is_action("goals_panel"):
		toggle_goals(); get_viewport().set_input_as_handled()


func _wake_cm() -> Node:
	if _cm and is_instance_valid(_cm):
		return _cm
	for cm in get_tree().get_nodes_in_group("chunk_manager"):
		if not bool(cm.get("is_dream_layer")):
			_cm = cm
			return cm
	return null


func _cell_color(cm: Node, wx: int, wz: int) -> Color:
	if cm.has_method("is_world_in_lake") and bool(cm.call("is_world_in_lake", Vector3(wx + 0.5, 0, wz + 0.5))):
		return Color(0.22, 0.42, 0.78)
	var h := int(cm.call("height_at", wx, wz)) if cm.has_method("height_at") else 0
	for y in [h + 2, h + 1]:
		if GameState.wake_blocks.has(Vector3i(wx, y, wz)):
			return Color(0.72, 0.55, 0.36)
	var c := Color(0.3, 0.55, 0.28)
	if cm.has_method("forest_kind") and cm.has_method("world_to_chunk"):
		var fk := str(cm.call("forest_kind", cm.call("world_to_chunk", Vector3(wx, 0, wz))))
		if fk == "grove": c = Color(0.16, 0.38, 0.17)
		elif fk == "clearing": c = Color(0.45, 0.62, 0.32)
	return c.lightened(clampf(float(h) * 0.07, 0.0, 0.45))


func _process(_delta: float) -> void:
	var blocked := GameState.ui_blocked() or GameState.transfer_ui_open or GameState.tutorial_focus() or GameState.is_dream()
	visible = not blocked
	var op := get_tree().get_first_node_in_group("objective_panel") as Control
	if op and not goals_shown:
		op.visible = false
	if not visible or not shown:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var cm := _wake_cm()
	if p == null or cm == null:
		return
	var c := Vector2i(floori(p.global_position.x / METERS_PER_CELL), floori(p.global_position.z / METERS_PER_CELL))
	if (c - _center).length() > 6:
		_center = c
		_row = 0
	# по 6 строк за кадр — полная карта за ~15 кадров
	for _i in 6:
		if _row >= CELLS:
			break
		for x in CELLS:
			var wx := int((_center.x - CELLS / 2 + x) * METERS_PER_CELL)
			var wz := int((_center.y - CELLS / 2 + _row) * METERS_PER_CELL)
			_img.set_pixel(x, _row, _cell_color(cm, wx, wz))
		_row += 1
	if _row >= CELLS and Engine.get_process_frames() % 90 == 0:
		_row = 0   # раз в полторы секунды — освежить (постройки, сломанное)
	_tex.update(_img)
	queue_redraw()


func world_to_map(pos: Vector3) -> Vector2:
	var k := SIZE / float(CELLS)
	return Vector2((pos.x / METERS_PER_CELL - (_center.x - CELLS / 2)) * k, (pos.z / METERS_PER_CELL - (_center.y - CELLS / 2)) * k)


func _draw() -> void:
	if not shown:
		return
	var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_rect(r.grow(3), Color(0.05, 0.04, 0.1, 0.86))
	draw_texture_rect(_tex, r, false)
	draw_rect(r.grow(1), Color(0.55, 0.6, 1.0, 0.7), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(SIZE * 0.5 - 4, 12), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	players_drawn = 0
	bosses_drawn = 0
	for av in get_tree().get_nodes_in_group("remote_player"):
		var mp := world_to_map((av as Node3D).global_position)
		if r.has_point(mp):
			var col: Color = SUITS[int(av.get("idx")) % SUITS.size()] if "idx" in av else Color(0.4, 0.8, 1)
			draw_circle(mp, 4.5, Color(0, 0, 0))
			draw_circle(mp, 3.5, col)
			draw_string(ThemeDB.fallback_font, mp + Vector2(6, 4), str(av.get("display_name")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))
			players_drawn += 1
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or not (b is Node3D) or int(b.get("hp") if b.get("hp") != null else 0) <= 0:
			continue
		var at: Vector3 = b.call("hit_center") if b.has_method("hit_center") else (b as Node3D).global_position
		var mp2 := world_to_map(at)
		mp2 = mp2.clamp(Vector2(8, 8), Vector2(SIZE - 8, SIZE - 8))   # за краем — у края карты
		_draw_face(mp2, _boss_kind(b))
		bosses_drawn += 1
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		var mp3 := world_to_map(p.global_position)
		var fwd := -p.global_transform.basis.z
		var ang := atan2(fwd.z, fwd.x)
		var pts := PackedVector2Array([mp3 + Vector2(cos(ang), sin(ang)) * 7.0, mp3 + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 5.0, mp3 + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 5.0])
		if not (mp3.is_finite() and is_finite(ang)): return
		draw_primitive(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), PackedVector2Array())   # треугольник без триангуляции
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0), 1.2)


func _boss_kind(b: Node) -> String:
	var path := str(b.get_script().resource_path.get_file().get_basename()) if b.get_script() else ""
	if path == "net_proxy": path = str(b.get("kind"))
	if path == "boss_burger" and int(b.get("phase")) >= 2: return "anton"
	return path


func _draw_face(at: Vector2, kind: String) -> void:
	## Значки лиц боссов: Мать — зелёная клякса, Анаконда — змеиная голова, Бургер — булка, Антон — клоун.
	var base := Color(0.4, 0.75, 0.35); var eye := Color(0.05, 0.05, 0.05); var extra := ""
	match kind:
		"block_mother": base = Color(0.45, 0.8, 0.4)
		"boss_anaconda": base = Color(0.35, 0.55, 0.3); eye = Color(1, 0.65, 0.1); extra = "fangs"
		"boss_burger": base = Color(0.9, 0.6, 0.25); extra = "bun"
		"anton": base = Color(0.95, 0.78, 0.62); extra = "clown"
	draw_circle(at, 9.5, Color(0, 0, 0))
	draw_circle(at, 8.0, base)
	if extra == "bun":
		draw_rect(Rect2(at + Vector2(-8, 1), Vector2(16, 3)), Color(0.4, 0.22, 0.12))
		draw_rect(Rect2(at + Vector2(-8, 4), Vector2(16, 1.5)), Color(0.4, 0.8, 0.3))
	draw_circle(at + Vector2(-3, -2), 1.6, eye)
	draw_circle(at + Vector2(3, -2), 1.6, eye)
	if extra == "clown":
		draw_circle(at + Vector2(0, 1), 2.2, Color(1, 0.1, 0.1))
		draw_circle(at + Vector2(-6, -5), 2.6, Color(1, 0.45, 0.1))
		draw_circle(at + Vector2(6, -5), 2.6, Color(1, 0.45, 0.1))
	elif extra == "fangs":
		draw_line(at + Vector2(-2, 3), at + Vector2(-1.5, 6), Color(1, 1, 1), 1.5)
		draw_line(at + Vector2(2, 3), at + Vector2(1.5, 6), Color(1, 1, 1), 1.5)
	else:
		draw_line(at + Vector2(-3, 3.5), at + Vector2(3, 3.5), eye, 1.5)
