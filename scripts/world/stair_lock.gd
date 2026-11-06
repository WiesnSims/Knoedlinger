class_name StairLock
extends Node3D
## Die Hausmeisterin sperrt das Stiegenhaus zu: the tall stairs and ramps of a map (MapProps of at
## least balance.stair_lock_min_height) can be locked for a while by a gate at their foot and one at
## their top. The gates stop players and Knödl (Jolt, LAYER_WORLD); enemies walk the baked ground
## field and pass ("de g'hörn eh zum Haus"). The host picks the stairs (BossDirector, Aim.STAIRWELL)
## and sends a LOCK run event; every machine finds the same stairs in its own copy of the map, puts
## the red mark up them and closes the gates when it hits.

const GATE_GREEN := Color(0.2, 0.36, 0.3)
const SIGN_WHITE := Color(0.95, 0.94, 0.9)
## The gates stand this far in from either end of the flight.
const INSET: float = 0.4

## Per stairwell: the middle of its foot and of its top (world), and its width.
var feet := PackedVector3Array()
var tops := PackedVector3Array()
var widths := PackedFloat32Array()
var lifts := PackedFloat32Array()
## The locked stairwell (-1 = none), seconds until its gates close and until they open again.
var locked: int = -1
var close_in: float = 0.0
var open_in: float = 0.0

var _balance: BalanceData
var _gates: Array[StaticBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _signs: Array[Label3D] = []


func setup(map: MapData, balance: BalanceData) -> void:
	name = "StairLock"
	_balance = balance
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for prop: MapProp in map.all_props():
		if (prop.kind != MapProp.Kind.RAMP and prop.kind != MapProp.Kind.STAIRS) or not prop.solid \
				or prop.size.y < balance.stair_lock_min_height:
			continue
		var along := Vector3(sin(deg_to_rad(prop.yaw_degrees)), 0.0, cos(deg_to_rad(prop.yaw_degrees)))
		var half: float = prop.size.z * 0.5
		feet.append(prop.position - along * half)
		tops.append(prop.position + along * half + Vector3(0.0, prop.size.y, 0.0))
		widths.append(prop.size.x)
		# The red mark lies on what the eye sees: stairs stand one step above their smooth collision.
		lifts.append(prop.size.y / maxi(prop.steps, 1) if prop.kind == MapProp.Kind.STAIRS else 0.0)
	if feet.is_empty():
		return
	# Two gates (foot and top), built once; only one stairwell is locked at a time.
	for k: int in 2:
		var gate := StaticBody3D.new()
		gate.name = "Gate%d" % k
		gate.collision_layer = MapBuilder.LAYER_WORLD
		gate.collision_mask = 0
		gate.visible = false
		gate.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(gate)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.disabled = true
		gate.add_child(shape)
		var look := MeshInstance3D.new()
		look.name = "Look"
		look.material_override = MapBuilder.vertex_color_material()
		gate.add_child(look)
		var sign := Label3D.new()
		sign.name = "Sign"
		sign.visibility_range_end = 45.0
		sign.font = UiStyle.font("number")
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.font_size = 64
		sign.pixel_size = 0.012
		sign.outline_size = 14
		sign.modulate = SIGN_WHITE
		sign.outline_modulate = Color(0.1, 0.16, 0.13)
		gate.add_child(sign)
		_gates.append(gate)
		_shapes.append(shape)
		_signs.append(sign)


## The stairwell nearest (x, z) whose flight passes within `reach` metres of it, or -1.
func nearest(x: float, z: float, reach: float) -> int:
	var best: int = -1
	var best_d: float = reach
	var p := Vector2(x, z)
	for k: int in feet.size():
		var a := Vector2(feet[k].x, feet[k].z)
		var b := Vector2(tops[k].x, tops[k].z)
		var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d <= best_d:
			best_d = d
			best = k
	return best


## The ends of the red mark up stairwell `k`.
func mark_foot(k: int) -> Vector3:
	return feet[k] + Vector3(0.0, lifts[k], 0.0)


func mark_top(k: int) -> Vector3:
	return tops[k] + Vector3(0.0, lifts[k], 0.0)


## True while a stairwell is locked or about to be.
func busy() -> bool:
	return locked >= 0


## Every machine: stairwell `k` closes in `delay` seconds (when its mark hits) for `seconds`.
func lock(k: int, delay: float, seconds: float) -> void:
	if k < 0 or k >= feet.size() or _gates.is_empty():
		return
	release()
	locked = k
	close_in = maxf(delay, 0.0)
	open_in = close_in + seconds


## Opens the gates at once (Sperrstund', the run's end).
func release() -> void:
	locked = -1
	for g: int in _gates.size():
		_show(g, false)


func update(delta: float) -> void:
	if locked < 0:
		return
	if close_in > 0.0:
		close_in -= delta
		if close_in <= 0.0:
			_close(locked)
	open_in -= delta
	if open_in <= 0.0:
		release()


func _close(k: int) -> void:
	var along: Vector3 = tops[k] - feet[k]
	along.y = 0.0
	along = along.normalized()
	var yaw: float = atan2(along.x, along.z)
	var height: float = _balance.stair_gate_height
	var size := Vector3(widths[k] + 0.4, height, 0.3)
	var at: Array[Vector3] = [feet[k] + along * INSET + Vector3(0.0, -0.3, 0.0), tops[k] - along * INSET + Vector3(0.0, -0.3, 0.0)]
	for g: int in _gates.size():
		var gate: StaticBody3D = _gates[g]
		gate.global_transform = Transform3D(Basis(Vector3.UP, yaw), at[g])
		(_shapes[g].shape as BoxShape3D).size = size
		_shapes[g].position = Vector3(0.0, height * 0.5, 0.0)
		(gate.get_node(^"Look") as MeshInstance3D).mesh = _gate_mesh(size)
		_signs[g].position = Vector3(0.0, height + 0.9, 0.0)
		_signs[g].text = tr("STAIRS_LOCKED")
		_show(g, true)


func _show(g: int, on: bool) -> void:
	_gates[g].visible = on
	_shapes[g].disabled = not on
	_gates[g].process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## A Gemeindebau iron gate: two posts, a top and bottom rail, bars between and the house rules
## (a white plate) in the middle. Never red: it is not an attack.
static func _gate_mesh(size: Vector3) -> ArrayMesh:
	var parts: Array[Dictionary] = []
	var half: float = size.x * 0.5
	for side: float in [-1.0, 1.0]:
		parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.22, size.y + 0.2, 0.22)), Transform3D(Basis(), Vector3(side * half, size.y * 0.5, 0.0)), GATE_GREEN.darkened(0.2)))
	for y: float in [0.25, size.y - 0.15]:
		parts.append(MeshFactory._part(MeshFactory._box(Vector3(size.x, 0.12, 0.12)), Transform3D(Basis(), Vector3(0.0, y, 0.0)), GATE_GREEN))
	var bars: int = maxi(int(size.x / 0.45), 3)
	for b: int in bars:
		var x: float = -half + size.x * (b + 0.5) / bars
		parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.06, size.y - 0.3, 0.06)), Transform3D(Basis(), Vector3(x, size.y * 0.5, 0.0)), GATE_GREEN))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(1.4, 0.9, 0.05)), Transform3D(Basis(), Vector3(0.0, size.y * 0.55, 0.12)), SIGN_WHITE))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(1.0, 0.08, 0.06)), Transform3D(Basis(), Vector3(0.0, size.y * 0.6, 0.13)), Color(0.15, 0.15, 0.15)))
	parts.append(MeshFactory._part(MeshFactory._box(Vector3(0.8, 0.08, 0.06)), Transform3D(Basis(), Vector3(0.0, size.y * 0.48, 0.13)), Color(0.15, 0.15, 0.15)))
	for part: Dictionary in parts:
		part["color"] = (part["color"] as Color).srgb_to_linear()
	return MeshFactory.merge(parts)
