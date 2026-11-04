class_name MapProp
extends Resource
## One hand-placed piece of a map: a block (platform, house, crate), a ramp, a flight of stairs or a
## pole. The player and the Knödl collide with it through Jolt; enemies walk on its top through the
## map's baked ground field (they are data, not physics bodies).

## ROOF: a gable roof (a triangular prism) whose ridge runs along x at half the depth. SPIRE: a
## four-sided pyramid. Both start at position.y and do not sink into the ground.
enum Kind { BLOCK, RAMP, STAIRS, POLE, ROOF, SPIRE }

## How far below `position.y` every prop reaches, so it never floats on bumpy ground.
const SINK: float = 1.5

@export var kind: Kind = Kind.BLOCK
## Centre of the footprint; y is the height of its foot (ramps and stairs start here).
@export var position: Vector3 = Vector3.ZERO
## Width (x), height (y) and length (z) before the yaw. Ramps and stairs rise along +z.
@export var size: Vector3 = Vector3(4.0, 2.0, 4.0)
@export var yaw_degrees: float = 0.0
## Stairs only: the number of steps (collision is a smooth ramp, the look has steps).
@export var steps: int = 6
@export var color: Color = Color(0.62, 0.45, 0.3)
## False for things enemies walk through or around (poles, fences): left out of the ground field.
@export var walkable: bool = true
## False for decoration the player and the Knödl pass through (window frames, tree crowns, flags).
@export var solid: bool = true


## The prop's top height at a world position, or -INF outside its footprint.
func top_at(x: float, z: float) -> float:
	var local: Vector2 = to_local(x, z)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	if absf(local.x) > hx or absf(local.y) > hz:
		return -INF
	match kind:
		Kind.RAMP:
			return position.y + size.y * (local.y + hz) / size.z
		Kind.STAIRS:
			var count: int = maxi(steps, 1)
			var step: int = mini(int((local.y + hz) / size.z * count), count - 1)
			return position.y + size.y * float(step + 1) / count
		Kind.ROOF:
			return position.y + size.y * (1.0 - absf(local.y) / hz)
		Kind.SPIRE:
			return position.y + size.y * (1.0 - maxf(absf(local.x) / hx, absf(local.y) / hz))
	return position.y + size.y


## World x/z to the prop's local x/z (rotated by -yaw around the centre).
func to_local(x: float, z: float) -> Vector2:
	var angle: float = deg_to_rad(yaw_degrees)
	var dx: float = x - position.x
	var dz: float = z - position.z
	var c: float = cos(angle)
	var s: float = sin(angle)
	# Godot's yaw turns +z toward +x: local = R(-yaw) * world.
	return Vector2(c * dx - s * dz, s * dx + c * dz)


## The footprint's corners in world x/z, for rasterising into the ground field.
func footprint_bounds() -> Rect2:
	var angle: float = deg_to_rad(yaw_degrees)
	var c: float = absf(cos(angle))
	var s: float = absf(sin(angle))
	var ex: float = size.x * 0.5 * c + size.z * 0.5 * s
	var ez: float = size.x * 0.5 * s + size.z * 0.5 * c
	return Rect2(position.x - ex, position.z - ez, ex * 2.0, ez * 2.0)


func transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position)
