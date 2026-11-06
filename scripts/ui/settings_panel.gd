class_name SettingsPanel
extends PanelContainer
## Einstellungen, from the main menu and from the pause menu, in three tabs (Ton & Bild, Steuerung,
## Spiel) of two columns each; Q / E or LB / RB switch the tab. Every change goes straight to Settings (applied and saved at once).
## "Zurück" (Esc) emits `closed`; "Standard" resets everything but the name.

signal closed

const COLUMN_WIDTH: float = 368.0
const LABEL_WIDTH: float = 160.0
## Every tab is at least this tall, so the panel keeps its size when the tab changes.
const PAGE_HEIGHT: float = 248.0
const VALUE_WIDTH: float = 56.0
## Tabs: [tab title key, left column, right column]; a column is groups of [group title key, rows],
## a row is [setting, label key, how to show the value].
const TABS: Array = [
	["SET_TAB_PICTURE", [
		["SET_GROUP_SOUND", [
			[&"volume_master", "SET_VOLUME_MASTER", "percent"], [&"volume_music", "SET_VOLUME_MUSIC", "percent"],
			[&"volume_sfx", "SET_VOLUME_SFX", "percent"], [&"volume_voice", "SET_VOLUME_VOICE", "percent"],
			[&"mute", "SET_MUTE", "toggle"],
		]],
	], [
		["SET_GROUP_DISPLAY", [
			[&"fullscreen", "SET_FULLSCREEN", "toggle"], [&"quality", "SET_QUALITY", "choice"],
			[&"antialiasing", "SET_ANTIALIASING", "toggle"], [&"reduce_flashing", "SET_REDUCE_FLASHING", "toggle"],
			[&"screen_wobble", "SET_SCREEN_WOBBLE", "toggle"],
		]],
	]],
	["SET_TAB_CONTROLS", [
		["SET_GROUP_CAMERA", [
			[&"camera_distance", "SET_CAMERA_DISTANCE", "metres"], [&"camera_fov", "SET_CAMERA_FOV", "degrees"],
			[&"mouse_sensitivity", "SET_MOUSE_SENSITIVITY", "times"], [&"look_smoothing", "SET_LOOK_SMOOTHING", "ms"],
			[&"invert_y", "SET_INVERT_Y", "toggle"],
		]],
	], [
		["SET_GROUP_PAD", [
			[&"pad_look_speed", "SET_PAD_LOOK_SPEED", "times"],
		]],
		["SET_GROUP_TOUCH", [
			[&"touch_controls", "SET_TOUCH_CONTROLS", "choice"], [&"touch_size", "SET_TOUCH_SIZE", "percent"],
			[&"touch_opacity", "SET_TOUCH_OPACITY", "percent"],
		]],
	]],
	["SET_TAB_GAME", [
		["SET_GROUP_GAME", [
			[&"player_name", "SET_PLAYER_NAME", "name"], [&"glossary", "SET_GLOSSARY", "toggle"],
			[&"knodl_follow", "SET_KNODL_FOLLOW", "toggle"],
			[&"enemy_chatter", "SET_ENEMY_CHATTER", "toggle"], [&"board", "SET_BOARD", "toggle"], [&"language", "SET_LANGUAGE", "language"],
		]],
	], []],
]

var _sliders: Dictionary[StringName, UiSlider] = {}
var _values: Dictionary[StringName, Label] = {}
var _toggles: Dictionary[StringName, UiToggle] = {}
var _choices: Dictionary[StringName, UiChoice] = {}
var _formats: Dictionary[StringName, String] = {}
var _name: LineEdit
var _save: SaveCodeBox
var _pages: Array[HBoxContainer] = []
var _tab_pills: Array[ActionPill] = []
## The first control of each tab, for the focus.
var _firsts: Array[Control] = []
var _tab: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap24")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var header_row := UiStyle.hbox(&"Row32")
	header.add_child(header_row)
	var title: Label = UiStyle.label(&"LabelTitle", tr("SET_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	var tabs := UiStyle.hbox()
	tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(tabs)
	# [Q]  Ton & Bild  Steuerung  Spiel  [E]: the keys step through the tabs.
	var prev := KeycapLabel.new(&"shoulder_left", "Q")
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(prev)
	for t: int in TABS.size():
		var pill := ActionPill.new()
		pill.toggle_mode = true
		pill.set_label(tr(TABS[t][0]))
		pill.pressed.connect(_show_tab.bind(t))
		tabs.add_child(pill)
		_tab_pills.append(pill)
		var page := UiStyle.hbox(&"Row32")
		column.add_child(page)
		page.custom_minimum_size = Vector2(0.0, PAGE_HEIGHT)
		_pages.append(page)
		_firsts.append(null)
		for groups: Array in [TABS[t][1], TABS[t][2]]:
			var side := UiStyle.vbox(&"Gap24")
			side.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
			page.add_child(side)
			for group: Array in groups:
				var block := UiStyle.vbox()
				side.add_child(block)
				block.add_child(UiStyle.label(&"LabelAccent", tr(group[0])))
				for def: Array in group[1]:
					block.add_child(_row(def[0], def[1], def[2], t))
	var next := KeycapLabel.new(&"shoulder_right", "E")
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(next)
	var buttons := UiStyle.hbox(&"Row16")
	column.add_child(buttons)
	var back := ActionPill.new("Esc", &"ui_cancel")
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
	column.move_child(_save, 1)
	var save := ActionPill.new()
	save.set_label(tr("SAVE_TITLE"))
	save.toggle_mode = true
	save.toggled.connect(func(on: bool) -> void:
		_save.visible = on
		for t: int in _pages.size():
			_pages[t].visible = not on and t == _tab
		if on:
			_save.refresh())
	buttons.add_child(save)
	_show_tab(0)
	refresh()


func _show_tab(t: int) -> void:
	_tab = posmod(t, _pages.size())
	for k: int in _pages.size():
		_pages[k].visible = k == _tab and not _save.visible
		_tab_pills[k].set_pressed_no_signal(k == _tab)
	if is_visible_in_tree():
		focus_first()


## Q / E (LB / RB on the pad) switch the tabs; typing in the name field never does.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	var step: int = 0
	if key != null and key.pressed and not key.echo and (key.physical_keycode == KEY_Q or key.physical_keycode == KEY_E):
		step = -1 if key.physical_keycode == KEY_Q else 1
	elif event.is_action_pressed(&"shoulder_left"):
		step = -1
	elif event.is_action_pressed(&"shoulder_right"):
		step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		GameAudio.play(&"ui_hover")
		_show_tab(_tab + step)


## Puts the current settings into the controls (on open, after a reset).
func refresh() -> void:
	for key: StringName in _sliders:
		_sliders[key].set_value_no_signal(Settings.get_float(key))
		_sliders[key].queue_redraw()
		_values[key].text = _format(key, Settings.get_float(key))
	for key: StringName in _toggles:
		_toggles[key].set_on(Settings.get_bool(key))
	for key: StringName in _choices:
		_choices[key].set_index_no_signal(Settings.CHOICES[key].find(str(Settings.get_value(key))))
	if _name != null:
		_name.text = str(Settings.get_value(&"player_name"))


func focus_first() -> void:
	if _firsts[_tab] != null:
		_firsts[_tab].grab_focus()


func _row(key: StringName, label_key: String, format: String, tab: int) -> Control:
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
		"choice":
			var choice := UiChoice.new()
			choice.custom_minimum_size.x = COLUMN_WIDTH - LABEL_WIDTH - 16.0
			choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var names := PackedStringArray()
			for value: String in Settings.CHOICES[key]:
				names.append(tr("SET_%s_%s" % [String(key).to_upper(), value.to_upper()]))
			choice.names = names
			choice.chosen.connect(func(k: int) -> void: Settings.set_value(key, Settings.CHOICES[key][k]))
			_choices[key] = choice
			control = choice
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
			if _firsts[tab] == null:
				_firsts[tab] = slider
			return row
	# Not the name field: Q / E would type into it instead of switching the tab.
	if _firsts[tab] == null and control.focus_mode != Control.FOCUS_NONE and not control is LineEdit:
		_firsts[tab] = control
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
