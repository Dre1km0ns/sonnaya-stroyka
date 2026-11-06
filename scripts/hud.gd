extends CanvasLayer
## HUD v0.4.2: хотбар, крафт-меню, без «макс.100».

@onready var world_label: Label = $Root/WorldLabel
@onready var clarity_bar: ProgressBar = $Root/ClarityBar
@onready var inv_label: Label = $Root/InvLabel
@onready var hint_label: Label = $Root/HintLabel
@onready var crosshair: Label = $Root/Crosshair

var _hotbar_slots: Array[ColorRect] = []
var _hotbar_labels: Array[Label] = []


func _ready() -> void:
	var menu_script: GDScript = load("res://scripts/craft_menu.gd")
	var menu: Control = menu_script.new()
	$Root.add_child(menu)
	_build_hotbar()
	GameState.world_changed.connect(_on_world)
	GameState.inventory_changed.connect(_refresh_inv)
	GameState.clarity_changed.connect(_on_clarity)
	GameState.hint_changed.connect(_on_hint)
	_on_world(GameState.is_dream())
	_refresh_inv()
	_on_clarity(GameState.clarity, GameState.CLARITY_MAX)
	_on_hint(GameState.last_hint)


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
		cell.custom_minimum_size = Vector2(84, 52)
		cell.color = Color(0.08, 0.08, 0.1, 0.72)
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


func _on_hint(text: String) -> void:
	hint_label.text = text
