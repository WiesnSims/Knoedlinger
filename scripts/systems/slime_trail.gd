class_name SlimeTrail
extends Node3D
## The Weinbergschnecke's slime (EnemyTypeData.slime_slow): every machine drops trail spots behind
## the slimy enemies it sees (host: EnemyManager, clients: EnemyReplica), so nothing extra goes over
## the network, and slows its own player on them. One MultiMesh for all spots (one draw call).

const MAX_SPOTS: int = 384
## Floats per MultiMesh instance: transform 12, colour 4.
const STRIDE: int = 16
const COLOR := Color(0.78, 0.86, 0.55, 0.55)

## Seconds a spot lasts and seconds between two spots of one snail.
var lifetime: float = 5.0
var interval: float = 0.5
## Spot radius in metres.
var spot_radius: float = 0.9

## Per enemy type: the slow of its slime (0 = none).
var _slow: PackedFloat32Array = PackedFloat32Array()
var _any: bool = false
var _ground: Heightfield
var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _age := PackedFloat32Array()
var _spot_slow := PackedFloat32Array()
var _next: int = 0
var _timer: float = 0.0
var _mesh: MultiMesh
var _buffer := PackedFloat32Array()


func setup(types: Array[EnemyTypeData], ground: Heightfield, p_balance: BalanceData) -> void:
	_ground = ground
	lifetime = p_balance.slime_seconds
	interval = p_balance.slime_interval
	spot_radius = p_balance.slime_radius
	for t: EnemyTypeData in types:
		_slow.append(t.slime_slow)
		if t.slime_slow > 0.0:
			_any = true
	if not _any:
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for array: PackedFloat32Array in [_x, _z, _age, _spot_slow]:
		array.resize(MAX_SPOTS)
	_age.fill(INF)
	_mesh = MultiMesh.new()
	_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_mesh.mesh = quad
	_mesh.instance_count = MAX_SPOTS
	_mesh.visible_instance_count = 0
	_buffer.resize(MAX_SPOTS * STRIDE)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Slime"
	instance.multimesh = _mesh
	instance.material_override = make_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 150.0, 2000.0))
	add_child(instance)


## The spots' look (ShaderWarmup builds it ahead too).
static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Ages the spots and drops new ones behind every slimy enemy in the given arrays.
func update(delta: float, count: int, alive: PackedByteArray, xs: PackedFloat32Array, zs: PackedFloat32Array,
		types: PackedByteArray) -> void:
	if not _any:
		return
	for k: int in MAX_SPOTS:
		_age[k] += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		for i: int in count:
			if alive[i] != 0 and _slow[types[i]] > 0.0:
				_x[_next] = xs[i]
				_z[_next] = zs[i]
				_age[_next] = 0.0
				_spot_slow[_next] = _slow[types[i]]
				_next = (_next + 1) % MAX_SPOTS
	_draw()


## The speed factor for someone standing at `at` (1 = no slime).
func speed_factor(at: Vector3) -> float:
	if not _any:
		return 1.0
	var reach_sq: float = spot_radius * spot_radius
	var slow: float = 0.0
	for k: int in MAX_SPOTS:
		if _age[k] < lifetime and _spot_slow[k] > slow:
			var dx: float = _x[k] - at.x
			var dz: float = _z[k] - at.z
			if dx * dx + dz * dz < reach_sq and absf(at.y - _height(_x[k], _z[k])) < 1.0:
				slow = _spot_slow[k]
	return 1.0 - slow


func _draw() -> void:
	var o: int = 0
	var shown: int = 0
	for k: int in MAX_SPOTS:
		if _age[k] >= lifetime:
			continue
		var fade: float = 1.0 - _age[k] / lifetime
		var size: float = spot_radius * 2.0 * (0.7 + 0.3 * fade)
		var y: float = _height(_x[k], _z[k]) + 0.05
		_buffer[o] = size
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = _x[k]
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = y
		_buffer[o + 8] = 0.0
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = size
		_buffer[o + 11] = _z[k]
		_buffer[o + 12] = COLOR.r
		_buffer[o + 13] = COLOR.g
		_buffer[o + 14] = COLOR.b
		_buffer[o + 15] = COLOR.a * fade
		o += STRIDE
		shown += 1
	if shown > 0:
		_mesh.buffer = _buffer
	_mesh.visible_instance_count = shown


func _height(x: float, z: float) -> float:
	return _ground.height_at(x, z) if _ground != null else 0.0
