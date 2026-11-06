class_name RunEventCodec
extends RefCounted
## Things that happen once in a run, sent reliably and in order from the host: a telegraphed attack
## mark, loot appearing or being picked up, a toast for everyone, a boss arriving or beaten, the
## Touristenbus. The host collects them per frame (Queue), applies its own copy for sound and
## toasts, and sends the same bytes to every client. Lasting state (Stempel count, gate, boss HP,
## the run's result) is in the world state instead.
##
## Message: u8 version | u8 count | events, each u8 kind followed by:
##   HAZARD  u16 id | u8 shape | f32 x | f32 z | f32 angle | u16 radius cm | u16 length cm | u16 telegraph ms
##   LOOT    u16 id | u8 kind | f32 x | f32 z | u16 value
##   TAKEN   u16 id | s32 peer
##   TOAST   u8 length | key (ASCII)
##   BOSS    u8 boss | u8 state | u16 slot
##   BUS     f32 x | f32 z | f32 yaw
##   CUE     u8 cue | f32 x | f32 z   (a sound or effect at a place: Stempel taken, chest opened ...)
##   SAY     u8 enemy type | u8 line | u16 slot | f32 x | f32 z   (an enemy says a line, EnemyVoices)
##   LOCK    u8 stairwell | u16 telegraph ms | u16 lock ms   (Die Hausmeisterin locks stairs, StairLock;
##           every machine finds the stairs and draws the mark from its own copy of the map)
##   SITE    u8 site | u8 index | u8 state | u8 extra | f32 x | f32 z   (Der Standler and the Marterl,
##           RunSites: a site placed, in use, done or gone; extra = the Marterl's kind)

const VERSION: int = 4
const MAX_EVENTS: int = 255

enum Kind { HAZARD, LOOT, TAKEN, TOAST, BOSS, BUS, CUE, SAY, LOCK, SITE }
enum BossState { ARRIVED, BEATEN }
## SPARK (1.4): a small pop where an item proc hit (chain, burst, execute, wisp).
enum Cue { STEMPEL, CHEST, COIN, HEAL, GATE_OPEN, NO_GOLD, CASH_IN, HAZARD_HIT, BOSS_HIT, BUS_HORN, SHOCKWAVE, SPARK }


class Event:
	extends RefCounted
	var kind: Kind = Kind.TOAST
	var id: int = 0
	## HAZARD: shape; LOOT: loot kind; BOSS: boss index; CUE: cue; SAY: enemy type; LOCK: stairwell;
	## SITE: site.
	var a: int = 0
	## LOOT: value; BOSS: slot; TAKEN: peer; SAY: line; SITE: extra.
	var b: int = 0
	## BOSS, SITE: state.
	var c: int = 0
	var x: float = 0.0
	var z: float = 0.0
	## HAZARD: angle; BUS: yaw.
	var angle: float = 0.0
	var radius: float = 0.0
	## LOCK: how long the stairs stay locked.
	var length: float = 0.0
	## HAZARD, LOCK: the telegraph.
	var seconds: float = 0.0
	var text: String = ""


## Host: events of one frame.
class Queue:
	extends RefCounted
	var events: Array[Event] = []

	func hazard(h: HazardField.Hazard) -> void:
		var e := Event.new()
		e.kind = Kind.HAZARD
		e.id = h.id
		e.a = h.shape
		e.x = h.x
		e.z = h.z
		e.angle = h.angle
		e.radius = h.radius
		e.length = h.length
		e.seconds = h.telegraph
		events.append(e)

	func loot(id: int, loot_kind: int, x: float, z: float, value: int) -> void:
		var e := Event.new()
		e.kind = Kind.LOOT
		e.id = id
		e.a = loot_kind
		e.x = x
		e.z = z
		e.b = value
		events.append(e)

	func taken(id: int, peer: int) -> void:
		var e := Event.new()
		e.kind = Kind.TAKEN
		e.id = id
		e.b = peer
		events.append(e)

	func toast(key: String) -> void:
		var e := Event.new()
		e.kind = Kind.TOAST
		e.text = key
		events.append(e)

	func boss(index: int, state: BossState, slot: int) -> void:
		var e := Event.new()
		e.kind = Kind.BOSS
		e.a = index
		e.c = state
		e.b = slot
		events.append(e)

	func bus(x: float, z: float, yaw: float) -> void:
		var e := Event.new()
		e.kind = Kind.BUS
		e.x = x
		e.z = z
		e.angle = yaw
		events.append(e)

	func cue(which: Cue, x: float, z: float) -> void:
		var e := Event.new()
		e.kind = Kind.CUE
		e.a = which
		e.x = x
		e.z = z
		events.append(e)

	## An enemy of type `enemy_type` in `slot` (at x, z) says its line number `line`.
	func say(enemy_type: int, line: int, slot: int, x: float, z: float) -> void:
		var e := Event.new()
		e.kind = Kind.SAY
		e.a = enemy_type
		e.b = line
		e.id = slot
		e.x = x
		e.z = z
		events.append(e)

	## Stairwell `stairwell` gets a mark filling for `telegraph` seconds, then stays locked `seconds`.
	func lock(stairwell: int, telegraph: float, seconds: float) -> void:
		var e := Event.new()
		e.kind = Kind.LOCK
		e.a = stairwell
		e.seconds = telegraph
		e.length = seconds
		events.append(e)

	## Site `site` number `index` (RunSites) is now in `state`; `extra` = the Marterl's kind.
	func site(which: int, index: int, state: int, extra: int, x: float, z: float) -> void:
		var e := Event.new()
		e.kind = Kind.SITE
		e.a = which
		e.id = index
		e.c = state
		e.b = extra
		e.x = x
		e.z = z
		events.append(e)

	func take() -> Array[Event]:
		var out: Array[Event] = events
		events = []
		return out


## Encodes up to MAX_EVENTS events; the caller sends the rest in another message.
static func encode(events: Array[Event]) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(2)
	data.encode_u8(0, VERSION)
	var count: int = mini(events.size(), MAX_EVENTS)
	data.encode_u8(1, count)
	for k: int in count:
		var e: Event = events[k]
		var o: int = data.size()
		match e.kind:
			Kind.HAZARD:
				data.resize(o + 22)
				data.encode_u16(o + 1, e.id & 0xFFFF)
				data.encode_u8(o + 3, e.a)
				data.encode_float(o + 4, e.x)
				data.encode_float(o + 8, e.z)
				data.encode_float(o + 12, e.angle)
				data.encode_u16(o + 16, clampi(roundi(e.radius * 100.0), 0, 0xFFFF))
				data.encode_u16(o + 18, clampi(roundi(e.length * 100.0), 0, 0xFFFF))
				data.encode_u16(o + 20, clampi(roundi(e.seconds * 1000.0), 0, 0xFFFF))
			Kind.LOOT:
				data.resize(o + 14)
				data.encode_u16(o + 1, e.id & 0xFFFF)
				data.encode_u8(o + 3, e.a)
				data.encode_float(o + 4, e.x)
				data.encode_float(o + 8, e.z)
				data.encode_u16(o + 12, clampi(e.b, 0, 0xFFFF))
			Kind.TAKEN:
				data.resize(o + 7)
				data.encode_u16(o + 1, e.id & 0xFFFF)
				data.encode_s32(o + 3, e.b)
			Kind.TOAST:
				var key: PackedByteArray = e.text.to_ascii_buffer()
				var length: int = mini(key.size(), 255)
				data.resize(o + 2 + length)
				data.encode_u8(o + 1, length)
				for i: int in length:
					data[o + 2 + i] = key[i]
			Kind.BOSS:
				data.resize(o + 5)
				data.encode_u8(o + 1, e.a)
				data.encode_u8(o + 2, e.c)
				data.encode_u16(o + 3, e.b & 0xFFFF)
			Kind.BUS:
				data.resize(o + 13)
				data.encode_float(o + 1, e.x)
				data.encode_float(o + 5, e.z)
				data.encode_float(o + 9, e.angle)
			Kind.CUE:
				data.resize(o + 10)
				data.encode_u8(o + 1, e.a)
				data.encode_float(o + 2, e.x)
				data.encode_float(o + 6, e.z)
			Kind.SAY:
				data.resize(o + 13)
				data.encode_u8(o + 1, e.a & 0xFF)
				data.encode_u8(o + 2, e.b & 0xFF)
				data.encode_u16(o + 3, e.id & 0xFFFF)
				data.encode_float(o + 5, e.x)
				data.encode_float(o + 9, e.z)
			Kind.LOCK:
				data.resize(o + 6)
				data.encode_u8(o + 1, e.a & 0xFF)
				data.encode_u16(o + 2, clampi(roundi(e.seconds * 1000.0), 0, 0xFFFF))
				data.encode_u16(o + 4, clampi(roundi(e.length * 1000.0), 0, 0xFFFF))
			Kind.SITE:
				data.resize(o + 13)
				data.encode_u8(o + 1, e.a & 0xFF)
				data.encode_u8(o + 2, e.id & 0xFF)
				data.encode_u8(o + 3, e.c & 0xFF)
				data.encode_u8(o + 4, e.b & 0xFF)
				data.encode_float(o + 5, e.x)
				data.encode_float(o + 9, e.z)
		data.encode_u8(o, e.kind)
	return data


## Returns an empty list for anything that is not a valid message.
static func decode(data: PackedByteArray) -> Array[Event]:
	if data.size() < 2 or data.decode_u8(0) != VERSION:
		return []
	var out: Array[Event] = []
	var count: int = data.decode_u8(1)
	var o: int = 2
	for k: int in count:
		if o >= data.size():
			return []
		var e := Event.new()
		var kind: int = data.decode_u8(o)
		if kind > Kind.SITE:
			return []
		e.kind = kind as Kind
		var size: int = _size_of(e.kind, data, o)
		if size <= 0 or o + size > data.size():
			return []
		match e.kind:
			Kind.HAZARD:
				e.id = data.decode_u16(o + 1)
				e.a = data.decode_u8(o + 3)
				e.x = data.decode_float(o + 4)
				e.z = data.decode_float(o + 8)
				e.angle = data.decode_float(o + 12)
				e.radius = data.decode_u16(o + 16) / 100.0
				e.length = data.decode_u16(o + 18) / 100.0
				e.seconds = data.decode_u16(o + 20) / 1000.0
			Kind.LOOT:
				e.id = data.decode_u16(o + 1)
				e.a = data.decode_u8(o + 3)
				e.x = data.decode_float(o + 4)
				e.z = data.decode_float(o + 8)
				e.b = data.decode_u16(o + 12)
			Kind.TAKEN:
				e.id = data.decode_u16(o + 1)
				e.b = data.decode_s32(o + 3)
			Kind.TOAST:
				e.text = data.slice(o + 2, o + size).get_string_from_ascii()
			Kind.BOSS:
				e.a = data.decode_u8(o + 1)
				e.c = data.decode_u8(o + 2)
				e.b = data.decode_u16(o + 3)
			Kind.BUS:
				e.x = data.decode_float(o + 1)
				e.z = data.decode_float(o + 5)
				e.angle = data.decode_float(o + 9)
			Kind.CUE:
				e.a = data.decode_u8(o + 1)
				e.x = data.decode_float(o + 2)
				e.z = data.decode_float(o + 6)
			Kind.SAY:
				e.a = data.decode_u8(o + 1)
				e.b = data.decode_u8(o + 2)
				e.id = data.decode_u16(o + 3)
				e.x = data.decode_float(o + 5)
				e.z = data.decode_float(o + 9)
			Kind.LOCK:
				e.a = data.decode_u8(o + 1)
				e.seconds = data.decode_u16(o + 2) / 1000.0
				e.length = data.decode_u16(o + 4) / 1000.0
			Kind.SITE:
				e.a = data.decode_u8(o + 1)
				e.id = data.decode_u8(o + 2)
				e.c = data.decode_u8(o + 3)
				e.b = data.decode_u8(o + 4)
				e.x = data.decode_float(o + 5)
				e.z = data.decode_float(o + 9)
		if not (is_finite(e.x) and is_finite(e.z) and is_finite(e.angle)):
			return []
		out.append(e)
		o += size
	if o != data.size():
		return []
	return out


static func _size_of(kind: Kind, data: PackedByteArray, o: int) -> int:
	match kind:
		Kind.HAZARD:
			return 22
		Kind.LOOT:
			return 14
		Kind.TAKEN:
			return 7
		Kind.TOAST:
			return 2 + data.decode_u8(o + 1) if o + 1 < data.size() else -1
		Kind.BOSS:
			return 5
		Kind.BUS:
			return 13
		Kind.CUE:
			return 10
		Kind.SAY:
			return 13
		Kind.LOCK:
			return 6
		Kind.SITE:
			return 13
	return -1
