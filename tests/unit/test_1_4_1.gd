extends GutTest
## 1.4.1 (patch): the Speisekarte never picks by itself (B3), more chests and hearts (A2, A3), a kept big Knödl
## hits hard (A4), the old weapons (A1) and the Krapfen aiming into the crowd (C1).

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


# --- A1 / C1: the old weapons and the Krapfen's aim -----------------------------------------------------

func _crowd(points: Array[Vector2]) -> EnemyManager:
	var manager := EnemyManager.new(balance, [load("res://data/enemies/tourist.tres")], points.size(), 3, null, 50.0)
	manager.populate(points.size(), PackedVector3Array([Vector3.ZERO]))
	for k: int in points.size():
		manager.pos_x[k] = points[k].x
		manager.pos_z[k] = points[k].y
		manager.hp[k] = 10000.0
		manager.max_hp[k] = 10000.0
	manager.update(0.0001, PackedVector3Array([Vector3(45.0, 0.0, 45.0)]))
	return manager


func _hurt(manager: EnemyManager) -> int:
	var count: int = 0
	for k: int in manager.capacity:
		if manager.hp[k] < manager.max_hp[k]:
			count += 1
	return count


func _owned(path: String) -> PlayerBuild.OwnedWeapon:
	var owned := PlayerBuild.OwnedWeapon.new()
	owned.data = load(path)
	owned.level = 1
	return owned


func test_the_krampusrute_forks_but_hits_at_most_twice_its_jumps() -> void:
	var points: Array[Vector2] = []
	for k: int in 20:
		points.append(Vector2(2.0 + (k % 5) * 1.5, (k / 5) * 1.5 - 2.0))
	var manager: EnemyManager = _crowd(points)
	var rute: PlayerBuild.OwnedWeapon = _owned("res://data/weapons/krampusrute.tres")
	WeaponSystem.chain_hit(rute, Vector3.ZERO, manager, 10.0, 1.0, 4, 0.0)
	assert_eq(_hurt(manager), 7, "4 jumps forked: 1 + 2 + 4 enemies, each once")
	assert_eq(rute.impacts.size(), 14, "one (from, to) pair per bolt")


func test_the_wuerstel_splashes_mustard_around_each_hit() -> void:
	var manager: EnemyManager = _crowd([Vector2(3.0, 0.0), Vector2(3.6, 0.4), Vector2(30.0, 0.0)])
	var wurst: PlayerBuild.OwnedWeapon = _owned("res://data/weapons/wuerstel.tres")
	WeaponSystem.chain_hit(wurst, Vector3.ZERO, manager, 10.0, 1.0, 1, 0.0)
	assert_almost_eq(manager.max_hp[0] - manager.hp[0], 10.0, 0.01, "the sausage")
	assert_almost_eq(manager.max_hp[1] - manager.hp[1], 10.0 * wurst.data.chain_splash_share, 0.01, "the Senf next to it")
	assert_eq(manager.hp[2], manager.max_hp[2], "nobody far away")


func test_a_full_tray_stops_hitting_until_it_turns() -> void:
	var points: Array[Vector2] = []
	for k: int in 30:
		points.append(Vector2(0.0, 1.0 + k * 0.3))
	var manager: EnemyManager = _crowd(points)
	var tray: WeaponData = load("res://data/weapons/tablett.tres")
	var pool := ProjectilePool.new()
	add_child_autofree(pool)
	pool.setup(balance, 64)
	pool.fire_shot(0.0, 0.0, 0.0, tray.projectile_speed, tray.projectile_lifetime, 5.0, tray.projectile_radius, tray.pierce,
			0.0, true, tray)
	for step: int in 30:
		pool.update(1.0 / 60.0, manager)
	assert_eq(pool.hits, tray.leg_hits, "the way out stops at a full tray")


func test_the_krapfen_lands_in_the_crowd_not_on_the_nearest() -> void:
	var points: Array[Vector2] = [Vector2(-3.0, 0.0)]
	for k: int in 8:
		points.append(Vector2(6.0 + (k % 3) * 0.5, (k / 3) * 0.5))
	var manager: EnemyManager = _crowd(points)
	var krapfen: WeaponData = load("res://data/weapons/krapfen_kanone.tres")
	var aim: Vector3 = WeaponSystem.aim_into_crowd(krapfen, Vector3.ZERO, Vector3.FORWARD, manager, 1.0, 0.0)
	assert_gt(aim.x, 0.9, "toward the bunch, away from the lone one")


# --- C6: a big hit pushes the player who was hit ------------------------------------------------------

func test_a_knockback_travels_to_the_player_it_hit() -> void:
	var queue := RunEventCodec.Queue.new()
	queue.knock(987654, 12.5, -15.0)
	var back: Array = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(back.size(), 1)
	assert_eq(back[0].kind, RunEventCodec.Kind.KNOCK)
	assert_eq(back[0].b, 987654)
	assert_almost_eq(back[0].x, 12.5, 0.001)
	assert_almost_eq(back[0].z, -15.0, 0.001)


# --- C4 / C5: notes in the main menu --------------------------------------------------------------------

func test_the_patch_list_is_new_after_an_update_until_opened() -> void:
	Profile.reset_memory()
	assert_false(Profile.patches_new(), "a fresh profile has nothing new to read")
	(Profile.data["notes"] as Dictionary)["patches_seen"] = "1.4.0"
	assert_true(Profile.patches_new(), "an older save sees Neu!")
	Profile.mark_patches_seen()
	assert_false(Profile.patches_new())
	var old_save: Dictionary = Profile._merged({"v": 1, "schilling": 5})
	assert_eq(str((old_save["notes"] as Dictionary)["patches_seen"]), "", "a save from before 1.4.1 has not seen this list")


func test_the_save_note_waits_for_a_knodlinger_then_every_ten_auftraege() -> void:
	Profile.reset_memory()
	assert_false(Profile.save_hint_due(), "nothing unlocked yet")
	var unlock: QuestData = null
	for quest: QuestData in Profile.content.quests:
		if quest.unlock_kind == &"character":
			unlock = quest
			break
	assert_not_null(unlock)
	(Profile.data["quests"] as Dictionary)[String(unlock.id)] = true
	assert_true(Profile.save_hint_due(), "the first Knödlinger unlocked")
	Profile.answer_save_hint(false)
	assert_false(Profile.save_hint_due(), "copied: quiet for a while")
	for k: int in Profile.SAVE_HINT_EVERY:
		(Profile.data["quests"] as Dictionary)["test_%d" % k] = true
	assert_true(Profile.save_hint_due(), "ten Aufträge later")
	Profile.answer_save_hint(true)
	for k: int in 30:
		(Profile.data["quests"] as Dictionary)["more_%d" % k] = true
	assert_false(Profile.save_hint_due(), "Nimma erinnern is for good")
	Profile.reset_memory()
