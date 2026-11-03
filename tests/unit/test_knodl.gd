extends GutTest
## The Knödl on its Spagat with real Jolt physics: a floor, a player and a simulated Knödl.

var balance: BalanceData
var sort: KnodlSortData
var floor_body: StaticBody3D
var player: Player
var knodl: Knodl


func before_each() -> void:
	InputSetup.ensure_actions()
	balance = load("res://data/balance.tres")
	sort = load("res://data/knodl/semmelknoedl.tres")
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = MapBuilder.LAYER_WORLD | MapBuilder.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	player = Player.new()
	player.setup(1, false, balance, null, null)
	add_child_autofree(player)
	player.teleport(Vector3.ZERO)
	knodl = Knodl.new()
	knodl.setup(1, balance, sort, player, true)
	add_child_autofree(knodl)
	knodl.place_at(Vector3(0.0, 0.6, 2.0))


## Moves the (remote-style) player to `where` over `frames` physics frames.
func _walk(where: Vector3, frames: int) -> void:
	var start: Vector3 = player.global_position
	for frame: int in frames:
		var to: Vector3 = start.lerp(where, float(frame + 1) / frames)
		var message := InputMessage.new()
		message.position = to
		player.apply_remote(message)
		await wait_physics_frames(1)


func test_the_string_never_gets_longer_than_its_maximum() -> void:
	await _walk(Vector3(30.0, 0.0, 0.0), 120)
	await wait_physics_frames(30)
	var distance: float = knodl.global_position.distance_to(player.hand_position())
	assert_lt(distance, balance.knodl_max_length + 0.3)
	assert_eq(knodl.state, Knodl.State.ATTACHED)


func test_schupfn_throws_and_reeling_brings_it_back() -> void:
	await wait_physics_frames(10)
	assert_true(knodl.schupfn(Vector3(1.0, 0.0, 0.0)))
	assert_eq(knodl.state, Knodl.State.THROWN)
	assert_gt(knodl.cooldown, 0.0)
	await wait_physics_frames(30)
	assert_gt(knodl.global_position.distance_to(player.hand_position()), balance.knodl_max_length,
			"a thrown Knödl flies past the string's length")
	assert_true(knodl.schupfn(Vector3.ZERO))
	assert_eq(knodl.state, Knodl.State.REELING)
	await wait_physics_frames(roundi(balance.knodl_reel_time * 60.0) + 20)
	assert_eq(knodl.state, Knodl.State.ATTACHED)
	assert_false(knodl.schupfn(Vector3(1.0, 0.0, 0.0)), "still on cooldown")


func test_growing_mass_grows_the_knodl() -> void:
	var before: float = knodl.radius
	knodl.add_knodl_mass(400.0)
	assert_gt(knodl.radius, before)
	assert_almost_eq(knodl.radius, Formulas.knodl_radius(400.0, balance), 0.0001)


func test_a_rolling_knodl_crushes_enemies() -> void:
	var types: Array[EnemyTypeData] = [load("res://data/enemies/tourist.tres")]
	var enemies := EnemyManager.new(balance, types, 1, 1, null, 50.0)
	enemies.populate(1, PackedVector3Array([Vector3.ZERO]))
	enemies.pos_x[0] = knodl.global_position.x
	enemies.pos_z[0] = knodl.global_position.z + 0.3
	enemies.update(0.0001, PackedVector3Array([Vector3(40.0, 0.0, 40.0)]))
	knodl.linear_velocity = Vector3(0.0, 0.0, 12.0)
	var kills: int = knodl.crush(enemies)
	assert_eq(kills, 1)
	assert_eq(enemies.kill_x.size(), 1)
