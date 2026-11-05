extends Node
## The one door to the network (CLAUDE.md networking rules). Gameplay never touches a transport:
## it asks this autoload who it is (is_host(), local_id()), sends through it and listens to its
## signals. Solo is simply a host with zero clients, so every gameplay path is the same.
##
## Host-authoritative: the host sends enemy snapshots and events; each player sends their own
## InputMessage, which the host validates and passes on to everyone else. A client must pass the
## handshake (game, version, build) before the host sends it anything else.
##
## Two backends look the same from here: `ws` (Godot's WebSocketMultiplayerPeer, the host listens
## itself; headless tests) and `relay` (RelayPeer over Berghittn's Durable Object relay with
## 4-letter room codes; browsers). A session has a roster (LobbyProfile per peer); the host starts the
## run for everyone (start_run), and gameplay only flows to a client once its run scene is loaded
## and it said so (send_run_ready); client_ids() are those players.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## Client: the host accepted the handshake.
signal joined_host
## Client: the host refused us ("version", "build", "game", or a relay reason: "full", "started",
## "no_room") or the connection failed ("connection_failed", "lost").
signal join_failed(reason: String)
## The session ended under us ("host_left", "kicked", "lost").
signal session_ended(reason: String)
## Relay: the room is open (host) or joined (client); its code.
signal room_opened(code: String)
## Anyone's lobby profile changed (or someone came or went).
signal roster_changed
## The host started the run (setup: map, grant, seed, roster), every role.
signal run_start_received(setup: Dictionary)
## The host took everyone back to the lobby after a run.
signal lobby_return_received
## Host: this client's run scene is loaded; gameplay messages flow to it from now on.
signal peer_run_ready(peer_id: int)
signal snapshot_received(data: PackedByteArray)
signal events_received(data: PackedByteArray)
signal player_input_received(peer_id: int, data: PackedByteArray)
signal world_state_received(data: PackedByteArray)
signal brosel_received(data: PackedByteArray)
## Run events from the host (RunEventCodec: attack marks, loot, toasts, bosses, the bus).
signal run_events_received(data: PackedByteArray)
## A Speisekarte message for the local player (OfferCodec: offer, chest or notice).
signal offer_received(data: PackedByteArray)
## Host: a player answered an offer (OfferCodec.Choice).
signal choice_received(peer_id: int, data: PackedByteArray)
## Client: what only the host counted about our run (kills, bosses, our knock-downs ...), at its end.
signal run_summary_received(data: Dictionary)

enum Mode { SOLO, HOST, CLIENT }
enum Backend { NONE, WS, RELAY }

const HOST_ID: int = 1
const DEFAULT_PORT: int = 9080
const MAX_PLAYERS: int = 4
const BUILD_ID_PATH: String = "res://build_id.txt"
## The relay on the live site, for desktop builds (the browser uses its own page's origin).
const SITE: String = "https://knoedlinger.pages.dev"
## Bytes counted per message on top of the payload: Godot's RPC header and the WebSocket frame.
const MESSAGE_OVERHEAD: int = 24
const REJECT_DISCONNECT_DELAY: float = 0.5

var mode: Mode = Mode.SOLO
var backend: Backend = Backend.NONE
var version: String = ""
var build_id: String = "dev"
var bytes_received: int = 0
var bytes_sent: int = 0
var snapshots_received: int = 0
## Relay: this room's 4-letter code.
var room_code: String = ""
## Everyone's LobbyProfile by peer id, ourselves included (the host's copy is the truth).
var profiles: Dictionary[int, Dictionary] = {}
## Our own profile, sent with the handshake and on every change.
var local_profile: Dictionary = {}

# Host: peers that passed the handshake, in join order.
var _accepted: Array[int] = []
# Host: peers whose run scene is loaded (gameplay goes to them).
var _in_run: Array[int] = []
# Client: the host accepted our handshake.
var _joined: bool = false
var _hello_sent: bool = false
# Started from the command line straight into a run (no --lobby): the run scene is already loaded.
var _direct_run: bool = false
var _relay: RelayPeer


func _ready() -> void:
	# Keeps talking while a solo Speisekarte pauses the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
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


## More than one player in this session (in the room, or in the run): co-op rules (no pause, the
## "Bin glei wieder da" sign) apply even while a client is still loading the run.
func is_coop() -> bool:
	return mode != Mode.SOLO and (profiles.size() > 1 or not _in_run.is_empty() or mode == Mode.CLIENT)


func local_id() -> int:
	return HOST_ID if mode == Mode.SOLO else multiplayer.get_unique_id()


## True when gameplay messages may flow: always on a host, on a client once the handshake passed.
func is_session_ready() -> bool:
	return mode != Mode.CLIENT or _joined


## Host: the clients playing the run (their run scene is loaded). Always empty in solo.
func client_ids() -> Array[int]:
	return _in_run.duplicate()


## Host: every client that passed the handshake (the room, loaded or not).
func room_ids() -> Array[int]:
	return _accepted.duplicate()


## The player's name as the room knows it.
func player_name(peer_id: int) -> String:
	return str(profiles.get(peer_id, {}).get("name", ""))


func host_ws(port: int, bind_address: String = "127.0.0.1") -> Error:
	var peer: MultiplayerPeer = WsTransport.host(port, bind_address)
	if peer == null:
		return ERR_CANT_CREATE
	_disable_server_relay()
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	backend = Backend.WS
	profiles = {HOST_ID: local_profile.duplicate(true)}
	print("[NET] LISTENING ws://%s:%d ver=%s build=%s" % [bind_address, port, version, build_id])
	return OK


func join_ws(address: String, port: int) -> Error:
	var peer: MultiplayerPeer = WsTransport.join(address, port)
	if peer == null:
		return ERR_CANT_CONNECT
	_disable_server_relay()
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	backend = Backend.WS
	print("[NET] JOINING ws://%s:%d" % [address, port])
	return OK


## Opens a new room on the relay; room_opened tells the code.
func host_relay() -> Error:
	return _open_relay("new")


## Joins the room with this code on the relay.
func join_relay(code: String) -> Error:
	code = RoomCode.normalize(code)
	if not RoomCode.is_valid(code):
		return ERR_INVALID_PARAMETER
	return _open_relay(code)


## Where the relay is: --relay=<url> / ?relay=<url> (tests: a local wrangler dev), else the page's own
## origin in the browser, else the live site.
func relay_base() -> String:
	if LaunchArgs.has("relay"):
		return LaunchArgs.get_string("relay")
	if OS.has_feature("web"):
		var origin: String = str(JavaScriptBridge.eval("location.origin", true))
		return origin.replace("https://", "wss://").replace("http://", "ws://")
	return SITE.replace("https://", "wss://")


## The link that opens the game straight into this room (?room=KNDL).
func invite_url() -> String:
	var page: String = SITE + "/"
	if OS.has_feature("web"):
		page = str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	return "%s?room=%s" % [page, room_code]


func leave() -> void:
	if _relay != null:
		_relay.control.disconnect(_on_relay_control)
		_relay = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_accepted.clear()
	_in_run.clear()
	profiles.clear()
	room_code = ""
	_joined = false
	_hello_sent = false
	mode = Mode.SOLO
	backend = Backend.NONE


## Our own lobby profile changed (name, character, the host's map and Grant level).
func send_profile(profile: Dictionary) -> void:
	local_profile = LobbyProfile.sanitize(profile)
	if mode == Mode.SOLO:
		return
	if is_host():
		profiles[HOST_ID] = local_profile.duplicate(true)
		_send_roster()
		roster_changed.emit()
	elif _joined:
		_rx_profile.rpc_id(HOST_ID, local_profile)


## Host: the roster changed by the host's rules (a character handed out); everyone hears it.
func set_profile(peer_id: int, profile: Dictionary) -> void:
	if mode != Mode.HOST or not profiles.has(peer_id):
		return
	profiles[peer_id] = LobbyProfile.sanitize(profile)
	if peer_id == HOST_ID:
		local_profile = profiles[peer_id].duplicate(true)
	_send_roster()
	roster_changed.emit()


## Host: everyone into the run. Nobody else may join the room until back_to_lobby().
func start_run(setup: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	if _relay != null:
		_relay.send_control({"t": "start"})
	_in_run.clear()
	for peer: int in _accepted:
		if _can_send(peer):
			_rx_start.rpc_id(peer, setup)
	run_start_received.emit(setup)


## Host: after a run, everyone back to the room (joining is open again).
func back_to_lobby() -> void:
	if mode != Mode.HOST:
		return
	if _relay != null:
		_relay.send_control({"t": "lobby"})
	_in_run.clear()
	for peer: int in _accepted:
		if _can_send(peer):
			_rx_lobby.rpc_id(peer)
	lobby_return_received.emit()


## Client: our run scene is loaded, send us the world.
func send_run_ready() -> void:
	if mode == Mode.CLIENT and _joined:
		_rx_run_ready.rpc_id(HOST_ID)


## Host: sends a player out of the room.
func kick(peer_id: int) -> void:
	if mode == Mode.HOST and peer_id != HOST_ID and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## Host: the enemy snapshot to every client in the run (unreliable_ordered; see docs/DECISIONS.md).
func send_snapshot(data: PackedByteArray) -> void:
	for peer: int in _in_run:
		if not _can_send(peer):
			continue
		_rx_snapshot.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: spawn/death events to every client in the run, reliable.
func send_events(data: PackedByteArray) -> void:
	for peer: int in _in_run:
		if not _can_send(peer):
			continue
		_rx_events.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: the per-player world state (WorldStateCodec) to every client in the run, newest wins.
func send_world_state(data: PackedByteArray) -> void:
	for peer: int in _in_run:
		if not _can_send(peer):
			continue
		_rx_world_state.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: Brösel changes (BroselCodec) to every client in the run, reliable and in order.
func send_brosel(data: PackedByteArray) -> void:
	for peer: int in _in_run:
		if not _can_send(peer):
			continue
		_rx_brosel.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: Brösel changes to one client (the full set when it joins).
func send_brosel_to(peer: int, data: PackedByteArray) -> void:
	if mode != Mode.HOST or not _in_run.has(peer) or not _can_send(peer):
		return
	_rx_brosel.rpc_id(peer, data)
	bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: run events (RunEventCodec) to every client in the run, reliable and in order.
func send_run_events(data: PackedByteArray) -> void:
	for peer: int in _in_run:
		if not _can_send(peer):
			continue
		_rx_run_events.rpc_id(peer, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: run events to one client (everything lying around when it joins).
func send_run_events_to(peer: int, data: PackedByteArray) -> void:
	if mode != Mode.HOST or not _in_run.has(peer) or not _can_send(peer):
		return
	_rx_run_events.rpc_id(peer, data)
	bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: a Speisekarte message for one player, reliable. The host's own player (and solo) gets it
## locally, a frame later, like any network message.
func send_offer(peer_id: int, data: PackedByteArray) -> void:
	if not is_host():
		return
	if peer_id == local_id():
		offer_received.emit.call_deferred(data)
		return
	if not _in_run.has(peer_id) or not _can_send(peer_id):
		return
	_rx_offer.rpc_id(peer_id, data)
	bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: the end-of-run numbers only the host keeps, to one client (reliable).
func send_run_summary(peer_id: int, data: Dictionary) -> void:
	if mode == Mode.HOST and _in_run.has(peer_id) and _can_send(peer_id):
		_rx_run_summary.rpc_id(peer_id, data)


## The local player's answer to an offer: to the host, or straight to the host's own handler.
func send_choice(data: PackedByteArray) -> void:
	if is_host():
		choice_received.emit.call_deferred(local_id(), data)
	elif _joined:
		_rx_choice.rpc_id(HOST_ID, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD


## The local player's InputMessage: a client sends it to the host, the host to every client.
func send_input(data: PackedByteArray) -> void:
	if mode == Mode.CLIENT:
		if not _joined:
			return
		_rx_input.rpc_id(HOST_ID, data)
		bytes_sent += data.size() + MESSAGE_OVERHEAD
	elif mode == Mode.HOST:
		for peer: int in _in_run:
			if not _can_send(peer):
				continue
			_rx_peer_input.rpc_id(peer, HOST_ID, data)
			bytes_sent += data.size() + MESSAGE_OVERHEAD


## Host: everything of this world send goes out now (relay; the WebSocket backend sends at once).
func flush() -> void:
	if _relay != null:
		_relay.flush_now()


## How far in the past clients show the host's enemies: more over the relay (a Cloudflare hop and
## batching) than on the local WebSocket.
func interpolation_delay_ms(balance: BalanceData) -> float:
	return balance.relay_interpolation_delay_ms if backend == Backend.RELAY else balance.interpolation_delay_ms


## Relay traffic since the room opened (both ways), for the F3 overlay.
func relay_traffic() -> Vector2i:
	return Vector2i(_relay.bytes_in, _relay.bytes_out) if _relay != null else Vector2i.ZERO


## Clients only ever talk to the host, and this autoload passes player messages on itself. Godot's
## own relay would also announce every join and leave to every client, sockets that are already
## closing included.
func _disable_server_relay() -> void:
	var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		scene_multiplayer.server_relay = false


func _open_relay(path: String) -> Error:
	leave()
	_relay = RelayPeer.new()
	_relay.control.connect(_on_relay_control)
	var url: String = "%s/api/room/%s?%s" % [relay_base(), path, Handshake.query(version, build_id)]
	var error: Error = _relay.open(url)
	if error != OK:
		_relay = null
		return error
	multiplayer.multiplayer_peer = _relay
	_disable_server_relay()
	backend = Backend.RELAY
	# Until the relay's welcome says which id we got.
	mode = Mode.CLIENT
	print("[NET] RELAY %s" % url)
	return OK


func _on_relay_control(message: Dictionary) -> void:
	match String(message.get("t", "")):
		"welcome":
			room_code = String(message.get("code", ""))
			if int(message.get("id", 0)) == HOST_ID:
				mode = Mode.HOST
				profiles = {HOST_ID: local_profile.duplicate(true)}
				print("[NET] ROOM %s open ver=%s build=%s" % [room_code, version, build_id])
			else:
				print("[NET] ROOM %s joined as peer %d" % [room_code, int(message.get("id", 0))])
				_send_hello()
			room_opened.emit(room_code)
		"closed":
			var reason: String = String(message.get("reason", "lost"))
			var was_joined: bool = mode == Mode.HOST or _joined
			leave()
			if was_joined:
				session_ended.emit(reason)
			else:
				join_failed.emit(reason)


func _start_from_args() -> void:
	if LaunchArgs.has("name") or local_profile.is_empty():
		local_profile = LobbyProfile.make(LaunchArgs.get_string("name", "Knödlinger"), RunSetup.character_id(), {}, [])
	_direct_run = LaunchArgs.has("net") and not LaunchArgs.has("lobby")
	match LaunchArgs.get_string("net"):
		"ws":
			var port: int = LaunchArgs.get_int("port", DEFAULT_PORT)
			if LaunchArgs.get_flag("host"):
				host_ws(port, LaunchArgs.get_string("bind", "127.0.0.1"))
			elif LaunchArgs.has("join"):
				join_ws(LaunchArgs.get_string("join", "127.0.0.1"), port)
		"relay":
			if LaunchArgs.get_flag("host"):
				host_relay()
			elif LaunchArgs.has("room"):
				join_relay(LaunchArgs.get_string("room"))


func _send_hello() -> void:
	if _hello_sent:
		return
	_hello_sent = true
	_hello.rpc_id(HOST_ID, Handshake.GAME_ID, version, build_id, local_profile)


func _send_roster() -> void:
	for peer: int in _accepted:
		if _can_send(peer):
			_rx_roster.rpc_id(peer, profiles)


func _on_peer_connected(peer_id: int) -> void:
	if mode == Mode.HOST:
		print("[NET] peer %d connected, waiting for its handshake" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.HOST or not _accepted.has(peer_id):
		return
	_accepted.erase(peer_id)
	_in_run.erase(peer_id)
	profiles.erase(peer_id)
	print("[NET] peer %d left" % peer_id)
	for peer: int in _accepted:
		if _can_send(peer):
			_rx_peer_left.rpc_id(peer, peer_id)
	_send_roster()
	peer_left.emit(peer_id)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	if backend == Backend.WS:
		_send_hello()


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("connection_failed")


func _on_server_disconnected() -> void:
	if backend == Backend.RELAY:
		# The relay says why ("closed") before it goes; that message ends the session.
		return
	leave()
	session_ended.emit("host_left")


@rpc("any_peer", "call_remote", "reliable")
func _hello(game: String, their_version: String, their_build: String, profile: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var reason: String = Handshake.check(game, their_version, their_build, version, build_id)
	if reason == Handshake.OK_REASON and _accepted.size() >= MAX_PLAYERS - 1:
		reason = "full"
	if reason != Handshake.OK_REASON:
		print("[NET] peer %d refused: %s (theirs %s/%s, ours %s/%s)" % [sender, reason, their_version, their_build, version, build_id])
		_rejected.rpc_id(sender, reason)
		get_tree().create_timer(REJECT_DISCONNECT_DELAY).timeout.connect(_drop_peer.bind(sender))
		return
	if _accepted.has(sender):
		return
	_accepted.append(sender)
	profiles[sender] = LobbyProfile.sanitize(profile)
	print("[NET] peer %d joined (%s, %s)" % [sender, profiles[sender]["name"], profiles[sender]["character"]])
	_welcome.rpc_id(sender)
	peer_joined.emit(sender)
	_send_roster()
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _welcome() -> void:
	_joined = true
	print("[NET] JOINED as peer %d" % multiplayer.get_unique_id())
	joined_host.emit()
	if _direct_run:
		send_run_ready()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	print("[NET] REJECTED %s" % reason)
	join_failed.emit(reason)


@rpc("any_peer", "call_remote", "reliable")
func _rx_profile(profile: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or not _accepted.has(sender):
		return
	profiles[sender] = LobbyProfile.sanitize(profile)
	_send_roster()
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rx_roster(data: Dictionary) -> void:
	profiles.clear()
	for peer: Variant in data:
		if peer is int:
			profiles[peer] = LobbyProfile.sanitize(data[peer])
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rx_start(setup: Dictionary) -> void:
	run_start_received.emit(setup)


@rpc("authority", "call_remote", "reliable")
func _rx_lobby() -> void:
	lobby_return_received.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rx_run_ready() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or not _accepted.has(sender) or _in_run.has(sender):
		return
	_in_run.append(sender)
	print("[NET] peer %d is in the run" % sender)
	peer_run_ready.emit(sender)


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


@rpc("authority", "call_remote", "reliable")
func _rx_run_events(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	run_events_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rx_offer(data: PackedByteArray) -> void:
	bytes_received += data.size() + MESSAGE_OVERHEAD
	offer_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _rx_run_summary(data: Dictionary) -> void:
	run_summary_received.emit(data)


@rpc("any_peer", "call_remote", "reliable")
func _rx_choice(data: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or not _in_run.has(sender):
		return
	bytes_received += data.size() + MESSAGE_OVERHEAD
	choice_received.emit(sender, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rx_input(data: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if mode != Mode.HOST or not _in_run.has(sender):
		return
	bytes_received += data.size() + MESSAGE_OVERHEAD
	player_input_received.emit(sender, data)
	for peer: int in _in_run:
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
	if multiplayer.multiplayer_peer == null:
		return false
	var websocket: WebSocketMultiplayerPeer = multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if websocket == null:
		return multiplayer.get_peers().has(peer_id)
	var socket: WebSocketPeer = websocket.get_peer(peer_id)
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _drop_peer(peer_id: int) -> void:
	# The refused client may have hung up on its own already.
	if multiplayer.multiplayer_peer != null and mode == Mode.HOST and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
