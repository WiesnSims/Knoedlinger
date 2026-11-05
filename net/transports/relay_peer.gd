class_name RelayPeer
extends MultiplayerPeerExtension
## Godot's multiplayer over the co-op relay (Berghittn's RelayPeer, docs/DECISIONS.md M6): one WebSocket to the room's
## Durable Object, which forwards frames between the players. The host is peer 1, as Godot expects.
##
## Every packet Godot queues goes into a frame that is sent FLUSH_INTERVAL_MS later at the
## latest, so a player sends about 20 frames a second whatever the game does: the relay bills
## incoming frames, not packets. Frame: [target i8] then [length u16][packet] for each packet.
## SceneMultiplayer sends an rpc() to everyone as one copy per peer, one after the other; the same
## packet for several peers in a row goes out once, to 0 (everyone) or -n (all but n), so 4 players
## cost no more frames or upload than 2. A new frame starts only where the target changes, and the
## frames go out in order, so each peer still gets everything in the order it was sent.
## Text frames are the relay's JSON control messages (welcome, joined, left, closed).
## bytes_in and bytes_out count every frame both ways, for the F3 overlay and the bandwidth test.

## A relay control message NetworkManager cares about: welcome, closed.
signal control(message: Dictionary)

const LENGTH_BYTES: int = 2
## A target byte 0x20 | mask names exactly the peers in the mask (bit k = peer k + 1).
const MASK_TARGET: int = 0x20
## Every queued packet goes out within this (about 20 frames a second: the relay bills frames).
const FLUSH_INTERVAL_MS: int = 50
## A quiet lobby says "ping" this often so the connection stays open.
const PING_INTERVAL_MS: int = 20000
## The relay refuses frames over 64 KiB; a frame is sent early once it grows past this.
const FRAME_SOFT_LIMIT: int = 48 * 1024
const SOCKET_BUFFER: int = 1 << 20

var bytes_in: int = 0
var bytes_out: int = 0
var _socket := WebSocketPeer.new()
var _status: ConnectionStatus = CONNECTION_DISCONNECTED
var _id: int = 0
var _target: int = 0
var _mode: TransferMode = TRANSFER_MODE_RELIABLE
var _channel: int = 0
var _refusing: bool = false
var _peers: Array[int] = []
# Arrived packets: [sender, PackedByteArray].
var _incoming: Array = []
# The frames to send, in order; the last one is being filled.
var _frames: Array[PackedByteArray] = []
# The packet put last and the peers it is for, kept back to see if it is a broadcast.
var _held: PackedByteArray = PackedByteArray()
var _held_for: Array[int] = []
var _last_flush: int = 0
var _last_ping: int = 0
var _close_reason: String = ""


func open(url: String) -> Error:
	_socket.outbound_buffer_size = SOCKET_BUFFER
	_socket.inbound_buffer_size = SOCKET_BUFFER
	var error: Error = _socket.connect_to_url(url)
	if error == OK:
		_status = CONNECTION_CONNECTING
	return error


## Sends a control message to the relay (host only: start, kick).
func send_control(message: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_text(JSON.stringify(message))


func _poll() -> void:
	_socket.poll()
	while _socket.get_available_packet_count() > 0:
		var data: PackedByteArray = _socket.get_packet()
		bytes_in += data.size()
		if _socket.was_string_packet():
			var text: String = data.get_string_from_utf8()
			# The keep-alive answer is plain text, not JSON.
			if text != "pong":
				_on_control(JSON.parse_string(text))
		else:
			_unpack(data)
	var state: WebSocketPeer.State = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		if _status != CONNECTION_DISCONNECTED:
			_drop()
		return
	if state != WebSocketPeer.STATE_OPEN or _status != CONNECTION_CONNECTED:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_flush >= FLUSH_INTERVAL_MS:
		_flush()
		_last_flush = now
	# The relay answers "ping" without waking up; it keeps a quiet lobby's connection alive.
	if now - _last_ping >= PING_INTERVAL_MS:
		_send_text("ping")
		_last_ping = now


func _on_control(message: Variant) -> void:
	if not message is Dictionary:
		return
	var m: Dictionary = message
	match String(m.get("t", "")):
		"welcome":
			_id = int(m["id"])
			_status = CONNECTION_CONNECTED
			_last_flush = Time.get_ticks_msec()
			_last_ping = _last_flush
			# Peers first: an RPC sent from the welcome handler needs its target known.
			for peer: Variant in m.get("peers", []):
				_add_peer(int(peer))
			control.emit(m)
		"joined":
			_add_peer(int(m["id"]))
		"left":
			_remove_peer(int(m["id"]))
		"closed":
			_close_reason = String(m.get("reason", ""))
			_socket.close()


func _add_peer(peer: int) -> void:
	if peer in _peers or peer == _id:
		return
	_peers.append(peer)
	peer_connected.emit(peer)


func _remove_peer(peer: int) -> void:
	if not peer in _peers:
		return
	_peers.erase(peer)
	peer_disconnected.emit(peer)


func _drop() -> void:
	# The relay's "closed" message can arrive in the same poll as the close itself, and a closed
	# socket hands out no more packets; the close reason says the same.
	if _close_reason == "":
		_close_reason = _socket.get_close_reason()
	for peer: int in _peers.duplicate():
		_remove_peer(peer)
	_status = CONNECTION_DISCONNECTED
	_frames.clear()
	_held_for.clear()
	_incoming.clear()
	control.emit({"t": "closed", "reason": _close_reason if _close_reason != "" else "lost"})


func _unpack(data: PackedByteArray) -> void:
	if data.size() < 1 + LENGTH_BYTES:
		return
	var sender: int = data[0]
	var at: int = 1
	while at + LENGTH_BYTES <= data.size():
		var length: int = data.decode_u16(at)
		at += LENGTH_BYTES
		if at + length > data.size():
			return
		_incoming.append([sender, data.slice(at, at + length)])
		at += length


## Sends everything queued now (the host after each world send: snapshots leave at a steady rate
## instead of beating against the flush timer).
func flush_now() -> void:
	if _status == CONNECTION_CONNECTED and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_flush()
		_last_flush = Time.get_ticks_msec()


func _flush() -> void:
	_queue_held()
	for frame: PackedByteArray in _frames:
		_send(frame)
	_frames.clear()


## The held packet into the frames, once for all the peers it is for.
func _queue_held() -> void:
	if _held_for.is_empty():
		return
	# Several peers at once go out as an exact mask (0x20 | bit per peer id - 1), never as "everyone":
	# the relay may already know a newcomer we have not heard of, who must not get this (Godot's
	# path cache refuses a packet twice, M6 browser check).
	var mask: int = 0
	for peer: int in _held_for:
		if peer >= 1 and peer <= 5:
			mask |= 1 << (peer - 1)
		else:
			mask = -1
			break
	if _held_for.has(0):
		_queue(0, _held)
	elif _held_for.size() > 1 and mask > 0:
		_queue(MASK_TARGET | mask, _held)
	else:
		for peer: int in _held_for:
			_queue(peer, _held)
	_held_for.clear()


func _queue(target: int, buffer: PackedByteArray) -> void:
	if _frames.is_empty() or _frames.back()[0] != target & 0xff:
		_frames.append(PackedByteArray([target & 0xff]))
	var frame: PackedByteArray = _frames.back()
	var at: int = frame.size()
	frame.resize(at + LENGTH_BYTES)
	frame.encode_u16(at, buffer.size())
	frame.append_array(buffer)
	_frames[-1] = frame
	# The relay refuses frames over 64 KiB; send early rather than grow past it.
	if frame.size() > FRAME_SOFT_LIMIT:
		for full: PackedByteArray in _frames:
			_send(full)
		_frames.clear()


func _send(frame: PackedByteArray) -> void:
	_socket.put_packet(frame)
	bytes_out += frame.size()


func _send_text(text: String) -> void:
	_socket.send_text(text)
	bytes_out += text.length()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > _get_max_packet_size():
		return ERR_OUT_OF_MEMORY
	# The next copy of a broadcast: one more peer for the held packet.
	if _target > 0 and not _held_for.is_empty() and not _held_for.has(_target) and not _held_for.has(0) \
			and buffer == _held:
		_held_for.append(_target)
		return OK
	_queue_held()
	_held = buffer
	_held_for.append(_target)
	return OK


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return (_incoming.pop_front() as Array)[1]


# SceneMultiplayer asks for the sender before it takes the packet.
func _get_packet_peer() -> int:
	return (_incoming[0] as Array)[0] if not _incoming.is_empty() else 0


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return FRAME_SOFT_LIMIT


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> TransferMode:
	return TRANSFER_MODE_RELIABLE


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _id == 1


# The relay delivers to any peer directly, so SceneMultiplayer need not route through the host.
func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _get_connection_status() -> ConnectionStatus:
	return _status


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_server():
		send_control({"t": "kick", "id": peer})


func _close() -> void:
	_flush()
	_close_reason = "left"
	_socket.close()
	_drop()
