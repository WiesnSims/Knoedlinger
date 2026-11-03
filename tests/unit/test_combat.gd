extends GutTest
## Weapons, contact damage, knockback, kills and the 3D ground for enemies.

var balance: BalanceData
var types: Array[EnemyTypeData] = []


func before_each() -> void:
	balance = BalanceData.new()
	var tourist: EnemyTypeData = load("res://data/enemies/tourist.tres")
	types = [tourist]


func _manager(count: int) -> EnemyManager:
	var manager := EnemyManager.new(balance, types, count, 3, null, 50.0)
	manager.populate(count, PackedVector3Array([Vector3.ZERO]))
	return manager


func _place(manager: EnemyManager, slot: int, x: float, z: float) -> void:
	manager.pos_x[slot] = x
	manager.pos_z[slot] = z
	manager.update(0.0001, PackedVector3Array([Vector3(100.0, 0.0, 100.0)]))


func test_the_shovel_hits_in_front_not_behind() -> void:
	var manager: EnemyManager = _manager(2)
	manager.pos_x[0] = 0.0
	manager.pos_z[0] = 2.0
	manager.pos_x[1] = 0.0
	manager.pos_z[1] = -2.0
	manager.update(0.0001, PackedVector3Array([Vector3(40.0, 0.0, 40.0)]))
	var shovel: WeaponData = load("res://data/weapons/schneeschaufel.tres")
	var hit: int = WeaponSystem.arc_hit(shovel, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), manager)
	assert_eq(hit, 1)
	assert_lt(manager.hp[0], manager.max_hp[0])
	assert_eq(manager.hp[1], manager.max_hp[1])


func test_kills_are_recorded_for_brosel_drops() -> void:
	var manager: EnemyManager = _manager(3)
	manager.damage(1, 1000.0)
	assert_eq(manager.kill_x.size(), 1)
	assert_eq(manager.kill_xp[0], types[0].brosel_xp)
	assert_eq(manager.kill_x[0], manager.pos_x[1])
	manager.clear_kills()
	assert_eq(manager.kill_x.size(), 0)


func test_knockback_pushes_and_dies_away() -> void:
	var manager: EnemyManager = _manager(1)
	_place(manager, 0, 0.0, 0.0)
	manager.damage(0, 0.1, 10.0, 0.0)
	var far := PackedVector3Array([Vector3(0.0, 0.0, 40.0)])
	for frame: int in 30:
		manager.update(1.0 / 60.0, far)
	assert_gt(manager.pos_x[0], 1.0)
	for frame: int in 120:
		manager.update(1.0 / 60.0, far)
	assert_eq(manager.kb_x[0], 0.0)


func test_touching_enemies_hurt_the_right_player_unless_they_are_above() -> void:
	var manager: EnemyManager = _manager(1)
	_place(manager, 0, 0.5, 0.0)
	var targets := PackedVector3Array([Vector3(40.0, 0.0, 40.0), Vector3(0.0, 0.0, 0.0)])
	manager.update(1.0 / 60.0, targets)
	assert_eq(manager.touch_damage[0], 0.0)
	assert_eq(manager.touch_damage[1], types[0].contact_damage)
	targets[1] = Vector3(0.0, 5.0, 0.0)
	manager.pos_x[0] = 0.5
	manager.pos_z[0] = 0.0
	manager.update(1.0 / 60.0, targets)
	assert_eq(manager.touch_damage[1], 0.0, "standing on a ledge")


func test_walkers_slow_down_climbing_a_wall() -> void:
	var ground := Heightfield.new(50.0, 101)
	for iz: int in ground.samples:
		for ix: int in ground.samples:
			if ground.world_x(ix) >= 2.0:
				ground.heights[iz * ground.samples + ix] = 4.0
	var flat_manager := EnemyManager.new(balance, types, 1, 3, null, 50.0)
	var wall_manager := EnemyManager.new(balance, types, 1, 3, ground, 50.0)
	for manager: EnemyManager in [flat_manager, wall_manager]:
		manager.populate(1, PackedVector3Array([Vector3.ZERO]))
		manager.pos_x[0] = 0.5
		manager.pos_z[0] = 0.0
		manager.speed[0] = 3.0
	var target := PackedVector3Array([Vector3(20.0, 0.0, 0.0)])
	for frame: int in 60:
		flat_manager.update(1.0 / 60.0, target)
		wall_manager.update(1.0 / 60.0, target)
	assert_lt(wall_manager.pos_x[0], flat_manager.pos_x[0] - 0.5)
	assert_gt(wall_manager.pos_x[0], 1.5, "they still scramble up")
