extends Node
## The one door to the network (CLAUDE.md networking rules). Gameplay never touches a transport:
## it asks this autoload who it is (is_host(), local_id()), sends through it and listens to its
## signals. Solo is simply a host with zero clients, so every gameplay path is the same.
##
## Host-authoritative: the host sends enemy snapshots and events; each player sends their own
## InputMessage, which the host validates and passes on to everyone else. A client must pass the
## handshake (game, version, build) before the host sends it anything else.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## Client: the host accepted the handshake.
signal joined_host
## Client: the host refused us ("version", "build", "game") or the connection failed.
signal join_failed(reason: String)
## The session ended under us ("host_left").
signal session_ended(reason: String)
signal snapshot_received(data: PackedByteArray)
signal events_received(data: PackedByteArray)
signal player_input_received(peer_id: int, data: PackedByteArray)
signal world_state_received(data: PackedByteArray)
signal brosel_received(data: PackedByteArray)

enum Mode { SOLO, HOST, CLIENT }

const HOST_ID: int = 1
const DEFAULT_PORT: int = 9080
const BUILD_ID_PATH: String = "res://build_id.txt"
## Bytes counted per message on top of the payload: Godot's RPC header and the WebSocket frame.
const MESSAGE_OVERHEAD: int = 24
const REJECT_DISCONNECT_DELAY: float = 0.5

var mode: Mode = Mode.SOLO
var version: String = ""
var build_id: String = "dev"
var bytes_received: int = 0
var bytes_sent: int = 0
var snapshots_received: int = 0

# Host: peers that passed the handshake, in join order.
var _accepted: Array[int] = []
# Client: the host accepted our handshake.
var _joined: bool = false


func _ready() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", "0"))
	if FileAccess.file_exists(BUILD_ID_PATH):
		build_id = FileAccess.get_file_as_string(BUILD_ID_PATH).strip_edges()
	# Test hooks: pretend to be another version or build (mp_test.ps1 checks the refusal).
	version = LaunchArgs.get_string("fake-ver", version)
	build_id = LaunchArgs.get_string("fake-build", build_id)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_start_from_args()


func is_host() -> bool:
	return mode != Mode.CLIENT


func is_online() -> bool:
	return mode != Mode.SOLO


func local_id() -> int:
	return HOST_ID if mode == Mode.SOLO else multiplayer.get_unique_id()


## True when gameplay messages may flow: always on a host, on a client once the handshake passed.
func is_session_ready() -> bool:
	return mode != Mode.CLIENT or _joined


## Host: the clients that passed the handshake. Always empty in solo.
func client_ids() -> Array[int]:
	return _accepted.duplicate()


func host_ws(port: int, bind_address: String = "127.0.0.1") -> Error:
	var peer: MultiplayerPeer = WsTransport.host(port, bind_address)
	if peer == null:
		return ERR_CANT_CREATE
	_disable_server_relay()
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	print("[NET] LISTENING ws://%s:%d ver=%s build=%s" % [bind_address, port, version, build_id])
	return OK


func join_ws(address: String, port: int) -> Error:
	var peer: MultiplayerPeer = WsTransport.join(address, port)
	if peer == null:
		return ERR_CANT_CONNECT
	_disable_server_relay()
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	print("[NET] JOINING ws://%s:%d" % [address, port])
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_accepted.clear()
	_joined = false
	mode = Mode.SOLO


## Host: the enemy snapshot to every accepted client (unreliable_ordered; see docs/DECISIONS.md).
func send_snapshot(data: PackedByteArray) -> void:
	for peer: int in _accepted:
		if not _can_send(peer):
			continue
		_rx_snapshot.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: spawn/death events to every accepted client, reliable.
func send_events(data: PackedByteArray) -> void:
	for peer: int in _accepted:
		if not _can_send(peer):
			continue
		_rx_events.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: the per-player world state (WorldStateCodec) to every accepted client, newest wins.
func send_world_state(data: PackedByteArray) -> void:
	for peer: int in _accepted:
		if not _can_send(peer):
			continue
		_rx_world_state.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: Brösel changes (BroselCodec) to every accepted client, reliable and in order.
func send_brosel(data: PackedByteArray) -> void:
	for peer: int in _accepted:
		if not _can_send(peer):
			continue
		_rx_brosel.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: Brösel changes to one client (the full set when it joins).
func send_brosel_to(peer: int, data: PackedByteArray) -> void:
	if mode != Mode.HOST or not _accepted.has(peer) or not _can_send(peer):
		return
	_rx_brosel.rpc_id(peer, data)
	bytes_sent += data.size() + MESSAGE_OVERHEAD


## The local player's InputMessage: a client sends it to the host, the host to every client.
func send_input(data: PackedByteArray) -> void:
	if mode == Mode.CLIENT:
		if not _joined:
			return
		_rx_input.rpc_id(HOST_ID, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD
	elif mode == Mode.HOST:
		for peer: int in _accepted:
			if not _can_send(peer):
				continue
			_rx_peer_input.rpc_id(peer, HOST_ID, data)
			bytes_sent += data.size() + MESSAGE_OVERHEAD


## Clients only ever talk to the host, and this autoload passes player messages on itself. Godot's
## own relay would also announce every join and leave to every client, sockets that are already
## closing included.
func _disable_server_relay() -> void:
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		scene_multiplayer.server_relay = false


func _start_from_args() -> void:
	if LaunchArgs.get_string("net") != "ws":
		return
	var port: int = LaunchArgs.get_int("port", DEFAULT_PORT)
	if LaunchArgs.get_flag("host"):
		host_ws(port, LaunchArgs.get_string("bind", "127.0.0.1"))
	elif LaunchArgs.has("join"):
		join_ws(LaunchArgs.get_string("join", "127.0.0.1"), port)


func _on_peer_connected(peer_id: int) -> void:
	if mode == Mode.HOST:
		print("[NET] peer %d connected, waiting for its handshake" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.HOST or not _accepted.has(peer_id):
		return
	_accepted.erase(peer_id)
	print("[NET] peer %d left" % peer_id)
	for peer: int in _accepted:
		if _can_send(peer):
			_rx_peer_left.rpc_id(peer, peer_id)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	_hello.rpc_id(HOST_ID, Handshake.GAME_ID, version, build_id)


func _on_connection_failed() -> void:
	mode = Mode.SOLO
	join_failed.emit("connection_failed")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_joined = false
	mode = Mode.SOLO
	session_ended.emit("host_left")


@rpc("any_peer", "call_remote", "reliable")
func _hello(game: String, their_version: String, their_build: String) -> void:
	if mode != Mode.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var reason: String = Handshake.check(game, their_version, their_build, version, build_id)
	if reason != Handshake.OK_REASON:
		print("[NET] peer %d refused: %s (theirs %s/%s, ours %s/%s)" % [sender, reason, their_version, their_build, version, build_id])
		_rejected.rpc_id(sender, reason)
		get_tree().create_timer(REJECT_DISCONNECT_DELAY).timeout.connect(_drop_peer.bind(sender))
		return
	if _accepted.has(sender):
		return
	_accepted.append(sender)
	print("[NET] peer %d joined" % sender)
	_welcome.rpc_id(sender)
	peer_joined.emit(sender)


@rpc("authority", "call_remote", "reliable")
func _welcome() -> void:
	_joined = true
	print("[NET] JOINED as peer %d" % multiplayer.get_unique_id())
	joined_host.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	print("[NET] REJECTED %s" % reason)
	join_failed.emit(reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_snapshot(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	snapshots_received += 1
	snapshot_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rx_events(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	events_received.emit(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_world_state(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	world_state_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rx_brosel(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	brosel_received.emit(data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rx_input(data: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or not _accepted.has(sender):
		return
	bytes_received += data.size() + MESSAGE_OVERHEAD
	player_input_received.emit(sender, data)
	for peer: int in _accepted:
		if peer != sender and _can_send(peer):
			_rx_peer_input.rpc_id(peer, sender, data)
			bytes_sent += data.size() + MESSAGE_OVERHEAD


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_peer_input(peer_id: int, data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	player_input_received.emit(peer_id, data)


@rpc("authority", "call_remote", "reliable")
func _rx_peer_left(peer_id: int) -> void:
	peer_left.emit(peer_id)


## Host: false for a peer whose socket is already closing, before Godot reports it gone; sending
## to it would only log an error.
func _can_send(peer_id: int) -> bool:
	var websocket: WebSocketMultiplayerPeer = multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if websocket == null:
		return true
	var socket: WebSocketPeer = websocket.get_peer(peer_id)
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _drop_peer(peer_id: int) -> void:
	# The refused client may have hung up on its own already.
	if multiplayer.multiplayer_peer != null and mode == Mode.HOST and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
