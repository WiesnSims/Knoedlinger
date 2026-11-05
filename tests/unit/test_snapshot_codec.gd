extends GutTest

const SLOTS: int = 500

var alive := PackedByteArray()
var x := PackedFloat32Array()
var z := PackedFloat32Array()
var type := PackedByteArray()
var hp := PackedByteArray()


func before_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	alive = PackedByteArray()
	x = PackedFloat32Array()
	z = PackedFloat32Array()
	type = PackedByteArray()
	hp = PackedByteArray()
	for i: int in SLOTS:
		alive.append(1 if rng.randf() < 0.9 else 0)
		x.append(rng.randf_range(-150.0, 150.0))
		z.append(rng.randf_range(-150.0, 150.0))
		type.append(rng.randi_range(0, 2))
		hp.append(rng.randi_range(0, 15))


## Positions travel in 1 / POSITION_SCALE metre steps (5 cm since M6).
func test_round_trip_is_lossless_within_half_a_step() -> void:
	var wire: PackedByteArray = SnapshotCodec.encode(42, 123456, SLOTS, alive, x, z, type, hp)
	var frame: SnapshotCodec.Frame = SnapshotCodec.decode(wire)
	assert_not_null(frame)
	assert_eq(frame.seq, 42)
	assert_eq(frame.host_ms, 123456)
	assert_eq(frame.slots, SLOTS)
	var errors: int = 0
	for i: int in SLOTS:
		if frame.alive[i] != alive[i]:
			errors += 1
		elif alive[i] != 0:
			var half_step: float = 0.5 / SnapshotCodec.POSITION_SCALE + 0.0001
			if absf(frame.x[i] - x[i]) > half_step or absf(frame.z[i] - z[i]) > half_step:
				errors += 1
			if frame.type[i] != type[i] or frame.hp[i] != hp[i]:
				errors += 1
	assert_eq(errors, 0)


func test_500_enemies_fit_the_bandwidth_budget() -> void:
	alive.fill(1)
	var wire: PackedByteArray = SnapshotCodec.encode(1, 0, SLOTS, alive, x, z, type, hp)
	var balance: BalanceData = load("res://data/balance.tres")
	var kib_per_s: float = (wire.size() + NetworkManager.MESSAGE_OVERHEAD) * balance.snapshot_rate_hz / 1024.0
	gut.p("500 enemies spread over the map: %d bytes per snapshot, %.1f KiB/s at %.0f Hz" % [wire.size(), kib_per_s, balance.snapshot_rate_hz])
	assert_lt(kib_per_s, balance.client_bandwidth_budget_kbps)


func test_garbage_is_rejected() -> void:
	assert_null(SnapshotCodec.decode(PackedByteArray()))
	assert_null(SnapshotCodec.decode(PackedByteArray([1, 1, 255, 255, 255, 0, 9, 9])))


func test_events_round_trip() -> void:
	var types: Array[EnemyTypeData] = [EnemyTypeData.new()]
	var manager := EnemyManager.new(BalanceData.new(), types, 8)
	manager.populate(4, PackedVector3Array([Vector3.ZERO]))
	var data: PackedByteArray = SnapshotCodec.encode_events(PackedInt32Array([1, 3]), PackedInt32Array([2]), manager)
	var events: Dictionary = SnapshotCodec.decode_events(data)
	assert_eq(events["spawned"], PackedInt32Array([1, 3]))
	assert_eq(events["died"], PackedInt32Array([2]))
	assert_eq(SnapshotCodec.decode_events(data.slice(0, data.size() - 1)), {})
