extends Control
## v0.15: обратная связь боя поверх HUD.
## 1) Хит-маркер у прицела: попал / ядро / отскок / ядро захлопнулось / иммунитет / добил.
## 2) Дуга направления урона: красная дуга вокруг прицела в сторону атакующего.
## Перерисовка только пока что-то анимируется (как полоса HP в v0.14).

const MARK_TIME := 0.28
const ARC_TIME := 1.1
const ARC_RADIUS := 86.0
const ARC_SPAN := 0.55          # радиан
const MARK_STYLE := {
	"hit": [Color(1, 1, 1), 1.0],
	"core": [Color(1.0, 0.82, 0.25), 1.25],
	"kill": [Color(1.0, 0.35, 0.25), 1.6],
	"bounce": [Color(0.62, 0.66, 0.72), 0.75],
	"sealed": [Color(1.0, 0.3, 0.3), 1.15],
	"immune": [Color(0.55, 0.85, 1.0), 0.8],
}

var _mark_kind := ""
var _mark_t := 0.0
var _arcs: Array = []          # [{angle, t, dmg}]
var marks_shown := 0           # для смоука
var arcs_shown := 0
var draw_count := 0
var camera_provider: Callable = Callable()   # → Camera3D (для смоука можно подменить)


func _ready() -> void:
	name = "CombatFeedback"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameState.hit_marker.connect(show_marker)
	GameState.player_hurt_from.connect(show_hurt_from)


func show_marker(kind: String) -> void:
	if not MARK_STYLE.has(kind):
		return
	_mark_kind = kind
	_mark_t = MARK_TIME * (1.6 if kind == "sealed" or kind == "kill" else 1.0)
	marks_shown += 1
	queue_redraw()


func screen_center() -> Vector2:
	## Центр экрана в локальных координатах: не зависит от того, как родитель раскладывает детей.
	var vp := get_viewport_rect().size if is_inside_tree() else size
	return vp * 0.5 - global_position


func current_marker() -> String:
	return _mark_kind if _mark_t > 0.0 else ""


func _camera() -> Camera3D:
	if camera_provider.is_valid():
		return camera_provider.call()
	return get_viewport().get_camera_3d() if get_viewport() else null


static func screen_angle(cam_basis: Basis, cam_pos: Vector3, origin: Vector3) -> float:
	## Угол дуги на экране: 0 — вверх (источник впереди), +PI/2 — справа, PI — сзади.
	var to := origin - cam_pos
	var fwd := -cam_basis.z
	var right := cam_basis.x
	fwd.y = 0.0
	right.y = 0.0
	to.y = 0.0
	if to.length() < 0.05 or fwd.length() < 0.01:
		return 0.0
	fwd = fwd.normalized()
	right = right.normalized()
	return atan2(to.dot(right), to.dot(fwd))


func show_hurt_from(origin: Vector3, dmg: int) -> void:
	var cam := _camera()
	if cam == null:
		return
	var ang := screen_angle(cam.global_transform.basis, cam.global_position, origin)
	_arcs.append({"angle": ang, "t": ARC_TIME, "dmg": dmg})
	while _arcs.size() > 4:
		_arcs.pop_front()
	arcs_shown += 1
	queue_redraw()


func last_arc_angle() -> float:
	return float(_arcs[-1]["angle"]) if not _arcs.is_empty() else INF


func _process(delta: float) -> void:
	var busy := false
	if _mark_t > 0.0:
		_mark_t = maxf(0.0, _mark_t - delta)
		busy = true
	for a in _arcs:
		a["t"] = float(a["t"]) - delta
	if not _arcs.is_empty():
		busy = true
		_arcs = _arcs.filter(func(a): return float(a["t"]) > 0.0)
	if busy:
		queue_redraw()


func _draw() -> void:
	draw_count += 1
	var c := screen_center()
	if _mark_t > 0.0 and MARK_STYLE.has(_mark_kind):
		var st: Array = MARK_STYLE[_mark_kind]
		var col: Color = st[0]
		var k: float = st[1]
		var life := clampf(_mark_t / MARK_TIME, 0.0, 1.0)
		col.a = 0.35 + 0.65 * life
		var inner := 7.0 * k + (1.0 - life) * 3.0
		var outer := inner + 7.0 * k
		var w := 2.0 if _mark_kind != "kill" else 3.0
		var sh := Color(0, 0, 0, 0.55 * col.a)   # тёмная обводка — маркер читается и на небе, и на траве
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			draw_line(c + n * inner, c + n * outer, sh, w + 2.5, true)
			draw_line(c + n * inner, c + n * outer, col, w, true)
		if _mark_kind == "bounce" or _mark_kind == "immune":
			draw_arc(c, inner * 0.7, 0, TAU, 16, sh, 3.5, true)
			draw_arc(c, inner * 0.7, 0, TAU, 16, col, 1.5, true)
		elif _mark_kind == "sealed":
			draw_line(c + Vector2(-outer, 0), c + Vector2(outer, 0), sh, 4.5, true)
			draw_line(c + Vector2(-outer, 0), c + Vector2(outer, 0), col, 2.0, true)
	for a in _arcs:
		var t: float = float(a["t"]) / ARC_TIME
		var col2 := Color(1.0, 0.18, 0.12, 0.85 * t)
		var ang: float = float(a["angle"]) - PI * 0.5   # 0 рад на экране = вверх
		var wid := 5.0 + minf(6.0, float(a["dmg"]) * 0.25)
		draw_arc(c, ARC_RADIUS, ang - ARC_SPAN * 0.5, ang + ARC_SPAN * 0.5, 24, col2, wid, true)
