extends GutTest
## Pooled MultiMesh renderers repack their instances every frame; physics interpolation (on for the
## project) would blend instance i of one tick with a different enemy of the next tick.


func test_pooled_renderers_are_not_physics_interpolated() -> void:
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"), "the project interpolates")
	var types: Array[EnemyTypeData] = [load("res://data/enemies/tourist.tres")]
	var renderer := EnemyRenderer.new()
	add_child_autofree(renderer)
	renderer.setup(types, 8)
	var brosel := BroselField.new()
	add_child_autofree(brosel)
	brosel.setup(BalanceData.new(), null, 20.0)
	var projectiles := ProjectilePool.new()
	add_child_autofree(projectiles)
	projectiles.setup(BalanceData.new(), 8)
	var checked: int = 0
	for parent: Node in [renderer, brosel, projectiles]:
		for child: Node in parent.get_children():
			var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
			if instance != null:
				assert_false(instance.is_physics_interpolated(), instance.name)
				checked += 1
	assert_eq(checked, 4)


func test_the_knodl_sphere_is_fine_enough_to_stay_round() -> void:
	var sphere: SphereMesh = MeshFactory.knodl()
	assert_gte(sphere.radial_segments, 48)
	assert_gte(sphere.rings, 24)
