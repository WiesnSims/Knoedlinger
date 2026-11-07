class_name LootField
extends Node3D
## Things lying around the Kirtag that a player picks up by walking over them: gold coins, chests
## (map chests cost gold, boss chests are free), the Stempel of the Formular quest, a Gulasch
## that heals, small Lebkuchenherzerl (1.4.1) and Fassl (barrels) that the player or the Knödl smashes for coins. The host owns them and says who took what; clients mirror them from run events.
## A few hundred at most, each kind drawn with one MultiMesh. In co-op every player may open every map
## chest once (1.4.1, A2): a chest the local player opened is `hidden` here but stays for the others.

enum Kind { COIN, CHEST, BOSS_CHEST, STEMPEL, HEAL, FASSL, HEART }

const CAPACITY: int = 512
## Transform 12 + instance colour 4 (always white; see EnemyRenderer for why colours are on).
const STRIDE: int = 16
## BOSS_CHEST value: items in the low byte, this bit = evolutions first.
const EVOLUTION_BIT: int = 0x100
## CHEST / BOSS_CHEST value: the chest's rarity sits in bits 12-13 (a map chest's price below them).
const RARITY_SHIFT: int = 12
const LOW_MASK: int = 0xFFF
## Light over a chest in its rarity colour (Gewöhnlich .. Hofratswürdig, docs/UI-STYLE.md palette).
const RARITY_LIGHT: Array[Color] = [Color("b8b8c0"), Color("5ccb6b"), Color("4aa3ff"), Color("b57bff")]
const STEMPEL_LIGHT := Color(1.0, 0.85, 0.35)
const BEAMS: int = 32


static func chest_value(low: int, rarity: int) -> int:
	return (low & LOW_MASK) | (clampi(rarity, 0, 3) << RARITY_SHIFT)


static func chest_rarity(value: int) -> int:
	return (value >> RARITY_SHIFT) & 3


## A map chest's base price; a boss chest's items and evolution bit.
static func chest_low(value: int) -> int:
	return value & LOW_MASK

var capacity: int = CAPACITY
var alive := PackedByteArray()
var ids := PackedInt32Array()
var kinds := PackedByteArray()
var xs := PackedFloat32Array()
var zs := PackedFloat32Array()
var values := PackedInt32Array()
## 1 = the local player opened this chest already (not drawn, not offered); others still see it.
var hidden := PackedByteArray()
var count: int = 0

var _ground: Heightfield
var _slot_of: Dictionary[int, int] = {}
var _next_id: int = 0
var _meshes: Array[MultiMesh] = []
var _buffers: Array[PackedFloat32Array] = []
var _beam: MultiMesh
var _beam_buffer := PackedFloat32Array()
var _time: float = 0.0


func setup(ground: Heightfield) -> void:
	_ground = ground
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for array: String in ["ids", "values"]:
		var ints := PackedInt32Array()
		ints.resize(capacity)
		set(array, ints)
	for array: String in ["xs", "zs"]:
		var floats := PackedFloat32Array()
		floats.resize(capacity)
		set(array, floats)
	alive.resize(capacity)
	alive.fill(0)
	hidden.resize(capacity)
	hidden.fill(0)
	kinds.resize(capacity)
	var material := MapBuilder.vertex_color_material()
	for kind: int in Kind.size():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _mesh_for(kind)
		multimesh.instance_count = capacity
		multimesh.visible_instance_count = 0
		var instance := MultiMeshInstance3D.new()
		instance.name = "Loot_%s" % Kind.keys()[kind]
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 150.0, 2000.0))
		add_child(instance)
		_meshes.append(multimesh)
		var buffer := PackedFloat32Array()
		buffer.resize(capacity * STRIDE)
		_buffers.append(buffer)
	# A light beam over every Stempel, so it can be found across the village, and a short one over
	# every chest in its rarity colour.
	_beam = MultiMesh.new()
	_beam.transform_format = MultiMesh.TRANSFORM_3D
	_beam.use_colors = true
	var column := CylinderMesh.new()
	column.top_radius = 0.5
	column.bottom_radius = 0.9
	column.height = 1.0
	column.radial_segments = 10
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	_beam.mesh = column
	_beam.instance_count = BEAMS
	_beam.visible_instance_count = 0
	_beam_buffer.resize(BEAMS * STRIDE)
	var beam_material := ShaderMaterial.new()
	beam_material.shader = load("res://shaders/beam.gdshader")
	var beams := MultiMeshInstance3D.new()
	beams.name = "StempelBeams"
	beams.multimesh = _beam
	beams.material_override = beam_material
	beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beams.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 150.0, 2000.0))
	add_child(beams)


## Host: a new item; returns its id (or -1 when full).
func add(kind: Kind, x: float, z: float, value: int) -> int:
	_next_id = (_next_id + 1) & 0xFFFF
	return _place(_next_id, kind, x, z, value)


## Client: an item the host made.
func add_remote(id: int, kind: int, x: float, z: float, value: int) -> void:
	if kind < Kind.size() and not _slot_of.has(id):
		_place(id, kind as Kind, x, z, value)


func remove(id: int) -> void:
	var slot: int = _slot_of.get(id, -1)
	if slot < 0:
		return
	alive[slot] = 0
	_slot_of.erase(id)
	count -= 1


## The local player opened this chest: it goes from their view, not from the others'.
func hide_opened(id: int) -> void:
	var slot: int = _slot_of.get(id, -1)
	if slot >= 0:
		hidden[slot] = 1


func has(id: int) -> bool:
	return _slot_of.has(id)


func slot_of(id: int) -> int:
	return _slot_of.get(id, -1)


func position_of(slot: int) -> Vector3:
	return Vector3(xs[slot], _ground_y(xs[slot], zs[slot]), zs[slot])


## Host: items within `reach` of (x, z) whose ground is within 2.5 m of `y` (stand on the roof to
## get a Stempel on the roof). Returns their slots.
func near(x: float, y: float, z: float, reach: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var reach_sq: float = reach * reach
	for slot: int in capacity:
		if alive[slot] == 0:
			continue
		var dx: float = xs[slot] - x
		var dz: float = zs[slot] - z
		if dx * dx + dz * dz < reach_sq and absf(_ground_y(xs[slot], zs[slot]) - y) < 2.5:
			found.append(slot)
	return found


## The nearest item of a kind (any kind when `kind` < 0), or -1.
func nearest(kind: int, x: float, z: float) -> int:
	var best: int = -1
	var best_sq: float = INF
	for slot: int in capacity:
		if alive[slot] == 0 or hidden[slot] != 0 or (kind >= 0 and kinds[slot] != kind):
			continue
		var d_sq: float = (xs[slot] - x) * (xs[slot] - x) + (zs[slot] - z) * (zs[slot] - z)
		if d_sq < best_sq:
			best_sq = d_sq
			best = slot
	return best


## Host: every alive item as (id, kind, x, z, value) rows, for a client that just joined.
func all_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot: int in capacity:
		if alive[slot] != 0:
			out.append(slot)
	return out


## Coins (or another kind) drift toward a player standing close (Wanderkarte reach), so collecting
## feels snappy.
func attract(x: float, z: float, reach: float, delta: float, kind: Kind = Kind.COIN) -> void:
	var reach_sq: float = reach * reach
	for slot: int in capacity:
		if alive[slot] == 0 or kinds[slot] != kind:
			continue
		var dx: float = x - xs[slot]
		var dz: float = z - zs[slot]
		var d_sq: float = dx * dx + dz * dz
		if d_sq < reach_sq and d_sq > 0.01:
			var d: float = sqrt(d_sq)
			var step: float = minf(12.0 * delta, d)
			xs[slot] += dx / d * step
			zs[slot] += dz / d * step


func draw(delta: float) -> void:
	_time += delta
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(Kind.size())
	counts.fill(0)
	var buffers: Array[PackedFloat32Array] = []
	for kind: int in Kind.size():
		buffers.append(_buffers[kind])
		_buffers[kind] = PackedFloat32Array()
	var beams: int = 0
	for slot: int in capacity:
		if alive[slot] == 0 or hidden[slot] != 0:
			continue
		var kind: int = kinds[slot]
		var x: float = xs[slot]
		var z: float = zs[slot]
		var y: float = _ground_y(x, z)
		var spin: float = 0.0
		var lift: float = 0.0
		match kind:
			Kind.COIN:
				spin = _time * 3.0 + slot
				lift = 0.5 + sin(_time * 4.0 + slot) * 0.1
			Kind.STEMPEL:
				spin = _time * 1.2
				lift = 0.8 + sin(_time * 2.0) * 0.25
			Kind.HEAL:
				spin = _time * 0.8
				lift = 0.3
			Kind.HEART:
				spin = _time * 2.5 + slot
				lift = 0.6 + sin(_time * 3.0 + slot) * 0.12
		var c: float = cos(spin)
		var s: float = sin(spin)
		var buffer: PackedFloat32Array = buffers[kind]
		var o: int = counts[kind] * STRIDE
		buffer[o] = c
		buffer[o + 1] = 0.0
		buffer[o + 2] = s
		buffer[o + 3] = x
		buffer[o + 4] = 0.0
		buffer[o + 5] = 1.0
		buffer[o + 6] = 0.0
		buffer[o + 7] = y + lift
		buffer[o + 8] = -s
		buffer[o + 9] = 0.0
		buffer[o + 10] = c
		buffer[o + 11] = z
		buffer[o + 12] = 1.0
		buffer[o + 13] = 1.0
		buffer[o + 14] = 1.0
		buffer[o + 15] = 1.0
		counts[kind] += 1
		var chest: bool = kind == Kind.CHEST or kind == Kind.BOSS_CHEST
		if (kind == Kind.STEMPEL or chest) and beams < BEAMS:
			var bo: int = beams * STRIDE
			var height: float = 40.0 if kind == Kind.STEMPEL else 7.0
			var light: Color = STEMPEL_LIGHT if kind == Kind.STEMPEL else RARITY_LIGHT[chest_rarity(values[slot])]
			for k: int in STRIDE:
				_beam_buffer[bo + k] = 0.0
			_beam_buffer[bo] = 1.0 if kind == Kind.STEMPEL else 0.6
			_beam_buffer[bo + 3] = x
			_beam_buffer[bo + 5] = height
			_beam_buffer[bo + 7] = y + height * 0.5
			_beam_buffer[bo + 10] = 1.0 if kind == Kind.STEMPEL else 0.6
			_beam_buffer[bo + 11] = z
			_beam_buffer[bo + 12] = light.r
			_beam_buffer[bo + 13] = light.g
			_beam_buffer[bo + 14] = light.b
			_beam_buffer[bo + 15] = 1.0
			beams += 1
	for kind: int in Kind.size():
		_meshes[kind].buffer = buffers[kind]
		_meshes[kind].visible_instance_count = counts[kind]
		_buffers[kind] = buffers[kind]
	_beam.buffer = _beam_buffer
	_beam.visible_instance_count = beams


func _place(id: int, kind: Kind, x: float, z: float, value: int) -> int:
	for slot: int in capacity:
		if alive[slot] == 0:
			alive[slot] = 1
			hidden[slot] = 0
			ids[slot] = id
			kinds[slot] = kind
			xs[slot] = x
			zs[slot] = z
			values[slot] = value
			_slot_of[id] = slot
			count += 1
			return id
	return -1


func _ground_y(x: float, z: float) -> float:
	return _ground.height_at(x, z) if _ground != null else 0.0


## Low-poly looks, colours stored linear like the map (MapBuilder.vertex_color_material()).
static func _mesh_for(kind: int) -> ArrayMesh:
	var parts: Array[Dictionary] = []
	var gold := Color(1.0, 0.8, 0.25)
	var wood := Color(0.55, 0.36, 0.2)
	match kind:
		Kind.COIN:
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.32, 0.32, 0.08, 12), Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), Vector3.ZERO), gold))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.2, 0.2, 0.1, 10), Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), Vector3.ZERO), gold.darkened(0.15)))
		Kind.CHEST, Kind.BOSS_CHEST:
			var trim: Color = gold if kind == Kind.BOSS_CHEST else Color(0.45, 0.45, 0.48)
			parts.append(MeshFactory._part(MeshFactory._box(Vector3(1.3, 0.75, 0.85)), Transform3D(Basis(), Vector3(0.0, 0.38, 0.0)), wood))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.43, 0.43, 1.3, 10), Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0)), Vector3(0.0, 0.76, 0.0)), wood.lightened(0.08)))
			for x: float in [-0.5, 0.5]:
				parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.12, 1.25, 0.9)), Transform3D(Basis(), Vector3(x, 0.6, 0.0)), trim))
			parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.22, 0.26, 0.08)), Transform3D(Basis(), Vector3(0.0, 0.72, 0.45)), gold))
		Kind.STEMPEL:
			# A big rubber stamp: wooden knob and handle, violet stamp pad.
			parts.append(MeshFactory._part(MeshFactory._sphere(0.28), Transform3D(Basis(), Vector3(0.0, 1.25, 0.0)), wood.lightened(0.15)))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.12, 0.14, 0.7, 8), Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), wood))
			parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.9, 0.22, 0.6)), Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)), wood.darkened(0.1)))
			parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.95, 0.12, 0.65)), Transform3D(Basis(), Vector3(0.0, 0.28, 0.0)), Color(0.45, 0.3, 0.65)))
		Kind.HEAL:
			# A bowl of Gulasch with a Semmel.
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.42, 0.3, 0.3, 12), Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)), Color(0.95, 0.95, 0.92)))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.38, 0.38, 0.04, 12), Transform3D(Basis(), Vector3(0.0, 0.29, 0.0)), Color(0.55, 0.3, 0.15)))
			parts.append(MeshFactory._part(MeshFactory._sphere(0.18), Transform3D(Basis(), Vector3(0.18, 0.35, 0.1)), Color(0.9, 0.72, 0.45)))
		Kind.HEART:
			# A small Lebkuchenherz standing up: two round lobes and a point, iced in white.
			var ginger := Color(0.62, 0.36, 0.18)
			var upright := Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))
			for x: float in [-0.13, 0.13]:
				parts.append(MeshFactory._part(MeshFactory._cylinder(0.17, 0.17, 0.08, 10), Transform3D(upright, Vector3(x, 0.08, 0.0)), ginger))
			parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.26, 0.26, 0.08)), Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI / 4.0)), Vector3(0.0, -0.08, 0.0)), ginger))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.07, 0.07, 0.1, 8), Transform3D(upright, Vector3(0.0, 0.02, 0.0)), Color(0.97, 0.95, 0.9)))
		Kind.FASSL:
			# A wine barrel on end with two iron hoops and a gold coin on the lid.
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.5, 0.42, 1.1, 12), Transform3D(Basis(), Vector3(0.0, 0.55, 0.0)), wood.lightened(0.1)))
			for y: float in [0.25, 0.85]:
				parts.append(MeshFactory._part(MeshFactory._cylinder(0.52, 0.5, 0.08, 12), Transform3D(Basis(), Vector3(0.0, y, 0.0)), Color(0.3, 0.3, 0.32)))
			parts.append(MeshFactory._part(MeshFactory._cylinder(0.2, 0.2, 0.06, 10), Transform3D(Basis(), Vector3(0.0, 1.12, 0.0)), gold))
	for part: Dictionary in parts:
		part["color"] = (part["color"] as Color).srgb_to_linear()
	return MeshFactory.merge(parts)
