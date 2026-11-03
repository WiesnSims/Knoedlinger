class_name BroselCodec
extends RefCounted
## Brösel changes from the host (reliable, in order): slots that were removed, then slots that were
## added or changed (a merge grows a Brösel). Clients replay them on their BroselField mirror.
##
## Layout (little endian): u8 version | u16 removed | u16 set | removed x u16 slot |
## set x (u16 slot | s16 x | s16 z (1 cm) | u16 value | u8 flags)

const VERSION: int = 1
const HEADER_SIZE: int = 5
const SET_SIZE: int = 9
const UNIT: float = 0.01


## Encodes the field's current values for the given slots. Slots that are no longer alive by now
## were removed again in the same interval and are skipped in `set`.
static func encode(removed: PackedInt32Array, changed: PackedInt32Array, field: BroselField) -> PackedByteArray:
	var live := PackedInt32Array()
	var seen: Dictionary[int, bool] = {}
	for slot: int in changed:
		if field.alive[slot] != 0 and not seen.has(slot):
			seen[slot] = true
			live.append(slot)
	var data := PackedByteArray()
	data.resize(HEADER_SIZE + removed.size() * 2 + live.size() * SET_SIZE)
	data.encode_u8(0, VERSION)
	data.encode_u16(1, removed.size())
	data.encode_u16(3, live.size())
	var o: int = HEADER_SIZE
	for slot: int in removed:
		data.encode_u16(o, slot)
		o += 2
	for slot: int in live:
		data.encode_u16(o, slot)
		data.encode_s16(o + 2, clampi(roundi(field.x[slot] / UNIT), -32767, 32767))
		data.encode_s16(o + 4, clampi(roundi(field.z[slot] / UNIT), -32767, 32767))
		data.encode_u16(o + 6, clampi(field.value[slot], 0, 0xFFFF))
		data.encode_u8(o + 8, field.flags[slot])
		o += SET_SIZE
	return data


## Applies a message to a client's mirror. Returns false if it was malformed.
static func apply(data: PackedByteArray, field: BroselField) -> bool:
	if data.size() < HEADER_SIZE or data.decode_u8(0) != VERSION:
		return false
	var removed: int = data.decode_u16(1)
	var set_count: int = data.decode_u16(3)
	if data.size() != HEADER_SIZE + removed * 2 + set_count * SET_SIZE:
		return false
	var o: int = HEADER_SIZE
	for k: int in removed:
		field.mirror_remove(data.decode_u16(o))
		o += 2
	for k: int in set_count:
		field.mirror_set(data.decode_u16(o), data.decode_s16(o + 2) * UNIT, data.decode_s16(o + 4) * UNIT,
				data.decode_u16(o + 6), data.decode_u8(o + 8))
		o += SET_SIZE
	return true
