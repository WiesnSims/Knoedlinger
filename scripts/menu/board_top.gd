class_name BoardTop
extends PanelContainer
## 1.3.2: the top of die Ehrentafel on the title screen (bottom right, while no screen is open), so
## every player sees it first: the best SIZE solo runs of all time on the first map (the Kirtag). A
## pill opens the whole board. Hidden when the board cannot be reached (desktop, offline).

signal open_pressed

const SIZE: int = 5
const MODE: String = "solo"
const PERIOD: String = "all"
const COLUMNS: Array = [32.0, 144.0, 168.0, 56.0]

var content: GameContent
var _map: StringName
var _grid: GridContainer
var _status: Label
var _ok: bool = false
var _held: bool = false


func _init(p_content: GameContent) -> void:
	content = p_content
	_map = content.maps[0].id
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var head := UiStyle.vbox(&"Tight")
	column.add_child(head)
	head.add_child(UiStyle.label(&"LabelAccent", tr("BOARD_TOP_TITLE")))
	head.add_child(UiStyle.label(&"LabelMuted", tr("BOARD_TOP_LINE") % [SIZE, tr(content.maps[0].name_key)]))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_grid)
	_status = UiStyle.label(&"LabelMuted", "")
	column.add_child(_status)
	var open := ActionPill.new()
	open.set_label(tr("BOARD_TOP_OPEN"))
	open.pressed.connect(func() -> void: open_pressed.emit())
	column.add_child(open)
	Board.listed.connect(_on_listed)


func fetch() -> void:
	Board.fetch(MODE, String(_map), PERIOD)


func _on_listed(mode: String, map: String, period: String, entries: Array, ok: bool) -> void:
	if mode != MODE or map != String(_map) or period != PERIOD:
		return
	_ok = ok
	visible = _ok and not _held
	_status.text = tr("BOARD_EMPTY") if entries.is_empty() else ""
	_status.visible = entries.is_empty()
	_grid.visible = not entries.is_empty()
	for child: Node in _grid.get_children():
		child.queue_free()
	for k: int in mini(entries.size(), SIZE):
		var entry: Dictionary = entries[k]
		var variation: StringName = &"LabelAccent" if Board.is_mine(int(entry.get("id", 0))) else &"LabelSmall"
		var grant: int = clampi(int(entry.get("grant", 1)), 0, content.grants.size() - 1)
		var time: int = int(entry.get("time", 0))
		var cells: Array = [
			str(k + 1), ", ".join(PackedStringArray(entry.get("names", []))),
			"%s · %s" % [tr("BOARD_RESULT_%d" % clampi(int(entry.get("result", 0)), 0, 2)), tr(content.grants[grant].name_key)],
			"%d:%02d" % [time / 60, time % 60],
		]
		for c: int in cells.size():
			var label: Label = UiStyle.label(variation if c > 0 else &"LabelMuted", cells[c])
			label.custom_minimum_size = Vector2(COLUMNS[c], 0.0)
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_grid.add_child(label)


## Hidden while a menu screen is open (it would sit under it), back when it closes.
func hold(on: bool) -> void:
	_held = on
	visible = _ok and not _held
