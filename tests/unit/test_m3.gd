extends GutTest
## M3: the Kirtag map, attack marks, elites, bosses, loot and the run events.

var balance: BalanceData


func before_each() -> void:
	balance = load("res://data/balance.tres")


func _manager(types: Array[EnemyTypeData], capacity: int = 32) -> EnemyManager:
	return EnemyManager.new(balance, types, capacity, 3)


func _hazards() -> HazardField:
	var field := HazardField.new()
	autofree(field)
	field.setup(null, 7)
	return field


func _attack(shape: AttackData.Shape, aim: AttackData.Aim, count: int = 1) -> AttackData:
	var attack := AttackData.new()
	attack.shape = shape
	attack.aim = aim
	attack.count = count
	attack.radius = 2.0
	attack.length = 10.0
	attack.telegraph = 1.0
	attack.damage = 10.0
	attack.spread = 5.0
	return attack


func test_roof_and_spire_tops() -> void:
	var roof := MapProp.new()
	roof.kind = MapProp.Kind.ROOF
	roof.position = Vector3(0.0, 4.0, 0.0)
	roof.size = Vector3(8.0, 3.0, 6.0)
	assert_almost_eq(roof.top_at(0.0, 0.0), 7.0, 0.001, "the ridge")
	assert_almost_eq(roof.top_at(3.0, 2.9), 4.1, 0.001, "near the eaves")
	var spire := MapProp.new()
	spire.kind = MapProp.Kind.SPIRE
	spire.position = Vector3.ZERO
	spire.size = Vector3(4.0, 8.0, 4.0)
	assert_almost_eq(spire.top_at(0.0, 0.0), 8.0, 0.001)
	assert_almost_eq(spire.top_at(1.0, 0.0), 4.0, 0.001)


func test_structures_expand_into_props_on_the_terrain() -> void:
	var map := MapData.new()
	map.half_size = 30.0
	map.terrain_samples = 32
	map.noise_amplitude = 0.0
	map.rim_height = 0.0
	map.hills = PackedVector4Array([Vector4(10.0, 0.0, 8.0, 2.0)])
	var house := MapStructure.new()
	house.kind = MapStructure.Kind.HOUSE
	house.position = Vector2(10.0, 0.0)
	map.structures.append(house)
	var props: Array[MapProp] = map.all_props()
	assert_gt(props.size(), 3, "walls, roof, door, windows")
	assert_almost_eq(props[0].position.y, 2.0, 0.001, "stands on the hill")
	var solid: int = 0
	for prop: MapProp in props:
		if prop.solid:
			solid += 1
	assert_between(solid, 2, props.size() - 1, "windows and the door are decoration")


func test_the_kirtag_map_is_complete() -> void:
	var map: MapData = load("res://data/maps/kirtag.tres")
	assert_eq(map.half_size, 150.0, "about 300 x 300 m (GAME-DESIGN.md)")
	assert_eq(map.terrain_samples & (map.terrain_samples - 1), 0)
	assert_gte(map.wirtshaus_spots.size(), 4)
	assert_gte(map.stempel_spots.size(), balance.stempel_count)
	assert_gte(map.chest_spots.size(), balance.map_chest_count)
	assert_gt(map.structures.size(), 50)
	# 1.4: the chests and the Marterl share the spots, every map has room for both.
	for id: String in ["kirtag", "gamskogl", "gemeindebau", "heuriger"]:
		var other: MapData = load("res://data/maps/%s.tres" % id)
		assert_gte(other.chest_spots.size(), balance.map_chest_count + balance.marterl_count + 2, id)
	var terrain: Heightfield = Heightfield.bake_terrain(map)
	var ground: Heightfield = Heightfield.bake_ground(map, terrain)
	# Chests stand on the ground, not on a roof or inside a wall.
	for spot: Vector2 in map.chest_spots:
		assert_lt(ground.height_at(spot.x, spot.y) - terrain.height_at(spot.x, spot.y), 1.3, "chest at %s" % spot)
	assert_almost_eq(ground.height_at(map.spawn_point.x, map.spawn_point.z), 0.0, 0.2, "the spawn is free")


func test_marks_contain_points() -> void:
	var circle := HazardField.Hazard.new()
	circle.shape = AttackData.Shape.CIRCLE
	circle.x = 10.0
	circle.radius = 2.0
	assert_true(HazardField.contains(circle, 11.5, 0.0, 0.5))
	assert_false(HazardField.contains(circle, 13.0, 0.0, 0.5))
	var line := HazardField.Hazard.new()
	line.shape = AttackData.Shape.LINE
	line.angle = 0.0
	line.radius = 1.0
	line.length = 10.0
	assert_true(HazardField.contains(line, 0.5, 8.0, 0.2), "on the line (it runs along +z)")
	assert_false(HazardField.contains(line, 2.0, 5.0, 0.2), "beside it")
	assert_false(HazardField.contains(line, 0.0, 12.0, 0.2), "past its end")


func test_attacks_make_their_marks_and_hit_after_the_telegraph() -> void:
	var field: HazardField = _hazards()
	field.start_attack(_attack(AttackData.Shape.CIRCLE, AttackData.Aim.RING, 6), 0.0, 0.0, 5.0, 0.0)
	assert_eq(field.hazards.size(), 6)
	for h: HazardField.Hazard in field.hazards:
		assert_almost_eq(Vector2(h.x, h.z).length(), 5.0, 0.01, "around the attacker")
	field.start_attack(_attack(AttackData.Shape.LINE, AttackData.Aim.TARGET, 3), 0.0, 0.0, 0.0, 10.0)
	assert_eq(field.take_made().size(), 9)
	field.update(0.5)
	assert_eq(field.hits.size(), 0)
	field.update(0.6)
	assert_eq(field.hits.size(), 9)
	assert_eq(field.struck.size(), 9)
	field.update(HazardField.FLASH_SECONDS + 0.01)
	assert_eq(field.hazards.size(), 0, "gone after the flash")


func test_elites_stop_and_ask_for_their_attack_in_range() -> void:
	var perchte: EnemyTypeData = load("res://data/enemies/perchte.tres")
	var manager: EnemyManager = _manager([perchte])
	var slot: int = manager.spawn_at(0, 2.0, 0.0)
	manager.attack_timer[slot] = 0.0
	manager.update(1.0 / 60.0, PackedVector3Array([Vector3.ZERO]))
	assert_eq(manager.attack_slot.size(), 1)
	assert_gt(manager.busy[slot], perchte.attack.telegraph - 0.01)
	var x: float = manager.pos_x[slot]
	manager.clear_attacks()
	manager.update(0.2, PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	assert_almost_eq(manager.pos_x[slot], x, 0.05, "stands still while the mark fills")
	assert_eq(manager.attack_slot.size(), 0, "not again before the cooldown")


func test_spawn_at_uses_spare_slots_and_controlled_enemies_stay_put() -> void:
	var manager: EnemyManager = _manager([load("res://data/enemies/tourist.tres")], 16)
	manager.target_count = 8
	var slot: int = manager.spawn_at(0, 5.0, 5.0, true)
	assert_gte(slot, 8, "above the crowd's slots")
	manager.update(0.5, PackedVector3Array([Vector3.ZERO]))
	assert_almost_eq(manager.pos_x[slot], 5.0, 0.001, "BossDirector moves it, not the crowd logic")
	manager.start_dash(slot, 1.0, 0.0, 10.0, 0.4)
	assert_almost_eq(manager.dash_time[slot], 0.4, 0.0001)


func test_akten_geist_splits_into_formulare() -> void:
	var akten: EnemyTypeData = load("res://data/enemies/akten_geist.tres")
	var formular: EnemyTypeData = load("res://data/enemies/formular.tres")
	var manager: EnemyManager = _manager([akten, formular])
	var slot: int = manager.spawn_at(0, 0.0, 0.0)
	assert_true(manager.damage(slot, 1000.0))
	var formulare: int = 0
	for i: int in manager.capacity:
		if manager.alive[i] != 0 and manager.type[i] == 1:
			formulare += 1
	assert_eq(formulare, akten.split_count)


func test_boss_director_spawns_fights_and_reports_the_kill() -> void:
	var wave: WaveData = load("res://data/waves/kirtag.tres")
	var manager := EnemyManager.new(balance, wave.enemies, 64, 9)
	var field: HazardField = _hazards()
	var director := BossDirector.new(balance, manager, field, wave)
	assert_eq(director.list.size(), 3)
	var boss: BossDirector.Active = director.spawn(0, 10.0, 0.0, 2)
	assert_not_null(boss)
	assert_almost_eq(manager.max_hp[boss.slot], director.list[0].max_hp * (1.0 + balance.coop_boss_hp_per_player), 0.01)
	assert_eq(manager.controlled[boss.slot], 1)
	var targets := PackedVector3Array([Vector3.ZERO])
	for frame: int in 240:
		director.update(1.0 / 60.0, targets)
	assert_gt(field.hazards.size(), 0, "it attacked")
	assert_lt(manager.pos_x[boss.slot], 10.0, "it came closer")
	var touch := PackedFloat32Array([0.0])
	manager.shove(boss.slot, 0.5, 0.0)
	director.touch_damage(targets, touch)
	assert_gt(touch[0], 0.0)
	manager.damage(boss.slot, 1.0e9)
	var beaten: Array[BossDirector.Active] = director.update(1.0 / 60.0, targets)
	assert_eq(beaten.size(), 1)
	assert_eq(director.active.size(), 0)


func test_loot_add_find_and_take() -> void:
	var loot := LootField.new()
	autofree(loot)
	loot.setup(null)
	var coin: int = loot.add(LootField.Kind.COIN, 1.0, 0.0, 5)
	var chest: int = loot.add(LootField.Kind.CHEST, 10.0, 0.0, 25)
	assert_eq(loot.count, 2)
	assert_eq(loot.near(0.0, 0.0, 0.0, 2.0).size(), 1)
	assert_eq(loot.nearest(LootField.Kind.CHEST, 0.0, 0.0), loot.slot_of(chest))
	loot.attract(0.0, 0.0, 4.0, 1.0)
	assert_lt(loot.xs[loot.slot_of(coin)], 1.0, "coins drift to the player")
	loot.remove(coin)
	assert_false(loot.has(coin))
	loot.add_remote(77, LootField.Kind.STEMPEL, 3.0, 3.0, 0)
	assert_true(loot.has(77))
	assert_eq(loot.count, 2)


func test_run_events_round_trip() -> void:
	var queue := RunEventCodec.Queue.new()
	var h := HazardField.Hazard.new()
	h.id = 513
	h.shape = AttackData.Shape.LINE
	h.x = -12.5
	h.z = 40.25
	h.angle = 1.25
	h.radius = 1.5
	h.length = 20.0
	h.telegraph = 1.2
	queue.hazard(h)
	queue.loot(9, LootField.Kind.BOSS_CHEST, 3.0, -4.0, 5 | LootField.EVOLUTION_BIT)
	queue.taken(9, 1234567)
	queue.toast("TOAST_FORMULAR")
	queue.boss(2, RunEventCodec.BossState.BEATEN, 300)
	queue.bus(1.0, 2.0, 0.5)
	queue.cue(RunEventCodec.Cue.GATE_OPEN, 0.0, -76.0)
	var events: Array[RunEventCodec.Event] = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(events.size(), 7)
	assert_eq(events[0].id, 513)
	assert_eq(events[0].a, AttackData.Shape.LINE)
	assert_almost_eq(events[0].length, 20.0, 0.01)
	assert_almost_eq(events[0].seconds, 1.2, 0.001)
	assert_eq(events[1].b, 5 | LootField.EVOLUTION_BIT)
	assert_eq(events[2].b, 1234567)
	assert_eq(events[3].text, "TOAST_FORMULAR")
	assert_eq(events[4].a, 2)
	assert_eq(events[4].c, RunEventCodec.BossState.BEATEN)
	assert_eq(events[4].b, 300)
	assert_almost_eq(events[5].angle, 0.5, 0.0001)
	assert_eq(events[6].a, RunEventCodec.Cue.GATE_OPEN)
	assert_true(queue.take().is_empty())


func test_run_events_refuse_garbage() -> void:
	assert_true(RunEventCodec.decode(PackedByteArray([1, 1, 99])).is_empty())
	assert_true(RunEventCodec.decode(PackedByteArray([7, 0])).is_empty())
	var good: PackedByteArray = RunEventCodec.encode([])
	good.append(0)
	assert_true(RunEventCodec.decode(good).is_empty(), "trailing bytes")


func test_world_state_carries_the_gate_and_the_boss() -> void:
	var frame := WorldStateCodec.Frame.new()
	frame.stempel_found = 2
	frame.stempel_total = 3
	frame.gate = WorldStateCodec.GATE_FORMULAR | WorldStateCodec.GATE_OPEN
	frame.result = 3
	frame.boss = 1
	frame.boss_slot = 300
	frame.boss_hp = 1234.5
	frame.boss_max_hp = 2200.0
	var e := WorldStateCodec.Entry.new()
	e.chests_opened = 4
	frame.entries.append(e)
	var back: WorldStateCodec.Frame = WorldStateCodec.decode(WorldStateCodec.encode(frame))
	assert_not_null(back)
	assert_eq(back.stempel_found, 2)
	assert_eq(back.stempel_total, 3)
	assert_eq(back.gate, frame.gate)
	assert_eq(back.result, 3)
	assert_eq(back.boss, 1)
	assert_eq(back.boss_slot, 300)
	assert_almost_eq(back.boss_hp, 1234.5, 0.01)
	assert_eq(back.entries[0].chests_opened, 4)


func test_audio_files_exist_for_every_sound() -> void:
	for id: StringName in GameAudio.SOUNDS:
		assert_true(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % id), String(id))
	for track: String in ["kirtag", "boss", "sperrstund"]:
		assert_true(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % track), track)
	for bark: String in ["heast", "geh_bitte", "servas", "wurscht"]:
		assert_true(ResourceLoader.exists("res://assets/audio/sfx/bark_%s.ogg" % bark), bark)
