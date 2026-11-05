extends Node
## Sound and music (autoload GameAudio). Sounds are OGG files in assets/audio/sfx/<id>.ogg, music in
## assets/audio/music/<id>.ogg; a missing file is simply silent. Sounds at a place get quieter with
## distance from the listener (the local camera); every sound has a minimum gap and a voice limit,
## so 500 enemies dying at once stay one crunchy pop instead of 500. Barks (short dialect lines)
## come at most once per BARK_GAP seconds (GAME-DESIGN.md: max one per 8 s). Music crossfades
## between tracks and can speed up with the run clock.
## `?mute=1` / `--mute=1` silences everything (automated runs). Music, effects and barks play on
## their own buses (Music, Sfx, Voice, from default_bus_layout.tres), whose volumes the Settings
## set. The buses must come from the layout file: on the web, buses added at runtime never reach
## the browser's audio graph and everything played on them is silent.

const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"
const VOICES: int = 20
const BARK_GAP: float = 8.0
## Distance (m) at which a placed sound has faded out completely.
const HEARING_RANGE: float = 45.0
const CROSSFADE: float = 1.5

## id: [minimum seconds between two plays, volume dB, max at once]
const SOUNDS: Dictionary[StringName, Array] = {
	&"hit": [0.05, -14.0, 3],
	&"kill": [0.06, -12.0, 3],
	&"brosel": [0.07, -18.0, 2],
	&"knodl_hit": [0.12, -8.0, 2],
	&"schupfn": [0.2, -6.0, 1],
	&"reel": [0.3, -10.0, 1],
	&"jump": [0.15, -14.0, 1],
	&"swing": [0.08, -16.0, 2],
	&"hurt": [0.3, -6.0, 1],
	&"downed": [1.0, -2.0, 1],
	&"level_up": [0.5, -4.0, 1],
	&"card": [0.08, -8.0, 1],
	&"ui_hover": [0.04, -16.0, 1],
	&"menu_open": [0.3, -8.0, 1],
	&"cash_in": [0.5, -3.0, 1],
	&"mahlzeit": [1.0, 0.0, 1],
	&"coin": [0.05, -10.0, 2],
	&"chest": [0.3, -4.0, 1],
	&"no_gold": [0.6, -8.0, 1],
	&"heal": [0.3, -6.0, 1],
	&"stempel": [0.3, -2.0, 1],
	&"gate_open": [1.0, -2.0, 1],
	&"warn": [0.25, -12.0, 2],
	&"slam": [0.08, -6.0, 3],
	&"boss_arrive": [2.0, -2.0, 1],
	&"boss_beaten": [2.0, -2.0, 1],
	&"bus_horn": [2.0, -4.0, 1],
	&"sperrstund": [2.0, 0.0, 1],
	&"victory": [2.0, -2.0, 1],
	&"defeat": [2.0, -2.0, 1],
}

var muted: bool = false
var music_volume_db: float = -8.0

var _streams: Dictionary[StringName, AudioStream] = {}
var _missing: Dictionary[StringName, bool] = {}
var _voices: Array[AudioStreamPlayer] = []
var _last_played: Dictionary[StringName, float] = {}
var _listener: Vector3 = Vector3.INF
var _last_bark: float = -100.0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_track: StringName = &""
var _fade: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	muted = LaunchArgs.get_flag("mute", false) or DisplayServer.get_name() == "headless"
	for bus: StringName in [&"Music", &"Sfx", &"Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			push_error("GameAudio: bus %s missing from default_bus_layout.tres" % bus)
	for k: int in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % k
		player.bus = &"Sfx"
		add_child(player)
		_voices.append(player)
	_music_a = AudioStreamPlayer.new()
	_music_a.name = "MusicA"
	_music_a.bus = &"Music"
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.name = "MusicB"
	_music_b.bus = &"Music"
	add_child(_music_b)


## Where the local player hears from (the camera); Vector3.INF = everything at full volume.
func set_listener(at: Vector3) -> void:
	_listener = at


## Plays a sound once; `at` = where it happens (Vector3.INF = not placed, e.g. the UI).
func play(id: StringName, at: Vector3 = Vector3.INF, pitch_jitter: float = 0.08) -> void:
	if muted:
		return
	var info: Array = SOUNDS.get(id, [0.05, -8.0, 2])
	var last: float = _last_played.get(id, -100.0)
	if _time - last < float(info[0]):
		return
	var volume: float = float(info[1])
	if at.is_finite() and _listener.is_finite():
		var distance: float = at.distance_to(_listener)
		if distance > HEARING_RANGE:
			return
		volume += linear_to_db(clampf(1.0 - distance / HEARING_RANGE, 0.05, 1.0))
	if _playing(id) >= int(info[2]):
		return
	var stream: AudioStream = _stream(SFX_DIR, id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_voice()
	if player == null:
		return
	_last_played[id] = _time
	player.stream = stream
	player.bus = &"Sfx"
	player.volume_db = volume
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.set_meta(&"id", id)
	player.play()


## A short dialect line (bark_<id>); at most one every BARK_GAP seconds.
func bark(id: StringName) -> void:
	if muted or _time - _last_bark < BARK_GAP:
		return
	var stream: AudioStream = _stream(SFX_DIR, StringName("bark_" + id))
	if stream == null:
		return
	var player: AudioStreamPlayer = _free_voice()
	if player == null:
		return
	_last_bark = _time
	player.stream = stream
	player.bus = &"Voice"
	player.volume_db = -1.0
	player.pitch_scale = 1.0
	player.set_meta(&"id", &"bark")
	player.play()


## Switches the music (crossfade); the same track keeps playing. &"" fades out.
func music(track: StringName) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old: AudioStreamPlayer = _music_a
	_music_a = _music_b
	_music_b = old
	_music_a.stop()
	_fade = CROSSFADE
	if muted or track == &"":
		return
	var stream: AudioStream = _stream(MUSIC_DIR, track)
	if stream == null:
		return
	_music_a.stream = stream
	_music_a.volume_db = -60.0
	_music_a.pitch_scale = 1.0
	_music_a.play()


## Tempo of the music (Volksmusik-Techno speeds up toward Sperrstund').
func set_music_speed(speed: float) -> void:
	if _music_a.playing:
		_music_a.pitch_scale = speed


func current_music() -> StringName:
	return _music_track


func _process(delta: float) -> void:
	_time += delta
	if _fade > 0.0:
		_fade = maxf(_fade - delta, 0.0)
		var t: float = 1.0 - _fade / CROSSFADE
		if _music_a.playing:
			_music_a.volume_db = lerpf(-40.0, music_volume_db, t)
		if _music_b.playing:
			_music_b.volume_db = lerpf(music_volume_db, -40.0, t)
			if _fade <= 0.0:
				_music_b.stop()


func _stream(dir: String, id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	if _missing.has(id):
		return null
	var path: String = dir.path_join(String(id) + ".ogg")
	if not ResourceLoader.exists(path):
		_missing[id] = true
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis and dir == MUSIC_DIR:
		(stream as AudioStreamOggVorbis).loop = true
	_streams[id] = stream
	return stream


func _playing(id: StringName) -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _voices:
		if player.playing and player.get_meta(&"id", &"") == id:
			count += 1
	return count


func _free_voice() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _voices:
		if not player.playing:
			return player
	return null
