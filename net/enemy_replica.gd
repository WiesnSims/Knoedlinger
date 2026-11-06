class_name EnemyReplica
extends RefCounted
## The client's view of the host's enemies: keeps the last few snapshots and shows the crowd
## `interpolation_delay_ms` in the past, interpolating between the two snapshots around that time.
## Fills the same slot-indexed arrays EnemyRenderer draws on the host.
##
## Also measures what the M0 sync test checks: snapshot intervals, how long the buffer ran dry
## (underruns), jumps of the render clock, and "pops": an enemy stepping much further in one frame
## than its own interpolated movement explains (real shoves on the host do not count).

const MAX_FRAMES: int = 8
## A rendered step longer than this many times the interpolated speed (plus POP_SLACK) is a pop.
const POP_FACTOR: float = 2.0
const POP_SLACK: float = 0.05
## The render clock should advance by the frame time; a step off by more than this is a jump.
const CLOCK_JUMP_MS: float = 25.0

var balance: BalanceData
var types: Array[EnemyTypeData] = []
var capacity: int = 0

var alive: PackedByteArray = PackedByteArray()
var x: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var yaw: PackedFloat32Array = PackedFloat32Array()
var type: PackedByteArray = PackedByteArray()
var radius: PackedFloat32Array = PackedFloat32Array()
var flash: PackedFloat32Array = PackedFloat32Array()
var phase: PackedFloat32Array = PackedFloat32Array()
## EnemyManager.STATUS_* bits from the newest snapshot (frozen / burning tint).
var status: PackedByteArray = PackedByteArray()
var alive_count: int = 0

# Stats.
var snapshots: int = 0
var decode_errors: int = 0
var out_of_order: int = 0
var underrun_ms: float = 0.0
var max_underrun_ms: float = 0.0
var pops: int = 0
var clock_jumps: int = 0
var rendered_frames: int = 0
var intervals_ms: PackedFloat32Array = PackedFloat32Array()
var events_spawned: int = 0
var events_died: int = 0
## Starts the sync measurement over (the run's measurement window begins after its warm-up; the
## first seconds of a browser co-op run are every tab compiling shaders).
func reset_counters() -> void:
	underrun_ms = 0.0
	max_underrun_ms = 0.0
	_underrun_streak_ms = 0.0
	pops = 0
	clock_jumps = 0
	intervals_ms.clear()


## Where enemies died since the caller last emptied it (x, z), for kill sounds.
var recent_deaths := PackedVector2Array()
## The host's alive count in the snapshot being shown (the newest one can be ~100 ms ahead).
var shown_host_alive: int = 0

var _frames: Array[SnapshotCodec.Frame] = []
var _clock_offset: float = 0.0
var _has_clock: bool = false
var _last_arrival_ms: int = -1
var _last_seq: int = -1
var _underrun_streak_ms: float = 0.0
var _last_render_ms: float = -1.0
# Previous rendered position, to count pops; -1 hp marks "not shown last frame".
var _prev_x: PackedFloat32Array = PackedFloat32Array()
var _prev_z: PackedFloat32Array = PackedFloat32Array()
var _prev_shown: PackedByteArray = PackedByteArray()
var _prev_hp: PackedByteArray = PackedByteArray()
# Interpolated speed per slot last frame: a frame on a snapshot boundary may carry either speed.
var _prev_speed: PackedFloat32Array = PackedFloat32Array()


func _init(p_balance: BalanceData, p_types: Array[EnemyTypeData], p_capacity: int) -> void:
	balance = p_balance
	types = p_types
	capacity = p_capacity
	alive.resize(capacity)
	alive.fill(0)
	type.resize(capacity)
	status.resize(capacity)
	_prev_shown.resize(capacity)
	_prev_shown.fill(0)
	_prev_hp.resize(capacity)
	for array_name: String in ["x", "z", "yaw", "radius", "flash", "phase", "_prev_x", "_prev_z", "_prev_speed"]:
		var array := PackedFloat32Array()
		array.resize(capacity)
		array.fill(0.0)
		set(array_name, array)
	for i: int in capacity:
		# Golden-angle phases so neighbours do not waddle in step.
		phase[i] = fposmod(i * 2.39996, TAU)


## Adds a snapshot as it arrives. Returns false if it was invalid or stale.
func push(data: PackedByteArray, now_ms: int) -> bool:
	var frame: SnapshotCodec.Frame = SnapshotCodec.decode(data)
	if frame == null or frame.slots > capacity:
		decode_errors += 1
		return false
	if _last_seq >= 0 and _seq_newer(_last_seq, frame.seq) <= 0:
		out_of_order += 1
		return false
	_last_seq = frame.seq
	snapshots += 1
	if _last_arrival_ms >= 0:
		intervals_ms.append(now_ms - _last_arrival_ms)
	_last_arrival_ms = now_ms
	# Host clock = local clock + offset. The largest offset seen belongs to the fastest delivery;
	# follow it up at once and drift down slowly, so jitter does not shake the render time.
	var sample: float = frame.host_ms - now_ms
	if not _has_clock or sample > _clock_offset:
		_clock_offset = sample
		_has_clock = true
	else:
		_clock_offset += (sample - _clock_offset) * 0.02
	_frames.append(frame)
	if _frames.size() > MAX_FRAMES:
		_frames.pop_front()
	return true


## Counts the reliable spawn/death events (effects hook in here from M1 on).
func push_events(data: PackedByteArray) -> void:
	var events: Dictionary = SnapshotCodec.decode_events(data)
	if events.is_empty():
		decode_errors += 1
		return
	events_spawned += (events["spawned"] as PackedInt32Array).size()
	events_died += (events["died"] as PackedInt32Array).size()
	for slot: int in events["died"] as PackedInt32Array:
		if slot >= 0 and slot < capacity and recent_deaths.size() < 64:
			recent_deaths.append(Vector2(x[slot], z[slot]))


func update(now_ms: int, delta: float) -> void:
	if _frames.is_empty():
		return
	var render_ms: float = now_ms + _clock_offset - NetworkManager.interpolation_delay_ms(balance)
	if _last_render_ms >= 0.0 and absf(render_ms - _last_render_ms - delta * 1000.0) > CLOCK_JUMP_MS:
		clock_jumps += 1
	_last_render_ms = render_ms
	var newest: SnapshotCodec.Frame = _frames[_frames.size() - 1]
	var a: SnapshotCodec.Frame = _frames[0]
	var b: SnapshotCodec.Frame = _frames[0]
	var t: float = 0.0
	if render_ms >= newest.host_ms:
		a = newest
		b = newest
		_underrun_streak_ms += delta * 1000.0
		underrun_ms += delta * 1000.0
		max_underrun_ms = maxf(max_underrun_ms, _underrun_streak_ms)
	else:
		_underrun_streak_ms = 0.0
		for k: int in range(_frames.size() - 1, 0, -1):
			if _frames[k - 1].host_ms <= render_ms:
				a = _frames[k - 1]
				b = _frames[k]
				t = clampf((render_ms - a.host_ms) / maxf(b.host_ms - a.host_ms, 1.0), 0.0, 1.0)
				break
	rendered_frames += 1
	shown_host_alive = b.alive_count
	var snap_sq: float = balance.interpolation_snap_distance * balance.interpolation_snap_distance
	# Seconds between the two snapshots, to turn their distance into the speed shown.
	var span: float = maxf((b.host_ms - a.host_ms) / 1000.0, 0.001)
	alive_count = 0
	var slots: int = mini(b.slots, capacity)
	for i: int in slots:
		if b.alive[i] == 0:
			alive[i] = 0
			_prev_shown[i] = 0
			continue
		var bx: float = b.x[i]
		var bz: float = b.z[i]
		var nx: float = bx
		var nz: float = bz
		var respawned: bool = true
		var shown_speed: float = 0.0
		if a.alive[i] != 0:
			var dx: float = bx - a.x[i]
			var dz: float = bz - a.z[i]
			if dx * dx + dz * dz < snap_sq:
				respawned = false
				shown_speed = sqrt(dx * dx + dz * dz) / span if a != b else 0.0
				nx = a.x[i] + dx * t
				nz = a.z[i] + dz * t
				if dx * dx + dz * dz > 0.0001:
					yaw[i] = atan2(dx, dz)
		var tp: int = b.type[i]
		if _prev_shown[i] != 0 and not respawned:
			var mx: float = nx - _prev_x[i]
			var mz: float = nz - _prev_z[i]
			var allowed: float = maxf(shown_speed, _prev_speed[i]) * delta * POP_FACTOR + POP_SLACK
			if mx * mx + mz * mz > allowed * allowed:
				pops += 1
			if b.hp[i] < _prev_hp[i]:
				flash[i] = 1.0
		if flash[i] > 0.0:
			flash[i] = maxf(flash[i] - delta * 6.0, 0.0)
		alive[i] = 1
		type[i] = tp
		status[i] = b.status[i] if i < b.status.size() else 0
		radius[i] = types[tp].radius if tp < types.size() else 0.4
		x[i] = nx
		z[i] = nz
		_prev_x[i] = nx
		_prev_z[i] = nz
		_prev_hp[i] = b.hp[i]
		_prev_speed[i] = shown_speed
		_prev_shown[i] = 1
		alive_count += 1
	for i: int in range(slots, capacity):
		alive[i] = 0


## The host's alive count in the newest snapshot.
func host_alive_count() -> int:
	return _frames[_frames.size() - 1].alive_count if not _frames.is_empty() else 0


func stats() -> Dictionary:
	var sorted: PackedFloat32Array = intervals_ms.duplicate()
	sorted.sort()
	return {
		"snapshots": snapshots,
		"decode_errors": decode_errors,
		"out_of_order": out_of_order,
		"interval_ms_p50": _percentile(sorted, 0.5),
		"interval_ms_p95": _percentile(sorted, 0.95),
		"interval_ms_max": sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0,
		"underrun_ms_total": underrun_ms,
		"underrun_ms_max_streak": max_underrun_ms,
		"pops": pops,
		"clock_jumps": clock_jumps,
		"rendered_frames": rendered_frames,
		"events_spawned": events_spawned,
		"events_died": events_died,
		"alive_shown": alive_count,
		"alive_host": shown_host_alive,
	}


static func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]


## > 0 when b is newer than a, with 16-bit wrap-around.
static func _seq_newer(a: int, b: int) -> int:
	var diff: int = (b - a) & 0xFFFF
	if diff == 0:
		return 0
	return 1 if diff < 0x8000 else -1
