extends GutTest
## The Heuriger (1.4 Part 1): the map, its Kellergassen, the Star-Schwarm, the Wespe, the
## Weinbergschnecke's slime and Der Sturm.

var balance: BalanceData


func before_each() -> void:
	balance = BalanceData.new()


func _manager(types: Array[EnemyTypeData]) -> EnemyManager:
	return EnemyManager.new(balance, types, 8, 3, null, 50.0)


func test_the_heuriger_loads_with_its_wave_music_and_buschenschanken() -> void:
	var map: MapData = load("res://data/maps/heuriger.tres")
	assert_eq(map.id, &"heuriger")
	assert_eq(map.music, &"heuriger")
	assert_true(map.wirtshaus_buschen)
	assert_eq(map.wave.id, &"heuriger")
	assert_gte(map.wirtshaus_spots.size(), 4)
	assert_true(ResourceLoader.exists("res://assets/audio/music/heuriger.ogg"))
	var bosses: Array[StringName] = []
	for entry: WaveBoss in map.wave.bosses:
		bosses.append(entry.boss.id)
	assert_has(bosses, &"sturm")
	for map_id: String in ["gamskogl", "gemeindebau"]:
		var other: MapData = load("res://data/maps/%s.tres" % map_id)
		assert_eq(other.music, StringName(map_id))
		assert_true(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % map_id))


func test_a_kellergasse_climbs_evenly_through_the_terraces() -> void:
	var map: MapData = load("res://data/maps/heuriger.tres")
	var line: Vector4 = map.lanes[0]
	var shape: Vector3 = map.lane_shapes[0]
	var from := Vector2(line.x, line.y)
	var to := Vector2(line.z, line.w)
	var last: float = -INF
	for k: int in 11:
		var at: Vector2 = from.lerp(to, k / 10.0)
		var h: float = map.terrain_height(at.x, at.y)
		assert_almost_eq(h, lerpf(shape.y, shape.z, k / 10.0), 0.6, "lane height at step %d" % k)
		assert_gt(h, last - 0.01)
		last = h


func test_a_star_pecks_up_loose_brosel_before_the_knodl() -> void:
	var star: EnemyTypeData = load("res://data/enemies/star.tres")
	var manager: EnemyManager = _manager([star])
	var field := BroselField.new()
	add_child_autofree(field)
	field.setup(balance, null, 50.0)
	manager.brosel = field
	field.drop(4.0, 0.0, 5, true)
	var slot: int = manager.spawn_at(0, 0.0, 0.0)
	var knodl := PackedVector4Array([Vector4(-6.0, 0.0, 0.0, 0.6)])
	for k: int in 120:
		manager.update(1.0 / 60.0, PackedVector3Array([Vector3(30.0, 0.0, 30.0)]), knodl)
	assert_eq(field.active_count, 0, "the Brösel is gone")
	assert_eq(field.stolen, 5)
	# With nothing left to peck, it goes for the Knödl.
	for k: int in 180:
		manager.update(1.0 / 60.0, PackedVector3Array([Vector3(30.0, 0.0, 30.0)]), knodl)
	assert_lt(Vector2(manager.pos_x[slot] + 6.0, manager.pos_z[slot]).length(), 2.0)


func test_a_wespe_only_wants_sweet_knodl() -> void:
	var wespe: EnemyTypeData = load("res://data/enemies/wespe.tres")
	var manager: EnemyManager = _manager([wespe])
	var slot: int = manager.spawn_at(0, 0.0, 0.0)
	var player := PackedVector3Array([Vector3(10.0, 0.0, 0.0)])
	var knodl := PackedVector4Array([Vector4(-10.0, 0.0, 0.0, 0.6)])
	manager.knodl_sweet = PackedByteArray([0])
	manager.update(0.1, player, knodl)
	assert_gt(manager.pos_x[slot], 0.0, "a Semmelknödl is not worth it: off to the player")
	manager.pos_x[slot] = 0.0
	manager.knodl_sweet = PackedByteArray([1])
	manager.update(0.1, player, knodl)
	assert_lt(manager.pos_x[slot], 0.0, "a Marillenknödl is")
	var marille: KnodlSortData = load("res://data/knodl/marillenknoedl.tres")
	var speck: KnodlSortData = load("res://data/knodl/speckknoedl.tres")
	assert_true(marille.sweet)
	assert_true(speck.heavy)


func test_the_slime_trail_slows_whoever_stands_on_it() -> void:
	var snail: EnemyTypeData = load("res://data/enemies/weinbergschnecke.tres")
	var trail := SlimeTrail.new()
	add_child_autofree(trail)
	trail.setup([snail], null, balance)
	var alive := PackedByteArray([1])
	trail.update(0.1, 1, alive, PackedFloat32Array([5.0]), PackedFloat32Array([5.0]), PackedByteArray([0]))
	assert_almost_eq(trail.speed_factor(Vector3(5.2, 0.0, 5.0)), 1.0 - snail.slime_slow, 0.001)
	assert_eq(trail.speed_factor(Vector3(9.0, 0.0, 5.0)), 1.0)
	trail.update(balance.slime_seconds + 0.1, 1, PackedByteArray([0]), PackedFloat32Array([5.0]),
			PackedFloat32Array([5.0]), PackedByteArray([0]))
	assert_eq(trail.speed_factor(Vector3(5.2, 0.0, 5.0)), 1.0, "it dries up")


func test_the_sturm_spiral_fills_up_one_mark_after_the_other() -> void:
	var boss: BossData = load("res://data/bosses/sturm.tres")
	var spiral: AttackData
	for attack: AttackData in boss.attacks:
		if attack.aim == AttackData.Aim.SPIRAL:
			spiral = attack
	assert_not_null(spiral)
	var field := HazardField.new()
	autofree(field)
	field.setup(null, 7)
	field.start_attack(spiral, 0.0, 0.0, 5.0, 0.0)
	assert_eq(field.hazards.size(), spiral.count)
	var nearest: float = INF
	var farthest: float = 0.0
	for k: int in field.hazards.size():
		var h: HazardField.Hazard = field.hazards[k]
		assert_almost_eq(h.telegraph, spiral.telegraph + k * spiral.stagger, 0.001)
		var out: float = Vector2(h.x, h.z).length()
		nearest = minf(nearest, out)
		farthest = maxf(farthest, out)
	assert_lt(nearest, spiral.spread * 0.5)
	assert_almost_eq(farthest, spiral.spread, 0.01)


func test_the_sturm_pulls_the_crowd_and_light_knodl_in() -> void:
	var boss: BossData = load("res://data/bosses/sturm.tres")
	var tourist: EnemyTypeData = load("res://data/enemies/tourist.tres")
	var wave := WaveData.new()
	var entry := WaveBoss.new()
	entry.boss = boss
	wave.bosses = [entry]
	wave.enemies = [tourist, boss.enemy, boss.escort]
	var manager: EnemyManager = EnemyManager.new(balance, wave.enemies, 24, 3, null, 50.0)
	var hazards := HazardField.new()
	autofree(hazards)
	hazards.setup(null, 7)
	var director := BossDirector.new(balance, manager, hazards, wave)
	var active: BossDirector.Active = director.spawn(0, 0.0, 0.0, 1)
	assert_not_null(active)
	var slot: int = manager.spawn_at(0, 10.0, 0.0)
	manager.speed[slot] = 0.0
	var far := PackedVector3Array([Vector3(45.0, 0.0, 45.0)])
	for k: int in 30:
		manager.update(1.0 / 60.0, far)
		director.update(1.0 / 60.0, far)
	assert_lt(Vector2(manager.pos_x[slot], manager.pos_z[slot]).length(), 10.0, "pulled in")
	var pull: Vector3 = director.pull_on(Vector3(8.0, 0.0, 0.0))
	assert_lt(pull.x, 0.0, "toward the Sturm")
	assert_eq(director.pull_on(Vector3(40.0, 0.0, 0.0)), Vector3.ZERO, "out of reach")
