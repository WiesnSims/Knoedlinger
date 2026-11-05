class_name RecordsScreen
extends PanelContainer
## "Ehrentafel": the online board first (`board`, the first tab and the default since 1.3.2), then
## the player's own best runs per map, one row per Knödlinger (longest time, wins and highest Grant
## won, highest level, most kills, biggest Knödl, most Schilling from one run).

signal closed

const COLUMNS: Array = [
	["time", "REC_TIME"], ["wins", "REC_WINS"], ["level", "REC_LEVEL"], ["kills", "REC_KILLS"],
	["knodl", "REC_KNODL"], ["schilling", "REC_SCHILLING"],
]
const NAME_WIDTH: float = 168.0
const VALUE_WIDTH: float = 88.0

var content: GameContent
var _body: VBoxContainer
var _tabs: HBoxContainer
var _own_pill: ActionPill
var _board_pill: ActionPill
## The online Ehrentafel, the first tab.
var board: BoardPanel


func _init(p_content: GameContent) -> void:
	content = p_content
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UiStyle.vbox(&"Gap16")
	add_child(column)
	var header: PanelContainer = UiStyle.panel(&"PanelHeader")
	column.add_child(header)
	header.add_child(UiStyle.label(&"LabelTitle", tr("RECORDS_TITLE")))
	_tabs = UiStyle.hbox()
	column.add_child(_tabs)
	_board_pill = ActionPill.new("", &"shoulder_left")
	_board_pill.set_label(tr("RECORDS_BOARD"))
	_board_pill.toggle_mode = true
	_board_pill.pressed.connect(func() -> void: _show_board(true))
	_tabs.add_child(_board_pill)
	_own_pill = ActionPill.new("", &"shoulder_right")
	_own_pill.set_label(tr("RECORDS_OWN"))
	_own_pill.toggle_mode = true
	_own_pill.pressed.connect(func() -> void: _show_board(false))
	_tabs.add_child(_own_pill)
	_body = UiStyle.vbox(&"Gap24")
	column.add_child(_body)
	board = BoardPanel.new(content)
	column.add_child(board)
	var back := ActionPill.new("Esc", &"ui_cancel")
	back.set_label(tr("MENU_BACK"))
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func refresh() -> void:
	_show_board(true)
	for child: Node in _body.get_children():
		child.queue_free()
	for info: MapInfo in content.maps:
		var block := UiStyle.vbox()
		_body.add_child(block)
		block.add_child(UiStyle.label(&"LabelAccent", tr(info.name_key)))
		var grid := GridContainer.new()
		grid.columns = COLUMNS.size() + 1
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(grid)
		grid.add_child(_cell("", NAME_WIDTH, &"LabelMuted"))
		for def: Array in COLUMNS:
			grid.add_child(_cell(tr(def[1]), VALUE_WIDTH, &"LabelMuted"))
		var any: bool = false
		for character: CharacterData in content.characters:
			var record: Dictionary = Profile.record(character.id, info.id)
			if record.is_empty():
				continue
			any = true
			grid.add_child(_cell(tr(character.name_key), NAME_WIDTH, &"LabelSmall"))
			for def: Array in COLUMNS:
				grid.add_child(_cell(value_text(def[0], record), VALUE_WIDTH, &"LabelSmall"))
		if not any:
			grid.visible = false
			block.add_child(UiStyle.label(&"LabelMuted", tr("RECORDS_NONE")))


func focus_first() -> void:
	pass


## Left / Right (LB / RB on the pad) switch between the Ehrentafel and the own records.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_RIGHT):
		get_viewport().set_input_as_handled()
		_show_board(key.physical_keycode == KEY_LEFT)
	elif event.is_action_pressed(&"shoulder_left") or event.is_action_pressed(&"shoulder_right"):
		get_viewport().set_input_as_handled()
		_show_board(event.is_action_pressed(&"shoulder_left"))


func _show_board(on: bool) -> void:
	_own_pill.set_pressed_no_signal(not on)
	_board_pill.set_pressed_no_signal(on)
	_body.visible = not on
	board.visible = on
	if on:
		board.fetch()


static func value_text(key: String, record: Dictionary) -> String:
	var value: float = float(record.get(key, 0))
	match key:
		"time":
			return "%d:%02d" % [floori(value / 60.0), int(value) % 60]
		"wins":
			var grant: int = int(record.get("grant", -1))
			if value <= 0.0:
				return "0"
			var content: GameContent = GameContent.load_default()
			return "%d · %s" % [roundi(value), TranslationServer.translate(content.grants[clampi(grant, 0, content.grants.size() - 1)].name_key)]
	return str(roundi(value))


func _cell(text: String, width: float, variation: StringName) -> Label:
	var label: Label = UiStyle.label(variation, text)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label
