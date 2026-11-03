class_name EnemyRenderer
extends Node3D
## Draws enemies from packed arrays: one MultiMeshInstance3D per enemy type plus one for all blob
## shadows, so 500 enemies cost (types + 1) draw calls. Used by the host's EnemyManager and by the
## client's EnemyReplica alike; it only reads the arrays it is given.

## Floats per instance in a MultiMesh buffer: 12 for the transform, 4 for the instance colour, 4 for
## custom data. The colour is always white: without instance colours the Compatibility renderer
## multiplies COLOR by stray per-instance data (seen in Godot 4.7.2, docs/DECISIONS.md).
const STRIDE: int = 20
const SHADOW_STRIDE: int = 12

var _types: Array[EnemyTypeData] = []
var _meshes: Array[MultiMesh] = []
var _buffers: Array[PackedFloat32Array] = []
var _shadow_mesh: MultiMesh
var _shadow_buffer: PackedFloat32Array = PackedFloat32Array()
var _capacity: int = 0


func setup(types: Array[EnemyTypeData], capacity: int) -> void:
	_types = types
	_capacity = capacity
	var waddle: Shader = load("res://shaders/enemy_waddle.gdshader")
	for type: EnemyTypeData in types:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = MeshFactory.enemy(type)
		multimesh.instance_count = capacity
		multimesh.visible_instance_count = 0
		var material := ShaderMaterial.new()
		material.shader = waddle
		material.set_shader_parameter(&"debug_view", LaunchArgs.get_int("debug_view", 0))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Enemies_%s" % type.id
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The crowd moves every frame; a huge AABB avoids recomputing it.
		instance.custom_aabb = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 40.0, 2000.0))
		add_child(instance)
		_meshes.append(multimesh)
		var buffer := PackedFloat32Array()
		buffer.resize(capacity * STRIDE)
		_buffers.append(buffer)
	_shadow_mesh = MultiMesh.new()
	_shadow_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_mesh.mesh = MeshFactory.blob_quad()
	_shadow_mesh.instance_count = capacity
	_shadow_mesh.visible_instance_count = 0
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = load("res://shaders/blob_shadow.gdshader")
	var shadows := MultiMeshInstance3D.new()
	shadows.name = "BlobShadows"
	shadows.multimesh = _shadow_mesh
	shadows.material_override = shadow_material
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadows.custom_aabb = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 40.0, 2000.0))
	add_child(shadows)
	_shadow_buffer.resize(capacity * SHADOW_STRIDE)


## Uploads all alive enemies. Arrays are indexed by slot; `yaw` in radians around +Y.
## One pass per type: a packed array taken out of `_buffers` is written in place only while nothing
## else holds it, otherwise every write would copy it.
func draw(slots: int, alive: PackedByteArray, x: PackedFloat32Array, z: PackedFloat32Array,
		yaw: PackedFloat32Array, type: PackedByteArray, radius: PackedFloat32Array,
		flash: PackedFloat32Array, phase: PackedFloat32Array) -> void:
	var used: int = mini(slots, _capacity)
	for t: int in _meshes.size():
		var buffer: PackedFloat32Array = _buffers[t]
		_buffers[t] = PackedFloat32Array()
		var scale: float = _types[t].model_scale
		var flyer: float = 1.0 if _types[t].flying else 0.0
		var o: int = 0
		for i: int in used:
			if alive[i] == 0 or type[i] != t:
				continue
			var c: float = cos(yaw[i]) * scale
			var s: float = sin(yaw[i]) * scale
			# Row-major 3x4 transform: rotation around Y times scale, then the origin.
			buffer[o] = c
			buffer[o + 1] = 0.0
			buffer[o + 2] = s
			buffer[o + 3] = x[i]
			buffer[o + 4] = 0.0
			buffer[o + 5] = scale
			buffer[o + 6] = 0.0
			buffer[o + 7] = flyer * 0.6
			buffer[o + 8] = -s
			buffer[o + 9] = 0.0
			buffer[o + 10] = c
			buffer[o + 11] = z[i]
			buffer[o + 12] = 1.0
			buffer[o + 13] = 1.0
			buffer[o + 14] = 1.0
			buffer[o + 15] = 1.0
			buffer[o + 16] = phase[i]
			buffer[o + 17] = flash[i]
			buffer[o + 18] = flyer
			buffer[o + 19] = 0.0
			o += STRIDE
		_meshes[t].buffer = buffer
		_meshes[t].visible_instance_count = o / STRIDE
		_buffers[t] = buffer
	var shadow_count: int = 0
	for i: int in used:
		if alive[i] == 0:
			continue
		var size: float = radius[i] * 2.4
		var so: int = shadow_count * SHADOW_STRIDE
		_shadow_buffer[so] = size
		_shadow_buffer[so + 1] = 0.0
		_shadow_buffer[so + 2] = 0.0
		_shadow_buffer[so + 3] = x[i]
		_shadow_buffer[so + 4] = 0.0
		_shadow_buffer[so + 5] = 1.0
		_shadow_buffer[so + 6] = 0.0
		_shadow_buffer[so + 7] = 0.02
		_shadow_buffer[so + 8] = 0.0
		_shadow_buffer[so + 9] = 0.0
		_shadow_buffer[so + 10] = size
		_shadow_buffer[so + 11] = z[i]
		shadow_count += 1
	_shadow_mesh.buffer = _shadow_buffer
	_shadow_mesh.visible_instance_count = shadow_count
