extends GutTest
## M4 meta: the Profile (Schilling, quests, unlocks, records, Grant levels, export code) and the
## Stammtisch bonus on a build. Tests run on an in-memory profile (Profile.persistent is false).


func before_each() -> void:
	Profile.reset_memory()


func after_all() -> void:
	Profile.reset_memory()


func _run(extra: Dictionary = {}) -> Dictionary:
	var run: Dictionary = {
		"character": "ferdl", "map": "kirtag", "grant": 1, "result": "CLOSED", "time": 905.0, "level": 25,
		"kills": 3000, "kills_by_type": {"gelse": 1200, "tourist": 1500}, "cash_ins": [0, 1, 2, 0],
		"bosses": ["oberkrampus"], "throws": 12, "stempel": 2, "best_knodl_mass": 800.0, "schilling": 120,
		"found": {"weapons": ["schneeschaufel"], "passives": ["lederhosn"], "items": ["gluecksschwein"]},
	}
	run.merge(extra, true)
	return run


func test_a_run_pays_schilling_and_stamps_quests() -> void:
	var reward: Dictionary = Profile.record_run(_run())
	assert_eq(reward["schilling"], 120)
	var done: Array[StringName] = []
	for quest: QuestData in reward["quests"]:
		done.append(quest.id)
	assert_true(done.has(&"gelsenplage"), "1,200 Gelsen")
	assert_true(done.has(&"krampus_weg"), "Oberkrampus beaten")
	assert_true(done.has(&"lehrling"), "level 20")
	assert_false(done.has(&"geselle"), "not level 30")
	var paid: int = 120
	for quest: QuestData in reward["quests"]:
		paid += quest.reward_schilling
	assert_eq(Profile.schilling(), paid, "run plus quest rewards")
	var again: Dictionary = Profile.record_run(_run())
	for quest: QuestData in again["quests"]:
		assert_false(done.has(quest.id), "a quest is stamped once")


func test_quest_rewards_unlock_what_they_name() -> void:
	assert_false(Profile.is_unlocked(&"weapon", &"mozartkugel_orbit"), "locked behind the Oberkrampus")
	assert_true(Profile.is_unlocked(&"weapon", &"schneeschaufel"), "no quest names it: open")
	assert_not_null(Profile.unlocking_quest(&"weapon", &"mozartkugel_orbit"))
	Profile.record_run(_run())
	assert_true(Profile.is_unlocked(&"weapon", &"mozartkugel_orbit"))
	assert_null(Profile.unlocking_quest(&"weapon", &"mozartkugel_orbit"))


func test_preview_builds_open_everything_without_touching_the_save() -> void:
	assert_true(Profile.is_preview_host("v1-4.knoedlinger.pages.dev"))
	assert_true(Profile.is_preview_host("cf33f1c7.knoedlinger.pages.dev"))
	assert_false(Profile.is_preview_host("knoedlinger.pages.dev"), "the live site keeps its locks")
	assert_false(Profile.is_preview_host("127.0.0.1"))
	assert_false(Profile.unlock_all, "off outside a preview")
	Profile.unlock_all = true
	for quest: QuestData in Profile.content.quests:
		if quest.unlock_kind != &"":
			assert_true(Profile.is_unlocked(quest.unlock_kind, quest.unlock_id), String(quest.unlock_id))
			assert_null(Profile.unlocking_quest(quest.unlock_kind, quest.unlock_id))
	assert_eq(Profile.grant_unlocked(), Profile.content.grants.size() - 1, "every Grant level")
	assert_eq((Profile.data["quests"] as Dictionary).size(), 0, "nothing stamped")
	var reward: Dictionary = Profile.record_run(_run({"result": "WON"}))
	assert_true(reward["grant_unlocked"], "a win still raises the saved Grant level")
	assert_false((reward["quests"] as Array).is_empty(), "quests still count and pay")
	Profile.unlock_all = false
	assert_eq(Profile.grant_unlocked(), 2)


func test_found_things_fill_the_almanach() -> void:
	Profile.record_run(_run())
	assert_true(Profile.is_found(&"weapon", &"schneeschaufel"))
	assert_true(Profile.is_found(&"item", &"gluecksschwein"))
	assert_true(Profile.is_found(&"enemy", &"gelse"))
	assert_false(Profile.is_found(&"enemy", &"perchte"))


func test_buying_ranks_costs_more_each_time_and_stops_at_the_max() -> void:
	var upgrade: MetaUpgradeData = Profile.content.upgrades[0]
	Profile.reset_memory(100000)
	var before: int = Profile.schilling()
	assert_true(Profile.buy(upgrade))
	assert_eq(Profile.schilling(), before - upgrade.cost(0))
	assert_gt(upgrade.cost(1), upgrade.cost(0))
	while Profile.rank(upgrade.id) < upgrade.max_rank:
		assert_true(Profile.buy(upgrade))
	assert_false(Profile.buy(upgrade), "maxed")
	Profile.reset_memory(0)
	assert_false(Profile.buy(upgrade), "too dear")


func test_meta_bonus_reaches_the_build() -> void:
	Profile.reset_memory(100000)
	for upgrade: MetaUpgradeData in Profile.content.upgrades:
		if upgrade.stat == &"max_hp" or upgrade.stat == &"weapon_slots" or upgrade.stat == &"rerolls":
			Profile.buy(upgrade)
	var balance := BalanceData.new()
	var build := PlayerBuild.new(load("res://data/catalog/catalog.tres"), balance)
	build.apply_meta(Profile.meta_bonus())
	assert_gt(build.stat(&"max_hp"), 0.0)
	assert_eq(build.weapon_slots, balance.weapon_slots + 1)
	assert_eq(build.rerolls, balance.rerolls_per_run + 1)


func test_winning_unlocks_the_next_grant_level_and_keeps_records() -> void:
	assert_eq(Profile.grant_unlocked(), 1)
	Profile.record_run(_run({"result": "CLOSED"}))
	assert_eq(Profile.grant_unlocked(), 1, "not a win")
	var reward: Dictionary = Profile.record_run(_run({"result": "WON", "kills": 5000}))
	assert_true(reward["grant_unlocked"])
	assert_eq(Profile.grant_unlocked(), 2)
	var record: Dictionary = Profile.record(&"ferdl", &"kirtag")
	assert_eq(int(record["wins"]), 1)
	assert_eq(int(record["kills"]), 5000)
	assert_true(reward["records"].has("kills"), "a better run is a new record")


func test_the_export_code_round_trips_and_refuses_damage() -> void:
	Profile.record_run(_run())
	Profile.reset_memory(0)
	Profile.record_run(_run({"result": "WON"}))
	var schilling: int = Profile.schilling()
	var code: String = Profile.export_code()
	assert_true(code.begins_with(Profile.CODE_PREFIX))
	Profile.reset_memory(0)
	assert_eq(Profile.import_code(code), "")
	assert_eq(Profile.schilling(), schilling)
	assert_eq(Profile.grant_unlocked(), 2)
	assert_eq(Profile.import_code("hallo"), "format")
	var broken: String = code.substr(0, code.length() - 14) + "AAAA" + code.substr(code.length() - 10)
	assert_eq(Profile.import_code(broken), "check")


func test_grant_levels_get_harder_and_pay_more() -> void:
	var grants: Array[GrantData] = Profile.content.grants
	assert_eq(grants.size(), 5)
	for k: int in range(1, grants.size()):
		assert_gte(grants[k].enemy_hp, grants[k - 1].enemy_hp)
		assert_gte(grants[k].schilling, grants[k - 1].schilling)
	assert_eq(grants[1].enemy_hp, 1.0, "Normal is the plain game")


func test_every_quest_and_upgrade_is_known() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var kinds: Array[StringName] = [&"kills", &"cash_ins", &"level", &"wins", &"runs", &"bosses", &"boss_no_throw",
		&"stempel", &"knodl", &"survive", &"overtime", &"schilling", &"items", &"grant_win", &"coop",
		&"daily_streak", &"daily_days"]
	for quest: QuestData in Profile.content.quests:
		assert_true(kinds.has(quest.kind), "%s: kind %s" % [quest.id, quest.kind])
		for key: String in [quest.title_key, quest.desc_key]:
			assert_ne(TranslationServer.translate(key), StringName(key), key)
		if quest.unlock_kind == &"weapon":
			assert_true(catalog.weapons.any(func(w: WeaponData) -> bool: return w.id == quest.unlock_id), String(quest.id))
		elif quest.unlock_kind == &"item":
			assert_true(catalog.items.any(func(i: ItemData) -> bool: return i.id == quest.unlock_id), String(quest.id))
	for upgrade: MetaUpgradeData in Profile.content.upgrades:
		assert_true(PlayerBuild.STATS.has(upgrade.stat) or MetaUpgradeData.SPECIALS.has(upgrade.stat), String(upgrade.id))
		assert_not_null(upgrade.icon, String(upgrade.id))
	for enemy: EnemyTypeData in Profile.content.enemies:
		assert_ne(TranslationServer.translate(enemy.desc_key), StringName(enemy.desc_key), String(enemy.id))
