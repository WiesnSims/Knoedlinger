extends GutTest
## PlayerBuild, CardDealer and LevelUpFlow: stats from passives, slots, rarity, evolutions, the
## mirror on clients, and the Speisekarte flow (pick, reroll, banish, skip, queued level-ups).

var balance: BalanceData
var catalog: UpgradeCatalog
var rng: RandomNumberGenerator


func before_each() -> void:
	balance = BalanceData.new()
	catalog = load("res://data/catalog/catalog.tres")
	rng = RandomNumberGenerator.new()
	rng.seed = 5


func _weapon(id: StringName) -> int:
	for k: int in catalog.weapons.size():
		if catalog.weapons[k].id == id:
			return k
	return -1


func _passive(id: StringName) -> int:
	for k: int in catalog.passives.size():
		if catalog.passives[k].id == id:
			return k
	return -1


func _take(build: PlayerBuild, kind: Card.Kind, index: int, times: int = 1, rarity: int = Card.Rarity.COMMON) -> void:
	for t: int in times:
		build.apply(Card.new(kind, index, rarity), balance)


func test_passive_levels_add_up_and_rarity_scales_them() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var lederhosn: int = _passive(&"lederhosn")
	_take(build, Card.Kind.PASSIVE, lederhosn, 2)
	assert_almost_eq(build.stat(&"armor"), 2.0, 0.001)
	_take(build, Card.Kind.PASSIVE, lederhosn, 1, Card.Rarity.HOFRAT)
	assert_eq(build.owned_passive(lederhosn).level, 3)
	assert_almost_eq(build.stat(&"armor"), 2.0 + balance.rarity_bonus[Card.Rarity.HOFRAT], 0.001)


func test_extra_jumps_count_levels_not_rarity() -> void:
	var build := PlayerBuild.new(catalog, balance)
	_take(build, Card.Kind.PASSIVE, _passive(&"haferlschuhe"), 1, Card.Rarity.HOFRAT)
	assert_eq(build.stat(&"extra_jumps"), 1.0)
	assert_gt(build.stat(&"jump_height"), 0.1, "jump height does scale with rarity")


func test_levels_stop_at_the_max() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var shovel: int = _weapon(&"schneeschaufel")
	_take(build, Card.Kind.WEAPON, shovel, 20)
	assert_eq(build.owned_weapon(shovel).level, catalog.weapons[shovel].max_level)


func test_the_deal_offers_different_items_and_respects_full_slots() -> void:
	var build := PlayerBuild.new(catalog, balance)
	build.add_start_weapon(catalog.weapons[_weapon(&"schneeschaufel")])
	for deal: int in 30:
		var cards: Array[Card] = CardDealer.deal(build, balance, rng, 3)
		assert_eq(cards.size(), 3)
		for a: int in cards.size():
			for b: int in range(a + 1, cards.size()):
				assert_false(cards[a].same_item(cards[b]), "no item twice on one menu")
	# Fill every weapon slot: no new weapon may be offered any more.
	for k: int in catalog.weapons.size():
		if not catalog.weapons[k].is_evolution and build.weapon_slots_used() < balance.weapon_slots:
			_take(build, Card.Kind.WEAPON, k)
	for deal: int in 30:
		for card: Card in CardDealer.deal(build, balance, rng, 3):
			if card.kind == Card.Kind.WEAPON:
				assert_not_null(build.owned_weapon(card.index), "only weapons already owned")


func test_evolutions_are_never_offered_as_new_weapons() -> void:
	var build := PlayerBuild.new(catalog, balance)
	for deal: int in 60:
		for card: Card in CardDealer.deal(build, balance, rng, 3):
			if card.kind == Card.Kind.WEAPON:
				assert_false(catalog.weapons[card.index].is_evolution)


func test_a_ready_evolution_is_on_the_menu_and_keeps_the_slot() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var spoon: int = _weapon(&"kochloeffel")
	_take(build, Card.Kind.WEAPON, spoon, catalog.weapons[spoon].max_level)
	_take(build, Card.Kind.WEAPON, _weapon(&"skistoecke"))
	assert_eq(build.evolutions_ready().size(), 0, "needs the passive too")
	_take(build, Card.Kind.PASSIVE, _passive(&"brettljause"))
	assert_eq(build.evolutions_ready().size(), 1)
	var cards: Array[Card] = CardDealer.deal(build, balance, rng, 3)
	assert_eq(cards[0].kind, Card.Kind.EVOLUTION)
	var fires: int = 7
	build.weapons[0].fires = fires
	build.apply(cards[0], balance)
	assert_eq(build.weapons.size(), 2)
	assert_eq(build.weapons[0].data.id, &"omas_nudelwalker")
	assert_eq(build.weapons[0].fires, fires, "same slot, same fire counter")
	assert_eq(build.evolutions_ready().size(), 0)
	for deal: int in 60:
		for card: Card in CardDealer.deal(build, balance, rng, 3):
			assert_false(card.kind == Card.Kind.WEAPON and card.index == spoon, "the evolved weapon is not offered again")
	assert_false(CardDealer.is_valid(Card.new(Card.Kind.WEAPON, spoon), build, balance))


func test_banished_items_stay_off_the_menu() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var banned: int = _passive(&"lederhosn")
	build.banished[Card.Kind.PASSIVE * 256 + banned] = true
	for deal: int in 60:
		for card: Card in CardDealer.deal(build, balance, rng, 3):
			assert_false(card.kind == Card.Kind.PASSIVE and card.index == banned)


func test_an_empty_pool_falls_back_to_gold_and_a_heal() -> void:
	var build := PlayerBuild.new(catalog, balance)
	for k: int in catalog.weapons.size():
		build.banished[Card.Kind.WEAPON * 256 + k] = true
	for k: int in catalog.passives.size():
		build.banished[Card.Kind.PASSIVE * 256 + k] = true
	var cards: Array[Card] = CardDealer.deal(build, balance, rng, 3)
	assert_eq(cards[0].kind, Card.Kind.GOLD)
	assert_eq(cards[1].kind, Card.Kind.HEAL)
	build.apply(cards[0], balance)
	assert_eq(build.gold, balance.fallback_gold)


func test_luck_makes_rare_cards_likelier() -> void:
	var rare_plain: int = 0
	var rare_lucky: int = 0
	for k: int in 2000:
		if CardDealer.roll_rarity(balance, rng, 0.0) >= Card.Rarity.NOBLE:
			rare_plain += 1
		if CardDealer.roll_rarity(balance, rng, 1.0) >= Card.Rarity.NOBLE:
			rare_lucky += 1
	assert_gt(float(rare_lucky), rare_plain * 1.5)


func test_a_chest_gives_items_and_an_evolution_first() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var orbit: int = _weapon(&"mozartkugel_orbit")
	_take(build, Card.Kind.WEAPON, orbit, catalog.weapons[orbit].max_level)
	_take(build, Card.Kind.PASSIVE, _passive(&"kraeuterlimo"))
	var taken: Array[Card] = CardDealer.open_chest(build, balance, rng, 3, true)
	assert_eq(taken.size(), 3)
	assert_eq(taken[0].kind, Card.Kind.EVOLUTION)
	assert_eq(build.weapons[0].data.id, &"kugel_karussell")


func test_the_mirror_rebuilds_the_same_stats() -> void:
	var build := PlayerBuild.new(catalog, balance)
	_take(build, Card.Kind.WEAPON, _weapon(&"skistoecke"), 3, Card.Rarity.FINE)
	_take(build, Card.Kind.PASSIVE, _passive(&"kraeuterlimo"), 2, Card.Rarity.NOBLE)
	_take(build, Card.Kind.PASSIVE, _passive(&"haferlschuhe"))
	build.weapons[0].fires = 99
	var mirror := PlayerBuild.new(catalog)
	assert_true(mirror.mirror(build.weapon_rows(), build.passive_rows(), 12, 2, 1))
	assert_eq(mirror.weapons[0].level, 3)
	assert_eq(mirror.weapons[0].fires, 99)
	assert_almost_eq(mirror.weapons[0].bonus, build.weapons[0].bonus, 0.01)
	assert_almost_eq(mirror.stat(&"move_speed"), build.stat(&"move_speed"), 0.001)
	assert_eq(mirror.stat(&"extra_jumps"), 1.0)
	assert_eq(mirror.gold, 12)
	assert_false(mirror.mirror(PackedInt32Array([200, 1, 100, 0]), PackedInt32Array(), 0, 0, 0), "unknown item")


func test_the_flow_offers_and_applies_a_pick() -> void:
	var flow := LevelUpFlow.new(balance, 3)
	var state := PlayerState.new(1, balance.player_max_hp, PlayerBuild.new(catalog, balance))
	state.add_xp(200.0, balance)
	var pending: int = state.pending_levels
	assert_gt(pending, 1)
	var states: Dictionary[int, PlayerState] = {1: state}
	flow.update(states, 0.016, false)
	assert_true(flow.is_open(1))
	assert_true(state.choosing)
	var cards: Array = flow._cards[1]
	var first: Card = cards[0]
	flow.on_choice(1, _choice(flow._seqs[1], OfferCodec.Action.PICK, 0), state, false)
	assert_eq(state.pending_levels, pending - 1)
	assert_true(flow.is_open(1), "the next level-up follows right away")
	if first.kind == Card.Kind.WEAPON:
		assert_not_null(state.build.owned_weapon(first.index))
	elif first.kind == Card.Kind.PASSIVE:
		assert_not_null(state.build.owned_passive(first.index))


func test_the_flow_rerolls_banishes_skips_and_ignores_stale_choices() -> void:
	var flow := LevelUpFlow.new(balance, 4)
	var state := PlayerState.new(1, balance.player_max_hp, PlayerBuild.new(catalog, balance))
	state.add_xp(14.0, balance)
	assert_eq(state.pending_levels, 1)
	var states: Dictionary[int, PlayerState] = {1: state}
	flow.update(states, 0.016, false)
	var seq: int = flow._seqs[1]
	flow.on_choice(1, _choice(seq + 5, OfferCodec.Action.SKIP, 0), state, false)
	assert_eq(state.pending_levels, 1, "a stale choice changes nothing")
	flow.on_choice(1, _choice(seq, OfferCodec.Action.REROLL, 0), state, false)
	assert_eq(state.build.rerolls, balance.rerolls_per_run - 1)
	assert_eq(state.pending_levels, 1, "a reroll keeps the level-up")
	seq = flow._seqs[1]
	var banish_at: int = -1
	var cards: Array = flow._cards[1]
	for k: int in cards.size():
		if (cards[k] as Card).kind == Card.Kind.WEAPON or (cards[k] as Card).kind == Card.Kind.PASSIVE:
			banish_at = k
	assert_gte(banish_at, 0)
	var banned: Card = cards[banish_at]
	flow.on_choice(1, _choice(seq, OfferCodec.Action.BANISH, banish_at), state, false)
	assert_eq(state.build.banishes, balance.banishes_per_run - 1)
	assert_true(state.build.banished.has(banned.item_key()))
	flow.on_choice(1, _choice(flow._seqs[1], OfferCodec.Action.SKIP, 0), state, false)
	assert_eq(state.pending_levels, 0)
	assert_eq(state.build.gold, balance.skip_gold)
	assert_false(flow.is_open(1))
	assert_false(state.choosing)


func test_coop_offers_pick_by_themselves_when_time_runs_out() -> void:
	var flow := LevelUpFlow.new(balance, 6)
	var state := PlayerState.new(2, balance.player_max_hp, PlayerBuild.new(catalog, balance))
	state.add_xp(14.0, balance)
	var states: Dictionary[int, PlayerState] = {2: state}
	flow.update(states, 0.016, true)
	assert_true(flow.is_open(2))
	flow.update(states, balance.card_seconds_coop + 0.1, true)
	assert_false(flow.is_open(2))
	assert_eq(state.pending_levels, 0)
	assert_eq(flow.picks, 1)


func test_choosing_players_take_no_damage() -> void:
	var state := PlayerState.new(1, 100.0, PlayerBuild.new(catalog, balance))
	state.choosing = true
	assert_false(state.hurt(50.0, balance))
	assert_eq(state.hp, 100.0)


func test_max_hp_and_regen_come_from_the_build() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var state := PlayerState.new(1, 100.0, build)
	state.hp = 50.0
	_take(build, Card.Kind.PASSIVE, _passive(&"brettljause"), 2)
	state.tick(10.0)
	assert_almost_eq(state.hp, 50.0 + 2 * 0.25 * 10.0, 0.01)


func _choice(seq: int, action: OfferCodec.Action, card: int) -> PackedByteArray:
	var choice := OfferCodec.Choice.new()
	choice.seq = seq
	choice.action = action
	choice.card = card
	return OfferCodec.encode_choice(choice)
