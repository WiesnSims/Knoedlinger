extends Node3D
## The title screen (docs/DECISIONS.md, M4 plan): the Kirtag of Unterhinterkogl slowly turning
## behind the menu, the logo and the entries on the left, the chosen screen on the right. Entries:
## Spielen, Tageskarte (the daily run, 1.4), Stammtisch, Aufträge, Ehrentafel, Almanach, Einstellungen, "Was is neu?" (the patch list)
## and "Stammtisch aufmachen" (co-op: the CoopScreen room). On the very first start it asks for the player's name.
## While no screen is open, the top of die Ehrentafel sits bottom right (BoardTop, 1.3.2).

const BACKDROP_MAP: String = "res://data/maps/kirtag.tres"
const RUN_SCENE: String = "res://scenes/run/run_world.tscn"
## The camera circles the Knödl stand: radius, height above it, radians per second.
const ORBIT_RADIUS: float = 26.0
const ORBIT_HEIGHT: float = 9.0
const ORBIT_SPEED: float = 0.05
const LEFT_WIDTH: float = 320.0
const MARGIN: float = 64.0
## Below this UI height the left column keeps only half the margin above and below and half the gaps,
## so its nine entries and the footer still fit (1280x720).
const SHORT_HEIGHT: float = 820.0
## [label key, screen id, enabled].
const ENTRIES: Array = [
	["MENU_PLAY", &"play", true],
	["MENU_DAILY", &"daily", true],
	["MENU_STAMMTISCH", &"stammtisch", true],
	["MENU_QUESTS", &"quests", true],
	["MENU_RECORDS", &"records", true],
	["MENU_ALMANACH", &"almanach", true],
	["MENU_SETTINGS", &"settings", true],
	["MENU_PATCHES", &"patches", true],
	["MENU_COOP", &"coop", true],
]

var content: GameContent
var _camera: Camera3D
var _centre: Vector3 = Vector3.ZERO
var _angle: float = 0.6
var _entries: Array[Button] = []
var _screens: Dictionary[StringName, Control] = {}
var _current: StringName = &""
var _name_label: Label
var _schilling_label: Label
var _name_prompt: PanelContainer
var _name_edit: LineEdit
var _left: Control
var _area: CenterContainer
var _starting: bool = false
var _board_top: BoardTop


func _ready() -> void:
	InputSetup.ensure_actions()
	get_tree().paused = false
	content = GameContent.load_default()
	_build_backdrop()
	_build_ui()
	GameAudio.music(&"kirtag")
	GameAudio.set_music_speed(0.94)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Settings.needs_name():
		_show_name_prompt()
	elif Lobby.is_active() or LaunchArgs.has("room") or LaunchArgs.has("coop"):
		# Back from a co-op run, or opened with an invite link: straight to the room.
		_open(&"coop")
	else:
		_entries[0].grab_focus()
	print("[MENU] ready")
	WebPage.loaded()


func _process(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_camera.global_position = _centre + Vector3(cos(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_angle) * ORBIT_RADIUS)
	_camera.look_at(_centre + Vector3(0.0, 2.5, 0.0))


func _build_backdrop() -> void:
	var map: MapData = load(BACKDROP_MAP)
	var terrain: Heightfield = Heightfield.bake_terrain(map)
	MapBuilder.build(map, terrain, self)
	# The chosen quality already shows on the title screen (Automatisch measures here too).
	var quality := QualityScaler.new()
	add_child(quality)
	quality.setup(load("res://data/balance.tres"), get_node_or_null(^"Sun") as DirectionalLight3D)
	_centre = map.spawn_point
	_centre.y = terrain.height_at(_centre.x, _centre.z)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root: Control = UiStyle.root(layer)
	# A soft dark band behind the left column keeps the logo readable over the bright Kirtag.
	var band := ColorRect.new()
	band.color = Color(UiStyle.color("panel"), 0.55)
	band.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	band.offset_right = LEFT_WIDTH + MARGIN * 2.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	_left = UiStyle.vbox(&"Gap32")
	_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_left.offset_left = MARGIN
	_left.offset_top = MARGIN
	_left.offset_bottom = -MARGIN
	_left.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	root.add_child(_left)
	root.resized.connect(func() -> void: _fit_column(root.size.y))
	(func() -> void: _fit_column(root.size.y)).call_deferred()
	_left.add_child(TitleLogo.new(tr("GAME_TITLE"), tr("GAME_SUBTITLE")))
	var list := UiStyle.vbox(&"Gap4")
	_left.add_child(list)
	for def: Array in ENTRIES:
		var entry := Button.new()
		entry.theme_type_variation = &"MenuEntry"
		entry.text = tr(def[0])
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.custom_minimum_size = Vector2(LEFT_WIDTH, 40.0)
		entry.disabled = not def[2]
		if not def[2]:
			entry.tooltip_text = tr("MENU_SOON")
			entry.focus_mode = Control.FOCUS_NONE
		var id: StringName = def[1]
		entry.pressed.connect(func() -> void: _open(id))
		entry.mouse_entered.connect(func() -> void:
			if not entry.disabled:
				GameAudio.play(&"ui_hover"))
		entry.focus_entered.connect(func() -> void: GameAudio.play(&"ui_hover"))
		list.add_child(entry)
		_entries.append(entry)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(spacer)
	var footer := UiStyle.vbox(&"Tight")
	_left.add_child(footer)
	_name_label = UiStyle.label(&"LabelSmall")
	footer.add_child(_name_label)
	_schilling_label = UiStyle.label(&"LabelAccent")
	footer.add_child(_schilling_label)
	Profile.changed.connect(_update_name)
	footer.add_child(UiStyle.label(&"LabelMuted", tr("MENU_VERSION") % NetworkManager.version))
	_update_name()
	Settings.changed.connect(func(key: StringName) -> void:
		if key == &"player_name":
			_update_name())
	# The screens, right of the column, centred in the free space.
	var area := CenterContainer.new()
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.offset_left = LEFT_WIDTH + MARGIN * 2.0
	area.offset_right = -MARGIN * 0.5
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(area)
	_area = area
	var play := PlayScreen.new(content)
	play.start_pressed.connect(_start_run)
	play.closed.connect(_close_screen)
	_screens[&"play"] = play
	var daily := DailyScreen.new(content)
	daily.start_pressed.connect(func() -> void: _start_daily(daily.day()))
	daily.closed.connect(_close_screen)
	_screens[&"daily"] = daily
	var settings := SettingsPanel.new()
	settings.closed.connect(_close_screen)
	_screens[&"settings"] = settings
	var coop := CoopScreen.new(content)
	coop.closed.connect(_close_screen)
	_screens[&"coop"] = coop
	var patches := PatchNotesScreen.new()
	patches.closed.connect(_close_screen)
	_screens[&"patches"] = patches
	for id: StringName in [&"stammtisch", &"quests", &"records", &"almanach"]:
		var screen: Control
		match id:
			&"stammtisch":
				screen = StammtischScreen.new(content)
			&"quests":
				screen = QuestsScreen.new(content)
			&"records":
				screen = RecordsScreen.new(content)
			&"almanach":
				screen = AlmanachScreen.new(content)
		screen.connect(&"closed", _close_screen)
		_screens[id] = screen
	for id: StringName in _screens:
		_screens[id].visible = false
		area.add_child(_screens[id])
	_board_top = BoardTop.new(content)
	_board_top.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_board_top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board_top.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_board_top.offset_right = -MARGIN
	_board_top.offset_bottom = -MARGIN
	_board_top.open_pressed.connect(func() -> void: _open(&"records"))
	root.add_child(_board_top)
	_board_top.fetch()
	_build_name_prompt(root)


func _fit_column(height: float) -> void:
	var short: bool = height < SHORT_HEIGHT
	_left.offset_top = MARGIN * 0.5 if short else MARGIN
	_left.offset_bottom = -_left.offset_top
	_left.theme_type_variation = &"Gap16" if short else &"Gap32"


func _update_name() -> void:
	_name_label.text = tr("MENU_PLAYER") % Settings.player_name()
	_schilling_label.text = tr("MENU_SCHILLING") % Profile.schilling()


func _open(id: StringName) -> void:
	if not _screens.has(id) or _starting:
		return
	GameAudio.play(&"card")
	for key: StringName in _screens:
		_screens[key].visible = key == id
	_current = id
	_board_top.hold(true)
	var screen: Control = _screens[id]
	if screen.has_method(&"refresh"):
		screen.call(&"refresh")
	if screen.has_method(&"focus_first"):
		screen.call_deferred(&"focus_first")
	# Fade and rise 16 px: the centre container itself moves, so it keeps laying the screen out.
	screen.modulate.a = 0.0
	_area.offset_top = 16.0
	_area.offset_bottom = 16.0
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "modulate:a", 1.0, UiStyle.T_PANEL_IN)
	tween.tween_property(_area, "offset_top", 0.0, UiStyle.T_PANEL_IN)
	tween.tween_property(_area, "offset_bottom", 0.0, UiStyle.T_PANEL_IN)


func _close_screen() -> void:
	if _current == &"":
		return
	var index: int = ENTRIES.map(func(def: Array) -> StringName: return def[1]).find(_current)
	_screens[_current].visible = false
	_current = &""
	_board_top.hold(false)
	if index >= 0:
		_entries[index].grab_focus()


func _start_run(character: StringName, map: StringName, grant: int) -> void:
	if _starting:
		return
	_starting = true
	# A solo run leaves any co-op room.
	if Lobby.is_active():
		Lobby.leave()
	RunSetup.character = String(character)
	RunSetup.map = String(map)
	RunSetup.grant = grant
	RunSetup.seed = -1
	RunSetup.daily = ""
	RunSetup.from_room = false
	Profile.remember_choice(character, map, grant)
	_go_to_run()


## Die Tageskarte: today's card, solo; only the day's first try goes onto its board.
func _start_daily(day: String) -> void:
	if _starting:
		return
	_starting = true
	if Lobby.is_active():
		Lobby.leave()
	RunSetup.use_daily(content, load("res://data/balance.tres"), day)
	RunSetup.daily_counts = Profile.start_daily(day)
	_go_to_run()


func _go_to_run() -> void:
	RunSetup.from_menu = true
	GameAudio.set_music_speed(1.0)
	# The loading screen first: building the map takes a moment, and the run shows the same screen
	# while the browser builds its shaders.
	add_child(LoadingScreen.new())
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


func _build_name_prompt(root: Control) -> void:
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.color("panel"), 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	_name_prompt = UiStyle.panel()
	_name_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStyle.centred(shade).add_child(_name_prompt)
	var column := UiStyle.vbox(&"Gap16")
	_name_prompt.add_child(column)
	column.add_child(UiStyle.label(&"LabelTitle", tr("NAME_TITLE")))
	var line: Label = UiStyle.label(&"LabelMuted", tr("NAME_LINE"))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(400.0, 0.0)
	column.add_child(line)
	_name_edit = LineEdit.new()
	_name_edit.max_length = Settings.NAME_MAX
	_name_edit.placeholder_text = Settings.NAME_FALLBACK
	_name_edit.text_submitted.connect(func(_t: String) -> void: _confirm_name())
	column.add_child(_name_edit)
	var ok := ActionPill.new("Enter", &"ui_accept")
	ok.set_label(tr("NAME_OK"))
	ok.pressed.connect(_confirm_name)
	column.add_child(ok)
	_name_prompt.set_meta(&"shade", shade)
	shade.visible = false


func _show_name_prompt() -> void:
	(_name_prompt.get_meta(&"shade") as Control).visible = true
	_name_edit.grab_focus.call_deferred()


func _confirm_name() -> void:
	var chosen: String = Settings.clean_name(_name_edit.text)
	Settings.set_value(&"player_name", chosen if chosen != "" else Settings.NAME_FALLBACK)
	(_name_prompt.get_meta(&"shade") as Control).visible = false
	GameAudio.play(&"card")
	if LaunchArgs.has("room") or LaunchArgs.has("coop"):
		_open(&"coop")
	else:
		_entries[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# The pad cannot type: A takes the name as it stands (or the fallback).
	if (_name_prompt.get_meta(&"shade") as Control).visible:
		if event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept"):
			get_viewport().set_input_as_handled()
			_confirm_name()
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		if _current != &"":
			get_viewport().set_input_as_handled()
			_close_screen()
