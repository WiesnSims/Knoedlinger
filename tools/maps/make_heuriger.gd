extends SceneTree
## Lays out the Heuriger in den Weinbergen (GAME-DESIGN.md map 4, plan for 1.4.0 task 1.1: terraced
## vineyards on several levels, the Knödl rolls down the terraces) and saves data/maps/heuriger.tres:
##   godot --headless --path . -s tools/maps/make_heuriger.gd
##
## The Weinberg fills the north: five round terraces of 3 m each round one hilltop, with the
## Presshaus and the boss gate on top. Ramps lead from terrace to terrace, turned a bit further round
## on every level, so the way up winds; two Kellergassen cut straight up from the foot to the fourth
## terrace (the shortcuts), with cellar portals where they cross a terrace wall. The Heurigen-Ort with
## the family's Knödl stand is the spawn in the south; two small vineyard hills stand east and west.
## Buschenschanken are the Wirtshäuser, Stempel lie on the terrace tops.

const OUT: String = "res://data/maps/heuriger.tres"
const HILL := Vector2(0.0, -40.0)
## Terrace edge radii from the foot up, and the height of each step.
const TERRACES: Array[float] = [74.0, 60.0, 47.0, 34.0, 21.0]
const STEP: float = 3.0
const EDGE: float = 2.5
## Kellergassen: their direction from the hilltop (degrees, 0 = +x, 90 = +z), the radius they start
## at the foot and end at on the fourth terrace, and their half width.
const LANE_ANGLES: Array[float] = [45.0, 135.0]
const LANE_FROM: float = 82.0
const LANE_TO: float = 27.0
const LANE_HALF: float = 3.5
## Ramps per terrace edge (degrees round the hilltop); kept clear of the Kellergassen.
const RAMPS: Array = [[90.0, 210.0, 330.0], [0.0, 180.0, 270.0], [100.0, 220.0, 320.0], [10.0, 170.0, 270.0], [90.0, 250.0]]
const SIDE_HILLS: Array[Vector2] = [Vector2(92.0, 62.0), Vector2(-95.0, 56.0)]
const SIDE_TERRACES: Array[float] = [24.0, 12.0]

const PLASTER := Color(0.95, 0.92, 0.8)
const WOOD := Color(0.5, 0.34, 0.2)
const ROOF := Color(0.62, 0.3, 0.18)
const STONE := Color(0.72, 0.66, 0.55)
const VINE := Color(0.36, 0.55, 0.22)

var _map := MapData.new()
var _kit := MapKit.new(_map)


func _init() -> void:
	_map.id = &"heuriger"
	_map.name_key = "MAP_HEURIGER"
	_map.wave = load("res://data/waves/heuriger.tres")
	_map.music = &"heuriger"
	_map.wirtshaus_buschen = true
	_map.half_size = 150.0
	_map.terrain_samples = 256
	_map.ground_cell = 0.5
	_map.noise_seed = 41
	_map.noise_amplitude = 0.5
	_map.noise_frequency = 0.03
	_map.flat_radius = 140.0
	_map.flat_blend = 10.0
	_map.rim_start = 124.0
	_map.rim_height = 26.0
	_map.spawn_point = Vector3(0.0, 0.0, 86.0)
	_map.portal_point = HILL + Vector2(0.0, 10.0)
	_map.grass_color = Color(0.5, 0.62, 0.3)
	_map.meadow_color = Color(0.6, 0.68, 0.34)
	_map.rock_color = Color(0.66, 0.58, 0.44)
	_map.dirt_color = Color(0.62, 0.5, 0.34)
	_map.path_color = Color(0.78, 0.7, 0.55)
	_map.path_width = 6.0
	_map.sky_color = Color(0.62, 0.78, 0.95)
	_map.plaza_radius = 0.0
	_map.mesa_edge = EDGE
	var mesas := PackedVector4Array()
	for r: float in TERRACES:
		mesas.append(Vector4(HILL.x, HILL.y, r, STEP))
	for centre: Vector2 in SIDE_HILLS:
		for r: float in SIDE_TERRACES:
			mesas.append(Vector4(centre.x, centre.y, r, STEP))
	_map.mesas = mesas
	var lanes := PackedVector4Array()
	var shapes := PackedVector3Array()
	for angle: float in LANE_ANGLES:
		var from: Vector2 = _polar(HILL, angle, LANE_FROM)
		var to: Vector2 = _polar(HILL, angle, LANE_TO)
		lanes.append(Vector4(from.x, from.y, to.x, to.y))
		shapes.append(Vector3(LANE_HALF, 0.0, STEP * 4.0))
	_map.lanes = lanes
	_map.lane_shapes = shapes
	# The village street, the way up to the foot of the Weinberg and to the side hills.
	_map.paths = PackedVector4Array([
		Vector4(-110.0, 100.0, 110.0, 100.0), Vector4(0.0, 100.0, 0.0, 38.0),
		Vector4(_polar(HILL, 45.0, LANE_FROM).x, _polar(HILL, 45.0, LANE_FROM).y, 40.0, 100.0),
		Vector4(_polar(HILL, 135.0, LANE_FROM).x, _polar(HILL, 135.0, LANE_FROM).y, -40.0, 100.0),
		Vector4(60.0, 100.0, 80.0, 86.0), Vector4(-60.0, 100.0, -84.0, 82.0)])
	_village()
	_presshaus()
	_ramps()
	_kellergassen()
	_spots()
	_vines()
	_kit.forest(4107, 70, 118.0, 136.0, StructureKit.FIR_GREEN)
	quit(_kit.save(OUT))


## A point `r` metres from `centre` toward `angle` degrees (0 = +x, 90 = +z).
func _polar(centre: Vector2, angle: float, r: float) -> Vector2:
	return centre + Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * r


func _village() -> void:
	_kit.put(MapStructure.Kind.KNODL_STAND, Vector2(0.0, 78.0), 0.0, Vector3(5.0, 2.8, 3.0), Color(0.62, 0.44, 0.27), Color(0.95, 0.8, 0.35), 3.0)
	for k: int in 6:
		var x: float = -100.0 + k * 40.0
		if absf(x) < 10.0:
			continue
		_kit.put(MapStructure.Kind.HOUSE, Vector2(x, 114.0), 180.0, Vector3(11.0, 4.5, 8.0), PLASTER if k % 2 == 0 else PLASTER.darkened(0.06), ROOF, 7.0)
	# The Heurigen garden by the stand: long tables under a tent and nut trees.
	_kit.put(MapStructure.Kind.TENT, Vector2(-22.0, 84.0), 90.0, Vector3(10.0, 4.0, 7.0), Color(0.95, 0.94, 0.9), Color(0.3, 0.55, 0.3), 6.0)
	for k: int in 4:
		_kit.put(MapStructure.Kind.BENCH, Vector2(10.0 + (k % 2) * 6.0, 84.0 + (k / 2) * 4.0), 0.0, Vector3(3.0, 0.45, 0.6), WOOD, WOOD, 1.5)
	for at: Vector2 in [Vector2(-40.0, 78.0), Vector2(30.0, 72.0), Vector2(78.0, 92.0), Vector2(-80.0, 90.0)]:
		_kit.put(MapStructure.Kind.FRUIT_TREE, at, 0.0, Vector3(1.0, 7.0, 1.0), Color(0.34, 0.52, 0.24), Color(0.5, 0.4, 0.25), 2.0)
	_kit.put(MapStructure.Kind.CHAPEL, Vector2(48.0, 62.0), 200.0, Vector3(5.0, 4.0, 6.0), PLASTER, ROOF, 4.0)


## The Presshaus on the hilltop holds the boss gate.
func _presshaus() -> void:
	_kit.put(MapStructure.Kind.AMT, HILL + Vector2(0.0, -8.0), 0.0, Vector3(18.0, 6.0, 9.0), PLASTER, ROOF, 10.5)


## Ramps up every terrace edge, the foot just outside the edge, the top on the terrace above.
func _ramps() -> void:
	for level: int in TERRACES.size():
		for angle: float in RAMPS[level]:
			_ramp(HILL, TERRACES[level], STEP * level, angle)
	for centre: Vector2 in SIDE_HILLS:
		for level: int in SIDE_TERRACES.size():
			for angle: float in [100.0 + level * 140.0, 280.0 + level * 140.0]:
				_ramp(centre, SIDE_TERRACES[level], STEP * level, angle)


func _ramp(centre: Vector2, radius: float, foot: float, angle: float) -> void:
	var at: Vector2 = _polar(centre, angle, radius + EDGE * 0.5)
	var inward: Vector2 = (centre - at).normalized()
	_kit.claim(at, 4.5, "ramp")
	_kit.prop(MapProp.Kind.RAMP, at, foot - _map.terrain_height(at.x, at.y), Vector3(5.0, STEP, 9.0),
			rad_to_deg(atan2(inward.x, inward.y)), STONE)


## Cellar portals where each Kellergasse crosses a terrace wall, Presshäuser at its foot.
func _kellergassen() -> void:
	for angle: float in LANE_ANGLES:
		var from: Vector2 = _polar(HILL, angle, LANE_FROM)
		var to: Vector2 = _polar(HILL, angle, LANE_TO)
		var along: Vector2 = (to - from).normalized()
		var across := Vector2(-along.y, along.x)
		var yaw: float = rad_to_deg(atan2(along.x, along.y))
		for level: int in 4:
			var at: Vector2 = _polar(HILL, angle, TERRACES[level] + EDGE * 0.5)
			var t: float = clampf((at - from).dot(to - from) / (to - from).length_squared(), 0.0, 1.0)
			var floor_y: float = lerpf(0.0, STEP * 4.0, t)
			for side: float in [-1.0, 1.0]:
				var pillar: Vector2 = at + across * side * (LANE_HALF + 0.7)
				_kit.prop(MapProp.Kind.BLOCK, pillar, floor_y - _map.terrain_height(pillar.x, pillar.y), Vector3(1.2, 5.2, 1.6), yaw, STONE)
			_kit.prop(MapProp.Kind.BLOCK, at, floor_y + 4.4 - _map.terrain_height(at.x, at.y),
					Vector3(LANE_HALF * 2.0 + 2.6, 0.8, 1.6), yaw, STONE.darkened(0.1), true, true)
		# Presshäuser on both sides of the foot of the lane.
		for side: float in [-1.0, 1.0]:
			var house: Vector2 = from + along * 2.0 + across * side * (LANE_HALF + 6.0)
			_kit.put(MapStructure.Kind.HOUSE, house, yaw + 90.0 * side, Vector3(6.0, 3.4, 5.0), PLASTER, ROOF, 4.2)


## Rows of vines across the terraces, with gaps so the Knödl can roll down.
func _vines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1848
	for level: int in TERRACES.size():
		var inner: float = (TERRACES[level + 1] + EDGE) if level + 1 < TERRACES.size() else 0.0
		if inner <= 0.0:
			continue
		var middle: float = (inner + TERRACES[level]) * 0.5
		var rows: int = int(middle * TAU / 14.0)
		for k: int in rows:
			var angle: float = 360.0 * k / rows + level * 7.0
			var at: Vector2 = _polar(HILL, angle, middle)
			if _kit.blocked(at, 3.0) or _near_lane(at, 5.0) or rng.randf() < 0.25:
				continue
			_kit.put(MapStructure.Kind.FENCE, at, 90.0 - angle, Vector3(4.5, 1.3, 0.3), VINE.lightened(rng.randf_range(-0.05, 0.1)), VINE, 2.4)


func _near_lane(at: Vector2, margin: float) -> bool:
	for k: int in _map.lanes.size():
		var line: Vector4 = _map.lanes[k]
		var a := Vector2(line.x, line.y)
		var ab: Vector2 = Vector2(line.z, line.w) - a
		var t: float = clampf((at - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if at.distance_to(a + ab * t) < LANE_HALF + margin:
			return true
	return false


func _spots() -> void:
	# Buschenschanken: in the village, at the foot of the Weinberg, on the first terrace and by the
	# side hills.
	var wirts: Array[Vector2] = [Vector2(36.0, 88.0), Vector2(-50.0, 92.0), _polar(HILL, 180.0, 80.0), _polar(HILL, 0.0, 80.0),
		_polar(HILL, 270.0, 82.0), _polar(HILL, 300.0, 67.5), Vector2(108.0, 18.0), Vector2(-108.0, 6.0)]
	for at: Vector2 in wirts:
		_kit.claim(at, 6.0, "Wirtshaus")
	_map.wirtshaus_spots = PackedVector2Array(wirts)
	# Stempel on the terrace tops and the side hills.
	_map.stempel_spots = PackedVector2Array([_polar(HILL, 20.0, 28.0), _polar(HILL, 200.0, 28.0), _polar(HILL, 300.0, 40.5),
		_polar(HILL, 160.0, 54.0), _polar(HILL, 240.0, 67.5), SIDE_HILLS[0], SIDE_HILLS[1], _polar(HILL, 60.0, 67.5),
		_polar(HILL, 340.0, 54.0)])
	_map.chest_spots = PackedVector2Array([Vector2(-20.0, 60.0), Vector2(24.0, 50.0), _polar(HILL, 120.0, 67.5),
		_polar(HILL, 20.0, 54.0), _polar(HILL, 250.0, 40.5), _polar(HILL, 75.0, 28.0), _polar(HILL, 150.0, 15.0),
		Vector2(92.0, 40.0), Vector2(-95.0, 34.0), Vector2(-100.0, -60.0), Vector2(100.0, -60.0), Vector2(30.0, -115.0),
		Vector2(-80.0, 108.0), Vector2(80.0, 108.0)])
	_map.bot_waypoints = PackedVector2Array([Vector2(0.0, 86.0), _polar(HILL, 45.0, LANE_FROM), _polar(HILL, 45.0, LANE_TO),
		_polar(HILL, 90.0, 10.0), _polar(HILL, 135.0, LANE_TO), _polar(HILL, 135.0, LANE_FROM), Vector2(-95.0, 56.0),
		Vector2(-40.0, 96.0), Vector2(40.0, 96.0), Vector2(92.0, 62.0), _polar(HILL, 0.0, 80.0), _polar(HILL, 180.0, 80.0)])
