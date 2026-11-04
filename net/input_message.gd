class_name InputMessage
extends RefCounted
## What a player sends every pose tick, even in solo (CLAUDE.md: player input is a message). Each
## player owns their own movement, so the message carries the input and where it took them; the host
## validates the position and passes it on to the other players.

const VERSION: int = 3
const SIZE: int = 24
const BUTTON_JUMP: int = 1
const BUTTON_SCHUPFN: int = 2

var tick: int = 0
## Movement stick, each axis -1..1 (x = world X, y = world Z).
var move: Vector2 = Vector2.ZERO
var buttons: int = 0
var position: Vector3 = Vector3.ZERO
## Facing around +Y in radians.
var yaw: float = 0.0
## Counts Schupfn presses (wraps at 256), so a press shorter than one message is never lost.
var schupfn_presses: int = 0
## Counts jumps (wraps at 256): every n-th makes Kevin's shockwave on the host.
var jumps: int = 0


func to_bytes() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE)
	data.encode_u8(0, VERSION)
	data.encode_u32(1, tick)
	data.encode_s8(5, roundi(clampf(move.x, -1.0, 1.0) * 127.0))
	data.encode_s8(6, roundi(clampf(move.y, -1.0, 1.0) * 127.0))
	data.encode_u8(7, buttons)
	data.encode_float(8, position.x)
	data.encode_float(12, position.y)
	data.encode_float(16, position.z)
	data.encode_u16(20, roundi(fposmod(yaw, TAU) / TAU * 65535.0))
	data.encode_u8(22, schupfn_presses & 0xFF)
	data.encode_u8(23, jumps & 0xFF)
	return data


## Returns null for anything that is not a valid message.
static func from_bytes(data: PackedByteArray) -> InputMessage:
	if data.size() != SIZE or data.decode_u8(0) != VERSION:
		return null
	var message := InputMessage.new()
	message.tick = data.decode_u32(1)
	message.move = Vector2(data.decode_s8(5) / 127.0, data.decode_s8(6) / 127.0)
	message.buttons = data.decode_u8(7)
	message.position = Vector3(data.decode_float(8), data.decode_float(12), data.decode_float(16))
	message.yaw = data.decode_u16(20) / 65535.0 * TAU
	message.schupfn_presses = data.decode_u8(22)
	message.jumps = data.decode_u8(23)
	if not message.position.is_finite():
		return null
	return message
