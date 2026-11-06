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


## Snapshots carry an enemy's type as an index into its map's wave list, in 4 bits.
func test_enemy_types_fit_the_snapshot_type_bits() -> void:
	for file: String in ResourceLoader.list_directory("res://data/waves"):
		var wave: WaveData = load("res://data/waves".path_join(file))
		assert_lte(wave.enemies.size(), SnapshotCodec.MAX_TYPES, file)


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
		# Bosses pay out through their BossData (golden Brösel, a chest) instead.
		if not data.boss:
			assert_gt(data.brosel_xp, 0, file)
		assert_gt(data.contact_damage, 0.0, file)


func test_m3_bosses_are_complete() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	var bosses: Array[BossData] = []
	for entry: WaveBoss in wave.bosses:
		bosses.append(entry.boss)
	assert_not_null(wave.final_boss)
	bosses.append(wave.final_boss)
	assert_eq(bosses.size(), 3, "Oberkrampus twice and the Hofrat")
	assert_true(wave.final_boss.final)
	assert_lt(wave.formular_minute, wave.final_boss_minute)
	for boss: BossData in bosses:
		assert_true(boss.enemy.boss, String(boss.id))
		assert_gte(wave.enemies.find(boss.enemy), 0, "%s has a body in the wave" % boss.id)
		assert_false(boss.attacks.is_empty(), String(boss.id))
		for key: String in [boss.name_key, boss.intro_key, boss.defeat_key]:
			assert_ne(TranslationServer.translate(key), StringName(key), key)
		for attack: AttackData in boss.attacks:
			assert_gt(attack.telegraph, 0.3, "%s: every attack is telegraphed" % attack.id)
			if attack.summon != null:
				assert_gte(wave.enemies.find(attack.summon), 0, "%s summons a known type" % attack.id)
			if attack.toast_key != "":
				assert_ne(TranslationServer.translate(attack.toast_key), StringName(attack.toast_key))


func test_elites_have_a_telegraphed_attack_and_splits_are_known() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	var elites: int = 0
	for data: EnemyTypeData in wave.enemies:
		if data.attack != null:
			elites += 1
			assert_gt(data.attack.telegraph, 0.3, String(data.id))
			assert_gt(data.attack.cooldown, data.attack.telegraph, String(data.id))
		if data.split_into != null:
			assert_gte(wave.enemies.find(data.split_into), 0, "%s splits into a type in the wave" % data.id)
	assert_gte(elites, 2, "Perchte and Radlfahrer")


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
	assert_lt(catalog.items.size(), 256)
	for weapon: WeaponData in catalog.weapons:
		assert_false(weapon.level_mods.is_empty(), String(weapon.id))
		for key: StringName in weapon.level_mods:
			assert_true(PlayerBuild.WEAPON_MODS.has(key), "%s: unknown mod %s" % [weapon.id, key])
			var label: String = "STAT_" + String(key).to_upper()
			assert_ne(TranslationServer.translate(label), StringName(label), label)
		assert_gte(weapon.max_amount, weapon.amount, String(weapon.id))


func test_items_are_known_to_the_game() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var per_rarity: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	for item: ItemData in catalog.items:
		assert_not_null(item)
		assert_not_null(item.icon, String(item.id))
		per_rarity[clampi(item.rarity, 0, 3)] += 1
		for key: String in [item.name_key, item.desc_key]:
			assert_ne(TranslationServer.translate(key), StringName(key), key)
		for stat: StringName in item.stats:
			assert_true(PlayerBuild.STATS.has(stat), "%s: unknown stat %s" % [item.id, stat])
		if item.effect != &"":
			assert_true(PlayerBuild.EFFECTS.has(item.effect), "%s: unknown effect %s" % [item.id, item.effect])
		assert_false(item.stats.is_empty() and item.effect == &"" and item.effects.is_empty(), "%s does something" % item.id)
	for r: int in 4:
		assert_gt(per_rarity[r], 0, "every chest rarity has items (rarity %d)" % r)


func test_characters_start_with_a_weapon_from_the_catalog() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for file: String in ResourceLoader.list_directory("res://data/characters"):
		var character: CharacterData = load("res://data/characters".path_join(file))
		assert_true(catalog.weapons.has(character.start_weapon), file)


func test_the_wave_uses_known_enemies_and_has_broeselfresser() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	assert_lte(wave.enemies.size(), SnapshotCodec.MAX_TYPES, "type fits 5 bits in snapshots")
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


func test_every_upgrade_has_an_icon() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for weapon: WeaponData in catalog.weapons:
		assert_not_null(weapon.icon, String(weapon.id))
	for passive: PassiveData in catalog.passives:
		assert_not_null(passive.icon, String(passive.id))


func test_every_map_has_its_places_and_a_wave() -> void:
	var content: GameContent = GameContent.load_default()
	for info: MapInfo in content.maps:
		var map: MapData = load("res://data/maps/%s.tres" % info.id)
		assert_not_null(map, String(info.id))
		var wave: WaveData = map.wave if map.wave != null else load("res://data/waves/kirtag.tres")
		assert_lte(wave.enemies.size(), SnapshotCodec.MAX_TYPES, String(info.id))
		assert_not_null(wave.final_boss, String(info.id))
		for boss: WaveBoss in wave.bosses:
			assert_true(wave.enemies.has(boss.boss.enemy), "%s: boss body %s in the wave" % [info.id, boss.boss.id])
		assert_true(wave.enemies.has(wave.final_boss.enemy), String(info.id))
		assert_gte(map.wirtshaus_spots.size(), 4, String(info.id))
		assert_gte(map.stempel_spots.size(), 3, String(info.id))
		assert_gte(map.chest_spots.size(), 6, String(info.id))
		assert_gte(map.bot_waypoints.size(), 4, String(info.id))
		var half: float = map.half_size
		for list: PackedVector2Array in [map.wirtshaus_spots, map.stempel_spots, map.chest_spots]:
			for spot: Vector2 in list:
				assert_true(absf(spot.x) < half and absf(spot.y) < half, "%s: spot %s inside the map" % [info.id, spot])
