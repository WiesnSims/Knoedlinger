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

@export_group("Places")
@export var spawn_point: Vector3 = Vector3(0.0, 0.0, 4.0)
## Points the bot wanders between (x, z).
@export var bot_waypoints: PackedVector2Array = PackedVector2Array()
@export var props: Array[MapProp] = []

@export_group("Look")
@export var grass_color: Color = Color(0.4, 0.62, 0.3)
@export var meadow_color: Color = Color(0.52, 0.7, 0.33)
@export var rock_color: Color = Color(0.55, 0.53, 0.5)
@export var dirt_color: Color = Color(0.6, 0.48, 0.32)
@export var sky_color: Color = Color(0.55, 0.75, 0.95)

var _noise: FastNoiseLite


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
	var edge: float = maxf(absf(x), absf(z))
	var rim: float = smoothstep(rim_start, half_size, edge)
	h += rim * rim * rim_height
	return h


## Metres between two terrain samples.
func terrain_cell() -> float:
	return half_size * 2.0 / float(terrain_samples - 1)
