extends GutTest
## Die Hausmeisterin (1.4 Part 4): the Gemeindebau-Hof's mini-boss at 10:00, her broom sweep, the
## stairs she locks (StairLock) and the LOCK run event.

var balance: BalanceData


func before_each() -> void:
	balance = BalanceData.new()


func _boss() -> BossData:
	return load("res://data/bosses/hausmeisterin.tres")


func _attack(aim: AttackData.Aim) -> AttackData:
	for attack: AttackData in _boss().attacks:
		if attack.aim == aim and (aim != AttackData.Aim.TARGET or attack.shape == AttackData.Shape.LINE):
			return attack
	return null


func _stairs() -> StairLock:
	var lock := StairLock.new()
	add_child_autofree(lock)
	lock.setup(load("res://data/maps/gemeindebau.tres"), balance)
	return lock


func test_she_replaces_the_second_oberkrampus_on_the_gemeindebau_only() -> void:
	var wave: WaveData = load("res://data/waves/gemeindebau.tres")
	var at_ten: BossData
	for entry: WaveBoss in wave.bosses:
		assert_ne(entry.boss.id, &"oberkrampus_2")
		if is_equal_approx(entry.minute, 10.0):
			at_ten = entry.boss
	assert_eq(at_ten, _boss())
	assert_has(wave.enemies, _boss().enemy, "her body is in the wave's list")
	assert_has(wave.enemies, _boss().escort)
	assert_lt(wave.enemies.size(), 32, "the snapshot holds 32 types")
	var kirtag: WaveData = load("res://data/waves/kirtag.tres")
	assert_eq(kirtag.bosses[1].boss.id, &"oberkrampus_2", "the other maps keep theirs")
	for line: VoiceLineData in _boss().enemy.voice.lines:
		assert_true(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % line.sound), str(line.sound))


func test_her_broom_sweeps_across_one_line_after_the_other() -> void:
	var sweep: AttackData = _attack(AttackData.Aim.TARGET)
	assert_not_null(sweep)
	var field := HazardField.new()
	autofree(field)
	field.setup(null, 7)
	field.start_attack(sweep, 0.0, 0.0, 0.0, 10.0)
	assert_eq(field.hazards.size(), sweep.count)
	for k: int in field.hazards.size():
		var h: HazardField.Hazard = field.hazards[k]
		assert_eq(h.shape, AttackData.Shape.LINE)
		assert_almost_eq(h.telegraph, sweep.telegraph + k * sweep.stagger, 0.001)
	# A fan without a stagger still hits all at once (the Oberkrampus' charge).
	var charge: AttackData = (load("res://data/bosses/oberkrampus_2.tres") as BossData).attacks[1]
	field.clear()
	field.start_attack(charge, 0.0, 0.0, 0.0, 10.0)
	for h: HazardField.Hazard in field.hazards:
		assert_almost_eq(h.telegraph, charge.telegraph, 0.001)


func test_the_gemeindebau_has_tall_stairs_to_lock_and_small_ones_are_left_out() -> void:
	var lock: StairLock = _stairs()
	# Four ramps onto the roofs, two corner stairs, four outer stairs; not the garden steps (3 m).
	assert_eq(lock.feet.size(), 10)
	for k: int in lock.feet.size():
		assert_gte(lock.tops[k].y - lock.feet[k].y, balance.stair_lock_min_height - 0.01)
	var k: int = lock.nearest(lock.feet[0].x + 1.0, lock.feet[0].z, 25.0)
	assert_eq(k, 0)
	assert_eq(lock.nearest(0.0, 13.5, 3.0), -1, "nothing tall near the garden steps")
	var kirtag := StairLock.new()
	add_child_autofree(kirtag)
	kirtag.setup(load("res://data/maps/kirtag.tres"), balance)
	assert_eq(kirtag.nearest(0.0, 0.0, 1000.0) >= 0, not kirtag.feet.is_empty())


func test_a_locked_stairwell_closes_when_the_mark_hits_and_opens_after_ten_seconds() -> void:
	var lock: StairLock = _stairs()
	var gate: StaticBody3D = lock.get_node(^"Gate0")
	var shape: CollisionShape3D = gate.get_child(0)
	lock.lock(2, 1.6, 10.0)
	assert_true(lock.busy())
	lock.update(1.0)
	assert_true(shape.disabled, "still open while the mark fills")
	lock.update(0.7)
	assert_false(shape.disabled, "closed")
	assert_true(gate.visible)
	assert_almost_eq(Vector2(gate.global_position.x, gate.global_position.z).distance_to(Vector2(lock.feet[2].x, lock.feet[2].z)), StairLock.INSET, 0.01)
	var top: StaticBody3D = lock.get_node(^"Gate1")
	assert_gt(top.global_position.y, gate.global_position.y + balance.stair_lock_min_height - 1.0, "one at the top too")
	lock.update(9.0)
	assert_true(lock.busy())
	lock.update(1.0)
	assert_false(lock.busy())
	assert_true(shape.disabled, "open again")
	lock.lock(1, 0.0, 10.0)
	lock.update(0.01)
	lock.release()
	assert_true(shape.disabled, "Sperrstund' opens it")


func test_she_marks_the_stairs_nearest_her_target_and_skips_when_none_are_near() -> void:
	var lock: StairLock = _stairs()
	var data: BossData = _boss().duplicate()
	data.attacks = [_attack(AttackData.Aim.STAIRWELL)]
	var wave := WaveData.new()
	var entry := WaveBoss.new()
	entry.boss = data
	wave.bosses = [entry]
	wave.enemies = [data.enemy, data.escort]
	var manager: EnemyManager = EnemyManager.new(balance, wave.enemies, 24, 3, null, 200.0)
	var hazards := HazardField.new()
	autofree(hazards)
	hazards.setup(null, 7)
	var director := BossDirector.new(balance, manager, hazards, wave)
	director.stairs = lock
	var foot: Vector3 = lock.feet[3]
	var boss: BossDirector.Active = director.spawn(0, foot.x + 6.0, foot.z, 1)
	boss.pause = 0.0
	director.update(0.05, PackedVector3Array([foot + Vector3(1.0, 0.0, 0.0)]))
	assert_eq(hazards.hazards.size(), 1)
	var h: HazardField.Hazard = hazards.hazards[0]
	assert_eq(h.tag, 3)
	assert_eq(h.attack.lock_seconds, 10.0)
	assert_almost_eq(h.rise, lock.tops[3].y - lock.feet[3].y, 0.01, "the mark leans up the stairs")
	assert_almost_eq(h.radius, lock.widths[3] * 0.5, 0.01)
	assert_true(HazardField.contains(h, lock.feet[3].lerp(lock.tops[3], 0.5).x, lock.feet[3].lerp(lock.tops[3], 0.5).z, 0.4))
	# Far from every stairwell: no mark, she just goes on.
	hazards.clear()
	boss.pause = 0.0
	boss.waiting = 0.0
	director.update(0.05, PackedVector3Array([Vector3(0.0, 0.0, 140.0)]))
	assert_eq(hazards.hazards.size(), 0)
	# And never a second lock while one is running.
	lock.lock(0, 1.0, 10.0)
	boss.pause = 0.0
	director.update(0.05, PackedVector3Array([foot]))
	assert_eq(hazards.hazards.size(), 0)


func test_the_lock_event_goes_over_the_wire() -> void:
	var queue := RunEventCodec.Queue.new()
	queue.lock(7, 1.6, 10.0)
	queue.toast("BOSS_HAUSMEISTERIN_LOCK")
	var events: Array[RunEventCodec.Event] = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(events.size(), 2)
	assert_eq(events[0].kind, RunEventCodec.Kind.LOCK)
	assert_eq(events[0].a, 7)
	assert_almost_eq(events[0].seconds, 1.6, 0.001)
	assert_almost_eq(events[0].length, 10.0, 0.001)
	assert_eq(events[1].text, "BOSS_HAUSMEISTERIN_LOCK")
