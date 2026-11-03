extends GutTest

var grid: SpatialHash


func before_each() -> void:
	grid = SpatialHash.new(10.0, 2.0, 16)


func test_grid_covers_the_arena() -> void:
	assert_eq(grid.columns, 10)
	assert_eq(grid.rows, 10)
	assert_eq(grid.head.size(), 100)


func test_query_finds_items_in_touching_cells_only() -> void:
	grid.insert(0, 0.5, 0.5)
	grid.insert(1, 1.5, 0.5)
	grid.insert(2, 8.0, 8.0)
	var found: int = grid.query(0.5, 0.5, 0.5)
	var items: Array[int] = []
	for k: int in found:
		items.append(grid.results[k])
	items.sort()
	assert_eq(items, [0, 1] as Array[int])


func test_query_across_cell_borders() -> void:
	grid.insert(3, 1.9, 1.9)
	grid.insert(4, 2.1, 2.1)
	assert_eq(grid.query(2.0, 2.0, 0.3), 2)


func test_positions_outside_are_clamped_to_border_cells() -> void:
	assert_eq(grid.cell_of(-50.0, -50.0), 0)
	assert_eq(grid.cell_of(50.0, 50.0), 99)


func test_clear_empties_every_cell() -> void:
	grid.insert(0, 0.0, 0.0)
	grid.clear()
	assert_eq(grid.query(0.0, 0.0, 1.0), 0)


func test_query_stops_at_result_capacity() -> void:
	var small := SpatialHash.new(10.0, 2.0, 16, 4)
	for i: int in 10:
		small.insert(i, 0.1, 0.1)
	assert_eq(small.query(0.1, 0.1, 0.5), 4)
