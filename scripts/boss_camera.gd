extends Node
## v0.21 c3: камера боя. Вплотную к Матери блоков её тело закрывало экран.
## 1) Рядом с любым боссом (до 9 м) FOV плавно расширяется 75° → 85°.
## 2) Когда камера ближе ~3.6 м к центру Матери, её модель плавно становится полупрозрачной (до 55%; пластины брони и ядро — нет),
##    так что видно и её замах, и то, что за ней. Хитбоксы и урон не меняются.
## Консоль: bosscam [on|off|status].

const FOV_NEAR_ADD := 10.0
const FOV_RANGE := 9.0
const FADE_FAR := 3.6
const FADE_SPAN := 1.2
const FADE_MAX := 0.55

var enabled := true
var base_fov := 75.0
var fov_add := 0.0
var fade := 0.0          # текущая прозрачность модели Матери (0..FADE_MAX)
var nearest_boss_dist := INF
var _cam: Camera3D


func _ready() -> void:
	add_to_group("boss_camera")


func _process(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
		if _cam: base_fov = _cam.fov
	if _cam == null:
		return
	var want_fov := 0.0
	var want_fade := 0.0
	var mother: Node3D = null
	nearest_boss_dist = INF
	for b in get_tree().get_nodes_in_group("boss"):
		if not (b is Node3D) or not is_instance_valid(b) or not (b as Node3D).is_visible_in_tree():
			continue
		if b.get("hp") != null and int(b.get("hp")) <= 0:
			continue
		var c: Vector3 = b.hit_center() if b.has_method("hit_center") else (b as Node3D).global_position
		var d := Vector2(_cam.global_position.x - c.x, _cam.global_position.z - c.z).length()
		nearest_boss_dist = minf(nearest_boss_dist, d)
		if b.is_in_group("block_mother"):
			mother = b
			want_fade = clampf((FADE_FAR - d) / FADE_SPAN, 0.0, 1.0) * FADE_MAX
	if enabled and nearest_boss_dist < FOV_RANGE:
		want_fov = FOV_NEAR_ADD * clampf((FOV_RANGE - nearest_boss_dist) / 4.0, 0.0, 1.0)
	if not enabled:
		want_fade = 0.0
	fov_add = move_toward(fov_add, want_fov, delta * 20.0)
	_cam.fov = base_fov + fov_add
	var new_fade := move_toward(fade, want_fade, delta * 2.0)
	if mother and (absf(new_fade - fade) > 0.001 or (new_fade == 0.0 and fade != 0.0)):
		apply_fade(mother, new_fade)
	fade = new_fade


static func apply_fade(boss: Node, t: float) -> void:
	## Только тело (Model). Пластины брони, их кромка и ядро остаются непрозрачными — это цели и сигналы боя.
	## Через копии материалов (а не GeometryInstance3D.transparency): так работает и в Compatibility-рендере.
	var model := boss.get_node_or_null("Model")
	if model:
		for g in model.find_children("*", "MeshInstance3D", true, false):
			_fade_mesh(g as MeshInstance3D, t)


static func _fade_mesh(mi: MeshInstance3D, t: float) -> void:
	## Меняем прозрачность прямо в материалах-переопределениях (их уже дублирует apply_night/подсветка разломов),
	## поэтому ночь и свечение Матери продолжают работать поверх. При t=0 режим прозрачности возвращается.
	if mi == null or mi.mesh == null:
		return
	for si in range(mi.mesh.get_surface_count()):
		var mat := mi.get_surface_override_material(si)
		if mat == null:
			if t <= 0.0: continue
			var src := mi.get_active_material(si)
			mat = src.duplicate() if src is BaseMaterial3D else StandardMaterial3D.new()
			mi.set_surface_override_material(si, mat)
		if not (mat is BaseMaterial3D): continue
		var bm := mat as BaseMaterial3D
		var c := bm.albedo_color
		if t > 0.0:
			if not bm.has_meta("_fade_tr"): bm.set_meta("_fade_tr", bm.transparency)
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			c.a = 1.0 - t
		elif bm.has_meta("_fade_tr"):
			bm.transparency = int(bm.get_meta("_fade_tr")); bm.remove_meta("_fade_tr")
			c.a = 1.0
		bm.albedo_color = c


static func fade_of(mi: MeshInstance3D) -> float:
	var m := mi.get_surface_override_material(0) as BaseMaterial3D if mi and mi.mesh else null
	if m == null or not m.has_meta("_fade_tr"): return 0.0
	return 1.0 - m.albedo_color.a


func status_text() -> String:
	return "Камера боя: %s · FOV %.0f° (база %.0f° +%.1f) · прозрачность Матери %d%% · до ближайшего босса %s" % [
		"вкл" if enabled else "выкл", (_cam.fov if _cam else base_fov), base_fov, fov_add, int(round(fade * 100.0)),
		("%.1f м" % nearest_boss_dist) if nearest_boss_dist < INF else "—"]
