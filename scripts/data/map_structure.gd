class_name MapStructure
extends Resource
## One building or set piece of a map as a single entry (a house, a beer tent, the church), so a
## map file reads like a village plan instead of hundreds of boxes. StructureKit expands it into
## MapProps when the map is built; it stands on the terrain at its position.

enum Kind { HOUSE, TENT, STALL, CHURCH, AMT, BANDSTAND, FIR, FRUIT_TREE, MAIBAUM, KNODL_STAND, FENCE,
	FOUNTAIN, BARN, CHAPEL, CRATES, BENCH }

@export var kind: Kind = Kind.HOUSE
## x and z on the map; the height comes from the terrain.
@export var position: Vector2 = Vector2.ZERO
## The front (door, counter, open side) faces +z turned by this.
@export var yaw_degrees: float = 0.0
## Width (x), wall height (y) and depth (z). Fences only use x (their length).
@export var size: Vector3 = Vector3(8.0, 3.5, 7.0)
## Walls, canvas or wood.
@export var color: Color = Color(0.94, 0.91, 0.82)
## Roof, stripes or trim.
@export var accent: Color = Color(0.5, 0.3, 0.16)
