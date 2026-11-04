extends SceneTree
## Lays out the Kirtag map (GAME-DESIGN.md map 1: "Kirtag in Unterhinterkogl") and saves it as
## data/maps/kirtag.tres. The .tres is the map; this script only places its ~150 entries and checks
## that nothing overlaps. Edit the layout here and run it again:
##   godot --headless --path . -s tools/maps/make_kirtag.gd
##
## North (-z) is the Gemeindeamt with the boss gate, the Kirtag square with the Maibaum and the
## family's Knödl stand is the centre, the church is east, a farm with an orchard south-east, the
## chapel on its hill south-west, forest toward the mountains all round.

const OUT: String = "res://data/maps/kirtag.tres"
const WALL := Color(0.95, 0.92, 0.84)
const WALL_YELLOW := Color(0.96, 0.86, 0.58)
const WALL_PINK := Color(0.95, 0.8, 0.74)
const WALL_GREEN := Color(0.8, 0.88, 0.74)
const ROOF_BROWN := Color(0.5, 0.3, 0.16)
const ROOF_DARK := Color(0.32, 0.27, 0.25)
const ROOF_GREEN := Color(0.3, 0.45, 0.35)
const CANVAS := Color(0.96, 0.96, 0.94)
const BLUE := Color(0.25, 0.45, 0.78)
const WOOD := Color(0.55, 0.38, 0.22)

var _map := MapData.new()
## Footprints placed so far (x, z, radius) for the overlap check.
var _taken: Array[Vector3] = []
var _problems: int = 0


func _init() -> void:
	_map.id = &"kirtag"
	_map.name_key = "MAP_KIRTAG"
	_map.half_size = 150.0
	_map.terrain_samples = 256
	_map.ground_cell = 0.5
	_map.noise_seed = 11
	_map.noise_amplitude = 1.0
	_map.noise_frequency = 0.02
	_map.flat_radius = 48.0
	_map.flat_blend = 22.0
	_map.rim_start = 124.0
	_map.rim_height = 30.0
	_map.spawn_point = Vector3(0.0, 0.0, 6.0)
	_map.plaza_radius = 30.0
	_map.path_width = 5.0
	_map.portal_point = Vector2(0.0, -76.0)
	# Hills: the chapel hill, a forest hill north-east, a small one north-west, the pasture rise
	# south-east and a hollow south.
	_map.hills = PackedVector4Array([
		Vector4(-92.0, 88.0, 34.0, 13.0), Vector4(98.0, -94.0, 30.0, 10.0), Vector4(-70.0, -100.0, 24.0, 7.0),
		Vector4(96.0, 70.0, 30.0, 2.5), Vector4(36.0, 84.0, 16.0, -3.0), Vector4(-104.0, -12.0, 18.0, 4.0)])
	# M4 verticality, a light touch (it stays the tutorial map): the Alm behind the Gemeindeamt, a
	# lookout in two steps west, a crag east; a chest waits on each.
	_map.mesa_edge = 3.0
	_map.mesas = PackedVector4Array([Vector4(0.0, -124.0, 13.0, 7.0), Vector4(-118.0, -64.0, 9.0, 5.0),
		Vector4(-118.0, -64.0, 4.0, 4.0), Vector4(116.0, -70.0, 8.0, 6.0)])
	_map.ridge_starts = PackedVector4Array([Vector4(60.0, -120.0, 120.0, -60.0), Vector4(-120.0, 40.0, -60.0, 118.0)])
	_map.ridge_shapes = PackedVector2Array([Vector2(12.0, 6.0), Vector2(10.0, 5.0)])
	_map.paths = PackedVector4Array([
		Vector4(0.0, -30.0, 0.0, -84.0), Vector4(0.0, 30.0, 0.0, 120.0), Vector4(30.0, 0.0, 128.0, 0.0),
		Vector4(-30.0, 0.0, -128.0, 0.0), Vector4(22.0, -20.0, 64.0, -34.0), Vector4(-20.0, 22.0, -84.0, 82.0),
		Vector4(20.0, 22.0, 88.0, 74.0), Vector4(-8.0, -84.0, 8.0, -84.0), Vector4(-12.0, -74.0, 12.0, -74.0)])
	_square()
	_amt()
	_village()
	_church()
	_farm()
	_chapel()
	_spots()
	_forest()
	if _problems > 0:
		push_error("%d overlaps, not saved" % _problems)
		quit(1)
		return
	var error: Error = ResourceSaver.save(_map, OUT)
	print("saved %s: %d structures, %d wirtshaus spots, %d stempel spots, %d chest spots (error %d)" % [
		OUT, _map.structures.size(), _map.wirtshaus_spots.size(), _map.stempel_spots.size(), _map.chest_spots.size(), error])
	quit(0 if error == OK else 1)


func _square() -> void:
	_put(MapStructure.Kind.KNODL_STAND, Vector2(0.0, -3.0), 0.0, Vector3(5.0, 2.8, 3.0), Color(0.62, 0.44, 0.27), Color(0.95, 0.8, 0.35), 3.0)
	_put(MapStructure.Kind.MAIBAUM, Vector2(0.0, -17.0), 0.0, Vector3(1.0, 24.0, 1.0), Color(0.96, 0.95, 0.9), Color(0.25, 0.55, 0.3), 1.5)
	_put(MapStructure.Kind.FOUNTAIN, Vector2(13.0, 11.0), 0.0, Vector3(4.2, 0.0, 4.2), Color(0.7, 0.69, 0.66), Color.WHITE, 2.4)
	_put(MapStructure.Kind.TENT, Vector2(-25.0, -4.0), 90.0, Vector3(16.0, 3.4, 10.0), CANVAS, BLUE, 8.5)
	_put(MapStructure.Kind.TENT, Vector2(25.0, -4.0), -90.0, Vector3(16.0, 3.4, 10.0), CANVAS, Color(0.3, 0.6, 0.35), 8.5)
	_put(MapStructure.Kind.BANDSTAND, Vector2(-17.0, -21.0), _facing(Vector2(-17.0, -21.0)), Vector3(8.0, 3.0, 8.0), Color(0.62, 0.45, 0.28), ROOF_GREEN, 5.5)
	var stall_colors: Array[Color] = [Color(0.95, 0.8, 0.35), Color(0.55, 0.42, 0.75), Color(0.35, 0.65, 0.8), Color(0.45, 0.7, 0.4), Color(0.95, 0.6, 0.3)]
	var stall_spots: Array[Vector2] = [Vector2(-18.0, 20.0), Vector2(-7.0, 25.0), Vector2(7.0, 25.0), Vector2(18.0, 20.0), Vector2(17.0, -21.0)]
	for k: int in stall_spots.size():
		_put(MapStructure.Kind.STALL, stall_spots[k], _facing(stall_spots[k]), Vector3(4.0, 2.6, 2.6), WOOD.lightened(0.1), stall_colors[k], 2.6)
	_put(MapStructure.Kind.CRATES, Vector2(-11.0, 9.0), 20.0, Vector3.ONE, WOOD, WOOD, 1.8)
	_put(MapStructure.Kind.CRATES, Vector2(9.0, -10.0), -35.0, Vector3.ONE, WOOD, WOOD, 1.8)
	for k: int in 4:
		var at := Vector2(-6.0 + k * 4.0, 15.0)
		_put(MapStructure.Kind.BENCH, at, 0.0, Vector3(2.4, 0.45, 0.5), WOOD, WOOD, 1.2)


func _amt() -> void:
	_put(MapStructure.Kind.AMT, Vector2(0.0, -92.0), 0.0, Vector3(24.0, 7.5, 12.0), Color(0.93, 0.88, 0.7), ROOF_DARK, 13.5)
	for x: float in [-16.0, 16.0]:
		_put(MapStructure.Kind.FRUIT_TREE, Vector2(x, -78.0), 0.0, Vector3(1.0, 6.0, 1.0), Color(0.36, 0.58, 0.26), Color(0.95, 0.8, 0.3), 2.0)
	_put(MapStructure.Kind.FENCE, Vector2(-22.0, -70.0), 90.0, Vector3(16.0, 1.0, 0.2), WOOD, WOOD, 0.0)
	_put(MapStructure.Kind.FENCE, Vector2(22.0, -70.0), 90.0, Vector3(16.0, 1.0, 0.2), WOOD, WOOD, 0.0)


func _village() -> void:
	var walls: Array[Color] = [WALL, WALL_YELLOW, WALL_PINK, WALL_GREEN, WALL]
	var roofs: Array[Color] = [ROOF_BROWN, ROOF_DARK, ROOF_BROWN, ROOF_GREEN, ROOF_DARK]
	var k: int = 0
	# Houses along the four roads, facing the road.
	for d: float in [48.0, 66.0, 86.0, 106.0]:
		for side: float in [-1.0, 1.0]:
			_house(Vector2(d, side * 15.0), 0.0 if side < 0.0 else 180.0, walls[k % 5], roofs[k % 5])
			k += 1
			_house(Vector2(-d, side * 15.0), 0.0 if side < 0.0 else 180.0, walls[k % 5], roofs[k % 5])
			k += 1
			_house(Vector2(side * 15.0, d), 90.0 if side < 0.0 else -90.0, walls[k % 5], roofs[k % 5])
			k += 1
	for d: float in [46.0, 60.0]:
		for side: float in [-1.0, 1.0]:
			_house(Vector2(side * 16.0, -d), 90.0 if side < 0.0 else -90.0, walls[k % 5], roofs[k % 5])
			k += 1


func _house(at: Vector2, yaw: float, wall: Color, roof: Color) -> void:
	var tall: bool = int(absf(at.x) + absf(at.y)) % 3 == 0
	_put(MapStructure.Kind.HOUSE, at, yaw, Vector3(8.0, 6.2 if tall else 3.6, 7.0), wall, roof, 5.6)


func _church() -> void:
	var at := Vector2(68.0, -44.0)
	_put(MapStructure.Kind.CHURCH, at, _facing(at), Vector3(11.0, 9.0, 20.0), Color(0.97, 0.95, 0.9), ROOF_DARK, 13.0)
	for k: int in 3:
		_put(MapStructure.Kind.FIR, at + Vector2(-14.0 + k * 3.0, 14.0 + k * 2.0), 0.0, Vector3(1.0, 8.0, 1.0), StructureKit.FIR_GREEN, Color.WHITE, 1.2)


func _farm() -> void:
	_put(MapStructure.Kind.BARN, Vector2(98.0, 86.0), _facing(Vector2(98.0, 86.0)), Vector3(12.0, 5.0, 9.0), Color(0.6, 0.42, 0.26), ROOF_BROWN, 9.0)
	_put(MapStructure.Kind.HOUSE, Vector2(76.0, 100.0), _facing(Vector2(76.0, 100.0)), Vector3(9.0, 6.2, 8.0), WALL, ROOF_BROWN, 6.5)
	for row: int in 3:
		for col: int in 4:
			_put(MapStructure.Kind.FRUIT_TREE, Vector2(62.0 + col * 7.0, 52.0 + row * 7.5), 0.0, Vector3(1.0, 5.0 + (row + col) % 2, 1.0),
					Color(0.36, 0.58, 0.26), Color(0.95, 0.8, 0.3) if (row + col) % 2 == 0 else Color(0.85, 0.85, 0.35), 1.6)
	_put(MapStructure.Kind.FENCE, Vector2(70.0, 44.0), 0.0, Vector3(26.0, 1.0, 0.2), WOOD, WOOD, 0.0)
	_put(MapStructure.Kind.FENCE, Vector2(56.0, 60.0), 90.0, Vector3(26.0, 1.0, 0.2), WOOD, WOOD, 0.0)


func _chapel() -> void:
	_put(MapStructure.Kind.CHAPEL, Vector2(-92.0, 88.0), _facing(Vector2(-92.0, 88.0)), Vector3(5.0, 4.0, 7.0), Color(0.97, 0.95, 0.9), ROOF_DARK, 5.0)
	for k: int in 5:
		var angle: float = TAU * k / 5.0
		_put(MapStructure.Kind.FIR, Vector2(-92.0, 88.0) + Vector2(cos(angle), sin(angle)) * 11.0, 0.0,
				Vector3(1.0, 9.0 + k % 3, 1.0), StructureKit.FIR_GREEN, Color.WHITE, 1.2)


## Fir forest between the village and the mountains (seeded, so it is the same every time).
func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1848
	var placed: int = 0
	var tries: int = 0
	while placed < 90 and tries < 5000:
		tries += 1
		var at := Vector2(rng.randf_range(-128.0, 128.0), rng.randf_range(-128.0, 128.0))
		var edge: float = maxf(absf(at.x), absf(at.y))
		if edge < 92.0 or _blocked(at, 3.5) or _near_path(at, 6.0):
			continue
		var height: float = rng.randf_range(8.0, 13.0)
		var green: Color = StructureKit.FIR_GREEN.lightened(rng.randf_range(-0.05, 0.12))
		_put(MapStructure.Kind.FIR, at, rng.randf_range(0.0, 90.0), Vector3(1.0, height, 1.0), green, Color.WHITE, 1.2)
		placed += 1


func _spots() -> void:
	# Wirtshäuser (7 x 6 m houses, built by Wirtshaus.building_props); a run opens 3 of them.
	var wirts: Array[Vector2] = [Vector2(38.0, 36.0), Vector2(-40.0, 38.0), Vector2(-42.0, -38.0), Vector2(116.0, 30.0),
		Vector2(-116.0, -32.0), Vector2(30.0, 112.0), Vector2(40.0, -100.0)]
	for at: Vector2 in wirts:
		_claim(at, 6.0, "Wirtshaus")
	_map.wirtshaus_spots = PackedVector2Array(wirts)
	_map.stempel_spots = PackedVector2Array([Vector2(-92.0, 80.0), Vector2(98.0, 86.0), Vector2(-30.0, -30.0),
		Vector2(68.0, -26.0), Vector2(118.0, -4.0), Vector2(-120.0, 8.0), Vector2(-6.0, 118.0), Vector2(98.0, -94.0),
		Vector2(-70.0, -100.0)])
	_map.chest_spots = PackedVector2Array([Vector2(-36.0, -4.0), Vector2(36.0, -4.0), Vector2(56.0, 8.0), Vector2(-56.0, -8.0),
		Vector2(8.0, 56.0), Vector2(-8.0, -54.0), Vector2(80.0, 62.0), Vector2(-60.0, 60.0), Vector2(60.0, -66.0),
		Vector2(-80.0, -60.0), Vector2(100.0, -40.0), Vector2(-100.0, 40.0), Vector2(20.0, 92.0), Vector2(-30.0, -86.0),
		Vector2(0.0, -124.0), Vector2(-118.0, -64.0), Vector2(116.0, -70.0)])
	for at: Vector2 in _map.stempel_spots:
		_check_free(at, "stempel")
	for at: Vector2 in _map.chest_spots:
		_check_free(at, "chest")
	_map.bot_waypoints = PackedVector2Array([Vector2(0.0, 6.0), Vector2(0.0, 40.0), Vector2(30.0, 60.0), Vector2(60.0, 30.0),
		Vector2(90.0, 0.0), Vector2(60.0, -20.0), Vector2(30.0, -40.0), Vector2(0.0, -64.0), Vector2(-30.0, -50.0),
		Vector2(-60.0, -20.0), Vector2(-90.0, 0.0), Vector2(-60.0, 30.0), Vector2(-30.0, 60.0), Vector2(0.0, 30.0)])


## Turns a structure at `at` so its front faces the centre of the map.
func _facing(at: Vector2) -> float:
	return rad_to_deg(atan2(-at.x, -at.y))


func _put(kind: MapStructure.Kind, at: Vector2, yaw: float, size: Vector3, color: Color, accent: Color, radius: float) -> void:
	if radius > 0.0:
		_claim(at, radius, MapStructure.Kind.keys()[kind])
	var structure := MapStructure.new()
	structure.kind = kind
	structure.position = at
	structure.yaw_degrees = yaw
	structure.size = size
	structure.color = color
	structure.accent = accent
	_map.structures.append(structure)


func _claim(at: Vector2, radius: float, what: String) -> void:
	for other: Vector3 in _taken:
		if at.distance_to(Vector2(other.x, other.y)) < radius + other.z - 0.5:
			push_error("%s at %s overlaps something at (%.0f, %.0f)" % [what, at, other.x, other.y])
			_problems += 1
	_taken.append(Vector3(at.x, at.y, radius))


func _blocked(at: Vector2, radius: float) -> bool:
	for other: Vector3 in _taken:
		if at.distance_to(Vector2(other.x, other.y)) < radius + other.z:
			return true
	for list: PackedVector2Array in [_map.wirtshaus_spots, _map.stempel_spots, _map.chest_spots]:
		for spot: Vector2 in list:
			if at.distance_to(spot) < radius + 8.0:
				return true
	return false


func _near_path(at: Vector2, margin: float) -> bool:
	return _map.path_cover(at.x, at.y) > 0.0 or _map.path_cover(at.x + margin, at.y) > 0.0 or _map.path_cover(at.x - margin, at.y) > 0.0 \
			or _map.path_cover(at.x, at.y + margin) > 0.0 or _map.path_cover(at.x, at.y - margin) > 0.0


## A Stempel or chest spot must not be inside a building (it may be on a roof or a platform).
func _check_free(at: Vector2, what: String) -> void:
	for other: Vector3 in _taken:
		var d: float = at.distance_to(Vector2(other.x, other.y))
		if d < other.z * 0.6 and d > 0.5:
			push_warning("%s spot %s is close to the middle of something at (%.0f, %.0f)" % [what, at, other.x, other.y])
