extends Node3D
## v0.11: отладочная сцена viewmodel. ←/→ — сменить инструмент, Space/ЛКМ — удар, W — подойти к стене.
## Запуск со скриншотами: godot --path . res://scenes/debug_viewmodel.tscn -- --vm-shots <папка>

const Rig := preload("res://scripts/viewmodel_rig.gd")
const BlockTex := preload("res://scripts/block_tex.gd")
const ORDER := ["pickaxe", "pickaxe2", "sword", "sword2", "sword3", "torch", "lantern"]

var cam: Camera3D
var rig: Node3D
var idx := 0
var label: Label


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var body := StaticBody3D.new()
	add_child(body)
	for x in range(-6, 7):
		for z in range(-10, 3):
			_cube(body, "ground", Vector3(x, -1, z))
	for x in range(-3, 4):
		for y in range(0, 3):
			_cube(body, "planks" if y > 0 else "stone", Vector3(x, y, -6))
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.position = Vector3(0.5, 1.6, 0.5)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(cam)
	cam.make_current()
	rig = Rig.new()
	cam.add_child(rig)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	ui.add_child(label)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.add_theme_font_size_override("font_size", 22)
	ui.add_child(cross)
	_apply()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--vm-shots")
	if i >= 0:
		var dir := args[i + 1] if args.size() > i + 1 else "user://vm_shots"
		call_deferred("_shots", dir)


func _cube(body: StaticBody3D, kind: String, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BlockTex.cube_mesh(kind, Vector3.ONE)
	mi.position = at + Vector3(0.5, 0.5, 0.5)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3.ONE
	cs.shape = bs
	cs.position = mi.position
	body.add_child(cs)


func _apply() -> void:
	rig.set_tool(ORDER[idx])
	label.text = "Viewmodel: %s  (%d/%d)  ←/→ сменить · Space удар · W/S к стене" % [ORDER[idx], idx + 1, ORDER.size()]


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_RIGHT: idx = (idx + 1) % ORDER.size(); _apply()
			KEY_LEFT: idx = (idx - 1 + ORDER.size()) % ORDER.size(); _apply()
			KEY_SPACE: rig.play_swing()
			KEY_W: cam.position.z -= 0.5
			KEY_S: cam.position.z += 0.5
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		rig.play_swing()


func _snap(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name))
	print("VMSHOT ", name)


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(10)
	for k in range(ORDER.size()):
		idx = k
		_apply()
		await _frames(4)
		await _snap(dir, "vm_%s_idle.png" % ORDER[k])
		rig.play_swing()
		var c: Dictionary = rig.config(ORDER[k])
		await get_tree().create_timer(float(c.swing_time) / float(c.speed) * 0.55).timeout
		await _snap(dir, "vm_%s_swing.png" % ORDER[k])
		await get_tree().create_timer(0.5).timeout
		print("VMSTATE %s rot_after=%s swinging=%s" % [ORDER[k], str(rig.swing_pivot.rotation_degrees), str(rig.swinging)])
	# У стены: проверка отвода.
	cam.position = Vector3(0.5, 1.6, -4.55)
	cam.rotation_degrees = Vector3(0, 0, 0)
	for t in ["sword2", "pickaxe"]:
		idx = ORDER.find(t)
		_apply()
		await _frames(20)
		await _snap(dir, "vm_%s_wall.png" % t)
		print("VMWALL %s retract=%.2f" % [t, rig.retract])
	get_tree().quit(0)
