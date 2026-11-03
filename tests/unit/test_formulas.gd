extends GutTest

var balance: BalanceData


func before_each() -> void:
	balance = BalanceData.new()


func test_xp_curve_matches_the_design() -> void:
	# GAME-DESIGN.md: 1 -> 2 needs ~13, 20 -> 21 ~325, 50 -> 51 ~1405.
	assert_almost_eq(Formulas.xp_to_next(1, balance), 13.4, 0.001)
	assert_almost_eq(Formulas.xp_to_next(20, balance), 325.0, 0.001)
	assert_almost_eq(Formulas.xp_to_next(50, balance), 1405.0, 0.001)


func test_levels_from_total_xp() -> void:
	assert_eq(Formulas.level_for_xp(0.0, balance), 1)
	assert_eq(Formulas.level_for_xp(13.3, balance), 1)
	assert_eq(Formulas.level_for_xp(13.4, balance), 2)
	var to_three: float = Formulas.xp_to_next(1, balance) + Formulas.xp_to_next(2, balance)
	assert_eq(Formulas.level_for_xp(to_three, balance), 3)
	assert_almost_eq(Formulas.level_progress(6.7, balance), 0.5, 0.001)


func test_knodl_starts_at_base_radius_and_grows() -> void:
	assert_almost_eq(Formulas.knodl_radius(0.0, balance), balance.knodl_base_radius, 0.0001)
	var small: float = Formulas.knodl_radius(50.0, balance)
	var big: float = Formulas.knodl_radius(500.0, balance)
	assert_gt(small, balance.knodl_base_radius)
	assert_gt(big, small)
	# Cube root: eight times the (1 + m / scale) means twice the radius.
	var m8: float = (8.0 - 1.0) * balance.knodl_mass_scale
	assert_almost_eq(Formulas.knodl_radius(m8, balance), balance.knodl_base_radius * 2.0, 0.002)


func test_knodl_radius_is_capped() -> void:
	assert_eq(Formulas.knodl_radius(1.0e9, balance), balance.knodl_max_radius)
	assert_almost_eq(Formulas.knodl_radius(-5.0, balance), balance.knodl_base_radius, 0.0001)


func test_contact_damage_is_base_times_speed_times_radius() -> void:
	assert_eq(Formulas.knodl_contact_damage(balance.knodl_min_hit_speed * 0.5, 1.0, balance), 0.0)
	assert_almost_eq(Formulas.knodl_contact_damage(10.0, 2.0, balance), balance.knodl_contact_damage * 20.0, 0.0001)
	assert_almost_eq(Formulas.knodl_contact_damage(10.0, 2.0, balance, 1.4), balance.knodl_contact_damage * 28.0, 0.0001)


func test_a_big_knodl_slows_the_player_but_not_below_the_floor() -> void:
	assert_eq(Formulas.knodl_speed_factor(balance.knodl_base_radius, balance), 1.0)
	assert_lt(Formulas.knodl_speed_factor(2.0, balance), 1.0)
	assert_eq(Formulas.knodl_speed_factor(100.0, balance), balance.knodl_min_speed_factor)


func test_xp_splits_into_brosel_sizes() -> void:
	assert_eq(Formulas.split_into_brosel(37, balance), PackedInt32Array([25, 5, 5, 1, 1]))
	assert_eq(Formulas.split_into_brosel(1, balance), PackedInt32Array([1]))
	assert_eq(Formulas.split_into_brosel(0, balance), PackedInt32Array())
