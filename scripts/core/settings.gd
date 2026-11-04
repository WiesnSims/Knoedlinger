extends Node
## Player settings (autoload Settings), saved in user://settings.cfg (IndexedDB in the browser):
## volumes, fullscreen, anti-aliasing, quality, camera, gamepad and touch, flashing, glossary
## tooltips, language and the player name. Change a
## value with set_value(); it is applied at once, saved, and `changed` tells the screens and the
## camera. Automated runs (bot, autoplay, headless) never load or save the file, so a player's
## settings never change what a test measures.

signal changed(key: StringName)

const PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const NAME_MAX: int = 16
const NAME_FALLBACK: String = "Knödlinger"
## Audio buses GameAudio plays on (created by GameAudio).
const BUSES: Dictionary[StringName, StringName] = {
	&"volume_master": &"Master", &"volume_music": &"Music", &"volume_sfx": &"Sfx", &"volume_voice": &"Voice",
}
const DEFAULTS: Dictionary[StringName, Variant] = {
	&"volume_master": 0.8,
	&"volume_music": 0.7,
	&"volume_sfx": 0.8,
	&"volume_voice": 0.9,
	&"mute": false,
	&"fullscreen": false,
	## Render quality (QualityScaler): "auto" steps down by itself when the frame rate drops.
	&"quality": "auto",
	## The Jagatee's slight screen wobble (and other camera shakes).
	&"screen_wobble": true,
	## MSAA on the 3D view (WebGL2 supports it in the Compatibility renderer).
	&"antialiasing": true,
	## Metres, the camera's starting distance (the mouse wheel still zooms).
	&"camera_distance": 8.0,
	&"camera_fov": 80.0,
	## Multiplies balance.camera_mouse_sensitivity.
	&"mouse_sensitivity": 1.0,
	&"invert_y": false,
	## Multiplies the right stick's look speed (balance.camera_pad_yaw_speed / _pitch_speed).
	&"pad_look_speed": 1.0,
	## Seconds of look smoothing (balance.camera_look_smoothing is the default).
	&"look_smoothing": 0.05,
	## Touch buttons on screen (TouchControls): "auto" = once the screen is touched.
	&"touch_controls": "auto",
	&"touch_size": 1.0,
	&"touch_opacity": 0.6,
	&"reduce_flashing": false,
	&"glossary": true,
	## Send real runs to the online Ehrentafel.
	&"board": true,
	&"language": "de",
	&"player_name": "",
}
## The anti-aliasing level when the setting is on.
const MSAA_ON: Viewport.MSAA = Viewport.MSAA_4X
## Allowed range and step of the number settings: [min, max, step].
const RANGES: Dictionary[StringName, Array] = {
	&"volume_master": [0.0, 1.0, 0.05],
	&"volume_music": [0.0, 1.0, 0.05],
	&"volume_sfx": [0.0, 1.0, 0.05],
	&"volume_voice": [0.0, 1.0, 0.05],
	&"camera_distance": [4.5, 16.0, 0.5],
	&"camera_fov": [60.0, 100.0, 1.0],
	&"mouse_sensitivity": [0.25, 3.0, 0.05],
	&"pad_look_speed": [0.25, 3.0, 0.05],
	&"look_smoothing": [0.0, 0.2, 0.01],
	&"touch_size": [0.7, 1.5, 0.05],
	&"touch_opacity": [0.2, 1.0, 0.05],
}
## The allowed values of the choice settings, in the order the menu steps through them.
const CHOICES: Dictionary[StringName, Array] = {
	&"quality": ["auto", "high", "medium", "low"],
	&"touch_controls": ["auto", "on", "off"],
}

var _values: Dictionary[StringName, Variant] = {}
## False in automated runs: the file is neither read nor written.
var persistent: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate()
	persistent = not (DisplayServer.get_name() == "headless" or LaunchArgs.get_flag("bot", false)
			or LaunchArgs.get_flag("autoplay", false) or LaunchArgs.has("net"))
	if persistent:
		_load()
	_apply_all()


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func get_float(key: StringName) -> float:
	return float(get_value(key))


func get_bool(key: StringName) -> bool:
	return bool(get_value(key))


func set_value(key: StringName, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown setting '%s'." % key)
		return
	if RANGES.has(key):
		var range_def: Array = RANGES[key]
		value = clampf(snappedf(float(value), float(range_def[2])), float(range_def[0]), float(range_def[1]))
	elif CHOICES.has(key):
		value = str(value)
		if not CHOICES[key].has(value):
			value = DEFAULTS[key]
	elif key == &"player_name":
		value = clean_name(str(value))
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply(key)
	_save()
	changed.emit(key)


## The name on the board and in the lobby: trimmed, at most NAME_MAX characters, never empty.
func player_name() -> String:
	var name: String = str(get_value(&"player_name"))
	return name if name != "" else NAME_FALLBACK


## True until the player has chosen a name (the menu asks once, on the first start).
func needs_name() -> bool:
	return persistent and str(get_value(&"player_name")) == ""


static func clean_name(raw: String) -> String:
	var name: String = ""
	for c: String in raw.strip_edges():
		# Letters, digits, space and a few marks; no control characters or markup.
		if c.unicode_at(0) >= 32 and not "<>[]{}\\\"".contains(c):
			name += c
	name = name.strip_edges()
	while name.contains("  "):
		name = name.replace("  ", " ")
	return name.left(NAME_MAX)


func reset_defaults() -> void:
	var name: Variant = _values.get(&"player_name", "")
	_values = DEFAULTS.duplicate()
	_values[&"player_name"] = name
	_apply_all()
	_save()
	for key: StringName in DEFAULTS:
		changed.emit(key)


func _apply_all() -> void:
	for key: StringName in DEFAULTS:
		_apply(key)


func _apply(key: StringName) -> void:
	if BUSES.has(key) or key == &"mute":
		for setting: StringName in BUSES:
			var bus: int = AudioServer.get_bus_index(BUSES[setting])
			if bus < 0:
				continue
			var level: float = get_float(setting)
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(level, 0.0001)))
			AudioServer.set_bus_mute(bus, level <= 0.001 or (setting == &"volume_master" and get_bool(&"mute")))
	elif key == &"fullscreen":
		# Only from a click in the browser (fullscreen needs a user gesture), never at startup there.
		if DisplayServer.get_name() == "headless" or (OS.has_feature("web") and not is_node_ready()):
			return
		var full: bool = get_bool(&"fullscreen")
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	elif key == &"antialiasing":
		get_tree().root.msaa_3d = MSAA_ON if get_bool(&"antialiasing") else Viewport.MSAA_DISABLED
	elif key == &"language":
		TranslationServer.set_locale(str(get_value(&"language")))


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key: StringName in DEFAULTS:
		if file.has_section_key(SECTION, key):
			var value: Variant = file.get_value(SECTION, key)
			if typeof(value) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and value is int):
				_values[key] = value
	_values[&"player_name"] = clean_name(str(_values[&"player_name"]))
	for key: StringName in CHOICES:
		if not CHOICES[key].has(str(_values[key])):
			_values[key] = DEFAULTS[key]


func _save() -> void:
	if not persistent:
		return
	var file := ConfigFile.new()
	for key: StringName in _values:
		file.set_value(SECTION, key, _values[key])
	if file.save(PATH) != OK:
		push_warning("Could not save the settings.")
