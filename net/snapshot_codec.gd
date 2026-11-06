class_name SnapshotCodec
extends RefCounted
## Enemy snapshots (CLAUDE.md: compressed snapshots of the packed arrays, ~15 Hz) and the reliable
## spawn/death events that go with them.
##
## Snapshot on the wire: [u8 version][u8 compression][u32 raw size][compressed raw]
## Raw: [u16 seq][u32 host ms][u16 slots][alive bitmask, 1 bit per slot]
##      then for the n alive slots, as byte planes (v2, M6): n x high byte of x, n x low byte of x,
##      the same for z (s16 in POSITION_SCALE units), n x [u8 type << 3 | hp bucket]. Planes keep
##      alike bytes together, which deflates far better (a 4-player crowd fits the budget).
##      v3 (1.3.2): 5 bits of type (MAX_TYPES, the Nachspielzeit ghosts made 18) and 3 of HP (HP_MAX);
##      the HP bucket only flashes hit enemies on clients.
##      v4 (1.4): one more plane, n x u8 status (EnemyManager.STATUS_*: frozen, burning), mostly zeros.
## Events: [u8 version][u16 spawns]{[u16 slot][u8 type][s16 x][s16 z]}[u16 deaths]{[u16 slot]}

const VERSION: int = 4
## Enemy types a wave may list (5 bits), and the top HP bucket (3 bits).
const MAX_TYPES: int = 32
const HP_MAX: int = 7
## 5 cm steps: invisible on half-metre enemies that clients interpolate anyway.
const POSITION_SCALE: float = 20.0
const MAX_COORDINATE: float = 327.0
const BYTES_PER_ENEMY: int = 6
const RAW_HEADER: int = 8
const WIRE_HEADER: int = 6
const COMPRESSION: FileAccess.CompressionMode = FileAccess.COMPRESSION_DEFLATE


class Frame:
	extends RefCounted
	var seq: int = 0
	var host_ms: int = 0
	var slots: int = 0
	var alive: PackedByteArray = PackedByteArray()
	var x: PackedFloat32Array = PackedFloat32Array()
	var z: PackedFloat32Array = PackedFloat32Array()
	var type: PackedByteArray = PackedByteArray()
	var hp: PackedByteArray = PackedByteArray()
	var status: PackedByteArray = PackedByteArray()
	var alive_count: int = 0


static func encode_manager(seq: int, host_ms: int, manager: EnemyManager) -> PackedByteArray:
	var hp := PackedByteArray()
	hp.resize(manager.capacity)
	for i: int in manager.capacity:
		if manager.alive[i] != 0:
			hp[i] = manager.hp_bucket(i)
	return encode(seq, host_ms, manager.capacity, manager.alive, manager.pos_x, manager.pos_z, manager.type, hp,
			manager.statuses())


static func encode(seq: int, host_ms: int, slots: int, alive: PackedByteArray, x: PackedFloat32Array,
		z: PackedFloat32Array, type: PackedByteArray, hp: PackedByteArray,
		status: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var mask_bytes: int = (slots + 7) / 8
	var count: int = 0
	for i: int in slots:
		if alive[i] != 0:
			count += 1
	var raw := PackedByteArray()
	raw.resize(RAW_HEADER + mask_bytes + count * BYTES_PER_ENEMY)
	raw.fill(0)
	raw.encode_u16(0, seq & 0xFFFF)
	raw.encode_u32(2, host_ms & 0xFFFFFFFF)
	raw.encode_u16(6, slots)
	var base: int = RAW_HEADER + mask_bytes
	var k: int = 0
	for i: int in slots:
		if alive[i] == 0:
			continue
		raw[RAW_HEADER + (i >> 3)] |= 1 << (i & 7)
		var qx: int = roundi(clampf(x[i], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE) & 0xFFFF
		var qz: int = roundi(clampf(z[i], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE) & 0xFFFF
		raw[base + k] = qx >> 8
		raw[base + count + k] = qx & 0xFF
		raw[base + 2 * count + k] = qz >> 8
		raw[base + 3 * count + k] = qz & 0xFF
		raw[base + 4 * count + k] = ((type[i] & 0x1F) << 3) | (hp[i] & HP_MAX)
		raw[base + 5 * count + k] = status[i] if i < status.size() else 0
		k += 1
	var packed: PackedByteArray = raw.compress(COMPRESSION)
	var wire := PackedByteArray()
	wire.resize(WIRE_HEADER)
	wire.encode_u8(0, VERSION)
	wire.encode_u8(1, COMPRESSION)
	wire.encode_u32(2, raw.size())
	wire.append_array(packed)
	return wire


## Returns null for anything that is not a valid snapshot.
static func decode(wire: PackedByteArray) -> Frame:
	if wire.size() < WIRE_HEADER or wire.decode_u8(0) != VERSION:
		return null
	var raw_size: int = wire.decode_u32(2)
	if raw_size < RAW_HEADER or raw_size > 1 << 20:
		return null
	var raw: PackedByteArray = wire.slice(WIRE_HEADER).decompress(raw_size, wire.decode_u8(1))
	if raw.size() != raw_size:
		return null
	var frame := Frame.new()
	frame.seq = raw.decode_u16(0)
	frame.host_ms = raw.decode_u32(2)
	frame.slots = raw.decode_u16(6)
	var mask_bytes: int = (frame.slots + 7) / 8
	if raw.size() < RAW_HEADER + mask_bytes:
		return null
	frame.alive.resize(frame.slots)
	frame.alive.fill(0)
	frame.x.resize(frame.slots)
	frame.z.resize(frame.slots)
	frame.type.resize(frame.slots)
	frame.hp.resize(frame.slots)
	frame.status.resize(frame.slots)
	var count: int = 0
	for i: int in frame.slots:
		if (raw[RAW_HEADER + (i >> 3)] & (1 << (i & 7))) != 0:
			count += 1
	var base: int = RAW_HEADER + mask_bytes
	if raw.size() != base + count * BYTES_PER_ENEMY:
		return null
	var k: int = 0
	for i: int in frame.slots:
		if (raw[RAW_HEADER + (i >> 3)] & (1 << (i & 7))) == 0:
			continue
		frame.alive[i] = 1
		var qx: int = (raw[base + k] << 8) | raw[base + count + k]
		var qz: int = (raw[base + 2 * count + k] << 8) | raw[base + 3 * count + k]
		frame.x[i] = (qx - 0x10000 if qx >= 0x8000 else qx) / POSITION_SCALE
		frame.z[i] = (qz - 0x10000 if qz >= 0x8000 else qz) / POSITION_SCALE
		var tag: int = raw[base + 4 * count + k]
		frame.type[i] = tag >> 3
		frame.hp[i] = tag & HP_MAX
		frame.status[i] = raw[base + 5 * count + k]
		frame.alive_count += 1
		k += 1
	return frame


static func encode_events(spawned: PackedInt32Array, died: PackedInt32Array, manager: EnemyManager) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(1 + 2 + spawned.size() * 7 + 2 + died.size() * 2)
	data.encode_u8(0, VERSION)
	data.encode_u16(1, spawned.size())
	var o: int = 3
	for slot: int in spawned:
		data.encode_u16(o, slot)
		data.encode_u8(o + 2, manager.type[slot])
		data.encode_s16(o + 3, roundi(clampf(manager.pos_x[slot], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE))
		data.encode_s16(o + 5, roundi(clampf(manager.pos_z[slot], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE))
		o += 7
	data.encode_u16(o, died.size())
	o += 2
	for slot: int in died:
		data.encode_u16(o, slot)
		o += 2
	return data


## Returns {"spawned": PackedInt32Array, "died": PackedInt32Array}, or an empty dictionary if invalid.
static func decode_events(data: PackedByteArray) -> Dictionary:
	if data.size() < 5 or data.decode_u8(0) != VERSION:
		return {}
	var spawn_count: int = data.decode_u16(1)
	var o: int = 3 + spawn_count * 7
	if data.size() < o + 2:
		return {}
	var death_count: int = data.decode_u16(o)
	if data.size() != o + 2 + death_count * 2:
		return {}
	var spawned := PackedInt32Array()
	for k: int in spawn_count:
		spawned.append(data.decode_u16(3 + k * 7))
	var died := PackedInt32Array()
	for k: int in death_count:
		died.append(data.decode_u16(o + 2 + k * 2))
	return {"spawned": spawned, "died": died}
