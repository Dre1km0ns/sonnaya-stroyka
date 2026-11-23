extends Node3D
## v0.24: жизнь Сна — светящиеся пылинки вокруг игрока, тихий эмбиент и дальний фон парящих островов.
## В Яви всё скрыто. Фон — силуэты островов на 140–220 м, ниже горизонта тумана, не мешают постройке.
var _motes: CPUParticles3D
var _amb: AudioStreamPlayer
var _backdrop: Node3D
var islands := 0


func _ready() -> void:
	add_to_group("dream_life")
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = 140
	_motes.lifetime = 6.0
	_motes.preprocess = 6.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(14, 6, 14)
	_motes.direction = Vector3(0, 1, 0)
	_motes.spread = 180.0
	_motes.gravity = Vector3(0, 0.15, 0)
	_motes.initial_velocity_min = 0.1
	_motes.initial_velocity_max = 0.5
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.4
	_motes.local_coords = false
	var qm := SphereMesh.new(); qm.radius = 0.045; qm.height = 0.09; qm.radial_segments = 6; qm.rings = 3
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.85, 0.7, 1.0, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true; m.emission = Color(0.75, 0.55, 1.0); m.emission_energy_multiplier = 2.5
	qm.material = m
	_motes.mesh = qm
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 0)); g.add_point(0.2, Color(1, 1, 1, 1)); g.add_point(0.8, Color(1, 1, 1, 1)); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_motes.color_ramp = g
	add_child(_motes)
	_amb = AudioStreamPlayer.new()
	_amb.name = "Ambience"
	_amb.bus = "SFX"
	var st: AudioStream = load("res://assets/audio/sfx_dream_ambience.ogg")
	if st is AudioStreamOggVorbis: (st as AudioStreamOggVorbis).loop = true
	_amb.stream = st
	_amb.volume_db = -16.0
	add_child(_amb)
	_build_backdrop()
	GameState.world_changed.connect(_on_world)
	_on_world(GameState.is_dream())


func _build_backdrop() -> void:
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	var rng := RandomNumberGenerator.new(); rng.seed = 2424
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.28, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var top := StandardMaterial3D.new()
	top.albedo_color = Color(0.55, 0.42, 0.78)
	top.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(14):
		var a := float(i) / 14.0 * TAU + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(140.0, 220.0)
		var root := Node3D.new()
		root.position = Vector3(cos(a) * r, rng.randf_range(-10.0, 28.0), sin(a) * r)
		_backdrop.add_child(root)
		var w := rng.randf_range(14.0, 34.0)
		for k in range(3):
			var b := MeshInstance3D.new(); var bm := BoxMesh.new()
			var s := w * (1.0 - k * 0.3)
			bm.size = Vector3(s, 4.0, s * rng.randf_range(0.7, 1.2))
			b.mesh = bm; b.material_override = mat if k > 0 else top
			b.position = Vector3(0, -k * 4.0, 0)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(b)
		islands += 1


func _on_world(is_dream: bool) -> void:
	visible = is_dream
	_motes.emitting = is_dream
	if is_dream and not _amb.playing and is_inside_tree():
		_amb.play()
	elif not is_dream:
		_amb.stop()


func _process(_delta: float) -> void:
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		_motes.global_position = cam.global_position
		_backdrop.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
