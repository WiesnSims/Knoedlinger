class_name EnemyVoices
extends Node3D
## Talking enemies (Berghittn's "Gredn", docs/DECISIONS.md): now and then an enemy near a player
## says a short dialect line, heard at its place and shown as text over its head. Far less chatty
## than Berghittn: one line every balance.voice_gap_min..max at most, never over the one before.
## The lines are data (EnemyTypeData.voice, data/voice_lines/), the voices are made by
## tools/audio/voices/voices.py.
##
## The host picks the lines: offer() for a moment (an attack, last words, a Knödl kill, a bite, a
## boss arriving ...) and an idle line from a random enemy near a player when nothing else came
## (host_update). It puts each in the run events (RunEventCodec SAY), so every role, solo too,
## shows it through present() if the "enemy_chatter" setting is on. Run by RunWorld.

## Lines shown at once; a nearer line takes the farther one's place.
const SHOWN: int = 2
## Random slots looked at for an idle line per try.
const IDLE_TRIES: int = 16
## The text keeps one size on screen (fixed_size): about the theme's body size (20 px of 720) at the
## default 80 degree field of view.
const TEXT_SIZE: int = 48
const TEXT_PIXEL: float = 0.00097
const TEXT_WIDTH: float = 900.0

var balance: BalanceData
var types: Array[EnemyTypeData] = []
var ground: Heightfield
var events: RunEventCodec.Queue
## Where the enemies are: the host's EnemyManager, or a client's EnemyReplica.
var enemies: EnemyManager
var replica: EnemyReplica
## Lines the host picked, and lines this machine showed (tests, mp_test).
var said: int = 0
var shown: int = 0

var _rng := RandomNumberGenerator.new()
## The gaps of balance.tres, or `?voice_every=<seconds>` (screenshots): a line that often, any type.
var _gap_min: float = 0.0
var _gap_max: float = 0.0
var _idle_after: float = 0.0
var _type_seconds: float = 0.0
var _gap: float = 0.0
var _idle_wait: float = 0.0
var _boss_gap: float = 0.0
var _type_gap := PackedFloat32Array()
var _half_said: Dictionary[int, bool] = {}
var _targets := PackedVector3Array()
var _view: Vector3 = Vector3.INF
var _bubbles: Array[Label3D] = []
## Per bubble: the slot it follows (-1 = stays where it is), the type there, a figure it follows
## instead (the Riesen-Wirt) and how high over it, seconds left, and where it is.
var _slot := PackedInt32Array()
var _type := PackedInt32Array()
var _node: Array[Node3D] = []
var _lift := PackedFloat32Array()
var _left := PackedFloat32Array()
var _at: Array[Vector3] = []


func setup(p_balance: BalanceData, p_types: Array[EnemyTypeData], p_ground: Heightfield, p_events: RunEventCodec.Queue,
		seed_value: int) -> void:
	balance = p_balance
	types = p_types
	ground = p_ground
	events = p_events
	_rng.seed = seed_value
	_type_gap.resize(types.size())
	_gap_min = balance.voice_gap_min
	_gap_max = balance.voice_gap_max
	_idle_after = balance.voice_idle_wait
	_type_seconds = balance.voice_type_gap
	var every: float = LaunchArgs.get_float("voice_every", 0.0)
	if every > 0.0:
		_gap_min = every
		_gap_max = every
		_idle_after = 0.0
		_type_seconds = 0.0
	_gap = _rng.randf_range(_gap_min, _gap_max)
	for k: int in SHOWN:
		var label: Label3D = make_text()
		label.name = "Line%d" % k
		label.visible = false
		add_child(label)
		_bubbles.append(label)
		_slot.append(-1)
		_type.append(0)
		_node.append(null)
		_lift.append(0.0)
		_left.append(0.0)
		_at.append(Vector3.ZERO)


## The text over a speaker's head (ShaderWarmup builds one too, so its shader is ready in time).
static func make_text() -> Label3D:
	var label := Label3D.new()
	label.font = UiStyle.font("bold")
	label.font_size = TEXT_SIZE
	label.pixel_size = TEXT_PIXEL
	label.fixed_size = true
	label.outline_size = 10
	label.modulate = UiStyle.color("text")
	label.outline_modulate = UiStyle.color("shadow")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = TEXT_WIDTH
	return label


## Host, every frame: the gaps run down, bosses at half health speak up, and an idle line comes
## once the gap and the wait for a moment's line are over. `targets` are the players.
func host_update(delta: float, targets: PackedVector3Array, boss_slots: PackedInt32Array) -> void:
	_targets = targets
	_boss_gap -= delta
	for t: int in _type_gap.size():
		_type_gap[t] -= delta
	for slot: int in boss_slots:
		if not _half_said.has(slot) and enemies.alive[slot] != 0 and enemies.hp[slot] < enemies.max_hp[slot] * 0.5:
			_half_said[slot] = true
			offer(slot, VoiceLineData.Moment.HALF)
	if _gap > 0.0:
		_gap -= delta
		return
	_idle_wait -= delta
	if _idle_wait > 0.0:
		return
	for k: int in IDLE_TRIES:
		var slot: int = _rng.randi_range(0, enemies.capacity - 1)
		if enemies.alive[slot] != 0 and offer(slot, VoiceLineData.Moment.IDLE):
			return


## Host: the enemy in `slot` may say a line for `moment` (a dead one at the place it died). Returns
## true when it does.
func offer(slot: int, moment: VoiceLineData.Moment) -> bool:
	var t: int = enemies.type[slot]
	var lines: VoiceLineSet = types[t].voice
	if lines == null:
		return false
	var picks: PackedInt32Array = lines.lines_for(moment)
	if picks.is_empty():
		return false
	var boss: bool = types[t].boss
	var always: bool = moment >= VoiceLineData.Moment.ARRIVE
	var x: float = enemies.pos_x[slot]
	var z: float = enemies.pos_z[slot]
	if not boss and (_type_gap[t] > 0.0 or not _near(x, z)):
		return false
	var line: int = picks[_rng.randi_range(0, picks.size() - 1)]
	if not always:
		if boss and _boss_gap > 0.0:
			return false
		if not boss and _gap > 0.0:
			return false
		var chance: float = lines.lines[line].chance
		if chance < 0.0:
			chance = balance.voice_chance_boss_attack if boss else _chance(moment)
		if _rng.randf() >= chance:
			return false
	var length: float = GameAudio.length(lines.lines[line].sound)
	_gap = maxf(_rng.randf_range(_gap_min, _gap_max), length + 0.5)
	_idle_wait = _idle_after
	_type_gap[t] = _type_seconds
	if boss or always:
		_boss_gap = balance.voice_boss_gap
	said += 1
	events.say(t, line, slot, x, z)
	return true


## Host: a Bröselfresser next to the Knödl at `at` (radius `radius`) may comment on its meal.
func offer_bite(at: Vector3, radius: float) -> void:
	if _gap > 0.0:
		return
	var grid: SpatialHash = enemies.grid
	var found: int = grid.query(at.x, at.z, radius + 1.5)
	for k: int in found:
		var slot: int = grid.results[k]
		var t: int = enemies.type[slot]
		if enemies.alive[slot] != 0 and types[t].eats_knodl and types[t].voice != null:
			offer(slot, VoiceLineData.Moment.EAT)
			return


## Every role: an enemy of type `t` says line `line` (from the run events). Plays it at its place
## and shows the text over its head, following the enemy in `slot` while it lives.
func present(t: int, line: int, slot: int, x: float, z: float) -> void:
	if t >= types.size() or types[t].voice == null or line >= types[t].voice.lines.size():
		return
	var data: VoiceLineData = types[t].voice.lines[line]
	# Last words stay where it fell; the slot is someone else's soon.
	var follow: int = -1 if data.moment == VoiceLineData.Moment.DEATH or data.moment == VoiceLineData.Moment.CRUSHED \
			or data.moment == VoiceLineData.Moment.BEATEN else slot
	_show(data, Vector3(x, ground.height_at(x, z) + _head(t), z), follow, t, null, 0.0)


## Every role: a figure that is no enemy (the Riesen-Wirt, which every machine moves itself) says
## one of its lines for `moment`.
func say_local(lines: VoiceLineSet, moment: VoiceLineData.Moment, figure: Node3D, head: float) -> void:
	var picks: PackedInt32Array = lines.lines_for(moment) if lines != null else PackedInt32Array()
	if picks.is_empty():
		return
	var data: VoiceLineData = lines.lines[picks[_rng.randi_range(0, picks.size() - 1)]]
	_show(data, figure.global_position + Vector3.UP * head, -1, 0, figure, head)


## Every role, every frame: the texts follow their speakers and fade; `view` is where the local
## player is.
func update_view(delta: float, view: Vector3) -> void:
	_view = view
	for k: int in SHOWN:
		var label: Label3D = _bubbles[k]
		if not label.visible:
			continue
		_left[k] -= delta
		if _left[k] <= 0.0:
			label.visible = false
			continue
		if _node[k] != null and is_instance_valid(_node[k]):
			_at[k] = _node[k].global_position + Vector3.UP * _lift[k]
		elif _slot[k] >= 0:
			var at: Vector2 = _enemy_at(_slot[k], _type[k])
			if is_finite(at.x):
				_at[k] = Vector3(at.x, ground.height_at(at.x, at.y) + _head(_type[k]), at.y)
			else:
				_slot[k] = -1
		label.global_position = _at[k]
		label.modulate.a = clampf(_left[k] / balance.voice_fade_seconds, 0.0, 1.0)
		label.outline_modulate.a = label.modulate.a * UiStyle.color("shadow").a


func _show(data: VoiceLineData, at: Vector3, slot: int, t: int, figure: Node3D, lift: float) -> void:
	if not _chatter():
		return
	var length: float = GameAudio.say(data.sound, at)
	var distance: float = at.distance_to(_view) if _view.is_finite() else 0.0
	if distance > balance.voice_show_reach:
		return
	# A free bubble, or the farther one if this line is nearer.
	var pick: int = -1
	var farthest: float = distance
	for k: int in SHOWN:
		if not _bubbles[k].visible:
			pick = k
			break
		var d: float = _at[k].distance_to(_view) if _view.is_finite() else 0.0
		if d > farthest:
			farthest = d
			pick = k
	if pick < 0:
		return
	var label: Label3D = _bubbles[pick]
	label.text = tr(data.text_key)
	label.visible = true
	label.modulate.a = 1.0
	label.outline_modulate.a = UiStyle.color("shadow").a
	label.global_position = at
	_at[pick] = at
	_slot[pick] = slot
	_type[pick] = t
	_node[pick] = figure
	_lift[pick] = lift
	_left[pick] = maxf(length, balance.voice_min_seconds) + balance.voice_fade_seconds
	shown += 1


## Where the enemy in `slot` is while it is still of type `t`; (INF, INF) once it is gone.
func _enemy_at(slot: int, t: int) -> Vector2:
	if enemies != null:
		if enemies.alive[slot] != 0 and enemies.type[slot] == t:
			return Vector2(enemies.pos_x[slot], enemies.pos_z[slot])
	elif replica != null and slot < replica.capacity:
		if replica.alive[slot] != 0 and replica.type[slot] == t:
			return Vector2(replica.x[slot], replica.z[slot])
	return Vector2(INF, INF)


## Metres from the ground to just over its head.
func _head(t: int) -> float:
	var data: EnemyTypeData = types[t]
	return data.model_scale * 1.9 + 0.5 + (1.5 if data.flying else 0.0)


func _near(x: float, z: float) -> bool:
	var reach_sq: float = balance.voice_reach * balance.voice_reach
	for at: Vector3 in _targets:
		if (at.x - x) * (at.x - x) + (at.z - z) * (at.z - z) < reach_sq:
			return true
	return false


func _chance(moment: VoiceLineData.Moment) -> float:
	match moment:
		VoiceLineData.Moment.ATTACK:
			return balance.voice_chance_attack
		VoiceLineData.Moment.DEATH:
			return balance.voice_chance_death
		VoiceLineData.Moment.CRUSHED:
			return balance.voice_chance_crushed
		VoiceLineData.Moment.EAT:
			return balance.voice_chance_eat
	return 1.0


func _chatter() -> bool:
	return not Settings.persistent or bool(Settings.get_value(&"enemy_chatter"))
