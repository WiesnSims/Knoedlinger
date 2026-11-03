class_name ProjectilePool
extends Node3D
## Pooled projectiles as packed arrays, drawn with one MultiMesh (CLAUDE.md: no instantiate() or
## queue_free() in hot paths). Hits are checked against the enemies through EnemyManager's grid.
## Host only in M0; how clients see projectiles is decided in M6 (docs/DECISIONS.md).

const STRIDE: int = 12
const HEIGHT: float = 1.0

var balance: BalanceData
var capacity: int = 0
var active_count: int = 0
var hits: int = 0

var _alive: PackedByteArray = PackedByteArray()
var _x: PackedFloat32Array = PackedFloat32Array()
var _z: PackedFloat32Array = PackedFloat32Array()
var _vx: PackedFloat32Array = PackedFloat32Array()
var _vz: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
## Stack of free slots; _free_top is how many are on it.
var _free: PackedInt32Array = PackedInt32Array()
var _free_top: int = 0
var _multimesh: MultiMesh
var _buffer: PackedFloat32Array = PackedFloat32Array()


func setup(p_balance: BalanceData, p_capacity: int) -> void:
	balance = p_balance
	capacity = p_capacity
	# Redrawn from the packed arrays every rendered frame. With physics interpolation on, Godot would
	# also blend each MultiMesh instance with the previous tick by index; instances are repacked when
	# shots come and go, so that blended two different shots.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_alive.resize(capacity)
	_alive.fill(0)
	_x.resize(capacity)
	_z.resize(capacity)
	_vx.resize(capacity)
	_vz.resize(capacity)
	_life.resize(capacity)
	_free.resize(capacity)
	for i: int in capacity:
		_free[i] = capacity - 1 - i
	_free_top = capacity
	_buffer.resize(capacity * STRIDE)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = MeshFactory.projectile()
	_multimesh.instance_count = capacity
	_multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/projectile.gdshader")
	var instance := MultiMeshInstance3D.new()
	instance.name = "Projectiles"
	instance.multimesh = _multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 40.0, 2000.0))
	add_child(instance)


func has_free() -> bool:
	return _free_top > 0


## Fires from (x, z) in direction (dir_x, dir_z), which must be normalised. False when the pool is full.
func fire(x: float, z: float, dir_x: float, dir_z: float) -> bool:
	if _free_top == 0:
		return false
	_free_top -= 1
	var slot: int = _free[_free_top]
	_alive[slot] = 1
	_x[slot] = x
	_z[slot] = z
	_vx[slot] = dir_x * balance.projectile_speed
	_vz[slot] = dir_z * balance.projectile_speed
	_life[slot] = balance.projectile_lifetime
	active_count += 1
	return true


func update(delta: float, enemies: EnemyManager) -> void:
	var grid: SpatialHash = enemies.grid
	var reach: float = balance.projectile_radius
	var damage: float = balance.projectile_damage
	var max_enemy_radius: float = 0.6
	for i: int in capacity:
		if _alive[i] == 0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_release(i)
			continue
		var x: float = _x[i] + _vx[i] * delta
		var z: float = _z[i] + _vz[i] * delta
		_x[i] = x
		_z[i] = z
		var found: int = grid.query(x, z, reach + max_enemy_radius)
		for k: int in found:
			var j: int = grid.results[k]
			var dx: float = enemies.pos_x[j] - x
			var dz: float = enemies.pos_z[j] - z
			var rr: float = reach + enemies.radius[j]
			if dx * dx + dz * dz < rr * rr and enemies.alive[j] != 0:
				enemies.damage(j, damage)
				hits += 1
				_release(i)
				break
	_draw()


func _release(slot: int) -> void:
	_alive[slot] = 0
	_free[_free_top] = slot
	_free_top += 1
	active_count -= 1


func _draw() -> void:
	var o: int = 0
	for i: int in capacity:
		if _alive[i] == 0:
			continue
		_buffer[o] = 1.0
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = _x[i]
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = HEIGHT
		_buffer[o + 8] = 0.0
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = 1.0
		_buffer[o + 11] = _z[i]
		o += STRIDE
	_multimesh.buffer = _buffer
	_multimesh.visible_instance_count = o / STRIDE
