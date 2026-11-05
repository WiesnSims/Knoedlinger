extends GutTest
## Talking enemies (EnemyVoices): the lines as data, the co-op event, and how often they talk.

const TALKERS: Array[String] = ["tourist", "akten_geist", "radler", "rasenmaeher", "perchte", "schneemann"]
const STEP: float = 1.0 / 60.0

var balance: BalanceData


func before_each() -> void:
	balance = load("res://data/balance.tres")


func test_every_line_has_a_text_and_a_voice() -> void:
	var sets: Array[VoiceLineSet] = [load("res://data/voice_lines/riesen_wirt.tres")]
	var quiet: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data: EnemyTypeData = load("res://data/enemies/" + file)
		if data.voice == null:
			quiet.append(String(data.id))
		else:
			sets.append(data.voice)
	# Only the Gelsen and the Lawine keep quiet.
	quiet.sort()
	assert_eq(quiet, ["gelse", "lawine"] as Array[String])
	var lines: int = 0
	for lines_set: VoiceLineSet in sets:
		assert_false(lines_set.lines.is_empty())
		for line: VoiceLineData in lines_set.lines:
			lines += 1
			assert_ne(tr(line.text_key), line.text_key, "text of %s" % line.text_key)
			assert_true(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % line.sound), "voice %s" % line.sound)
			assert_gt(GameAudio.length(line.sound), 0.2, "length of %s" % line.sound)
	assert_gt(lines, 60)


func test_say_event_round_trip() -> void:
	var queue := RunEventCodec.Queue.new()
	queue.say(7, 3, 1023, -41.5, 12.25)
	var events: Array[RunEventCodec.Event] = RunEventCodec.decode(RunEventCodec.encode(queue.take()))
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, RunEventCodec.Kind.SAY)
	assert_eq(events[0].a, 7)
	assert_eq(events[0].b, 3)
	assert_eq(events[0].id, 1023)
	assert_almost_eq(events[0].x, -41.5, 0.001)
	assert_almost_eq(events[0].z, 12.25, 0.001)


func test_lines_come_every_few_seconds_and_never_overlap() -> void:
	var setup: Array = _crowd(TALKERS)
	var voices: EnemyVoices = setup[0]
	var queue: RunEventCodec.Queue = setup[1]
	var targets := PackedVector3Array([Vector3.ZERO])
	var times: Array[float] = []
	var last_by_type: Dictionary[int, float] = {}
	var seconds: float = 0.0
	var ends: float = 0.0
	for frame: int in 180 * 60:
		seconds += STEP
		voices.host_update(STEP, targets, PackedInt32Array())
		for e: RunEventCodec.Event in queue.take():
			assert_eq(e.kind, RunEventCodec.Kind.SAY)
			assert_gt(seconds, ends, "a line over the one before")
			var line: VoiceLineData = voices.types[e.a].voice.lines[e.b]
			ends = seconds + GameAudio.length(line.sound)
			if last_by_type.has(e.a):
				assert_gt(seconds - last_by_type[e.a], balance.voice_type_gap - 0.01, "type gap")
			last_by_type[e.a] = seconds
			times.append(seconds)
	var gaps: Array[float] = []
	for k: int in range(1, times.size()):
		gaps.append(times[k] - times[k - 1])
	var mean: float = (times.back() - times.front()) / maxi(times.size() - 1, 1)
	gaps.sort()
	gut.p("voices: %d lines in 180 s, gaps %.2f..%.2f s, mean %.2f s" % [times.size(), gaps.front(), gaps.back(), mean])
	assert_gt(gaps.front(), balance.voice_gap_min - 0.01, "shortest gap")
	assert_between(mean, 3.0, 5.5, "mean gap %.2f s over %d lines" % [mean, times.size()])


func test_nobody_far_away_talks() -> void:
	var setup: Array = _crowd(TALKERS)
	var voices: EnemyVoices = setup[0]
	var queue: RunEventCodec.Queue = setup[1]
	var far := PackedVector3Array([Vector3(200.0, 0.0, 200.0)])
	for frame: int in 30 * 60:
		voices.host_update(STEP, far, PackedInt32Array())
	assert_true(queue.take().is_empty())


func test_bosses_always_speak_up_but_others_wait() -> void:
	var setup: Array = _crowd(["tourist", "oberkrampus"])
	var voices: EnemyVoices = setup[0]
	var queue: RunEventCodec.Queue = setup[1]
	voices.host_update(STEP, PackedVector3Array([Vector3.ZERO]), PackedInt32Array())
	var tourist: int = -1
	var boss: int = -1
	for slot: int in voices.enemies.capacity:
		if voices.enemies.alive[slot] != 0:
			if voices.enemies.type[slot] == 0 and tourist < 0:
				tourist = slot
			elif voices.enemies.type[slot] == 1 and boss < 0:
				boss = slot
	# Arriving is always said; the tourist's last words have to wait for the gap after it.
	assert_true(voices.offer(boss, VoiceLineData.Moment.ARRIVE))
	for k: int in 50:
		assert_false(voices.offer(tourist, VoiceLineData.Moment.DEATH))
	# Down to half its health, the boss says so once.
	voices.enemies.hp[boss] = voices.enemies.max_hp[boss] * 0.4
	queue.take()
	for frame: int in 10:
		voices.host_update(STEP, PackedVector3Array([Vector3.ZERO]), PackedInt32Array([boss]))
	var half: int = 0
	for e: RunEventCodec.Event in queue.take():
		if voices.types[e.a].voice.lines[e.b].moment == VoiceLineData.Moment.HALF:
			half += 1
	assert_eq(half, 1)


## EnemyVoices on a host with a crowd of these types around (0, 0), within reach.
func _crowd(ids: Array) -> Array:
	var types: Array[EnemyTypeData] = []
	for id: String in ids:
		types.append(load("res://data/enemies/%s.tres" % id))
	var manager := EnemyManager.new(balance, types, 64, 3)
	manager.populate(60, PackedVector3Array([Vector3.ZERO]))
	for slot: int in manager.capacity:
		var angle: float = TAU * slot / manager.capacity
		manager.shove(slot, cos(angle) * 8.0, sin(angle) * 8.0)
		# One of each type for sure, the rest mixed.
		if slot < ids.size():
			manager.type[slot] = slot
	var queue := RunEventCodec.Queue.new()
	var voices := EnemyVoices.new()
	add_child_autofree(voices)
	voices.setup(balance, types, null, queue, 11)
	voices.enemies = manager
	return [voices, queue]
