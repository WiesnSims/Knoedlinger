class_name PatchNotesScreen
extends PanelContainer
## "Was is neu?": what changed in which release, newest on top (data/patch_notes/patch_notes.tres).
## Each release is a raised panel with its version and date, then one line per change.

signal closed

const WIDTH: float = 736.0
const LIST_HEIGHT: float = 416.0

var _list: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	var title_row := UiStyle.hbox()
	header.add_child(title_row)
	var title: Label = UiStyle.label(&"LabelTitle", tr("PATCHES_TITLE"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var current: Label = UiStyle.label(&"LabelNumber", NetworkManager.version)
	current.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(current)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(_scroll)
	_list = UiStyle.vbox()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	for note: PatchNote in PatchNotes.load_default().notes:
		_list.add_child(_release(note))
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func refresh() -> void:
	_scroll.scroll_vertical = 0


func focus_first() -> void:
	_scroll.grab_focus()


func _release(note: PatchNote) -> Control:
	var panel: PanelContainer = UiStyle.panel(&"PanelRaised")
	var text := UiStyle.vbox(&"Tight")
	panel.add_child(text)
	var head := UiStyle.hbox()
	text.add_child(head)
	var version: Label = UiStyle.label(&"LabelAccent", tr("PATCHES_VERSION") % note.version)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(version)
	head.add_child(UiStyle.label(&"LabelMuted", note.date))
	for key: String in note.line_keys:
		var line: Label = UiStyle.label(&"", "• " + tr(key))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(WIDTH - 48.0, 0.0)
		text.add_child(line)
	return panel
