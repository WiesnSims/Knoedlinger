extends GutTest
## M6 co-op: lobby profiles and room codes, the co-op fields of the world state (v5), the planar
## snapshot (v2), knock-down / revive on PlayerState, and the co-op quests on the Profile.


func before_each() -> void:
	Profile.reset_memory()


func after_all() -> void:
	Profile.reset_memory()


func test_lobby_profile_is_cleaned() -> void:
	var dirty: Dictionary = {"name": "  [b]Resi[/b] mit am sehr langen Namen  ", "character": "Resi!<x>",
		"meta": {"max_hp": 10.0, "evil": "x", "dmg": INF, "speed": 99.0}, "unlocked": ["ferdl", 5, "toni"],
		"map": "kirtag", "grant": 77, "extra": "dropped"}
	var clean: Dictionary = LobbyProfile.sanitize(dirty)
	assert_lte((clean["name"] as String).length(), LobbyProfile.NAME_MAX)
	assert_false((clean["name"] as String).contains("["))
	assert_eq(clean["character"], "esix")
	assert_eq((clean["meta"] as Dictionary).get(&"max_hp"), 10.0)
	assert_false((clean["meta"] as Dictionary).has(&"evil"), "only numbers")
	assert_false((clean["meta"] as Dictionary).has(&"dmg"), "only finite numbers")
	assert_eq((clean["meta"] as Dictionary).get(&"speed"), LobbyProfile.META_LIMIT, "clamped")
	assert_eq(clean["unlocked"], ["ferdl", "5", "toni"])
	assert_eq(clean["grant"], 9)
	assert_false(clean.has("extra"))
	assert_eq(LobbyProfile.sanitize(null)["name"], "Knödlinger", "garbage still gives a profile")


func test_room_codes_are_four_clear_letters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k: int in 200:
		var code: String = RoomCode.generate(rng)
		assert_true(RoomCode.is_valid(code), code)
		assert_false(code.contains("I") or code.contains("O"), code)
	assert_eq(RoomCode.normalize(" kndl "), "KNDL")
	assert_false(RoomCode.is_valid("KND"))
	assert_false(RoomCode.is_valid("KNDO"))


func test_world_state_carries_the_coop_fields() -> void:
	var frame := WorldStateCodec.Frame.new()
	frame.seq = 9
	for peer: int in [1, 1234567]:
		var e := WorldStateCodec.Entry.new()
		e.peer_id = peer
		e.hp = 50.0
		e.max_hp = 100.0
		e.downed = peer == 1
		e.out = false
		e.revive = 0.6
		e.down_left = 23.4 if peer == 1 else -1.0
		e.merge_partner = 1234567 if peer == 1 else 1
		e.revives_given = 3
		e.passes = 2
		e.catches = 1
		e.merges = 4
		e.streit_catches = 1
		e.merged_tier = 3 if peer == 1 else -1
		e.knodl_revive_mask = 0b101
		e.has_second = peer == 1234567
		e.second_position = Vector3(1.0, 2.0, -3.0)
		e.second_radius = 0.42
		e.weapons = PackedInt32Array([0, 3, 7, 100, 0, 0, 0, 0, 0])
		frame.entries.append(e)
	var data: PackedByteArray = WorldStateCodec.encode(frame)
	var back: WorldStateCodec.Frame = WorldStateCodec.decode(data)
	assert_not_null(back)
	var a: WorldStateCodec.Entry = back.entries[0]
	var b: WorldStateCodec.Entry = back.entries[1]
	assert_true(a.downed)
	assert_almost_eq(a.revive, 0.6, 0.01)
	assert_eq(a.down_left, 24.0, "whole seconds, rounded up")
	assert_eq(b.down_left, -1.0)
	assert_eq(a.merge_partner, 1234567)
	assert_eq(b.merge_partner, 1)
	assert_eq([a.revives_given, a.passes, a.catches, a.merges, a.streit_catches, a.merged_tier], [3, 2, 1, 4, 1, 3])
	assert_eq(b.merged_tier, -1)
	assert_eq(a.knodl_revive_mask, 0b101)
	assert_false(a.has_second)
	assert_true(b.has_second)
	assert_almost_eq(b.second_position.z, -3.0, 0.001)
	assert_almost_eq(b.second_radius, 0.42, 0.001)
	assert_eq(b.weapons[1], 3, "the build rows still follow the second Knödl")
	data.resize(data.size() - 1)
	assert_null(WorldStateCodec.decode(data), "a cut message is refused")


func test_planar_snapshot_round_trips_negative_and_far_positions() -> void:
	var slots: int = 40
	var alive := PackedByteArray()
	var x := PackedFloat32Array()
	var z := PackedFloat32Array()
	var type := PackedByteArray()
	var hp := PackedByteArray()
	for i: int in slots:
		alive.append(1 if i % 3 != 0 else 0)
		x.append(-149.97 + i * 7.31)
		z.append(150.0 - i * 6.9)
		type.append(i % SnapshotCodec.MAX_TYPES)
		hp.append(SnapshotCodec.HP_MAX - i % (SnapshotCodec.HP_MAX + 1))
	var frame: SnapshotCodec.Frame = SnapshotCodec.decode(SnapshotCodec.encode(3, 99, slots, alive, x, z, type, hp))
	assert_not_null(frame)
	for i: int in slots:
		assert_eq(frame.alive[i], alive[i])
		if alive[i] != 0:
			assert_almost_eq(frame.x[i], x[i], 0.5 / SnapshotCodec.POSITION_SCALE + 0.001)
			assert_almost_eq(frame.z[i], z[i], 0.5 / SnapshotCodec.POSITION_SCALE + 0.001)
			assert_eq(frame.type[i], type[i])
			assert_eq(frame.hp[i], hp[i])


func test_a_coop_knock_down_bleeds_out_and_a_revive_brings_them_back() -> void:
	var balance: BalanceData = load("res://data/balance.tres")
	var state := PlayerState.new(2, 100.0, null)
	assert_true(state.hurt(500.0, balance))
	state.bleeds_out = true
	state.downed_timer = balance.coop_down_seconds
	assert_false(state.tick(balance.coop_down_seconds * 0.5))
	assert_true(state.downed)
	assert_false(state.out)
	assert_false(state.tick(balance.coop_down_seconds), "no respawn in co-op")
	assert_true(state.out, "nobody came: out until a cash-in")
	state.revive(balance.revive_hp, balance.revive_grace)
	assert_false(state.downed)
	assert_false(state.out)
	assert_almost_eq(state.hp, 100.0 * balance.revive_hp, 0.01)
	assert_false(state.hurt(10.0, balance), "a moment without hits after waking")


func test_coop_deeds_stamp_the_coop_quests() -> void:
	var run: Dictionary = {"character": "resi", "map": "kirtag", "grant": 1, "result": "WON", "time": 905.0,
		"level": 30, "kills": 3000, "cash_ins": [0, 0, 0, 1], "schilling": 100,
		"coop": {"runs": 1, "revives": 10, "passes": 25, "streit": 1, "merge_cash_xl": 1, "family_win": 1,
			"knodl_revive_ferdl": 1}}
	var reward: Dictionary = Profile.record_run(run)
	var stamped: Array = (reward["quests"] as Array).map(func(q: QuestData) -> String: return String(q.id))
	for id: String in ["familienausflug", "aufgweckt", "erste_hilfe", "knodl_pass", "gemeinsam_einkehren",
			"streitschlichter", "ganze_familie"]:
		assert_true(stamped.has(id), id)
	assert_false(Profile.is_unlocked(&"item", &"doppelportion"), "Nachschlag bitte needs 25 cash-ins")
