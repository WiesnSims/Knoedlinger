class_name PauseMenu
extends CanvasLayer
## Esc in a run: "Kurz Pause" with Weiter (Esc), Einstellungen and Zum Menü. RunWorld pauses solo
## games while it is open (`toggled`); co-op runs on, like the Speisekarte. Zum Menü ends the run
## (`quit_pressed`).

signal toggled(open: bool)
signal quit_pressed

const WIDTH: float = 320.0

var _shown: Control
var _menu: PanelContainer
var _settings: SettingsPanel
var _entries: Array[Button] = []
## RunWorld turns it off while another full-screen panel is up or the run is over.
var allowed: bool = true


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = UiStyle.root(self)
	_shown = Control.new()
	_shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shown)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.color("panel"), 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown.add_child(shade)
	var centre: CenterContainer = UiStyle.centred(_shown)
	_menu = UiStyle.panel()
	_menu.custom_minimum_size = Vector2(WIDTH, 0.0)
	centre.add_child(_menu)
	var column := UiStyle.vbox(&"Gap16")
	_menu.add_child(column)
	column.add_child(UiStyle.label(&"LabelTitle", tr("PAUSE_TITLE")))
	var list := UiStyle.vbox(&"Gap4")
	column.add_child(list)
	for def: Array in [["PAUSE_RESUME", _resume], ["MENU_SETTINGS", _open_settings], ["PAUSE_QUIT", _quit]]:
		var entry := Button.new()
		entry.theme_type_variation = &"MenuEntry"
		entry.text = tr(def[0])
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.custom_minimum_size = Vector2(WIDTH - 32.0, 40.0)
		entry.pressed.connect(def[1])
		entry.focus_entered.connect(func() -> void: GameAudio.play(&"ui_hover"))
		list.add_child(entry)
		_entries.append(entry)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	centre.add_child(_settings)
	_shown.visible = false


func is_open() -> bool:
	return _shown.visible


func set_open(on: bool) -> void:
	if on == is_open() or (on and not allowed):
		return
	_shown.visible = on
	_settings.visible = false
	_menu.visible = true
	if on:
		_shown.modulate.a = 0.0
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
				.tween_property(_shown, "modulate:a", 1.0, UiStyle.T_PANEL_IN)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		GameAudio.play(&"menu_open")
		_entries[0].grab_focus.call_deferred()
	toggled.emit(on)


func _resume() -> void:
	set_open(false)


func _open_settings() -> void:
	_menu.visible = false
	_settings.refresh()
	_settings.visible = true
	_settings.focus_first.call_deferred()


func _close_settings() -> void:
	_settings.visible = false
	_menu.visible = true
	_entries[1].grab_focus.call_deferred()


func _quit() -> void:
	set_open(false)
	quit_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Another panel (Tab screen) takes its own Esc.
	if not event.is_action_pressed(&"pause") or (not is_open() and not allowed):
		return
	get_viewport().set_input_as_handled()
	if _settings.visible:
		_close_settings()
	else:
		set_open(not is_open())
