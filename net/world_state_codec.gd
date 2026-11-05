class_name WorldStateCodec
extends RefCounted
## The host's world state, sent ~15 times per second (unreliable, newest wins): run time and phase,
## Brösel count, the Wirtshäuser, and per player their HP, XP, level, flags, build and their
## Knödl's pose and mass.
##
## Layout (little endian):
##   u8 version | u16 seq | u32 host ms | f32 run time | u16 Brösel alive | u8 phase |
##   u8 Formular Stempel found | u8 Stempel total | u8 gate flags | u8 result | u8 boss (255 = none) |
##   u16 boss slot | f32 boss hp | f32 boss max hp | u8 padding |
##   then per Wirtshaus (the count is the u8 at offset 14) u8 spot | u8 flags (open, served, tier << 2) | u8 players
##   per player PLAYER_SIZE bytes: s32 peer | f32 hp | f32 max hp | f32 xp | u16 level |
##   u8 flags | u8 life | u8 pending levels | u8 Knödl state | u8 Knödl cooldown (1/20 s) |
##   u8 rerolls | f32 Knödl mass | 3 x f32 Knödl position | 4 x s16 Knödl rotation (q * 32767) |
##   u16 gold | u8 banishes | u8 weapons | u8 passives | u8 chests opened | u8 items | u16 Schilling |
##   u8 revive progress (/255) | u8 seconds until out (255 = none) | s32 merge partner (0 = none) |
##   co-op deeds: u8 revives given | u8 passes | u8 catches | u8 merges | u8 Familienstreit catches |
##   s8 best merged cash-in tier | u16 characters woken with the Knödl (bit = GameContent index)
##   then, with FLAG_SECOND, the second Knödl (Doppelportion): 3 x f32 position | 4 x s16 rotation |
##   f32 radius; then per weapon u8 index | u8 level | u8 fire counter | 4 x u16 mod * 1000 (damage, rate, area,
##   crit) | u8 extra pieces, per passive u8 index | u8 level | u16 bonus * 100, and per item
##   u8 index | u8 count.

const VERSION: int = 5
const HEADER_SIZE: int = 31
const WIRT_SIZE: int = 2
const PLAYER_SIZE: int = 71
const SECOND_SIZE: int = 24
const WEAPON_SIZE: int = 12
const PASSIVE_SIZE: int = 4
const ITEM_SIZE: int = 2
## Ints per weapon row (PlayerBuild.weapon_rows()).
const WEAPON_ROW: int = 8
const FLAG_DOWNED: int = 1
const FLAG_CHOOSING: int = 2
const FLAG_OUT: int = 4
const FLAG_SECOND: int = 8
const WIRT_OPEN: int = 1
const WIRT_SERVED: int = 2
## Gate flags: the Formular is out, the gate is open, the final boss is out, he is beaten.
const GATE_FORMULAR: int = 1
const GATE_OPEN: int = 2
const GATE_BOSS_OUT: int = 4
const GATE_BOSS_BEATEN: int = 8
const NO_BOSS: int = 255


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
	var chests_opened: int = 0
	## What the run pays this player so far (shown on their end screen).
	var schilling: int = 0
	## PlayerBuild.weapon_rows() / passive_rows() / item_rows().
	var weapons: PackedInt32Array = PackedInt32Array()
	var passives: PackedInt32Array = PackedInt32Array()
	var items: PackedInt32Array = PackedInt32Array()
	## Co-op: knocked down for good until a cash-in, how far a teammate got waking them (0..1), the
	## seconds left before they are out (-1 = none), whose Knödl theirs is merged with (0 = none).
	var out: bool = false
	var revive: float = 0.0
	var down_left: float = -1.0
	var merge_partner: int = 0
	## Co-op deeds this run (quests on every player's own profile).
	var revives_given: int = 0
	var passes: int = 0
	var catches: int = 0
	var merges: int = 0
	var streit_catches: int = 0
	var merged_tier: int = -1
	var knodl_revive_mask: int = 0
	## Doppelportion: the second, smaller Knödl.
	var has_second: bool = false
	var second_position: Vector3 = Vector3.ZERO
	var second_rotation: Quaternion = Quaternion.IDENTITY
	var second_radius: float = 0.0


class Frame:
	extends RefCounted
	var seq: int = 0
	var host_ms: int = 0
	var run_time: float = 0.0
	var brosel_alive: int = 0
	## RunWorld.Phase.
	var phase: int = 0
	## Per Wirtshaus: Vector3i(spot, flags, tier).
	var stempel_found: int = 0
	var stempel_total: int = 0
	var gate: int = 0
	## RunWorld.Result.
	var result: int = 0
	## The boss shown in the HUD bar (BossDirector.list index) or NO_BOSS.
	var boss: int = NO_BOSS
	var boss_slot: int = 0
	var boss_hp: float = 0.0
	var boss_max_hp: float = 0.0
	var wirtshaeuser: Array[Vector3i] = []
	var entries: Array[Entry] = []


static func encode(frame: Frame) -> PackedByteArray:
	var size: int = HEADER_SIZE + frame.wirtshaeuser.size() * WIRT_SIZE + 1
	for e: Entry in frame.entries:
		size += PLAYER_SIZE + (SECOND_SIZE if e.has_second else 0) + e.weapons.size() / WEAPON_ROW * WEAPON_SIZE + e.passives.size() / 3 * PASSIVE_SIZE \
				+ e.items.size() / 2 * ITEM_SIZE
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
	data.encode_u8(15, clampi(frame.stempel_found, 0, 255))
	data.encode_u8(16, clampi(frame.stempel_total, 0, 255))
	data.encode_u8(17, frame.gate & 0xFF)
	data.encode_u8(18, frame.result & 0xFF)
	data.encode_u8(19, frame.boss & 0xFF)
	data.encode_u16(20, frame.boss_slot & 0xFFFF)
	data.encode_float(22, frame.boss_hp)
	data.encode_float(26, frame.boss_max_hp)
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
		data.encode_u8(o + 18, (FLAG_DOWNED if e.downed else 0) | (FLAG_CHOOSING if e.choosing else 0)
				| (FLAG_OUT if e.out else 0) | (FLAG_SECOND if e.has_second else 0))
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
		var weapon_count: int = e.weapons.size() / WEAPON_ROW
		var passive_count: int = e.passives.size() / 3
		var item_count: int = e.items.size() / 2
		data.encode_u8(o + 51, weapon_count)
		data.encode_u8(o + 52, passive_count)
		data.encode_u8(o + 53, clampi(e.chests_opened, 0, 255))
		data.encode_u8(o + 54, item_count)
		data.encode_u16(o + 55, clampi(e.schilling, 0, 0xFFFF))
		data.encode_u8(o + 57, clampi(roundi(e.revive * 255.0), 0, 255))
		data.encode_u8(o + 58, 255 if e.down_left < 0.0 or not is_finite(e.down_left) else clampi(ceili(e.down_left), 0, 254))
		data.encode_s32(o + 59, e.merge_partner)
		data.encode_u8(o + 63, clampi(e.revives_given, 0, 255))
		data.encode_u8(o + 64, clampi(e.passes, 0, 255))
		data.encode_u8(o + 65, clampi(e.catches, 0, 255))
		data.encode_u8(o + 66, clampi(e.merges, 0, 255))
		data.encode_u8(o + 67, clampi(e.streit_catches, 0, 255))
		data.encode_s8(o + 68, clampi(e.merged_tier, -1, 3))
		data.encode_u16(o + 69, e.knodl_revive_mask & 0xFFFF)
		o += PLAYER_SIZE
		if e.has_second:
			data.encode_float(o, e.second_position.x)
			data.encode_float(o + 4, e.second_position.y)
			data.encode_float(o + 8, e.second_position.z)
			var r: Quaternion = e.second_rotation.normalized()
			data.encode_s16(o + 12, roundi(r.x * 32767.0))
			data.encode_s16(o + 14, roundi(r.y * 32767.0))
			data.encode_s16(o + 16, roundi(r.z * 32767.0))
			data.encode_s16(o + 18, roundi(r.w * 32767.0))
			data.encode_float(o + 20, e.second_radius)
			o += SECOND_SIZE
		for k: int in weapon_count:
			var w: int = k * WEAPON_ROW
			data.encode_u8(o, e.weapons[w])
			data.encode_u8(o + 1, clampi(e.weapons[w + 1], 0, 255))
			data.encode_u8(o + 2, e.weapons[w + 2] & 0xFF)
			for m: int in 4:
				data.encode_u16(o + 3 + m * 2, clampi(e.weapons[w + 3 + m], 0, 0xFFFF))
			data.encode_u8(o + 11, clampi(roundi(e.weapons[w + 7] / 1000.0), 0, 255))
			o += WEAPON_SIZE
		for k: int in passive_count:
			data.encode_u8(o, e.passives[k * 3])
			data.encode_u8(o + 1, clampi(e.passives[k * 3 + 1], 0, 255))
			data.encode_u16(o + 2, clampi(e.passives[k * 3 + 2], 0, 0xFFFF))
			o += PASSIVE_SIZE
		for k: int in item_count:
			data.encode_u8(o, e.items[k * 2])
			data.encode_u8(o + 1, clampi(e.items[k * 2 + 1], 0, 255))
			o += ITEM_SIZE
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
	frame.stempel_found = data.decode_u8(15)
	frame.stempel_total = data.decode_u8(16)
	frame.gate = data.decode_u8(17)
	frame.result = data.decode_u8(18)
	frame.boss = data.decode_u8(19)
	frame.boss_slot = data.decode_u16(20)
	frame.boss_hp = data.decode_float(22)
	frame.boss_max_hp = data.decode_float(26)
	if not is_finite(frame.boss_hp) or not is_finite(frame.boss_max_hp):
		return null
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
		e.out = (flags & FLAG_OUT) != 0
		e.has_second = (flags & FLAG_SECOND) != 0
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
		e.chests_opened = data.decode_u8(o + 53)
		var item_count: int = data.decode_u8(o + 54)
		e.schilling = data.decode_u16(o + 55)
		e.revive = data.decode_u8(o + 57) / 255.0
		var left: int = data.decode_u8(o + 58)
		e.down_left = -1.0 if left == 255 else float(left)
		e.merge_partner = data.decode_s32(o + 59)
		e.revives_given = data.decode_u8(o + 63)
		e.passes = data.decode_u8(o + 64)
		e.catches = data.decode_u8(o + 65)
		e.merges = data.decode_u8(o + 66)
		e.streit_catches = data.decode_u8(o + 67)
		e.merged_tier = data.decode_s8(o + 68)
		e.knodl_revive_mask = data.decode_u16(o + 69)
		if not e.knodl_position.is_finite() or not is_finite(e.hp) or not is_finite(e.knodl_mass):
			return null
		o += PLAYER_SIZE
		if e.has_second:
			if data.size() < o + SECOND_SIZE:
				return null
			e.second_position = Vector3(data.decode_float(o), data.decode_float(o + 4), data.decode_float(o + 8))
			var r := Quaternion(data.decode_s16(o + 12) / 32767.0, data.decode_s16(o + 14) / 32767.0,
					data.decode_s16(o + 16) / 32767.0, data.decode_s16(o + 18) / 32767.0)
			e.second_rotation = r.normalized() if r.length_squared() > 0.0001 else Quaternion.IDENTITY
			e.second_radius = data.decode_float(o + 20)
			if not e.second_position.is_finite() or not is_finite(e.second_radius):
				return null
			o += SECOND_SIZE
		if data.size() < o + weapon_count * WEAPON_SIZE + passive_count * PASSIVE_SIZE + item_count * ITEM_SIZE:
			return null
		for w: int in weapon_count:
			e.weapons.append_array([data.decode_u8(o), data.decode_u8(o + 1), data.decode_u8(o + 2),
					data.decode_u16(o + 3), data.decode_u16(o + 5), data.decode_u16(o + 7), data.decode_u16(o + 9),
					data.decode_u8(o + 11) * 1000])
			o += WEAPON_SIZE
		for p: int in passive_count:
			e.passives.append_array([data.decode_u8(o), data.decode_u8(o + 1), data.decode_u16(o + 2)])
			o += PASSIVE_SIZE
		for i: int in item_count:
			e.items.append_array([data.decode_u8(o), data.decode_u8(o + 1)])
			o += ITEM_SIZE
		frame.entries.append(e)
	if o != data.size():
		return null
	return frame
