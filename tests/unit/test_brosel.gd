extends GutTest

var balance: BalanceData
var field: BroselField


func before_each() -> void:
	balance = BalanceData.new()
	balance.brosel_scatter = 0.0
	field = _make_field(balance)


func after_each() -> void:
	field.free()


func _make_field(b: BalanceData) -> BroselField:
	var f := BroselField.new()
	f.setup(b, null, 50.0)
	return f


func test_a_knodl_rolling_over_brosel_gets_xp_and_mass() -> void:
	field.drop(3.0, 0.0, 5, true)
	field.drop(30.0, 0.0, 1, true)
	field.absorb(Vector3(3.0, 0.5, 0.0), 0.5, 7)
	var credits: Dictionary[int, Vector2] = field.take_credits()
	assert_eq(credits[7], Vector2(5.0, 5.0))
	assert_eq(field.active_count, 1)


func test_shed_brosel_give_mass_but_no_xp_and_wait_before_pickup() -> void:
	field.drop(0.0, 0.0, 4, false, 1.0)
	field.absorb(Vector3(0.0, 0.5, 0.0), 1.0, 2)
	assert_true(field.take_credits().is_empty(), "too early")
	var none: Dictionary[int, Vector4] = {}
	field.update(1.1, none)
	field.absorb(Vector3(0.0, 0.5, 0.0), 1.0, 2)
	assert_eq(field.take_credits()[2], Vector2(0.0, 4.0))


func test_brosel_near_the_player_fly_to_their_knodl() -> void:
	field.drop(0.5, 0.0, 1, true)
	field.attract(Vector3.ZERO, 1.8, 1.0, 3)
	var knodls: Dictionary[int, Vector4] = {3: Vector4(-3.0, 0.5, 0.0, 0.5)}
	for frame: int in 60:
		field.update(1.0 / 60.0, knodls)
	assert_eq(field.take_credits()[3], Vector2(1.0, 1.0))
	assert_eq(field.active_count, 0)


func test_a_player_high_in_the_air_pulls_no_brosel_up() -> void:
	field.drop(0.5, 0.0, 1, true)
	field.attract(Vector3(0.0, 6.0, 0.0), 1.8, 1.0, 3)
	var knodls: Dictionary[int, Vector4] = {3: Vector4(-3.0, 6.0, 0.0, 0.5)}
	for frame: int in 60:
		field.update(1.0 / 60.0, knodls)
	assert_true(field.take_credits().is_empty(), "too high above them")
	field.attract(Vector3(0.0, 0.6, 0.0), 1.8, 1.0, 3)
	for frame: int in 60:
		field.update(1.0 / 60.0, knodls)
	assert_eq(field.take_credits()[3], Vector2(1.0, 1.0), "a small hop still pulls")


func test_a_knodl_hanging_in_the_air_eats_nothing_below() -> void:
	field.drop(0.0, 0.0, 3, true)
	field.absorb(Vector3(0.0, 4.0, 0.0), 0.5, 2)
	assert_true(field.take_credits().is_empty())
	field.absorb(Vector3(0.0, 0.6, 0.0), 0.5, 2)
	assert_eq(field.take_credits()[2], Vector2(3.0, 3.0))


func test_a_full_pool_merges_instead_of_losing_xp() -> void:
	var small := BalanceData.new()
	small.brosel_cap = 4
	small.brosel_scatter = 0.0
	var tiny: BroselField = _make_field(small)
	for i: int in 10:
		tiny.drop(float(i), 0.0, 1, true)
	assert_eq(tiny.active_count, 4)
	assert_eq(tiny.total_value(), 10)
	assert_eq(tiny.merges, 6)
	tiny.free()


func test_clients_mirror_the_host_through_the_codec() -> void:
	var mirror: BroselField = _make_field(balance)
	field.drop(1.0, 2.0, 5, true)
	field.drop(-4.25, 7.5, 1, false)
	field.drop(9.0, 9.0, 25, true)
	var changes: Array[PackedInt32Array] = field.take_changes()
	assert_true(BroselCodec.apply(BroselCodec.encode(changes[1], changes[0], field), mirror))
	assert_eq(mirror.active_count, 3)
	field.absorb(Vector3(1.0, 0.5, 2.0), 0.5, 1)
	field.drop(20.0, 20.0, 5, true)
	changes = field.take_changes()
	assert_true(BroselCodec.apply(BroselCodec.encode(changes[1], changes[0], field), mirror))
	assert_eq(mirror.active_count, field.active_count)
	assert_eq(mirror.total_value(), field.total_value())
	for i: int in field.capacity:
		if field.alive[i] != 0:
			assert_eq(mirror.alive[i], 1)
			assert_almost_eq(mirror.x[i], field.x[i], 0.01)
			assert_eq(mirror.flags[i], field.flags[i])
	assert_false(BroselCodec.apply(PackedByteArray([1, 2]), mirror))
	mirror.free()


func test_nearest_finds_the_closest_lying_brosel() -> void:
	field.drop(5.0, 0.0, 1, true)
	field.drop(2.0, 1.0, 1, true)
	assert_eq(field.nearest(0.0, 0.0, 10.0), Vector2(2.0, 1.0))
	assert_false(field.nearest(30.0, 30.0, 3.0).is_finite())
