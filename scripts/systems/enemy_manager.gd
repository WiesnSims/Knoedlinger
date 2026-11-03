class_name EnemyManager
extends RefCounted
## All enemies as data, not nodes (CLAUDE.md performance rules). Runs on the host only; clients see
## them through snapshots (net/snapshot_codec.gd) and EnemyReplica. Every array is indexed by slot.
##
## Each frame: steer every alive enemy toward the nearest player, push it apart from its neighbours
## (from last frame's grid) and from the players, then rebuild the grid for projectiles and the next
## frame. Enemies far from every player only update every `enemy_far_update_interval` frames.

var balance: BalanceData
var types: Array[EnemyTypeData] = []
var capacity: int = 0
## How many slots should be alive; dead slots below this respawn after enemy_respawn_delay.
var target_count: int = 0
var grid: SpatialHash

var alive: PackedByteArray = PackedByteArray()
var type: PackedByteArray = PackedByteArray()
var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_z: PackedFloat32Array = PackedFloat32Array()
var yaw: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var max_hp: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var flash: PackedFloat32Array = PackedFloat32Array()
var phase: PackedFloat32Array = PackedFloat32Array()
var respawn_timer: PackedFloat32Array = PackedFloat32Array()

## Slots that spawned / died since the last take_events(), for the network's reliable events.
var spawned: PackedInt32Array = PackedInt32Array()
var died: PackedInt32Array = PackedInt32Array()
var alive_count: int = 0
var kills: int = 0
## Enemy-player touches this frame (contact damage comes with real HP in M1).
var contacts: int = 0

var _rng := RandomNumberGenerator.new()
var _frame: int = 0
var _weights_total: float = 0.0


func _init(p_balance: BalanceData, p_types: Array[EnemyTypeData], p_capacity: int, seed_value: int = 1) -> void:
	balance = p_balance
	types = p_types
	capacity = p_capacity
	_rng.seed = seed_value
	grid = SpatialHash.new(balance.arena_half_size, balance.grid_cell_size, capacity)
	alive.resize(capacity)
	type.resize(capacity)
	alive.fill(0)
	type.fill(0)
	for name: String in ["pos_x", "pos_z", "yaw", "hp", "max_hp", "speed", "radius", "flash", "phase", "respawn_timer"]:
		var array := PackedFloat32Array()
		array.resize(capacity)
		array.fill(0.0)
		set(name, array)
	for t: EnemyTypeData in types:
		_weights_total += t.spawn_weight


## Fills `count` slots right away around the given players (start of the stress test).
func populate(count: int, targets: PackedVector3Array) -> void:
	target_count = mini(count, capacity)
	for i: int in target_count:
		_spawn(i, targets)
	_rebuild_grid()


func update(delta: float, targets: PackedVector3Array) -> void:
	_frame += 1
	contacts = 0
	if targets.is_empty():
		return
	var far_sq: float = balance.enemy_far_distance * balance.enemy_far_distance
	var interval: int = maxi(balance.enemy_far_update_interval, 1)
	var half: float = balance.arena_half_size - 0.5
	var strength: float = balance.enemy_separation_strength
	var max_neighbors: int = balance.enemy_separation_max_neighbors
	var player_radius: float = balance.player_radius
	var head: PackedInt32Array = grid.head
	var next: PackedInt32Array = grid.next
	var columns: int = grid.columns
	var rows: int = grid.rows
	var inverse_cell: float = 1.0 / grid.cell_size
	var target_count_local: int = targets.size()
	for i: int in capacity:
		if alive[i] == 0:
			if i < target_count:
				respawn_timer[i] -= delta
				if respawn_timer[i] <= 0.0:
					_spawn(i, targets)
			continue
		if flash[i] > 0.0:
			flash[i] = maxf(flash[i] - delta * 6.0, 0.0)
		var x: float = pos_x[i]
		var z: float = pos_z[i]
		var best_sq: float = INF
		var tx: float = 0.0
		var tz: float = 0.0
		for t: int in target_count_local:
			var target: Vector3 = targets[t]
			var d_sq: float = (target.x - x) * (target.x - x) + (target.z - z) * (target.z - z)
			if d_sq < best_sq:
				best_sq = d_sq
				tx = target.x
				tz = target.z
		var step: float = delta
		if best_sq > far_sq:
			if (i + _frame) % interval != 0:
				continue
			step = delta * interval
		var distance: float = sqrt(best_sq)
		var r: float = radius[i]
		var vx: float = 0.0
		var vz: float = 0.0
		if distance > 0.001:
			vx = (tx - x) / distance * speed[i]
			vz = (tz - z) / distance * speed[i]
		# Keep out of the player's body instead of walking into it.
		var touch: float = r + player_radius
		if distance < touch:
			contacts += 1
			vx = 0.0
			vz = 0.0
			if distance > 0.001:
				var push: float = (touch - distance) / step
				vx = (x - tx) / distance * push
				vz = (z - tz) / distance * push
		# Separation from the neighbours in the 3 x 3 cells around.
		var px: float = 0.0
		var pz: float = 0.0
		var seen: int = 0
		var cx: int = clampi(int((x - grid.origin_x) * inverse_cell), 0, columns - 1)
		var cz: int = clampi(int((z - grid.origin_z) * inverse_cell), 0, rows - 1)
		for oz: int in range(maxi(cz - 1, 0), mini(cz + 2, rows)):
			if seen >= max_neighbors:
				break
			var row: int = oz * columns
			for ox: int in range(maxi(cx - 1, 0), mini(cx + 2, columns)):
				var j: int = head[row + ox]
				while j >= 0 and seen < max_neighbors:
					if j != i:
						var dx: float = x - pos_x[j]
						var dz: float = z - pos_z[j]
						var d_sq: float = dx * dx + dz * dz
						var rr: float = r + radius[j]
						if d_sq < rr * rr and d_sq > 0.000001:
							var d: float = sqrt(d_sq)
							px += dx / d * (rr - d)
							pz += dz / d * (rr - d)
							seen += 1
					j = next[j]
		vx += px * strength
		vz += pz * strength
		x = clampf(x + vx * step, -half, half)
		z = clampf(z + vz * step, -half, half)
		pos_x[i] = x
		pos_z[i] = z
		if vx * vx + vz * vz > 0.01:
			yaw[i] = atan2(vx, vz)
	# Drop the local views first, or rebuilding the grid would copy its arrays.
	head = PackedInt32Array()
	next = PackedInt32Array()
	_rebuild_grid()


## Returns true when this hit killed the enemy.
func damage(slot: int, amount: float) -> bool:
	if alive[slot] == 0:
		return false
	hp[slot] -= amount
	flash[slot] = 1.0
	if hp[slot] > 0.0:
		return false
	alive[slot] = 0
	alive_count -= 1
	kills += 1
	respawn_timer[slot] = balance.enemy_respawn_delay
	died.append(slot)
	return true


## HP as 0..15 for the snapshot (4 bits).
func hp_bucket(slot: int) -> int:
	return clampi(ceili(hp[slot] / max_hp[slot] * 15.0), 0, 15)


func take_events() -> Array[PackedInt32Array]:
	var events: Array[PackedInt32Array] = [spawned, died]
	spawned = PackedInt32Array()
	died = PackedInt32Array()
	return events


func _spawn(slot: int, targets: PackedVector3Array) -> void:
	var t: int = _pick_type()
	var data: EnemyTypeData = types[t]
	var center: Vector3 = targets[_rng.randi_range(0, targets.size() - 1)] if not targets.is_empty() else Vector3.ZERO
	var angle: float = _rng.randf() * TAU
	var distance: float = _rng.randf_range(balance.enemy_spawn_ring_min, balance.enemy_spawn_ring_max)
	var half: float = balance.arena_half_size - 0.5
	pos_x[slot] = clampf(center.x + cos(angle) * distance, -half, half)
	pos_z[slot] = clampf(center.z + sin(angle) * distance, -half, half)
	yaw[slot] = angle + PI
	type[slot] = t
	hp[slot] = data.max_hp
	max_hp[slot] = data.max_hp
	speed[slot] = data.speed * _rng.randf_range(0.85, 1.15)
	radius[slot] = data.radius
	flash[slot] = 0.0
	phase[slot] = _rng.randf() * TAU
	if alive[slot] == 0:
		alive_count += 1
	alive[slot] = 1
	spawned.append(slot)


func _pick_type() -> int:
	var roll: float = _rng.randf() * _weights_total
	for t: int in types.size():
		roll -= types[t].spawn_weight
		if roll <= 0.0:
			return t
	return types.size() - 1


func _rebuild_grid() -> void:
	grid.clear()
	for i: int in capacity:
		if alive[i] != 0:
			grid.insert(i, pos_x[i], pos_z[i])
