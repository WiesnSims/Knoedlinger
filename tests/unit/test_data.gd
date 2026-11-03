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


func test_m1_content_loads_with_translated_names() -> void:
	for dir: String in ["res://data/characters", "res://data/weapons", "res://data/knodl"]:
		var files: PackedStringArray = ResourceLoader.list_directory(dir)
		assert_gt(files.size(), 0, dir)
		for file: String in files:
			var data: Resource = load(dir.path_join(file))
			assert_not_null(data, file)
			var key: String = data.get("name_key")
			assert_ne(TranslationServer.translate(key), StringName(key), file)
	var ferdl: CharacterData = load("res://data/characters/ferdl.tres")
	assert_not_null(ferdl.start_weapon)
	assert_not_null(ferdl.knodl_sort)
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	assert_gte(wave.enemies.size(), 5, "M2: five enemy types")


func test_enemy_types_drop_brosel_and_hurt() -> void:
	for file: String in ResourceLoader.list_directory("res://data/enemies"):
		var data: EnemyTypeData = load("res://data/enemies".path_join(file))
		assert_gt(data.brosel_xp, 0, file)
		assert_gt(data.contact_damage, 0.0, file)


func test_the_catalog_has_the_m2_content_with_texts() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var base: int = 0
	var evolutions: int = 0
	for weapon: WeaponData in catalog.weapons:
		assert_not_null(weapon)
		if weapon.is_evolution:
			evolutions += 1
		else:
			base += 1
		for key: String in [weapon.name_key, weapon.desc_key]:
			assert_ne(TranslationServer.translate(key), StringName(key), key)
		if weapon.evolution != null:
			assert_true(weapon.evolution.is_evolution, String(weapon.id))
			assert_true(catalog.weapons.has(weapon.evolution), "evolution of %s is in the catalog" % weapon.id)
			assert_true(catalog.passives.has(weapon.evolves_with), "partner of %s is in the catalog" % weapon.id)
	assert_gte(base, 6, "M2: six weapons")
	assert_gte(evolutions, 2, "M2: two evolutions")
	var passive_count: int = 0
	for passive: PassiveData in catalog.passives:
		assert_not_null(passive)
		if passive.kind == PassiveData.Kind.PASSIVE:
			passive_count += 1
		for key: String in [passive.name_key, passive.desc_key]:
			assert_ne(TranslationServer.translate(key), StringName(key), key)
		for stat: StringName in passive.stats:
			assert_true(PlayerBuild.STATS.has(stat), "%s: unknown stat %s" % [passive.id, stat])
			var label: String = "STAT_" + String(stat).to_upper()
			assert_ne(TranslationServer.translate(label), StringName(label), label)
	assert_gte(passive_count, 6, "M2: six passives")
	assert_lt(catalog.weapons.size(), 256)
	assert_lt(catalog.passives.size(), 256)


func test_characters_start_with_a_weapon_from_the_catalog() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for file: String in ResourceLoader.list_directory("res://data/characters"):
		var character: CharacterData = load("res://data/characters".path_join(file))
		assert_true(catalog.weapons.has(character.start_weapon), file)


func test_the_wave_uses_known_enemies_and_has_broeselfresser() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	assert_lte(wave.enemies.size(), 16, "type fits 4 bits in snapshots")
	var eaters: int = 0
	for enemy: EnemyTypeData in wave.enemies:
		if enemy.eats_knodl:
			eaters += 1
			assert_gt(enemy.bite_per_second, 0.0, String(enemy.id))
	assert_gte(eaters, 2)
	for entry: WaveEntry in wave.entries:
		assert_true(wave.enemies.has(entry.enemy))
		assert_lt(entry.from_minute, entry.to_minute)


func test_nothing_friendly_uses_krampus_red() -> void:
	# GAME-DESIGN.md: one danger colour for enemy attacks, nothing friendly may use it.
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for weapon: WeaponData in catalog.weapons:
		var c: Color = weapon.color
		assert_false(c.r > 0.7 and c.g < 0.35 and c.b < 0.35, String(weapon.id))
