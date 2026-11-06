class_name HazardField
extends Node3D
## Telegraphed enemy attacks (GAME-DESIGN.md pillar 6): Krampus-red marks on the ground that fill
## up and then hit everyone inside. The host decides them (from elites' attack requests and boss
## patterns), resolves the hits and sends each new mark to the clients as a run event; every machine
## draws them the same way. One MultiMesh for all marks (one draw call).

const MAX_HAZARDS: int = 96
## A mark flashes this long after it hit, then disappears.
const FLASH_SECONDS: float = 0.25
## Floats per MultiMesh instance: transform 12, colour 4, custom 4.
const STRIDE: int = 20
## A dash along a line takes this long.
const DASH_SECONDS: float = 0.4


class Hazard:
	extends RefCounted
	var id: int = 0
	var shape: AttackData.Shape = AttackData.Shape.CIRCLE
	var x: float = 0.0
	var z: float = 0.0
	## LINE: direction in radians (atan2(dx, dz)); (x, z) is the line's start.
	var angle: float = 0.0
	var radius: float = 1.0
	var length: float = 0.0
	var telegraph: float = 1.0
	var left: float = 1.0
	var flash: float = 0.0
	# Host only.
	var attack: AttackData
	var source: int = -1
	## A mark up a flight of stairs: the height of its start (NAN = lies on the ground) and how much
	## higher its end is; `tag` is the stairwell (StairLock), -1 for every other mark.
	var base_y: float = NAN
	var rise: float = 0.0
	var tag: int = -1

	func end_x() -> float:
		return x + sin(angle) * length

	func end_z() -> float:
		return z + cos(angle) * length


var hazards: Array[Hazard] = []
## Host: marks made since the last take_new() (to send), and the ones that hit this update.
var made: Array[Hazard] = []
var hits: Array[Hazard] = []
## Every machine: marks that struck this update (for sound and screen shake).
var struck: Array[Hazard] = []

var _ground: Heightfield
var _next_id: int = 0
var _rng := RandomNumberGenerator.new()
var _mesh: MultiMesh
var _buffer := PackedFloat32Array()


func setup(ground: Heightfield, seed_value: int = 1) -> void:
	_ground = ground
	_rng.seed = seed_value
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = MultiMesh.new()
	_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.use_colors = true
	_mesh.use_custom_data = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_mesh.mesh = quad
	_mesh.instance_count = MAX_HAZARDS
	_mesh.visible_instance_count = 0
	_buffer.resize(MAX_HAZARDS * STRIDE)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/hazard.gdshader")
	var instance := MultiMeshInstance3D.new()
	instance.name = "Marks"
	instance.multimesh = _mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 150.0, 2000.0))
	add_child(instance)


## Host: the marks of one attack by an enemy at (sx, sz) aimed at (tx, tz). `source` is the
## attacker's slot (for dashes), -1 for none.
func start_attack(attack: AttackData, sx: float, sz: float, tx: float, tz: float, source: int = -1) -> void:
	if attack.shape == AttackData.Shape.CIRCLE and attack.aim == AttackData.Aim.SPIRAL:
		# Out from the attacker in two turns, one mark after the other.
		var count: int = maxi(attack.count, 1)
		var start: float = _rng.randf() * TAU
		for k: int in count:
			var share: float = float(k + 1) / count
			var around: float = start + share * TAU * 2.0
			var reach: float = attack.radius + share * maxf(attack.spread - attack.radius, 0.0)
			_make(attack, AttackData.Shape.CIRCLE, sx + cos(around) * reach, sz + sin(around) * reach, 0.0, source,
					attack.telegraph + k * attack.stagger)
		return
	match attack.shape:
		AttackData.Shape.LINE:
			var dx: float = tx - sx
			var dz: float = tz - sz
			var angle: float = atan2(dx, dz) if dx * dx + dz * dz > 0.0001 else _rng.randf() * TAU
			for k: int in maxi(attack.count, 1):
				var turn: float = (k - (attack.count - 1) * 0.5) * deg_to_rad(attack.spread)
				_make(attack, AttackData.Shape.LINE, sx, sz, angle + turn, source,
						attack.telegraph + k * attack.stagger if attack.stagger > 0.0 else -1.0)
		_:
			for k: int in maxi(attack.count, 1):
				var cx: float = tx
				var cz: float = tz
				match attack.aim:
					AttackData.Aim.SELF:
						cx = sx
						cz = sz
					AttackData.Aim.RING:
						var around: float = TAU * k / maxi(attack.count, 1)
						cx = sx + cos(around) * attack.spread
						cz = sz + sin(around) * attack.spread
					AttackData.Aim.TARGET:
						if k > 0:
							var scatter: float = _rng.randf() * TAU
							var reach: float = _rng.randf_range(0.4, 1.0) * attack.spread
							cx = tx + cos(scatter) * reach
							cz = tz + sin(scatter) * reach
				_make(attack, AttackData.Shape.CIRCLE, cx, cz, 0.0, source)


## Client: a mark the host made (from a run event).
func add_remote(id: int, shape: int, x: float, z: float, angle: float, radius: float, length: float, telegraph: float) -> void:
	if hazards.size() >= MAX_HAZARDS:
		return
	var h := Hazard.new()
	h.id = id
	h.shape = shape as AttackData.Shape
	h.x = x
	h.z = z
	h.angle = angle
	h.radius = radius
	h.length = length
	h.telegraph = telegraph
	h.left = telegraph
	hazards.append(h)


## A LINE up a slope from `foot` to `top` (world positions of its centre line), `radius` to each
## side. Host: `attack` decides the hit and the mark goes out (as StairLock's event); client: the
## look only, from its own copy of the map.
func add_slope(foot: Vector3, top: Vector3, radius: float, telegraph: float, attack: AttackData = null,
		source: int = -1, tag: int = -1) -> Hazard:
	if hazards.size() >= MAX_HAZARDS:
		return null
	var h := Hazard.new()
	_next_id = (_next_id + 1) & 0xFFFF
	h.id = _next_id
	h.shape = AttackData.Shape.LINE
	h.x = foot.x
	h.z = foot.z
	h.angle = atan2(top.x - foot.x, top.z - foot.z)
	h.length = Vector2(top.x - foot.x, top.z - foot.z).length()
	h.radius = radius
	h.base_y = foot.y
	h.rise = top.y - foot.y
	h.telegraph = telegraph
	h.left = telegraph
	h.attack = attack
	h.source = source
	h.tag = tag
	hazards.append(h)
	if attack != null:
		made.append(h)
	return h


## Counts every mark down; the host's marks that hit this update land in `hits`.
func update(delta: float) -> void:
	hits.clear()
	struck.clear()
	var k: int = 0
	while k < hazards.size():
		var h: Hazard = hazards[k]
		if h.left > 0.0:
			h.left -= delta
			if h.left <= 0.0:
				h.flash = FLASH_SECONDS
				struck.append(h)
				if h.attack != null:
					hits.append(h)
		else:
			h.flash -= delta
			if h.flash <= 0.0:
				hazards.remove_at(k)
				continue
		k += 1
	_draw()


## True when a body of `body_radius` at (px, pz) is inside the mark.
static func contains(h: Hazard, px: float, pz: float, body_radius: float) -> bool:
	if h.shape == AttackData.Shape.CIRCLE:
		var dx: float = px - h.x
		var dz: float = pz - h.z
		var reach: float = h.radius + body_radius
		return dx * dx + dz * dz < reach * reach
	var dir := Vector2(sin(h.angle), cos(h.angle))
	var rel := Vector2(px - h.x, pz - h.z)
	var along: float = rel.dot(dir)
	if along < -body_radius or along > h.length + body_radius:
		return false
	return absf(rel.dot(Vector2(dir.y, -dir.x))) < h.radius + body_radius


func take_made() -> Array[Hazard]:
	var out: Array[Hazard] = made
	made = []
	return out


func clear() -> void:
	hazards.clear()
	made.clear()
	hits.clear()
	_draw()


func _make(attack: AttackData, shape: AttackData.Shape, x: float, z: float, angle: float, source: int,
		telegraph: float = -1.0) -> void:
	if hazards.size() >= MAX_HAZARDS:
		return
	var h := Hazard.new()
	_next_id = (_next_id + 1) & 0xFFFF
	h.id = _next_id
	h.shape = shape
	h.x = x
	h.z = z
	h.angle = angle
	h.radius = attack.radius
	h.length = attack.length if shape == AttackData.Shape.LINE else 0.0
	h.telegraph = telegraph if telegraph > 0.0 else attack.telegraph
	h.left = h.telegraph
	h.attack = attack
	h.source = source
	hazards.append(h)
	made.append(h)


func _draw() -> void:
	if _mesh == null:
		return
	var o: int = 0
	for h: Hazard in hazards:
		var cx: float = h.x
		var cz: float = h.z
		var sx: float = h.radius * 2.0
		var sz: float = h.radius * 2.0
		var c: float = 1.0
		var s: float = 0.0
		var y: float = _ground_y(h.x, h.z)
		if h.shape == AttackData.Shape.LINE:
			cx = h.x + sin(h.angle) * h.length * 0.5
			cz = h.z + cos(h.angle) * h.length * 0.5
			sz = h.length
			c = cos(h.angle)
			s = sin(h.angle)
			y = maxf(y, maxf(_ground_y(cx, cz), _ground_y(h.end_x(), h.end_z())))
			if not is_nan(h.base_y):
				y = h.base_y + h.rise * 0.5
		elif h.radius > 2.0:
			y = maxf(y, maxf(_ground_y(h.x + h.radius * 0.7, h.z), _ground_y(h.x - h.radius * 0.7, h.z)))
		# Rotation around Y by the line's angle, scaled to its size.
		_buffer[o] = c * sx
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = s * sz
		_buffer[o + 3] = cx
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		# A mark up the stairs leans with them.
		_buffer[o + 6] = h.rise
		_buffer[o + 7] = y + 0.1
		_buffer[o + 8] = -s * sx
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = c * sz
		_buffer[o + 11] = cz
		_buffer[o + 12] = 1.0
		_buffer[o + 13] = 1.0
		_buffer[o + 14] = 1.0
		_buffer[o + 15] = 1.0
		_buffer[o + 16] = 1.0 - clampf(h.left / maxf(h.telegraph, 0.01), 0.0, 1.0)
		_buffer[o + 17] = 0.0 if h.shape == AttackData.Shape.CIRCLE else 1.0
		_buffer[o + 18] = clampf(h.flash / FLASH_SECONDS, 0.0, 1.0)
		_buffer[o + 19] = h.length / maxf(h.radius * 2.0, 0.01)
		o += STRIDE
	_mesh.buffer = _buffer
	_mesh.visible_instance_count = o / STRIDE


func _ground_y(x: float, z: float) -> float:
	return _ground.height_at(x, z) if _ground != null else 0.0
