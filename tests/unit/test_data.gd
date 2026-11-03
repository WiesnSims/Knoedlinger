extends GutTest


func test_balance_loads_with_sane_numbers() -> void:
	var balance: BalanceData = load("res://data/balance.tres")
	assert_not_null(balance)
	assert_gt(balance.snapshot_rate_hz, 0.0)
	assert_gt(balance.grid_cell_size, 0.0)
	assert_eq(balance.client_bandwidth_budget_kbps, 60.0)


func test_every_enemy_type_loads_with_a_translated_name() -> void:
	var files: PackedStringArray = ResourceLoader.list_directory("res://data/enemies")
	assert_gt(files.size(), 0)
	for file: String in files:
		var data: EnemyTypeData = load("res://data/enemies".path_join(file)) as EnemyTypeData
		assert_not_null(data, file)
		if data == null:
			continue
		assert_gt(data.max_hp, 0.0, file)
		assert_ne(TranslationServer.translate(data.name_key), StringName(data.name_key), file)


func test_enemy_types_fit_the_snapshot_type_bits() -> void:
	assert_lt(ResourceLoader.list_directory("res://data/enemies").size(), 16)
