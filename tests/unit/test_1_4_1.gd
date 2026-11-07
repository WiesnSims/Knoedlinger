extends GutTest
## 1.4.1 (patch): the Speisekarte never picks by itself (B3), a kept big Knödl hits hard (A4), ...

var balance: BalanceData
var catalog: UpgradeCatalog


func before_each() -> void:
	balance = BalanceData.new()
	catalog = load("res://data/catalog/catalog.tres")


# --- B3: the Speisekarte picks only on purpose -------------------------------------------------------

func _menu() -> Speisekarte:
	var menu := Speisekarte.new()
	menu.catalog = catalog
	menu.balance = balance
	add_child_autofree(menu)
	var offer := OfferCodec.Offer.new()
	offer.seq = 3
	offer.cards = [Card.new(Card.Kind.GOLD, 0, 0, 1), Card.new(Card.Kind.HEAL, 0, 0, 1)]
	menu.show_offer(offer, null)
	return menu


func _key(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	return key


func test_space_and_enter_never_pick_a_card() -> void:
	var menu: Speisekarte = _menu()
	var answers: Array = []
	menu.answered.connect(func(data: PackedByteArray) -> void: answers.append(data))
	menu._opened_ms -= 2000
	menu._cards[0].grab_focus()
	for keycode: Key in [KEY_SPACE, KEY_ENTER]:
		menu._input(_key(keycode))
	assert_eq(answers.size(), 0, "the jump key does not take the focused row")
	assert_true(menu.is_open())


func test_nothing_picks_right_after_opening() -> void:
	var menu: Speisekarte = _menu()
	var answers: Array = []
	menu.answered.connect(func(data: PackedByteArray) -> void: answers.append(data))
	menu._input(_key(KEY_1))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._input(click)
	assert_eq(answers.size(), 0, "a press in the first half second is swallowed")
	menu._opened_ms -= roundi(Speisekarte.PICK_GUARD * 1000.0) + 50
	menu._input(_key(KEY_1))
	assert_eq(answers.size(), 1, "then 1 takes the first card")


# --- A4: a kept big Knödl hits hard ------------------------------------------------------------------

func test_a_knodl_past_size_l_hits_more_than_linearly() -> void:
	var big: float = Formulas.knodl_radius(balance.wirtshaus_tier_mass[2], balance)
	assert_almost_eq(Formulas.knodl_hit_radius(big * 0.8, balance), big * 0.8, 0.0001, "small ones as before")
	var xl: float = Formulas.knodl_radius(balance.wirtshaus_tier_mass[3], balance)
	var ratio: float = Formulas.knodl_contact_damage(10.0, xl, balance) / Formulas.knodl_contact_damage(10.0, big, balance)
	assert_gt(ratio, xl / big * 1.3, "XL hits clearly harder than its size alone")
	assert_almost_eq(ratio, pow(xl / big, balance.knodl_big_exponent), 0.001)


func test_elites_take_double_and_a_boss_hit_is_capped() -> void:
	assert_almost_eq(Formulas.knodl_heavy_damage(10.0, false, 500.0, balance), 10.0 * balance.knodl_elite_mult, 0.001)
	assert_almost_eq(Formulas.knodl_heavy_damage(10.0, true, 5000.0, balance), 10.0 * balance.knodl_boss_mult, 0.001)
	assert_almost_eq(Formulas.knodl_heavy_damage(1000.0, true, 5000.0, balance), 5000.0 * balance.knodl_boss_hit_cap, 0.001,
			"one pass never takes more than the cap")


# --- A2 / A3: chests for everyone, hearts when hurt -----------------------------------------------------

func test_hearts_drop_only_when_hurt_and_most_when_low() -> void:
	assert_eq(Formulas.heart_chance(100.0, 100.0, balance), 0.0, "none at full HP")
	var scratched: float = Formulas.heart_chance(90.0, 100.0, balance)
	assert_gt(scratched, 0.0)
	assert_lt(scratched, balance.heart_drop_chance * 0.5)
	assert_almost_eq(Formulas.heart_chance(100.0 * balance.heart_full_below, 100.0, balance), balance.heart_drop_chance, 0.0001)
	assert_almost_eq(Formulas.heart_chance(5.0, 100.0, balance), balance.heart_drop_chance, 0.0001, "capped below")


func test_a_chest_opened_by_one_player_travels_as_its_own_event() -> void:
	var queue := RunEventCodec.Queue.new()
	queue.opened(812, 1234567)
	queue.taken(813, 2)
	var back: Array = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(back.size(), 2)
	assert_eq(back[0].kind, RunEventCodec.Kind.OPENED)
	assert_eq(back[0].id, 812)
	assert_eq(back[0].b, 1234567)
	assert_eq(back[1].kind, RunEventCodec.Kind.TAKEN)


func test_a_chest_the_local_player_opened_is_hidden_only_here() -> void:
	var field := LootField.new()
	add_child_autofree(field)
	field.setup(null)
	var id: int = field.add(LootField.Kind.CHEST, 3.0, 4.0, 20)
	field.hide_opened(id)
	assert_eq(field.nearest(LootField.Kind.CHEST, 0.0, 0.0), -1, "not offered to the local player")
	assert_true(field.has(id), "still there for the others")
