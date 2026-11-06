extends CanvasLayer
## HUD v0.4.5: хотбар с иконками кирки/меча, красная полоска босса.

@onready var world_label: Label = $Root/WorldLabel
@onready var clarity_bar: ProgressBar = $Root/ClarityBar
@onready var inv_label: Label = $Root/InvLabel
@onready var hint_label: Label = $Root/HintLabel
@onready var crosshair: Label = $Root/Crosshair

var _hotbar_slots: Array[ColorRect] = []
var _hotbar_labels: Array[Label] = []
var _hotbar_icons: Array[TextureRect] = []
var _icon_viewports: Dictionary = {}
var _boss_wrap: Control
var _boss_bar: ProgressBar
var _boss_label: Label


func _ready() -> void:
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	$Root.add_child(menu)
	_build_hotbar()
	_build_boss_bar()
	GameState.world_changed.connect(_on_world)
	GameState.inventory_changed.connect(_refresh_inv)
	GameState.clarity_changed.connect(_on_clarity)
	GameState.hint_changed.connect(_on_hint)
	_on_world(GameState.is_dream())
	_refresh_inv()
	_on_clarity(GameState.clarity, GameState.CLARITY_MAX)
	if hint_label:
		hint_label.visible = false
		hint_label.text = ""


func _build_hotbar() -> void:
	var root: Control = $Root
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -230.0
	bar.offset_right = 230.0
	bar.offset_top = -128.0
	bar.offset_bottom = -72.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	for i in range(GameState.ITEM_SLOT_COUNT):
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(84, 56)
		cell.color = Color(0.08, 0.08, 0.1, 0.72)
		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 18
		icon.offset_top = 2
		icon.offset_right = -18
		icon.offset_bottom = -18
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		cell.add_child(icon)
		var lab := Label.new()
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.anchor_right = 1.0
		lab.anchor_bottom = 1.0
		lab.offset_left = 4
		lab.offset_top = 4
		lab.offset_right = -4
		lab.offset_bottom = -4
		lab.add_theme_font_size_override("font_size", 12)
		cell.add_child(lab)
		bar.add_child(cell)
		_hotbar_slots.append(cell)
		_hotbar_labels.append(lab)
		_hotbar_icons.append(icon)


func _on_world(is_dream: bool) -> void:
	world_label.text = "СОН" if is_dream else "ЯВЬ"
	world_label.modulate = Color(0.75, 0.7, 1.0) if is_dream else Color(0.9, 0.8, 0.6)
	clarity_bar.visible = is_dream


func _on_clarity(value: float, max_value: float) -> void:
	clarity_bar.max_value = max_value
	clarity_bar.value = value


func _refresh_inv() -> void:
	inv_label.text = GameState.inventory_status_text()
	for i in range(_hotbar_slots.size()):
		var selected := i == GameState.selected_slot
		_hotbar_slots[i].color = Color(0.28, 0.24, 0.12, 0.88) if selected else Color(0.08, 0.08, 0.1, 0.72)
		var item: Dictionary = GameState.item_slots[i] if i < GameState.item_slots.size() else {}
		var id := str(item.get("id", ""))
		var title := str(item.get("name", ""))
		if title == "":
			title = "пусто"
		var count := GameState.slot_display_count(i)
		var key_hint := str(i + 1) if i < 2 else str(i + 1)
		if i >= 2:
			key_hint = str(i + 1)
		_hotbar_labels[i].text = "[%s] %s\nx%d" % [key_hint, title, count]
		if i < _hotbar_icons.size():
			var icon: TextureRect = _hotbar_icons[i]
			if id == "pickaxe" or id == "sword":
				icon.texture = _tool_icon_texture(id)
				icon.visible = true
				_hotbar_labels[i].offset_top = 30
			else:
				icon.texture = null
				icon.visible = false
				_hotbar_labels[i].offset_top = 4


func _on_hint(_text: String) -> void:
	if hint_label:
		hint_label.visible = false
		hint_label.text = ""


func _build_boss_bar() -> void:
	var root: Control = $Root
	_boss_wrap = Control.new()
	_boss_wrap.name = "BossBarWrap"
	_boss_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_wrap.offset_left = 180
	_boss_wrap.offset_right = -180
	_boss_wrap.offset_top = 14
	_boss_wrap.offset_bottom = 70
	_boss_wrap.visible = false
	root.add_child(_boss_wrap)
	_boss_label = Label.new()
	_boss_label.text = "Мать блоков"
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_label.offset_bottom = 22
	_boss_label.add_theme_font_size_override("font_size", 18)
	_boss_wrap.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.max_value = 1000
	_boss_bar.value = 1000
	_boss_bar.show_percentage = false
	_boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar.offset_top = 24
	_boss_bar.offset_bottom = 48
	_boss_bar.custom_minimum_size = Vector2(0, 24)
	_style_boss_bar(_boss_bar)
	_boss_wrap.add_child(_boss_bar)


func _process(_delta: float) -> void:
	if _boss_wrap == null:
		return
	var bosses: Array = get_tree().get_nodes_in_group("block_mother") if get_tree() else []
	var live: Node = null
	for b in bosses:
		if is_instance_valid(b) and int(b.get("hp")) > 0:
			live = b
			break
	if live == null:
		_boss_wrap.visible = false
		return
	_boss_wrap.visible = true
	var hp: int = int(live.get("hp"))
	var mx: int = int(live.get("max_hp"))
	_boss_bar.max_value = mx
	_boss_bar.value = hp
	_boss_label.text = "Мать блоков   %d / %d" % [hp, mx]


func _style_boss_bar(bar: ProgressBar) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.90, 0.09, 0.11, 1.0)
	fill.set_corner_radius_all(4)
	fill.content_margin_left = 2
	fill.content_margin_right = 2
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.04, 0.05, 0.94)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("fg", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("bg", bg)
	bar.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.modulate = Color.WHITE


func boss_bar_fill_is_red() -> bool:
	if _boss_bar == null:
		return false
	var sb: StyleBox = _boss_bar.get_theme_stylebox("fill")
	if sb == null or not (sb is StyleBoxFlat):
		return false
	var c: Color = (sb as StyleBoxFlat).bg_color
	return c.r >= 0.75 and c.g <= 0.25 and c.b <= 0.25


func _tool_icon_texture(id: String) -> Texture2D:
	if _icon_viewports.has(id):
		return (_icon_viewports[id] as SubViewport).get_texture()
	var path := "res://assets/models/%s.glb" % id
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return null
	var res = load(path)
	if res == null or not (res is PackedScene):
		return null
	var vp := SubViewport.new()
	vp.name = "IconVP_%s" % id
	vp.size = Vector2i(80, 80)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.disable_3d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.9, 0.7, 1.4)
	cam.look_at(Vector3(0, 0.15, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	light.light_energy = 1.15
	world.add_child(light)
	var model: Node3D = (res as PackedScene).instantiate()
	model.scale = Vector3.ONE * (0.28 if id == "pickaxe" else 0.09)
	model.rotation_degrees = Vector3(-25, 40, 12) if id == "pickaxe" else Vector3(-20, 35, 8)
	world.add_child(model)
	_icon_viewports[id] = vp
	return vp.get_texture()

