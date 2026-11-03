class_name Heightfield
extends RefCounted
## Heights on a square grid centred on the origin, sampled bilinearly. Two of them per map: the
## terrain (render mesh and Jolt collision) and the ground (terrain plus walkable props) that enemies
## and Brösel stand on, so 2D enemy data lives on 3D terrain without physics (docs/DECISIONS.md).

var half_size: float = 0.0
var cell: float = 1.0
## Samples per side.
var samples: int = 0
## Row-major, x fastest: heights[z * samples + x].
var heights: PackedFloat32Array = PackedFloat32Array()

var _inverse_cell: float = 1.0


func _init(p_half_size: float = 0.0, p_samples: int = 2) -> void:
	half_size = p_half_size
	samples = maxi(p_samples, 2)
	cell = half_size * 2.0 / float(samples - 1) if half_size > 0.0 else 1.0
	_inverse_cell = 1.0 / cell
	heights.resize(samples * samples)
	heights.fill(0.0)


## Bilinear height at a world position; outside the grid the border value holds.
func height_at(x: float, z: float) -> float:
	var fx: float = clampf((x + half_size) * _inverse_cell, 0.0, samples - 1.001)
	var fz: float = clampf((z + half_size) * _inverse_cell, 0.0, samples - 1.001)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var i: int = iz * samples + ix
	var h00: float = heights[i]
	var h10: float = heights[i + 1]
	var h01: float = heights[i + samples]
	var h11: float = heights[i + samples + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Steepest rise per metre around a position (central differences), for slope checks.
func slope_at(x: float, z: float) -> float:
	var dx: float = (height_at(x + cell, z) - height_at(x - cell, z)) * 0.5 * _inverse_cell
	var dz: float = (height_at(x, z + cell) - height_at(x, z - cell)) * 0.5 * _inverse_cell
	return sqrt(dx * dx + dz * dz)


func world_x(ix: int) -> float:
	return -half_size + ix * cell


## The terrain of a map at its own resolution, from the exact height function.
static func bake_terrain(map: MapData) -> Heightfield:
	var field := Heightfield.new(map.half_size, map.terrain_samples)
	var n: int = field.samples
	for iz: int in n:
		var z: float = field.world_x(iz)
		var row: int = iz * n
		for ix: int in n:
			field.heights[row + ix] = map.terrain_height(field.world_x(ix), z)
	return field


## The ground enemies and Brösel stand on: the terrain, raised to the top of every walkable prop.
static func bake_ground(map: MapData, terrain: Heightfield) -> Heightfield:
	var n: int = roundi(map.half_size * 2.0 / map.ground_cell) + 1
	var field := Heightfield.new(map.half_size, n)
	for iz: int in n:
		var z: float = field.world_x(iz)
		var row: int = iz * n
		for ix: int in n:
			field.heights[row + ix] = terrain.height_at(field.world_x(ix), z)
	for prop: MapProp in map.props:
		if not prop.walkable:
			continue
		var bounds: Rect2 = prop.footprint_bounds()
		var x0: int = clampi(floori((bounds.position.x + map.half_size) / field.cell), 0, n - 1)
		var x1: int = clampi(ceili((bounds.end.x + map.half_size) / field.cell), 0, n - 1)
		var z0: int = clampi(floori((bounds.position.y + map.half_size) / field.cell), 0, n - 1)
		var z1: int = clampi(ceili((bounds.end.y + map.half_size) / field.cell), 0, n - 1)
		for iz: int in range(z0, z1 + 1):
			var z: float = field.world_x(iz)
			for ix: int in range(x0, x1 + 1):
				var top: float = prop.top_at(field.world_x(ix), z)
				var i: int = iz * n + ix
				if top > field.heights[i]:
					field.heights[i] = top
	return field
