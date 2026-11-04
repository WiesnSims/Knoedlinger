extends GutTest

var balance: BalanceData


func before_each() -> void:
	balance = BalanceData.new()


func test_hits_respect_the_hurt_cooldown() -> void:
	var state := PlayerState.new(1, 100.0)
	assert_false(state.hurt(10.0, balance))
	assert_eq(state.hp, 90.0)
	state.hurt(10.0, balance)
	assert_eq(state.hp, 90.0, "invulnerable right after a hit")
	state.tick(balance.player_hurt_cooldown + 0.01)
	state.hurt(10.0, balance)
	assert_eq(state.hp, 80.0)


func test_downed_at_zero_and_back_after_the_respawn_time() -> void:
	var state := PlayerState.new(1, 20.0)
	assert_true(state.hurt(50.0, balance))
	assert_true(state.downed)
	assert_eq(state.deaths, 1)
	assert_false(state.tick(balance.player_respawn_seconds * 0.5))
	assert_true(state.tick(balance.player_respawn_seconds))
	assert_false(state.downed)
	assert_eq(state.hp, 20.0)
	assert_eq(state.life, 1)


func test_xp_raises_the_level() -> void:
	var state := PlayerState.new()
	assert_eq(state.add_xp(13.0, balance), 0)
	assert_eq(state.add_xp(1.0, balance), 1)
	assert_eq(state.level, 2)


func test_world_state_round_trip() -> void:
	var frame := WorldStateCodec.Frame.new()
	frame.seq = 513
	frame.host_ms = 123456
	frame.run_time = 61.5
	frame.brosel_alive = 321
	frame.phase = 1
	frame.wirtshaeuser = [Vector3i(0, 1, 0), Vector3i(4, 3, 2)]
	var e := WorldStateCodec.Entry.new()
	e.peer_id = 1234567
	e.hp = 42.5
	e.max_hp = 100.0
	e.xp = 99.0
	e.level = 7
	e.downed = true
	e.life = 3
	e.choosing = true
	e.pending_levels = 2
	e.gold = 1234
	e.rerolls = 3
	e.banishes = 1
	e.weapons = PackedInt32Array([0, 8, 200, 1250, 500, 300, 50, 1000, 5, 1, 7, 0, 0, 0, 0, 0])
	e.passives = PackedInt32Array([9, 1, 150])
	e.items = PackedInt32Array([3, 2, 0, 1])
	e.knodl_state = Knodl.State.REELING
	e.knodl_cooldown = 2.35
	e.knodl_mass = 812.25
	e.knodl_position = Vector3(-12.5, 3.25, 40.0)
	e.knodl_rotation = Quaternion(Vector3.UP, 1.0)
	frame.entries.append(e)
	var data: PackedByteArray = WorldStateCodec.encode(frame)
	assert_eq(data.size(), WorldStateCodec.HEADER_SIZE + 2 * WorldStateCodec.WIRT_SIZE + 1 + WorldStateCodec.PLAYER_SIZE
			+ 2 * WorldStateCodec.WEAPON_SIZE + WorldStateCodec.PASSIVE_SIZE + 2 * WorldStateCodec.ITEM_SIZE)
	var back: WorldStateCodec.Frame = WorldStateCodec.decode(data)
	assert_not_null(back)
	assert_eq(back.seq, 513)
	assert_eq(back.brosel_alive, 321)
	assert_almost_eq(back.run_time, 61.5, 0.001)
	assert_eq(back.phase, 1)
	assert_eq(back.wirtshaeuser, frame.wirtshaeuser)
	var b: WorldStateCodec.Entry = back.entries[0]
	assert_eq(b.peer_id, 1234567)
	assert_almost_eq(b.hp, 42.5, 0.001)
	assert_eq(b.level, 7)
	assert_true(b.downed)
	assert_eq(b.life, 3)
	assert_true(b.choosing)
	assert_eq(b.pending_levels, 2)
	assert_eq(b.gold, 1234)
	assert_eq(b.rerolls, 3)
	assert_eq(b.banishes, 1)
	assert_eq(b.weapons, e.weapons)
	assert_eq(b.passives, e.passives)
	assert_eq(b.items, e.items)
	assert_eq(b.knodl_state, Knodl.State.REELING)
	assert_almost_eq(b.knodl_cooldown, 2.35, 0.05)
	assert_almost_eq(b.knodl_mass, 812.25, 0.001)
	assert_almost_eq(b.knodl_position.x, -12.5, 0.001)
	assert_almost_eq(b.knodl_rotation.angle_to(e.knodl_rotation), 0.0, 0.001)
	assert_null(WorldStateCodec.decode(data.slice(0, data.size() - 1)))
	var longer: PackedByteArray = data.duplicate()
	longer.append(0)
	assert_null(WorldStateCodec.decode(longer))


func test_input_message_counts_schupfn_presses() -> void:
	var message := InputMessage.new()
	message.schupfn_presses = 255
	var back: InputMessage = InputMessage.from_bytes(message.to_bytes())
	assert_eq(back.schupfn_presses, 255)
