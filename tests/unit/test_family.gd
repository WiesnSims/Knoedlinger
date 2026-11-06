extends GutTest
## The new family (1.4 Part 2): Opa Hias, Cousine Mitzi and Steffi, their start weapons
## (Gartenschlauch, Fiakerpeitsche, Steirische Harmonika) and the Serviettenknödl and Topfenknödl.

var balance: BalanceData


func before_each() -> void:
	balance = BalanceData.new()


func _manager(count: int) -> EnemyManager:
	var manager := EnemyManager.new(balance, [load("res://data/enemies/tourist.tres")], count, 3, null, 50.0)
	manager.populate(count, PackedVector3Array([Vector3.ZERO]))
	return manager


func _place(manager: EnemyManager, points: Array[Vector2]) -> void:
	for k: int in points.size():
		manager.pos_x[k] = points[k].x
		manager.pos_z[k] = points[k].y
	manager.update(0.0001, PackedVector3Array([Vector3(45.0, 0.0, 45.0)]))


func test_the_three_are_in_the_family_each_unlocked_by_an_auftrag() -> void:
	var content: GameContent = load("res://data/content.tres")
	var catalog: UpgradeCatalog = load("res://data/catalog/catalog.tres")
	var ids: Array[StringName] = []
	for character: CharacterData in content.characters:
		ids.append(character.id)
	var unlocks: Dictionary = {}
	var quest_ids: Array[StringName] = []
	for quest: QuestData in content.quests:
		quest_ids.append(quest.id)
		if quest.unlock_kind == &"character" or quest.unlock_kind == &"weapon":
			unlocks[quest.unlock_id] = quest
	for id: StringName in [&"hias", &"mitzi", &"steffi"]:
		assert_has(ids, id)
		assert_true(unlocks.has(id), "%s is unlocked by an Auftrag" % id)
		assert_has(quest_ids, StringName("%s_40" % id))
		assert_has(quest_ids, StringName("%s_sieg" % id))
		var who: CharacterData = load("res://data/characters/%s.tres" % id)
		assert_has(catalog.weapons, who.start_weapon, "%s's start weapon is on the Speisekarte" % id)
		var weapon_quest: QuestData = unlocks.get(who.start_weapon.id)
		assert_not_null(weapon_quest, "%s's weapon is unlocked by an Auftrag" % id)
		if weapon_quest != null:
			assert_eq(weapon_quest.filter, id, "by playing %s" % id)
		assert_ne(tr(who.trait_key), who.trait_key)
	assert_eq((unlocks[&"hias"] as QuestData).filter, &"gemeindebau")
	assert_eq((unlocks[&"steffi"] as QuestData).filter, &"heuriger")
	assert_eq((unlocks[&"mitzi"] as QuestData).kind, &"overtime")


func test_the_whip_cracks_hardest_at_its_tip() -> void:
	var whip: WeaponData = load("res://data/weapons/fiakerpeitsche.tres")
	var manager: EnemyManager = _manager(2)
	_place(manager, [Vector2(0.0, 2.0), Vector2(0.0, whip.reach - 0.3)])
	assert_eq(WeaponSystem.arc_hit(whip, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), manager, 0.1), 2)
	var near: float = manager.max_hp[0] - manager.hp[0]
	var tip: float = manager.max_hp[1] - manager.hp[1]
	assert_almost_eq(tip, near * whip.tip_multiplier, 0.001)


func test_the_harmonika_squeezes_then_blasts() -> void:
	var harmonika: WeaponData = load("res://data/weapons/steirische_harmonika.tres")
	var owned := PlayerBuild.OwnedWeapon.new()
	owned.data = harmonika
	owned.level = 1
	var manager: EnemyManager = _manager(1)
	_place(manager, [Vector2(6.0, 0.0)])
	owned.mines.append(Vector3(0.0, 0.0, harmonika.pull_seconds))
	WeaponSystem._tick_pulls(owned, manager, harmonika.pull_seconds * 0.5, 1.0, 0.2)
	assert_lt(manager.pos_x[0], 6.0, "drawn in")
	assert_eq(manager.hp[0], manager.max_hp[0], "no damage while it squeezes")
	WeaponSystem._tick_pulls(owned, manager, harmonika.pull_seconds, 1.0, 0.2)
	assert_lt(manager.hp[0], manager.max_hp[0], "then the ring goes off")
	assert_gt(manager.kb_x[0], 0.0, "and pushes out")
	assert_true(owned.mines.is_empty())


func test_the_topfenknodl_comes_back_quick_and_hits_softer() -> void:
	var topfen: KnodlSortData = load("res://data/knodl/topfenknoedl.tres")
	var knodl := Knodl.new()
	add_child_autofree(knodl)
	knodl.setup(1, balance, topfen, null, true)
	assert_almost_eq(knodl.full_cooldown(), balance.knodl_cooldown * 0.5, 0.001)
	assert_lt(topfen.contact_damage_mult, 1.0)
	assert_lt(topfen.reel_time_mult * balance.knodl_reel_time, 0.6)
	assert_true(topfen.sweet, "Wespen like it")


func test_the_serviettenknodl_sweeps_a_wide_strip_and_turns_slowly() -> void:
	var knodl := Knodl.new()
	add_child_autofree(knodl)
	knodl.setup(1, balance, load("res://data/knodl/serviettenknoedl.tres"), null, true)
	knodl.heading = Vector3(0.0, 0.0, 1.0)
	var r: float = knodl.radius
	assert_true(knodl._in_strip(r * 1.6, 0.0, r, r * 2.0), "beside it, inside the strip")
	assert_false(knodl._in_strip(0.0, r * 1.6, r, r * 2.0), "ahead of it, beyond the roll")
	var ball := Knodl.new()
	add_child_autofree(ball)
	ball.setup(2, balance, load("res://data/knodl/semmelknoedl.tres"), null, true)
	assert_false(ball._in_strip(r * 1.6, 0.0, r, r), "a round Knödl has no strip")
	var turned: Vector3 = Knodl._turned(Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), 0.1)
	assert_almost_eq(turned.angle_to(Vector3(0.0, 0.0, 1.0)), 0.1, 0.001, "one step at a time")
	var back: Vector3 = Knodl._turned(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), 0.1)
	assert_almost_eq(back.z, 1.0, 0.001, "rolling backwards needs no turn")


func test_mitzi_trots_after_running_straight_and_a_sharp_turn_stops_it() -> void:
	var mitzi := Player.new()
	mitzi.setup(2, false, balance, load("res://data/characters/mitzi.tres"), null)
	add_child_autofree(mitzi)
	var step: float = 1.0 / 60.0
	mitzi.motion_velocity = Vector3(0.0, 0.0, mitzi.run_speed())
	for k: int in roundi(balance.trot_seconds / step) + 2:
		mitzi._update_trait_clocks(step)
	assert_almost_eq(mitzi.trot_bonus(), 0.2, 0.001)
	mitzi.motion_velocity = Vector3(mitzi.run_speed(), 0.0, 0.0)
	mitzi._update_trait_clocks(step)
	assert_eq(mitzi.trot_bonus(), 0.0, "a sharp turn resets the Trab")
	var other := Player.new()
	other.setup(3, false, balance, load("res://data/characters/ferdl.tres"), null)
	add_child_autofree(other)
	other.straight_time = 10.0
	assert_eq(other.trot_bonus(), 0.0, "only Mitzi trots")


func test_opa_hias_counts_standing_still() -> void:
	var hias := Player.new()
	hias.setup(2, false, balance, load("res://data/characters/hias.tres"), null)
	add_child_autofree(hias)
	for k: int in 70:
		hias._update_trait_clocks(1.0 / 60.0)
	assert_gte(hias.still_time, balance.idle_seconds)
	hias.motion_velocity = Vector3(3.0, 0.0, 0.0)
	hias._update_trait_clocks(1.0 / 60.0)
	assert_eq(hias.still_time, 0.0)
	var build := PlayerBuild.new(load("res://data/catalog/catalog.tres"))
	var before: float = build.stat(&"rate")
	build.trait_rate = 0.25
	build.recompute()
	assert_almost_eq(build.stat(&"rate") - before, 0.25, 0.001)
