class_name WsTransport
extends RefCounted
## The local/headless backend (CLAUDE.md: keep it working at all times): Godot's own
## WebSocketMultiplayerPeer, with the host listening directly. Only desktop and headless builds can
## listen, so browsers use the Durable Object relay instead (RelayPeer, M6), which looks the same to
## NetworkManager. Everything on a WebSocket is reliable and ordered, whatever transfer mode is asked.

## Enough for a few seconds of 500-enemy snapshots if a client stalls.
const BUFFER_BYTES: int = 1 << 20


static func host(port: int, bind_address: String) -> MultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	_configure(peer)
	var error: Error = peer.create_server(port, bind_address)
	if error != OK:
		push_error("WebSocket host on %s:%d failed: %s" % [bind_address, port, error_string(error)])
		return null
	return peer


static func join(address: String, port: int) -> MultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	_configure(peer)
	var error: Error = peer.create_client("ws://%s:%d" % [address, port])
	if error != OK:
		push_error("WebSocket join %s:%d failed: %s" % [address, port, error_string(error)])
		return null
	return peer


static func _configure(peer: WebSocketMultiplayerPeer) -> void:
	peer.inbound_buffer_size = BUFFER_BYTES
	peer.outbound_buffer_size = BUFFER_BYTES
	peer.max_queued_packets = 4096
