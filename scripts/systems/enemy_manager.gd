class_name EnemyManager
extends RefCounted
## All enemies as data, not nodes (CLAUDE.md performance rules). Runs on the host only; clients see
## them through snapshots (net/snapshot_codec.gd) and EnemyReplica. Every array is indexed by slot.
##
## Each frame: steer every alive enemy toward the nearest player (Bröselfresser: the nearest Knödl,
## which they nibble at), push it apart from its neighbours
## (from last frame's grid) and from the players, then rebuild the grid for weapons, the Knödl and
## the next frame. Enemies far from every player only update every `enemy_far_update_interval`
## frames. Enemies move in x/z; their height is the map's baked ground (docs/DECISIONS.md).

var balance: BalanceData
var types: Array[EnemyTypeData] = []
var capacity: int = 0
## How many slots should be alive; dead slots below this respawn after respawn_delay.
var target_count: int = 0
var respawn_delay: float = 0.0
## Spawn mix per type (WaveData.weights_at); empty = EnemyTypeData.spawn_weight.
var type_weights: PackedFloat32Array = PackedFloat32Array()
## New enemies get their type's max HP times this (time and co-op scaling), and their speed times
## speed_mult (the Grant level).
var hp_mult: float = 1.0
var speed_mult: float = 1.0
## New enemies appear on a ring this far from a random player.
var ring_min: float = 0.0
var ring_max: float = 0.0
## While spawn_sector_width > 0, new enemies only come from that slice of the ring (radians around
## spawn_sector_angle): a wave from one direction (the Touristenbus).
var spawn_sector_angle: float = 0.0
var spawn_sector_width: float = 0.0
var grid: SpatialHash
## The ground enemies walk on; null = flat at y = 0 (stress test).
var ground: Heightfield
## Enemies stay inside +-bounds on x and z.
var bounds: float = 0.0

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
## Knockback velocity, dying away over time.
var kb_x: PackedFloat32Array = PackedFloat32Array()
var kb_z: PackedFloat32Array = PackedFloat32Array()
## Seconds until a Knödl may hurt this enemy again.
var knodl_timer: PackedFloat32Array = PackedFloat32Array()
## Elites: seconds until their attack is ready again, and seconds they still stand still while
## their telegraph fills up.
var attack_timer: PackedFloat32Array = PackedFloat32Array()
var busy: PackedFloat32Array = PackedFloat32Array()
## A dash along an attack line: velocity and seconds left.
var dash_x: PackedFloat32Array = PackedFloat32Array()
var dash_z: PackedFloat32Array = PackedFloat32Array()
var dash_time: PackedFloat32Array = PackedFloat32Array()
## 1 = moved by someone else (BossDirector), not by the crowd logic.
var controlled: PackedByteArray = PackedByteArray()

## Attacks elites started this update (slot and the target point), for the HazardField; the
## caller empties them.
var attack_slot: PackedInt32Array = PackedInt32Array()
var attack_x: PackedFloat32Array = PackedFloat32Array()
var attack_z: PackedFloat32Array = PackedFloat32Array()
## Type of each enemy in the kill list (gold drops, boss deaths).
var kill_type: PackedInt32Array = PackedInt32Array()
## Slot of each enemy in the kill list.
var kill_slot: PackedInt32Array = PackedInt32Array()

## Slots that spawned / died since the last take_events(), for the network's reliable events.
var spawned: PackedInt32Array = PackedInt32Array()
var died: PackedInt32Array = PackedInt32Array()
## Where enemies died since the last clear_kills() and how much XP they drop (for Brösel).
var kill_x: PackedFloat32Array = PackedFloat32Array()
var kill_z: PackedFloat32Array = PackedFloat32Array()
var kill_xp: PackedInt32Array = PackedInt32Array()
var alive_count: int = 0
var kills: int = 0
## Enemy-player touches this frame.
var contacts: int = 0
## Per target of the last update(): the highest contact damage of any enemy touching it this frame.
var touch_damage: PackedFloat32Array = PackedFloat32Array()
## Per Knödl of the last update(): the mass Bröselfresser bit off it this frame.
var knodl_bites: PackedFloat32Array = PackedFloat32Array()

var _rng := RandomNumberGenerator.new()
var _frame: int = 0
var _eats: PackedByteArray = PackedByteArray()
var _bites: PackedFloat32Array = PackedFloat32Array()
## Per type: its attack (or null) and the type index it splits into (-1 = none).
var _attacks: Array[AttackData] = []
var _split_type: PackedInt32Array = PackedInt32Array()


func _init(p_balance: BalanceData, p_types: Array[EnemyTypeData], p_capacity: int, seed_value: int = 1,
		p_ground: Heightfield = null, p_bounds: float = -1.0) -> void:
	balance = p_balance
	types = p_types
	capacity = p_capacity
	ground = p_ground
	bounds = p_bounds if p_bounds > 0.0 else balance.arena_half_size
	respawn_delay = balance.enemy_respawn_delay
	ring_min = balance.enemy_spawn_ring_min
	ring_max = balance.enemy_spawn_ring_max
	_rng.seed = seed_value
	grid = SpatialHash.new(bounds, balance.grid_cell_size, capacity)
	alive.resize(capacity)
	type.resize(capacity)
	alive.fill(0)
	type.fill(0)
	for name: String in ["pos_x", "pos_z", "yaw", "hp", "max_hp", "speed", "radius", "flash", "phase",
			"respawn_timer", "kb_x", "kb_z", "knodl_timer", "attack_timer", "busy", "dash_x", "dash_z", "dash_time"]:
		var array := PackedFloat32Array()
		array.resize(capacity)
		array.fill(0.0)
		set(name, array)
	controlled.resize(capacity)
	controlled.fill(0)
	for t: EnemyTypeData in types:
		_eats.append(1 if t.eats_knodl else 0)
		_bites.append(t.bite_per_second)
		_attacks.append(t.attack)
		_split_type.append(types.find(t.split_into) if t.split_into != null else -1)


## Fills `count` slots right away around the given players (start of the stress test).
func populate(count: int, targets: PackedVector3Array) -> void:
	target_count = mini(count, capacity)
	for i: int in target_count:
		_spawn(i, targets)
	_rebuild_grid()


## The ground height at any x/z.
func ground_at(x: float, z: float) -> float:
	return ground.height_at(x, z) if ground != null else 0.0


## `targets` are the players to chase; `knodls` (x, y, z, radius) the Knödl Bröselfresser go for
## (the caller leaves out Knödl they must ignore).
func update(delta: float, targets: PackedVector3Array, knodls: PackedVector4Array = PackedVector4Array()) -> void:
	_frame += 1
	contacts = 0
	var target_total: int = targets.size()
	touch_damage.resize(target_total)
	touch_damage.fill(0.0)
	var knodl_total: int = knodls.size()
	knodl_bites.resize(knodl_total)
	knodl_bites.fill(0.0)
	if targets.is_empty():
		return
	var far_sq: float = balance.enemy_far_distance * balance.enemy_far_distance
	var interval: int = maxi(balance.enemy_far_update_interval, 1)
	var half: float = bounds - 0.5
	var strength: float = balance.enemy_separation_strength
	var max_neighbors: int = balance.enemy_separation_max_neighbors
	var player_radius: float = balance.player_radius
	var contact_height: float = balance.enemy_contact_height
	var climb_slope: float = balance.enemy_climb_slope
	var climb_min: float = balance.enemy_climb_min_factor
	var kb_keep: float = exp(-balance.enemy_knockback_decay * delta)
	var head: PackedInt32Array = grid.head
	var next: PackedInt32Array = grid.next
	var columns: int = grid.columns
	var rows: int = grid.rows
	var inverse_cell: float = 1.0 / grid.cell_size
	var has_ground: bool = ground != null
	for i: int in capacity:
		if alive[i] == 0:
			if i < target_count:
				respawn_timer[i] -= delta
				if respawn_timer[i] <= 0.0:
					_spawn(i, targets)
			continue
		if flash[i] > 0.0:
			flash[i] = maxf(flash[i] - delta * 6.0, 0.0)
		if knodl_timer[i] > 0.0:
			knodl_timer[i] -= delta
		if controlled[i] != 0:
			continue
		var x: float = pos_x[i]
		var z: float = pos_z[i]
		var best_sq: float = INF
		var best: int = 0
		var eater: bool = knodl_total > 0 and _eats[type[i]] != 0
		var tx: float = 0.0
		var tz: float = 0.0
		if eater:
			for k: int in knodl_total:
				var knodl: Vector4 = knodls[k]
				var d_sq: float = (knodl.x - x) * (knodl.x - x) + (knodl.z - z) * (knodl.z - z)
				if d_sq < best_sq:
					best_sq = d_sq
					best = k
			tx = knodls[best].x
			tz = knodls[best].z
		else:
			for t: int in target_total:
				var target: Vector3 = targets[t]
				var d_sq: float = (target.x - x) * (target.x - x) + (target.z - z) * (target.z - z)
				if d_sq < best_sq:
					best_sq = d_sq
					best = t
			tx = targets[best].x
			tz = targets[best].z
		var step: float = delta
		var knocked: bool = kb_x[i] != 0.0 or kb_z[i] != 0.0
		if best_sq > far_sq and not knocked:
			if (i + _frame) % interval != 0:
				continue
			step = delta * interval
		var distance: float = sqrt(best_sq)
		var r: float = radius[i]
		var vx: float = 0.0
		var vz: float = 0.0
		# Elites start their attack when the target is in range, then stand still while the mark
		# on the ground fills up (or dash along their line once it hits).
		var attack: AttackData = _attacks[type[i]]
		if attack != null and not eater:
			attack_timer[i] -= step
			if attack_timer[i] <= 0.0 and busy[i] <= 0.0 and dash_time[i] <= 0.0 and distance < attack.range:
				attack_timer[i] = attack.cooldown * _rng.randf_range(0.85, 1.15)
				busy[i] = attack.telegraph + 0.25
				attack_slot.append(i)
				attack_x.append(tx)
				attack_z.append(tz)
		if dash_time[i] > 0.0:
			dash_time[i] -= step
			vx = dash_x[i]
			vz = dash_z[i]
		elif busy[i] > 0.0:
			busy[i] -= step
			yaw[i] = atan2(tx - x, tz - z)
		elif distance > 0.001:
			vx = (tx - x) / distance * speed[i]
			vz = (tz - z) / distance * speed[i]
		# Keep out of the player's body instead of walking into it, and hurt them on touch. A player
		# standing well above or below (a ledge, a jump) is out of reach. Bröselfresser stop at the
		# Knödl and eat.
		var touch: float = r + (knodls[best].w + 0.1 if eater else player_radius)
		if eater:
			if distance < touch + 0.15:
				var gy: float = ground.height_at(x, z) if has_ground else 0.0
				if absf(knodls[best].y - gy) < knodls[best].w + contact_height:
					knodl_bites[best] += _bites[type[i]] * step
				vx = 0.0
				vz = 0.0
				if distance > 0.001 and distance < touch:
					var push: float = (touch - distance) / step
					vx = (x - tx) / distance * push
					vz = (z - tz) / distance * push
		elif distance < touch:
			var gy: float = ground.height_at(x, z) if has_ground else 0.0
			if absf(targets[best].y - gy) < contact_height:
				contacts += 1
				var hurt: float = types[type[i]].contact_damage
				if hurt > touch_damage[best]:
					touch_damage[best] = hurt
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
		if knocked:
			vx += kb_x[i]
			vz += kb_z[i]
			kb_x[i] *= kb_keep
			kb_z[i] *= kb_keep
			if kb_x[i] * kb_x[i] + kb_z[i] * kb_z[i] < 0.01:
				kb_x[i] = 0.0
				kb_z[i] = 0.0
		var nx: float = clampf(x + vx * step, -half, half)
		var nz: float = clampf(z + vz * step, -half, half)
		# Walkers slow down on steep ground and scramble up walls; fliers do not care.
		if has_ground and not types[type[i]].flying:
			var moved: float = sqrt((nx - x) * (nx - x) + (nz - z) * (nz - z))
			if moved > 0.0001:
				var rise: float = (ground.height_at(nx, nz) - ground.height_at(x, z)) / moved
				if rise > climb_slope:
					var factor: float = maxf(climb_slope / rise, climb_min)
					nx = x + (nx - x) * factor
					nz = z + (nz - z) * factor
		pos_x[i] = nx
		pos_z[i] = nz
		if vx * vx + vz * vz > 0.01:
			yaw[i] = atan2(vx, vz)
	# Drop the local views first, or rebuilding the grid would copy its arrays.
	head = PackedInt32Array()
	next = PackedInt32Array()
	_rebuild_grid()


## Returns true when this hit killed the enemy. (kx, kz) is a knockback velocity to add.
func damage(slot: int, amount: float, kx: float = 0.0, kz: float = 0.0) -> bool:
	if alive[slot] == 0:
		return false
	hp[slot] -= amount
	flash[slot] = 1.0
	if kx != 0.0 or kz != 0.0:
		var factor: float = types[type[slot]].knockback_factor
		kb_x[slot] += kx * factor
		kb_z[slot] += kz * factor
	if hp[slot] > 0.0:
		return false
	alive[slot] = 0
	alive_count -= 1
	kills += 1
	respawn_timer[slot] = respawn_delay
	kb_x[slot] = 0.0
	kb_z[slot] = 0.0
	died.append(slot)
	kill_x.append(pos_x[slot])
	kill_z.append(pos_z[slot])
	kill_xp.append(types[type[slot]].brosel_xp)
	kill_type.append(type[slot])
	kill_slot.append(slot)
	controlled[slot] = 0
	var split: int = _split_type[type[slot]]
	if split >= 0:
		for k: int in types[type[slot]].split_count:
			var angle: float = TAU * k / maxi(types[type[slot]].split_count, 1)
			spawn_at(split, pos_x[slot] + cos(angle) * 0.8, pos_z[slot] + sin(angle) * 0.8)
	return true


## Puts one enemy of type `t` at (x, z) right away, outside the normal crowd if a spare slot is
## free (bosses, summons, splits). `is_controlled`: BossDirector moves it. Returns the slot or -1.
func spawn_at(t: int, x: float, z: float, is_controlled: bool = false, hp_scale: float = 1.0) -> int:
	var slot: int = -1
	for i: int in range(capacity - 1, -1, -1):
		if alive[i] == 0 and (i >= target_count or slot < 0):
			slot = i
			if i >= target_count:
				break
	if slot < 0:
		return -1
	_reset(slot, t)
	var half: float = bounds - 0.5
	pos_x[slot] = clampf(x, -half, half)
	pos_z[slot] = clampf(z, -half, half)
	hp[slot] *= hp_scale
	max_hp[slot] *= hp_scale
	controlled[slot] = 1 if is_controlled else 0
	return slot


## Sends an enemy along (dx, dz) at `dash_speed` for `seconds` (an attack line's dash).
func start_dash(slot: int, dx: float, dz: float, dash_speed: float, seconds: float) -> void:
	var length: float = sqrt(dx * dx + dz * dz)
	if alive[slot] == 0 or length < 0.001:
		return
	dash_x[slot] = dx / length * dash_speed
	dash_z[slot] = dz / length * dash_speed
	dash_time[slot] = seconds
	busy[slot] = 0.0
	yaw[slot] = atan2(dx, dz)


## Empties the attack requests once the caller has read them.
func clear_attacks() -> void:
	attack_slot.clear()
	attack_x.clear()
	attack_z.clear()


## Removes an enemy without a kill (no Brösel, no kill count): the Riesen-Wirt sweeps it out.
func despawn(slot: int) -> void:
	if alive[slot] == 0:
		return
	alive[slot] = 0
	alive_count -= 1
	respawn_timer[slot] = respawn_delay
	kb_x[slot] = 0.0
	kb_z[slot] = 0.0
	controlled[slot] = 0
	died.append(slot)


## Moves an enemy (pushed out of a Knödl, for example), staying inside the bounds.
func shove(slot: int, x: float, z: float) -> void:
	var half: float = bounds - 0.5
	pos_x[slot] = clampf(x, -half, half)
	pos_z[slot] = clampf(z, -half, half)


## HP as 0..15 for the snapshot (4 bits).
func hp_bucket(slot: int) -> int:
	return clampi(ceili(hp[slot] / max_hp[slot] * 15.0), 0, 15)


func take_events() -> Array[PackedInt32Array]:
	var events: Array[PackedInt32Array] = [spawned, died]
	spawned = PackedInt32Array()
	died = PackedInt32Array()
	return events


## Empties the kill list once the caller has read kill_x / kill_z / kill_xp.
func clear_kills() -> void:
	kill_x.clear()
	kill_z.clear()
	kill_xp.clear()
	kill_type.clear()
	kill_slot.clear()


func _spawn(slot: int, targets: PackedVector3Array) -> void:
	var t: int = _pick_type()
	var center: Vector3 = targets[_rng.randi_range(0, targets.size() - 1)] if not targets.is_empty() else Vector3.ZERO
	var angle: float = _rng.randf() * TAU
	if spawn_sector_width > 0.0:
		angle = spawn_sector_angle + _rng.randf_range(-0.5, 0.5) * spawn_sector_width
	var distance: float = _rng.randf_range(ring_min, ring_max)
	var half: float = bounds - 0.5
	_reset(slot, t)
	pos_x[slot] = clampf(center.x + cos(angle) * distance, -half, half)
	pos_z[slot] = clampf(center.z + sin(angle) * distance, -half, half)
	yaw[slot] = angle + PI


## A fresh enemy of type `t` in `slot` (position set by the caller).
func _reset(slot: int, t: int) -> void:
	var data: EnemyTypeData = types[t]
	type[slot] = t
	controlled[slot] = 0
	busy[slot] = 0.0
	dash_time[slot] = 0.0
	attack_timer[slot] = _rng.randf_range(1.0, data.attack.cooldown) if data.attack != null else 0.0
	hp[slot] = data.max_hp * hp_mult
	max_hp[slot] = data.max_hp * hp_mult
	speed[slot] = data.speed * speed_mult * _rng.randf_range(0.85, 1.15)
	radius[slot] = data.radius
	flash[slot] = 0.0
	phase[slot] = _rng.randf() * TAU
	kb_x[slot] = 0.0
	kb_z[slot] = 0.0
	knodl_timer[slot] = 0.0
	if alive[slot] == 0:
		alive_count += 1
	alive[slot] = 1
	spawned.append(slot)


func _pick_type() -> int:
	var total: float = 0.0
	for t: int in types.size():
		total += _weight(t)
	if total <= 0.0:
		return 0
	var roll: float = _rng.randf() * total
	for t: int in types.size():
		roll -= _weight(t)
		if roll <= 0.0 and _weight(t) > 0.0:
			return t
	return types.size() - 1


func _weight(t: int) -> float:
	return type_weights[t] if t < type_weights.size() else types[t].spawn_weight


func _rebuild_grid() -> void:
	grid.clear()
	for i: int in capacity:
		if alive[i] != 0:
			grid.insert(i, pos_x[i], pos_z[i])
