class_name SettingsPanel
extends PanelContainer
## Einstellungen, from the main menu and from the pause menu: sound, display, camera and game
## settings in two columns. Every change goes straight to Settings (applied and saved at once).
## "Zurück" (Esc) emits `closed`; "Standard" resets everything but the name.

signal closed

const COLUMN_WIDTH: float = 352.0
const LABEL_WIDTH: float = 136.0
const VALUE_WIDTH: float = 56.0
## Group title key, then rows: [setting, label key, how to show the value].
const LEFT: Array = [
	["SET_GROUP_SOUND", [
		[&"volume_master", "SET_VOLUME_MASTER", "percent"], [&"volume_music", "SET_VOLUME_MUSIC", "percent"],
		[&"volume_sfx", "SET_VOLUME_SFX", "percent"], [&"volume_voice", "SET_VOLUME_VOICE", "percent"],
		[&"mute", "SET_MUTE", "toggle"],
	]],
	["SET_GROUP_DISPLAY", [
		[&"fullscreen", "SET_FULLSCREEN", "toggle"], [&"reduce_flashing", "SET_REDUCE_FLASHING", "toggle"],
	]],
]
const RIGHT: Array = [
	["SET_GROUP_CAMERA", [
		[&"camera_distance", "SET_CAMERA_DISTANCE", "metres"], [&"camera_fov", "SET_CAMERA_FOV", "degrees"],
		[&"mouse_sensitivity", "SET_MOUSE_SENSITIVITY", "times"], [&"look_smoothing", "SET_LOOK_SMOOTHING", "ms"],
		[&"invert_y", "SET_INVERT_Y", "toggle"],
	]],
	["SET_GROUP_GAME", [
		[&"player_name", "SET_PLAYER_NAME", "name"], [&"glossary", "SET_GLOSSARY", "toggle"],
		[&"language", "SET_LANGUAGE", "language"],
	]],
]

var _sliders: Dictionary[StringName, UiSlider] = {}
var _values: Dictionary[StringName, Label] = {}
var _toggles: Dictionary[StringName, UiToggle] = {}
var _formats: Dictionary[StringName, String] = {}
var _name: LineEdit
var _first: Control
var _save: SaveCodeBox
var _settings_row: HBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap24")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	header.add_child(UiStyle.label(&"LabelTitle", tr("SET_TITLE")))
	var row := UiStyle.hbox(&"Row32")
	column.add_child(row)
	for groups: Array in [LEFT, RIGHT]:
		var side := UiStyle.vbox(&"Gap24")
		side.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
		row.add_child(side)
		for group: Array in groups:
			var block := UiStyle.vbox()
			side.add_child(block)
			block.add_child(UiStyle.label(&"LabelAccent", tr(group[0])))
			for def: Array in group[1]:
				block.add_child(_row(def[0], def[1], def[2]))
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	var back := ActionPill.new("Esc")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)
	var reset := ActionPill.new()
	reset.set_label(tr("SET_RESET"))
	reset.pressed.connect(func() -> void:
		Settings.reset_defaults()
		refresh())
	buttons.add_child(reset)
	# The save as a code, in place of the settings while it is open.
	_save = SaveCodeBox.new()
	_save.visible = false
	column.add_child(_save)
	column.move_child(_save, 2)
	var save := ActionPill.new()
	save.set_label(tr("SAVE_TITLE"))
	save.toggle_mode = true
	save.toggled.connect(func(on: bool) -> void:
		_save.visible = on
		_settings_row.visible = not on
		if on:
			_save.refresh())
	buttons.add_child(save)
	_settings_row = row
	refresh()


## Puts the current settings into the controls (on open, after a reset).
func refresh() -> void:
	for key: StringName in _sliders:
		_sliders[key].set_value_no_signal(Settings.get_float(key))
		_sliders[key].queue_redraw()
		_values[key].text = _format(key, Settings.get_float(key))
	for key: StringName in _toggles:
		_toggles[key].set_on(Settings.get_bool(key))
	if _name != null:
		_name.text = str(Settings.get_value(&"player_name"))


func focus_first() -> void:
	if _first != null:
		_first.grab_focus()


func _row(key: StringName, label_key: String, format: String) -> Control:
	var row := UiStyle.hbox(&"Row16")
	row.custom_minimum_size = Vector2(0.0, 32.0)
	var name: Label = UiStyle.label(&"LabelSmall", tr(label_key))
	name.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	var control: Control
	match format:
		"toggle":
			var toggle := UiToggle.new()
			toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			toggle.toggled.connect(func(on: bool) -> void:
				Settings.set_value(key, on)
				GameAudio.play(&"ui_hover"))
			_toggles[key] = toggle
			control = toggle
		"name":
			_name = LineEdit.new()
			_name.max_length = Settings.NAME_MAX
			_name.placeholder_text = Settings.NAME_FALLBACK
			_name.custom_minimum_size = Vector2(COLUMN_WIDTH - LABEL_WIDTH - 16.0, 40.0)
			_name.text_submitted.connect(func(text: String) -> void:
				Settings.set_value(&"player_name", text)
				_name.release_focus())
			_name.focus_exited.connect(func() -> void: Settings.set_value(&"player_name", _name.text))
			control = _name
		"language":
			# German only for now; the strings already sit in a CSV, so English can follow.
			control = UiStyle.label(&"LabelMuted", tr("SET_LANGUAGE_DE"))
			control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_:
			var range_def: Array = Settings.RANGES[key]
			var slider := UiSlider.new()
			slider.custom_minimum_size.x = COLUMN_WIDTH - LABEL_WIDTH - VALUE_WIDTH - 32.0
			slider.min_value = range_def[0]
			slider.max_value = range_def[1]
			slider.step = range_def[2]
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var shown: Label = UiStyle.label(&"LabelSmall")
			shown.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
			shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value_changed.connect(func(v: float) -> void:
				Settings.set_value(key, v)
				shown.text = _format(key, v))
			_sliders[key] = slider
			_values[key] = shown
			_formats[key] = format
			row.add_child(slider)
			row.add_child(shown)
			if _first == null:
				_first = slider
			return row
	row.add_child(control)
	return row


func _format(key: StringName, v: float) -> String:
	match _formats.get(key, ""):
		"percent":
			return "%d %%" % roundi(v * 100.0)
		"metres":
			return "%.1f m" % v
		"degrees":
			return "%d°" % roundi(v)
		"times":
			return "×%.2f" % v
		"ms":
			return "%d ms" % roundi(v * 1000.0)
	return str(v)
