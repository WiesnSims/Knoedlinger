extends GutTest


func _prop(kind: MapProp.Kind, where: Vector3, prop_size: Vector3, yaw: float = 0.0) -> MapProp:
	var prop := MapProp.new()
	prop.kind = kind
	prop.position = where
	prop.size = prop_size
	prop.yaw_degrees = yaw
	prop.steps = 4
	return prop


func _flat_map() -> MapData:
	var map := MapData.new()
	map.half_size = 20.0
	map.terrain_samples = 41
	map.ground_cell = 0.5
	map.noise_amplitude = 0.0
	map.rim_height = 0.0
	return map


func test_heightfield_samples_bilinearly() -> void:
	var field := Heightfield.new(1.0, 3)
	# Samples at x/z = -1, 0, 1; raise the middle one.
	field.heights[4] = 2.0
	assert_almost_eq(field.height_at(0.0, 0.0), 2.0, 0.0001)
	assert_almost_eq(field.height_at(0.5, 0.0), 1.0, 0.0001)
	assert_almost_eq(field.height_at(-0.5, -0.5), 0.5, 0.0001)
	# Outside the grid the border holds.
	assert_almost_eq(field.height_at(50.0, 50.0), 0.0, 0.0001)


func test_block_top_and_ramp_slope() -> void:
	var block: MapProp = _prop(MapProp.Kind.BLOCK, Vector3(0.0, 1.0, 0.0), Vector3(4.0, 3.0, 4.0))
	assert_eq(block.top_at(1.0, 1.0), 4.0)
	assert_eq(block.top_at(3.0, 0.0), -INF)
	var ramp: MapProp = _prop(MapProp.Kind.RAMP, Vector3.ZERO, Vector3(2.0, 4.0, 8.0))
	assert_almost_eq(ramp.top_at(0.0, -4.0), 0.0, 0.0001)
	assert_almost_eq(ramp.top_at(0.0, 0.0), 2.0, 0.0001)
	assert_almost_eq(ramp.top_at(0.0, 3.9), 3.95, 0.0001)


func test_yaw_turns_plus_z_toward_plus_x() -> void:
	# Turned by 90 degrees, a ramp rising along +z rises along +x.
	var ramp: MapProp = _prop(MapProp.Kind.RAMP, Vector3.ZERO, Vector3(2.0, 4.0, 8.0), 90.0)
	assert_lt(ramp.top_at(-3.0, 0.0), ramp.top_at(3.0, 0.0))
	assert_eq(ramp.top_at(0.0, 3.0), -INF)


func test_stairs_rise_in_steps() -> void:
	var stairs: MapProp = _prop(MapProp.Kind.STAIRS, Vector3.ZERO, Vector3(2.0, 4.0, 8.0))
	assert_almost_eq(stairs.top_at(0.0, -3.5), 1.0, 0.0001)
	assert_almost_eq(stairs.top_at(0.0, -2.5), 1.0, 0.0001)
	assert_almost_eq(stairs.top_at(0.0, -1.5), 2.0, 0.0001)
	assert_almost_eq(stairs.top_at(0.0, 3.9), 4.0, 0.0001)


func test_ground_field_includes_walkable_props_only() -> void:
	var map: MapData = _flat_map()
	map.props.append(_prop(MapProp.Kind.BLOCK, Vector3(5.0, 0.0, 5.0), Vector3(4.0, 3.0, 4.0)))
	var pole: MapProp = _prop(MapProp.Kind.POLE, Vector3(-5.0, 0.0, -5.0), Vector3(1.0, 10.0, 1.0))
	pole.walkable = false
	map.props.append(pole)
	var terrain: Heightfield = Heightfield.bake_terrain(map)
	var ground: Heightfield = Heightfield.bake_ground(map, terrain)
	assert_almost_eq(ground.height_at(5.0, 5.0), 3.0, 0.0001)
	assert_almost_eq(ground.height_at(-5.0, -5.0), 0.0, 0.0001)
	assert_almost_eq(ground.height_at(0.0, 0.0), 0.0, 0.0001)


func test_terrain_has_hills_and_rim() -> void:
	var map: MapData = _flat_map()
	map.flat_radius = 2.0
	map.hills = PackedVector4Array([Vector4(10.0, 0.0, 5.0, 3.0), Vector4(-10.0, 0.0, 5.0, -2.0)])
	map.rim_start = 15.0
	map.rim_height = 10.0
	assert_almost_eq(map.terrain_height(10.0, 0.0), 3.0, 0.0001)
	assert_almost_eq(map.terrain_height(-10.0, 0.0), -2.0, 0.0001)
	assert_almost_eq(map.terrain_height(0.0, 0.0), 0.0, 0.0001)
	assert_almost_eq(map.terrain_height(0.0, 20.0), 10.0, 0.0001)


func test_the_test_field_loads_and_bakes() -> void:
	var map: MapData = load("res://data/maps/testfeld.tres")
	assert_not_null(map)
	assert_gt(map.props.size(), 5)
	assert_gt(map.bot_waypoints.size(), 3)
	# Jolt keeps a height map shape only for power-of-two sample counts (MapData.terrain_samples).
	assert_eq(map.terrain_samples & (map.terrain_samples - 1), 0)
	var terrain: Heightfield = Heightfield.bake_terrain(map)
	assert_almost_eq(terrain.height_at(map.spawn_point.x, map.spawn_point.z), 0.0, 0.05)
	assert_ne(TranslationServer.translate(map.name_key), StringName(map.name_key))
