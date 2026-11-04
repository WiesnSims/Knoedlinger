class_name MapKit
extends RefCounted
## Shared helpers for the map generators in tools/maps/ (the Kirtag's has its own copy from M3):
## structures with an overlap check, props standing on the terrain, spots that must stay free.

var map: MapData
var problems: int = 0
## Footprints placed so far (x, z, radius).
var taken: Array[Vector3] = []


func _init(p_map: MapData) -> void:
	map = p_map


func put(kind: MapStructure.Kind, at: Vector2, yaw: float, size: Vector3, color: Color, accent: Color, radius: float) -> void:
	if radius > 0.0:
		claim(at, radius, MapStructure.Kind.keys()[kind])
	var structure := MapStructure.new()
	structure.kind = kind
	structure.position = at
	structure.yaw_degrees = yaw
	structure.size = size
	structure.color = color
	structure.accent = accent
	map.structures.append(structure)


## A prop whose foot stands on the terrain at (x, z) plus `lift` (a block's foot, a ramp's start).
func prop(kind: MapProp.Kind, at: Vector2, lift: float, size: Vector3, yaw: float, color: Color, solid: bool = true,
		walkable: bool = true, steps: int = 6) -> MapProp:
	var p := MapProp.new()
	p.kind = kind
	p.position = Vector3(at.x, map.terrain_height(at.x, at.y) + lift, at.y)
	p.size = size
	p.yaw_degrees = yaw
	p.color = color
	p.solid = solid
	p.walkable = walkable
	p.steps = steps
	map.props.append(p)
	return p


func claim(at: Vector2, radius: float, what: String) -> void:
	for other: Vector3 in taken:
		if at.distance_to(Vector2(other.x, other.y)) < radius + other.z - 0.5:
			push_error("%s at %s overlaps something at (%.0f, %.0f)" % [what, at, other.x, other.y])
			problems += 1
	taken.append(Vector3(at.x, at.y, radius))


func blocked(at: Vector2, radius: float) -> bool:
	for other: Vector3 in taken:
		if at.distance_to(Vector2(other.x, other.y)) < radius + other.z:
			return true
	for list: PackedVector2Array in [map.wirtshaus_spots, map.stempel_spots, map.chest_spots]:
		for spot: Vector2 in list:
			if at.distance_to(spot) < radius + 8.0:
				return true
	return false


func near_path(at: Vector2, margin: float) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2(margin, 0.0), Vector2(-margin, 0.0), Vector2(0.0, margin), Vector2(0.0, -margin)]:
		if map.path_cover(at.x + offset.x, at.y + offset.y) > 0.0:
			return true
	return false


## Seeded fir trees where nothing else stands, within `inner`..`outer` (square distance) of the centre.
func forest(seed_value: int, count: int, inner: float, outer: float, green: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: int = 0
	var tries: int = 0
	while placed < count and tries < 8000:
		tries += 1
		var at := Vector2(rng.randf_range(-outer, outer), rng.randf_range(-outer, outer))
		var edge: float = maxf(absf(at.x), absf(at.y))
		if edge < inner or blocked(at, 3.5) or near_path(at, 6.0):
			continue
		put(MapStructure.Kind.FIR, at, rng.randf_range(0.0, 90.0), Vector3(1.0, rng.randf_range(8.0, 13.0), 1.0),
				green.lightened(rng.randf_range(-0.05, 0.12)), Color.WHITE, 1.2)
		placed += 1


func facing(at: Vector2) -> float:
	return rad_to_deg(atan2(-at.x, -at.y))


func save(path: String) -> int:
	if problems > 0:
		push_error("%d overlaps, not saved" % problems)
		return 1
	var error: Error = ResourceSaver.save(map, path)
	print("saved %s: %d structures, %d props, %d wirtshaus spots, %d stempel spots, %d chest spots (error %d)" % [
		path, map.structures.size(), map.props.size(), map.wirtshaus_spots.size(), map.stempel_spots.size(),
		map.chest_spots.size(), error])
	return 0 if error == OK else 1
