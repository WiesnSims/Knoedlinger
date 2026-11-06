extends GutTest
## 1.4 Part 6 (changes): gold and chests (6.6), the item effects (6.7), the build view (6.8).

var balance: BalanceData
var content: GameContent


func before_each() -> void:
	balance = load("res://data/balance.tres")
	content = GameContent.load_default()


func test_chest_prices_grow_per_bought_chest() -> void:
	var prices: Array[int] = []
	for bought: int in 15:
		prices.append(Formulas.chest_price(balance.map_chest_price, bought, balance))
	assert_eq(prices[0], balance.map_chest_price)
	for k: int in range(1, prices.size()):
		assert_gt(prices[k], prices[k - 1], "each bought chest makes the next one dearer")
	var total: int = 0
	for price: int in prices:
		total += price
	assert_between(total, 1200, 2200, "about 1,650 gold for 15 chests (DECISIONS 6.6)")


func test_coins_are_worth_more_as_the_clock_runs() -> void:
	assert_eq(Formulas.coin_value(0.0, balance), 1)
	assert_between(Formulas.coin_value(720.0, balance), 4, 6, "~5 gold a coin at 12:00")
	assert_gte(Formulas.coin_value(-5.0, balance), 1)


func test_the_world_state_carries_chests_bought() -> void:
	var frame := WorldStateCodec.Frame.new()
	var e := WorldStateCodec.Entry.new()
	e.peer_id = 7
	e.chests_opened = 5
	e.chests_bought = 3
	frame.entries.append(e)
	var back: WorldStateCodec.Frame = WorldStateCodec.decode(WorldStateCodec.encode(frame))
	assert_eq(back.entries[0].chests_opened, 5)
	assert_eq(back.entries[0].chests_bought, 3, "free chests (Zweitschlüssel) do not raise the price")


func test_fassl_is_a_loot_kind_with_room_for_coins() -> void:
	var loot := LootField.new()
	add_child_autofree(loot)
	loot.setup(Heightfield.new(50.0, 11))
	var id: int = loot.add(LootField.Kind.FASSL, 3.0, 4.0, 0)
	assert_gte(id, 0)
	assert_eq(loot.nearest(LootField.Kind.FASSL, 0.0, 0.0), loot.slot_of(id))
	assert_lt(balance.coin_loot_cap, loot.capacity - 32, "boss chests and Stempel always find a slot")


func _item(id: StringName) -> int:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	for k: int in catalog.items.size():
		if catalog.items[k].id == id:
			return k
	return -1


func test_proc_chances_stack_per_copy_and_with_the_lantern() -> void:
	assert_almost_eq(ItemProcs.stacked_chance(0.1, 1), 0.1, 0.0001)
	assert_almost_eq(ItemProcs.stacked_chance(0.1, 2), 0.19, 0.0001, "1 - (1 - p)^n")
	assert_almost_eq(ItemProcs.stacked_chance(0.1, 1, 0.5), 0.15, 0.0001, "Stallaterne: +50 % on every chance")
	assert_eq(ItemProcs.stacked_chance(0.9, 3, 2.0), 1.0, "never above 1")
	var effect := ItemEffect.new()
	effect.action = ItemEffect.Action.DAMAGE_PER_KILL
	effect.value = 0.3
	effect.cap = 0.5
	assert_almost_eq(ItemProcs.stacked_value(effect, 2), 0.5, 0.0001, "capped")


func test_every_new_item_is_known_and_says_what_it_does() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var with_rules: int = 0
	for item: ItemData in catalog.items:
		var lines: PackedStringArray = ItemText.describe(item, 1, balance)
		assert_false(lines.is_empty(), "%s has an effect text" % item.id)
		for line: String in lines:
			assert_false(line.contains("IFX_") or line.contains("{"), "%s: %s" % [item.id, line])
		if not item.effects.is_empty():
			with_rules += 1
		# Hofratswürdig items are build-defining: one copy (Marterl-Kerze keeps its two revives).
		if item.rarity == 3 and item.evolves_from == null and item.id != &"marterl_kerze":
			assert_eq(item.max_stacks, 1, "%s: one copy" % item.id)
		assert_true(Profile.unlocking_quest(&"item", item.id) != null or item.id in [&"omas_rezept", &"haferlschuhe",
				&"gluecksschwein", &"lebkuchenherz", &"kirtagsbrezn", &"zuckerwatte", &"schiessbudenrose", &"goldhaube",
				&"doppler", &"edelweiss", &"rosenkranz", &"trachtenjanker", &"sauerkraut", &"kracherl", &"zirbenschnaps",
				&"holundersaft", &"spitzwegerich", &"feldstecher", &"sonntagsgwand", &"wetterhahn", &"kuckucksuhr",
				&"maibaumspitz", &"broeselbutter", &"powidl", &"bergab_gesetz", &"schweizerkracher", &"kirchenglocke",
				&"riesenknodl", &"doppelportion", &"spielhahnfeder", &"gleitschirm", &"zweitschluessel", &"sparbuch",
				&"marterl_kerze"], "%s: new items wait behind an Auftrag" % item.id)
	assert_gte(catalog.items.size(), 60)
	assert_gte(with_rules, 30)
	var gfrorns: ItemData = catalog.items[_item(&"gfrorns")]
	assert_eq(ItemText.effect_line(gfrorns.effects[0], 1, balance), "10 % beim Treffer: 1,5 s eingfroren")
	assert_true(ItemText.effect_line(gfrorns.effects[0], 2, balance).begins_with("19 %"), "stacked chance shown")


func test_hits_are_logged_for_procs_and_bonuses_apply_per_target() -> void:
	var tourist: EnemyTypeData = load("res://data/enemies/tourist.tres")
	var types: Array[EnemyTypeData] = [tourist]
	var manager := EnemyManager.new(balance, types, 4, 3, null, 50.0)
	manager.populate(2, PackedVector3Array([Vector3.ZERO]))
	manager.proc_source.resize(3)
	manager.source_bonus.resize(3)
	manager.proc_source[2] = 1
	manager.source_bonus[2] = Vector4(1.0, 0.0, 0.0, 0.0)
	manager.source = 2
	var full: float = manager.hp[0]
	manager.damage(0, 1.0)
	assert_almost_eq(manager.hp[0], full - 2.0, 0.001, "+100 % against a healthy enemy")
	manager.damage(0, 1.0, 0.0, 0.0, false)
	assert_eq(manager.hit_slot.size(), 1, "an unflashed tick (burn) is no hit")
	manager.source = 1
	manager.damage(1, 1.0)
	assert_eq(manager.hit_slot.size(), 1, "sources without proc items log nothing")
	manager.source = -1


func test_the_shield_takes_hits_first_and_comes_from_overhealing() -> void:
	var state := PlayerState.new(1, 100.0)
	state.shield_share = 0.5
	state.heal(80.0)
	assert_almost_eq(state.shield, 50.0, 0.001, "overheal up to half the max HP")
	state.hurt(30.0, balance)
	assert_almost_eq(state.shield, 20.0, 0.001)
	assert_almost_eq(state.hp, 100.0, 0.001)


func test_the_anvil_adds_a_second_mod_and_the_backpack_a_piece() -> void:
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var build := PlayerBuild.new(catalog, balance)
	var card := Card.new()
	card.kind = Card.Kind.WEAPON
	card.index = 0
	build.apply(card, balance)
	build.add_item(_item(&"amboss"))
	card.level = 2
	card.mod = 0
	card.value = 0.2
	build.apply(card, balance)
	var gained: int = 0
	for value: float in build.weapons[0].mods:
		if value > 0.0:
			gained += 1
	assert_eq(gained, 2, "the card's mod and the anvil's")
	var before: int = Formulas.weapon_amount(build.weapons[0].data, build.weapons[0].mods, build.weapons[0].extra_amount)
	build.add_item(_item(&"rucksack"))
	assert_eq(Formulas.weapon_amount(build.weapons[0].data, build.weapons[0].mods, build.weapons[0].extra_amount), before + 1)
