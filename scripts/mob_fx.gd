extends RefCounted
## v0.24: общая смерть мобов — заваливание набок, оседание, вспышка частиц цвета моба и звук.
const BreakFx := preload("res://scripts/break_fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
static var deaths := 0


static func death(mob: Node3D, col: Color = Color(0.55, 0.45, 0.7), dur: float = 1.1) -> void:
	if mob == null or not mob.is_inside_tree():
		return
	deaths += 1
	var hb := mob.get_node_or_null("HPBar")
	if hb: hb.visible = false
	var model: Node3D = mob.get_node_or_null("Model") as Node3D
	var tgt: Node3D = model if model else mob
	var tw := mob.create_tween()
	tw.set_parallel(true)
	var side := 1.0 if randf() < 0.5 else -1.0
	tw.tween_property(tgt, "rotation:z", tgt.rotation.z + side * 1.45, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(tgt, "position:y", tgt.position.y - 0.25, dur * 0.6).set_delay(dur * 0.3)
	tw.tween_property(tgt, "scale", tgt.scale * 0.05, dur * 0.35).set_delay(dur * 0.65)
	var host := mob.get_parent()
	var at := mob.global_position + Vector3(0, 0.6, 0)
	mob.get_tree().create_timer(dur * 0.65).timeout.connect(func() -> void:
		if is_instance_valid(host):
			BreakFx.puff(host, at, col, 22))
	Sfx.play("mob_die", mob.get_tree().root, -4.0, randf_range(0.85, 1.15))


static func drop_dust(mob: Node3D, amount: int) -> void:
	## Видимая награда: осыпь вылетает из моба кучкой и подбирается автоподбором.
	if mob == null or amount <= 0 or not mob.is_inside_tree():
		return
	var at := mob.global_position + Vector3(0, 0.8, 0)
	var rec: Dictionary = GameState.register_drop({"id": "dust", "name": "Осыпь", "count": amount}, at)
	var bc := mob.get_tree().get_first_node_in_group("build_controller")
	if bc and bc.has_method("spawn_drop"):
		bc.spawn_drop(rec, Vector3(randf_range(-1.5, 1.5), 4.0, randf_range(-1.5, 1.5)), 0.4)
