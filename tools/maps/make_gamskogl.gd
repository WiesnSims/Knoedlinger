extends SceneTree
## Lays out the Gamskogl-Piste (GAME-DESIGN.md map 2: a ski slope with lifts, steep climbs and drops;
## slopes make the Knödl deadly; the Lawine mini-boss) and saves data/maps/gamskogl.tres:
##   godot --headless --path . -s tools/maps/make_gamskogl.gd
##
## The whole map leans uphill to the north (-z). The Talstation with the family's Knödl stand is the
## spawn at the bottom; groomed pistes zig-zag up past the Mittelstation and the Schneebar, whose
## plateaus stand on top of each other (several levels, real drops), to the Bergstation at the top,
## where the boss gate is. High ground is safe-ish (enemies climb slowly) and holds the Stempel.

const OUT: String = "res://data/maps/gamskogl.tres"
const SNOW := Color(0.93, 0.95, 0.98)
const WOOD := Color(0.45, 0.3, 0.18)
const ROOF := Color(0.3, 0.24, 0.2)
const RED_HUT := Color(0.72, 0.28, 0.24)

var _map := MapData.new()
var _kit := MapKit.new(_map)


func _init() -> void:
	_map.id = &"gamskogl"
	_map.name_key = "MAP_GAMSKOGL"
	_map.wave = load("res://data/waves/gamskogl.tres")
	_map.half_size = 150.0
	_map.terrain_samples = 256
	_map.ground_cell = 0.5
	_map.noise_seed = 23
	_map.noise_amplitude = 1.6
	_map.noise_frequency = 0.03
	_map.flat_radius = 0.0
	_map.flat_blend = 1.0
	_map.rim_start = 120.0
	_map.rim_height = 34.0
	_map.tilt = Vector2(0.0, -0.17)
	_map.spawn_point = Vector3(0.0, 0.0, 84.0)
	_map.portal_point = Vector2(0.0, -96.0)
	_map.grass_color = SNOW
	_map.meadow_color = Color(0.86, 0.9, 0.97)
	_map.rock_color = Color(0.5, 0.5, 0.53)
	_map.dirt_color = Color(0.78, 0.82, 0.9)
	_map.path_color = Color(0.98, 0.98, 1.0)
	_map.path_width = 9.0
	_map.sky_color = Color(0.55, 0.72, 0.95)
	_map.plaza_radius = 0.0
	# Plateaus: the Talstation terrace, the Mittelstation west with a ledge on it, the Schneebar east
	# with a lookout on top (three levels), the Bergstation at the top, and two hut shelves.
	_map.mesa_edge = 3.5
	_map.mesas = PackedVector4Array([
		Vector4(0.0, 84.0, 22.0, 2.0),
		Vector4(-52.0, -10.0, 30.0, 6.0), Vector4(-60.0, -18.0, 12.0, 5.0),
		Vector4(56.0, -40.0, 26.0, 7.0), Vector4(60.0, -44.0, 13.0, 6.0), Vector4(62.0, -46.0, 5.0, 5.0),
		Vector4(0.0, -100.0, 30.0, 6.0),
		Vector4(-80.0, 60.0, 16.0, 4.0), Vector4(84.0, 44.0, 18.0, 4.0)])
	# Moguls on the pistes and a ridge between them.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var hills := PackedVector4Array()
	for k: int in 18:
		hills.append(Vector4(rng.randf_range(-40.0, 40.0), rng.randf_range(-70.0, 60.0), rng.randf_range(4.0, 7.0), rng.randf_range(0.8, 1.6)))
	_map.hills = hills
	_map.ridge_starts = PackedVector4Array([Vector4(10.0, 40.0, 24.0, -70.0)])
	_map.ridge_shapes = PackedVector2Array([Vector2(7.0, 3.0)])
	# The pistes: a zig-zag from the Bergstation down to the Talstation, and a black one straight down.
	_map.paths = PackedVector4Array([
		Vector4(0.0, -84.0, -40.0, -40.0), Vector4(-40.0, -40.0, 30.0, 0.0), Vector4(30.0, 0.0, -30.0, 40.0),
		Vector4(-30.0, 40.0, 0.0, 72.0), Vector4(0.0, -84.0, 40.0, -10.0), Vector4(40.0, -10.0, 12.0, 70.0)])
	_talstation()
	_lift()
	_huts()
	_kickers()
	_spots()
	_kit.forest(2306, 110, 70.0, 130.0, StructureKit.FIR_GREEN.darkened(0.1))
	quit(_kit.save(OUT))


func _talstation() -> void:
	_kit.put(MapStructure.Kind.KNODL_STAND, Vector2(0.0, 78.0), 0.0, Vector3(5.0, 2.8, 3.0), Color(0.62, 0.44, 0.27), Color(0.95, 0.8, 0.35), 3.0)
	_kit.put(MapStructure.Kind.HOUSE, Vector2(-16.0, 96.0), 180.0, Vector3(12.0, 5.0, 8.0), WOOD, ROOF, 7.0)
	_kit.put(MapStructure.Kind.STALL, Vector2(14.0, 92.0), 200.0, Vector3(4.0, 2.6, 2.6), WOOD.lightened(0.15), Color(0.35, 0.6, 0.85), 2.6)
	for k: int in 4:
		_kit.put(MapStructure.Kind.BENCH, Vector2(-6.0 + k * 4.0, 92.0), 0.0, Vector3(2.4, 0.45, 0.5), WOOD, WOOD, 1.2)
	# The Bergstation at the top holds the boss gate.
	_kit.put(MapStructure.Kind.AMT, Vector2(0.0, -112.0), 0.0, Vector3(22.0, 7.0, 11.0), Color(0.82, 0.8, 0.76), ROOF, 12.5)


## Lift pylons from the Talstation to the Bergstation.
func _lift() -> void:
	for k: int in 7:
		var at := Vector2(-22.0 + k * 0.6, 70.0 - k * 26.0)
		if _kit.blocked(at, 1.5):
			continue
		_kit.put(MapStructure.Kind.MAIBAUM, at, 0.0, Vector3(0.8, 14.0, 0.8), Color(0.55, 0.57, 0.6), Color(0.55, 0.57, 0.6), 1.2)


func _huts() -> void:
	var spots: Array[Vector2] = [Vector2(-66.0, -4.0), Vector2(70.0, -30.0), Vector2(-86.0, 72.0), Vector2(92.0, 56.0),
		Vector2(-30.0, -70.0), Vector2(30.0, -76.0)]
	for k: int in spots.size():
		_kit.put(MapStructure.Kind.HOUSE, spots[k], _kit.facing(spots[k]), Vector3(8.0, 3.6, 7.0), RED_HUT if k % 2 == 0 else WOOD, ROOF, 5.6)


## Kickers on the pistes: run up one and the Knödl flies.
func _kickers() -> void:
	for at: Vector2 in [Vector2(-10.0, 20.0), Vector2(20.0, 30.0), Vector2(-6.0, -62.0)]:
		_kit.claim(at, 4.0, "kicker")
		_kit.prop(MapProp.Kind.RAMP, at, 0.0, Vector3(6.0, 2.2, 8.0), 180.0, Color(0.9, 0.93, 0.98))


func _spots() -> void:
	var wirts: Array[Vector2] = [Vector2(28.0, 60.0), Vector2(-40.0, 30.0), Vector2(-50.0, -36.0), Vector2(48.0, 10.0),
		Vector2(-104.0, -30.0), Vector2(104.0, -8.0), Vector2(46.0, -90.0)]
	for at: Vector2 in wirts:
		_kit.claim(at, 6.0, "Wirtshaus")
	_map.wirtshaus_spots = PackedVector2Array(wirts)
	# Stempel up high: the Schneebar lookout, the Mittelstation ledge, the hut shelves, the top.
	_map.stempel_spots = PackedVector2Array([Vector2(62.0, -46.0), Vector2(-60.0, -18.0), Vector2(-80.0, 54.0),
		Vector2(84.0, 36.0), Vector2(-24.0, -96.0), Vector2(24.0, -100.0), Vector2(-100.0, 20.0), Vector2(104.0, -60.0),
		Vector2(0.0, 30.0)])
	_map.chest_spots = PackedVector2Array([Vector2(-20.0, 60.0), Vector2(20.0, 40.0), Vector2(-52.0, 4.0), Vector2(56.0, -24.0),
		Vector2(0.0, -40.0), Vector2(-36.0, -80.0), Vector2(36.0, -60.0), Vector2(-90.0, 40.0), Vector2(90.0, 20.0),
		Vector2(-70.0, -60.0), Vector2(74.0, -70.0), Vector2(0.0, -120.0), Vector2(-60.0, 90.0), Vector2(60.0, 90.0)])
	_map.bot_waypoints = PackedVector2Array([Vector2(0.0, 84.0), Vector2(-30.0, 40.0), Vector2(30.0, 0.0), Vector2(-40.0, -40.0),
		Vector2(0.0, -84.0), Vector2(40.0, -10.0), Vector2(60.0, 30.0), Vector2(12.0, 70.0), Vector2(-60.0, 60.0),
		Vector2(-52.0, -10.0)])
