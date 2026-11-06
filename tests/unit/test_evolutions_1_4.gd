extends GutTest
## 1.4 Part 3: the evolutions for every family start weapon, the Krapfen-Kanone (lobbed shots that
## hop and splash), the Seniorenteller (XP) and the Gummistiefel (knockback, sure footing), and the
## rule that everything new is locked behind an Auftrag.

const NEW_WEAPONS: Array[StringName] = [&"krapfen_kanone", &"schneepflug", &"slalom_gewitter", &"zahlen_bitte",
	&"almabtrieb", &"hochwasser", &"viererzug", &"zeltfest", &"faschingsdienstag"]
const NEW_PASSIVES: Array[StringName] = [&"seniorenteller", &"gummistiefel"]

var balance: BalanceData
var catalog: UpgradeCatalog


func before_each() -> void:
	balance = BalanceData.new()
	catalog = load("res://data/catalog/catalog.tres")


func _manager(count: int) -> EnemyManager:
	var manager := EnemyManager.new(balance, [load("res://data/enemies/tourist.tres")], count, 3, null, 50.0)
	manager.populate(count, PackedVector3Array([Vector3.ZERO]))
	return manager


func _place(manager: EnemyManager, points: Array[Vector2]) -> void:
	for k: int in points.size():
		manager.pos_x[k] = points[k].x
		manager.pos_z[k] = points[k].y
	manager.update(0.0001, PackedVector3Array([Vector3(45.0, 0.0, 45.0)]))


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


func test_every_family_start_weapon_evolves() -> void:
	var content: GameContent = load("res://data/content.tres")
	for character: CharacterData in content.characters:
		var weapon: WeaponData = character.start_weapon
		assert_not_null(weapon.evolution, "%s evolves" % weapon.id)
		assert_not_null(weapon.evolves_with, "%s has a partner stat" % weapon.id)
		if weapon.evolution != null:
			assert_true(weapon.evolution.is_evolution)
			assert_has(catalog.weapons, weapon.evolution)
		if weapon.evolves_with != null:
			assert_has(catalog.passives, weapon.evolves_with)


func test_new_content_is_in_the_catalog_with_text_and_an_icon() -> void:
	for id: StringName in NEW_WEAPONS:
		var k: int = _weapon(id)
		assert_gt(k, -1, "%s is in the catalog" % id)
		if k < 0:
			continue
		var weapon: WeaponData = catalog.weapons[k]
		assert_ne(tr(weapon.name_key), weapon.name_key)
		assert_ne(tr(weapon.desc_key), weapon.desc_key)
		assert_not_null(weapon.icon)
	for id: StringName in NEW_PASSIVES:
		var k: int = _passive(id)
		assert_gt(k, -1, "%s is in the catalog" % id)
		if k >= 0:
			assert_ne(tr(catalog.passives[k].name_key), catalog.passives[k].name_key)
			assert_not_null(catalog.passives[k].icon)
	for key: String in ["STAT_XP_GAIN", "STAT_KNOCKBACK", "STAT_SURE_FOOTING"]:
		assert_ne(tr(key), key)


func test_everything_new_is_locked_behind_an_auftrag() -> void:
	var content: GameContent = load("res://data/content.tres")
	var unlocks: Dictionary = {}
	for quest: QuestData in content.quests:
		unlocks[quest.unlock_id] = quest
		assert_ne(tr(quest.title_key), quest.title_key, "%s has a title" % quest.id)
	for id: StringName in NEW_WEAPONS + NEW_PASSIVES:
		assert_true(unlocks.has(id), "%s is unlocked by an Auftrag" % id)


func test_a_locked_evolution_is_never_ready() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var shovel: int = _weapon(&"schneeschaufel")
	build.apply(Card.new(Card.Kind.WEAPON, shovel, Card.Rarity.COMMON, 1), balance)
	build.apply(Card.new(Card.Kind.PASSIVE, _passive(&"bergkas"), Card.Rarity.COMMON, 1), balance)
	build.owned_weapon(shovel).level = build.evolution_level
	assert_eq(build.evolutions_ready(), [Vector2i(0, _weapon(&"schneepflug"))])
	build.locked[Card.Kind.WEAPON * 256 + _weapon(&"schneepflug")] = true
	assert_eq(build.evolutions_ready(), [] as Array[Vector2i])


func test_viererzug_lashes_all_four_ways() -> void:
	var weapon: WeaponData = load("res://data/weapons/viererzug.tres")
	var manager: EnemyManager = _manager(4)
	_place(manager, [Vector2(0.0, 4.0), Vector2(4.0, 0.0), Vector2(0.0, -4.0), Vector2(-4.0, 0.0)])
	for k: int in 4:
		WeaponSystem.arc_hit(weapon, Vector3.ZERO, Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, WeaponSystem.arc_turn(k, 4)),
				manager, 0.1)
	for k: int in 4:
		assert_lt(manager.hp[k], manager.max_hp[k], "enemy %d is hit" % k)
	assert_almost_eq(WeaponSystem.arc_turn(1, 2), PI, 0.0001, "two swings: front and back")


func test_the_krapfen_hops_and_splashes_where_it_lands() -> void:
	var weapon: WeaponData = load("res://data/weapons/krapfen_kanone.tres")
	var pool := ProjectilePool.new()
	add_child_autofree(pool)
	pool.setup(balance, 8)
	var manager: EnemyManager = _manager(2)
	var every: float = weapon.projectile_lifetime / weapon.hops
	var step: float = weapon.projectile_speed * every
	# One under the first landing, one half a hop on (it flies over that one).
	_place(manager, [Vector2(0.0, step), Vector2(0.0, step * 1.5)])
	WeaponSystem.fire_shots(weapon, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 1, 1.0, 1.0, pool)
	assert_eq(pool.active_count, 1)
	var frames: int = ceili(every * 1.25 * 60.0)
	for f: int in frames:
		pool.update(1.0 / 60.0, manager)
	assert_lt(manager.hp[0], manager.max_hp[0], "splashed where it landed")
	assert_eq(manager.hp[1], manager.max_hp[1], "nothing is hit in the air")
	assert_lt(manager.slow_mult[0], 1.0, "jam slows")
	for f: int in ceili(weapon.projectile_lifetime * 2.0 * 60.0):
		pool.update(1.0 / 60.0, manager)
	assert_eq(pool.active_count, 0, "gone after its last landing")
	assert_eq(pool.hits, weapon.hops, "landed every hop")


func test_seniorenteller_gives_more_xp() -> void:
	var build := PlayerBuild.new(catalog, balance)
	var state := PlayerState.new(1, 100.0, build)
	state.add_xp(10.0, balance)
	var plain: float = state.xp
	build.apply(Card.new(Card.Kind.PASSIVE, _passive(&"seniorenteller"), Card.Rarity.COMMON, 1), balance)
	assert_gt(build.stat(&"xp_gain"), 0.0)
	state.add_xp(10.0, balance)
	assert_almost_eq(state.xp - plain, 10.0 * (1.0 + build.stat(&"xp_gain")), 0.001)


func test_gummistiefel_push_harder() -> void:
	var build := PlayerBuild.new(catalog, balance)
	build.apply(Card.new(Card.Kind.PASSIVE, _passive(&"gummistiefel"), Card.Rarity.COMMON, 1), balance)
	assert_gt(build.stat(&"knockback"), 0.0)
	assert_gt(build.stat(&"sure_footing"), 0.0)
	var weapon: WeaponData = load("res://data/weapons/kuhglocke.tres")
	var manager: EnemyManager = _manager(1)
	_place(manager, [Vector2(3.0, 0.0)])
	WeaponSystem.ring_hit(weapon, Vector3.ZERO, manager, 0.1, weapon.reach)
	var plain: float = manager.kb_x[0]
	manager = _manager(1)
	_place(manager, [Vector2(3.0, 0.0)])
	WeaponSystem.knock = 1.0 + build.stat(&"knockback")
	WeaponSystem.ring_hit(weapon, Vector3.ZERO, manager, 0.1, weapon.reach)
	WeaponSystem.knock = 1.0
	assert_almost_eq(manager.kb_x[0], plain * (1.0 + build.stat(&"knockback")), 0.01)
