class_name MapData
extends Resource
## One map as data: a heightmap terrain made of gentle noise, hand-placed hills and bowls, a flat
## centre and a ring of mountains at the edge, plus hand-placed props. MapBuilder turns it into
## meshes and collision; Heightfield bakes the ground that enemies and Brösel stand on. Everything
## is deterministic, so a client builds exactly the host's map from the same file.

@export var id: StringName = &""
## Translation key of the player-facing name.
@export var name_key: String = ""
## Half the side length of the square map in metres.
@export var half_size: float = 100.0
## Terrain samples per side. Jolt keeps a HeightMapShape3D as a real height field only when this is
## a power of two; anything else becomes a slower triangle mesh.
@export var terrain_samples: int = 256
## Sample spacing of the baked ground field (terrain plus walkable props) for enemies and Brösel.
@export var ground_cell: float = 0.5

@export_group("Shape")
@export var noise_seed: int = 7
@export var noise_amplitude: float = 1.2
@export var noise_frequency: float = 0.025
## The centre stays flat within this radius and blends into the terrain over flat_blend metres.
@export var flat_radius: float = 22.0
@export var flat_blend: float = 12.0
## Hills (positive height) and bowls (negative): x, z, radius, height. Cosine-shaped.
@export var hills: PackedVector4Array = PackedVector4Array()
## Ridges along a line: x0, z0, x1, z1 in the first vector, radius and height in the second's x, y.
@export var ridge_starts: PackedVector4Array = PackedVector4Array()
@export var ridge_shapes: PackedVector2Array = PackedVector2Array()
## Mountains at the border, rising from rim_start (distance from the centre, square) to the edge.
@export var rim_start: float = 86.0
@export var rim_height: float = 22.0
## The whole map leans: height += x * tilt.x + z * tilt.y (a ski slope), on top of everything else.
@export var tilt: Vector2 = Vector2.ZERO
## Plateaus with steep edges (x, z, radius, height): flat on top, a drop of `height` over mesa_edge
## metres at the rim. Stacked ones make several levels (Megabonk-style climbs and drops).
@export var mesas: PackedVector4Array = PackedVector4Array()
@export var mesa_edge: float = 3.0

## The run's timeline on this map (enemies, bosses, the Formular); null = the Kirtag's.
@export var wave: WaveData

@export_group("Places")
@export var spawn_point: Vector3 = Vector3(0.0, 0.0, 4.0)
## Points the bot wanders between (x, z).
@export var bot_waypoints: PackedVector2Array = PackedVector2Array()
@export var props: Array[MapProp] = []
## Where Wirtshäuser stand (x, z); each faces the map centre. A run opens some of them at random.
@export var wirtshaus_spots: PackedVector2Array = PackedVector2Array()
## Buildings and set pieces (StructureKit expands them into props).
@export var structures: Array[MapStructure] = []
## Where the Stempel of the Formular quest may lie (x, z); a run picks balance.stempel_count of them.
@export var stempel_spots: PackedVector2Array = PackedVector2Array()
## Where map chests may stand (x, z); a run fills balance.map_chest_count of them.
@export var chest_spots: PackedVector2Array = PackedVector2Array()
## The boss gate (the portal to the Amt der Unterwelt) and where the boss appears out of it.
@export var portal_point: Vector2 = Vector2(0.0, -60.0)

@export_group("Look")
@export var grass_color: Color = Color(0.4, 0.62, 0.3)
@export var meadow_color: Color = Color(0.52, 0.7, 0.33)
@export var rock_color: Color = Color(0.55, 0.53, 0.5)
@export var dirt_color: Color = Color(0.6, 0.48, 0.32)
@export var sky_color: Color = Color(0.55, 0.75, 0.95)
## Gravel paths painted on the terrain: x0, z0, x1, z1 per segment, path_width wide.
@export var paths: PackedVector4Array = PackedVector4Array()
@export var path_width: float = 4.0
@export var path_color: Color = Color(0.72, 0.64, 0.5)
## The village square around the centre is gravel too, out to this radius (0 = none).
@export var plaza_radius: float = 0.0


## 0..1: how much of a path or the plaza covers this point (soft edges).
func path_cover(x: float, z: float) -> float:
	var cover: float = 0.0
	if plaza_radius > 0.0:
		cover = smoothstep(plaza_radius + 1.0, plaza_radius - 1.0, sqrt(x * x + z * z))
	var half: float = path_width * 0.5
	var p := Vector2(x, z)
	for line: Vector4 in paths:
		var a := Vector2(line.x, line.y)
		var ab := Vector2(line.z, line.w) - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		if d < half + 1.0:
			cover = maxf(cover, smoothstep(half + 1.0, half - 0.5, d))
	return cover

var _noise: FastNoiseLite
var _all_props: Array[MapProp] = []


## The hand-placed props, the structures and the buildings at every Wirtshaus spot (the same on
## every machine).
func all_props() -> Array[MapProp]:
	if _all_props.is_empty():
		_all_props = props.duplicate()
		for structure: MapStructure in structures:
			_all_props.append_array(StructureKit.props_for(self, structure))
		for k: int in wirtshaus_spots.size():
			_all_props.append_array(Wirtshaus.building_props(self, k))
	return _all_props


## A Wirtshaus spot as a transform: on the terrain, its door (+z) facing the map centre.
func wirtshaus_transform(spot: int) -> Transform3D:
	var at: Vector2 = wirtshaus_spots[spot]
	var yaw: float = atan2(-at.x, -at.y)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, terrain_height(at.x, at.y), at.y))


## The terrain height at a world position, without props. Exact; Heightfield bakes it into a grid.
func terrain_height(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = noise_seed
		_noise.frequency = noise_frequency
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.fractal_octaves = 3
	var from_centre: float = sqrt(x * x + z * z)
	var away: float = smoothstep(flat_radius, flat_radius + flat_blend, from_centre)
	var h: float = _noise.get_noise_2d(x, z) * noise_amplitude * away
	for hill: Vector4 in hills:
		var dx: float = x - hill.x
		var dz: float = z - hill.y
		var d_sq: float = dx * dx + dz * dz
		if d_sq < hill.z * hill.z:
			h += hill.w * 0.5 * (1.0 + cos(PI * sqrt(d_sq) / hill.z))
	for k: int in mini(ridge_starts.size(), ridge_shapes.size()):
		var line: Vector4 = ridge_starts[k]
		var shape: Vector2 = ridge_shapes[k]
		var a := Vector2(line.x, line.y)
		var b := Vector2(line.z, line.w)
		var p := Vector2(x, z)
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		if d < shape.x:
			h += shape.y * 0.5 * (1.0 + cos(PI * d / shape.x))
	for mesa: Vector4 in mesas:
		var d: float = Vector2(x - mesa.x, z - mesa.y).length()
		if d < mesa.z + mesa_edge:
			h += mesa.w * smoothstep(mesa.z + mesa_edge, mesa.z, d)
	h += x * tilt.x + z * tilt.y
	var edge: float = maxf(absf(x), absf(z))
	var rim: float = smoothstep(rim_start, half_size, edge)
	h += rim * rim * rim_height
	return h


## Metres between two terrain samples.
func terrain_cell() -> float:
	return half_size * 2.0 / float(terrain_samples - 1)
