class_name WorldStateCodec
extends RefCounted
## The host's world state, sent ~15 times per second (unreliable, newest wins): run time and phase,
## Brösel count, the Wirtshäuser, and per player their HP, XP, level, flags, build and their
## Knödl's pose and mass.
##
## Layout (little endian):
##   u8 version | u16 seq | u32 host ms | f32 run time | u16 Brösel alive | u8 phase |
##   u8 Wirtshäuser, each u8 spot | u8 flags (open, served, tier << 2) | u8 players
##   per player PLAYER_SIZE bytes: s32 peer | f32 hp | f32 max hp | f32 xp | u16 level |
##   u8 flags | u8 life | u8 pending levels | u8 Knödl state | u8 Knödl cooldown (1/20 s) |
##   u8 rerolls | f32 Knödl mass | 3 x f32 Knödl position | 4 x s16 Knödl rotation (q * 32767) |
##   u16 gold | u8 banishes | u8 weapons | u8 passives | 3 bytes padding
##   then per weapon u8 index | u8 level | u16 bonus * 100 | u8 fire counter,
##   and per passive u8 index | u8 level | u16 bonus * 100.

const VERSION: int = 2
const HEADER_SIZE: int = 15
const WIRT_SIZE: int = 2
const PLAYER_SIZE: int = 56
const WEAPON_SIZE: int = 5
const PASSIVE_SIZE: int = 4
const FLAG_DOWNED: int = 1
const FLAG_CHOOSING: int = 2
const WIRT_OPEN: int = 1
const WIRT_SERVED: int = 2


class Entry:
	extends RefCounted
	var peer_id: int = 0
	var hp: float = 0.0
	var max_hp: float = 0.0
	var xp: float = 0.0
	var level: int = 1
	var downed: bool = false
	var choosing: bool = false
	var life: int = 0
	var pending_levels: int = 0
	var knodl_state: int = 0
	var knodl_cooldown: float = 0.0
	var knodl_mass: float = 0.0
	var knodl_position: Vector3 = Vector3.ZERO
	var knodl_rotation: Quaternion = Quaternion.IDENTITY
	var gold: int = 0
	var rerolls: int = 0
	var banishes: int = 0
	## PlayerBuild.weapon_rows() / passive_rows().
	var weapons: PackedInt32Array = PackedInt32Array()
	var passives: PackedInt32Array = PackedInt32Array()


class Frame:
	extends RefCounted
	var seq: int = 0
	var host_ms: int = 0
	var run_time: float = 0.0
	var brosel_alive: int = 0
	## RunWorld.Phase.
	var phase: int = 0
	## Per Wirtshaus: Vector3i(spot, flags, tier).
	var wirtshaeuser: Array[Vector3i] = []
	var entries: Array[Entry] = []


static func encode(frame: Frame) -> PackedByteArray:
	var size: int = HEADER_SIZE + frame.wirtshaeuser.size() * WIRT_SIZE + 1
	for e: Entry in frame.entries:
		size += PLAYER_SIZE + e.weapons.size() / 4 * WEAPON_SIZE + e.passives.size() / 3 * PASSIVE_SIZE
	var data := PackedByteArray()
	data.resize(size)
	data.fill(0)
	data.encode_u8(0, VERSION)
	data.encode_u16(1, frame.seq & 0xFFFF)
	data.encode_u32(3, frame.host_ms & 0xFFFFFFFF)
	data.encode_float(7, frame.run_time)
	data.encode_u16(11, clampi(frame.brosel_alive, 0, 0xFFFF))
	data.encode_u8(13, frame.phase)
	data.encode_u8(14, frame.wirtshaeuser.size())
	var o: int = HEADER_SIZE
	for wirt: Vector3i in frame.wirtshaeuser:
		data.encode_u8(o, wirt.x)
		data.encode_u8(o + 1, (wirt.y & 3) | ((wirt.z & 3) << 2))
		o += WIRT_SIZE
	data.encode_u8(o, frame.entries.size())
	o += 1
	for e: Entry in frame.entries:
		data.encode_s32(o, e.peer_id)
		data.encode_float(o + 4, e.hp)
		data.encode_float(o + 8, e.max_hp)
		data.encode_float(o + 12, e.xp)
		data.encode_u16(o + 16, clampi(e.level, 0, 0xFFFF))
		data.encode_u8(o + 18, (FLAG_DOWNED if e.downed else 0) | (FLAG_CHOOSING if e.choosing else 0))
		data.encode_u8(o + 19, e.life & 0xFF)
		data.encode_u8(o + 20, clampi(e.pending_levels, 0, 255))
		data.encode_u8(o + 21, e.knodl_state)
		data.encode_u8(o + 22, clampi(roundi(e.knodl_cooldown * 20.0), 0, 255))
		data.encode_u8(o + 23, clampi(e.rerolls, 0, 255))
		data.encode_float(o + 24, e.knodl_mass)
		data.encode_float(o + 28, e.knodl_position.x)
		data.encode_float(o + 32, e.knodl_position.y)
		data.encode_float(o + 36, e.knodl_position.z)
		var q: Quaternion = e.knodl_rotation.normalized()
		data.encode_s16(o + 40, roundi(q.x * 32767.0))
		data.encode_s16(o + 42, roundi(q.y * 32767.0))
		data.encode_s16(o + 44, roundi(q.z * 32767.0))
		data.encode_s16(o + 46, roundi(q.w * 32767.0))
		data.encode_u16(o + 48, clampi(e.gold, 0, 0xFFFF))
		data.encode_u8(o + 50, clampi(e.banishes, 0, 255))
		var weapon_count: int = e.weapons.size() / 4
		var passive_count: int = e.passives.size() / 3
		data.encode_u8(o + 51, weapon_count)
		data.encode_u8(o + 52, passive_count)
		o += PLAYER_SIZE
		for k: int in weapon_count:
			data.encode_u8(o, e.weapons[k * 4])
			data.encode_u8(o + 1, clampi(e.weapons[k * 4 + 1], 0, 255))
			data.encode_u16(o + 2, clampi(e.weapons[k * 4 + 2], 0, 0xFFFF))
			data.encode_u8(o + 4, e.weapons[k * 4 + 3] & 0xFF)
			o += WEAPON_SIZE
		for k: int in passive_count:
			data.encode_u8(o, e.passives[k * 3])
			data.encode_u8(o + 1, clampi(e.passives[k * 3 + 1], 0, 255))
			data.encode_u16(o + 2, clampi(e.passives[k * 3 + 2], 0, 0xFFFF))
			o += PASSIVE_SIZE
	return data


## Returns null for anything that is not a valid world state.
static func decode(data: PackedByteArray) -> Frame:
	if data.size() < HEADER_SIZE + 1 or data.decode_u8(0) != VERSION:
		return null
	var frame := Frame.new()
	frame.seq = data.decode_u16(1)
	frame.host_ms = data.decode_u32(3)
	frame.run_time = data.decode_float(7)
	frame.brosel_alive = data.decode_u16(11)
	frame.phase = data.decode_u8(13)
	var wirt_count: int = data.decode_u8(14)
	var o: int = HEADER_SIZE
	if data.size() < o + wirt_count * WIRT_SIZE + 1:
		return null
	for k: int in wirt_count:
		var flags: int = data.decode_u8(o + 1)
		frame.wirtshaeuser.append(Vector3i(data.decode_u8(o), flags & 3, (flags >> 2) & 3))
		o += WIRT_SIZE
	var count: int = data.decode_u8(o)
	o += 1
	for k: int in count:
		if data.size() < o + PLAYER_SIZE:
			return null
		var e := Entry.new()
		e.peer_id = data.decode_s32(o)
		e.hp = data.decode_float(o + 4)
		e.max_hp = data.decode_float(o + 8)
		e.xp = data.decode_float(o + 12)
		e.level = data.decode_u16(o + 16)
		var flags: int = data.decode_u8(o + 18)
		e.downed = (flags & FLAG_DOWNED) != 0
		e.choosing = (flags & FLAG_CHOOSING) != 0
		e.life = data.decode_u8(o + 19)
		e.pending_levels = data.decode_u8(o + 20)
		e.knodl_state = data.decode_u8(o + 21)
		e.knodl_cooldown = data.decode_u8(o + 22) / 20.0
		e.rerolls = data.decode_u8(o + 23)
		e.knodl_mass = data.decode_float(o + 24)
		e.knodl_position = Vector3(data.decode_float(o + 28), data.decode_float(o + 32), data.decode_float(o + 36))
		var q := Quaternion(data.decode_s16(o + 40) / 32767.0, data.decode_s16(o + 42) / 32767.0,
				data.decode_s16(o + 44) / 32767.0, data.decode_s16(o + 46) / 32767.0)
		e.knodl_rotation = q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY
		e.gold = data.decode_u16(o + 48)
		e.banishes = data.decode_u8(o + 50)
		var weapon_count: int = data.decode_u8(o + 51)
		var passive_count: int = data.decode_u8(o + 52)
		if not e.knodl_position.is_finite() or not is_finite(e.hp) or not is_finite(e.knodl_mass):
			return null
		o += PLAYER_SIZE
		if data.size() < o + weapon_count * WEAPON_SIZE + passive_count * PASSIVE_SIZE:
			return null
		for w: int in weapon_count:
			e.weapons.append_array([data.decode_u8(o), data.decode_u8(o + 1), data.decode_u16(o + 2), data.decode_u8(o + 4)])
			o += WEAPON_SIZE
		for p: int in passive_count:
			e.passives.append_array([data.decode_u8(o), data.decode_u8(o + 1), data.decode_u16(o + 2)])
			o += PASSIVE_SIZE
		frame.entries.append(e)
	if o != data.size():
		return null
	return frame
