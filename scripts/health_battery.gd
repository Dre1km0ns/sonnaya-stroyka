extends Control
## v0.12: горизонтальная полоса HP слева снизу. Числа «текущее / максимум»,
## плавная заливка, отложенный след урона, разные вспышки урона и лечения,
## ненавязчивый пульс при критическом HP. Логическое HP не хранится здесь:
## полоса читает значения, которые HUD передаёт из GameState.player_hp.

const FILL_SPEED := 6.5
const TRAIL_DELAY := 0.35
const TRAIL_SPEED := 2.4
const CRIT_FRACTION := 0.25

var label: Label
var regen := false
var _shown_hp: int = 100
var _shown_max: int = 100
var _fill: float = 1.0
var _trail: float = 1.0
var _trail_delay: float = 0.0
var _flash := 0.0
var _flash_heal := 0.0
var _crit_pulse := 0.0
var _dead_visual := false


func _ready() -> void:
	name = "HealthBattery"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.name = "HPText"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.94))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_refresh_label()


func set_hp(v: int, m: int) -> void:
	## Единственный вход: HUD передаёт GameState.player_hp / PLAYER_MAX_HP (или сигнал player_hp_changed).
	var new_max := maxi(1, m)
	var new_hp := clampi(v, 0, new_max)
	if new_max != _shown_max:
		# Смена максимума: пересчитать доли, след не должен «торчать» выше новой шкалы.
		var old_frac := float(_shown_hp) / float(maxi(1, _shown_max))
		_shown_max = new_max
		_fill = clampf(old_frac, 0.0, 1.0)
		_trail = minf(_trail, 1.0)
	if new_hp < _shown_hp:
		_flash = 0.42
		_flash_heal = 0.0
		_trail_delay = TRAIL_DELAY
		if _trail < _fill:
			_trail = _fill
	elif new_hp > _shown_hp:
		_flash_heal = 0.45
		_flash = 0.0
		# Лечение: след сразу догоняет, без «раны назад».
		_trail_delay = 0.0
	if _shown_hp <= 0 and new_hp > 0:
		# Возрождение: заливка растёт с нуля.
		_fill = 0.0
		_trail = 0.0
		_dead_visual = false
	_shown_hp = new_hp
	_shown_max = new_max
	if _shown_hp <= 0:
		_dead_visual = true
	_refresh_label()
	queue_redraw()


func _refresh_label() -> void:
	if label:
		label.text = "%d / %d" % [_shown_hp, _shown_max]


func fraction() -> float:
	return float(_shown_hp) / float(maxi(1, _shown_max))


func visual_fraction() -> float:
	return _fill


func trail_fraction() -> float:
	return _trail


func fill_color() -> Color:
	var f := fraction()
	if f <= 0.0:
		return Color(0.28, 0.2, 0.2)
	if f > 0.5:
		return Color(0.36, 0.78, 0.48)
	if f > CRIT_FRACTION:
		return Color(0.92, 0.72, 0.28)
	return Color(0.9, 0.32, 0.28)


func _process(delta: float) -> void:
	var target := fraction()
	_fill = move_toward(_fill, target, delta * FILL_SPEED)
	if _shown_hp < int(round(_trail * float(_shown_max))) or _trail > target:
		if _trail_delay > 0.0:
			_trail_delay = maxf(0.0, _trail_delay - delta)
		else:
			_trail = move_toward(_trail, _fill, delta * TRAIL_SPEED)
	else:
		_trail = maxf(_trail, _fill)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if _flash_heal > 0.0:
		_flash_heal = maxf(0.0, _flash_heal - delta)
	if fraction() > 0.0 and fraction() <= CRIT_FRACTION:
		_crit_pulse += delta * 3.2
	else:
		_crit_pulse = 0.0
	queue_redraw()


func _draw() -> void:
	var body := Rect2(Vector2.ZERO, size)
	var r := 5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.08, 0.78)
	bg.border_color = Color(0.78, 0.8, 0.74, 0.7)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(r)
	draw_style_box(bg, body)
	var inner := body.grow(-3.5)
	# Отложенный след урона (тусклая полоса позади основной).
	if _trail > _fill + 0.004:
		var trail := StyleBoxFlat.new()
		trail.bg_color = Color(0.72, 0.22, 0.18, 0.7)
		trail.set_corner_radius_all(r - 2)
		draw_style_box(trail, Rect2(inner.position, Vector2(maxf(2.0, inner.size.x * _trail), inner.size.y)))
	if _fill > 0.0:
		var fill := StyleBoxFlat.new()
		var c := fill_color()
		if _flash > 0.0:
			c = c.lerp(Color(1.0, 0.55, 0.45), clampf(_flash * 2.0, 0.0, 1.0))
		elif _flash_heal > 0.0:
			c = c.lerp(Color(0.55, 1.0, 0.7), clampf(_flash_heal * 1.8, 0.0, 1.0))
		if _crit_pulse > 0.0:
			var k := 0.5 + 0.5 * sin(_crit_pulse)
			c = c.lerp(Color(1.0, 0.35, 0.3), 0.18 * k)
		fill.bg_color = c
		fill.set_corner_radius_all(r - 2)
		draw_style_box(fill, Rect2(inner.position, Vector2(maxf(3.0, inner.size.x * _fill), inner.size.y)))
	if _dead_visual and _shown_hp <= 0:
		# Тусклая рамка без заливки — смерть, без кричащего текста.
		pass
