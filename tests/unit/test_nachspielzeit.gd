extends GutTest
## 1.3.2 Nachspielzeit: past Sperrstund' the waves send only the Stammgast-Geister (the grantige ones
## from 17:00), the crowd hurries on (EnemyManager.pace), and the Profile keeps the longest
## Nachspielzeit for its quests.

const WAVES: Array[String] = ["kirtag", "gamskogl", "gemeindebau", "heuriger"]

var balance: BalanceData


func before_each() -> void:
	balance = load("res://data/balance.tres")
	Profile.reset_memory()


func after_all() -> void:
	Profile.reset_memory()


func _wave(id: String) -> WaveData:
	return load("res://data/waves/%s.tres" % id)


## The weights of the types in `wave` at `minute`, by enemy id (only those that spawn).
func _mix(wave: WaveData, minute: float) -> Dictionary:
	var weights: PackedFloat32Array = wave.weights_at(minute * 60.0)
	var mix: Dictionary = {}
	for t: int in wave.enemies.size():
		if weights[t] > 0.0:
			mix[String(wave.enemies[t].id)] = weights[t]
	return mix


func test_every_wave_fits_the_snapshot_and_sends_ghosts_only_after_sperrstund() -> void:
	for id: String in WAVES:
		var wave: WaveData = _wave(id)
		assert_lte(wave.enemies.size(), SnapshotCodec.MAX_TYPES, "%s fits 5 bits of type" % id)
		var before: Dictionary = _mix(wave, 14.9)
		assert_false(before.has("geist") or before.has("geist_grantig"), "%s: no ghosts before 15:00" % id)
		assert_eq(_mix(wave, 15.5).keys(), ["geist"], "%s: only the white ghosts at 15:30" % id)
		var late: Dictionary = _mix(wave, 17.5)
		assert_eq(late.size(), 2, "%s: both ghosts at 17:30" % id)
		assert_lt(late["geist_grantig"], late["geist"], "%s: a few grantige at first" % id)
		var later: Dictionary = _mix(wave, 20.0)
		assert_almost_eq(later["geist_grantig"], later["geist"], 0.001, "%s: half grantig from 19:00" % id)


func test_the_ghosts_fly_through_walls_and_stay_at_sperrstund() -> void:
	for file: String in ["geist", "geist_grantig"]:
		var ghost: EnemyTypeData = load("res://data/enemies/%s.tres" % file)
		assert_true(ghost.flying, "%s ignores walls and slopes" % file)
		assert_true(ghost.stays_at_sperrstund, "%s is not swept out" % file)
		assert_eq(ghost.look, &"geist")
		assert_not_null(ghost.voice)
		assert_ne(tr(ghost.name_key), ghost.name_key)
		assert_ne(tr(ghost.desc_key), ghost.desc_key)
	var grantig: EnemyTypeData = load("res://data/enemies/geist_grantig.tres")
	assert_ne(tr(grantig.arrive_toast), grantig.arrive_toast)
	var content: GameContent = GameContent.load_default()
	var ids: Array[StringName] = []
	for enemy: EnemyTypeData in content.enemies:
		ids.append(enemy.id)
	assert_true(ids.has(&"geist") and ids.has(&"geist_grantig"), "both in the Almanach")


func test_the_ghost_model_stays_in_the_fodder_budget() -> void:
	var mesh: ArrayMesh = MeshFactory.enemy(load("res://data/enemies/geist.tres"))
	var triangles: int = 0
	for s: int in mesh.get_surface_count():
		var indices: PackedInt32Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3 if not indices.is_empty() else mesh.surface_get_array_len(s) / 3
	gut.p("Stammgast-Geist: %d triangles" % triangles)
	assert_between(triangles, 200, 800)


## One enemy walking at a player 10 m away for one frame: `pace` multiplies the step.
func _step_with_pace(pace: float) -> float:
	var types: Array[EnemyTypeData] = [load("res://data/enemies/tourist.tres")]
	var manager := EnemyManager.new(balance, types, 4, 3, null, 50.0)
	var slot: int = manager.spawn_at(0, 0.0, 0.0)
	manager.pace = pace
	manager.update(0.1, PackedVector3Array([Vector3(10.0, 0.0, 0.0)]))
	return manager.pos_x[slot]


func test_pace_hurries_every_walker() -> void:
	var normal: float = _step_with_pace(1.0)
	assert_gt(normal, 0.0)
	assert_almost_eq(_step_with_pace(1.5), normal * 1.5, 0.001)


func test_the_profile_keeps_the_longest_nachspielzeit_for_the_quests() -> void:
	var run: Dictionary = {"character": "resi", "map": "kirtag", "grant": 1, "result": "WON", "time": 1000.0,
		"overtime": 100.0, "level": 30, "kills": 100, "schilling": 50}
	var done: Array[StringName] = []
	for quest: QuestData in Profile.record_run(run)["quests"]:
		done.append(quest.id)
	assert_true(done.has(&"nachspielzeit"), "1 minute past Sperrstund'")
	assert_false(done.has(&"sperrstund_ignoriert"), "not 3 minutes yet")
	run["overtime"] = 200.0
	run["character"] = "ferdl"
	done.clear()
	for quest: QuestData in Profile.record_run(run)["quests"]:
		done.append(quest.id)
	assert_true(done.has(&"sperrstund_ignoriert"), "3 minutes with anyone")
	assert_false(done.has(&"oma_bleibt_sitzen"), "but not with Oma Resi")
	run["character"] = "resi"
	done.clear()
	for quest: QuestData in Profile.record_run(run)["quests"]:
		done.append(quest.id)
	assert_true(done.has(&"oma_bleibt_sitzen"), "3 minutes with Oma Resi")
	# A shorter run later keeps the record.
	run["overtime"] = 10.0
	Profile.record_run(run)
	var best: Dictionary = Profile.data["best"]["overtime"]
	assert_almost_eq(float(best["_all"]), 200.0, 0.001)
