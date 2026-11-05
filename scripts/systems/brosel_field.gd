class_name BroselField
extends Node3D
## All Brösel (the XP crumbs enemies drop) as pooled packed arrays drawn with one MultiMesh
## (CLAUDE.md: pooled, no instantiate() in hot paths). Brösel are absorbed by a Knödl, not by the
## player: a Knödl rolling over them eats them, and Brösel close to a player fly to that player's
## Knödl. Each absorbed Brösel credits its owner with XP and Knödl mass.
##
## The host runs the logic and records what changed; clients mirror the pool from those events
## (net/brosel_codec.gd) and only draw it. Static Brösel bob and spin in the shader, so the
## MultiMesh is only re-uploaded when something changed.

const STRIDE: int = 20
## Brösel lie this high above the ground (the shader adds the bob).
const LIFT: float = 0.18
## How far to look for a Brösel to merge into when the pool is full.
const MERGE_RADIUS: float = 6.0
const FLAG_XP: int = 1

var balance: BalanceData
var capacity: int = 0
var ground: Heightfield
var active_count: int = 0
## Host: XP and mass credited per peer since the last take_credits(): {peer_id: Vector2(xp, mass)}.
var credits: Dictionary[int, Vector2] = {}
## Host: slots added (or changed) and removed since the last take_changes(), for the network.
var added: PackedInt32Array = PackedInt32Array()
var removed: PackedInt32Array = PackedInt32Array()
var merges: int = 0

var alive: PackedByteArray = PackedByteArray()
var x: PackedFloat32Array = PackedFloat32Array()
var y: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var value: PackedInt32Array = PackedInt32Array()
## FLAG_XP: absorbing it gives XP (drops). Without it, only mass (Brösel a Knödl shed).
var flags: PackedByteArray = PackedByteArray()
## Seconds before a Knödl may absorb it.
var delay: PackedFloat32Array = PackedFloat32Array()
## Peer whose Knödl it flies to, 0 = lying on the ground.
var target: PackedInt32Array = PackedInt32Array()

var _free: PackedInt32Array = PackedInt32Array()
var _free_top: int = 0
var _grid: SpatialHash
var _grid_dirty: bool = true
var _draw_dirty: bool = true
var _flying: int = 0
var _merge_cursor: int = 0
## A client's mirror never picks slots itself, so it keeps no free-slot stack.
var _mirror: bool = false
var _multimesh: MultiMesh
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func setup(p_balance: BalanceData, p_ground: Heightfield, half_size: float) -> void:
	balance = p_balance
	ground = p_ground
	capacity = balance.brosel_cap
	# Redrawn from the packed arrays every rendered frame. With physics interpolation on, Godot would
	# also blend each MultiMesh instance with the previous tick by index; instances are repacked when
	# Brösel come and go, so that blended two different Brösel.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 4711
	alive.resize(capacity)
	alive.fill(0)
	flags.resize(capacity)
	for array_name: String in ["x", "y", "z", "delay"]:
		var array := PackedFloat32Array()
		array.resize(capacity)
		array.fill(0.0)
		set(array_name, array)
	value.resize(capacity)
	target.resize(capacity)
	target.fill(0)
	_free.resize(capacity)
	for i: int in capacity:
		_free[i] = capacity - 1 - i
	_free_top = capacity
	_grid = SpatialHash.new(half_size, balance.grid_cell_size, capacity)
	_buffer.resize(capacity * STRIDE)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = MeshFactory.brosel()
	_multimesh.instance_count = capacity
	_multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/brosel.gdshader")
	var instance := MultiMeshInstance3D.new()
	instance.name = "Brosel"
	instance.multimesh = _multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000.0, -50.0, -1000.0), Vector3(2000.0, 200.0, 2000.0))
	add_child(instance)


## Host: drops a Brösel near (px, pz). When the pool is full it merges into a nearby one instead, so
## no XP is ever lost (GAME-DESIGN.md: cap 1,500). Returns the slot it went to.
func drop(px: float, pz: float, amount: int, gives_xp: bool, pickup_delay: float = 0.0) -> int:
	var scatter: float = balance.brosel_scatter
	px += _rng.randf_range(-scatter, scatter)
	pz += _rng.randf_range(-scatter, scatter)
	var flag: int = FLAG_XP if gives_xp else 0
	if _free_top == 0:
		var slot: int = _merge_target(px, pz, flag)
		value[slot] += amount
		merges += 1
		added.append(slot)
		_draw_dirty = true
		return slot
	_free_top -= 1
	var slot: int = _free[_free_top]
	_place(slot, px, pz, amount, flag)
	delay[slot] = pickup_delay
	added.append(slot)
	return slot


## Host: Brösel within `reach` of a player's body (feet at `feet`, `body` metres tall) start flying
## to the Knödl of `peer`. A player high in the air pulls nothing up (owner, movement).
func attract(feet: Vector3, body: float, reach: float, peer: int) -> void:
	_refresh_grid()
	var found: int = _grid.query(feet.x, feet.z, reach)
	var reach_sq: float = reach * reach
	for k: int in found:
		var i: int = _grid.results[k]
		if alive[i] == 0 or target[i] != 0 or delay[i] > 0.0:
			continue
		var dx: float = x[i] - feet.x
		var dz: float = z[i] - feet.z
		# How far above the head or below the feet it lies (0 = level with the body).
		var dy: float = maxf(feet.y - y[i], y[i] - feet.y - body)
		dy = maxf(dy, 0.0)
		if dx * dx + dz * dz + dy * dy <= reach_sq:
			target[i] = peer
			_flying += 1


## Host: a Knödl of `peer` at `centre` with `radius` eats every Brösel it touches.
func absorb(centre: Vector3, radius: float, peer: int) -> void:
	_refresh_grid()
	var reach: float = radius + balance.brosel_pickup_margin
	var found: int = _grid.query(centre.x, centre.z, reach)
	var reach_sq: float = reach * reach
	for k: int in found:
		var i: int = _grid.results[k]
		if alive[i] == 0 or delay[i] > 0.0:
			continue
		var dx: float = x[i] - centre.x
		var dz: float = z[i] - centre.z
		var dy: float = y[i] - centre.y
		if dx * dx + dz * dz <= reach_sq and absf(dy) <= reach + 0.5:
			_eat(i, peer)


## Host: moves the flying Brösel toward their Knödl ({peer: Vector4(x, y, z, radius)}) and counts
## down pickup delays. Brösel whose Knödl is gone drop back to the ground.
func update(delta: float, knodls: Dictionary[int, Vector4]) -> void:
	if _flying == 0:
		for i: int in capacity:
			if alive[i] != 0 and delay[i] > 0.0:
				delay[i] -= delta
		return
	var step: float = balance.brosel_fly_speed * delta
	for i: int in capacity:
		if alive[i] == 0:
			continue
		if delay[i] > 0.0:
			delay[i] -= delta
		var peer: int = target[i]
		if peer == 0:
			continue
		if not knodls.has(peer):
			target[i] = 0
			_flying -= 1
			y[i] = _ground_y(x[i], z[i])
			_grid_dirty = true
			_draw_dirty = true
			continue
		var k: Vector4 = knodls[peer]
		var to := Vector3(k.x - x[i], k.y - y[i], k.z - z[i])
		var d: float = to.length()
		if d <= k.w + step:
			_eat(i, peer)
			continue
		var move: Vector3 = to / d * step
		x[i] += move.x
		y[i] += move.y
		z[i] += move.z
		_draw_dirty = true
		_grid_dirty = true


## The closest lying Brösel to (px, pz) within `reach`, as (x, z); (INF, INF) when there is none.
func nearest(px: float, pz: float, reach: float) -> Vector2:
	_refresh_grid()
	var found: int = _grid.query(px, pz, reach)
	var best := Vector2(INF, INF)
	var best_sq: float = reach * reach
	for k: int in found:
		var i: int = _grid.results[k]
		if alive[i] == 0 or target[i] != 0:
			continue
		var d_sq: float = (x[i] - px) * (x[i] - px) + (z[i] - pz) * (z[i] - pz)
		if d_sq < best_sq:
			best_sq = d_sq
			best = Vector2(x[i], z[i])
	return best


## Host: empties the pool (a new run).
func clear() -> void:
	for i: int in capacity:
		if alive[i] != 0:
			_release(i)
			removed.append(i)


## Host: the credits since the last call, then forgets them.
func take_credits() -> Dictionary[int, Vector2]:
	var taken: Dictionary[int, Vector2] = credits
	credits = {}
	return taken


func take_changes() -> Array[PackedInt32Array]:
	var changes: Array[PackedInt32Array] = [added, removed]
	added = PackedInt32Array()
	removed = PackedInt32Array()
	return changes


## Client: mirrors a removal from the host.
func mirror_remove(slot: int) -> void:
	_mirror = true
	if slot >= 0 and slot < capacity and alive[slot] != 0:
		_release(slot)


## Client: mirrors a new or changed Brösel from the host.
func mirror_set(slot: int, px: float, pz: float, amount: int, flag: int) -> void:
	_mirror = true
	if slot < 0 or slot >= capacity:
		return
	if alive[slot] != 0:
		active_count -= 1
	_place(slot, px, pz, amount, flag)


## Uploads the instances if anything changed since the last draw.
func draw() -> void:
	if not _draw_dirty:
		return
	_draw_dirty = false
	var buffer: PackedFloat32Array = _buffer
	_buffer = PackedFloat32Array()
	var values: PackedInt32Array = balance.brosel_values
	var golden: int = values[values.size() - 1]
	var o: int = 0
	for i: int in capacity:
		if alive[i] == 0:
			continue
		var amount: int = value[i]
		# 20 cm for the smallest, about 80 cm for a golden one: readable inside the crowd.
		var s: float = 0.2 * pow(float(amount), 0.3)
		var flying: float = 1.0 if target[i] != 0 else 0.0
		buffer[o] = s
		buffer[o + 1] = 0.0
		buffer[o + 2] = 0.0
		buffer[o + 3] = x[i]
		buffer[o + 4] = 0.0
		buffer[o + 5] = s
		buffer[o + 6] = 0.0
		buffer[o + 7] = y[i]
		buffer[o + 8] = 0.0
		buffer[o + 9] = 0.0
		buffer[o + 10] = s
		buffer[o + 11] = z[i]
		var color: Color = _color(amount, flags[i], golden)
		buffer[o + 12] = color.r
		buffer[o + 13] = color.g
		buffer[o + 14] = color.b
		buffer[o + 15] = 1.0
		buffer[o + 16] = float(i) * 2.39996
		buffer[o + 17] = flying
		buffer[o + 18] = 0.0
		buffer[o + 19] = 0.0
		o += STRIDE
	_multimesh.buffer = buffer
	_multimesh.visible_instance_count = o / STRIDE
	_buffer = buffer


## Total XP (or mass) lying around, for tests and stats.
func total_value() -> int:
	var total: int = 0
	for i: int in capacity:
		if alive[i] != 0:
			total += value[i]
	return total


func _eat(slot: int, peer: int) -> void:
	var credit: Vector2 = credits.get(peer, Vector2.ZERO)
	var amount: float = float(value[slot])
	credit.y += amount
	if flags[slot] & FLAG_XP:
		credit.x += amount
	credits[peer] = credit
	_release(slot)
	removed.append(slot)


func _place(slot: int, px: float, pz: float, amount: int, flag: int) -> void:
	alive[slot] = 1
	x[slot] = px
	z[slot] = pz
	y[slot] = _ground_y(px, pz)
	value[slot] = amount
	flags[slot] = flag
	delay[slot] = 0.0
	target[slot] = 0
	active_count += 1
	_grid_dirty = true
	_draw_dirty = true


func _release(slot: int) -> void:
	if target[slot] != 0:
		_flying -= 1
	alive[slot] = 0
	target[slot] = 0
	if not _mirror:
		_free[_free_top] = slot
		_free_top += 1
	active_count -= 1
	_grid_dirty = true
	_draw_dirty = true


func _merge_target(px: float, pz: float, flag: int) -> int:
	_refresh_grid()
	var found: int = _grid.query(px, pz, MERGE_RADIUS)
	var best: int = -1
	var best_sq: float = INF
	for k: int in found:
		var i: int = _grid.results[k]
		if alive[i] == 0 or target[i] != 0 or flags[i] != flag:
			continue
		var d_sq: float = (x[i] - px) * (x[i] - px) + (z[i] - pz) * (z[i] - pz)
		if d_sq < best_sq:
			best_sq = d_sq
			best = i
	if best >= 0:
		return best
	# Nothing near: grow the next lying Brösel in turn, so the XP is kept even if it moves.
	for _attempt: int in capacity:
		_merge_cursor = (_merge_cursor + 1) % capacity
		if alive[_merge_cursor] != 0 and target[_merge_cursor] == 0:
			return _merge_cursor
	return _merge_cursor


func _ground_y(px: float, pz: float) -> float:
	return (ground.height_at(px, pz) if ground != null else 0.0) + LIFT


func _refresh_grid() -> void:
	if not _grid_dirty:
		return
	_grid_dirty = false
	_grid.clear()
	for i: int in capacity:
		if alive[i] != 0:
			_grid.insert(i, x[i], z[i])


func _color(amount: int, flag: int, golden: int) -> Color:
	if amount >= golden:
		return Color(1.0, 0.86, 0.3)
	var crumb := Color(0.86, 0.66, 0.36)
	if flag & FLAG_XP == 0:
		# Shed mass looks paler: it is only dough, the XP was paid out already.
		crumb = Color(0.9, 0.82, 0.66)
	return crumb.lightened(clampf(float(amount) / golden, 0.0, 1.0) * 0.3)
