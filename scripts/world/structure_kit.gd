class_name StructureKit
extends RefCounted
## Expands a MapStructure (a house, a beer tent, the church ...) into the MapProps it is built from.
## Everything is in the structure's own frame first (front = +z, foot = y 0) and then placed on the
## terrain at its position, so the same entry looks the same wherever it stands. Colours stay out
## of Krampus red (GAME-DESIGN.md: red is only for enemy attacks).

const WOOD := Color(0.55, 0.38, 0.22)
const DARK_WOOD := Color(0.36, 0.24, 0.14)
const GLASS := Color(0.32, 0.38, 0.46)
const FLOWERS := Color(0.92, 0.45, 0.68)
const STONE := Color(0.66, 0.65, 0.62)
const FIR_GREEN := Color(0.18, 0.38, 0.22)
const LEAF_GREEN := Color(0.36, 0.58, 0.26)
const BARK := Color(0.4, 0.28, 0.18)
const WATER := Color(0.45, 0.7, 0.9)


## The props of one structure on `map` (its foot follows the terrain under its centre).
static func props_for(map: MapData, structure: MapStructure) -> Array[MapProp]:
	var out: Array[MapProp] = []
	var base_y: float = map.terrain_height(structure.position.x, structure.position.y)
	var place := Transform3D(Basis(Vector3.UP, deg_to_rad(structure.yaw_degrees)),
			Vector3(structure.position.x, base_y, structure.position.y))
	var b := _Builder.new(place, structure.yaw_degrees, out)
	var s: Vector3 = structure.size
	var c: Color = structure.color
	var a: Color = structure.accent
	match structure.kind:
		MapStructure.Kind.HOUSE:
			_house(b, s, c, a)
		MapStructure.Kind.TENT:
			_tent(b, s, c, a)
		MapStructure.Kind.STALL:
			_stall(b, s, c, a, false)
		MapStructure.Kind.KNODL_STAND:
			_stall(b, s, c, a, true)
		MapStructure.Kind.CHURCH:
			_church(b, s, c, a)
		MapStructure.Kind.AMT:
			_amt(b, s, c, a)
		MapStructure.Kind.BANDSTAND:
			_bandstand(b, s, c, a)
		MapStructure.Kind.FIR:
			_fir(b, s.y, c)
		MapStructure.Kind.FRUIT_TREE:
			_fruit_tree(b, s.y, c, a)
		MapStructure.Kind.MAIBAUM:
			_maibaum(b, s.y, c, a)
		MapStructure.Kind.FENCE:
			b.add(MapProp.Kind.BLOCK, Vector3.ZERO, Vector3(s.x, s.y, 0.15), c, true, false)
			# Posts every 2.5 m.
			var posts: int = maxi(int(s.x / 2.5), 1)
			for k: int in posts + 1:
				b.add(MapProp.Kind.BLOCK, Vector3(-s.x * 0.5 + s.x * k / posts, 0.0, 0.0), Vector3(0.22, s.y + 0.2, 0.22), c.darkened(0.2), false, false)
		MapStructure.Kind.FOUNTAIN:
			b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(s.x, 0.8, s.x), c)
			b.add(MapProp.Kind.POLE, Vector3(0.0, 0.0, 0.0), Vector3(s.x - 0.6, 0.83, s.x - 0.6), WATER, false)
			b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(0.5, 2.4, 0.5), c, true, false)
			b.add(MapProp.Kind.POLE, Vector3(0.0, 2.2, 0.0), Vector3(1.6, 0.3, 1.6), c, false)
		MapStructure.Kind.BARN:
			_barn(b, s, c, a)
		MapStructure.Kind.CHAPEL:
			_house(b, s, c, a, false)
			b.add(MapProp.Kind.BLOCK, Vector3(0.0, s.y, s.z * 0.5 - 0.8), Vector3(1.4, 2.2 + s.z * 0.42, 1.4), c, false)
			b.add(MapProp.Kind.SPIRE, Vector3(0.0, s.y + 2.2 + s.z * 0.42, s.z * 0.5 - 0.8), Vector3(1.7, 2.6, 1.7), a, false)
		MapStructure.Kind.CRATES:
			b.add(MapProp.Kind.BLOCK, Vector3.ZERO, Vector3(1.6, 1.2, 1.6), c)
			b.add(MapProp.Kind.BLOCK, Vector3(1.7, 0.0, 0.3), Vector3(1.4, 0.9, 1.4), c.darkened(0.1))
			b.add(MapProp.Kind.BLOCK, Vector3(0.2, 1.2, 0.1), Vector3(1.1, 1.0, 1.1), c.lightened(0.08))
		MapStructure.Kind.BENCH:
			b.add(MapProp.Kind.BLOCK, Vector3.ZERO, Vector3(s.x, 0.45, 0.5), c)
	return out


static func _house(b: _Builder, s: Vector3, c: Color, a: Color, chimney: bool = true) -> void:
	b.add(MapProp.Kind.BLOCK, Vector3.ZERO, s, c)
	b.add(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.x + 0.9, s.z * 0.42, s.z + 0.9), a)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, s.z * 0.5 + 0.06), Vector3(1.2, 2.2, 0.14), DARK_WOOD, false)
	var floors: int = 2 if s.y > 5.0 else 1
	for f: int in floors:
		var y: float = 1.3 + f * 2.8
		for side: float in [-1.0, 1.0]:
			var x: float = side * s.x * 0.28
			if f == 0 and absf(x) < 1.3:
				continue
			b.add(MapProp.Kind.BLOCK, Vector3(x, y, s.z * 0.5 + 0.06), Vector3(0.95, 1.0, 0.12), GLASS, false)
			b.add(MapProp.Kind.BLOCK, Vector3(x, y - 0.25, s.z * 0.5 + 0.22), Vector3(1.1, 0.25, 0.3), FLOWERS, false)
			b.add(MapProp.Kind.BLOCK, Vector3(x, y, -s.z * 0.5 - 0.06), Vector3(0.95, 1.0, 0.12), GLASS, false)
	if chimney:
		b.add(MapProp.Kind.BLOCK, Vector3(s.x * 0.25, s.y, -s.z * 0.15), Vector3(0.6, s.z * 0.42 + 0.6, 0.6), STONE, false)


static func _tent(b: _Builder, s: Vector3, c: Color, a: Color) -> void:
	var hx: float = s.x * 0.5
	var hz: float = s.z * 0.5
	for x: float in [-hx, 0.0, hx]:
		for z: float in [-hz, hz]:
			b.add(MapProp.Kind.POLE, Vector3(x, 0.0, z), Vector3(0.3, s.y, 0.3), Color(0.95, 0.95, 0.92), true, false)
	b.add(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.x + 0.6, s.z * 0.35, s.z + 0.6), c)
	for z: float in [-hz - 0.3, hz + 0.3]:
		b.add(MapProp.Kind.BLOCK, Vector3(0.0, s.y - 0.6, z), Vector3(s.x + 0.6, 0.6, 0.08), a, false)
	var rows: int = maxi(int((s.z - 2.0) / 2.6), 1)
	for r: int in rows:
		var z: float = -hz + 1.0 + (s.z - 2.0) * (r + 0.5) / rows
		b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, z), Vector3(s.x - 3.0, 0.8, 0.8), WOOD)
		b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, z - 0.75), Vector3(s.x - 3.0, 0.45, 0.35), WOOD.darkened(0.1))
		b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, z + 0.75), Vector3(s.x - 3.0, 0.45, 0.35), WOOD.darkened(0.1))


static func _stall(b: _Builder, s: Vector3, c: Color, a: Color, knodl: bool) -> void:
	var hz: float = s.z * 0.5
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, hz - 0.45), Vector3(s.x, 1.15, 0.9), c)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, -hz + 0.1), Vector3(s.x, s.y, 0.2), c.darkened(0.12))
	for x: float in [-s.x * 0.5 + 0.12, s.x * 0.5 - 0.12]:
		b.add(MapProp.Kind.POLE, Vector3(x, 0.0, hz - 0.1), Vector3(0.18, s.y, 0.18), c.darkened(0.2), true, false)
	b.add(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.x + 0.5, 0.9, s.z + 0.6), a)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.3, hz + 0.02), Vector3(s.x - 0.3, 0.55, 0.06), a, false)
	if knodl:
		# The family's Knödl pot and a pile of Knödl on the counter.
		b.add(MapProp.Kind.POLE, Vector3(-s.x * 0.25, 1.15, hz - 0.45), Vector3(0.7, 0.55, 0.7), Color(0.55, 0.56, 0.6), false)
		for k: int in 3:
			b.add(MapProp.Kind.SPIRE, Vector3(s.x * 0.15 + k * 0.45, 1.15, hz - 0.45), Vector3(0.4, 0.35, 0.4), Color(0.93, 0.83, 0.58), false)
	else:
		for k: int in 3:
			b.add(MapProp.Kind.BLOCK, Vector3(-s.x * 0.3 + k * s.x * 0.3, 1.15, hz - 0.45), Vector3(0.5, 0.3, 0.4),
					[Color(0.9, 0.7, 0.35), Color(0.6, 0.4, 0.75), Color(0.45, 0.7, 0.85)][k], false)


static func _church(b: _Builder, s: Vector3, c: Color, a: Color) -> void:
	b.add(MapProp.Kind.BLOCK, Vector3.ZERO, s, c)
	# The nave runs along z, so its roof ridge does too.
	b.add_turned(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.z + 0.8, s.x * 0.5, s.x + 0.8), 90.0, a)
	var tower: float = s.y + 10.0
	var tz: float = s.z * 0.5 + 2.2
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, tz), Vector3(4.6, tower, 4.6), c)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, tower, tz), Vector3(5.0, 9.0, 5.0), Color(0.36, 0.56, 0.48))
	b.add(MapProp.Kind.POLE, Vector3(0.0, tower - 3.0, tz + 2.32), Vector3(1.8, 0.1, 1.8), Color(0.95, 0.86, 0.45), false)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, tz + 2.35), Vector3(1.6, 3.0, 0.14), DARK_WOOD, false)
	for k: int in 3:
		var z: float = -s.z * 0.3 + k * s.z * 0.3
		for side: float in [-1.0, 1.0]:
			b.add(MapProp.Kind.BLOCK, Vector3(side * (s.x * 0.5 + 0.06), 2.5, z), Vector3(0.12, 3.0, 1.1), GLASS, false)


static func _amt(b: _Builder, s: Vector3, c: Color, a: Color) -> void:
	b.add(MapProp.Kind.BLOCK, Vector3.ZERO, s, c)
	b.add(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.x + 1.0, 3.2, s.z + 1.0), a)
	# A porch with steps up to the big door.
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, s.z * 0.5 + 1.5), Vector3(8.0, 0.6, 3.0), STONE)
	b.add(MapProp.Kind.STAIRS, Vector3(0.0, 0.0, s.z * 0.5 + 3.6), Vector3(5.0, 0.6, 1.2), STONE, true, true, 180.0, 2)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.6, s.z * 0.5 + 0.06), Vector3(2.4, 3.0, 0.14), DARK_WOOD, false)
	for f: int in 2:
		for k: int in 6:
			var x: float = -s.x * 0.42 + k * s.x * 0.168
			if f == 0 and absf(x) < 2.0:
				continue
			b.add(MapProp.Kind.BLOCK, Vector3(x, 1.6 + f * 3.2, s.z * 0.5 + 0.06), Vector3(1.0, 1.4, 0.12), GLASS, false)
	# Flag pole with the Gemeinde flag (green and white).
	b.add(MapProp.Kind.POLE, Vector3(s.x * 0.5 + 2.0, 0.0, s.z * 0.5 + 1.0), Vector3(0.2, 11.0, 0.2), Color(0.85, 0.85, 0.85), true, false)
	b.add(MapProp.Kind.BLOCK, Vector3(s.x * 0.5 + 3.0, 9.0, s.z * 0.5 + 1.0), Vector3(2.0, 0.6, 0.05), Color(0.2, 0.55, 0.3), false)
	b.add(MapProp.Kind.BLOCK, Vector3(s.x * 0.5 + 3.0, 9.6, s.z * 0.5 + 1.0), Vector3(2.0, 0.6, 0.05), Color(0.97, 0.97, 0.95), false)


static func _bandstand(b: _Builder, s: Vector3, c: Color, a: Color) -> void:
	var h: float = 1.1
	var hx: float = s.x * 0.5
	b.add(MapProp.Kind.BLOCK, Vector3.ZERO, Vector3(s.x, h, s.z), c)
	b.add(MapProp.Kind.STAIRS, Vector3(0.0, 0.0, s.z * 0.5 + 1.3), Vector3(3.0, h, 2.6), STONE, true, true, 180.0, 4)
	for x: float in [-hx + 0.2, hx - 0.2]:
		for z: float in [-hx + 0.2, hx - 0.2]:
			b.add(MapProp.Kind.POLE, Vector3(x, h, z), Vector3(0.25, s.y, 0.25), Color(0.95, 0.95, 0.92), true, false)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, h + s.y, 0.0), Vector3(s.x + 1.0, 2.6, s.z + 1.0), a)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, h, -hx + 0.1), Vector3(s.x, 0.8, 0.12), c.darkened(0.15), true, false)
	b.add(MapProp.Kind.BLOCK, Vector3(-hx + 0.1, h, 0.0), Vector3(0.12, 0.8, s.z), c.darkened(0.15), true, false)
	b.add(MapProp.Kind.BLOCK, Vector3(hx - 0.1, h, 0.0), Vector3(0.12, 0.8, s.z), c.darkened(0.15), true, false)


static func _fir(b: _Builder, h: float, c: Color) -> void:
	b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(0.5, h * 0.35, 0.5), BARK, true, false)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, h * 0.18, 0.0), Vector3(h * 0.5, h * 0.42, h * 0.5), c, false)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, h * 0.42, 0.0), Vector3(h * 0.38, h * 0.36, h * 0.38), c.lightened(0.05), false)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, h * 0.64, 0.0), Vector3(h * 0.25, h * 0.36, h * 0.25), c.lightened(0.1), false)


static func _fruit_tree(b: _Builder, h: float, c: Color, a: Color) -> void:
	b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(0.35, h * 0.5, 0.35), BARK, true, false)
	b.add_turned(MapProp.Kind.BLOCK, Vector3(0.0, h * 0.4, 0.0), Vector3(h * 0.6, h * 0.45, h * 0.6), 45.0, c, false)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, h * 0.8, 0.0), Vector3(h * 0.35, h * 0.2, h * 0.35), c.lightened(0.08), false)
	# A few apples (the accent colour).
	for k: int in 4:
		var angle: float = TAU * k / 4.0 + 0.4
		b.add(MapProp.Kind.BLOCK, Vector3(cos(angle) * h * 0.3, h * 0.55, sin(angle) * h * 0.3), Vector3(0.25, 0.25, 0.25), a, false)


static func _maibaum(b: _Builder, h: float, c: Color, a: Color) -> void:
	b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(0.6, h, 0.6), c, true, false)
	b.add(MapProp.Kind.POLE, Vector3.ZERO, Vector3(2.4, 0.5, 2.4), STONE)
	for turn: float in [0.0, 60.0, 120.0]:
		b.add_turned(MapProp.Kind.BLOCK, Vector3(0.0, h * 0.72, 0.0), Vector3(3.6, 0.35, 0.3), turn, a, false)
	b.add(MapProp.Kind.SPIRE, Vector3(0.0, h, 0.0), Vector3(1.8, 3.4, 1.8), FIR_GREEN, false)
	# Guild signs up the pole.
	for k: int in 4:
		var y: float = h * 0.25 + k * h * 0.1
		b.add_turned(MapProp.Kind.BLOCK, Vector3(0.0, y, 0.0), Vector3(1.6, 0.6, 0.06), 45.0 * k, Color(0.95, 0.9, 0.7), false)


static func _barn(b: _Builder, s: Vector3, c: Color, a: Color) -> void:
	b.add(MapProp.Kind.BLOCK, Vector3.ZERO, s, c)
	b.add(MapProp.Kind.ROOF, Vector3(0.0, s.y, 0.0), Vector3(s.x + 0.8, s.z * 0.38, s.z + 0.8), a)
	b.add(MapProp.Kind.BLOCK, Vector3(0.0, 0.0, s.z * 0.5 + 0.06), Vector3(3.0, 3.0, 0.14), DARK_WOOD, false)
	# A ramp up the back to the eaves: from there the roof is a lookout.
	var ramp_length: float = s.y * 2.6
	b.add(MapProp.Kind.RAMP, Vector3(0.0, 0.0, -s.z * 0.5 - ramp_length * 0.5), Vector3(3.2, s.y, ramp_length), WOOD)


## Collects props in a structure's frame and places them on the map.
class _Builder:
	extends RefCounted
	var place: Transform3D
	var yaw: float
	var out: Array[MapProp]

	func _init(p_place: Transform3D, p_yaw: float, p_out: Array[MapProp]) -> void:
		place = p_place
		yaw = p_yaw
		out = p_out

	func add(kind: MapProp.Kind, local: Vector3, size: Vector3, color: Color, solid: bool = true, walkable: bool = true,
			turn: float = 0.0, steps: int = 6) -> MapProp:
		var prop := MapProp.new()
		prop.kind = kind
		prop.position = place * local
		prop.size = size
		prop.yaw_degrees = yaw + turn
		prop.color = color
		prop.solid = solid
		prop.walkable = walkable
		prop.steps = steps
		out.append(prop)
		return prop

	func add_turned(kind: MapProp.Kind, local: Vector3, size: Vector3, turn: float, color: Color, solid: bool = true) -> MapProp:
		return add(kind, local, size, color, solid, true, turn)
