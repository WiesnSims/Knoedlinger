class_name ProjectilePool
extends Node3D
## Pooled projectiles as packed arrays, drawn with one MultiMesh (CLAUDE.md: no instantiate() or
## queue_free() in hot paths). Hits are checked against the enemies through EnemyManager's grid; a
## shot passes through `pierce` enemies before it is used up. On a client the pool only shows
## shots (update() without enemies): each player's weapon fire counter tells it when to fire, so
## the shots fly where the host's do without being sent.

const STRIDE: int = 12
## Shots fly this high above the ground.
const HEIGHT: float = 1.0

var balance: BalanceData
var capacity: int = 0
var active_count: int = 0
var hits: int = 0
## Shots fly over this ground; null = flat at y = 0 (stress test).
var ground: Heightfield

var _alive: PackedByteArray = PackedByteArray()
var _x: PackedFloat32Array = PackedFloat32Array()
var _z: PackedFloat32Array = PackedFloat32Array()
var _vx: PackedFloat32Array = PackedFloat32Array()
var _vz: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _damage: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _knockback: PackedFloat32Array = PackedFloat32Array()
var _pierce: PackedInt32Array = PackedInt32Array()
## The enemy slot hit last, so a piercing shot does not hit the same one on the next frame.
var _last_hit: PackedInt32Array = PackedInt32Array()
## Boomerangs: the lifetime left at which they turn (-1 = never); the weapon whose statuses apply.
var _turn_at: PackedFloat32Array = PackedFloat32Array()
var _weapons: Array[WeaponData] = []
## Lobbed shots: seconds between landings (0 = a plain shot) and the time since the last one.
var _hop_every: PackedFloat32Array = PackedFloat32Array()
var _hop_t: PackedFloat32Array = PackedFloat32Array()
var _hop_height: PackedFloat32Array = PackedFloat32Array()
## Stack of free slots; _free_top is how many are on it.
var _free: PackedInt32Array = PackedInt32Array()
var _free_top: int = 0
var _multimesh: MultiMesh
var _buffer: PackedFloat32Array = PackedFloat32Array()


func setup(p_balance: BalanceData, p_capacity: int, p_ground: Heightfield = null) -> void:
	balance = p_balance
	capacity = p_capacity
	ground = p_ground
	# Redrawn from the packed arrays every rendered frame. With physics interpolation on, Godot would
	# also blend each MultiMesh instance with the previous tick by index; instances are repacked when
	# shots come and go, so that blended two different shots.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_alive.resize(capacity)
	_alive.fill(0)
	for array_name: String in ["_x", "_z", "_vx", "_vz", "_life", "_damage", "_radius", "_knockback", "_turn_at",
			"_hop_every", "_hop_t", "_hop_height"]:
		var array := PackedFloat32Array()
		array.resize(capacity)
		array.fill(0.0)
		set(array_name, array)
	_pierce.resize(capacity)
	_weapons.resize(capacity)
	_last_hit.resize(capacity)
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
	instance.custom_aabb = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 80.0, 2000.0))
	add_child(instance)


func has_free() -> bool:
	return _free_top > 0


## The stress test's shot: the balance numbers, stops at the first enemy. `dir` must be normalised.
func fire(x: float, z: float, dir_x: float, dir_z: float) -> bool:
	return fire_shot(x, z, dir_x * balance.projectile_speed, dir_z * balance.projectile_speed,
			balance.projectile_lifetime, balance.projectile_damage, balance.projectile_radius, 0, 0.0)


## Fires one shot from (x, z) with velocity (vx, vz). False when the pool is full.
## A boomerang turns round after half its lifetime; `weapon` adds its on-hit statuses (burn, slow).
## A lobbed shot (`hops` > 0) hits nothing in flight: it lands `hops` times over its lifetime and
## splashes `radius` around each landing.
func fire_shot(x: float, z: float, vx: float, vz: float, lifetime: float, damage: float, radius: float,
		pierce: int, knockback: float, boomerang: bool = false, weapon: WeaponData = null, hops: int = 0) -> bool:
	if _free_top == 0:
		return false
	_free_top -= 1
	var slot: int = _free[_free_top]
	_alive[slot] = 1
	_x[slot] = x
	_z[slot] = z
	_vx[slot] = vx
	_vz[slot] = vz
	_life[slot] = lifetime
	_damage[slot] = damage
	_radius[slot] = radius
	_pierce[slot] = pierce
	_knockback[slot] = knockback
	_last_hit[slot] = -1
	_turn_at[slot] = lifetime * 0.5 if boomerang else -1.0
	_weapons[slot] = weapon
	_hop_every[slot] = lifetime / hops if hops > 0 else 0.0
	_hop_t[slot] = 0.0
	_hop_height[slot] = weapon.hop_height if weapon != null else 0.0
	if hops > 0:
		# Half a hop to spare, so float drift never ends it before its last landing.
		_life[slot] = lifetime + _hop_every[slot] * 0.5
	active_count += 1
	return true


## Moves every shot; with `enemies` (host) they hit, without (client) they only fly.
func update(delta: float, enemies: EnemyManager) -> void:
	var grid: SpatialHash = enemies.grid if enemies != null else null
	var max_enemy_radius: float = 0.6
	for i: int in capacity:
		if _alive[i] == 0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_release(i)
			continue
		if _turn_at[i] >= 0.0 and _life[i] <= _turn_at[i]:
			# The tray comes back the way it went, and may hit everything again.
			_turn_at[i] = -1.0
			_vx[i] = -_vx[i]
			_vz[i] = -_vz[i]
			_last_hit[i] = -1
		var x: float = _x[i] + _vx[i] * delta
		var z: float = _z[i] + _vz[i] * delta
		_x[i] = x
		_z[i] = z
		if _hop_every[i] > 0.0:
			_hop_t[i] += delta
			if _hop_t[i] >= _hop_every[i]:
				_hop_t[i] -= _hop_every[i]
				if grid != null:
					hits += 1
					WeaponSystem.blast(_weapons[i], enemies, x, z, _radius[i], _damage[i], 0.0, _knockback[i])
				if _life[i] < _hop_every[i]:
					_release(i)
			continue
		if grid == null:
			continue
		var reach: float = _radius[i]
		var found: int = grid.query(x, z, reach + max_enemy_radius)
		for k: int in found:
			var j: int = grid.results[k]
			if j == _last_hit[i] or enemies.alive[j] == 0:
				continue
			var dx: float = enemies.pos_x[j] - x
			var dz: float = enemies.pos_z[j] - z
			var rr: float = reach + enemies.radius[j]
			if dx * dx + dz * dz >= rr * rr:
				continue
			var kick: float = _knockback[i] / maxf(sqrt(_vx[i] * _vx[i] + _vz[i] * _vz[i]), 0.001)
			if _weapons[i] != null:
				WeaponSystem.apply_hit(_weapons[i], enemies, j, _damage[i], _vx[i] * kick, _vz[i] * kick)
			else:
				enemies.damage(j, _damage[i], _vx[i] * kick, _vz[i] * kick)
			hits += 1
			_last_hit[i] = j
			if _pierce[i] <= 0:
				_release(i)
				break
			_pierce[i] -= 1
	_draw()


func _release(slot: int) -> void:
	_alive[slot] = 0
	_free[_free_top] = slot
	_free_top += 1
	active_count -= 1


func _draw() -> void:
	var o: int = 0
	var has_ground: bool = ground != null
	for i: int in capacity:
		if _alive[i] == 0:
			continue
		# Pointing along the flight: rotation around Y so the shot's +z follows its velocity.
		var speed: float = sqrt(_vx[i] * _vx[i] + _vz[i] * _vz[i])
		var s: float = _vx[i] / speed if speed > 0.001 else 0.0
		var c: float = _vz[i] / speed if speed > 0.001 else 1.0
		var y: float = HEIGHT + (ground.height_at(_x[i], _z[i]) if has_ground else 0.0)
		if _hop_every[i] > 0.0:
			var p: float = _hop_t[i] / _hop_every[i]
			y += 4.0 * p * (1.0 - p) * _hop_height[i] - HEIGHT * 0.6
		_buffer[o] = c
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = s
		_buffer[o + 3] = _x[i]
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = y
		_buffer[o + 8] = -s
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = c
		_buffer[o + 11] = _z[i]
		o += STRIDE
	_multimesh.buffer = _buffer
	_multimesh.visible_instance_count = o / STRIDE
