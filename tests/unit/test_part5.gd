extends GutTest
## 1.4 Part 5 (features): die Tageskarte (Daily Kirtag) – one card a day, the same for everyone,
## the first try counts, the streak for its Aufträge.

var balance: BalanceData
var content: GameContent


func before_each() -> void:
	balance = load("res://data/balance.tres")
	content = GameContent.load_default()
	Profile.reset_memory()


func after_all() -> void:
	Profile.reset_memory()
	RunSetup.daily = ""
	RunSetup.seed = -1


func test_the_day_follows_utc_and_counts_back_over_month_ends() -> void:
	var unix: int = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 6, "hour": 23,
		"minute": 59, "second": 0})
	assert_eq(Daily.day_id(unix), "20261106")
	assert_eq(Daily.day_id(unix + 60), "20261107")
	assert_eq(Daily.day_before("20261201"), "20261130")
	assert_eq(Daily.day_before("20270101"), "20261231")
	assert_eq(Daily.board_map("20261106"), "daily_20261106")
	assert_eq(Daily.date_text("20261106"), "6.11.2026")


func test_one_card_a_day_the_same_for_everyone() -> void:
	var card: Dictionary = Daily.pick(content, balance, "20261106")
	assert_eq(Daily.pick(content, balance, "20261106"), card, "the same day gives the same card")
	assert_not_null(content.character(card["character"]))
	assert_not_null(content.map_info(card["map"]))
	assert_between(int(card["grant"]), balance.daily_grant_min, balance.daily_grant_max)
	assert_gt(int(card["seed"]), 0)
	# Over a month, the card changes and visits several Knödlinger and maps.
	var characters: Dictionary = {}
	var maps: Dictionary = {}
	for d: int in range(1, 31):
		var other: Dictionary = Daily.pick(content, balance, "202611%02d" % d)
		characters[other["character"]] = true
		maps[other["map"]] = true
	assert_gt(characters.size(), 4)
	assert_gt(maps.size(), 2)


func test_a_daily_run_takes_the_card() -> void:
	RunSetup.use_daily(content, balance, "20261106")
	var card: Dictionary = Daily.pick(content, balance, "20261106")
	assert_eq(RunSetup.character, String(card["character"]))
	assert_eq(RunSetup.map, String(card["map"]))
	assert_eq(RunSetup.grant, int(card["grant"]))
	assert_eq(RunSetup.seed, int(card["seed"]))
	assert_eq(RunSetup.daily, "20261106")


func test_only_the_first_try_counts_and_the_streak_needs_every_day() -> void:
	assert_false(Profile.daily_played("20261106"))
	assert_true(Profile.start_daily("20261106"), "the first try of the day counts")
	assert_false(Profile.start_daily("20261106"), "the second is practice")
	assert_eq(Profile.daily_streak("20261106"), 1)
	assert_true(Profile.start_daily("20261107"))
	assert_true(Profile.start_daily("20261108"))
	assert_eq(Profile.daily_streak("20261108"), 3)
	assert_eq(Profile.daily_streak("20261109"), 3, "the day after still shows the streak until it is missed")
	assert_eq(Profile.daily_streak("20261110"), 0, "a missed day ends it")
	assert_true(Profile.start_daily("20261111"))
	assert_eq(Profile.daily_streak("20261111"), 1)
	assert_eq(Profile.daily_best_streak(), 3)


func test_the_streak_aufgaben_are_stamped_after_a_run() -> void:
	for d: int in range(1, 8):
		Profile.start_daily("202611%02d" % d)
	var reward: Dictionary = Profile.record_run({"character": "ferdl", "map": "kirtag", "result": "LOST"})
	var ids: Array = (reward["quests"] as Array).map(func(q: QuestData) -> StringName: return q.id)
	assert_has(ids, &"stammkundschaft", "7 days in a row")
	assert_does_not_have(ids, &"abonnement", "30 days are still to come")


# --- Run-Abrechnung (5.4) --------------------------------------------------------------------------

func _manager() -> EnemyManager:
	var types: Array[EnemyTypeData] = [load("res://data/enemies/tourist.tres")]
	var manager := EnemyManager.new(balance, types, 16, 5)
	manager.populate(4, PackedVector3Array([Vector3.ZERO]))
	return manager


func test_damage_counts_for_its_source_and_only_what_the_enemy_had() -> void:
	var manager: EnemyManager = _manager()
	var hp: float = manager.hp[0]
	manager.source = 2
	manager.damage(0, hp * 0.5)
	manager.damage(0, hp * 10.0)
	assert_almost_eq(manager.dealt[2], hp, 0.01, "overkill does not count")
	assert_eq(manager.source_kills[2], 1)
	manager.source = -1
	manager.damage(1, 1.0)
	assert_eq(manager.dealt.size(), 3, "no source, no count")


func test_a_burn_counts_for_whoever_lit_it() -> void:
	var manager: EnemyManager = _manager()
	manager.source = 1
	manager.burn(0, manager.hp[0] * 2.0, 3.0)
	manager.source = -1
	var hp: float = manager.hp[0]
	for k: int in 120:
		manager.update(1.0 / 60.0, PackedVector3Array([Vector3(200.0, 0.0, 200.0)]))
	assert_almost_eq(manager.dealt[1], hp, 0.01)
	assert_eq(manager.source_kills[1], 1)


func test_the_bill_shows_numbers_short() -> void:
	assert_eq(RunEndScreen.short_number(950.0), "950")
	assert_eq(RunEndScreen.short_number(12345.0), "12,3k")
	assert_eq(RunEndScreen.short_number(4500000.0), "4,5 Mio")
