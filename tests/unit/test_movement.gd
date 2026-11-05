extends GutTest
## Megabonk-style movement (docs/DECISIONS.md, movement): momentum, jump arcs, gliding, fliers
## that rise to airborne players.

var balance: BalanceData
var player: Player


func before_each() -> void:
	balance = BalanceData.new()
	player = Player.new()
	player.setup(1, false, balance, null, null)
	add_child_autofree(player)
	player.teleport(Vector3(0.0, 5.0, 0.0))


## Seconds from a ground jump until the feet are back at take-off height (fixed 60 Hz steps).
func _air_time(held: bool) -> float:
	player.velocity = Vector3(0.0, balance.player_jump_velocity, 0.0)
	var height: float = 0.0
	var time: float = 0.0
	var step: float = 1.0 / 60.0
	while time < 5.0:
		player.call(&"_fall", held, step)
		height += player.velocity.y * step
		time += step
		if height <= 0.0:
			break
	return time


func test_a_full_jump_hangs_about_a_second_and_holding_hangs_longer() -> void:
	var held: float = _air_time(true)
	assert_between(held, 0.8, 1.1, "about Megabonk's 1 s")
	assert_lt(_air_time(false), held, "the hang at the top only while jump is held")


func test_gliding_falls_slowly_only_while_jump_is_held() -> void:
	player.stat_glide = 0.5
	player.velocity = Vector3(0.0, -20.0, 0.0)
	player.call(&"_fall", true, 1.0 / 60.0)
	var cap: float = balance.player_glide_fall_speed / (1.0 + 0.5 * balance.player_glide_strength)
	assert_almost_eq(player.velocity.y, -cap, 0.001)
	player.velocity = Vector3(0.0, -20.0, 0.0)
	player.call(&"_fall", false, 1.0 / 60.0)
	assert_lt(player.velocity.y, -20.0, "let go: falls normally")


func test_the_air_keeps_momentum_and_the_cap_holds() -> void:
	var fast := Vector2(12.0, 0.0)
	var kept: Vector2 = player.call(&"_steer", fast, Vector2.ZERO, player.run_speed(), false, 0.1)
	assert_almost_eq(kept.length(), 12.0, 0.001, "no stick in the air: keeps going")
	var steered: Vector2 = player.call(&"_steer", fast, Vector2(0.0, 1.0), player.run_speed(), false, 0.1)
	assert_almost_eq(steered.length(), 12.0, 0.001, "the stick steers, the speed stays")
	assert_gt(steered.y, 0.0)
	var braked: Vector2 = player.call(&"_steer", fast, Vector2(-1.0, 0.0), player.run_speed(), false, 0.1)
	assert_lt(braked.length(), 12.0, "pulling back brakes")
	var capped: Vector2 = player.call(&"_steer", Vector2(40.0, 0.0), Vector2(1.0, 0.0), player.run_speed(), false, 0.1)
	assert_almost_eq(capped.length(), player.momentum_cap(), 0.001)
	assert_almost_eq(player.max_speed(), player.momentum_cap(), 0.001, "the host's pose check allows it")


func test_a_jump_while_running_pushes_forward() -> void:
	player.velocity = Vector3(player.run_speed(), 0.0, 0.0)
	player.set(&"_move", Vector2(1.0, 0.0))
	player.call(&"_jump")
	assert_almost_eq(player.velocity.x, player.run_speed() + balance.player_jump_forward_boost, 0.001)
	assert_gt(player.velocity.y, 0.0)


func test_fliers_rise_to_airborne_targets_only_up_close() -> void:
	var range_m: float = balance.enemy_air_climb_range
	assert_eq(EnemyManager.air_lift(5.0, 0.5, 8.0, range_m), 5.0, "right below: all the way up")
	assert_eq(EnemyManager.air_lift(12.0, 0.5, 8.0, range_m), 8.0, "never above its reach")
	assert_eq(EnemyManager.air_lift(5.0, range_m + 1.0, 8.0, range_m), 0.0, "far away: stays low")
	assert_eq(EnemyManager.air_lift(5.0, 0.5, 0.0, range_m), 0.0, "walkers never rise")



## Runs at a slope (rising toward -z at `degrees` from a floor) for `seconds`, holding forward and
## tapping jump; returns the height gained.
func _climb(degrees: float, seconds: float) -> float:
	InputSetup.ensure_actions()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	_static(floor_box, Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	var slope_box := BoxShape3D.new()
	slope_box.size = Vector3(20.0, 1.0, 80.0)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(degrees))
	# Its top face runs through the origin and rises toward -z.
	_static(slope_box, Transform3D(tilt, -tilt.y * 0.5))
	var climber := Player.new()
	climber.setup(2, true, balance, null, null)
	add_child_autofree(climber)
	climber.teleport(Vector3(0.0, 0.1, 3.0))
	await wait_physics_frames(2)
	var from: float = climber.global_position.y
	Input.action_press(&"move_up")
	for k: int in roundi(seconds * 60.0):
		if k % 20 == 0:
			Input.action_press(&"jump")
		elif k % 20 == 8:
			Input.action_release(&"jump")
		await wait_physics_frames(1)
	Input.action_release(&"move_up")
	Input.action_release(&"jump")
	return climber.global_position.y - from


func _static(box: BoxShape3D, where: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = MapBuilder.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.transform = where
	add_child_autofree(body)


func test_a_steep_slope_is_climbed_in_hops_but_a_wall_is_not() -> void:
	var steep: float = await _climb(60.0, 3.0)
	assert_gt(steep, 3.0, "60 degrees: too steep to walk, firm enough to hop up")
	var wall: float = await _climb(88.0, 3.0)
	assert_lt(wall, 3.0, "a wall stays a wall: one jump high at most")
