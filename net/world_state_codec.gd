class_name WorldStateCodec
extends RefCounted
## The host's per-player world state, sent ~15 times per second (unreliable, newest wins): run
## time, Brösel count, and per player their HP, XP, level, flags and their Knödl's pose and mass.
##
## Layout (little endian):
##   u8 version | u16 seq | u32 host ms | f32 run time | u16 Brösel alive | u8 players
##   per player (PLAYER_SIZE bytes): s32 peer | f32 hp | f32 max hp | f32 xp | u16 level |
##   u8 flags | u8 life | u8 swing count | u8 Knödl state | u8 Knödl cooldown (1/20 s) |
##   f32 Knödl mass | 3 x f32 Knödl position | 4 x s16 Knödl rotation (quaternion * 32767)

const VERSION: int = 1
const HEADER_SIZE: int = 14
const PLAYER_SIZE: int = 48
const FLAG_DOWNED: int = 1


class Entry:
	extends RefCounted
	var peer_id: int = 0
	var hp: float = 0.0
	var max_hp: float = 0.0
	var xp: float = 0.0
	var level: int = 1
	var downed: bool = false
	var life: int = 0
	var swing_count: int = 0
	var knodl_state: int = 0
	var knodl_cooldown: float = 0.0
	var knodl_mass: float = 0.0
	var knodl_position: Vector3 = Vector3.ZERO
	var knodl_rotation: Quaternion = Quaternion.IDENTITY


class Frame:
	extends RefCounted
	var seq: int = 0
	var host_ms: int = 0
	var run_time: float = 0.0
	var brosel_alive: int = 0
	var entries: Array[Entry] = []


static func encode(frame: Frame) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(HEADER_SIZE + frame.entries.size() * PLAYER_SIZE)
	data.encode_u8(0, VERSION)
	data.encode_u16(1, frame.seq & 0xFFFF)
	data.encode_u32(3, frame.host_ms & 0xFFFFFFFF)
	data.encode_float(7, frame.run_time)
	data.encode_u16(11, clampi(frame.brosel_alive, 0, 0xFFFF))
	data.encode_u8(13, frame.entries.size())
	var o: int = HEADER_SIZE
	for e: Entry in frame.entries:
		data.encode_s32(o, e.peer_id)
		data.encode_float(o + 4, e.hp)
		data.encode_float(o + 8, e.max_hp)
		data.encode_float(o + 12, e.xp)
		data.encode_u16(o + 16, clampi(e.level, 0, 0xFFFF))
		data.encode_u8(o + 18, FLAG_DOWNED if e.downed else 0)
		data.encode_u8(o + 19, e.life & 0xFF)
		data.encode_u8(o + 20, e.swing_count & 0xFF)
		data.encode_u8(o + 21, e.knodl_state)
		data.encode_u8(o + 22, clampi(roundi(e.knodl_cooldown * 20.0), 0, 255))
		data.encode_u8(o + 23, 0)
		data.encode_float(o + 24, e.knodl_mass)
		data.encode_float(o + 28, e.knodl_position.x)
		data.encode_float(o + 32, e.knodl_position.y)
		data.encode_float(o + 36, e.knodl_position.z)
		var q: Quaternion = e.knodl_rotation.normalized()
		data.encode_s16(o + 40, roundi(q.x * 32767.0))
		data.encode_s16(o + 42, roundi(q.y * 32767.0))
		data.encode_s16(o + 44, roundi(q.z * 32767.0))
		data.encode_s16(o + 46, roundi(q.w * 32767.0))
		o += PLAYER_SIZE
	return data


## Returns null for anything that is not a valid world state.
static func decode(data: PackedByteArray) -> Frame:
	if data.size() < HEADER_SIZE or data.decode_u8(0) != VERSION:
		return null
	var count: int = data.decode_u8(13)
	if data.size() != HEADER_SIZE + count * PLAYER_SIZE:
		return null
	var frame := Frame.new()
	frame.seq = data.decode_u16(1)
	frame.host_ms = data.decode_u32(3)
	frame.run_time = data.decode_float(7)
	frame.brosel_alive = data.decode_u16(11)
	var o: int = HEADER_SIZE
	for k: int in count:
		var e := Entry.new()
		e.peer_id = data.decode_s32(o)
		e.hp = data.decode_float(o + 4)
		e.max_hp = data.decode_float(o + 8)
		e.xp = data.decode_float(o + 12)
		e.level = data.decode_u16(o + 16)
		e.downed = (data.decode_u8(o + 18) & FLAG_DOWNED) != 0
		e.life = data.decode_u8(o + 19)
		e.swing_count = data.decode_u8(o + 20)
		e.knodl_state = data.decode_u8(o + 21)
		e.knodl_cooldown = data.decode_u8(o + 22) / 20.0
		e.knodl_mass = data.decode_float(o + 24)
		e.knodl_position = Vector3(data.decode_float(o + 28), data.decode_float(o + 32), data.decode_float(o + 36))
		var q := Quaternion(data.decode_s16(o + 40) / 32767.0, data.decode_s16(o + 42) / 32767.0,
				data.decode_s16(o + 44) / 32767.0, data.decode_s16(o + 46) / 32767.0)
		e.knodl_rotation = q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY
		if not e.knodl_position.is_finite() or not is_finite(e.hp) or not is_finite(e.knodl_mass):
			return null
		frame.entries.append(e)
		o += PLAYER_SIZE
	return frame
