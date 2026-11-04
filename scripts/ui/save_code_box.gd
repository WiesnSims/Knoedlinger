class_name SaveCodeBox
extends VBoxContainer
## The save as a code (CLAUDE.md: save data must be exportable and importable as a code): copy the
## Profile's export code to the clipboard, paste one to load it, or start over (asks twice). Part of
## the Einstellungen panel.

var _code: LineEdit
var _status: Label
var _reset: ActionPill
var _reset_armed: bool = false


func _init() -> void:
	theme_type_variation = &"Gap16"
	add_child(UiStyle.label(&"LabelAccent", tr("SAVE_TITLE")))
	var line: Label = UiStyle.label(&"LabelMuted", tr("SAVE_LINE"))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(736.0, 0.0)
	add_child(line)
	_code = LineEdit.new()
	_code.placeholder_text = tr("SAVE_PLACEHOLDER")
	_code.custom_minimum_size = Vector2(736.0, 40.0)
	add_child(_code)
	var buttons := UiStyle.hbox(&"Row16")
	add_child(buttons)
	var copy := ActionPill.new()
	copy.set_label(tr("SAVE_COPY"))
	copy.pressed.connect(_copy)
	buttons.add_child(copy)
	var load_code := ActionPill.new()
	load_code.set_label(tr("SAVE_LOAD"))
	load_code.pressed.connect(_load)
	buttons.add_child(load_code)
	_reset = ActionPill.new()
	_reset.set_label(tr("SAVE_RESET"))
	_reset.pressed.connect(_on_reset)
	buttons.add_child(_reset)
	_status = UiStyle.label(&"LabelChange", "")
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(_status)


func refresh() -> void:
	_code.text = Profile.export_code()
	_status.text = ""
	_reset_armed = false
	_reset.set_label(tr("SAVE_RESET"))


func _copy() -> void:
	_code.text = Profile.export_code()
	DisplayServer.clipboard_set(_code.text)
	_code.select_all()
	_status.text = tr("SAVE_COPIED")
	GameAudio.play(&"card")


func _load() -> void:
	var problem: String = Profile.import_code(_code.text)
	_status.text = tr("SAVE_LOADED") if problem == "" else tr("SAVE_BAD_" + problem)
	GameAudio.play(&"card" if problem == "" else &"no_gold")


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset.set_label(tr("SAVE_RESET_SURE"))
		return
	Profile.reset()
	refresh()
	_status.text = tr("SAVE_RESET_DONE")
