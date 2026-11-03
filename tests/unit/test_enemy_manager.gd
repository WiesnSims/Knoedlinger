extends GutTest

var manager: EnemyManager


func before_each() -> void:
	var types: Array[EnemyTypeData] = [load("res://data/enemies/tourist.tres")]
	manager = EnemyManager.new(load("res://data/balance.tres"), types, 64, 5)
	manager.populate(50, PackedVector3Array([Vector3.ZERO]))


func test_populate_spawns_on_the_ring() -> void:
	assert_eq(manager.alive_count, 50)
	var balance: BalanceData = manager.balance
	var outside: int = 0
	for i: int in 50:
		var d: float = Vector2(manager.pos_x[i], manager.pos_z[i]).length()
		if d < balance.enemy_spawn_ring_min - 0.01 or d > balance.enemy_spawn_ring_max + 0.01:
			outside += 1
	assert_eq(outside, 0)


func test_enemies_close_in_on_the_player() -> void:
	var before: float = Vector2(manager.pos_x[0], manager.pos_z[0]).length()
	for frame: int in 30:
		manager.update(1.0 / 60.0, PackedVector3Array([Vector3.ZERO]))
	assert_lt(Vector2(manager.pos_x[0], manager.pos_z[0]).length(), before)


func test_enemies_chase_the_nearest_of_several_players() -> void:
	var targets := PackedVector3Array([Vector3(-140.0, 0.0, -140.0), Vector3(manager.pos_x[0] + 3.0, 0.0, manager.pos_z[0])])
	var before_x: float = manager.pos_x[0]
	manager.update(0.1, targets)
	assert_gt(manager.pos_x[0], before_x)


func test_kill_and_respawn_keep_the_count() -> void:
	assert_true(manager.damage(0, 1000.0))
	assert_eq(manager.alive_count, 49)
	assert_eq(manager.kills, 1)
	manager.update(1.0 / 60.0, PackedVector3Array([Vector3.ZERO]))
	assert_eq(manager.alive_count, 50)
	var events: Array[PackedInt32Array] = manager.take_events()
	assert_true(events[1].has(0))


func test_hp_bucket_scales_to_four_bits() -> void:
	assert_eq(manager.hp_bucket(1), 15)
	manager.damage(1, manager.max_hp[1] * 0.5)
	assert_between(manager.hp_bucket(1), 7, 8)
