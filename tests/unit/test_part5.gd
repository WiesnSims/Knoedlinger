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


func test_the_reckoning_reaches_the_client_inside_the_shared_summary() -> void:
	# The shared summary is a plain Dictionary over a reliable RPC: nested dictionaries survive it.
	var shared: Dictionary = {"damage_by_source": {"kuhglocke": 85.9, "knodl": 17.5}, "downed_by": {"perchte": 2}}
	var back: Variant = bytes_to_var(var_to_bytes(shared))
	assert_eq(back, shared)


# --- Der Standler (5.2) ------------------------------------------------------------------------------

func _shop_state() -> PlayerState:
	var build := PlayerBuild.new(load("res://data/catalog/catalog.tres"), balance)
	return PlayerState.new(1, 100.0, build)


func test_a_shop_offer_carries_its_prices() -> void:
	var offer := OfferCodec.Offer.new()
	offer.type = OfferCodec.Type.SHOP
	offer.seq = 7
	offer.cards = [Card.new(Card.Kind.ITEM, 3, 1, 1), Card.new(Card.Kind.ITEM, 5, 2, 1)]
	offer.prices = PackedInt32Array([45, 70])
	var back: OfferCodec.Offer = OfferCodec.decode_offer(OfferCodec.encode_offer(offer))
	assert_not_null(back)
	assert_eq(back.type, OfferCodec.Type.SHOP)
	assert_eq(back.prices, PackedInt32Array([45, 70]))
	assert_eq(back.cards[1].index, 5)
	offer.type = OfferCodec.Type.OFFER
	assert_eq(OfferCodec.decode_offer(OfferCodec.encode_offer(offer)).prices.size(), 0, "a plain offer has none")


func test_buying_costs_gold_and_leaving_closes_the_shop() -> void:
	var flow := LevelUpFlow.new(balance, 3)
	var state: PlayerState = _shop_state()
	var item: int = 0
	var cards: Array[Card] = [Card.new(Card.Kind.ITEM, item, state.build.catalog.items[item].rarity, 1)]
	var bought: Array = []
	var closed: Array = []
	flow.bought.connect(func(peer: int, card: int) -> void: bought.append([peer, card]))
	flow.shop_closed.connect(func(peer: int) -> void: closed.append(peer))
	flow.open_shop(1, state, cards, PackedInt32Array([40]), false)
	assert_true(flow.is_shop(1))
	assert_true(state.choosing)
	var pick := OfferCodec.Choice.new()
	pick.seq = flow._seqs[1]
	flow.on_choice(1, OfferCodec.encode_choice(pick), state, false)
	assert_eq(state.build.item_count(item), 0, "no gold, no item")
	assert_true(flow.is_shop(1), "the shop stays open")
	state.build.gold = 50
	pick.seq = flow._seqs[1]
	flow.on_choice(1, OfferCodec.encode_choice(pick), state, false)
	assert_eq(state.build.item_count(item), 1)
	assert_eq(state.build.gold, 10)
	assert_eq(bought, [[1, 0]])
	assert_false(state.choosing)
	flow.open_shop(1, state, cards, PackedInt32Array([40]), false)
	var leave := OfferCodec.Choice.new()
	leave.seq = flow._seqs[1]
	leave.action = OfferCodec.Action.SKIP
	flow.on_choice(1, OfferCodec.encode_choice(leave), state, false)
	assert_false(flow.is_shop(1))
	assert_eq(closed, [1])
	assert_eq(state.build.gold, 10, "leaving pays nothing")


func test_his_prices_rise_with_every_buy_and_the_clock() -> void:
	var sites := RunSites.new(null, balance, 1)
	assert_eq(sites.price(0, 0, 0.0), balance.standler_prices[0])
	assert_gt(sites.price(0, 1, 0.0), sites.price(0, 0, 0.0))
	assert_gt(sites.price(0, 0, 600.0), sites.price(0, 0, 0.0))
	assert_gt(sites.price(3, 0, 0.0), sites.price(0, 0, 0.0), "Hofratswürdig costs more")


func test_a_site_event_travels() -> void:
	var queue := RunEventCodec.Queue.new()
	queue.site(RunSites.Site.MARTERL, 2, RunSites.State.ACTIVE, RunSites.Marterl.GIER, 12.5, -40.0)
	var back: Array[RunEventCodec.Event] = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(back.size(), 1)
	assert_eq(back[0].kind, RunEventCodec.Kind.SITE)
	assert_eq([back[0].a, back[0].id, back[0].c, back[0].b], [RunSites.Site.MARTERL, 2, RunSites.State.ACTIVE,
		RunSites.Marterl.GIER])
	assert_almost_eq(back[0].z, -40.0, 0.001)


func test_the_bill_shows_numbers_short() -> void:
	assert_eq(RunEndScreen.short_number(950.0), "950")
	assert_eq(RunEndScreen.short_number(12345.0), "12,3k")
	assert_eq(RunEndScreen.short_number(4500000.0), "4,5 Mio")
