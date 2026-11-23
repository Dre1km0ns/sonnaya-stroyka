extends Node
## v0.24: кооп по локальной сети до 4 игроков (ENet). Автозагрузка NetSession.
## Хост — авторитет: его мир (сид, блоки, раскопки, сундуки, дроп, время суток, мобы и боссы). Сохраняется только мир хоста.
## У каждого свой инвентарь, здоровье, стамина и свой Сон; закреплённое при пробуждении попадает в Явь и уходит через хоста всем.
## Синхронизация мира — дифф: каждые 0.25 с узел сравнивает wake_blocks / removed_terrain / сундуки / дроп со своей «тенью»
## и отправляет изменения (клиент — хосту, хост — всем). Применение идемпотентно.
signal roster_changed
signal world_received
signal join_failed(reason: String)
signal lan_found(list: Array)

const PORT := 24567
const DISC_PORT := 24568
const MAX_PLAYERS := 4
const SYNC_SEC := 0.25
const POS_SEC := 1.0 / 15.0
const MOB_SEC := 0.1
const TIME_SEC := 1.0
const AVATARS := ["character-a", "character-b", "character-c", "character-d"]

var mode := ""                 # "" | "host" | "client"
var want_host := false         # меню «Создать сетевую игру» → хост поднимается, когда загрузится мир
var player_name := "Игрок"
var peers: Dictionary = {}     # peer_id -> {"name", "idx"}
var avatars: Dictionary = {}   # peer_id -> Node3D (group remote_player)
var proxies: Dictionary = {}   # клиент: id моба хоста -> net_proxy
var pending_world: Dictionary = {}
var in_world := false
var stats := {"sent": 0, "recv": 0, "blocks_in": 0, "blocks_out": 0, "hits_sent": 0, "hits_recv": 0, "hurt_sent": 0, "hurt_recv": 0, "chat": 0}
var last_chat := ""
var _shadow_b: Dictionary = {}
var _shadow_r: Dictionary = {}
var _shadow_s: Dictionary = {}
var _shadow_d: Dictionary = {}
var _sync_t := 0.0
var _pos_t := 0.0
var _mob_t := 0.0
var _time_t := 0.0
var _disc: PacketPeerUDP
var _disc_client: PacketPeerUDP
var _disc_t := -1.0
var _disc_found: Array = []
var _chat_ui: LineEdit


func _ready() -> void:
	add_to_group("net_session")
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Не удалось подключиться."))
	multiplayer.server_disconnected.connect(_on_server_lost)
	get_tree().node_added.connect(_on_node_added)


func is_host() -> bool: return mode == "host"
func is_client() -> bool: return mode == "client"
func active() -> bool: return mode != ""
func player_count() -> int: return 1 + peers.size() if active() else 1


# ------------------------------------------------------------------ подключение
func host(port: int = PORT) -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return "Не удалось открыть порт %d (ошибка %d)." % [port, err]
	multiplayer.multiplayer_peer = p
	mode = "host"
	peers.clear()
	_start_discovery_responder()
	_update_players()
	_enter_world_if_ready()
	GameState.chat("Сетевая игра открыта: порт %d. Друзья в той же сети жмут «Подключиться»." % port, Color(0.6, 0.9, 1.0), true)
	return ""


func join(ip: String, port: int = PORT) -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip.strip_edges(), port)
	if err != OK:
		return "Ошибка подключения %d." % err
	multiplayer.multiplayer_peer = p
	mode = "client"
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = ""
	want_host = false
	in_world = false
	peers.clear()
	for a in avatars.values():
		if is_instance_valid(a): a.queue_free()
	avatars.clear()
	for pr in proxies.values():
		if is_instance_valid(pr): pr.queue_free()
	proxies.clear()
	if _disc: _disc.close(); _disc = null
	GameState.net_players = 1


func _fail(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func _on_connected() -> void:
	_req_world.rpc_id(1, player_name)


func _on_server_lost() -> void:
	var was := in_world
	leave()
	if was and get_tree():
		GameState.chat("Связь с хостом потеряна.", Color(1.0, 0.6, 0.5), true)
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var nm := str(peers[id].get("name", "Игрок"))
	peers.erase(id)
	if avatars.has(id):
		if is_instance_valid(avatars[id]): avatars[id].queue_free()
		avatars.erase(id)
	_update_players()
	if is_host():
		_roster.rpc(_roster_data())
	GameState.chat("%s вышел из игры." % nm, Color(0.7, 0.85, 1.0), true)


func _update_players() -> void:
	GameState.net_players = player_count()
	roster_changed.emit()


func _roster_data() -> Dictionary:
	var d := {1: {"name": player_name, "idx": 0}}
	for id in peers: d[id] = peers[id]
	return d


@rpc("any_peer", "reliable")
func _req_world(nm: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.size() >= MAX_PLAYERS - 1:
		_refuse.rpc_id(id, "Сервер полон: уже %d игрока." % MAX_PLAYERS)
		return
	var used := {0: true}
	for p in peers.values(): used[int(p.idx)] = true
	var idx := 1
	while used.has(idx): idx += 1
	peers[id] = {"name": nm.substr(0, 20) if nm.strip_edges() != "" else "Игрок %d" % (idx + 1), "idx": idx}
	_update_players()
	_recv_world.rpc_id(id, snapshot())
	_reset_shadows()
	_roster.rpc(_roster_data())
	GameState.chat("%s подключился. Игроков: %d." % [peers[id].name, player_count()], Color(0.6, 0.9, 1.0), true)


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable")
func _roster(d: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	peers.clear()
	for id in d:
		if int(id) != me:
			peers[int(id)] = d[id]
	_update_players()


func snapshot() -> Dictionary:
	var st := {}
	for k in GameState.world_storage:
		if str(k).begins_with("w:"): st[k] = GameState.world_storage[k]
	return {"name": GameState.world_name, "seed_text": GameState.seed_text, "seed": GameState.world_seed, "peaceful": GameState.peaceful,
		"difficulty": GameState.difficulty, "blocks": GameState.wake_blocks, "removed": GameState.removed_terrain, "storage": st,
		"drops": GameState.dropped_items, "day_time": GameState.day_time, "mother": GameState.mother_defeated,
		"anaconda": GameState.anaconda_defeated, "burger": GameState.burger_defeated, "spawn": GameState.spawn_point}


@rpc("authority", "reliable")
func _recv_world(snap: Dictionary) -> void:
	pending_world = snap
	world_received.emit()


func begin_client_world(snap: Dictionary = pending_world) -> void:
	## Клиент: мир хоста без своей папки (не сохраняется), старт в Яви рядом с хостом.
	GameState.begin_world("%s (сеть)" % str(snap.get("name", "Мир")), "", str(snap.get("seed_text", "")), int(snap.get("seed", 1337)), bool(snap.get("peaceful", false)))
	GameState.tutorial_enabled = false
	GameState.set_difficulty(str(snap.get("difficulty", "normal")))
	GameState.wake_blocks = (snap.get("blocks", {}) as Dictionary).duplicate(true)
	for c in snap.get("removed", {}):
		GameState.removed_terrain[c] = snap.removed[c]
		GameState._index_removed(c)
	for k in snap.get("storage", {}):
		GameState.world_storage[k] = (snap.storage[k] as Array).duplicate(true)
	GameState.dropped_items = (snap.get("drops", []) as Array).duplicate(true)
	GameState.day_time = float(snap.get("day_time", 0.0))
	GameState.mother_defeated = bool(snap.get("mother", false))
	GameState.anaconda_defeated = bool(snap.get("anaconda", false))
	GameState.burger_defeated = bool(snap.get("burger", false))
	if snap.has("spawn"):
		GameState.spawn_point = snap.spawn
		GameState.creation_spawn = snap.spawn
	_update_players()   # begin_world сбросил net_players


# ------------------------------------------------------------------ вход в мир
func _on_node_added(n: Node) -> void:
	if n.is_in_group("build_controller") or n.name == "Main":
		call_deferred("_enter_world_if_ready")


func _enter_world_if_ready() -> void:
	if want_host and mode == "" and get_tree().get_first_node_in_group("build_controller") != null:
		want_host = false
		host()
		return
	if not active() or in_world:
		return
	if get_tree().get_first_node_in_group("build_controller") == null:
		return
	in_world = true
	_reset_shadows()
	_ensure_chat_ui()


func _reset_shadows() -> void:
	_shadow_b = GameState.wake_blocks.duplicate(true)
	_shadow_r = GameState.removed_terrain.duplicate()
	_shadow_s = {}
	for k in GameState.world_storage:
		if str(k).begins_with("w:"): _shadow_s[k] = (GameState.world_storage[k] as Array).duplicate(true)
	_shadow_d = {}
	for r in GameState.dropped_items:
		_shadow_d[_uid(r)] = true


func _uid(r: Dictionary) -> int:
	if not r.has("uid"):
		r["uid"] = randi()
	return int(r["uid"])


# ------------------------------------------------------------------ дифф мира
func collect_changes() -> Dictionary:
	var b := {}
	for c in GameState.wake_blocks:
		var v: Dictionary = GameState.wake_blocks[c]
		if not _shadow_b.has(c) or _shadow_b[c] != v:
			b[c] = v.duplicate(true)
			_shadow_b[c] = v.duplicate(true)
	if _shadow_b.size() != GameState.wake_blocks.size() or b.size() > 0:
		for c in _shadow_b.keys():
			if not GameState.wake_blocks.has(c):
				b[c] = null
				_shadow_b.erase(c)
	var r := {}
	if _shadow_r.size() != GameState.removed_terrain.size():
		for c in GameState.removed_terrain:
			if not _shadow_r.has(c):
				r[c] = GameState.removed_terrain[c]
				_shadow_r[c] = GameState.removed_terrain[c]
	var s := {}
	for k in GameState.world_storage:
		if not str(k).begins_with("w:"): continue
		var slots: Array = GameState.world_storage[k]
		if not _shadow_s.has(k) or _shadow_s[k] != slots:
			s[k] = slots.duplicate(true)
			_shadow_s[k] = slots.duplicate(true)
	for k in _shadow_s.keys():
		if not GameState.world_storage.has(k):
			s[k] = null
			_shadow_s.erase(k)
	var da: Array = []
	var now := {}
	for rec in GameState.dropped_items:
		var u := _uid(rec)
		now[u] = true
		if not _shadow_d.has(u):
			var o := {"uid": u, "id": rec.id, "count": int(rec.count), "pos": rec.get("pos", Vector3.ZERO)}
			if rec.has("durability"): o["durability"] = rec.durability
			da.append(o)
	var dd: Array = []
	for u in _shadow_d.keys():
		if not now.has(u):
			dd.append(u)
	_shadow_d = now
	var out := {}
	if not b.is_empty(): out["b"] = b
	if not r.is_empty(): out["r"] = r
	if not s.is_empty(): out["s"] = s
	if not da.is_empty(): out["da"] = da
	if not dd.is_empty(): out["dd"] = dd
	return out


func apply_changes(ch: Dictionary) -> void:
	stats.recv += 1
	var cells: Array = []
	for c in ch.get("b", {}):
		var v: Variant = ch.b[c]
		if v == null:
			if GameState.wake_blocks.has(c):
				GameState.wake_blocks.erase(c)
				cells.append(c)
				GameState.wake_cell_removed.emit(c)
			_shadow_b.erase(c)
		else:
			GameState.wake_blocks[c] = (v as Dictionary).duplicate(true)
			_shadow_b[c] = (v as Dictionary).duplicate(true)
			cells.append(c)
	if not cells.is_empty():
		stats.blocks_in += cells.size()
		GameState.mark_torches_dirty()
		GameState.placed_cells_changed.emit(false, cells)
		for c in cells: GameState.terrain_cell_changed.emit(c)
	for c in ch.get("r", {}):
		_shadow_r[c] = ch.r[c]
		GameState.remove_terrain_cell_silent(c, str(ch.r[c]))
		for cm in get_tree().get_nodes_in_group("chunk_manager"):
			if not bool(cm.get("is_dream_layer")) and cm.has_method("rebuild_chunk_at_world"):
				cm.rebuild_chunk_at_world(c.x, c.z)
	for k in ch.get("s", {}):
		if ch.s[k] == null:
			GameState.world_storage.erase(k); _shadow_s.erase(k)
		else:
			GameState.world_storage[k] = (ch.s[k] as Array).duplicate(true)
			_shadow_s[k] = (ch.s[k] as Array).duplicate(true)
	if ch.has("s"):
		GameState.inventory_changed.emit()
	var bc := get_tree().get_first_node_in_group("build_controller")
	for o in ch.get("da", []):
		var u := int(o.uid)
		_shadow_d[u] = true
		var have := false
		for rec in GameState.dropped_items:
			if int(rec.get("uid", -1)) == u: have = true; break
		if have: continue
		var rec2: Dictionary = (o as Dictionary).duplicate(true)
		GameState.dropped_items.append(rec2)
		if bc and bc.has_method("spawn_drop"): bc.spawn_drop(rec2, Vector3.ZERO, 0.3)
	for u in ch.get("dd", []):
		_shadow_d.erase(int(u))
		for i in range(GameState.dropped_items.size() - 1, -1, -1):
			if int(GameState.dropped_items[i].get("uid", -1)) == int(u):
				var rec3: Dictionary = GameState.dropped_items[i]
				GameState.dropped_items.remove_at(i)
				for n in get_tree().get_nodes_in_group("dropped_item"):
					if is_instance_valid(n) and is_same(n.get("rec"), rec3):
						n.set("collected", true); n.queue_free()


@rpc("any_peer", "reliable")
func _push_changes(ch: Dictionary) -> void:
	if not is_host():
		return
	apply_changes(ch)
	_world_changes.rpc(ch)


@rpc("authority", "reliable")
func _world_changes(ch: Dictionary) -> void:
	apply_changes(ch)


func _sync_world() -> void:
	var ch := collect_changes()
	if ch.is_empty():
		return
	stats.sent += 1
	stats.blocks_out += (ch.get("b", {}) as Dictionary).size()
	if is_host():
		_world_changes.rpc(ch)
	else:
		_push_changes.rpc_id(1, ch)


# ------------------------------------------------------------------ игроки
@rpc("any_peer", "unreliable_ordered")
func _p_state(pos: Vector3, yaw: float, item: String, dream: bool, hp: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var av := _avatar(id)
	if av == null:
		return
	av.set_meta("target", pos)
	av.set_meta("yaw", yaw)
	av.set_meta("hp", hp)
	av.set("dead", hp <= 0)
	av.visible = not dream and not GameState.is_dream()
	av.set_meta("item", item)


func _avatar(id: int) -> Node3D:
	if avatars.has(id) and is_instance_valid(avatars[id]):
		return avatars[id]
	var bc := get_tree().get_first_node_in_group("build_controller")
	var host_node: Node = bc._wake_world() if bc and bc.has_method("_wake_world") else null
	if host_node == null:
		return null
	var av: Node3D = load("res://scripts/net_avatar.gd").new()
	av.peer_id = id
	var info: Dictionary = peers.get(id, {"name": "Игрок", "idx": 1})
	av.display_name = str(info.get("name", "Игрок"))
	av.model_name = AVATARS[int(info.get("idx", 1)) % AVATARS.size()]
	host_node.add_child(av)
	avatars[id] = av
	return av


func hurt_remote(p: Node, amount: int, source: String, origin: Vector3) -> void:
	var id := int(p.get("peer_id")) if p and "peer_id" in p else 0
	if id <= 0:
		return
	stats.hurt_sent += 1
	_net_hurt.rpc_id(id, amount, source, origin)


@rpc("any_peer", "reliable")
func _net_hurt(amount: int, source: String, origin: Vector3) -> void:
	stats.hurt_recv += 1
	if origin != Vector3.INF:
		GameState.hit_from(origin)
	GameState.damage_player(amount, source)


# ------------------------------------------------------------------ мобы и боссы (хост → клиенты)
func _mob_list() -> Array:
	var out: Array = []
	var seen := {}
	for g in ["enemy", "boss"]:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D) or not is_instance_valid(n) or n.is_queued_for_deletion() or seen.has(n):
				continue
			if n.is_in_group("net_proxy"):
				continue
			seen[n] = true
			var nd := n as Node3D
			var path := str(n.get_script().resource_path.get_file().get_basename()) if n.get_script() else "mob"
			var boss := n.is_in_group("boss")
			var title := str(n.call("boss_title")) if n.has_method("boss_title") else (str(n.call("display_name")) if n.has_method("display_name") else "")
			var hc: Vector3 = n.call("hit_center") if n.has_method("hit_center") else nd.global_position + Vector3(0, 0.8, 0)
			out.append([n.get_instance_id(), path, nd.global_position, nd.rotation.y, int(n.get("hp")) if "hp" in n else 1,
				int(n.get("max_hp")) if "max_hp" in n else 1, boss, title, hc, float(n.get("hit_radius")) if "hit_radius" in n else 0.5])
	return out


@rpc("authority", "unreliable_ordered")
func _mobs(list: Array) -> void:
	var bc := get_tree().get_first_node_in_group("build_controller")
	var host_node: Node = bc._wake_world() if bc and bc.has_method("_wake_world") else null
	if host_node == null:
		return
	var alive := {}
	for m in list:
		var id := int(m[0])
		alive[id] = true
		var pr: Node3D = proxies.get(id)
		if pr == null or not is_instance_valid(pr):
			pr = load("res://scripts/net_proxy.gd").new()
			pr.remote_id = id
			pr.kind = str(m[1])
			pr.is_boss = bool(m[6])
			host_node.add_child(pr)
			pr.global_position = m[2]
			proxies[id] = pr
		pr.update_from(m)
	for id in proxies.keys():
		if not alive.has(id):
			if is_instance_valid(proxies[id]): proxies[id].die_out()
			proxies.erase(id)


func send_hit(remote_id: int, dmg: int, weapon: String) -> void:
	stats.hits_sent += 1
	_net_hit.rpc_id(1, remote_id, dmg, weapon)


@rpc("any_peer", "reliable")
func _net_hit(remote_id: int, dmg: int, weapon: String) -> void:
	if not is_host():
		return
	stats.hits_recv += 1
	var n := instance_from_id(remote_id)
	if n == null or not is_instance_valid(n) or not (n is Node) or not ((n as Node).is_in_group("enemy") or (n as Node).is_in_group("boss")):
		return
	if n.has_method("receive_weapon_hit"):
		n.receive_weapon_hit(dmg, weapon)
	elif weapon == "arrow" and n.has_method("take_arrow"):
		n.take_arrow(dmg, null)
	elif n.has_method("take_damage"):
		n.take_damage(dmg)


@rpc("any_peer", "reliable")
func _net_summon() -> void:
	## Клиент использовал призывалку — отсчёт запускает хост.
	if not is_host():
		return
	var host_node := get_tree().current_scene
	var bs: GDScript = load("res://scripts/burger_summon.gd")
	if bs.can_summon(get_tree()) == "":
		bs.start(host_node, bs.DELAY)


func request_summon() -> void:
	_net_summon.rpc_id(1)


# ------------------------------------------------------------------ время и чат
@rpc("authority", "unreliable_ordered")
func _net_time(t: float) -> void:
	if absf(GameState.day_time - t) > 2.0:
		GameState.day_time = t
		for d in get_tree().get_nodes_in_group("day_cycle"):
			if d.has_method("set_time"): d.set_time(t)


func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 160)
	if text == "":
		return
	_net_chat.rpc(player_name, text)
	_show_chat(player_name, text)


@rpc("any_peer", "reliable")
func _net_chat(nm: String, text: String) -> void:
	_show_chat(nm, text)


func _show_chat(nm: String, text: String) -> void:
	stats.chat += 1
	last_chat = "%s: %s" % [nm, text]
	GameState.chat(last_chat, Color(0.65, 0.9, 1.0), true)


func _ensure_chat_ui() -> void:
	if _chat_ui and is_instance_valid(_chat_ui):
		return
	var hud := get_tree().current_scene.get_node_or_null("HUD") if get_tree().current_scene else null
	var root: Node = hud.get_node_or_null("Root") if hud else null
	if root == null:
		return
	_chat_ui = LineEdit.new()
	_chat_ui.name = "NetChat"
	_chat_ui.placeholder_text = "Сообщение игрокам — Enter, отмена — Esc"
	_chat_ui.anchor_left = 0.0; _chat_ui.anchor_right = 0.0; _chat_ui.anchor_top = 1.0; _chat_ui.anchor_bottom = 1.0
	_chat_ui.offset_left = 12; _chat_ui.offset_right = 470; _chat_ui.offset_top = -120; _chat_ui.offset_bottom = -86
	_chat_ui.visible = false
	_chat_ui.text_submitted.connect(func(t: String) -> void:
		send_chat(t)
		_close_chat())
	root.add_child(_chat_ui)


func open_chat() -> void:
	_ensure_chat_ui()
	if _chat_ui == null: return
	_chat_ui.visible = true
	_chat_ui.text = ""
	_chat_ui.grab_focus()
	GameState.console_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_chat() -> void:
	if _chat_ui:
		_chat_ui.visible = false
		_chat_ui.release_focus()
	GameState.console_open = false
	GameState.modal_closed_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not in_world:
		return
	if _chat_ui and _chat_ui.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_chat(); get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("net_chat") and event.is_action_pressed("net_chat") and not GameState.ui_blocked():
		open_chat()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ поиск в локальной сети
func _start_discovery_responder() -> void:
	_disc = PacketPeerUDP.new()
	if _disc.bind(DISC_PORT) != OK:
		_disc = null


func discover(seconds: float = 1.5) -> void:
	_disc_client = PacketPeerUDP.new()
	_disc_client.set_broadcast_enabled(true)
	_disc_client.bind(0)
	_disc_client.set_dest_address("255.255.255.255", DISC_PORT)
	_disc_client.put_packet("SONNAYA?".to_utf8_buffer())
	_disc_found = []
	_disc_t = seconds


func _poll_discovery(delta: float) -> void:
	if _disc:
		while _disc.get_available_packet_count() > 0:
			var pkt := _disc.get_packet().get_string_from_utf8()
			if pkt == "SONNAYA?":
				var ip := _disc.get_packet_ip(); var port := _disc.get_packet_port()
				_disc.set_dest_address(ip, port)
				_disc.put_packet(("SONNAYA!|%s|%s|%d|%d" % [player_name, GameState.world_name, PORT, player_count()]).to_utf8_buffer())
	if _disc_client and _disc_t > 0.0:
		_disc_t -= delta
		while _disc_client.get_available_packet_count() > 0:
			var pkt2 := _disc_client.get_packet().get_string_from_utf8()
			var parts := pkt2.split("|")
			if parts.size() >= 5 and parts[0] == "SONNAYA!":
				_disc_found.append({"ip": _disc_client.get_packet_ip(), "host": parts[1], "world": parts[2], "port": int(parts[3]), "players": int(parts[4])})
		if _disc_t <= 0.0:
			_disc_client.close(); _disc_client = null
			lan_found.emit(_disc_found)


# ------------------------------------------------------------------ цикл
func _process(delta: float) -> void:
	_poll_discovery(delta)
	if not active() or not in_world or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if peers.is_empty() and is_host():
		_reset_shadows_light()
		return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = SYNC_SEC
		_sync_world()
	_pos_t -= delta
	if _pos_t <= 0.0:
		_pos_t = POS_SEC
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p:
			_p_state.rpc(p.global_position, p.rotation.y, str(GameState.get_selected_item().get("id", "")), GameState.is_dream(), GameState.player_hp)
	if is_host():
		_mob_t -= delta
		if _mob_t <= 0.0:
			_mob_t = MOB_SEC
			_mobs.rpc(_mob_list())
		_time_t -= delta
		if _time_t <= 0.0:
			_time_t = TIME_SEC
			_net_time.rpc(GameState.day_time)


func _reset_shadows_light() -> void:
	## Хост один: тени держим актуальными без отправки (иначе первый подключившийся получит дифф поверх снимка).
	_sync_t -= 0.0
	if Engine.get_process_frames() % 30 == 0:
		_reset_shadows()
