class_name SnapshotCodec
extends RefCounted
## Enemy snapshots (CLAUDE.md: compressed snapshots of the packed arrays, ~15 Hz) and the reliable
## spawn/death events that go with them.
##
## Snapshot on the wire: [u8 version][u8 compression][u32 raw size][compressed raw]
## Raw: [u16 seq][u32 host ms][u16 slots][alive bitmask, 1 bit per slot]
##      then per alive slot: [s16 x][s16 z] in POSITION_SCALE units, [u8 type << 4 | hp bucket]
## Events: [u8 version][u16 spawns]{[u16 slot][u8 type][s16 x][s16 z]}[u16 deaths]{[u16 slot]}

const VERSION: int = 1
const POSITION_SCALE: float = 100.0
const MAX_COORDINATE: float = 327.0
const BYTES_PER_ENEMY: int = 5
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
	var alive_count: int = 0


static func encode_manager(seq: int, host_ms: int, manager: EnemyManager) -> PackedByteArray:
	var hp := PackedByteArray()
	hp.resize(manager.capacity)
	for i: int in manager.capacity:
		if manager.alive[i] != 0:
			hp[i] = manager.hp_bucket(i)
	return encode(seq, host_ms, manager.capacity, manager.alive, manager.pos_x, manager.pos_z, manager.type, hp)


static func encode(seq: int, host_ms: int, slots: int, alive: PackedByteArray, x: PackedFloat32Array,
		z: PackedFloat32Array, type: PackedByteArray, hp: PackedByteArray) -> PackedByteArray:
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
	var o: int = RAW_HEADER + mask_bytes
	for i: int in slots:
		if alive[i] == 0:
			continue
		raw[RAW_HEADER + (i >> 3)] |= 1 << (i & 7)
		raw.encode_s16(o, roundi(clampf(x[i], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE))
		raw.encode_s16(o + 2, roundi(clampf(z[i], -MAX_COORDINATE, MAX_COORDINATE) * POSITION_SCALE))
		raw[o + 4] = ((type[i] & 0x0F) << 4) | (hp[i] & 0x0F)
		o += BYTES_PER_ENEMY
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
	var o: int = RAW_HEADER + mask_bytes
	for i: int in frame.slots:
		if (raw[RAW_HEADER + (i >> 3)] & (1 << (i & 7))) == 0:
			continue
		if o + BYTES_PER_ENEMY > raw.size():
			return null
		frame.alive[i] = 1
		frame.x[i] = raw.decode_s16(o) / POSITION_SCALE
		frame.z[i] = raw.decode_s16(o + 2) / POSITION_SCALE
		frame.type[i] = raw[o + 4] >> 4
		frame.hp[i] = raw[o + 4] & 0x0F
		frame.alive_count += 1
		o += BYTES_PER_ENEMY
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
