extends SceneTree
## Lays out the Gemeindebau-Hof (GAME-DESIGN.md map 3: a Viennese council block courtyard with stairs,
## balconies and laundry lines; vertical routes over several levels) and saves
## data/maps/gemeindebau.tres:
##   godot --headless --path . -s tools/maps/make_gemeindebau.gd
##
## The big Hof in the middle is ringed by four flat-roofed blocks, 14 m high, with a gate gap in each
## side. Ramps and stairs inside the Hof lead up onto the roofs, which run all the way round: the
## high route (enemies climb walls slowly). The courtyard itself has a raised garden in two tiers and
## laundry lines. Outside: streets, lower blocks whose roofs can be reached by stairs, the
## Hausverwaltung with the boss gate in the north, Beisln as the Wirtshäuser.

const OUT: String = "res://data/maps/gemeindebau.tres"
const FACADE := Color(0.86, 0.78, 0.62)
const FACADE_RED := Color(0.78, 0.5, 0.38)
const ROOF_GREY := Color(0.5, 0.5, 0.52)
const WINDOW := Color(0.35, 0.42, 0.5)
const STONE := Color(0.7, 0.68, 0.64)
const WOOD := Color(0.55, 0.38, 0.22)
const HOF_HALF: float = 44.0
const BLOCK_DEPTH: float = 12.0
const BLOCK_HEIGHT: float = 14.0
const GATE: float = 10.0

var _map := MapData.new()
var _kit := MapKit.new(_map)


func _init() -> void:
	_map.id = &"gemeindebau"
	_map.name_key = "MAP_GEMEINDEBAU"
	_map.wave = load("res://data/waves/gemeindebau.tres")
	_map.music = &"gemeindebau"
	_map.half_size = 150.0
	_map.terrain_samples = 256
	_map.ground_cell = 0.5
	_map.noise_seed = 31
	_map.noise_amplitude = 0.3
	_map.noise_frequency = 0.02
	_map.flat_radius = 90.0
	_map.flat_blend = 20.0
	_map.rim_start = 128.0
	_map.rim_height = 24.0
	_map.spawn_point = Vector3(0.0, 0.0, 26.0)
	_map.portal_point = Vector2(0.0, -88.0)
	_map.grass_color = Color(0.42, 0.6, 0.32)
	_map.meadow_color = Color(0.5, 0.66, 0.36)
	_map.dirt_color = Color(0.58, 0.56, 0.52)
	_map.path_color = Color(0.5, 0.5, 0.52)
	_map.path_width = 10.0
	_map.plaza_radius = 0.0
	# The raised garden in the Hof: two tiers, 3 m each.
	_map.mesa_edge = 2.5
	_map.mesas = PackedVector4Array([Vector4(0.0, -6.0, 17.0, 3.0), Vector4(0.0, -6.0, 8.0, 3.0)])
	# Streets round the Hof and out to the corners of the map.
	var ring: float = HOF_HALF + BLOCK_DEPTH + 10.0
	_map.paths = PackedVector4Array([
		Vector4(-ring, -ring, ring, -ring), Vector4(ring, -ring, ring, ring), Vector4(ring, ring, -ring, ring),
		Vector4(-ring, ring, -ring, -ring), Vector4(0.0, -ring, 0.0, -120.0), Vector4(0.0, ring, 0.0, 120.0),
		Vector4(ring, 0.0, 120.0, 0.0), Vector4(-ring, 0.0, -120.0, 0.0), Vector4(0.0, HOF_HALF, 0.0, ring),
		Vector4(0.0, -HOF_HALF, 0.0, -ring), Vector4(HOF_HALF, 0.0, ring, 0.0), Vector4(-HOF_HALF, 0.0, -ring, 0.0)])
	_hof()
	_courtyard()
	_outer_blocks()
	_kit.put(MapStructure.Kind.AMT, Vector2(0.0, -104.0), 0.0, Vector3(26.0, 8.0, 12.0), Color(0.88, 0.84, 0.74), Color(0.32, 0.27, 0.25), 14.0)
	_spots()
	_kit.forest(3101, 60, 112.0, 132.0, StructureKit.FIR_GREEN)
	quit(_kit.save(OUT))


## The four blocks round the Hof, each in two halves with the gate gap between, windows on both
## faces (decoration), and the way up inside the Hof.
func _hof() -> void:
	var inner: float = HOF_HALF + BLOCK_DEPTH * 0.5
	var half_length: float = (HOF_HALF * 2.0 + BLOCK_DEPTH * 2.0 - GATE) * 0.25
	for side: int in 4:
		var yaw: float = side * 90.0
		var normal := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		var along := Vector2(normal.y, -normal.x)
		for half: float in [-1.0, 1.0]:
			var offset: float = (GATE * 0.5 + half_length) * half
			var at: Vector2 = normal * inner + along * offset
			_kit.claim(at, 0.1, "block")
			_kit.prop(MapProp.Kind.BLOCK, at, 0.0, Vector3(half_length * 2.0, BLOCK_HEIGHT, BLOCK_DEPTH), yaw,
					FACADE if side % 2 == 0 else FACADE_RED)
			# A low parapet and windows in three rows on both faces (not solid).
			for row: int in 3:
				for col: int in int(half_length / 4.0):
					var x: float = -half_length + 4.0 + col * 8.0
					for face: float in [-1.0, 1.0]:
						var spot: Vector2 = at + along * x * (1.0 if side < 2 else 1.0) + normal * face * (BLOCK_DEPTH * 0.5 + 0.05)
						_kit.prop(MapProp.Kind.BLOCK, spot, 2.5 + row * 4.0, Vector3(1.6, 1.8, 0.1), yaw, WINDOW, false, false)
		# Up onto the roof from inside the Hof: a long ramp along this block (corner to the gate).
		var ramp_at: Vector2 = normal * (HOF_HALF - 4.0) + along * (HOF_HALF * 0.5)
		_kit.prop(MapProp.Kind.RAMP, ramp_at, 0.0, Vector3(5.0, BLOCK_HEIGHT, 34.0), yaw + 90.0, STONE)
	# Stairs onto the corner roofs from outside, for a second way up.
	for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, 1.0)]:
		var at: Vector2 = corner * (HOF_HALF + BLOCK_DEPTH + 4.0)
		_kit.prop(MapProp.Kind.STAIRS, at, 0.0, Vector3(4.0, BLOCK_HEIGHT, 26.0), 90.0 if corner.x < 0.0 else -90.0, STONE, true, true, 20)


func _courtyard() -> void:
	_kit.put(MapStructure.Kind.KNODL_STAND, Vector2(0.0, 20.0), 0.0, Vector3(5.0, 2.8, 3.0), Color(0.62, 0.44, 0.27), Color(0.95, 0.8, 0.35), 3.0)
	_kit.put(MapStructure.Kind.FOUNTAIN, Vector2(-26.0, 26.0), 0.0, Vector3(4.2, 0.0, 4.2), STONE, Color.WHITE, 2.4)
	# Stairs onto both tiers of the garden.
	_kit.prop(MapProp.Kind.STAIRS, Vector2(0.0, 13.5), 0.0, Vector3(4.0, 3.0, 5.0), 180.0, STONE, true, true, 5)
	_kit.prop(MapProp.Kind.STAIRS, Vector2(0.0, 4.5), 3.0, Vector3(3.0, 3.0, 5.0), 180.0, STONE, true, true, 5)
	for at: Vector2 in [Vector2(-10.0, -10.0), Vector2(10.0, -2.0), Vector2(6.0, -14.0)]:
		_kit.put(MapStructure.Kind.FRUIT_TREE, at, 0.0, Vector3(1.0, 6.0, 1.0), Color(0.36, 0.58, 0.26), Color(0.85, 0.85, 0.35), 1.6)
	# Laundry lines between poles (you pass under them).
	for k: int in 4:
		var z: float = -30.0 + k * 7.0
		_kit.prop(MapProp.Kind.POLE, Vector2(24.0, z), 0.0, Vector3(0.2, 3.0, 0.2), 0.0, WOOD, true, false)
		_kit.prop(MapProp.Kind.POLE, Vector2(36.0, z), 0.0, Vector3(0.2, 3.0, 0.2), 0.0, WOOD, true, false)
		_kit.prop(MapProp.Kind.BLOCK, Vector2(30.0, z), 2.2, Vector3(12.0, 0.9, 0.05), 0.0,
				[Color(0.95, 0.95, 0.93), Color(0.55, 0.7, 0.9), Color(0.95, 0.85, 0.5), Color(0.6, 0.85, 0.6)][k], false, false)
	_kit.put(MapStructure.Kind.CRATES, Vector2(-30.0, -24.0), 15.0, Vector3.ONE, WOOD, WOOD, 1.8)
	for k: int in 3:
		_kit.put(MapStructure.Kind.BENCH, Vector2(-20.0 + k * 3.0, 34.0), 0.0, Vector3(2.4, 0.45, 0.5), WOOD, WOOD, 1.2)


## Lower blocks in the four quarters outside the Hof; stairs up onto some of their roofs.
func _outer_blocks() -> void:
	var spots: Array[Vector2] = [Vector2(96.0, -96.0), Vector2(-96.0, 96.0), Vector2(96.0, 96.0), Vector2(-96.0, -96.0),
		Vector2(96.0, -40.0), Vector2(-96.0, 40.0), Vector2(40.0, 96.0), Vector2(-40.0, -96.0)]
	for k: int in spots.size():
		var at: Vector2 = spots[k]
		var height: float = 6.0 + (k % 3) * 2.0
		_kit.claim(at, 9.0, "outer block")
		_kit.prop(MapProp.Kind.BLOCK, at, 0.0, Vector3(16.0, height, 14.0), 0.0, FACADE_RED if k % 2 == 0 else FACADE)
		if k % 2 == 0:
			_kit.prop(MapProp.Kind.STAIRS, at + Vector2(10.0, 0.0), 0.0, Vector3(4.0, height, 12.0), 180.0, STONE, true, true, 10)


func _spots() -> void:
	# Beisln outside the Hof (built by Wirtshaus.building_props); a run opens 3 of them.
	var wirts: Array[Vector2] = [Vector2(80.0, 20.0), Vector2(-80.0, -20.0), Vector2(20.0, 82.0), Vector2(-24.0, -82.0),
		Vector2(80.0, 66.0), Vector2(-80.0, 66.0), Vector2(70.0, -76.0)]
	for at: Vector2 in wirts:
		_kit.claim(at, 6.0, "Wirtshaus")
	_map.wirtshaus_spots = PackedVector2Array(wirts)
	# Stempel on the roofs, on the garden top and out in the quarters.
	var roof: float = HOF_HALF + BLOCK_DEPTH * 0.5
	_map.stempel_spots = PackedVector2Array([Vector2(0.0, -6.0), Vector2(roof, -30.0), Vector2(-roof, 30.0),
		Vector2(30.0, roof), Vector2(-30.0, -roof), Vector2(96.0, 96.0), Vector2(-96.0, -96.0), Vector2(110.0, 0.0),
		Vector2(-110.0, 0.0)])
	_map.chest_spots = PackedVector2Array([Vector2(-20.0, -30.0), Vector2(20.0, 30.0), Vector2(roof, 20.0), Vector2(-roof, -20.0),
		Vector2(-20.0, roof), Vector2(20.0, -roof), Vector2(96.0, -96.0), Vector2(-96.0, 96.0), Vector2(60.0, 0.0),
		Vector2(-60.0, 0.0), Vector2(0.0, 60.0), Vector2(0.0, -64.0), Vector2(110.0, 50.0), Vector2(-110.0, -50.0)])
	_map.bot_waypoints = PackedVector2Array([Vector2(0.0, 26.0), Vector2(0.0, 50.0), Vector2(60.0, 66.0), Vector2(66.0, 0.0),
		Vector2(60.0, -66.0), Vector2(0.0, -66.0), Vector2(-60.0, -66.0), Vector2(-66.0, 0.0), Vector2(-60.0, 66.0),
		Vector2(0.0, 40.0), Vector2(-20.0, 0.0), Vector2(20.0, -20.0)])
