class_name SpatialHash
extends RefCounted
## Uniform grid over the arena's XZ plane for enemy, projectile, Brösel and Knödl collisions
## (CLAUDE.md: never the physics engine). Each cell is a linked list through `next`: `head[cell]` is
## the first item in the cell, `next[item]` the one after it, -1 ends the list. Rebuilt every frame
## with clear() + insert(), both O(1) per item; clear() is one native fill.
##
## Hot loops may walk `head` and `next` directly (see EnemyManager); everything else uses query().

var cell_size: float
var columns: int
var rows: int
var origin_x: float
var origin_z: float
## First item per cell, -1 when empty.
var head: PackedInt32Array = PackedInt32Array()
## Next item in the same cell, -1 at the end.
var next: PackedInt32Array = PackedInt32Array()
## Items found by the last query(), valid up to result_count.
var results: PackedInt32Array = PackedInt32Array()
var result_count: int = 0

var _inverse_cell: float


func _init(half_size: float, cell: float, capacity: int, max_results: int = 256) -> void:
	cell_size = cell
	_inverse_cell = 1.0 / cell
	columns = ceili(half_size * 2.0 / cell)
	rows = columns
	origin_x = -half_size
	origin_z = -half_size
	head.resize(columns * rows)
	head.fill(-1)
	next.resize(capacity)
	next.fill(-1)
	results.resize(max_results)


func clear() -> void:
	head.fill(-1)


## Cell index for a position; positions outside the grid are clamped to the border cells.
func cell_of(x: float, z: float) -> int:
	var cx: int = clampi(int((x - origin_x) * _inverse_cell), 0, columns - 1)
	var cz: int = clampi(int((z - origin_z) * _inverse_cell), 0, rows - 1)
	return cz * columns + cx


func insert(item: int, x: float, z: float) -> void:
	var cell: int = cell_of(x, z)
	next[item] = head[cell]
	head[cell] = item


## Collects every item in the cells touching the square around (x, z) with half side `radius` into
## `results` and returns how many. Callers check the exact distance themselves.
func query(x: float, z: float, radius: float) -> int:
	result_count = 0
	var max_results: int = results.size()
	var x0: int = clampi(int((x - radius - origin_x) * _inverse_cell), 0, columns - 1)
	var x1: int = clampi(int((x + radius - origin_x) * _inverse_cell), 0, columns - 1)
	var z0: int = clampi(int((z - radius - origin_z) * _inverse_cell), 0, rows - 1)
	var z1: int = clampi(int((z + radius - origin_z) * _inverse_cell), 0, rows - 1)
	for cz: int in range(z0, z1 + 1):
		var row: int = cz * columns
		for cx: int in range(x0, x1 + 1):
			var item: int = head[row + cx]
			while item >= 0:
				if result_count == max_results:
					return result_count
				results[result_count] = item
				result_count += 1
				item = next[item]
	return result_count
