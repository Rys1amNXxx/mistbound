class_name GameSession
extends Node
## Transport/session lifecycle. Host is authoritative; clients own only input intent.

signal started()
signal ended(reason: String)
signal message(text: String)

const Store = preload("res://scripts/systems/save_store.gd")
const Catalog = preload("res://scripts/systems/item_catalog.gd")
const PROTOCOL_VERSION := 2
const DEFAULT_PORT := 24570
const MAX_PLAYERS := 4

var simulation: Node2D
var active: bool = false
var mode: String = "offline"
var local_id: int = 1
var _pending: Dictionary = {}
var _action_times: Dictionary = {}
var _snapshot_timer: float = 0.0
var _save_timer: float = 0.0
var _connection_timer: float = 0.0
var _last_character_json: String = ""
var _last_world_json: String = ""

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): stop("连接失败：检查房主地址、UDP 端口和防火墙。"))
	multiplayer.server_disconnected.connect(func(): stop("房主已离开。已确认的角色进度保存在本机。"))
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)

func configure(world: Node2D) -> void:
	simulation = world
	simulation.notice.connect(_on_notice)
	simulation.checkpoint.connect(_checkpoint)

func start_solo() -> Error:
	_prepare(true)
	mode = "offline"
	active = true
	local_id = 1
	simulation.add_player(1, Store.load_character())
	simulation.enter_zone("camp")
	started.emit()
	return OK

func host(port: int = DEFAULT_PORT) -> Error:
	if port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	_prepare(true)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1, 3)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	mode = "host"
	active = true
	local_id = 1
	simulation.add_player(1, Store.load_character())
	simulation.enter_zone("camp")
	started.emit()
	message.emit("房间已创建 · UDP %d · 最多 4 人" % port)
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	_prepare(false)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port, 3)
	if error != OK:
		return error
	mode = "client"
	local_id = 0
	_connection_timer = 10.0
	multiplayer.multiplayer_peer = peer
	return OK

func _prepare(is_authority: bool) -> void:
	if active:
		save_now()
	active = false
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending.clear()
	_action_times.clear()
	_snapshot_timer = 0.0
	_save_timer = 0.0
	_connection_timer = 0.0
	_last_character_json = ""
	_last_world_json = ""
	simulation.reset(is_authority, Store.load_world() if is_authority else {})

func stop(reason: String = "已返回主菜单。") -> void:
	var save_ok := save_now() if active else true
	active = false
	_connection_timer = 0.0
	mode = "offline"
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_pending.clear()
	_action_times.clear()
	simulation.reset(true)
	ended.emit(reason if save_ok else reason + " 存档写入失败，请检查目录权限。")

func _physics_process(delta: float) -> void:
	if active and mode != "client":
		simulation.step(delta)

func _process(delta: float) -> void:
	if _connection_timer > 0:
		_connection_timer -= delta
		if _connection_timer <= 0:
			stop("连接超时：请确认房主已开房，且 UDP 端口可达。")
	if mode == "host":
		for id in _pending.keys():
			_pending[id] -= delta
			if float(_pending[id]) <= 0:
				_pending.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)
	if not active:
		return
	_snapshot_timer += delta
	_save_timer += delta
	if mode == "host" and _snapshot_timer >= 0.1:
		_snapshot_timer = 0.0
		_broadcast_snapshot(false)
	if _save_timer >= 5.0:
		_save_timer = 0.0
		save_now()

func send_input(motion: Vector2, aim: Vector2, attack: bool) -> void:
	if not active:
		return
	if mode == "client":
		_submit_input.rpc_id(1, simulation.epoch, motion, aim, attack)
	else:
		simulation.set_input(1, motion, aim, attack)

func action(action_name: String, argument: String = "") -> void:
	if not active:
		return
	if mode == "client":
		_request_action.rpc_id(1, simulation.epoch, action_name, argument)
	else:
		simulation.act(1, action_name, argument)

func _peer_connected(id: int) -> void:
	if mode == "host":
		_pending[id] = 8.0

func _peer_disconnected(id: int) -> void:
	_pending.erase(id)
	_action_times.erase(id)
	if mode == "host" and simulation.players.has(id):
		simulation.remove_player(id)
		_broadcast_snapshot(true)
		_on_notice(0, "一名旅人离开了队伍")

func _connected() -> void:
	if mode != "client":
		return
	local_id = multiplayer.get_unique_id()
	_register_player.rpc_id(1, PROTOCOL_VERSION, Store.load_character())

@rpc("any_peer", "call_remote", "reliable", 0)
func _register_player(version: int, profile: Dictionary) -> void:
	if mode != "host" or not active:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _pending.has(sender) or simulation.players.has(sender):
		return
	if version != PROTOCOL_VERSION or simulation.players.size() >= MAX_PLAYERS or JSON.stringify(profile).length() > 16384:
		_rejected.rpc_id(sender, "版本不兼容、房间已满或角色数据无效。")
		_pending[sender] = 0.5
		return
	_pending.erase(sender)
	simulation.add_player(sender, Catalog.sanitize_profile(profile))
	_broadcast_snapshot(true)
	_on_notice(0, "一名旅人加入了队伍")

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_input(input_epoch: int, motion: Vector2, aim: Vector2, attack: bool) -> void:
	if mode != "host" or not active or input_epoch != simulation.epoch:
		return
	simulation.set_input(multiplayer.get_remote_sender_id(), motion, aim, attack)

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_action(input_epoch: int, action_name: String, argument: String) -> void:
	if mode != "host" or not active or input_epoch != simulation.epoch:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not simulation.players.has(sender) or action_name not in ["dash", "interact", "equip"] or argument.length() > 64:
		return
	var now := Time.get_ticks_msec()
	var action_times: Dictionary = _action_times.get(sender, {})
	# Independent actions may legitimately arrive in the same frame (pickup then
	# equip, or dash then interact). Only repeated requests of one type are throttled.
	if now - int(action_times.get(action_name, -1000)) < 100:
		return
	action_times[action_name] = now
	_action_times[sender] = action_times
	simulation.act(sender, action_name, argument)

func _broadcast_snapshot(reliable: bool) -> void:
	if mode != "host":
		return
	var state: Dictionary = simulation.snapshot()
	# Bound unreliable packets below the path MTU; larger snapshots use ENet's
	# reliable fragmentation. This is intentionally a small-room baseline.
	var packet: PackedByteArray = var_to_bytes(state).compress(FileAccess.COMPRESSION_DEFLATE)
	for id in simulation.players:
		if id != 1:
			if reliable or packet.size() > 1000:
				_receive_checkpoint.rpc_id(id, state)
			else:
				_receive_packet.rpc_id(id, packet)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_packet(packet: PackedByteArray) -> void:
	if packet.size() > 1000:
		return
	var raw: PackedByteArray = packet.decompress_dynamic(131072, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return
	var state: Variant = bytes_to_var(raw)
	if state is Dictionary:
		_receive_state(state)

func _receive_state(state: Dictionary) -> void:
	_ingest(state, false)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_checkpoint(state: Dictionary) -> void:
	_ingest(state, true)

func _ingest(state: Dictionary, persist: bool) -> void:
	if mode != "client":
		return
	if not simulation.apply_snapshot(state, local_id):
		return
	if not active and simulation.players.has(local_id):
		active = true
		_connection_timer = 0.0
		started.emit()
	if persist:
		save_now()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(reason: String) -> void:
	stop(reason)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_notice(text: String) -> void:
	message.emit(text)

func _on_notice(peer_id: int, text: String) -> void:
	if peer_id == 0 or peer_id == local_id:
		message.emit(text)
	if mode == "host":
		for id in simulation.players:
			if id != 1 and (peer_id == 0 or peer_id == id):
				_receive_notice.rpc_id(id, text)

func _checkpoint() -> void:
	if not active:
		return
	save_now()
	_broadcast_snapshot(true)

func save_now() -> bool:
	if not active:
		return true
	var ok := true
	var profile: Dictionary = simulation.get_profile(local_id)
	if not profile.is_empty():
		var character_json := JSON.stringify(profile)
		if character_json != _last_character_json:
			if Store.save_character(profile) == OK:
				_last_character_json = character_json
			else:
				ok = false
	if mode != "client":
		var world_json := JSON.stringify(simulation.world_data)
		if world_json != _last_world_json:
			if Store.save_world(simulation.world_data) == OK:
				_last_world_json = world_json
			else:
				ok = false
	if not ok:
		message.emit("存档写入失败，请检查存档目录权限及剩余空间。")
	return ok
