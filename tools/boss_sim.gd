extends SceneTree
## Headless-симуляция боя с «Матерью блоков» (v0.6).
## godot --headless --fixed-fps 60 --path . -s res://tools/boss_sim.gd -- [--bot=good|idle] [--seed=N]
## Бот «good»: уходит из-под тени прыжка, перепрыгивает волну, уходит с теней кирпичей и маркера,
## бьёт мечом (10 урона / 0.45 с, дальность 2.6 + hit_radius) когда босс уязвим или стоит.
## Бот «idle»: стоит рядом и только бьёт — проверка, что урон-капы держатся (≤40 за удар, ≤70 за 3 с).

const SWORD_DAMAGE := 10
const SWORD_CD := 0.45
const SWORD_REACH := 2.6
const WALK := 6.0
const SPRINT := 10.0
const JUMP_V := 5.5
const SIM_LIMIT := 420.0

var gs: Node
var boss: CharacterBody3D
var player: CharacterBody3D
var bot := "good"
var t := 0.0
var swing_cd := 0.0
var hits := 0
var deaths := 0
var dmg_events: Array = []  # [t, dmg, source]
var max_single := 0
var max_window := 0
var phase_times := {}
var states_seen := {}
var done := false
var gravity := 9.8
var _prev_state := -1
var alog: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bot="):
			bot = a.substr(6)
	call_deferred("_setup")


func _setup() -> void:
	gs = root.get_node("GameState")
	gs.peaceful = false
	gs.heal_player_full()
	gs.player_hp_changed.connect(_on_hp)
	gs.player_died.connect(_on_died)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000, 1, 3000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	root.add_child(floor_body)
	player = CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	pcs.shape = cap
	pcs.position = Vector3(0, 0.85, 0)
	player.add_child(pcs)
	player.position = Vector3(0, 0.1, 8)
	root.add_child(player)
	var host := Node3D.new()
	host.name = "World"
	root.add_child(host)
	boss = load("res://scripts/block_mother.gd").spawn_near(host, Vector3i(-4, 0, -2))
	alog = boss.attack_log
	print("SIM: bot=%s boss hp=%d" % [bot, boss.hp])


var _last_hp := 100


func _on_hp(hp: int, _mx: int) -> void:
	if hp < _last_hp:
		var d := _last_hp - hp
		dmg_events.append([t, d])
		max_single = maxi(max_single, d)
		var w := 0
		for e in dmg_events:
			if t - float(e[0]) <= 3.0:
				w += int(e[1])
		max_window = maxi(max_window, w)
	_last_hp = hp


func _on_died() -> void:
	deaths += 1
	gs.heal_player_full()
	_last_hp = 100


func _physics_process(delta: float) -> bool:
	if boss == null or done:
		return false
	t += delta
	if not is_instance_valid(boss) or boss.state == boss.S.DEAD:
		_finish("killed")
		return true
	if boss.state == boss.S.LEAVING:
		_finish("left")
		return true
	if t > SIM_LIMIT:
		_finish("timeout")
		return true
	var st: int = boss.state
	states_seen[boss.STATE_NAMES[st]] = true
	if not phase_times.has(boss.phase):
		phase_times[boss.phase] = snappedf(t, 0.1)
	if gs.player_hp <= 0:
		gs.heal_player_full()
	_drive(delta)
	if OS.get_environment("SIMDBG") != "" and st != _prev_state and t > 30.0 and t < 60.0:
		print("t=%.1f %s hp=%d dist=%.1f pos=%s bpos=%s" % [t, boss.STATE_NAMES[st], boss.hp, _flat(boss.global_position, player.global_position).length(), player.global_position, boss.global_position])
	_prev_state = st
	return false


func _flat(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x - b.x, 0, a.z - b.z)


func _drive(delta: float) -> void:
	var p := player.global_position
	var bp := boss.global_position
	var to_b := _flat(bp, p)
	var dist := to_b.length()
	var want := Vector3.ZERO
	var speed := WALK
	var jump := false
	var st: int = boss.state
	if bot == "kite" and fmod(t, 30.0) > 4.0 and fmod(t, 30.0) < 9.0:
		# «кайт»: убегает далеко (>14 м) → должна сработать пересборка рядом с игроком
		want = -to_b.normalized() if dist > 0.1 else Vector3(0, 0, 1)
		speed = SPRINT
	elif bot == "good" or bot == "kite":
		var danger := false
		# 1) тень прыжка
		if st == boss.S.AIR or st == boss.S.WINDUP:
			var land: Vector3 = boss._target if st == boss.S.AIR else bp
			var away := _flat(p, land)
			if away.length() < boss.SLAM_RADIUS + 1.5:
				want = away.normalized() if away.length() > 0.05 else Vector3(1, 0, 0)
				speed = SPRINT
				danger = true
		# 2) маркер пересборки
		if st == boss.S.MARKER or st == boss.S.SCATTER:
			var away2 := _flat(p, boss._marker_pos)
			if away2.length() < boss.REASSEMBLE_RADIUS + 1.5:
				want = away2.normalized() if away2.length() > 0.05 else Vector3(0, 0, 1)
				speed = SPRINT
				danger = true
		# 3) тени кирпичей
		for b in boss._bricks:
			var bpos: Vector3 = b["pos"]
			var away3 := _flat(p, bpos)
			if away3.length() < boss.BRICK_RADIUS + 0.9:
				want = (want + away3.normalized()).normalized()
				speed = SPRINT
				danger = true
		# 4) волна — прыжок, когда кольцо подходит
		for w in boss._waves:
			var c: Vector3 = w["center"]
			var r: float = float(w["r"])
			var dd := _flat(p, c).length()
			if dd - r < 1.2 and dd - r > -0.2 and player.is_on_floor():
				jump = true
		if not danger:
			var attackable: bool = st in [boss.S.STAGGER, boss.S.IDLE, boss.S.TRANSITION, boss.S.RAIN]
			var reach: float = SWORD_REACH + boss.hit_radius - 0.4
			if attackable and boss.is_vulnerable():
				if dist > reach:
					want = to_b.normalized()
					speed = SPRINT
			else:
				# держим дистанцию ~5.5 м, чтобы успеть уйти
				if dist < 4.5:
					want = -to_b.normalized()
				elif dist > 7.0:
					want = to_b.normalized()
	else:
		# idle-бот: стоит вплотную и бьёт
		if dist > 2.5:
			want = to_b.normalized()
	var v := player.velocity
	v.x = want.x * speed
	v.z = want.z * speed
	if player.is_on_floor():
		v.y = JUMP_V if jump else 0.0
	else:
		v.y -= gravity * delta
	player.velocity = v
	player.move_and_slide()
	# меч
	swing_cd = maxf(0.0, swing_cd - delta)
	if swing_cd <= 0.0:
		var c2: Vector3 = boss.hit_center() if boss.has_method("hit_center") else bp
		var d2 := (c2 - (player.global_position + Vector3(0, 1.5, 0))).length()
		if d2 <= SWORD_REACH + boss.hit_radius:
			swing_cd = SWORD_CD
			var before: int = boss.hp
			boss.take_damage(SWORD_DAMAGE)
			if boss.hp < before:
				hits += 1
		else:
			for m in get_nodes_in_group("blockling"):
				if is_instance_valid(m) and (m.global_position - player.global_position).length() < SWORD_REACH + 0.5:
					swing_cd = SWORD_CD
					m.take_damage(SWORD_DAMAGE)
					break


func _finish(why: String) -> void:
	done = true
	print("SIM RESULT bot=%s end=%s ttk=%.1f s hits=%d deaths=%d max_single=%d max_3s=%d phases=%s" % [
		bot, why, t, hits, deaths, max_single, max_window, str(phase_times)])
	print("SIM states=", states_seen.keys())
	print("SIM attack_log=", alog)
	var ok := max_single <= 40 and max_window <= 70
	print("SIM caps ", "OK" if ok else "FAIL")
	quit(0 if ok else 2)
