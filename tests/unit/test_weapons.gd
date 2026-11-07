extends GutTest
## Weapon formulas and patterns, Bröselfresser, the wave timeline, Wirtshaus tiers and armor.

var balance: BalanceData
var types: Array[EnemyTypeData] = []


func before_each() -> void:
	balance = BalanceData.new()
	var tourist: EnemyTypeData = load("res://data/enemies/tourist.tres")
	types = [tourist]


func _manager(count: int, p_types: Array[EnemyTypeData] = types) -> EnemyManager:
	var manager := EnemyManager.new(balance, p_types, count, 3, null, 50.0)
	manager.populate(count, PackedVector3Array([Vector3.ZERO]))
	return manager


## Puts enemies where wanted and rebuilds the grid (with the players far away).
func _place(manager: EnemyManager, points: Array[Vector2]) -> void:
	for k: int in points.size():
		manager.pos_x[k] = points[k].x
		manager.pos_z[k] = points[k].y
	manager.update(0.0001, PackedVector3Array([Vector3(45.0, 0.0, 45.0)]))


func test_weapon_numbers_grow_with_mods_and_stats() -> void:
	var shovel: WeaponData = load("res://data/weapons/schneeschaufel.tres")
	var none := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	assert_almost_eq(Formulas.weapon_damage(shovel, none, 0.0), shovel.damage, 0.001)
	var mods := PackedFloat32Array([0.6, 1.0, 0.25, 0.1, 5.0])
	assert_almost_eq(Formulas.weapon_damage(shovel, mods, 0.0), shovel.damage * 1.6, 0.001)
	assert_almost_eq(Formulas.weapon_damage(shovel, none, 0.5), shovel.damage * 1.5, 0.001)
	assert_almost_eq(Formulas.weapon_cooldown(shovel, mods, 0.0, balance), shovel.cooldown / 2.0, 0.001, "rate +100 % = twice as often")
	assert_almost_eq(Formulas.weapon_cooldown(shovel, none, 5.0, balance), shovel.cooldown * 0.4, 0.001, "the stat takes at most 60 %")
	assert_almost_eq(Formulas.weapon_cooldown(shovel, PackedFloat32Array([0.0, 999.0, 0.0, 0.0, 0.0]), 0.0, balance),
			balance.weapon_min_cooldown, 0.001)
	assert_almost_eq(Formulas.weapon_area(shovel, mods, 0.2), 1.25 * 1.2, 0.001)
	assert_almost_eq(Formulas.weapon_crit(shovel, mods, 0.05), shovel.crit_chance + 0.15, 0.001)
	assert_eq(Formulas.weapon_amount(shovel, none), 1)
	assert_eq(Formulas.weapon_amount(shovel, mods), shovel.max_amount, "capped")


func test_armor_reduces_hits_but_never_to_nothing() -> void:
	assert_almost_eq(Formulas.hit_damage(6.0, 0.0, balance), 6.0, 0.001)
	assert_almost_eq(Formulas.hit_damage(6.0, balance.armor_half, balance), 3.0, 0.001, "half at armor_half")
	assert_lt(Formulas.hit_damage(6.0, 20.0, balance), Formulas.hit_damage(6.0, 10.0, balance))
	assert_gt(Formulas.hit_damage(5.0, balance.armor_half * 0.8, balance), 2.5, "a few points no longer shrug off fodder")
	assert_eq(Formulas.hit_damage(5.0, 1000.0, balance), balance.min_hit_damage)
	assert_eq(Formulas.hit_damage(0.0, 1.0, balance), 0.0)


func test_wirtshaus_tiers_follow_the_mass() -> void:
	var tiers: PackedFloat32Array = balance.wirtshaus_tier_mass
	assert_eq(Formulas.wirtshaus_tier(tiers[0] - 1.0, balance), -1)
	assert_eq(Formulas.wirtshaus_tier(tiers[0], balance), 0)
	assert_eq(Formulas.wirtshaus_tier(tiers[2] + 1.0, balance), 2)
	assert_eq(Formulas.wirtshaus_tier(tiers[3] * 10.0, balance), 3)


func test_the_cowbell_rings_all_around() -> void:
	var bell: WeaponData = load("res://data/weapons/kuhglocke.tres")
	var manager: EnemyManager = _manager(3)
	_place(manager, [Vector2(3.0, 0.0), Vector2(-2.0, -2.0), Vector2(20.0, 0.0)])
	var hit: int = WeaponSystem.ring_hit(bell, Vector3.ZERO, manager, 0.5, bell.reach)
	assert_eq(hit, 2)
	assert_gt(manager.kb_x[0], 0.0, "pushed outward")
	assert_lt(manager.kb_x[1], 0.0)
	assert_eq(manager.hp[2], manager.max_hp[2])


func test_orbit_pieces_hit_once_per_interval() -> void:
	var orbit: WeaponData = load("res://data/weapons/mozartkugel_orbit.tres")
	var owned := PlayerBuild.OwnedWeapon.new()
	owned.data = orbit
	owned.level = 1
	var manager: EnemyManager = _manager(1)
	var at: Vector2 = Formulas.orbit_offset(orbit, 0, 2, 0.0, 1.0, 0.0)
	_place(manager, [at])
	var rng := RandomNumberGenerator.new()
	assert_eq(WeaponSystem.orbit_hit(owned, Vector3.ZERO, manager, 0.0, 1.0, 0.1, 0.0, 0.0, rng), 1)
	assert_eq(WeaponSystem.orbit_hit(owned, Vector3.ZERO, manager, 0.01, 1.0, 0.1, 0.0, 0.0, rng), 0, "too soon")
	var later: float = orbit.hit_interval + 0.01
	# Put the enemy where piece 0 is then.
	_place(manager, [Formulas.orbit_offset(orbit, 0, 2, later, 1.0, 0.0)])
	assert_eq(WeaponSystem.orbit_hit(owned, Vector3.ZERO, manager, later, 1.0, 0.1, 0.0, 0.0, rng), 1)


func test_orbit_offsets_spread_evenly_and_spin_with_move_speed() -> void:
	var karussell: WeaponData = load("res://data/weapons/kugel_karussell.tres")
	var a: Vector2 = Formulas.orbit_offset(karussell, 0, 4, 0.0, 1.0, 0.0)
	var b: Vector2 = Formulas.orbit_offset(karussell, 2, 4, 0.0, 1.0, 0.0)
	assert_almost_eq((a + b).length(), 0.0, 0.001, "opposite sides")
	var slow: float = Formulas.orbit_offset(karussell, 0, 4, 1.0, 1.0, 0.0).angle_to(a)
	var fast: float = Formulas.orbit_offset(karussell, 0, 4, 0.1, 1.0, 1.0).angle_to(a)
	assert_ne(slow, fast)


func test_ski_poles_pierce_through_a_line_of_enemies() -> void:
	var poles: WeaponData = load("res://data/weapons/skistoecke.tres")
	var manager: EnemyManager = _manager(7)
	_place(manager, [Vector2(0.0, 2.0), Vector2(0.0, 4.0), Vector2(0.0, 6.0), Vector2(0.0, 8.0), Vector2(0.0, 10.0),
			Vector2(0.0, 12.0), Vector2(0.0, 14.0)])
	var pool := ProjectilePool.new()
	add_child_autofree(pool)
	pool.setup(balance, 8)
	WeaponSystem.fire_shots(poles, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 1, 1.0, 0.5, pool)
	for frame: int in 60:
		pool.update(1.0 / 60.0, manager)
	var hurt: int = 0
	for k: int in 7:
		if manager.hp[k] < manager.max_hp[k]:
			hurt += 1
	assert_eq(hurt, poles.pierce + 1, "passes through `pierce` enemies and stops in the next")


func test_arcs_and_shots_aim_at_the_nearest_enemy_in_reach() -> void:
	var manager: EnemyManager = _manager(3)
	_place(manager, [Vector2(-3.0, 0.0), Vector2(0.0, -6.0), Vector2(30.0, 30.0)])
	var facing := Vector3(0.0, 0.0, 1.0)
	var aim: Vector3 = WeaponSystem.aim_at_nearest(Vector3.ZERO, facing, manager, 8.0, 2.0)
	assert_almost_eq(aim.x, -1.0, 0.001, "the nearer enemy, not the way the player faces")
	aim = WeaponSystem.aim_at_nearest(Vector3(20.0, 0.0, 0.0), facing, manager, 8.0, 2.0)
	assert_eq(aim, facing, "nobody in reach: the way the player faces")
	for direction: Vector3 in [Vector3(1.0, 0.0, 0.0), Vector3(-0.6, 0.0, -0.8), facing]:
		var back: Vector3 = WeaponSystem.aim_direction(WeaponSystem.aim_byte(direction))
		assert_lt(back.angle_to(direction), deg_to_rad(1.5), "the aim byte keeps the heading")
	var poles: WeaponData = load("res://data/weapons/skistoecke.tres")
	var tray: WeaponData = load("res://data/weapons/tablett.tres")
	assert_almost_eq(WeaponSystem.aim_reach(poles, 1.0, 0.0), poles.projectile_speed * poles.projectile_lifetime, 0.001)
	assert_almost_eq(WeaponSystem.aim_reach(tray, 1.0, 0.0), tray.projectile_speed * tray.projectile_lifetime * 0.5,
			0.001, "a boomerang turns at half its flight")


func test_a_client_pool_only_shows_shots() -> void:
	var pool := ProjectilePool.new()
	add_child_autofree(pool)
	pool.setup(balance, 4)
	pool.fire_shot(0.0, 0.0, 10.0, 0.0, 0.5, 1.0, 0.3, 0, 0.0)
	pool.update(0.1, null)
	assert_eq(pool.active_count, 1)
	pool.update(0.5, null)
	assert_eq(pool.active_count, 0)


func test_broeselfresser_go_for_the_knodl_and_bite() -> void:
	var pigeon: EnemyTypeData = load("res://data/enemies/taube.tres")
	var eaters: Array[EnemyTypeData] = [pigeon]
	var manager := EnemyManager.new(balance, eaters, 1, 3, null, 50.0)
	manager.populate(1, PackedVector3Array([Vector3.ZERO]))
	manager.pos_x[0] = 0.0
	manager.pos_z[0] = 10.0
	var player := PackedVector3Array([Vector3(0.0, 0.0, -5.0)])
	var knodl := PackedVector4Array([Vector4(5.0, 0.6, 10.0, 0.6)])
	manager.update(0.1, player, knodl)
	assert_gt(manager.pos_x[0], 0.0, "flies to the Knödl, not the player")
	for frame: int in 120:
		manager.update(1.0 / 60.0, player, knodl)
	assert_gt(manager.knodl_bites[0], 0.0)
	assert_almost_eq(manager.knodl_bites[0], pigeon.bite_per_second / 60.0, 0.001)
	manager.update(0.1, player)
	assert_lt(manager.pos_z[0], 10.0, "without a Knödl to eat it goes for the player")


func test_a_knodl_bitten_sheds_part_as_brosel() -> void:
	var knodl := Knodl.new()
	add_child_autofree(knodl)
	knodl.setup(1, balance, load("res://data/knodl/semmelknoedl.tres"), null, true)
	knodl.set_knodl_mass(100.0)
	knodl.bite(10.0, 0.5)
	assert_almost_eq(knodl.knodl_mass, 95.0, 0.001)
	assert_eq(knodl.take_shed(), 5)


func test_the_wave_mixes_types_by_the_clock() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	var boar: int = -1
	for t: int in wave.enemies.size():
		if wave.enemies[t].id == &"wildschwein":
			boar = t
	assert_gte(boar, 0)
	assert_eq(wave.weights_at(30.0)[boar], 0.0, "no boars at the start")
	assert_gt(wave.weights_at(6.0 * 60.0)[boar], 0.0)
	var manager := EnemyManager.new(balance, wave.enemies, 200, 3, null, 50.0)
	manager.type_weights = wave.weights_at(30.0)
	manager.populate(200, PackedVector3Array([Vector3.ZERO]))
	for i: int in 200:
		assert_ne(manager.type[i], boar)


func test_enemy_hp_scales_for_new_spawns() -> void:
	var manager := EnemyManager.new(balance, types, 2, 3, null, 50.0)
	manager.hp_mult = 2.5
	manager.populate(2, PackedVector3Array([Vector3.ZERO]))
	assert_almost_eq(manager.max_hp[0], types[0].max_hp * 2.5, 0.001)


func test_the_riesen_wirt_sweeps_without_drops() -> void:
	var manager: EnemyManager = _manager(2)
	manager.despawn(0)
	assert_eq(manager.alive_count, 1)
	assert_eq(manager.kills, 0)
	assert_eq(manager.kill_x.size(), 0)
